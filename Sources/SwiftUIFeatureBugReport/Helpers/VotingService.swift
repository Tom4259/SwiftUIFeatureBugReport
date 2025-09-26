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
    
    public func hasVoted(for issueNumber: Int) -> Bool {
        
        votedIssues.contains(issueNumber)
    }
    
    public func addVote(to issueNumber: Int, using gitHubService: GitHubService) async throws {

        guard !hasVoted(for: issueNumber) else {
            
            throw VotingError.alreadyVoted
        }
        
        try await gitHubService.addVote(to: issueNumber)
        
        // Track locally to prevent future duplicate votes
        var voted = votedIssues
        voted.insert(issueNumber)
        votedIssues = voted
    }
}

public enum VotingError: LocalizedError {
    
    case alreadyVoted
    case notVoted
    
    public var errorDescription: String? {
        
        switch self {
            
        case .alreadyVoted: return "You've already voted for this issue"
        case .notVoted: return "You haven't voted for this issue"
        }
    }
}
