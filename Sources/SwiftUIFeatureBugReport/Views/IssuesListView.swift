//
//  IssuesListView.swift
//  SwiftUIFeatureBugReport
//
//  Created by Tom Redway on 25/09/2025.
//

import SwiftUI

public struct IssuesListView: View {
    
    @State var gitHubService: GitHubService
    @State private var ownershipService = IssueOwnershipService()
    
    @State private var votingService = VotingService()
    
    @State private var selectedFilter: IssueType = .all
    @AppStorage("issueSort") private var selectedSort: SortType = .votes
    
    @State private var showingFeedbackForm = false
    @State private var votingInProgress: Set<Int> = []
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    /// Whether the view brings its own `NavigationStack`.
    private let embedsNavigationStack: Bool

    /// Leave `embedsNavigationStack` on when presenting this somewhere with no navigation of its own -
    /// a sheet, or a split view's detail column. Turn it off when pushing this onto a stack the host
    /// already owns: a stack nested inside another stack's destination makes SwiftUI compare the two
    /// paths against each other, and it traps when their element types differ.
    public init(credentials: GitHubCredentials, allowUserReplies: Bool = false, embedsNavigationStack: Bool = true) {

        self.gitHubService = GitHubService(credentials: credentials, allowUserReplies: allowUserReplies)
        self.embedsNavigationStack = embedsNavigationStack
    }
    
    var filteredIssues: [GitHubIssue] {
        
        switch selectedFilter {
            
        case .all: return gitHubService.issues
        case .bugs: return gitHubService.issues.filter { $0.isBug }
        case .features: return gitHubService.issues.filter { $0.isFeatureRequest }
        }
    }
    
    var sortedIssues: [GitHubIssue] {
        
        switch selectedSort {
            
        case .votes: return filteredIssues.sorted(by: { $0.voteCount > $1.voteCount })
        case .mostRecent: return filteredIssues.sorted(by: { $0.updated_at > $1.updated_at })
        }
    }
    
    public var body: some View {

        if embedsNavigationStack {

            NavigationStack { issuesList }
        }
        else {

            issuesList
        }
    }

    @ViewBuilder private var issuesList: some View {

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
            else {

                Section {

                    NavigationLink(destination: { CompletedIssuesView(gitHubService: gitHubService, ownershipService: ownershipService, filter: selectedFilter) },
                                   label: { Label("View Completed", systemImage: "checkmark.circle") })
                }

                if filteredIssues.isEmpty {

                    emptyStateView
                }
                else {

                    List(sortedIssues) { issue in

                        IssueRowView(service: $gitHubService,
                                     ownershipService: $ownershipService,
                                     selectedFilter: $selectedFilter,
                                     issue: issue,
                                     isVoting: votingInProgress.contains(issue.number),
                                     hasVoted: votingService.hasVoted(for: issue.number),
                                     onUpvote: { await upvoteIssue(issue) })
                    }
                }
            }
        }
        .navigationTitle("Feedback")
        .toolbar {

            ToolbarItem(placement: toolbarTrailingPlacement) {

                Menu(content: {

                    Picker(selection: $selectedSort, content: {

                        ForEach(SortType.allCases, id: \.self) {

                            Text($0.localised)
                        }

                    }, label: { })

                }, label: { Image(systemName: "line.horizontal.3.decrease") })
            }

            #if os(iOS)
            if #available(iOS 26, *) {

                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            #endif

            ToolbarItem(placement: toolbarTrailingPlacement) {

                Button(action: { showingFeedbackForm = true }, label: { Image(systemName: "plus") })
            }
        }

        .task {

            guard !gitHubService.hasLoadedInitialIssues else { return }

            await gitHubService.loadIssues()

            gitHubService.hasLoadedInitialIssues = true
        }

        .refreshable { await gitHubService.loadIssues() }

        .sheet(isPresented: $showingFeedbackForm) { FeedbackFormView(gitHubService: gitHubService, selectedType: selectedFilter, ownershipService: ownershipService) }

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
    
    @Binding var service: GitHubService
    @Binding var ownershipService: IssueOwnershipService
    @Binding var selectedFilter: IssueType
    var issue: GitHubIssue
    
    var isVoting: Bool
    var hasVoted: Bool
    
    var onUpvote: () async -> Void
    
    
    public var body: some View {
        
        NavigationLink(destination: { IssueDetailsView(issue: issue, gitHubService: service, ownershipService: ownershipService) }, label: {
            
            VStack(alignment: .leading, spacing: 8) {
                            
                HStack {
                    
                    Text(issue.title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    IssueTypeLabel(selectedFilter: $selectedFilter, issue: issue)
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
                    
                    Text(issue.wasEdited ? "Updated \(formatDate(issue.updated_at))" : formatDate(issue.created_at))
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
    
    @Binding var selectedFilter: IssueType
    
    var issue: GitHubIssue
    
    public var body: some View {
        
        if let otherLabel = issue.nextLabel {
            
            LabelDisplay(label: otherLabel)
        }
        
        if selectedFilter == .all {
            
            Text(issue.isFeatureRequest ? "Feature" : "Bug")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(issue.isFeatureRequest ? Color.blue : Color.red, in: Capsule())
                .foregroundColor(.white)
        }
    }
}


public struct LabelDisplay: View {
    
    let label: GitHubLabel
    
    public var body: some View {
        
        Text(label.name)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(label.displayColour, in: Capsule())
            .foregroundColor(.white)
    }
}


public struct IssueDetailsView: View {
    
    let issue: GitHubIssue
    let gitHubService: GitHubService
    let ownershipService: IssueOwnershipService
    
    @State private var comments: [GitHubComment] = []
    @State private var isLoadingComments = false
    @State private var errorMessage: String?
    
    @State private var showEditForm = false
    
    @State private var showCloseConfirmation = false
    @State private var showReopenConfirmation = false
    @State private var isClosing = false
    
    @State private var showReplySheet = false
    
    public var body: some View {
        
        Form {
            
            Section("Labels") {
                
                HStack {
                    
                    ForEach(issue.displayLabels, id: \.name) { label in
                        
                        LabelDisplay(label: label)
                    }
                }
            }
            
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
                        
                        IssueDetailsView.commentView(comment: comment)
                    }
                }
                
            } header: { Text("Comments") }
            
            if ownershipService.ownsIssue(issue.number) && gitHubService.allowUserReplies {
                
                Button(action: { showReplySheet = true }, label: { Label("Reply", systemImage: "arrowshape.turn.up.left") })
            }
            
            if let errorMessage = errorMessage {
                
                Section {
                    
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle(issue.title)
        
        .toolbar {
            
            //only show this if the corerct user
            if ownershipService.ownsIssue(issue.number) {
                
                ToolbarItem(placement: toolbarTrailingPlacement) {
                    
                    Menu(content: {
                        
                        if gitHubService.completedIssues.contains(where: { $0.id == issue.id }) {
                            
                            Button(action: { showReopenConfirmation = true }, label: { Label("Mark Incomplete", systemImage: "xmark") })
                        }
                        else {
                            
                            Button(action: { showEditForm = true }, label: { Label("Edit", systemImage: "pencil") })
                            Button(action: { showCloseConfirmation = true }, label: { Label("Mark Completed", systemImage: "checkmark") })
                        }
                        
                    }, label: { Image(systemName: "ellipsis") })
                }
            }
        }
        
        .task { await loadComments() }
        
        .refreshable { await loadComments() }
        
        .sheet(isPresented: $showEditForm) {
            FeedbackFormView(
                gitHubService: gitHubService,
                selectedType: issue.isFeatureRequest ? .features : .bugs,
                issueToEdit: issue,
                ownershipService: ownershipService
            )
        }
        
        .sheet(isPresented: $showReplySheet, onDismiss: { Task { await loadComments() } }) { IssueReplyView(issue: issue, gitHubService: gitHubService, comments: comments) }
        
        .alert("Close Feedback", isPresented: $showCloseConfirmation) {
            
            Button("Close", role: .destructive) { Task { await closeIssue() } }
            
            Button("Cancel", role: .cancel) { }
            
        } message: {  Text("Are you sure you want to close this issue? You can reopen it later if needed.") }
        
        .alert("Reopen Feedback", isPresented: $showReopenConfirmation) {
            
            Button("Reopen") { Task { await reopenIssue() } }
            
            Button("Cancel", role: .cancel) { }
            
        } message: { Text("This will reopen the issue and mark it as active again.") }
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
    
    
    private func closeIssue() async {
            
        isClosing = true
        errorMessage = nil
        
        do {
            
            try await gitHubService.closeIssue(number: issue.number)
            
            //refresh issues
            await gitHubService.loadIssues()
            await gitHubService.loadClosedIssues()
        }
        catch { errorMessage = "Failed to close issue: \(error.localizedDescription)"  }
        
        isClosing = false
    }
    
    private func reopenIssue() async {
        
        isClosing = true
        errorMessage = nil
        
        do {
            
            try await gitHubService.reopenIssue(number: issue.number)
            
            //refresh issues
            await gitHubService.loadIssues()
            await gitHubService.loadClosedIssues()
        }
        catch { errorMessage = "Failed to reopen issue: \(error.localizedDescription)" }
        
        isClosing = false
    }
    
    
    static func formatDate(_ dateString: String) -> String {
        
        let formatter = ISO8601DateFormatter()
        
        guard let date = formatter.date(from: dateString) else { return "Unknown" }
        
        let displayFormatter = RelativeDateTimeFormatter()
        displayFormatter.unitsStyle = .short
        
        return displayFormatter.localizedString(for: date, relativeTo: Date())
    }
    
    @ViewBuilder
    static func commentView(comment: GitHubComment) -> some View {
        
        VStack(alignment: .leading, spacing: 8) {
            
            HStack {
                
                Image(systemName: "person.circle.fill")
                    .foregroundColor(comment.isDeveloper ? .blue : .green)
                
                Text(comment.isDeveloper ? "Developer" : "User")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(IssueDetailsView.formatDate(comment.created_at))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(comment.trimmedBody)
                .font(.body)
        }
        .padding(.vertical, 4)
    }
    
    public struct IssueReplyView: View {
        
        @Environment(\.dismiss) var dismiss
        
        let issue: GitHubIssue
        let gitHubService: GitHubService
        let comments: [GitHubComment]
        
        @State private var replyMessage: String = ""
        
        @State private var errorSendingReply = false
        
        public var body: some View {
            
            NavigationStack {
                
                Form {
                    
                    Section("Messages") {
                        
                        if comments.isEmpty {
                            
                            Text("No messages")
                        }
                        else {
                            
                            ForEach(comments) { comment in
                                
                                IssueDetailsView.commentView(comment: comment)
                            }
                        }
                    }
                    
                    Section("New Message") {
                        
                        TextEditor(text: $replyMessage)
                            .frame(minHeight: 100)
                    }
                }
                .navigationTitle("New Message")
                
                .toolbar {
                    
                    ToolbarItem(placement: toolbarLeadingPlacement) {
                        
                        Button(role: .cancel, action: { dismiss() }, label: { Image(systemName: "xmark") })
                    }
                    
                    ToolbarItem(placement: toolbarTrailingPlacement) {
                        
                        if #available(iOS 26.0, macOS 26.0, *) {
                            
                            Button(role: .confirm, action: { sendReply() }, label: { Text("Reply") })
                        }
                        else {
                            
                            Button(action: { sendReply() }, label: { Text("Reply") })
                        }
                    }
                }
                
                .alert("Error sending reply", isPresented: $errorSendingReply, actions: { Button("Ok") { } }, message: { Text("Please try again later.") })
            }
        }
        
        private func sendReply() {
            
            guard !replyMessage.isEmpty else { return }
            
            let userBody: String = "User: " + replyMessage
            
            Task {
                
                do {
                    
                    try await gitHubService.addComment(to: issue.number, body: userBody)
                    
                    UserDefaults.standard.set(comments.count + 1, forKey: "commentsCount-\(issue.number)")
                    
                    dismiss()
                }
                catch {
                    
                    errorSendingReply = true
                }
            }
        }
    }
}

private var toolbarLeadingPlacement: ToolbarItemPlacement {
    
#if os(iOS)
    .topBarLeading
#else
    .secondaryAction
#endif
}

private var toolbarTrailingPlacement: ToolbarItemPlacement {
    
#if os(iOS)
    .topBarTrailing
#else
    .primaryAction
#endif
}
