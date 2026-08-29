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
        // Never a `NavigationSplitView` of its own, regardless of `embedsNavigationStack` - the only
        // known caller embeds this in another split view's detail column (via `FeedbackBoardView`'s
        // toolbar menu), and nesting one split view inside another's detail is not supported. A plain
        // `HStack` gets the same side-by-side look without being one, so it nests cleanly. See the
        // matching fix and its longer explanation on `FeedbackBoardView.container`.
        HStack(spacing: 0) {

            queueList
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)

            Divider()

            Group {

                if let selected = selectedRequest {

                    // Its own `NavigationStack` so its toolbar and refresh action stay scoped to this
                    // pane rather than merging into the queue list's.
                    NavigationStack { PortalRequestView(store: store, request: selected) }
                        .id(selected.id)
                }
                else {

                    FeedbackEmptyState(symbol: "hammer",
                                       title: "Nothing selected",
                                       message: "Pick a request from the list.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

#if os(macOS)
        // Plain content, not `.searchable`/`.feedbackRefreshable` - nested this deep inside a host's
        // own split view detail column, macOS has been seen merging and re-rendering those per-column
        // toolbar contributions, producing duplicate search fields and refresh buttons. See the
        // matching fix on `FeedbackBoardView.board`.
        VStack(spacing: 0) {
            
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

                    versionMenu

                    Button(action: { Task { await store.load() } }) {

                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                }
                
                listFilter
            }
            .padding([.horizontal, .top], 12)

            portalList
        }
        .ownedNavigationTitle("Dev Portal", ownsStack: embedsNavigationStack)
#else
        portalList
            .navigationTitle("Dev Portal")
            .searchable(text: $searchText, prompt: Text("Search"))
            .feedbackRefreshable { await store.load() }
            .toolbar {

                if !availableVersions.isEmpty {

                    ToolbarItem(placement: toolbarTrailingPlacement) { versionMenu }
                }
            }
#endif
    }

    @ViewBuilder private var portalList: some View {

        // No `selection:` on the Mac - rows are buttons that set `selection` themselves (§ row(for:)).
#if os(macOS)
        List { portalRows }
#else
        List(selection: $selection) { portalRows }
#endif
    }
    
    @ViewBuilder private var listFilter: some View {
        
        // No visible "Queue" label - the row has zero insets so the control can span it, and a
        // leading label ate into that width and pushed the segments off-centre. Open/Reported/
        // Images/All read as a queue switch on sight, exactly as the board's filter does.
        Picker("", selection: $queue) {

            ForEach(PortalQueue.allCases, id: \.self) {

                Label($0.localised, systemImage: $0.symbolName).tag($0)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityLabel(Text("Triage queue"))
        .frame(maxWidth: .infinity, minHeight: 50)
    }

    @ViewBuilder private var portalRows: some View {

#if os(iOS)
        Section {
            
            listFilter
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .compactSectionSpacing()
#endif

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

    /// Lives in the header rather than as a list row - it is a filter over the list, and as a row it
    /// pushed the requests themselves below the fold before a single one had been read.
    @ViewBuilder private var versionMenu: some View {

        if !availableVersions.isEmpty {

            Picker("App version", selection: $versionFilter) {

                Text("All versions").tag(String?.none)

                ForEach(availableVersions, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden()
            .accessibilityLabel(Text("Filter by app version"))
            .help("Filter by app version")
#if os(macOS)
            .fixedSize()
#endif
        }
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
        // A button, not a selectable row - `List(selection:)` draws its own highlight and focus ring,
        // which is the mismatched shape that showed up behind a selected row. See the matching change
        // on `FeedbackBoardView.row(for:)`.
        Button(action: { selection = request.id }) {

            content
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(selection == request.id ? Color.accentColor.opacity(0.18) : Color.clear)
        .accessibilityAddTraits(selection == request.id ? [.isSelected] : [])
        .rowActions { rowMenu(for: request) }
        #else
        NavigationLink { PortalRequestView(store: store, request: request) }
            label: { content }
            .rowActions { rowMenu(for: request) }
        #endif
    }

    @ViewBuilder private func rowMenu(for request: FeedbackRequest) -> some View {

        if request.moderation == .hidden {

            Button(action: { Task { await store.moderation.unhide(request) } },
                   label: { Label("Unhide", systemImage: "eye") })
        }
        else {

            Button(role: .destructive, action: { Task { await store.moderation.hide(request) } },
                   label: { Label("Hide", systemImage: "eye.slash") })
        }

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
