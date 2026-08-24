//
//  PlatformSupport.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

/// The small platform differences, in one place, so no call site needs a conditional.

var toolbarLeadingPlacement: ToolbarItemPlacement {

    #if os(iOS)
    .topBarLeading
    #else
    .cancellationAction
    #endif
}

var toolbarTrailingPlacement: ToolbarItemPlacement {

    #if os(iOS)
    .topBarTrailing
    #else
    .primaryAction
    #endif
}

extension View {

    /// `navigationBarTitleDisplayMode` does not exist on macOS.
    @ViewBuilder func inlineNavigationTitle() -> some View {

        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// macOS has no pull-to-refresh gesture, so `.refreshable` alone leaves Mac users with no way to
    /// reload. Both platforms get the modifier; only macOS also gets a visible button.
    @ViewBuilder func feedbackRefreshable(action: @escaping @Sendable () async -> Void) -> some View {

        #if os(macOS)
        self
            .refreshable { await action() }
            .toolbar {

                ToolbarItem(placement: .automatic) {

                    Button(action: { Task { await action() } },
                           label: { Label("Refresh", systemImage: "arrow.clockwise") })
                }
            }
        #else
        self.refreshable { await action() }
        #endif
    }

    /// Tightens the space around a bare row - a segmented picker with no background still claims a
    /// full section's worth of spacing, which reads as a double gap next to a banner.
    ///
    /// `listSectionSpacing` is iOS-only; the Mac's list metrics do not have the same problem.
    @ViewBuilder func compactSectionSpacing() -> some View {

        #if os(iOS)
        self.listSectionSpacing(.compact)
        #else
        self
        #endif
    }

    /// Row actions land as a swipe on iOS and a context menu on macOS. Both platforms get the context
    /// menu, so neither loses the action and Mac users are not left hunting for a gesture that has no
    /// pointer equivalent.
    @ViewBuilder func rowActions<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {

        #if os(iOS)
        self
            .swipeActions(edge: .trailing, allowsFullSwipe: false) { content() }
            .contextMenu { content() }
        #else
        self.contextMenu { content() }
        #endif
    }
}


/// `TextEditor` has no placeholder and different insets on each platform, so every multi-line field
/// goes through this rather than repeating the workaround.
struct FeedbackTextEditor: View {

    let placeholder: LocalizedStringKey
    @Binding var text: String
    var minHeight: CGFloat = 110

    var body: some View {

        ZStack(alignment: .topLeading) {

            if text.isEmpty {

                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
        }
    }
}
