//
//  GitHubCredentials.swift
//  SwiftUIFeatureBugReport
//
//  Created by Tom Redway on 25/09/2025.
//

import Foundation

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
}

public struct GitHubLabel: Codable {
    public let name: String
    public let color: String
}

public struct GitHubUser: Codable {
    public let login: String
    public let id: Int
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
}

public enum GitHubError: LocalizedError {
    case invalidURL
    case invalidResponse
    case failedToCreate
    case failedToUpdate
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from GitHub"
        case .failedToCreate:
            return "Failed to create issue"
        case .failedToUpdate:
            return "Failed to update issue"
        }
    }
}
