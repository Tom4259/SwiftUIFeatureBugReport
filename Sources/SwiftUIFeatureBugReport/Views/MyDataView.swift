//
//  MyDataView.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

/// Reached from the board's overflow menu (§9.4). Not on the main screen, not buried three levels
/// down - somewhere a user looking for it will actually find it.
public struct MyDataView: View {

    @State private var store: FeedbackStore
    @State private var showingDeleteConfirmation = false

    private let embedsNavigationStack: Bool

    public init(configuration: FeedbackConfiguration, embedsNavigationStack: Bool = true) {

        self.init(store: FeedbackStore(configuration: configuration), embedsNavigationStack: embedsNavigationStack)
    }

    public init(store: FeedbackStore, embedsNavigationStack: Bool = true) {

        self.store = store
        self.embedsNavigationStack = embedsNavigationStack
    }

    public var body: some View {

        if embedsNavigationStack {

            NavigationStack { myData }
        }
        else {

            myData
        }
    }

    @ViewBuilder private var myData: some View {

        Form {

            if !store.canWrite {

                Section { ReadOnlyNotice() }
            }
            else {

                Section {

                    if store.accountData.isLoading {

                        HStack { ProgressView().controlSize(.small); Text("Counting…") }
                    }
                    else {

                        LabeledContent("Requests", value: store.accountData.counts.requests.formatted(.number))
                        LabeledContent("Votes", value: store.accountData.counts.votes.formatted(.number))
                            .foregroundStyle(.secondary)
                        LabeledContent("Replies", value: store.accountData.counts.comments.formatted(.number))
                        LabeledContent("Reports", value: store.accountData.counts.reports.formatted(.number))
                    }

                } header: { Text("Your activity") }
                  footer: { Text("Tied to your iCloud account. No email address, no sign-up, no account was created for you.") }

                Section {

                    Button(role: .destructive, action: { showingDeleteConfirmation = true },
                           label: { Label("Delete my requests, replies and reports", systemImage: "trash") })
                        .disabled(store.accountData.isDeleting || store.accountData.counts.isEmpty)

                    if store.accountData.isDeleting {

                        HStack { ProgressView().controlSize(.small); Text("Deleting…") }
                    }

                } footer: {

                    Text("Votes you cast on other people's requests aren't included. A vote carries no text, and removing them would quietly change someone else's total. Withdraw a vote from the request itself.")
                }

                if !store.reports.blockedAuthors.isEmpty { blockedSection }
            }

            if let error = store.accountData.error {

                Section { FeedbackErrorBanner(error: error, retry: nil) }
            }
        }
        .formStyle(.grouped)
        .ownedNavigationTitle("My requests", ownsStack: embedsNavigationStack)
        .inlineNavigationTitle()
        .task { await store.accountData.loadCounts() }

        .confirmationDialog("Delete everything you've posted?",
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {

            Button("Delete everything", role: .destructive) {

                Task { await store.deleteMyData() }
            }

            Button("Cancel", role: .cancel) { }

        } message: {

            // Stated plainly rather than buried, in both directions: what goes, and what stays.
            // Deleting a request really does take other people's votes and replies on it with it, and
            // someone about to do that deserves to know before rather than after.
            Text("This permanently deletes your requests, replies and reports. Any votes and replies other people left on your requests go with them. Votes you cast on other people's requests stay, so their totals aren't changed. Withdraw those individually if you want them gone. This can't be undone.")
        }
    }

    @ViewBuilder private var blockedSection: some View {

        Section {

            ForEach(Array(store.reports.blockedAuthors).sorted(), id: \.self) { author in

                HStack {

                    Text(author)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Unblock") { store.reports.unblock(author: author) }
                        .font(.caption)
                }
            }

        } header: { Text("Blocked authors") }
          footer: { Text("Kept on this device only.") }
    }
}
