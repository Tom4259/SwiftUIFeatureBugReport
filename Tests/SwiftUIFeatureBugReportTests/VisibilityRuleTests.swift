//
//  VisibilityRuleTests.swift
//  SwiftUIFeatureBugReportTests
//

import Testing

@testable import SwiftUIFeatureBugReport

/// The rule that decides whether a user sees a request at all. Getting it wrong in either direction
/// is serious: too strict and legitimate content disappears, too loose and reported content stays up.
@Suite("Client-side visibility rule")
struct VisibilityRuleTests {

    private func isVisible(_ moderation: ModerationState,
                           isBlocked: Bool = false,
                           hasReported: Bool = false,
                           reportCount: Int = 0,
                           threshold: Int = 3) -> Bool {

        ReportService.isVisible(moderation: moderation,
                                isBlocked: isBlocked,
                                hasReported: hasReported,
                                reportCount: reportCount,
                                threshold: threshold)
    }

    @Test("Hidden is never visible, whatever else is true")
    func hiddenAlwaysWins() {

        #expect(isVisible(.hidden) == false)
        #expect(isVisible(.hidden, reportCount: 0) == false)
    }

    /// `approved` exists so that a developer clearing reports makes it stick. Without this branch the
    /// reports stay counted, the threshold is still met, and the request re-hides itself as soon as
    /// the next client refreshes - which reads as the developer's action silently failing.
    @Test("Approved survives reports that are already over the threshold")
    func approvedOverridesTheThreshold() {

        #expect(isVisible(.approved, reportCount: 99, threshold: 3))
        #expect(isVisible(.approved, hasReported: true))
    }

    @Test("A blocked author is hidden even when the request is approved")
    func blockingBeatsApproval() {

        #expect(isVisible(.approved, isBlocked: true) == false)
        #expect(isVisible(.visible, isBlocked: true) == false)
    }

    @Test("Reporting hides it for the reporter immediately")
    func reporterStopsSeeingItAtOnce() {

        #expect(isVisible(.visible, hasReported: true, reportCount: 1) == false)
        #expect(isVisible(.visible, hasReported: false, reportCount: 1))
    }

    @Test("The threshold hides at the boundary, not past it")
    func thresholdBoundary() {

        #expect(isVisible(.visible, reportCount: 2, threshold: 3))
        #expect(isVisible(.visible, reportCount: 3, threshold: 3) == false)
        #expect(isVisible(.visible, reportCount: 4, threshold: 3) == false)
    }
}


/// A request becomes read-only for its creator once **another** user has voted on it. The creator
/// auto-votes at creation, so the tally is 1 from the moment the request exists - which is why the
/// rule subtracts the creator's own vote rather than testing `tally > 0`.
@Suite("Edit window")
struct CanEditTests {

    @Test("A brand new request is editable despite its own auto-vote")
    func ownAutoVoteDoesNotFreezeIt() {

        #expect(FeedbackStore.canEdit(isMine: true, status: .open, tally: 1, hasVoted: true))
    }

    @Test("One vote from someone else closes the window")
    func anotherPersonsVoteFreezesIt() {

        #expect(FeedbackStore.canEdit(isMine: true, status: .open, tally: 2, hasVoted: true) == false)
        #expect(FeedbackStore.canEdit(isMine: true, status: .open, tally: 1, hasVoted: false) == false)
    }

    @Test("Withdrawing your own vote does not reopen it for others' votes")
    func withdrawnOwnVote() {

        #expect(FeedbackStore.canEdit(isMine: true, status: .open, tally: 0, hasVoted: false))
    }

    @Test("Someone else's request is never editable")
    func notMine() {

        #expect(FeedbackStore.canEdit(isMine: false, status: .open, tally: 0, hasVoted: false) == false)
    }

    @Test("A completed request is closed to edits even with no votes")
    func completedIsFrozen() {

        #expect(FeedbackStore.canEdit(isMine: true, status: .complete, tally: 0, hasVoted: false) == false)
    }
}


/// Which statuses the board lists while nobody is searching. The roadmap is the other half of this
/// split, so a status dropped here has to be one the roadmap picks up - otherwise it leaves the app
/// with no screen at all.
@Suite("Open board rule")
struct OpenBoardRuleTests {

    @Test("Completed work is the only thing the board drops")
    func completeIsDropped() {

        #expect(FeedbackStore.belongsOnOpenBoard(.complete) == false)
    }

    /// The reassurance case. "Fixed, waiting on a release" reads as the report having been dropped if
    /// it vanishes from the board, which is what makes people file it a second time.
    @Test("Work in flight stays on the board")
    func inFlightStays() {

        #expect(FeedbackStore.belongsOnOpenBoard(.open))
        #expect(FeedbackStore.belongsOnOpenBoard(.inProgress))
        #expect(FeedbackStore.belongsOnOpenBoard(.updatePending))
    }

    /// Board and roadmap have to cover all four between them. `RoadmapView` lists `inProgress`,
    /// `updatePending` and `complete`, so `open` is the one status only the board can show - and the
    /// rule must never drop it.
    @Test("Every status is reachable from one screen or the other")
    func noStatusIsOrphaned() {

        let roadmapCovers: Set<RequestStatus> = [.inProgress, .updatePending, .complete]

        for status in RequestStatus.allCases {

            #expect(FeedbackStore.belongsOnOpenBoard(status) || roadmapCovers.contains(status),
                    "\(status.rawValue) appears on neither the board nor the roadmap")
        }
    }
}
