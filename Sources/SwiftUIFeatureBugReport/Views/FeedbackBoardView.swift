//
//  FeedbackBoardView.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import SwiftUI

#if os(macOS)
/// Where the Mac's "more" menu goes.
///
/// A `NavigationLink` here would push onto whatever stack the *host* owns, and the one known host
/// puts this in a Settings window's detail column - so the push replaced the whole settings pane,
/// took its Done button with it, and left the sidebar highlighting a tab that was no longer on
/// screen. Swapping this view's own content instead keeps every destination inside the board.
private enum BoardDestination: Hashable, Identifiable {

    case roadmap
    case updates
    case myData
    case portal

    var id: Self { self }

    var title: LocalizedStringKey {

        switch self {

        case .roadmap: return "Roadmap"
        case .updates: return "Updates"
        case .myData: return "My requests"
        case .portal: return "Developer portal"
        }
    }
}
#endif


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

    #if os(macOS)
    /// Non-nil while a "more" destination has replaced the board (§ BoardDestination).
    @State private var destination: BoardDestination?
    #endif

    private let prefill: FeedbackPrefill?

    /// Whether the view brings its own navigation container.

    /// Leave `embedsNavigationStack` on when presenting this somewhere with no navigation of its own -
    /// a sheet, or a split view's detail column. Turn it off when pushing this onto a stack the host
    /// already owns: a stack nested inside another stack's destination makes SwiftUI compare the two
    /// paths against each other, and it traps when their element types differ.
    public init(configuration: FeedbackConfiguration,
                prefill: FeedbackPrefill? = nil) {

        self.store = FeedbackStore(configuration: configuration)
        self.prefill = prefill
    }

    /// Shares one store with the rest of the host app - use this when the board is one tab of several
    /// and you do not want each tab reloading the same tallies.
    public init(store: FeedbackStore,
                prefill: FeedbackPrefill? = nil) {

        self.store = store
        self.prefill = prefill
    }

    public var body: some View {

        container
            .task {

                guard !store.requests.hasLoadedOnce else { return }

                await store.start()
            }
    }

    // MARK: - Layout

    /// Never a `NavigationSplitView` of its own - this is meant to sit inside whatever navigation
    /// container the host already has (a `NavigationStack`, or another `NavigationSplitView`'s
    /// detail column), and nesting one split view inside another is explicitly not supported.
    ///
    /// iOS pushes the detail (there is no room to show both at once). macOS lays list and detail
    /// side by side with a plain `HStack` instead - visually the same as a split view, without being
    /// one, so it nests cleanly inside a host that already owns a real split view.
    @ViewBuilder private var container: some View {

#if os(macOS)
        // A "more" destination takes over the whole tab, with a back button of this view's own, so
        // nothing is ever pushed onto the host's navigation stack (§ BoardDestination).
        if let destination {

            VStack(spacing: 0) {

                HStack(spacing: 8) {

                    Button(action: { self.destination = nil },
                           label: { Label("Back", systemImage: "chevron.backward") })
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                        .help("Back to the board")

                    Text(destination.title)
                        .font(.headline)

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                destinationContent(destination)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        else {

            HStack(spacing: 0) {

                board
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 400)

                Divider()

                Group {

                    if let selected = selectedRequest {

                        // Its own `NavigationStack`, not `false` - a plain `HStack` has no notion of a
                        // "column", so without one this pane's toolbar and refresh action would merge
                        // into the list's instead of staying separate. A stack nested inside another
                        // container is the supported pattern; a split view inside one is not.
                        RequestDetailView(store: store, request: selected, embedsNavigationStack: true)
                            // `RequestDetailView` seeds `@State` from the request it is handed, so without
                            // a per-request identity SwiftUI reuses the same instance across a selection
                            // change and that state keeps showing the previously selected request.
                            .id(selected.id)
                    }
                    else {

                        FeedbackEmptyState(symbol: "sidebar.right",
                                           title: "Nothing selected",
                                           message: "Pick a request from the list.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
#else
        board
#endif
    }

    #if os(macOS)
    /// Every destination is handed `embedsNavigationStack: false` - it is laid out inside this view's
    /// own content, so a stack of its own would nest inside the host's and reintroduce the push.
    @ViewBuilder private func destinationContent(_ destination: BoardDestination) -> some View {

        switch destination {

        case .roadmap: RoadmapView(store: store, embedsNavigationStack: false)
        case .updates: UpdatesView(store: store, embedsNavigationStack: false)
        case .myData: MyDataView(store: store, embedsNavigationStack: false)
        case .portal: DeveloperPortalView(store: store, embedsNavigationStack: false)
        }
    }
    #endif

    @ViewBuilder private var board: some View {

#if os(macOS)
        // Plain content, not `.searchable`/`.toolbar`/`.feedbackRefreshable` - nested this deep inside
        // a host's own split view detail column, macOS has been seen merging and re-rendering those
        // per-column toolbar contributions, which is what was producing duplicate search fields and
        // refresh buttons. Ordinary view content can't "duplicate via toolbar merging" because no
        // toolbar is involved.
        VStack(spacing: 0) {

            macHeader

            Divider()

            listContent
        }
        .navigationTitle("Feedback")
        .sheet(isPresented: $showingForm) {

            FeedbackFormView(store: store, prefill: prefill, initialType: filter == .features ? .feature : .bug)
        }
#else
        listContent
            .navigationTitle("Feedback")
            .searchable(text: $searchText, prompt: Text("Search"))
            .toolbar { toolbarContent }
            .feedbackRefreshable { await store.refresh() }
            .sheet(isPresented: $showingForm) {

                FeedbackFormView(store: store, prefill: prefill, initialType: filter == .features ? .feature : .bug)
            }
#endif
    }

#if os(macOS)
    @ViewBuilder private var macHeader: some View {

        VStack(spacing: 8) {
            
            HStack(spacing: 10) {

                HStack(spacing: 4) {

                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Spacer(minLength: 8)

                Button(action: { Task { await refreshEverything() } }) {

                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")

                // Front and centre rather than buried in the menu - it is the developer's most-used
                // destination on this screen, and it was two clicks and a submenu away.
                if store.container.isDeveloper {

                    Button(action: { destination = .portal }) {

                        Image(systemName: "hammer")
                    }
                    .help("Developer portal")
                }

                Menu {

                    moreMenuItems

                } label: { Image(systemName: "ellipsis.circle") }
                    .menuIndicator(.hidden)
                    .fixedSize()

                Button(action: { showingForm = true }) {

                    Image(systemName: "plus")
                }
                .disabled(!store.canWrite)
                .help("New Feedback")
            }
            .buttonStyle(.borderless)
            
            listFilter
        }
        .padding([.horizontal, .top], 12)
    }
#endif

    @ViewBuilder private var listContent: some View {

        // No `selection:` on the Mac - rows are buttons that set `selection` themselves (§ row(for:)).
#if os(macOS)
        List { listRows }
#else
        List(selection: $selection) { listRows }
#endif
    }
    
    @ViewBuilder private var listFilter: some View {
        
        Section {

            // No separate "Filter" label - "All/Bugs/Features" reads as a filter on sight, and a
            // segmented control spanning the row's full width is unambiguous on its own.
            Picker("", selection: $filter) {

                ForEach(BoardFilter.allCases, id: \.self) { Text($0.localised).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityLabel(Text("Filter by type"))
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .compactSectionSpacing()
    }

    @ViewBuilder private var listRows: some View {
        
#if os(iOS)
        listFilter
#endif

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

    @ViewBuilder private func row(for request: FeedbackRequest) -> some View {

        let content = RequestRow(request: request,
                                 voteCount: store.votes.tally(for: request.id),
                                 hasVoted: store.votes.hasVoted(on: request.id),
                                 isVoting: votingIn.contains(request.id),
                                 canVote: store.canWrite,
                                 showsType: filter == .all,
                                 onVote: { vote(on: request) })

#if os(macOS)
        // A button rather than a selectable list row. `List(selection:)` draws its own focus ring and
        // highlight on the row's full rectangle, which sat behind - and a different shape from - the
        // card below, so a selected row picked up a second, squarer outline. Driving `selection`
        // from a button leaves this view's card as the only thing drawn.
        //
        // Each row carries that card itself: a plain `List` on the Mac draws no separators or fills
        // of its own here, so without one the rows run together as a single wall of text.
        Button(action: { selection = request.id }) {

            content
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected(request) ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                                                : AnyShapeStyle(.quaternary),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay {

                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected(request) ? 1.5 : 0)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected(request) ? [.isSelected] : [])
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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

        if store.container.isDeveloper {

            ToolbarItem(placement: toolbarTrailingPlacement) {

                NavigationLink { DeveloperPortalView(store: store, embedsNavigationStack: false) }
                    label: { Label("Developer portal", systemImage: "hammer") }
            }
        }

        ToolbarItem(placement: toolbarTrailingPlacement) {

            Menu {

                moreMenuItems

            } label: { Label("More", systemImage: "ellipsis.circle") }
        }

        ToolbarItem(placement: toolbarTrailingPlacement) {

            Button(action: { showingForm = true },
                   label: { Label("New Feedback", systemImage: "plus") })
                .disabled(!store.canWrite)
        }
    }

    /// Shared between iOS's toolbar menu and macOS's plain header menu (§ macHeader) - one set of
    /// destinations, not two copies that can drift apart.
    @ViewBuilder private var moreMenuItems: some View {

        Picker("Sort", selection: $sort) {

            ForEach(BoardSort.allCases, id: \.self) { Text($0.localised).tag($0) }
        }

        Divider()

#if os(macOS)
        // Buttons, not links - see `BoardDestination` for why nothing here may push.
        Button(action: { destination = .roadmap },
               label: { Label("Roadmap", systemImage: "map") })

        Button(action: { destination = .updates },
               label: { Label("Updates", systemImage: "bell") })

        Button(action: { destination = .myData },
               label: { Label("My requests", systemImage: "person.crop.circle") })

#else
        NavigationLink { RoadmapView(store: store, embedsNavigationStack: false) }
            label: { Label("Roadmap", systemImage: "map") }

        NavigationLink { UpdatesView(store: store, embedsNavigationStack: false) }
            label: { Label("Updates", systemImage: "bell") }

        NavigationLink { MyDataView(store: store, embedsNavigationStack: false) }
            label: { Label("My requests", systemImage: "person.crop.circle") }

#endif
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

                Button("Send Feedback") { showingForm = true }
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

    /// The board *and* whatever is open beside it - the detail pane no longer carries a refresh of
    /// its own, so this one button has to leave the whole tab up to date.
    private func refreshEverything() async {

        await store.refresh()

        if let selection { await store.comments.load(for: selection) }
    }

    private func isSelected(_ request: FeedbackRequest) -> Bool { selection == request.id }

    private var selectedRequest: FeedbackRequest? {

        guard let selection else { return nil }

        return store.requests.requests.first { $0.id == selection }
    }

    // MARK: - Data

    /// Filtering and searching happen over the already-loaded board rather than as new queries - the
    /// fetch is capped at 500 records, so this is cheap, and it keeps typing off the network.
    private var displayedRequests: [FeedbackRequest] {

        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = store.boardRequests.filter { request in

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
