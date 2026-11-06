import AppKit
import SwiftUI

extension Color {
    static let tactAccent = Color(red: 0.369, green: 0.859, blue: 0.753)
    static let onAccent = Color(red: 0.043, green: 0.082, blue: 0.071)
    static let surface = Color.primary.opacity(0.08)
    static let surfaceStrong = Color.primary.opacity(0.14)
    static let hairline = Color.primary.opacity(0.12)
    static let diffAdded = Color(light: Color(red: 0.06, green: 0.31, blue: 0.66), dark: Color(red: 0.75, green: 0.87, blue: 1.0))
    static let diffAddedBackground = Color(red: 0.30, green: 0.60, blue: 1.0).opacity(0.22)
    static let diffRemoved = Color(light: Color(red: 0.66, green: 0.27, blue: 0.06), dark: Color(red: 1.0, green: 0.70, blue: 0.54))
    static let connected = Color(light: Color(red: 0.11, green: 0.42, blue: 0.23), dark: Color(red: 0.56, green: 0.89, blue: 0.69))

    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
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
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.hairline))
    }
}

extension View {
    func inputField() -> some View { modifier(InputFieldStyle()) }
}

/// Lets the panel use the same blurred glass as system overlays.
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
