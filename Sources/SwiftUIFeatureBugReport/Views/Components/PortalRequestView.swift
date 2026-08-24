//
//  PortalRequestView.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import SwiftUI

/// Triage for one request. Everything a developer can do lives here.
struct PortalRequestView: View {

    @State var store: FeedbackStore
    @State var request: FeedbackRequest

    @State private var metadata: [String: String] = [:]
    @State private var newLabel = ""
    @State private var reply = ""
    @State private var shippedMessage = ""
    @State private var resolvedVersion = ""
    @State private var isLoadingDetail = true

    @State private var showingDelete = false
    @State private var showingBlockAuthor = false
    @State private var showingDeleteAuthorData = false
    @State private var error: FeedbackError?

    var body: some View {

        Form {

            if request.moderation != .visible || store.reports.reportCount(for: request.id) >= store.configuration.reportThreshold {

                Section {

                    ModerationBanner(moderation: request.moderation,
                                     reportCount: store.reports.reportCount(for: request.id),
                                     threshold: store.configuration.reportThreshold)
                }
            }

            Section {

                Text(request.body)

                LabeledContent("Author") {

                    Text(request.creatorID)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                LabeledContent("Votes", value: store.votes.tally(for: request.id).formatted(.number))
                LabeledContent("Reports", value: store.reports.reportCount(for: request.id).formatted(.number))

            if let breakdown = reportBreakdown, !breakdown.isEmpty {

                LabeledContent("Reported as", value: breakdown)
            }

            ForEach(Array(store.reports.reasons(for: request.id).enumerated()), id: \.offset) { _, reason in

                VStack(alignment: .leading, spacing: 2) {

                    Text("Reason given")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(reason)
                        .font(.footnote)
                }
            }

            } header: { Text(request.title) }

            Section {

                NavigationLink {

                    RequestInfoView(request: request, metadata: metadata)

                } label: { Label("Request info", systemImage: "info.circle") }
            }

            statusSection
            labelSection
            imageSection
            moderationSection
            commentSection
            replySection
            notifySection

            if let error { Section { FeedbackErrorBanner(error: error, retry: nil) } }
        }
        .formStyle(.grouped)
        .navigationTitle("Request")
        .inlineNavigationTitle()
        .toolbar {

            ToolbarItem(placement: toolbarTrailingPlacement) {

                Menu {

                    Section {

                        Button(action: { Task { await store.moderation.approve(request); await reloadDetail() } },
                               label: { Label("Clear reports", systemImage: "checkmark.shield") })
                            .disabled(request.moderation == .approved)

                        Button(action: { Task { await store.moderation.hide(request); await reloadDetail() } },
                               label: { Label("Hide from everyone", systemImage: "eye.slash") })
                            .disabled(request.moderation == .hidden)
                    }

                    Section("Danger zone") {

                        Button(role: .destructive, action: { showingDelete = true },
                               label: { Label("Delete this request", systemImage: "trash") })

                        Button(role: .destructive, action: { showingBlockAuthor = true },
                               label: { Label("Hide everything by this author", systemImage: "person.slash") })

                        Button(role: .destructive, action: { showingDeleteAuthorData = true },
                               label: { Label("Delete all of this author's data", systemImage: "person.crop.circle.badge.xmark") })
                    }

                } label: { Label("Options", systemImage: "ellipsis.circle") }
            }
        }
        .modifier(PortalConfirmations(store: store,
                                      request: request,
                                      showingDelete: $showingDelete,
                                      showingBlockAuthor: $showingBlockAuthor,
                                      showingDeleteAuthorData: $showingDeleteAuthorData))
        .task { await reloadDetail() }
    }

    // MARK: - Sections

    @ViewBuilder private var statusSection: some View {

        Section {

            Picker("Status", selection: Binding(get: { request.status },
                                                set: { newStatus in

                request.status = newStatus

                Task {

                    await store.moderation.setStatus(newStatus, on: request)

                    // The service prefills the version on completion; mirror it back into the field.
                    if newStatus == .complete, resolvedVersion.isEmpty {

                        resolvedVersion = DeviceInfo.getAppVersion()
                        request.resolvedInVersion = resolvedVersion
                    }
                }
            })) {

                ForEach(RequestStatus.allCases, id: \.self) { Text($0.localised).tag($0) }
            }

            if request.status == .complete || request.status == .updatePending {

                TextField("Fixed in version", text: $resolvedVersion)
                    .onSubmit { commitVersion() }

                if resolvedVersion != request.resolvedInVersion {

                    Button("Save version") { commitVersion() }
                }
            }

        } header: { Text("Status") }
          footer: {

            Text("Users searching before they submit see \"Fixed in \(resolvedVersion.isEmpty ? "…" : resolvedVersion)\" on this request. Hold it at Update Pending until the build is actually live.")
          }
    }

    @ViewBuilder private var labelSection: some View {

        Section {

            if !request.labels.isEmpty {

                ForEach(request.labels, id: \.self) { label in

                    HStack {

                        LabelChip(name: label)

                        Spacer()

                        Button(role: .destructive, action: { remove(label: label) },
                               label: { Image(systemName: "minus.circle") })
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Remove label \(label)"))
                    }
                }
            }

            HStack {

                TextField("Add a label", text: $newLabel)

                Button("Add") { addLabel() }
                    .disabled(newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

        } header: { Text("Labels") }
    }

    @ViewBuilder private var imageSection: some View {

        if request.imageState != .none {

            Section {

                if !request.imageURLs.isEmpty {

                    ImageGallery(urls: request.imageURLs)
                }
                else if request.imageState != .rejected {

                    // The record says it has an image but no asset came back. Say so rather than
                    // rendering nothing, which is indistinguishable from a layout bug.
                    Label(isLoadingDetail ? "Loading image…" : "No image data on this record",
                          systemImage: isLoadingDetail ? "clock" : "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("State", value: request.imageState.rawValue)

                if request.imageState == .pending {

                    Button(action: { moderateImage(approve: true) },
                           label: { Label("Approve image", systemImage: "checkmark.circle") })
                        .disabled(store.moderation.isWorking)

                    Button(role: .destructive,
                           action: { moderateImage(approve: false) },
                           label: { Label("Reject and delete image", systemImage: "trash") })
                        .disabled(store.moderation.isWorking)
                }

            } header: { Text("Image") }
              footer: { Text("Rejecting deletes the files, not just the flag. Anyone who can query the record can otherwise still fetch them.") }
        }
    }

    /// Re-reads the record afterwards rather than guessing the new state locally, so what is on screen
    /// is always what the server actually stored.
    private func moderateImage(approve: Bool) {

        Task {

            if approve { await store.moderation.approveImage(on: request) }
            else { await store.moderation.rejectImage(on: request) }

            await reloadDetail()
        }
    }

    @ViewBuilder private var moderationSection: some View {

        Section {

            LabeledContent("Moderation", value: request.moderation.rawValue)

            Button(action: { Task { await store.moderation.approve(request); request.moderation = .approved } },
                   label: { Label("Clear reports", systemImage: "checkmark.shield") })
                .disabled(request.moderation == .approved)

            Button(role: .destructive,
                   action: { Task { await store.moderation.hide(request); request.moderation = .hidden } },
                   label: { Label("Hide from everyone", systemImage: "eye.slash") })
                .disabled(request.moderation == .hidden)

        } header: { Text("Moderation") }
          footer: { Text("Clearing moves it to approved, so the existing reports stop counting and it can't silently re-hide itself.") }
    }

    @ViewBuilder private var commentSection: some View {

        Section {

            if store.comments.comments.isEmpty {

                Text("No replies")
                    .foregroundStyle(.secondary)
            }
            else {

                ForEach(store.comments.comments) { comment in

                    VStack(alignment: .leading, spacing: 4) {

                        HStack {

                            Text(comment.isDeveloper ? "Developer" : "User")
                                .font(.caption.weight(.semibold))

                            // A user comment whose author is neither the request's creator nor a
                            // developer should not exist. CloudKit cannot enforce that rule, so the
                            // portal shows it rather than pretending it cannot happen.
                            if !comment.isDeveloper && comment.creatorID != request.creatorID {

                                Label("Not the author", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }

                            Spacer()

                            Text(comment.createdAt, format: .relative(presentation: .named))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Text(comment.body)
                            .font(.footnote)

                        Text(comment.creatorID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

        } header: { Text("Replies") }
    }

    @ViewBuilder private var replySection: some View {

        Section {

            FeedbackTextEditor(placeholder: "Reply as the developer", text: $reply, minHeight: 70)

            Button("Post reply") { postReply() }
                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        } header: { Text("Reply") }
    }

    @ViewBuilder private var notifySection: some View {

        Section {

            TextField("Shipped in 2.1", text: $shippedMessage)

            Button(action: { notifyFollowers() },
                   label: { Label("Notify everyone following", systemImage: "bell.badge") })
                .disabled(shippedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || store.moderation.isWorking)

        } header: { Text("Announce") }
          footer: { Text("Writes one update per follower. Everyone who voted is included.") }
    }

    /// Report categories for this request, most common first, so the queue can be read at a glance.
    private var reportBreakdown: String? {

        let counts = store.reports.categories(for: request.id)

        guard !counts.isEmpty else { return nil }

        return counts
            .sorted { $0.value > $1.value }
            .map { "\($0.key.displayName) (\($0.value))" }
            .joined(separator: ", ")
    }

    // MARK: - Actions

    private func reloadDetail() async {

        isLoadingDetail = true

        request = await store.requests.loadDetail(request)
        resolvedVersion = request.resolvedInVersion
        metadata = await store.moderation.metadata(for: request)

        await store.comments.load(for: request.id)

        isLoadingDetail = false
    }

    private func commitVersion() {

        let version = resolvedVersion.trimmingCharacters(in: .whitespacesAndNewlines)

        guard version != request.resolvedInVersion else { return }

        request.resolvedInVersion = version

        Task { await store.moderation.setResolvedVersion(version, on: request) }
    }

    private func addLabel() {

        let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !label.isEmpty, !request.labels.contains(label) else { return }

        request.labels.append(label)
        newLabel = ""

        Task { await store.moderation.setLabels(request.labels, on: request) }
    }

    private func remove(label: String) {

        request.labels.removeAll { $0 == label }

        Task { await store.moderation.setLabels(request.labels, on: request) }
    }

    private func postReply() {

        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {

            do { try await store.comments.addDeveloperComment(to: request, body: text) }
            catch { self.error = CloudKitErrorHandler.classify(error) }

            reply = ""
        }
    }

    private func notifyFollowers() {

        let message = shippedMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {

            await store.moderation.notifyFollowers(of: request, message: message)

            shippedMessage = ""
        }
    }
}


/// The dialogs behind the danger-zone menu items, factored out so the toolbar builder stays readable.
private struct PortalConfirmations: ViewModifier {

    let store: FeedbackStore
    let request: FeedbackRequest

    @Binding var showingDelete: Bool
    @Binding var showingBlockAuthor: Bool
    @Binding var showingDeleteAuthorData: Bool

    func body(content: Content) -> some View {

        content

            .confirmationDialog("Delete this request?", isPresented: $showingDelete, titleVisibility: .visible) {

                Button("Delete", role: .destructive) { Task { await store.moderation.delete(request) } }
                Button("Cancel", role: .cancel) { }

            } message: { Text("Its votes, replies, reports and metadata go with it. This can't be undone.") }

            .confirmationDialog("Hide everything by this author?",
                                isPresented: $showingBlockAuthor,
                                titleVisibility: .visible) {

                Button("Hide all", role: .destructive) { Task { await store.moderation.hideAll(by: request.creatorID) } }
                Button("Cancel", role: .cancel) { }

            } message: { Text("Every request from this author is hidden from everyone. Nothing is deleted.") }

            .confirmationDialog("Delete all of this author's data?",
                                isPresented: $showingDeleteAuthorData,
                                titleVisibility: .visible) {

                Button("Delete everything", role: .destructive) {

                    Task {

                        await store.accountData.delete(creatorID: request.creatorID)
                        await store.load()
                    }
                }

                Button("Cancel", role: .cancel) { }

            } message: { Text("Use this to honour a deletion request. Their requests are removed along with the votes and replies other people left on them. This can't be undone.") }
    }
}


/// Everything about where a request came from, moved off the triage screen so that screen stays
/// scannable. Nothing here is actionable, which is exactly why it does not belong inline.
struct RequestInfoView: View {

    let request: FeedbackRequest
    let metadata: [String: String]

    var body: some View {

        Form {

            Section {

                LabeledContent("Author") {

                    Text(request.creatorID)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                LabeledContent("Submitted", value: request.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Last activity", value: request.lastActivityAt.formatted(date: .abbreviated, time: .shortened))

            } header: { Text("Origin") }

            Section {

                ForEach(request.environment.disclosureEntries, id: \.label.key) { entry in

                    LabeledContent(String(localized: entry.label), value: entry.value)
                }

            } header: { Text("Environment") }
              footer: { Text("The version this was reported from, which is not the version it gets fixed in.") }

            Section {

                if metadata.isEmpty {

                    Text("None attached")
                        .foregroundStyle(.secondary)
                }
                else {

                    ForEach(metadata.keys.sorted(), id: \.self) { key in

                        LabeledContent(key, value: metadata[key] ?? "")
                    }
                }

            } header: { Text("Private metadata") }
              footer: { Text("Readable only by you and the person who submitted it.") }
        }
        .formStyle(.grouped)
        .navigationTitle("Request info")
        .inlineNavigationTitle()
    }
}
