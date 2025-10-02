//
//  GitHubCredentials.swift
//  SwiftUIFeatureBugReport
//
//  Created by Tom Redway on 25/09/2025.
//

import Foundation
import SwiftUI


public struct GitHubCredentials {
    
    let owner: String
    let repo: String
    let token: String
    
    public init(owner: String, repo: String, token: String) {
        
        self.owner = owner
        self.repo = repo
        self.token = token
    }
}

public struct GitHubIssue: Codable, Identifiable {
    
    public let id: Int
    public let number: Int
    public let title: String
    public let body: String?
    public let state: String
    public let labels: [GitHubLabel]
    public let created_at: String
    public let updated_at: String
    public let user: GitHubUser
    
    public var isFeatureRequest: Bool {
        labels.contains { $0.name == "feature-request" }
    }
    
    public var isBug: Bool {
        labels.contains { $0.name == "bug" }
    }
    
    public var displayableBody: String? {
        
        guard let body else { return nil }
        
        let cleaned = removeVoteSection(from: body)
        
        return cleaned
    }
    
    
    var voteCount: Int {
        
        return parseVoteCount(from: body)
    }
    
    
    private func removeVoteSection(from body: String) -> String {
        
        guard !body.isEmpty else { return body }
        
        var cleanedBody = body
        
        // Remove the vote section (everything after the vote separator line)
        if let voteSeparatorRange = cleanedBody.range(of: "\n\n---\n👍 Votes:") {
            
            cleanedBody = String(cleanedBody[..<voteSeparatorRange.lowerBound])
        }
        
        // Remove the device information section (everything after the device info separator)
        if let deviceSeparatorRange = cleanedBody.range(of: "\n\n---\n**Device Information:**") {
            
            cleanedBody = String(cleanedBody[..<deviceSeparatorRange.lowerBound])
        }
        
        // Also handle the "Submitted via mobile app" section if it exists without device info
        if let appSeparatorRange = cleanedBody.range(of: "\n\n*Submitted via mobile app*") {
            
            cleanedBody = String(cleanedBody[..<appSeparatorRange.lowerBound])
        }
        
        return cleanedBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func parseVoteCount(from body: String?) -> Int {
        
        guard let body else { return 0 }
        
        // Look for pattern: 👍 Votes: 123
        let pattern = #"👍 Votes: (\d+)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let countRange = Range(match.range(at: 1), in: body) else {
            return 0
        }
        
        return Int(body[countRange]) ?? 0
    }
}

public struct GitHubLabel: Codable {
    
    public let name: String
    public let color: String
}

public struct GitHubUser: Codable {
    
    public let login: String
    public let id: Int
}

public struct GitHubComment: Codable, Identifiable {
    
    public let id: Int
    public let body: String
    public let user: GitHubUser
    public let created_at: String
    public let updated_at: String
}

struct CreateIssueRequest: Codable {
    
    let title: String
    let body: String
    let labels: [String]
}

struct UpdateIssueRequest: Codable {
    
    let body: String
}

public enum IssueType: String, CaseIterable {
    
    case all = "All"
    case bugs = "Bugs"
    case features = "Feature Requests"
    
    var localised: LocalizedStringKey {
        
        switch self {
            
        case.all: return "All"
        case .bugs: return "Bugs"
        case .features: return "Feature Requests"
        }
    }
}

public enum GitHubError: LocalizedError {
    
    case invalidURL
    case invalidResponse
    case failedToCreate
    case failedToUpdate
    
    public var errorDescription: LocalizedStringKey? {
        
        switch self {
            
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response from GitHub"
        case .failedToCreate: return "Failed to create issue"
        case .failedToUpdate: return "Failed to update issue"
        }
    }
}
