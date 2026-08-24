//
//  MetadataDisclosureView.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

/// Exactly what will be attached, in full (§9.3).
///
/// No summarising and no hidden keys - if a developer attaches something through `FeedbackPrefill`,
/// the person submitting gets to read it before they send it.
struct MetadataDisclosureView: View {

    let environment: DeviceEnvironment
    let metadata: [String: String]

    var body: some View {

        List {

            Section {

                ForEach(environment.disclosureEntries, id: \.label.key) { entry in

                    LabeledContent(String(localized: entry.label), value: entry.value)
                }

            } header: { Text("Device information") }
              footer: { Text("Visible to anyone using this app, the same as on any public issue tracker.") }

            if metadata.isEmpty {

                Section {

                    Text("This app is not attaching any additional information.")
                        .foregroundStyle(.secondary)
                }
            }
            else {

                Section {

                    ForEach(metadata.keys.sorted(), id: \.self) { key in

                        LabeledContent(key, value: metadata[key] ?? "")
                    }

                } header: { Text("Added by this app") }
                  footer: { Text("Stored privately. Only the developer and you can read this.") }
            }
        }
        .navigationTitle("What gets sent")
        .inlineNavigationTitle()
    }
}
