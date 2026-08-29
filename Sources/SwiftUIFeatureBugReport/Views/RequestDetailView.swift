//
//  RequestDetailView.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import SwiftUI

public struct RequestDetailView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var store: FeedbackStore
    @State private var request: FeedbackRequest

    @State private var isVoting = false
    @State private var reply = ""
    @State private var isSendingReply = false

    @State private var showingReport = false
    @State private var reportCategory: ReportCategory = .spam

    @State private var showingEdit = false
    @State private var showingCompleteConfirmation = false

    @State private var error: FeedbackError?
    @State private var retryGate = RetryGate()

    private let embedsNavigationStack: Bool

    public init(store: FeedbackStore, request: FeedbackRequest, embedsNavigationStack: Bool = true) {

        self.store = store
        self.request = request
        self.embedsNavigationStack = embedsNavigationStack
    }

    public var body: some View {

        if embedsNavigationStack {

            NavigationStack { detail }
        }
        else {

            detail
        }
    }

    @ViewBuilder private var detail: some View {

        Form {

            Section {

                // Spelled out rather than left to the navigation title: on the Mac this view is a pane
                // of someone else's split view, where that title is drawn by the host if at all, and
                // the detail opened onto the body with nothing saying which request you were reading.
                Text(request.title)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)

                Text(request.body)

                HStack(spacing: 6) {

                    TypeBadge(type: request.type)

                    if request.status == .complete { ResolvedVersionBadge(version: request.resolvedInVersion) }
                    else { StatusBadge(status: request.status) }

                    if request.moderation == .hidden { HiddenBadge() }

                    ForEach(request.labels, id: \.self) { LabelChip(name: $0) }
                }
            }

            imageSection

            Section {

                LabeledContent("Votes", value: store.votes.tally(for: request.id).formatted(.number))
                LabeledContent("Submitted", value: request.createdAt.formatted(date: .abbreviated, time: .omitted))
            }

            commentSection

            if store.comments.canComment(on: request) { replySection }

            if let error {

                Section {

                    FeedbackErrorBanner(error: error, retry: retryGate.isBlocked ? nil : { self.error = nil })
                }
            }

        }
        .formStyle(.grouped)
        .navigationTitle(request.title)
        .inlineNavigationTitle()
        .toolbar { toolbarContent }

        .task {

            request = await store.requests.loadDetail(request)

            await store.comments.load(for: request.id)
        }

        // iOS only. On the Mac `feedbackRefreshable` put a second Refresh button in the host's bar -
        // one that appeared and vanished with the selection and, despite its name, reloaded only this
        // request's comments. The board header's refresh is the one refresh, and it does both now.
        #if os(iOS)
        .refreshable { await store.comments.load(for: request.id) }
        #endif

        .sheet(isPresented: $showingEdit) {

            EditRequestView(store: store, request: request) { updated in request = updated }
        }

        .sheet(isPresented: $showingReport) { reportSheet }

        .confirmationDialog("Mark this complete?",
                            isPresented: $showingCompleteConfirmation,
                            titleVisibility: .visible) {

            Button("Mark complete") { Task { await markComplete() } }
            Button("Cancel", role: .cancel) { }

        } message: { Text("This tells everyone the request has been dealt with. You can't undo it from here.") }
    }

    // MARK: - Sections

    @ViewBuilder private var imageSection: some View {

        switch request.imageState {

        case .pending:

            // The text shows immediately. Hiding the whole request while its image waits on review
            // reads as a failed submission, and the user files it again.
            Section {

                Label("Image awaiting review", systemImage: "clock")
                    .foregroundStyle(.secondary)
            }

        case .rejected:

            Section {

                Label("Image removed by the developer", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }

        case .approved:

            if !request.imageURLs.isEmpty {

                Section { ImageGallery(urls: request.imageURLs) }
            }

        case .none:

            EmptyView()
        }
    }

    @ViewBuilder private var commentSection: some View {

        Section {

            if store.comments.isLoading {

                HStack { ProgressView(); Text("Loading replies…") }
            }
            else if store.comments.comments.isEmpty {

                Text("No replies yet")
                    .foregroundStyle(.secondary)
            }
            else {

                ForEach(store.comments.comments) { comment in

                    CommentRow(comment: comment)
                }
            }

        } header: { Text("Replies") }
    }

    @ViewBuilder private var replySection: some View {

        Section {

            FeedbackTextEditor(placeholder: "Add a reply", text: $reply, minHeight: 80)

            Button(action: { sendReply() }) {

                HStack {

                    Text("Send reply")

                    if isSendingReply { Spacer(); ProgressView().controlSize(.small) }
                }
            }
            .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingReply)

        } footer: {

            Text(store.container.isDeveloper
                 ? "Posted as the developer."
                 : "Only you and the developer can reply here.")
        }
    }

    @ViewBuilder private var reportSheet: some View {

        NavigationStack {

            Form {

                Section {

                    Picker("Reason", selection: $reportCategory) {

                        ForEach(ReportCategory.allCases, id: \.self) {

                            Label($0.localised, systemImage: $0.symbolName).tag($0)
                        }
                    }

                } header: { Text("Reason") }
                  footer: { Text("It stops showing for you straight away. Reports are reviewed by the developer.") }
            }
            .formStyle(.grouped)
            .navigationTitle("Report")
            .inlineNavigationTitle()
            .toolbar {

                ToolbarItem(placement: toolbarLeadingPlacement) {

                    Button("Cancel", role: .cancel) { showingReport = false }
                }

                ToolbarItem(placement: toolbarTrailingPlacement) {

                    Button("Report") { submitReport() }
                }
            }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {

        // Voting is the primary action on this screen, so it sits in the toolbar in its own right
        // rather than behind a menu.
        ToolbarItem(placement: toolbarTrailingPlacement) {

            VoteButton(count: store.votes.tally(for: request.id),
                       hasVoted: store.votes.hasVoted(on: request.id),
                       isBusy: isVoting,
                       isEnabled: store.canWrite,
                       action: { vote() })
        }

        ToolbarItem(placement: toolbarTrailingPlacement) {

            Menu {

                if store.isMine(request) {

                    Section {

                        Button(action: { showingEdit = true },
                               label: { Label("Edit", systemImage: "pencil") })
                            .disabled(!store.canEdit(request))

                        if request.status != .complete {

                            Button(action: { showingCompleteConfirmation = true },
                                   label: { Label("Mark complete", systemImage: "checkmark") })
                        }
                    }
                }

                Section {

                    Button(action: { toggleFollow() }) {

                        Label(store.follows.isFollowing(request.id) ? "Following" : "Follow",
                              systemImage: store.follows.isFollowing(request.id) ? "bell.fill" : "bell")
                    }
                    .disabled(!store.canWrite)
                }

                Section {

                    Button(role: .destructive, action: { showingReport = true },
                           label: { Label("Report", systemImage: "flag") })
                        .disabled(!store.canWrite || store.reports.hasReported(request.id))

                    if !request.creatorID.isEmpty && !store.isMine(request) {

                        Button(role: .destructive, action: { store.reports.block(author: request.creatorID) },
                               label: { Label("Block this author", systemImage: "person.slash") })
                            .disabled(store.reports.isBlocked(request.creatorID))
                    }
                }

            } label: { Label("Options", systemImage: "ellipsis.circle") }
        }
    }

    // MARK: - Actions

    private func vote() {

        guard store.canWrite, !isVoting else { return }

        isVoting = true

        Task {

            do {

                if store.votes.hasVoted(on: request.id) { try await store.votes.unvote(on: request.id) }
                else { try await store.vote(on: request) }
            }
            catch {

                retryGate.note(error)
                self.error = CloudKitErrorHandler.classify(error)
            }

            isVoting = false
        }
    }

    private func toggleFollow() {

        Task {

            do {

                if store.follows.isFollowing(request.id) { try await store.follows.unfollow(request.id) }
                else { try await store.follows.follow(request.id) }
            }
            catch { self.error = CloudKitErrorHandler.classify(error) }
        }
    }

    private func sendReply() {

        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return }

        isSendingReply = true

        Task {

            do {

                if store.container.isDeveloper {

                    try await store.comments.addDeveloperComment(to: request, body: text)
                }
                else {

                    try await store.comments.addUserComment(to: request, body: text)
                }

                reply = ""
            }
            catch {

                self.error = CloudKitErrorHandler.classify(error)
            }

            isSendingReply = false
        }
    }

    private func submitReport() {

        showingReport = false

        Task {

            do {

                try await store.reports.report(request.id, category: reportCategory)

                // Reported content stops showing for the reporter immediately, so there is nothing
                // left on this screen to look at.
                dismiss()
            }
            catch {

                self.error = CloudKitErrorHandler.classify(error)
            }
        }
    }

    private func markComplete() async {

        do {

            try await store.requests.markComplete(request)

            request.status = .complete
        }
        catch {

            self.error = CloudKitErrorHandler.classify(error)
        }
    }
}


struct CommentRow: View {

    let comment: FeedbackComment

    var body: some View {

        VStack(alignment: .leading, spacing: 6) {

            HStack {

                Image(systemName: comment.isDeveloper ? "checkmark.seal.fill" : "person.circle.fill")
                    .foregroundStyle(comment.isDeveloper ? Color.accentColor : Color.secondary)

                Text(comment.isDeveloper ? "Developer" : "Author")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(comment.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(comment.body)
        }
        .padding(.vertical, 2)
    }
}


/// Creator edit. Only reachable while `FeedbackStore.canEdit` allows it.
struct EditRequestView: View {

    @Environment(\.dismiss) private var dismiss

    let store: FeedbackStore
    let request: FeedbackRequest
    let onSave: (FeedbackRequest) -> Void

    @State private var title: String
    @State private var body_: String
    @State private var isSaving = false
    @State private var error: FeedbackError?

    init(store: FeedbackStore, request: FeedbackRequest, onSave: @escaping (FeedbackRequest) -> Void) {

        self.store = store
        self.request = request
        self.onSave = onSave

        _title = State(initialValue: request.title)
        _body_ = State(initialValue: request.body)
    }

    var body: some View {

        NavigationStack {

            Form {

                Section { TextField("Title", text: $title) } header: { Text("Title") }

                Section {

                    FeedbackTextEditor(placeholder: "Details", text: $body_)

                } header: { Text("Details") }

                if let error { Section { FeedbackErrorBanner(error: error, retry: nil) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit")
            .inlineNavigationTitle()
            .toolbar {

                ToolbarItem(placement: toolbarLeadingPlacement) {

                    Button("Cancel", role: .cancel) { dismiss() }
                }

                ToolbarItem(placement: toolbarTrailingPlacement) {

                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || isSaving)
                }
            }
        }
    }

    private func save() {

        isSaving = true

        Task {

            do {

                try await store.requests.update(request, title: title, body: body_)

                var updated = request
                updated.title = title
                updated.body = body_

                onSave(updated)
                dismiss()
            }
            catch {

                self.error = CloudKitErrorHandler.classify(error)
            }

            isSaving = false
        }
    }
}
