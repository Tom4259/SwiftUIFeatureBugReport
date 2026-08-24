//
//  FeedbackBoardView.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import SwiftUI

/// The main board: browse, filter, sort, search, vote inline, and open the form.
public struct FeedbackBoardView: View {

    @State private var store: FeedbackStore
    @State private var retryGate = RetryGate()

    @State private var filter: BoardFilter = .all
    @AppStorage("feedbackBoardSort") private var sort: BoardSort = .votes

    @State private var searchText = ""
    @State private var showingForm = false
    @State private var votingIn: Set<CKRecord.ID> = []
    // Selected by ID, not by value: the struct is replaced wholesale on every reload,
    // so a value-based selection would silently drop each time the board refreshes.
    @State private var selection: CKRecord.ID?

    private let prefill: FeedbackPrefill?

    /// Whether the view brings its own navigation container.
    private let embedsNavigationStack: Bool

    /// Leave `embedsNavigationStack` on when presenting this somewhere with no navigation of its own -
    /// a sheet, or a split view's detail column. Turn it off when pushing this onto a stack the host
    /// already owns: a stack nested inside another stack's destination makes SwiftUI compare the two
    /// paths against each other, and it traps when their element types differ.
    public init(configuration: FeedbackConfiguration,
                prefill: FeedbackPrefill? = nil,
                embedsNavigationStack: Bool = true) {

        self.store = FeedbackStore(configuration: configuration)
        self.prefill = prefill
        self.embedsNavigationStack = embedsNavigationStack
    }

    /// Shares one store with the rest of the host app - use this when the board is one tab of several
    /// and you do not want each tab reloading the same tallies.
    public init(store: FeedbackStore,
                prefill: FeedbackPrefill? = nil,
                embedsNavigationStack: Bool = true) {

        self.store = store
        self.prefill = prefill
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
        // The Mac gets a split view - detail is always visible and there is no back button to go
        // looking for.
        if embedsNavigationStack {

            NavigationSplitView {

                board
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340)

            } detail: {

                if let selected = selectedRequest {

                    RequestDetailView(store: store, request: selected, embedsNavigationStack: false)
                }
                else {

                    FeedbackEmptyState(symbol: "sidebar.right",
                                       title: "Nothing selected",
                                       message: "Pick a request from the list.")
                }
            }
        }
        else {

            board
        }
        #else
        if embedsNavigationStack {

            NavigationStack { board }
        }
        else {

            board
        }
        #endif
    }

    // MARK: - List

    @ViewBuilder private var board: some View {

        listContent
            .navigationTitle("Feedback")
            .searchable(text: $searchText, prompt: Text("Search feedback"))
            .toolbar { toolbarContent }
            .feedbackRefreshable { await store.refresh() }
            .sheet(isPresented: $showingForm) {

                FeedbackFormView(store: store, prefill: prefill, initialType: filter == .features ? .feature : .bug)
            }
    }

    @ViewBuilder private var listContent: some View {

        List(selection: $selection) {

            Section {

                Picker("Filter", selection: $filter) {

                    ForEach(BoardFilter.allCases, id: \.self) { Text($0.localised).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(Text("Filter by type"))
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .compactSectionSpacing()

            if !store.canWrite && store.container.identityState != .resolving {

                Section { ReadOnlyNotice() }
            }

            if let error = store.requests.error {

                Section {

                    FeedbackErrorBanner(error: error,
                                        retry: retryGate.isBlocked ? nil : { Task { await store.load() } })
                }
            }

            // Nothing row-level renders until identity has settled (§6.1).
            if store.container.identityState == .resolving {

                Section { IdentityResolvingView() }
            }
            else if store.requests.isLoading && !store.requests.hasLoadedOnce {

                Section { ProgressView("Loading…").frame(maxWidth: .infinity) }
            }
            else if displayedRequests.isEmpty {

                Section { emptyState }
            }
            else {

                Section { ForEach(displayedRequests) { row(for: $0) } }
            }
        }
    }

    @ViewBuilder private func row(for request: FeedbackRequest) -> some View {

        let content = RequestRow(request: request,
                                 voteCount: store.votes.tally(for: request.id),
                                 hasVoted: store.votes.hasVoted(on: request.id),
                                 isVoting: votingIn.contains(request.id),
                                 canVote: store.canWrite,
                                 showsType: filter == .all,
                                 onVote: { vote(on: request) })

        #if os(macOS)
        content
            .tag(request.id)
            .rowActions { rowMenu(for: request) }
        #else
        NavigationLink { RequestDetailView(store: store, request: request, embedsNavigationStack: false) }
            label: { content }
            .rowActions { rowMenu(for: request) }
        #endif
    }

    @ViewBuilder private func rowMenu(for request: FeedbackRequest) -> some View {

        let voted = store.votes.hasVoted(on: request.id)

        Button(action: { vote(on: request) },
               label: { Label(voted ? "Withdraw vote" : "Vote",
                              systemImage: voted ? "arrow.uturn.down.circle" : "arrow.up.circle") })
            .disabled(!store.canWrite)

        Button(action: { toggleFollow(request) },
               label: { Label(store.follows.isFollowing(request.id) ? "Unfollow" : "Follow",
                              systemImage: store.follows.isFollowing(request.id) ? "bell.slash" : "bell") })
            .disabled(!store.canWrite)

        #if os(macOS)
        // On iOS this is reachable by opening the request; on the Mac the row menu is the only
        // pointer-friendly route to it.
        Button(action: { selection = request.id },
               label: { Label("Open", systemImage: "arrow.forward") })
        #endif
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {

        ToolbarItem(placement: toolbarTrailingPlacement) {

            Menu {

                Picker("Sort", selection: $sort) {

                    ForEach(BoardSort.allCases, id: \.self) { Text($0.localised).tag($0) }
                }

                Divider()

                NavigationLink { RoadmapView(store: store, embedsNavigationStack: false) }
                    label: { Label("Roadmap", systemImage: "map") }

                NavigationLink { UpdatesView(store: store, embedsNavigationStack: false) }
                    label: { Label("Updates", systemImage: "bell") }

                NavigationLink { MyDataView(store: store, embedsNavigationStack: false) }
                    label: { Label("My requests", systemImage: "person.crop.circle") }

                if store.container.isDeveloper {

                    Divider()

                    NavigationLink { DeveloperPortalView(store: store, embedsNavigationStack: false) }
                        label: { Label("Developer portal", systemImage: "hammer") }
                }

            } label: { Label("More", systemImage: "ellipsis.circle") }
        }

        ToolbarItem(placement: toolbarTrailingPlacement) {

            Button(action: { showingForm = true },
                   label: { Label("New feedback", systemImage: "plus") })
                .disabled(!store.canWrite)
        }
    }

    @ViewBuilder private var emptyState: some View {

        if !searchText.isEmpty {

            FeedbackEmptyState(symbol: "magnifyingglass",
                               title: "No matches",
                               message: "Nothing on the board matches that.")
        }
        else {

            VStack(spacing: 16) {

                FeedbackEmptyState(symbol: filter == .bugs ? "ladybug.circle" : "lightbulb.circle",
                                   title: "Nothing yet",
                                   message: "Be the first to send some feedback.")

                Button("Send feedback") { showingForm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canWrite)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func toggleFollow(_ request: FeedbackRequest) {

        guard store.canWrite else { return }

        Task {

            if store.follows.isFollowing(request.id) { try? await store.follows.unfollow(request.id) }
            else { try? await store.follows.follow(request.id) }
        }
    }

    private var selectedRequest: FeedbackRequest? {

        guard let selection else { return nil }

        return store.requests.requests.first { $0.id == selection }
    }

    // MARK: - Data

    /// Filtering and searching happen over the already-loaded board rather than as new queries - the
    /// fetch is capped at 500 records, so this is cheap, and it keeps typing off the network.
    private var displayedRequests: [FeedbackRequest] {

        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = store.visibleRequests.filter { request in

            guard filter.matches(request.type) else { return false }

            guard !needle.isEmpty else { return true }

            return request.title.lowercased().contains(needle) || request.body.lowercased().contains(needle)
        }

        switch sort {

        case .votes:
            return filtered.sorted { store.votes.tally(for: $0.id) > store.votes.tally(for: $1.id) }

        case .mostRecent:
            return filtered.sorted { $0.lastActivityAt > $1.lastActivityAt }
        }
    }

    /// Toggles. Voting goes through the store so it also follows the request.
    private func vote(on request: FeedbackRequest) {

        guard store.canWrite, !votingIn.contains(request.id) else { return }

        votingIn.insert(request.id)

        Task {

            do {

                if store.votes.hasVoted(on: request.id) {

                    try await store.votes.unvote(on: request.id)
                }
                else {

                    try await store.vote(on: request)
                }
            }
            catch { retryGate.note(error) }

            votingIn.remove(request.id)
        }
    }
}
