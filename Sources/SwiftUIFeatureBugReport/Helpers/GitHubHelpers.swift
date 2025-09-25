//
//  GitHubHelpers.swift
//  SwiftUIFeatureBugReport
//
//  Created by Tom Redway on 25/09/2025.
//

import Foundation

struct GitHubIssue: Codable, Identifiable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let labels: [GitHubLabel]
    let reactions: GitHubReactions?
    let created_at: String
    let updated_at: String
    let user: GitHubUser
    
    var isFeatureRequest: Bool {
        labels.contains { $0.name == "feature-request" }
    }
    
    var isBug: Bool {
        labels.contains { $0.name == "bug" }
    }
    
    var upvoteCount: Int {
        reactions?.plusOne ?? 0
    }
}

struct GitHubLabel: Codable {
    let name: String
    let color: String
}

struct GitHubReactions: Codable {
    let plusOne: Int
    let minusOne: Int
    let laugh: Int
    let hooray: Int
    let confused: Int
    let heart: Int
    
    private enum CodingKeys: String, CodingKey {
        case plusOne = "+1"
        case minusOne = "-1"
        case laugh, hooray, confused, heart
    }
}

struct GitHubUser: Codable {
    let login: String
    let id: Int
}

struct CreateIssueRequest: Codable {
    let title: String
    let body: String
    let labels: [String]
}

struct GitHubCredentials {
    
    let owner: String
    let repo: String
    let token: String
}

@Observable @MainActor class GitHubService {
    
    public var issues: [GitHubIssue] = []
    public var isLoading = false
    public var errorMessage: String?
    
    private let baseURL = "https://api.github.com"
    private let owner: String
    private let repo: String
    private let token: String
    
    init(credentials: GitHubCredentials) {
        
        self.owner = credentials.owner
        self.repo = credentials.repo
        self.token = credentials.token
    }
    
    private var headers: [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json"
        ]
    }
    
    // MARK: - Fetch Issues
    func loadIssues(type: IssueType = .all) async {
        isLoading = true
        errorMessage = nil
        
        do {
            var urlString = "\(baseURL)/repos/\(owner)/\(repo)/issues?state=open&sort=created&direction=desc"
            
            switch type {
            case .bugs:
                urlString += "&labels=bug"
            case .features:
                urlString += "&labels=feature-request"
            case .all:
                urlString += "&labels=bug,feature-request"
            }
            
            guard let url = URL(string: urlString) else {
                throw GitHubError.invalidURL
            }
            
            var request = URLRequest(url: url)
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                throw GitHubError.invalidResponse
            }
            
            let decoder = JSONDecoder()
            let fetchedIssues = try decoder.decode([GitHubIssue].self, from: data)
            
            self.issues = fetchedIssues
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("Error loading issues: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Create Issue
    @discardableResult
    func createIssue(title: String, description: String, type: IssueType, deviceInfo: String) async throws -> Int {
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues")!
        
        let label = type == .bugs ? "bug" : "feature-request"
        let body = """
        \(description)
        
        ---
        **Device Information:**
        \(deviceInfo)
        
        *Submitted via mobile app*
        """
        
        let issueRequest = CreateIssueRequest(
            title: title,
            body: body,
            labels: [label, "user-submitted"]
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(issueRequest)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw GitHubError.failedToCreate
        }
        
        let decoder = JSONDecoder()
        let createdIssue = try decoder.decode(GitHubIssue.self, from: data)
        
        return createdIssue.number
    }
    
    // MARK: - Add Reaction (Upvote)
    func addReaction(to issueNumber: Int, reaction: ReactionType = .plusOne) async throws {
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(issueNumber)/reactions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let reactionBody = ["content": reaction.rawValue]
        request.httpBody = try JSONSerialization.data(withJSONObject: reactionBody)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw GitHubError.failedToReact
        }
    }
}

enum IssueType: String, CaseIterable {
    case all = "All"
    case bugs = "Bugs"
    case features = "Feature Requests"
}

enum ReactionType: String {
    case plusOne = "+1"
    case minusOne = "-1"
    case laugh = "laugh"
    case hooray = "hooray"
    case confused = "confused"
    case heart = "heart"
}

enum GitHubError: LocalizedError {
    case invalidURL
    case invalidResponse
    case failedToCreate
    case failedToReact
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from GitHub"
        case .failedToCreate:
            return "Failed to create issue"
        case .failedToReact:
            return "Failed to add reaction"
        }
    }
}
