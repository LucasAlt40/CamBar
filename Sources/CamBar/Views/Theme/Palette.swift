import AppKit
import SwiftUI

/// Colors of the "Nocturne Guard" design.
enum Palette {
    static let accent = Color(hex: 0x10B981)
    static let accentStrong = Color(hex: 0x059669)
    static let warning = Color(hex: 0xF59E0B)
    static let warningText = Color(hex: 0xFCD34D)
    static let danger = Color(hex: 0xF43F5E)
    static let dangerSoft = Color(hex: 0xFB7185)
    static let dangerText = Color(hex: 0xFDA4AF)

    static let window = Color(hex: 0x0F1319)
    static let titleBar = Color(hex: 0x141922)
    static let sidebar = Color(hex: 0x121720)
    static let panel = Color(hex: 0x171C25)
    static let card = Color(hex: 0x1C2128)
    static let hairline = Color.white.opacity(0.08)

    static let windowNS = NSColor(srgbRed: 0.059, green: 0.075, blue: 0.098, alpha: 1)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
