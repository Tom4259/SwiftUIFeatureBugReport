//
//  FeedbackBadges.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

struct TypeBadge: View {

    let type: FeedbackType

    var body: some View {

        Text(type.localised)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(type == .feature ? Color.blue : Color.red, in: Capsule())
            .foregroundStyle(.white)
    }
}


struct StatusBadge: View {

    let status: RequestStatus

    var body: some View {

        Label(status.localised, systemImage: status.symbolName)
            .font(.caption2)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(status.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(status.tint)
    }
}


struct LabelChip: View {

    let name: String

    var body: some View {

        Text(name)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(labelName: name), in: Capsule())
            .foregroundStyle(.white)
    }
}


/// The vote control.
///
/// Its accessibility label announces the count and whether this user has voted - VoiceOver reading
/// "button" over a bare arrow tells you nothing about either.
struct VoteButton: View {

    let count: Int
    let hasVoted: Bool
    let isBusy: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {

        Button(action: action) {

            HStack(spacing: 4) {

                if isBusy {

                    ProgressView()
                        .controlSize(.small)
                }
                else {

                    Image(systemName: hasVoted ? "hand.thumbsup.fill" : "hand.thumbsup")
                }

                Text(count.formatted(.number))
            }
            .font(.caption)
            .foregroundStyle(hasVoted ? Color.green : Color.accentColor)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        // Tappable while voted: the button toggles, so a mis-tap or a change of mind is recoverable.
        .disabled(isBusy || !isEnabled)
        .accessibilityLabel(hasVoted
                            ? Text("Voted. ^[\(count) vote](inflect: true)")
                            : Text("Vote. ^[\(count) vote](inflect: true)"))
        .accessibilityHint(hasVoted ? Text("Withdraws your vote") : Text("Adds your vote"))
        .accessibilityAddTraits(hasVoted ? [.isSelected] : [])
    }
}


/// "Fixed in 2.1" - the single most useful thing to tell someone looking at a completed request,
/// and the line that stops "then why is it still broken for me?" arriving as a support message.
///
/// Falls back to a plain "Fixed" when the developer has not recorded a version.
struct ResolvedVersionBadge: View {

    let version: String

    var body: some View {

        Group {

            if version.isEmpty { Label("Fixed", systemImage: "checkmark.circle.fill") }
            else { Label("Fixed in \(version)", systemImage: "checkmark.circle.fill") }
        }
        .font(.caption2)
        .foregroundStyle(.green)
    }
}


/// Warns that the portal is pointed at the Development database.
///
/// Only shown for Development, because that is the only case that needs saying: an empty Production
/// board and an empty Development board look identical, and the difference between "nobody has
/// reported anything" and "you are looking at the wrong database" is worth a coloured banner.
struct EnvironmentBanner: View {

    let containerIdentifier: String

    var body: some View {

        HStack(alignment: .firstTextBaseline, spacing: 12) {

            Image(systemName: CloudKitEnvironment.development.symbolName)
                .foregroundStyle(CloudKitEnvironment.development.tint)

            VStack(alignment: .leading, spacing: 2) {

                Text(CloudKitEnvironment.development.localised)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CloudKitEnvironment.development.tint)

                Text(containerIdentifier)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("Feedback from the App Store lives in Production and will not appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}


/// States the moderation situation at the top of a request in the portal.
///
/// Without it, hidden and auto-hidden requests look exactly like visible ones once you are inside
/// them - you can reply, set a status and announce a fix on something no user can see. The auto-hidden
/// case matters most: `moderation` is still `visible`, so nothing on the record says it is hidden;
/// only the report count crossing the threshold does, and that is computed client-side.
struct ModerationBanner: View {

    let moderation: ModerationState
    let reportCount: Int
    let threshold: Int

    private var state: (title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String, tint: Color)? {

        switch moderation {

        case .hidden:
            return ("Hidden from everyone",
                    "No user can see this request. Unhide it from the menu to bring it back.",
                    "eye.slash.fill", .red)

        case .visible where reportCount >= threshold:
            return ("Automatically hidden",
                    "^[\(reportCount) report](inflect: true) reached the threshold of \(threshold), so users can no longer see this. Clear reports to restore it.",
                    "exclamationmark.triangle.fill", .orange)

        case .approved:
            return ("Reports cleared",
                    "Visible to everyone. Further reports will not hide it automatically.",
                    "checkmark.shield.fill", .green)

        default:
            return nil
        }
    }

    var body: some View {

        if let state {

            HStack(alignment: .firstTextBaseline, spacing: 12) {

                Image(systemName: state.symbol)
                    .foregroundStyle(state.tint)

                VStack(alignment: .leading, spacing: 2) {

                    Text(state.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(state.tint)

                    Text(state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}
