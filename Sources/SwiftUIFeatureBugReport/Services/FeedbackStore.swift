//
//  FeedbackStore.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation
import Observation

/// The one object a view needs.
///
/// Each service keeps its single responsibility; this holds them together, owns the rules that span
/// more than one of them (visibility, the edit lock), and gives the views a single thing to observe.
@Observable @MainActor public final class FeedbackStore {

    public let container: FeedbackContainer
    public let requests: RequestService
    public let votes: VoteService
    public let follows: FollowService
    public let reports: ReportService
    public let comments: CommentService
    public let activity: ActivityService
    public let moderation: ModerationService
    public let accountData: AccountDataService

    /// Set once permission has been asked for, so it is asked once per session whichever route got
    /// there - a user's first submission, or a developer opening the portal.
    private var hasAskedForNotifications = false

    /// Shared by every public entry view. A configuration-based view owns a fresh store, while
    /// store-based views often appear together; both paths must converge on one startup operation.
    @ObservationIgnored private var startupTask: Task<Void, Never>?

    public convenience init(configuration: FeedbackConfiguration) {

        self.init(container: FeedbackContainer(configuration: configuration))
    }

    public init(container: FeedbackContainer) {

        self.container = container

        let requests = RequestService(container: container)
        let votes = VoteService(container: container)
        let follows = FollowService(container: container)

        self.requests = requests
        self.votes = votes
        self.follows = follows
        self.reports = ReportService(container: container)
        self.comments = CommentService(container: container)
        self.activity = ActivityService(container: container)
        self.moderation = ModerationService(container: container,
                                            requests: requests,
                                            votes: votes,
                                            follows: follows)
        self.accountData = AccountDataService(container: container)

        // `.CKAccountChanged` re-resolves identity inside the container; everything derived from the
        // old identity has to go with it, or the board keeps showing the previous account's votes.
        container.onIdentityChange = { [weak self] in

            guard let self else { return }

            self.votes.reset()
            self.follows.reset()
            self.reports.reset()
            self.comments.reset()
            self.activity.reset()
            self.requests.reset()

            Task { await self.load() }
        }
    }

    public var configuration: FeedbackConfiguration { container.configuration }

    public var isReady: Bool { container.identityState == .ready }

    public var canWrite: Bool { container.canWrite }

    // MARK: - Loading

    public func start() async {

        if let startupTask {

            await startupTask.value

            // Startup has run, but its load may not have landed - a transient failure, or the
            // `.CKAccountChanged` handler resetting `requests` after it. Read again rather than leaving
            // the board empty until someone pulls to refresh.
            if !requests.hasLoadedOnce { await load() }

            return
        }

        // No `identityState` guard here. It was standing in for "startup has not run yet", but
        // `observeAccountChanges` resolves identity independently of this method, and CloudKit posts
        // `.CKAccountChanged` routinely during launch. A board appearing after that found the state
        // already `.ready`, skipped startup entirely and never loaded - pull to refresh was the only
        // way to populate it, because `refresh()` calls `load()` directly. `startupTask` above is the
        // sentinel that actually tracks whether startup has run.
        let task = Task { @MainActor [weak self] in

            guard let self else { return }

            await self.performStart()
        }

        startupTask = task

        await task.value
    }

    private func performStart() async {

        await container.resolveIdentity()
        await load()

        if container.identityState == .ready {

            await activity.registerForRemoteNotificationsIfAuthorized()
            await activity.registerSubscriptions()
            await activity.registerDeveloperSubscription()
            await activity.registerDeveloperCommentSubscription()
        }
    }

    /// Asked when the developer opens the portal, rather than at launch or on submission (§8.3).
    ///
    /// A developer never goes through `submit`, so the first-submission prompt never reaches them and
    /// both developer subscriptions end up delivering to a device that never registered with APNs.
    /// Opening the portal is the developer's equivalent intent signal: it is the one screen the
    /// new-request and new-comment pushes exist to send them back to. Asking at launch instead would
    /// spend the one system prompt before they have shown any interest in the board at all.
    ///
    /// Safe to call on every appearance. `requestNotificationAuthorization` returns early unless the
    /// status is `.notDetermined`, so a developer who has already answered is never re-asked.
    public func askForDeveloperNotificationsIfNeeded() async {

        guard container.isDeveloper, !hasAskedForNotifications else { return }

        hasAskedForNotifications = true

        // The subscriptions themselves save without permission and already did so at startup. What a
        // grant adds is the APNs registration, which `requestNotificationAuthorization` performs
        // itself; re-saving covers identity having resolved after that startup pass.
        if await activity.requestNotificationAuthorization() {

            await activity.registerDeveloperSubscription()
            await activity.registerDeveloperCommentSubscription()
        }
    }

    public func load() async {

        await requests.loadBoard()

        // One bulk query each, none depending on the others.
        //
        // The activity feed is in here rather than only in `refresh()` because the board now carries an
        // unread badge on its Updates button. A feed fetched only on pull-to-refresh leaves that badge
        // reading zero on a cold launch - precisely the moment it has something to say. It costs a
        // signed-out user nothing: `feed()` returns early without an identity. It also means the
        // `.CKAccountChanged` handler, which resets `activity` and then calls this, refills it.
        async let tallies: Void = votes.loadTallies()
        async let reportCounts: Void = reports.loadReportCounts()
        async let following: Void = follows.loadMyFollows()
        async let activityFeed: Void = activity.feed()

        _ = await (tallies, reportCounts, following, activityFeed)
    }

    /// The views' refresh entry point. Identical to `load()` now that the activity feed has joined it,
    /// and kept under its own name because it is what every pull-to-refresh and refresh button calls.
    public func refresh() async {

        await load()
    }

    /// Deletes this user's data and reconciles the state derived from it.
    ///
    /// `ReportService.myReports` is unioned rather than replaced on load, so that a fresh report hides
    /// its target immediately without waiting for a round trip. That means it only ever grows within a
    /// session - after a deletion it would keep hiding content whose report no longer exists. Clearing
    /// it here is what makes the reload authoritative again.
    public func deleteMyData() async {

        await accountData.deleteAllMyData()

        reports.reset()

        // The follow records are gone from the server; without this the cached set keeps every row
        // showing as followed until the next launch.
        follows.reset()

        await load()
    }

    // MARK: - Derived rules

    /// What a **user** may see, after moderation, blocking and the report threshold.
    ///
    /// This is the public-facing rule, and the roadmap uses it too: a roadmap is a curated "here is
    /// what is coming" list, so a hidden request has no business on it even for the person who hid it.
    /// The board is the one place that relaxes it - see `boardRequests`.
    public var visibleRequests: [FeedbackRequest] {

        requests.requests.filter { isVisible($0) }
    }

    /// What the board shows. Identical to `visibleRequests` for a user.
    ///
    /// A developer also sees what *they* have hidden, marked with a badge, so hiding stays reversible
    /// from the screen they actually use rather than only from the portal. Their local author blocks
    /// still apply - those are a personal choice, not a moderation one.
    public var boardRequests: [FeedbackRequest] {

        guard container.isDeveloper else { return visibleRequests }

        return requests.requests.filter { !reports.isBlocked($0.creatorID) }
    }

    /// What the board's own list shows: `boardRequests` without the work that has already shipped.
    ///
    /// Completed requests are the oldest things on the board and so carry the largest tallies, which
    /// under the default vote sort parked them permanently at the top of the one screen whose question
    /// is "what should I build next". Nothing is lost by dropping them: `RoadmapView` groups completed
    /// work by the version it shipped in, and the board still *finds* it by search - see
    /// `FeedbackBoardView.displayedRequests`, where searching deliberately reads `boardRequests`
    /// instead. That split is load-bearing. The board is where someone looks before filing, so a
    /// shipped request that no longer has a row of its own must still answer to its own name, or
    /// hiding it simply converts it into duplicate reports.
    ///
    /// This applies to the developer too. The board is the shared view of what is still live, and the
    /// portal is where completed work is administered. Their moderation relaxation above is a separate
    /// axis and survives: a developer still sees what they have hidden, badged, as long as it is open.
    public var openBoardRequests: [FeedbackRequest] {

        boardRequests.filter { Self.belongsOnOpenBoard($0.status) }
    }

    /// The rule itself, free of any state, so it can be tested without a container.
    ///
    /// Only `complete` goes. `updatePending` stays on the board on purpose: "fixed, waiting on a
    /// release" is the most reassuring thing a reporter can be shown, and hiding it reads as the
    /// report having been dropped, which invites them to file it again.
    nonisolated static func belongsOnOpenBoard(_ status: RequestStatus) -> Bool { status != .complete }

    public func isVisible(_ request: FeedbackRequest) -> Bool {

        reports.isVisible(request, threshold: configuration.reportThreshold)
    }

    public func isMine(_ request: FeedbackRequest) -> Bool {

        guard let me = container.currentUserRecordID else { return false }

        return request.creatorID == me
    }

    /// A request becomes read-only for its creator once **another** user has voted on it.
    ///
    /// The creator auto-votes on their own request at creation, so the tally is 1 from the moment it
    /// exists. The check is therefore "votes excluding mine", never "votes > 0" - the latter freezes
    /// every request the instant it is created.
    public func canEdit(_ request: FeedbackRequest) -> Bool {

        Self.canEdit(isMine: isMine(request),
                     status: request.status,
                     tally: votes.tally(for: request.id),
                     hasVoted: votes.hasVoted(on: request.id))
    }

    /// The rule itself, free of any state. The subtraction is the whole point and is easy to get
    /// wrong, so it is worth being able to test on its own.
    nonisolated static func canEdit(isMine: Bool, status: RequestStatus, tally: Int, hasVoted: Bool) -> Bool {

        guard isMine, status != .complete else { return false }

        return tally - (hasVoted ? 1 : 0) <= 0
    }

    /// Voting also follows, so the common case needs no second tap. Withdrawing a vote deliberately
    /// leaves the follow in place - losing interest in *building* something is not the same as no
    /// longer wanting to hear how it turns out.
    public func vote(on request: FeedbackRequest) async throws {

        try await votes.vote(on: request.id)
        try? await follows.follow(request.id)
    }

    // MARK: - Actions

    /// Creating auto-votes for the creator, which is both sensible (you want your own request) and
    /// what makes the edit lock's "excluding my own vote" arithmetic work.
    public func submit(title: String,
                       body: String,
                       type: FeedbackType,
                       imageData: [Data],
                       metadata: [String: String]) async throws -> FeedbackRequest {

        let request = try await requests.create(title: title,
                                                body: body,
                                                type: type,
                                                imageData: imageData,
                                                metadata: metadata)

        try? await votes.vote(on: request.id)
        try? await follows.follow(request.id)

        // Asked here, at the first submission, rather than on first open of the board (§8.3).
        if !hasAskedForNotifications {

            hasAskedForNotifications = true

            if await activity.requestNotificationAuthorization() {

                await activity.registerSubscriptions()
            }
        }

        return request
    }
}
