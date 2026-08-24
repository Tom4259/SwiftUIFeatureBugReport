//
//  ImageAttachmentPicker.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

#if os(iOS)
import PhotosUI
#endif

/// One control, with the platform branch **inside** it, so no call site needs a conditional.
///
/// The two platforms genuinely differ here: iOS screenshots land in Photos, Mac screenshots land on
/// the Desktop. A `PhotosPicker` on the Mac would point at the wrong place, and a screenshots-only
/// filter there would be meaningless.
struct ImageAttachmentPicker: View {

    @Binding var imageData: [Data]

    @State private var isImporting = false

    #if os(iOS)
    @State private var selections: [PhotosPickerItem] = []
    #endif

    private var remaining: Int { max(0, FeedbackRequest.maximumImages - imageData.count) }

    private var hasAttachments: Bool { !imageData.isEmpty }

    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            if !imageData.isEmpty { thumbnails }

            if remaining > 0 { picker }
            else {

                Text("Maximum of \(FeedbackRequest.maximumImages) images.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var thumbnails: some View {

        ScrollView(.horizontal, showsIndicators: false) {

            HStack(spacing: 10) {

                ForEach(Array(imageData.enumerated()), id: \.offset) { index, data in

                    if let preview = previewImage(from: data) {

                        ZStack(alignment: .topTrailing) {

                            preview
                                .resizable()
                                .scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(.rect(cornerRadius: 8))

                            Button(action: { imageData.remove(at: index) },
                                   label: { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.hierarchical) })
                                .buttonStyle(.borderless)
                                .padding(4)
                                .accessibilityLabel(Text("Remove image \(index + 1)"))
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Text("Attached image \(index + 1) of \(imageData.count)"))
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder private var picker: some View {

        #if os(iOS)
        // `PhotosPicker`'s label closure is `@Sendable`, so it can neither read main-actor state nor
        // capture a `LocalizedStringKey` (which is not `Sendable`). Hoisting to a `Bool` satisfies
        // both: the flag is captured, and the key is built from literals inside the closure.
        let attached = hasAttachments

        PhotosPicker(selection: $selections,
                     maxSelectionCount: remaining,
                     matching: .images,
                     photoLibrary: .shared()) {

            Label(attached ? "Add another" : "Attach a screenshot", systemImage: "photo.badge.plus")
        }
        .onChange(of: selections) { _, items in

            guard !items.isEmpty else { return }

            // Snapshot what is already attached before suspending. Reading the binding from inside the
            // task would be a main-actor access from a Sendable closure, and the value could have
            // moved on by the time the loads finish.
            let existing = imageData

            Task { @MainActor in

                var loaded: [Data] = []

                for item in items {

                    if let data = try? await item.loadTransferable(type: Data.self) { loaded.append(data) }
                }

                imageData = Array((existing + loaded).prefix(FeedbackRequest.maximumImages))
                selections = []
            }
        }
        #else
        Button(action: { isImporting = true },
               label: { Label(hasAttachments ? "Add another" : "Attach a screenshot",
                              systemImage: "photo.badge.plus") })
            .fileImporter(isPresented: $isImporting,
                          allowedContentTypes: [.image],
                          allowsMultipleSelection: true) { result in

                guard case .success(let urls) = result else { return }

                var loaded: [Data] = []

                for url in urls.prefix(remaining) {

                    // A file chosen through the importer arrives security-scoped.
                    let didStartAccess = url.startAccessingSecurityScopedResource()

                    defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

                    if let data = try? Data(contentsOf: url) { loaded.append(data) }
                }

                imageData = Array((imageData + loaded).prefix(FeedbackRequest.maximumImages))
            }
        #endif
    }

    private func previewImage(from data: Data) -> Image? {

        #if canImport(UIKit)
        UIImage(data: data).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        NSImage(data: data).map { Image(nsImage: $0) }
        #else
        nil
        #endif
    }
}


/// Read-only gallery for a request's approved images.
struct ImageGallery: View {

    let urls: [URL]

    var body: some View {

        if urls.count == 1, let image = FeedbackImage.image(at: urls[0]) {

            image
                .resizable()
                .scaledToFit()
                .accessibilityLabel(Text("Image attached to this request"))
        }
        else {

            ScrollView(.horizontal, showsIndicators: false) {

                HStack(spacing: 10) {

                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in

                        if let image = FeedbackImage.image(at: url) {

                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(.rect(cornerRadius: 8))
                                .accessibilityLabel(Text("Image \(index + 1) of \(urls.count)"))
                        }
                    }
                }
            }
        }
    }
}
