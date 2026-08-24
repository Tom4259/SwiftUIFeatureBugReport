//
//  RoadmapView.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

/// The board grouped by status rather than sorted by votes - planned, in progress, done.
public struct RoadmapView: View {

    @State private var store: FeedbackStore

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

            NavigationStack { roadmap }
        }
        else {

            roadmap
        }
    }

    @ViewBuilder private var roadmap: some View {

        List {

            if store.container.identityState == .resolving {

                Section { IdentityResolvingView() }
            }
            else if upcoming.allSatisfy({ $0.requests.isEmpty }) && shipped.isEmpty {

                Section {

                    FeedbackEmptyState(symbol: "map",
                                       title: "Nothing planned yet",
                                       message: "Requests appear here once they're picked up.")
                }
            }
            else {

                // Everything still in flight, grouped by status.
                ForEach(upcoming, id: \.status) { group in

                    if !group.requests.isEmpty {

                        Section {

                            ForEach(group.requests) { row(for: $0) }

                        } header: { Label(group.status.localised, systemImage: group.status.symbolName) }
                    }
                }

                // Everything shipped, grouped by the version it shipped in - newest first. This is the
                // "what did I get in the update I have not installed yet" view, without being a second
                // screen to maintain.
                ForEach(shipped, id: \.version) { group in

                    Section {

                        ForEach(group.requests) { row(for: $0) }

                    } header: {

                        if group.version.isEmpty { Label("Completed", systemImage: "checkmark.circle.fill") }
                        else { Label("Fixed in \(group.version)", systemImage: "checkmark.circle.fill") }
                    }
                }
            }
        }
        .navigationTitle("Roadmap")
        .feedbackRefreshable { await store.load() }
        .task {

            guard !store.requests.hasLoadedOnce else { return }

            await store.start()
        }
    }

    @ViewBuilder private func row(for request: FeedbackRequest) -> some View {

        NavigationLink {

            RequestDetailView(store: store, request: request, embedsNavigationStack: false)

        } label: {

            VStack(alignment: .leading, spacing: 4) {

                Text(request.title)
                    .font(.subheadline)
                    .lineLimit(2)

                Text("^[\(store.votes.tally(for: request.id)) vote](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var upcoming: [(status: RequestStatus, requests: [FeedbackRequest])] {

        let visible = store.visibleRequests

        return [RequestStatus.updatePending, .inProgress].map { status in

            (status, visible.filter { $0.status == status }
                .sorted { store.votes.tally(for: $0.id) > store.votes.tally(for: $1.id) })
        }
    }

    /// Completed requests bucketed by `resolvedInVersion`.
    ///
    /// Sorted with `.numeric`, which is the only comparison that gets version strings right - plain
    /// string ordering puts "2.9" above "2.10" and "1.0.1" below "1.0". Requests a developer completed
    /// without recording a version fall into a trailing unlabelled group rather than disappearing.
    private var shipped: [(version: String, requests: [FeedbackRequest])] {

        let completed = store.visibleRequests.filter { $0.status == .complete }

        guard !completed.isEmpty else { return [] }

        let buckets = Dictionary(grouping: completed, by: \.resolvedInVersion)

        return buckets.keys
            .sorted { lhs, rhs in

                // The unversioned bucket always sits last.
                if lhs.isEmpty { return false }
                if rhs.isEmpty { return true }

                return lhs.compare(rhs, options: .numeric) == .orderedDescending
            }
            .map { version in

                (version, (buckets[version] ?? [])
                    .sorted { store.votes.tally(for: $0.id) > store.votes.tally(for: $1.id) })
            }
    }
}
