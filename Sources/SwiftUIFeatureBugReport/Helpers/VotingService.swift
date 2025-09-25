//
//  VotingService.swift
//  SwiftUIFeatureBugReport
//
//  Created by Tom Redway on 25/09/2025.
//

import Foundation
import SwiftUI

@Observable @MainActor public class VotingService {
    
    @ObservationIgnored @AppStorage("votedIssues") private var votedIssueData: Data = Data()
    
    private var votedIssues: Set<Int> {
        get {
            (try? JSONDecoder().decode(Set<Int>.self, from: votedIssueData)) ?? []
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                votedIssueData = encoded
            }
        }
    }
    
    public init() {}
    
    // MARK: - Public API
    
    /// Check if user has already voted for a specific issue
    public func hasVoted(for issueNumber: Int) -> Bool {
        votedIssues.contains(issueNumber)
    }
    
    /// Add vote with local tracking to prevent duplicate votes
    public func addVote(to issueNumber: Int, using gitHubService: GitHubService) async throws {
        // Check if already voted
        guard !hasVoted(for: issueNumber) else {
            throw VotingError.alreadyVoted
        }
        
        // Add vote to GitHub
        try await gitHubService.addVote(to: issueNumber)
        
        // Track locally to prevent future duplicate votes
        var voted = votedIssues
        voted.insert(issueNumber)
        votedIssues = voted
    }
    
    /// Remove vote from local tracking (Note: doesn't decrement GitHub count)
    public func removeVote(from issueNumber: Int) {
        var voted = votedIssues
        voted.remove(issueNumber)
        votedIssues = voted
    }
    
    /// Get all voted issue numbers (useful for debugging)
    public func getVotedIssues() -> Set<Int> {
        return votedIssues
    }
    
    /// Clear all votes from local storage (useful for testing/reset)
    public func clearAllVotes() {
        votedIssues = []
    }
    
    /// Get count of total votes cast by this user
    public func getTotalVoteCount() -> Int {
        return votedIssues.count
    }
}

public enum VotingError: LocalizedError {
    case alreadyVoted
    case notVoted
    
    public var errorDescription: String? {
        switch self {
        case .alreadyVoted:
            return "You've already voted for this issue"
        case .notVoted:
            return "You haven't voted for this issue"
        }
    }
}
