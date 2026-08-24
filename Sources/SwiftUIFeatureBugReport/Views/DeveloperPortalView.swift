//
//  DeveloperPortalView.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import SwiftUI

enum PortalQueue: String, CaseIterable, Hashable {

    case open
    case reported
    case images
    case all

    var localised: LocalizedStringKey {

        switch self {

        case .open: return "Open"
        case .reported: return "Reported"
        case .images: return "Images"
        case .all: return "All"
        }
    }

    var symbolName: String {

        switch self {

        case .open: return "tray"
        case .reported: return "flag"
        case .images: return "photo"
        case .all: return "list.bullet"
        }
    }
}


/// Developer-facing triage.
///
/// Shipping this view in every build is not a security hole: `FeedbackContainer.isDeveloper` decides
/// whether it is *offered*, and the `dev` security role decides whether its writes are *accepted*.
public struct DeveloperPortalView: View {

    @State private var store: FeedbackStore

    @State private var queue: PortalQueue = .open
    @State private var versionFilter: String?
    // Selected by ID, not by value: the struct is replaced wholesale on every reload,
    // so a value-based selection would silently drop each time the board refreshes.
    @State private var selection: CKRecord.ID?
    @State private var searchText = ""

    private let embedsNavigationStack: Bool

    public init(configuration: FeedbackConfiguration, embedsNavigationStack: Bool = true) {

        self.init(store: FeedbackStore(configuration: configuration), embedsNavigationStack: embedsNavigationStack)
    }

    public init(store: FeedbackStore, embedsNavigationStack: Bool = true) {

        self.store = store
        self.embedsNavigationStack = embedsNavigationStack
    }

    public var body: some View {

        container
            .task {

                guard !store.requests.hasLoadedOnce else { return }

                await store.start()
            }
    }

    @ViewBuilder private var container: some View {

        #if os(macOS)
        // Triage without navigating: the queue stays on the left and the request opens beside it.
        if embedsNavigationStack {

            NavigationSplitView {

                queueList.navigationSplitViewColumnWidth(min: 300, ideal: 360)

            } detail: {

                if let selected = selectedRequest {

                    PortalRequestView(store: store, request: selected)
                }
                else {

                    FeedbackEmptyState(symbol: "hammer",
                                       title: "Nothing selected",
                                       message: "Pick a request from the list.")
                }
            }
        }
        else {

            queueList
        }
        #else
        if embedsNavigationStack {

            NavigationStack { queueList }
        }
        else {

            queueList
        }
        #endif
    }

    @ViewBuilder private var queueList: some View {

        List(selection: $selection) {

            // Shown only for Development. In Production there is nothing to warn about, and a
            // permanent "all is well" banner is just chrome above every triage session.
            if store.configuration.environment == .development {

                Section {

                    EnvironmentBanner(containerIdentifier: store.configuration.containerIdentifier)
                }
            }

            Section {

                Picker("Queue", selection: $queue) {

                    ForEach(PortalQueue.allCases, id: \.self) {

                        Label($0.localised, systemImage: $0.symbolName).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .compactSectionSpacing()

            if !availableVersions.isEmpty {

                Section {

                    Picker("App version", selection: $versionFilter) {

                        Text("All versions").tag(String?.none)

                        ForEach(availableVersions, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                }
            }

            if let error = store.moderation.error {

                Section { FeedbackErrorBanner(error: error, retry: nil) }
            }

            if queued.isEmpty {

                Section {

                    FeedbackEmptyState(symbol: queue.symbolName,
                                       title: "Nothing here",
                                       message: "This queue is empty.")
                }
            }
            else {

                Section {

                    ForEach(queued) { request in row(for: request) }

                } header: { Text("^[\(queued.count) request](inflect: true)") }
            }
        }
        .navigationTitle("Portal")
        .searchable(text: $searchText, prompt: Text("Search title, body or author"))
        .feedbackRefreshable { await store.load() }
    }

    @ViewBuilder private func row(for request: FeedbackRequest) -> some View {

        let content = VStack(alignment: .leading, spacing: 4) {

            HStack {

                Text(request.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                Spacer(minLength: 8)

                TypeBadge(type: request.type)
            }

            HStack(spacing: 6) {

                StatusBadge(status: request.status)

                if store.reports.reportCount(for: request.id) > 0 {

                    Label("\(store.reports.reportCount(for: request.id))", systemImage: "flag.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                if request.imageState == .pending {

                    Label("Image", systemImage: "photo")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if request.moderation == .hidden {

                    Label("Hidden", systemImage: "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("^[\(store.votes.tally(for: request.id)) vote](inflect: true) · \(request.environment.versionLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        #if os(macOS)
        content
            .tag(request.id)
            .rowActions { rowMenu(for: request) }
        #else
        NavigationLink { PortalRequestView(store: store, request: request) }
            label: { content }
            .rowActions { rowMenu(for: request) }
        #endif
    }

    @ViewBuilder private func rowMenu(for request: FeedbackRequest) -> some View {

        Button(role: .destructive, action: { Task { await store.moderation.hide(request) } },
               label: { Label("Hide", systemImage: "eye.slash") })

        Button(action: { Task { await store.moderation.approve(request) } },
               label: { Label("Clear reports", systemImage: "checkmark.shield") })
    }

    private var selectedRequest: FeedbackRequest? {

        guard let selection else { return nil }

        return store.requests.requests.first { $0.id == selection }
    }

    // MARK: - Queues

    /// The portal sees hidden and over-threshold requests too - the client-side visibility rule is for
    /// users, not for the person who has to moderate.
    private var queued: [FeedbackRequest] {

        store.requests.requests
            .filter { request in

                guard versionFilter == nil || request.environment.appVersion == versionFilter else { return false }

                // Client-side over the already-loaded board - no extra query, and it can match the
                // author ID, which is what you have when a deletion request arrives by email.
                let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

                if !needle.isEmpty {

                    let haystack = [request.title, request.body, request.creatorID].joined(separator: " ").lowercased()

                    guard haystack.contains(needle) else { return false }
                }

                switch queue {

                // Named for exactly what it filters on, so the tab and the behaviour cannot drift apart.
                case .open: return request.status == .open && request.moderation != .hidden
                case .reported: return store.reports.reportCount(for: request.id) > 0
                case .images: return request.imageState == .pending
                case .all: return true
                }
            }
            .sorted { store.votes.tally(for: $0.id) > store.votes.tally(for: $1.id) }
    }

    private var availableVersions: [String] {

        Array(Set(store.requests.requests.map(\.environment.appVersion)))
            .filter { !$0.isEmpty }
            .sorted(by: >)
    }
}
