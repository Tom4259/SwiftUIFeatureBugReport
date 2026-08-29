//
//  RequestRow.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

struct RequestRow: View {

    let request: FeedbackRequest
    let voteCount: Int
    let hasVoted: Bool
    let isVoting: Bool
    let canVote: Bool
    let showsType: Bool
    let onVote: () -> Void

    var body: some View {

        VStack(alignment: .leading, spacing: 8) {

            HStack(alignment: .firstTextBaseline) {

                Text(request.title)
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if showsType { TypeBadge(type: request.type) }
            }

            if !request.body.isEmpty {

                Text(request.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !request.labels.isEmpty || request.status != .open || request.moderation == .hidden {

                HStack(spacing: 6) {

                    if request.status == .complete { ResolvedVersionBadge(version: request.resolvedInVersion) }
                    else if request.status != .open { StatusBadge(status: request.status) }

                    if request.moderation == .hidden { HiddenBadge() }

                    ForEach(request.labels.prefix(2), id: \.self) { LabelChip(name: $0) }
                }
            }

            HStack {

                VoteButton(count: voteCount,
                           hasVoted: hasVoted,
                           isBusy: isVoting,
                           isEnabled: canVote,
                           action: onVote)

                if request.imageState == .pending {

                    Label("Image in review", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(request.lastActivityAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        // The vote button stays its own element; the rest of the row reads as one label.
        .accessibilityElement(children: .contain)
    }
}


/// Shown while identity is still resolving.
///
/// Rendering rows before `identityState` is settled means every one of them reads "not mine, not
/// voted" and then visibly flips a moment later, which looks like a bug even though it is not.
struct IdentityResolvingView: View {

    var body: some View {

        VStack(spacing: 12) {

            ProgressView()

            Text("Checking your iCloud account…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 32)
    }
}


/// The read-only state. Not an error - browsing and reading work fine without an account; only
/// writing needs one, because CloudKit public-database writes require a signed-in iCloud account.
struct ReadOnlyNotice: View {

    var body: some View {

        HStack(alignment: .firstTextBaseline, spacing: 12) {

            Image(systemName: "icloud.slash")

            VStack(alignment: .leading, spacing: 2) {

                Text("Read-only")
                    .font(.subheadline.weight(.semibold))

                Text("Sign in to iCloud in Settings to post, vote or comment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}


struct FeedbackEmptyState: View {

    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {

        VStack(spacing: 12) {

            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}


struct FeedbackErrorBanner: View {

    let error: FeedbackError

    /// `nil` while a rate limit is still running - a user able to spam-tap retry into an active rate
    /// limit only extends it.
    let retry: (() -> Void)?

    var body: some View {

        VStack(alignment: .leading, spacing: 8) {

            Label {

                Text(error.localizedDescription)
                    .font(.footnote)

            } icon: { Image(systemName: "exclamationmark.triangle") }

            if let retry {

                Button("Try again", action: retry)
                    .font(.footnote)
            }
        }
        .foregroundStyle(.secondary)
    }
}
