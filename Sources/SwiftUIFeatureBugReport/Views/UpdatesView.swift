//
//  UpdatesView.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

/// Activity on requests this user created or voted on.
///
/// Optional, and opt-in by the integrator - it is a plain query with no subscription setup behind it,
/// so it works whether or not push notifications were ever configured.
public struct UpdatesView: View {

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

            NavigationStack { updates }
        }
        else {

            updates
        }
    }

    @ViewBuilder private var updates: some View {

        List {

            if store.container.identityState == .resolving {

                Section { IdentityResolvingView() }
            }
            else if !store.canWrite {

                Section { ReadOnlyNotice() }
            }
            else if store.activity.isLoading && store.activity.activity.isEmpty {

                Section { ProgressView("Loading…").frame(maxWidth: .infinity) }
            }
            else if store.activity.activity.isEmpty {

                Section {

                    FeedbackEmptyState(symbol: "bell",
                                       title: "No updates",
                                       message: "Anything you posted or voted for will show up here when it changes.")
                }
            }
            else {

                ForEach(store.activity.activity) { item in

                    HStack(alignment: .top, spacing: 10) {

                        Image(systemName: item.kind.symbolName)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 3) {

                            Text(item.requestTitle)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)

                            Text(item.message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Text(item.createdAt, format: .relative(presentation: .named))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .ownedNavigationTitle("Updates", ownsStack: embedsNavigationStack)
        .feedbackRefreshable { await store.activity.feed() }
        .task {

            await store.activity.feed()
            store.activity.markAllSeen()
        }
    }
}
