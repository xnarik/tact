import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Follows both the light or dark mode and the chosen theme each time it's drawn.
    static func themed(_ key: KeyPath<ThemeColors, UInt32>) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let colors = isDark ? ActiveTheme.current.dark : ActiveTheme.current.light
            return NSColor(hex: colors[keyPath: key])
        }
    }

    static let tactWindow = themed(\.background)
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    static let windowFill = Color(nsColor: .tactWindow)
    static let cardFill = Color(nsColor: .themed(\.card))
    static let surface = Color(nsColor: .themed(\.control))
    static let surfaceStrong = Color(nsColor: .themed(\.selected))
    static let hairline = Color(nsColor: .themed(\.border))
    static let textPrimary = Color(nsColor: .themed(\.text))
    static let textSecondary = Color(nsColor: .themed(\.secondaryText))
    static let tactAccent = Color(nsColor: .themed(\.accent))
    static let onAccent = Color(nsColor: .themed(\.onAccent))
    static let diffAdded = Color(nsColor: .themed(\.added))
    static let diffAddedBackground = Color(nsColor: .themed(\.addedBackground))
    static let diffRemoved = Color(nsColor: .themed(\.removed))
    static let connected = Color(nsColor: .themed(\.success))
}

/// Windows paint their own background outside SwiftUI, so a theme change has to reach them directly.
@MainActor
func refreshWindowBackgrounds() {
    for window in NSApp.windows where window.styleMask.contains(.titled) {
        window.backgroundColor = .tactWindow
        window.contentView?.needsDisplay = true
    }
}

struct ThemedDivider: View {
    var vertical = false

    var body: some View {
        Rectangle().fill(Color.hairline).frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

struct KeyCap: View {
    let text: String
    var onAccent = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, text.count > 1 ? 5 : 0)
            .background(RoundedRectangle(cornerRadius: 5).fill(onAccent ? Color.black.opacity(0.14) : Color.surfaceStrong))
            .overlay {
                // Keeps the cap visible in light themes, where its fill can match the background.
                if !onAccent { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.hairline.opacity(0.6)) }
            }
    }
}

struct KeyCaps: View {
    let keys: [String]
    var onAccent = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { KeyCap(text: $0.element, onAccent: onAccent) }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.onAccent)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.tactAccent))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

struct GhostButtonStyle: ButtonStyle {
    var bordered = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(isEnabled && (hovering || configuration.isPressed) ? Color.surface : .clear))
            .overlay {
                if bordered { RoundedRectangle(cornerRadius: 9).strokeBorder(Color.hairline) }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

struct InputFieldStyle: ViewModifier {
    var placeholder: String?
    var text: String
    var fontSize: CGFloat

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .background(alignment: .leading) {
                // macOS ignores the color of a field's own prompt and draws it too faintly to read.
                if let placeholder, text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: fontSize))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.hairline))
    }
}

extension View {
    func inputField(placeholder: String? = nil, text: String = "", fontSize: CGFloat = 13) -> some View {
        modifier(InputFieldStyle(placeholder: placeholder, text: text, fontSize: fontSize))
    }

    /// The base every window's content sits on.
    func themedBase() -> some View {
        background(Color.windowFill)
            .foregroundStyle(Color.textPrimary)
            .tint(Color.tactAccent)
    }
}
