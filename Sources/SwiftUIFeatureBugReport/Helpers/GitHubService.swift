// GitHubService.swift
import Foundation
import SwiftUI

@Observable @MainActor public class GitHubService {
    
    private var allIssues: [GitHubIssue] = []
    public var issues: [GitHubIssue] = []
    public var completedIssues: [GitHubIssue] = []
    public var isLoading = false
    public var errorMessage: String?
    
    private let baseURL = "https://api.github.com"
    private let owner: String
    private let repo: String
    private let token: String
    
    public let allowUserReplies: Bool
    
    public var hasLoadedInitialIssues: Bool = false
    public var hasLoadedInitialClosedIssues: Bool = false
    
    public init(credentials: GitHubCredentials, allowUserReplies: Bool = false) {
        
        self.owner = credentials.owner
        self.repo = credentials.repo
        self.token = credentials.token
        self.allowUserReplies = allowUserReplies
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
        
        withAnimation { isLoading = true }
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
            
            // no need to sort anymore since the user can choose the sort
            self.issues = fetchedIssues
        }
        catch {
            
            self.errorMessage = error.localizedDescription
            
            print("Error loading issues: \(error)")
        }
        
        withAnimation { isLoading = false }
    }
    
    
    public func loadClosedIssues() async {
        
        withAnimation { isLoading = true }
        errorMessage = nil
        
        do {
            
            guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues?state=closed&sort=updated&direction=desc") else { throw GitHubError.invalidURL }
            
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                
                throw GitHubError.invalidResponse
            }
            
            //only showing issues with bug or feature request. Won't include pull request issues
            let fetchedIssues = try JSONDecoder().decode([GitHubIssue].self, from: data).filter({ $0.labels.contains(where: { $0.name == "bug" || $0.name == "feature-request" }) })
            
            // Sort by last updated (most recent first)
            withAnimation {
                
                self.completedIssues = fetchedIssues.sorted { $0.updated_at > $1.updated_at }
            }
        }
        catch {
            
            self.errorMessage = error.localizedDescription
            
            print("Error loading closed issues: \(error)")
        }
        
        withAnimation { isLoading = false }
    }
    
    
    @discardableResult
    public func createIssue(title: String, description: String, type: IssueType, deviceInfo: String?, contactEmail: String? = nil) async throws -> Int {
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues")!
        
        
        let label = type == .bugs ? "bug" : "feature-request"
        let body = generateIssueBody(description: description, deviceInfo: deviceInfo, contactEmail: contactEmail)
        
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
    
    
    @discardableResult
    public func updateIssueContent(number: Int, title: String, description: String, type: IssueType, deviceInfo: String, contactEmail: String? = nil) async throws -> GitHubIssue {
        
        struct UpdateIssueContentRequest: Codable {
            
            let title: String
            let body: String
            let labels: [String]
        }
        
        // Get current issue to preserve vote count
        let currentIssue = try await getIssue(number: number)
        let currentVotes = currentIssue.voteCount
        
        let label = type == .bugs ? "bug" : "feature-request"
        let body = generateIssueBody(description: description, deviceInfo: deviceInfo, contactEmail: contactEmail)
        
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(number)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let updateRequest = UpdateIssueContentRequest(
            title: title,
            body: body,
            labels: [label, "user-submitted"]
        )
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(updateRequest)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw GitHubError.failedToUpdate
        }
        
        await loadIssues()
        
        return try JSONDecoder().decode(GitHubIssue.self, from: data)
    }
    
    
    
    struct CloseIssueRequest: Codable {
        
        let state: String // "open" or "closed"
    }
    
    // Close an issue
    public func closeIssue(number: Int) async throws {
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(number)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let closeRequest = CloseIssueRequest(state: "closed")
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(closeRequest)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw GitHubError.failedToUpdate
        }
    }

    // Reopen an issue
    public func reopenIssue(number: Int) async throws {
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(number)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let reopenRequest = CloseIssueRequest(state: "open")
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(reopenRequest)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw GitHubError.failedToUpdate
        }
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
    
    
    
    private func generateIssueBody(description: String, deviceInfo: String?, contactEmail: String?) -> String {
        
        var deviceData = ""
        if let deviceInfo {
            
            deviceData = "\n\n---\n**Device Information:**\n" + deviceInfo
        }
        
        
        var contactData = ""
        if let contactEmail {
            
            contactData = "**Contact Email:**\n" + contactEmail
        }
        
        
        
        let body = """
        \(description)        
        \(deviceData)
        
        \(contactData)
        
        ---
        👍 Votes: 0
        """
        
        return body
    }
    
    
    // MARK: - Comments
    
    //call this method to check if there are any new comments that the user hasn't seen on their issues, and a notification will be sent
    public func checkForNewComments() async throws -> [GitHubComment] {
        
        let ownedIssues = IssueOwnershipService().getOwnedIssues()
        
        var newComments: [GitHubComment] = []
        
        for issueNo in ownedIssues {
            
            let key = "commentsCount-\(issueNo)"
            
            let previousCommentCount = UserDefaults.standard.integer(forKey: key)
            
            let comments = try await getComments(for: issueNo)
            
            
            if comments.count > previousCommentCount {
                
                let new = comments.suffix(from: previousCommentCount)
                
                newComments.append(contentsOf: new)
                
                UserDefaults.standard.set(comments.count, forKey: key)
            }
        }
        
        return newComments
    }

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
