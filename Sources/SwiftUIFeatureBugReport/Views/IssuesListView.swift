//
//  IssuesListView.swift
//  SwiftUIFeatureBugReport
//
//  Created by Tom Redway on 25/09/2025.
//

import SwiftUI

public struct IssuesListView: View {
    
    private let gitHubService: GitHubService
    
    @State private var votingService = VotingService()
    
    @State private var selectedFilter: IssueType = .all
    
    @State private var showingFeedbackForm = false
    @State private var votingInProgress: Set<Int> = []
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    public init(credentials: GitHubCredentials) {
        
        self.gitHubService = GitHubService(credentials: credentials)
    }
    
    var filteredIssues: [GitHubIssue] {
        
        switch selectedFilter {
            
        case .all: return gitHubService.issues
        case .bugs: return gitHubService.issues.filter { $0.isBug }
        case .features: return gitHubService.issues.filter { $0.isFeatureRequest }
        }
    }
    
    public var body: some View {
        
        Form {
            
            Section {
                
                Picker("Filter", selection: $selectedFilter) {
                    
                    ForEach(IssueType.allCases, id: \.self) { type in
                        
                        Text(type.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
                
                if gitHubService.isLoading {
                    
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                }
                else if filteredIssues.isEmpty {
                    
                    emptyStateView
                }
                else {
                    
                    List(filteredIssues) { issue in
                        
                        IssueRowView(service: gitHubService,
                                     issue: issue,
                                     isVoting: votingInProgress.contains(issue.number),
                                     hasVoted: votingService.hasVoted(for: issue.number),
                                     onUpvote: { await upvoteIssue(issue) })
                    }
                }
        }
        .navigationTitle("Feedback")
        .toolbar {
            
            ToolbarItem(placement: .navigationBarTrailing) {
                
                Button(action: { showingFeedbackForm = true }, label: { Image(systemName: "plus") })
            }
        }
        
        .task { await gitHubService.loadIssues() }
        
        .refreshable { await gitHubService.loadIssues() }
        
        .sheet(isPresented: $showingFeedbackForm) { FeedbackFormView(gitHubService: gitHubService, selectedType: selectedFilter) }
        
        .alert("Voting Error", isPresented: $showErrorAlert, actions: { Button("Ok") { } }, message: { Text(errorMessage ?? "Unknown error occurred") })
    }
    
    private var emptyStateView: some View {
        
        VStack(spacing: 20) {
            
            Image(systemName: selectedFilter == .bugs ? "ladybug.circle" : "lightbulb.circle")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Group {
                
                if selectedFilter == .all {
                    
                    Text("Nothing yet")
                }
                else {
                    
                    Text("No \(selectedFilter.rawValue.lowercased()) yet")
                }
            }
            .font(.headline)
            
            Text("Be the first to submit \(selectedFilter == .bugs ? "a bug report" : selectedFilter == .features ? "a feature request" : "feedback")!")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Submit Feedback") {
                showingFeedbackForm = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func upvoteIssue(_ issue: GitHubIssue) async {
        
        // Prevent multiple simultaneous votes on same issue
        guard !votingInProgress.contains(issue.number) else { return }
        
        // Check if user already voted
        if votingService.hasVoted(for: issue.number) {
            
            errorMessage = "You've already voted for this issue"
            showErrorAlert = true
            
            return
        }
        
        votingInProgress.insert(issue.number)
        
        do {
            
            try await votingService.addVote(to: issue.number, using: gitHubService)
            // Refresh the list to show updated vote counts
            await gitHubService.loadIssues()
        }
        catch {
            
            errorMessage = error.localizedDescription
            showErrorAlert = true
            
            print("Failed to upvote: \(error)")
        }
        
        votingInProgress.remove(issue.number)
    }
}

public struct IssueRowView: View {
    
    public let service: GitHubService
    public let issue: GitHubIssue
    
    public let isVoting: Bool
    public let hasVoted: Bool
    
    public let onUpvote: () async -> Void    
    
    
    public init(service: GitHubService, issue: GitHubIssue, isVoting: Bool, hasVoted: Bool, onUpvote: @escaping () async -> Void) {
        
        self.service = service
        self.issue = issue
        self.isVoting = isVoting
        self.hasVoted = hasVoted
        self.onUpvote = onUpvote
    }
    
    public var body: some View {
        
        NavigationLink(destination: { IssueDetailsView(issue: issue, gitHubService: service) }, label: {
            
            VStack(alignment: .leading, spacing: 8) {
                            
                HStack {
                    
                    Text(issue.title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    IssueTypeLabel(issue: issue)
                }
                
                // Description (excluding vote count section)
                if let body = issue.displayableBody, !body.isEmpty {
                    
                    Text(body)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Bottom row with voting and date
                HStack {
                    
                    Button(action: { Task { await onUpvote() } }) {
                        
                        HStack(spacing: 4) {
                            
                            if isVoting {
                                
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            else {
                                
                                Image(systemName: hasVoted ? "checkmark.circle.fill" : "arrow.up.circle")
                            }
                            
                            Text("\(issue.voteCount)")
                        }
                        .foregroundColor(hasVoted ? .green : .blue)
                        .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isVoting || hasVoted)
                    
                    Spacer()
                    
                    Text(formatDate(issue.created_at))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        })
        
        
    }
    
    private func formatDate(_ dateString: String) -> String {
        
        let formatter = ISO8601DateFormatter()
        
        guard let date = formatter.date(from: dateString) else {
            
            return "Unknown"
        }
        
        let displayFormatter = RelativeDateTimeFormatter()
        displayFormatter.unitsStyle = .short
        
        return displayFormatter.localizedString(for: date, relativeTo: Date())
    }
}


public struct IssueTypeLabel: View {
    
    public let issue: GitHubIssue
    
    public init(issue: GitHubIssue) {
        
        self.issue = issue
    }
    
    public var body: some View {
        
        Text(issue.isFeatureRequest ? "Feature" : "Bug")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(issue.isFeatureRequest ? Color.blue : Color.red, in: Capsule())
            .foregroundColor(.white)
    }
}


public struct IssueDetailsView: View {
    
    let issue: GitHubIssue
    let gitHubService: GitHubService
    
    @State private var comments: [GitHubComment] = []
    @State private var isLoadingComments = false
    @State private var errorMessage: String?
    
    public var body: some View {
        
        Form {
            
            Section("Description") {
                
                Text(issue.displayableBody ?? "N/A")
            }
            
            Section("Votes") {
                
                Text(issue.voteCount.formatted(.number))
            }
            
            Section {
                
                if isLoadingComments {
                    
                    HStack {
                        
                        ProgressView()
                        
                        Text("Loading comments...")
                    }
                }
                else if comments.isEmpty {
                    
                    Text("No developer response yet")
                        .foregroundColor(.secondary)
                }
                else {
                    
                    ForEach(comments) { comment in
                        
                        VStack(alignment: .leading, spacing: 8) {
                            
                            HStack {
                                
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.blue)
                                
                                Text("Developer")
//                                Text(comment.user.login)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                Spacer()
                                
                                Text(formatDate(comment.created_at))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(comment.body)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
            } header: { Text("Developer Response") }
            
            if let errorMessage = errorMessage {
                
                Section {
                    
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle(issue.title)
        
        .task { await loadComments() }
        
        .refreshable { await loadComments() }
    }
    
    private func loadComments() async {
        
        isLoadingComments = true
        errorMessage = nil
        
        do {
            comments = try await gitHubService.getComments(for: issue.number)
        }
        catch {
            errorMessage = "Failed to load comments: \(error.localizedDescription)"
        }
        
        isLoadingComments = false
    }
    
    private func formatDate(_ dateString: String) -> String {
        
        let formatter = ISO8601DateFormatter()
        
        guard let date = formatter.date(from: dateString) else { return "Unknown" }
        
        let displayFormatter = RelativeDateTimeFormatter()
        displayFormatter.unitsStyle = .short
        
        return displayFormatter.localizedString(for: date, relativeTo: Date())
    }
}
