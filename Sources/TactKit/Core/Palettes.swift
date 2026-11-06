import Foundation

/// One full set of solid colors. Nothing here is translucent, so what's behind a window can't
/// wash out the text. `Tests` hold every set to WCAG contrast ratios.
public struct ThemeColors: Equatable, Sendable {
    public var background: UInt32
    /// Behind the message itself, the most important thing on screen.
    public var card: UInt32
    /// Chips, inputs and other controls.
    public var control: UInt32
    /// The selected segment and keycaps, which sit on top of controls.
    public var selected: UInt32
    public var border: UInt32
    public var text: UInt32
    public var secondaryText: UInt32
    public var accent: UInt32
    public var onAccent: UInt32
    public var added: UInt32
    public var addedBackground: UInt32
    public var removed: UInt32
    public var success: UInt32
}

public struct ColorTheme: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let light: ThemeColors
    public let dark: ThemeColors

    public static let defaultID = "mint"

    public static let all: [ColorTheme] = [
        ColorTheme(
            id: "mint", name: "Mint",
            light: ThemeColors(background: 0xF1F4F6, card: 0xFFFFFF, control: 0xE2E7EB, selected: 0xFFFFFF, border: 0x7C8894,
                               text: 0x11161B, secondaryText: 0x49535D, accent: 0x0F7A66, onAccent: 0xFFFFFF,
                               added: 0x0B4A9E, addedBackground: 0xD3E6FF, removed: 0x9C3D06, success: 0x14663A),
            dark: ThemeColors(background: 0x14181C, card: 0x1F252B, control: 0x2C343C, selected: 0x46515C, border: 0x66727E,
                              text: 0xF7F9FA, secondaryText: 0xC4CCD4, accent: 0x5EDBC0, onAccent: 0x08201A,
                              added: 0xA9D8FF, addedBackground: 0x15375C, removed: 0xFFB08A, success: 0x7FE3A8)),
        ColorTheme(
            id: "ocean", name: "Ocean",
            light: ThemeColors(background: 0xEEF4FB, card: 0xFFFFFF, control: 0xDCE7F4, selected: 0xFFFFFF, border: 0x7488A3,
                               text: 0x0B1B30, secondaryText: 0x41536C, accent: 0x1C62B8, onAccent: 0xFFFFFF,
                               added: 0x0B5A50, addedBackground: 0xCFF1EA, removed: 0x9C3D06, success: 0x14663A),
            dark: ThemeColors(background: 0x0C1626, card: 0x15233A, control: 0x20324F, selected: 0x36507A, border: 0x5D779C,
                              text: 0xF4F8FF, secondaryText: 0xBFCDE2, accent: 0x6CB6FF, onAccent: 0x06182C,
                              added: 0x9BEBD9, addedBackground: 0x0F3A44, removed: 0xFFB08A, success: 0x7FE3A8)),
        ColorTheme(
            id: "plum", name: "Plum",
            light: ThemeColors(background: 0xF5F1FA, card: 0xFFFFFF, control: 0xE8E0F2, selected: 0xFFFFFF, border: 0x877A9B,
                               text: 0x1C1229, secondaryText: 0x524668, accent: 0x6B3FBF, onAccent: 0xFFFFFF,
                               added: 0x0B4A9E, addedBackground: 0xD3E6FF, removed: 0x9C3D06, success: 0x14663A),
            dark: ThemeColors(background: 0x191322, card: 0x261D33, control: 0x372A49, selected: 0x513F6B, border: 0x7A6A96,
                              text: 0xFAF7FF, secondaryText: 0xCFC5E0, accent: 0xC9A7FF, onAccent: 0x1D0E35,
                              added: 0xA9D8FF, addedBackground: 0x22325E, removed: 0xFFB08A, success: 0x7FE3A8)),
        ColorTheme(
            id: "ember", name: "Ember",
            light: ThemeColors(background: 0xFAF4EE, card: 0xFFFFFF, control: 0xF0E5DA, selected: 0xFFFFFF, border: 0x978473,
                               text: 0x261A12, secondaryText: 0x5F4E42, accent: 0xB4500F, onAccent: 0xFFFFFF,
                               added: 0x0B4A9E, addedBackground: 0xD3E6FF, removed: 0xA32020, success: 0x14663A),
            dark: ThemeColors(background: 0x1C1512, card: 0x2A201A, control: 0x3B2D25, selected: 0x57443A, border: 0x826B5C,
                              text: 0xFFF9F5, secondaryText: 0xDCCDC3, accent: 0xFFA45C, onAccent: 0x2B1403,
                              added: 0xA9D8FF, addedBackground: 0x1F3650, removed: 0xFFB3B3, success: 0x7FE3A8)),
        ColorTheme(
            id: "forest", name: "Forest",
            light: ThemeColors(background: 0xF0F6F1, card: 0xFFFFFF, control: 0xDFEBE2, selected: 0xFFFFFF, border: 0x76897C,
                               text: 0x10201A, secondaryText: 0x43574B, accent: 0x2C6E2F, onAccent: 0xFFFFFF,
                               added: 0x0B4A9E, addedBackground: 0xD3E6FF, removed: 0x9C3D06, success: 0x1F6B2B),
            dark: ThemeColors(background: 0x101A14, card: 0x1A2820, control: 0x26392E, selected: 0x3B5546, border: 0x5F7D6C,
                              text: 0xF5FBF7, secondaryText: 0xC2D6CA, accent: 0xA6E36B, onAccent: 0x13240A,
                              added: 0xA9D8FF, addedBackground: 0x15375C, removed: 0xFFB08A, success: 0xA6E36B)),
        ColorTheme(
            id: "graphite", name: "High contrast",
            light: ThemeColors(background: 0xFFFFFF, card: 0xFFFFFF, control: 0xEBEBEB, selected: 0xFFFFFF, border: 0x6B6B6B,
                               text: 0x000000, secondaryText: 0x3D3D3D, accent: 0x000000, onAccent: 0xFFFFFF,
                               added: 0x0B4A9E, addedBackground: 0xD3E6FF, removed: 0x9C3D06, success: 0x14663A),
            dark: ThemeColors(background: 0x000000, card: 0x141414, control: 0x262626, selected: 0x474747, border: 0x7A7A7A,
                              text: 0xFFFFFF, secondaryText: 0xD6D6D6, accent: 0xFFFFFF, onAccent: 0x000000,
                              added: 0xA9D8FF, addedBackground: 0x0F3355, removed: 0xFFB08A, success: 0x7FE3A8)),
    ]

    public static func named(_ id: String) -> ColorTheme {
        all.first { $0.id == id } ?? all[0]
    }
}

/// The theme colors resolve against at draw time. Colors are looked up deep inside AppKit's
/// drawing, away from any SwiftUI environment, so this has to be reachable from there.
public enum ActiveTheme {
    nonisolated(unsafe) public static var current = ColorTheme.all[0]
}

public enum Contrast {
    private static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// The WCAG contrast ratio, from 1 (identical) to 21 (black on white).
    public static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
