// GitHubService.swift
import Foundation
import SwiftUI

@Observable @MainActor public class GitHubService {
    
    private var allIssues: [GitHubIssue] = []
    public var issues: [GitHubIssue] = []
    public var isLoading = false
    public var errorMessage: String?
    
    private let baseURL = "https://api.github.com"
    private let owner: String
    private let repo: String
    private let token: String
    
    public init(credentials: GitHubCredentials) {
        
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
    
    
    private func updateVoteCount(in body: String?, newCount: Int) -> String {
        
        guard let body = body else {
            return "\n\n---\n👍 Votes: \(newCount)"
        }
        
        let votePattern = #"👍 Votes: \d+"#
        let newVoteText = "👍 Votes: \(newCount)"
        
        if body.contains("👍 Votes:") {
            // Replace existing count
            guard let regex = try? NSRegularExpression(pattern: votePattern) else {
                return body
            }
            
            let range = NSRange(body.startIndex..., in: body)
            
            return regex.stringByReplacingMatches(in: body, range: range, withTemplate: newVoteText)
        }
        else {
            // Add vote count to end
            return body + "\n\n---\n\(newVoteText)"
        }
    }
    
    // MARK: - Public API Methods
    
    public func loadIssues() async {
        
        isLoading = true
        errorMessage = nil
        
        do {
            
            guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues?state=open&sort=created&direction=desc") else { throw GitHubError.invalidURL }
            
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                
                throw GitHubError.invalidResponse
            }
            
            let fetchedIssues = try JSONDecoder().decode([GitHubIssue].self, from: data)
            
            // Sort by vote count (highest first), then by creation date
            self.issues = fetchedIssues.sorted { issue1, issue2 in
                let votes1 = issue1.voteCount
                let votes2 = issue2.voteCount
                
                if votes1 == votes2 {
                    // If votes are equal, sort by creation date (newest first)
                    return issue1.created_at > issue2.created_at
                }
                
                return votes1 > votes2
            }
        }
        catch {
            
            self.errorMessage = error.localizedDescription
            
            print("Error loading issues: \(error)")
        }
        
        isLoading = false
    }
    
    @discardableResult
    public func createIssue(title: String, description: String, contactEmail: String? = nil, type: IssueType, deviceInfo: String) async throws -> Int {
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues")!
        
        let label = type == .bugs ? "bug" : "feature-request"
        let body = """
        \(description)
        
        ---
        **Device Information:**
        \(deviceInfo)
        
        **Contact Email:**
        \(contactEmail ?? "N/A")
        
        *Submitted via mobile app*
        
        ---
        👍 Votes: 0
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
        
        let createdIssue = try JSONDecoder().decode(GitHubIssue.self, from: data)
        
        
        withAnimation { issues.insert(createdIssue, at: 0) }
        
        
        return createdIssue.number
    }
    
    public func addVote(to issueNumber: Int) async throws {

        let issue = try await getIssue(number: issueNumber)
        
        // Parse current vote count
        let currentVotes = issue.voteCount
        let newVotes = currentVotes + 1
        
        // Update the issue body with new vote count
        let updatedBody = updateVoteCount(in: issue.body, newCount: newVotes)
        try await updateIssue(number: issueNumber, body: updatedBody)
    }
    
    // MARK: - Comments

    // Get all comments for a specific issue
    public func getComments(for issueNumber: Int) async throws -> [GitHubComment] {
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(issueNumber)/comments")!
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            
            throw GitHubError.invalidResponse
        }
        
        return try JSONDecoder().decode([GitHubComment].self, from: data)
    }

    // Add a comment to an issue
    public func addComment(to issueNumber: Int, body: String) async throws -> GitHubComment {
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(issueNumber)/comments")!
        var request = URLRequest(url: url)
        
        request.httpMethod = "POST"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let commentData = ["body": body]
        request.httpBody = try JSONSerialization.data(withJSONObject: commentData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            
            throw GitHubError.failedToCreate
        }
        
        return try JSONDecoder().decode(GitHubComment.self, from: data)
    }
    
    
    // MARK: - Private API Methods
    
    private func getIssue(number: Int) async throws -> GitHubIssue {
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(number)")!
        
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            
            throw GitHubError.invalidResponse
        }
        
        return try JSONDecoder().decode(GitHubIssue.self, from: data)
    }
    
    private func updateIssue(number: Int, body: String) async throws {
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(number)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let updateRequest = UpdateIssueRequest(body: body)
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(updateRequest)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            
            throw GitHubError.failedToUpdate
        }
    }
}
