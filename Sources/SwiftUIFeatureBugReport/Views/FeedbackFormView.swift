//
//  FeedbackFormView.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import SwiftUI

public struct FeedbackFormView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var store: FeedbackStore

    @State private var type: FeedbackType
    @State private var title: String
    @State private var body_: String
    @State private var imageData: [Data] = []

    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var error: FeedbackError?

    @State private var matches: [FeedbackRequest] = []
    @State private var lastSearchedText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var votedFromSearch: FeedbackRequest?

    private let metadata: [String: String]
    private let embedsNavigationStack: Bool

    /// Fires at four characters or more, debounced. Below that the token search is all noise.
    private static let searchMinimumLength = 4
    private static let searchDebounce = Duration.milliseconds(450)

    public init(configuration: FeedbackConfiguration,
                prefill: FeedbackPrefill? = nil,
                embedsNavigationStack: Bool = true) {

        self.init(store: FeedbackStore(configuration: configuration),
                  prefill: prefill,
                  embedsNavigationStack: embedsNavigationStack)
    }

    public init(store: FeedbackStore,
                prefill: FeedbackPrefill? = nil,
                initialType: FeedbackType = .bug,
                embedsNavigationStack: Bool = true) {

        self.store = store
        self.metadata = prefill?.metadata ?? [:]
        self.embedsNavigationStack = embedsNavigationStack

        _type = State(initialValue: prefill?.type ?? initialType)
        _title = State(initialValue: prefill?.title ?? "")
        _body_ = State(initialValue: prefill?.body ?? "")
    }

    /// Title and body are both required. This stays required whatever a `FeedbackPrefill` supplied -
    /// prefilling is a convenience, not a way to submit an empty report.
    private var canSubmit: Bool {

        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSubmitting
            && store.canWrite
    }

    public var body: some View {

        if embedsNavigationStack {

            NavigationStack { form }
        }
        else {

            form
        }
    }

    @ViewBuilder private var form: some View {

        Form {

            if !store.canWrite && store.container.identityState != .resolving {

                Section { ReadOnlyNotice() }
            }

            Section {

                Picker("Type", selection: $type) {

                    Text("Bug").tag(FeedbackType.bug)
                    Text("Feature").tag(FeedbackType.feature)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(Text("Feedback type"))
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .compactSectionSpacing()

            Section {

                TextField("Title", text: $title)
                    .onChange(of: title) { _, newValue in scheduleSearch(for: newValue) }

            } header: { Text("Title") }

            if !matches.isEmpty { searchResults }

            Section {

                FeedbackTextEditor(placeholder: "What happened, or what would you like to see?",
                                   text: $body_)

            } header: { Text("Details") }

            if store.configuration.allowImageAttachments {

                Section { ImageAttachmentPicker(imageData: $imageData) }
            }

            Section {

                NavigationLink {

                    MetadataDisclosureView(environment: DeviceInfo.current(), metadata: metadata)

                } label: { Label("What gets sent with this", systemImage: "info.circle") }
            }

            Section {

                Button(action: { submit() }) {

                    HStack {

                        Text("Submit")

                        if isSubmitting {

                            Spacer()

                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(!canSubmit)
            }

            if let error {

                Section { FeedbackErrorBanner(error: error, retry: nil) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New feedback")
        .inlineNavigationTitle()
        .toolbar {

            ToolbarItem(placement: toolbarLeadingPlacement) {

                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
        .onDisappear { searchTask?.cancel() }

        .alert("Thanks", isPresented: $showSuccess) {

            Button("OK") { dismiss() }

        } message: { Text("Your feedback has been posted.") }

        .alert("Voted", isPresented: .constant(votedFromSearch != nil)) {

            Button("OK") {

                votedFromSearch = nil
                dismiss()
            }

        } message: {

            Text("Your vote has been added to \"\(votedFromSearch?.title ?? "")\".")
        }
    }

    // MARK: - Search before submit

    /// **Never blocks submission.** Titles overlap innocently, and blocking on a near-match would lose
    /// real reports. This is a nudge with a vote button attached, nothing more.
    @ViewBuilder private var searchResults: some View {

        Section {

            ForEach(matches) { match in

                HStack(alignment: .firstTextBaseline) {

                    VStack(alignment: .leading, spacing: 4) {

                        Text(match.title)
                            .font(.subheadline)
                            .lineLimit(2)

                        // "Fixed in 2.1" is the single most useful thing to tell someone who is about
                        // to file a duplicate, so completed requests are included and flagged.
                        if match.status == .complete {

                            ResolvedVersionBadge(version: match.resolvedInVersion)
                        }
                        else if match.status != .open {

                            StatusBadge(status: match.status)
                        }
                    }

                    Spacer(minLength: 8)

                    VoteButton(count: store.votes.tally(for: match.id),
                               hasVoted: store.votes.hasVoted(on: match.id),
                               isBusy: false,
                               isEnabled: store.canWrite,
                               action: { voteFromSearch(match) })
                }
            }

        } header: { Text("Already reported?") }
          footer: { Text("Vote for an existing one instead, or carry on and submit yours.") }
    }

    private func scheduleSearch(for text: String) {

        searchTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= Self.searchMinimumLength else {

            matches = []
            lastSearchedText = ""

            return
        }

        // Skip if the text has not actually changed since the last search.
        guard trimmed != lastSearchedText else { return }

        searchTask = Task {

            try? await Task.sleep(for: Self.searchDebounce)

            guard !Task.isCancelled else { return }

            let results = await store.requests.search(trimmed)

            guard !Task.isCancelled else { return }

            lastSearchedText = trimmed
            matches = results
        }
    }

    private func voteFromSearch(_ match: FeedbackRequest) {

        Task {

            do {

                try await store.votes.vote(on: match.id)

                votedFromSearch = match
            }
            catch {

                self.error = CloudKitErrorHandler.classify(error)
            }
        }
    }

    // MARK: - Submit

    private func submit() {

        // The button is disabled while a save is in flight. That is the whole of the double-tap
        // defence, and it is the only submission throttle here - a client-side cooldown is bypassable
        // and so protects nothing.
        guard canSubmit else { return }

        isSubmitting = true
        error = nil

        Task {

            do {

                _ = try await store.submit(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                           body: body_.trimmingCharacters(in: .whitespacesAndNewlines),
                                           type: type,
                                           imageData: imageData,
                                           metadata: metadata)

                showSuccess = true
            }
            catch {

                self.error = error as? FeedbackError ?? CloudKitErrorHandler.classify(error)
            }

            isSubmitting = false
        }
    }
}
