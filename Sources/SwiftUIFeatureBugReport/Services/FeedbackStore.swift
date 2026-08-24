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

    /// Set once the first submission has asked for notification permission, so it is asked once.
    private var hasAskedForNotifications = false

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

        await container.resolveIdentity()
        await load()

        if container.identityState == .ready {

            await activity.registerSubscriptions()
            await activity.registerDeveloperSubscription()
        }
    }

    public func load() async {

        await requests.loadBoard()

        // One bulk query each, none depending on the others.
        async let tallies: Void = votes.loadTallies()
        async let reportCounts: Void = reports.loadReportCounts()
        async let following: Void = follows.loadMyFollows()

        _ = await (tallies, reportCounts, following)
    }

    public func refresh() async {

        await load()
        await activity.feed()
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

        await load()
    }

    // MARK: - Derived rules

    /// The board after moderation, blocking and the report threshold have been applied.
    public var visibleRequests: [FeedbackRequest] {

        requests.requests.filter { reports.isVisible($0, threshold: configuration.reportThreshold) }
    }

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

        guard isMine(request), request.status != .complete else { return false }

        let othersVotes = votes.tally(for: request.id) - (votes.hasVoted(on: request.id) ? 1 : 0)

        return othersVotes <= 0
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
