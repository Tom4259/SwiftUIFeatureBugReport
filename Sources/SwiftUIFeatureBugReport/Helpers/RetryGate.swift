//
//  RetryGate.swift
//  SwiftUIFeatureBugReport
//

import Foundation
import Observation

/// Holds a retry affordance closed for as long as CloudKit asked us to wait.
///
/// Rate limiting is the one error where offering a retry button makes things actively worse: a user
/// tapping it into an active limit extends the limit. `CKErrorRetryAfterKey` says how long to wait,
/// so the button simply is not there until then.
@Observable @MainActor final class RetryGate {

    private(set) var blockedUntil: Date?

    var isBlocked: Bool {

        guard let blockedUntil else { return false }

        return blockedUntil > .now
    }

    func note(_ error: any Error) {

        guard let delay = CloudKitErrorHandler.retryDelay(for: error) else { return }

        blockedUntil = Date.now.addingTimeInterval(delay)

        Task {

            try? await Task.sleep(for: .seconds(delay))

            if let blockedUntil, blockedUntil <= .now { self.blockedUntil = nil }
        }
    }

    func clear() { blockedUntil = nil }
}
