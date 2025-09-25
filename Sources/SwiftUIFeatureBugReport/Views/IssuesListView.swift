//
//  IssuesListView.swift
//  SwiftUIFeatureBugReport
//
//  Created by Tom Redway on 25/09/2025.
//

import SwiftUI

struct IssuesListView: View {
    
    @State private var gitHubService: GitHubService
    @State private var selectedFilter: IssueType = .all
    @State private var showingFeedbackForm = false
    
    let credentials: GitHubCredentials
    
    init(credentials: GitHubCredentials) {
        
        self.credentials = credentials
        self.gitHubService = GitHubService(credentials: credentials)
    }
    
    var filteredIssues: [GitHubIssue] {
        switch selectedFilter {
        case .all:
            return gitHubService.issues
        case .bugs:
            return gitHubService.issues.filter { $0.isBug }
        case .features:
            return gitHubService.issues.filter { $0.isFeatureRequest }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Filter Picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(IssueType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                if gitHubService.isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredIssues.isEmpty {
                    emptyStateView
                } else {
                    List(filteredIssues) { issue in
                        IssueRowView(issue: issue) {
                            Task {
                                await upvoteIssue(issue)
                            }
                        }
                    }
                    .refreshable {
                        await gitHubService.loadIssues(type: selectedFilter)
                    }
                }
            }
            .navigationTitle("Feedback")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingFeedbackForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                await gitHubService.loadIssues(type: selectedFilter)
            }
            .onChange(of: selectedFilter) { _, newValue in
                Task {
                    await gitHubService.loadIssues(type: newValue)
                }
            }
            .sheet(isPresented: $showingFeedbackForm) {
                FeedbackFormView(credentils: credentials)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: selectedFilter == .bugs ? "ladybug.circle" : "lightbulb.circle")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No \(selectedFilter.rawValue.lowercased()) yet")
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
        do {
            try await gitHubService.addReaction(to: issue.number)
            // Refresh the list to show updated reaction counts
            await gitHubService.loadIssues(type: selectedFilter)
        } catch {
            print("Failed to upvote: \(error)")
        }
    }
}

struct IssueRowView: View {
    let issue: GitHubIssue
    let onUpvote: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title and Labels
            HStack {
                Text(issue.title)
                    .font(.headline)
                    .lineLimit(2)
                
                Spacer()
                
                IssueTypeLabel(issue: issue)
            }
            
            // Description
            if let body = issue.body, !body.isEmpty {
                Text(body.prefix(100) + (body.count > 100 ? "..." : ""))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            
            // Bottom row with voting and date
            HStack {
                Button(action: onUpvote) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle")
                        Text("\(issue.upvoteCount)")
                    }
                    .foregroundColor(.blue)
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                
                Spacer()
                
                Text(formatDate(issue.created_at))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
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

struct IssueTypeLabel: View {
    let issue: GitHubIssue
    
    var body: some View {
        Text(issue.isFeatureRequest ? "Feature" : "Bug")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(issue.isFeatureRequest ? Color.blue : Color.red)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
