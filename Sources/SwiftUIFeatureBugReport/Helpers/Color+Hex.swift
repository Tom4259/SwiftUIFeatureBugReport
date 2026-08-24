//
//  Color+Hex.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

extension Color {

    init(hex: String) {

        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64

        switch hex.count {

        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Stable colour for a developer-managed label, so the same label reads the same everywhere
    /// without the developer having to pick one.
    ///
    /// Hashed by hand rather than with `hashValue` - Swift seeds string hashing per process, so the
    /// stock hash would repaint every label on each launch.
    init(labelName: String) {

        var hash: UInt32 = 2166136261 // FNV-1a

        for byte in labelName.lowercased().utf8 {

            hash = (hash ^ UInt32(byte)) &* 16777619
        }

        self.init(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.75)
    }
}
