//
//  FeedbackImage.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Image handling for attachments (§9.6).
///
/// Everything here goes through ImageIO rather than UIKit/AppKit so both platforms take the same
/// path - the only thing that genuinely differs between them is where the user picks the file from.
enum FeedbackImage {

    /// Long edge, in pixels, after downscaling. Comfortably enough to read a screenshot, small enough
    /// that a public container does not fill up with 12-megapixel uploads.
    static let maximumDimension = 1600

    static let compressionQuality = 0.7

    /// Re-encodes and downscales before upload.
    ///
    /// Re-encoding is what strips EXIF - including GPS, should a photo rather than a screenshot ever
    /// get through - and it bounds the payload at the same time. Returns a file URL because that is
    /// what `CKAsset` takes.
    static func prepareForUpload(_ data: Data) throws -> URL {

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {

            throw FeedbackError.imageEncodingFailed
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {

            throw FeedbackError.imageEncodingFailed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("feedback-\(UUID().uuidString)")
            .appendingPathExtension("jpg")

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {

            throw FeedbackError.imageEncodingFailed
        }

        // Only the pixels are copied across - no metadata dictionary is carried over from the source.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { throw FeedbackError.imageEncodingFailed }

        return url
    }

    /// Prepares a batch, stopping at `FeedbackRequest.maximumImages`.
    static func prepareForUpload(_ items: [Data]) throws -> [URL] {

        try items.prefix(FeedbackRequest.maximumImages).map { try prepareForUpload($0) }
    }

    /// `CKAsset.fileURL` points at a temporary file valid only for the lifetime of the operation that
    /// produced it. **Copy it out immediately** - reading it later gives intermittent nil images that
    /// are miserable to debug because they work every time you step through them.
    static func copyOut(_ asset: CKAsset) -> URL? {

        guard let source = asset.fileURL else { return nil }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("feedback-asset-\(UUID().uuidString)")
            .appendingPathExtension(source.pathExtension.isEmpty ? "jpg" : source.pathExtension)

        do {

            try FileManager.default.copyItem(at: source, to: destination)

            return destination
        }
        catch {

            return nil
        }
    }

    static func copyOut(_ assets: [CKAsset]) -> [URL] { assets.compactMap { copyOut($0) } }

    /// Bridges a file URL onto a SwiftUI `Image` without either platform's picker types leaking into
    /// call sites.
    @MainActor static func image(at url: URL) -> Image? {

        guard let data = try? Data(contentsOf: url) else { return nil }

        #if canImport(UIKit)
        guard let platformImage = UIImage(data: data) else { return nil }

        return Image(uiImage: platformImage)
        #elseif canImport(AppKit)
        guard let platformImage = NSImage(data: data) else { return nil }

        return Image(nsImage: platformImage)
        #else
        return nil
        #endif
    }
}
