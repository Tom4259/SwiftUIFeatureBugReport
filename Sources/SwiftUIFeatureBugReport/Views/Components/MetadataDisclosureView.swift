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
    
    @Binding var includeMetadata: Bool

    let environment: DeviceEnvironment
    let metadata: [String: String]

    var body: some View {

        List {

            Section {

                ForEach(environment.disclosureEntries, id: \.label.key) { entry in

                    LabeledContent(String(localized: entry.label), value: entry.value)
                }

            } header: { Text("Device information") }
            footer: { Text("Visible to everyone") }

            if metadata.isEmpty {

                Section {

                    Text("This app is not attaching any additional information")
                        .foregroundStyle(.secondary)
                }
            }
            else {
                
                // Its own section, not sharing a row with the disclosure link above - this only ever
                // holds back the developer-added extras. Device information always goes regardless of this
                // toggle; it is the minimum needed to triage a report, and matches any public issue tracker.
                Section {

                    Toggle("Include additional information", isOn: $includeMetadata)

                } header: { Text("Additional information") }
                  footer: { Text("Turning this off still sends device information, just not the additional information this app attached") }

                
                Section(content: {
                    
                    ForEach(metadata.keys.sorted(), id: \.self) { key in

                        LabeledContent(key, value: metadata[key] ?? "")
                    }
                    
                }, footer: { Text("Only the developer can see this") })
                .opacity(includeMetadata ? 1 : 0.5)
            }
        }
        .navigationTitle("What gets included")
        .inlineNavigationTitle()
    }
}
