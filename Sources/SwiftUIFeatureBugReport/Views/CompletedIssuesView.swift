//
//  CompletedIssuesView.swift
//  SwiftUIFeatureBugReport
//
//  Created by Tom Redway on 06/10/2025.
//

import SwiftUI

public struct CompletedIssuesView: View {
    
    private let gitHubService: GitHubService
    
    @State private var selectedFilter: IssueType
    
    public init(gitHubService: GitHubService, filter: IssueType = .all) {
        
        self.gitHubService = gitHubService
        self.selectedFilter = filter
    }
    
    var filteredIssues: [GitHubIssue] {
        
        switch selectedFilter {
            
        case .all: return gitHubService.completedIssues
        case .bugs: return gitHubService.completedIssues.filter { $0.isBug }
        case .features: return gitHubService.completedIssues.filter { $0.isFeatureRequest }
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
                
                ForEach(filteredIssues) { issue in
                    
                    NavigationLink(destination: {
                        IssueDetailsView(issue: issue, gitHubService: gitHubService)
                    }, label: {
                        
                        VStack(alignment: .leading, spacing: 8) {
                            
                            HStack {
                                
                                Text(issue.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                
                                Spacer()
                                
                                IssueTypeLabel(selectedFilter: $selectedFilter, issue: issue)
                            }
                            
                            // Description
                            if let body = issue.displayableBody, !body.isEmpty {
                                
                                Text(body)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            // Bottom row with status and date
                            HStack {
                                
                                HStack(spacing: 4) {
                                    
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    
                                    Text("Completed")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                
                                Spacer()
                                
                                Text("Closed \(formatDate(issue.updated_at))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    })
                }
            }
        }
        .navigationTitle("Completed")
        .task {
            
            guard !gitHubService.hasLoadedInitialClosedIssues else { return }
            
            await gitHubService.loadClosedIssues()
            
            gitHubService.hasLoadedInitialClosedIssues = true
        }
        .refreshable { await gitHubService.loadClosedIssues() }
    }
    
    private var emptyStateView: some View {
        
        VStack(spacing: 20) {
            
            Image(systemName: "checkmark.circle")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No completed issues yet")
                .font(.headline)
            
            Text("Closed issues will appear here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
