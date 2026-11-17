import SwiftUI

extension HAEntity {
    /// Accent colour for the "on" state of a tile.
    var tint: Color {
        switch kind {
        case .light:
            // Use the bulb's colour unless it is (almost) white, which would be invisible as a tint.
            if let rgb = rgbColor, min(rgb.red, rgb.green, rgb.blue) < 0.75 {
                return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
            }
            return .yellow
        case .climate: return hvacAction == "cooling" || state == "cool" ? .cyan : .orange
        case .cover: return .indigo
        case .toggle: return .green
        case .scene: return .purple
        case .sensor: return .teal
        case .unsupported: return .gray
        }
    }
}
