// GitHubService.swift
import Foundation

@Observable @MainActor public class GitHubService {
    
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
    
    // MARK: - Vote Parsing Utilities
    public static func parseVoteCount(from body: String?) -> Int {
        
        guard let body = body else { return 0 }
        
        // Look for pattern: 👍 Votes: 123
        let pattern = #"👍 Votes: (\d+)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let countRange = Range(match.range(at: 1), in: body) else {
            return 0
        }
        
        return Int(body[countRange]) ?? 0
    }
    
    public static func removeVoteSection(from body: String) -> String {
        
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
    
    public func loadIssues(type: IssueType = .all) async {
        
        isLoading = true
        errorMessage = nil
        
        do {
            
            var urlString = "\(baseURL)/repos/\(owner)/\(repo)/issues?state=open&sort=created&direction=desc"
            
            switch type {
                
            case .bugs:
                urlString += "&labels=bug"
            case .features:
                urlString += "&labels=feature-request"
            case .all: break
            }
            
            guard let url = URL(string: urlString) else { throw GitHubError.invalidURL }
            
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                
                throw GitHubError.invalidResponse
            }
            
            let fetchedIssues = try JSONDecoder().decode([GitHubIssue].self, from: data)
            
            // Filter issues based on type (since GitHub API doesn't support OR logic for labels)
            let filteredIssues: [GitHubIssue]
            
            switch type {
                
            case .all:
                filteredIssues = fetchedIssues.filter { issue in
                    issue.isBug || issue.isFeatureRequest
                }
                
            case .bugs, .features: filteredIssues = fetchedIssues
            }
            
            // Sort by vote count (highest first), then by creation date
            self.issues = filteredIssues.sorted { issue1, issue2 in
                let votes1 = Self.parseVoteCount(from: issue1.body)
                let votes2 = Self.parseVoteCount(from: issue2.body)
                
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
    public func createIssue(title: String, description: String, type: IssueType, deviceInfo: String) async throws -> Int {
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues")!
        
        let label = type == .bugs ? "bug" : "feature-request"
        let body = """
        \(description)
        
        ---
        **Device Information:**
        \(deviceInfo)
        
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
        
        
        Task { await loadIssues() }
        
        
        return createdIssue.number
    }
    
    public func addVote(to issueNumber: Int) async throws {

        let issue = try await getIssue(number: issueNumber)
        
        // Parse current vote count
        let currentVotes = Self.parseVoteCount(from: issue.body)
        let newVotes = currentVotes + 1
        
        // Update the issue body with new vote count
        let updatedBody = updateVoteCount(in: issue.body, newCount: newVotes)
        try await updateIssue(number: issueNumber, body: updatedBody)
    }
    
    // MARK: - Private API Methods
    
    private func getIssue(number: Int) async throws -> GitHubIssue {
        
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(number)")!
        
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
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
