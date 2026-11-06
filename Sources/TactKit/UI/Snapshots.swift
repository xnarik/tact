import AppKit
import SwiftUI

/// Draws each screen and the app icon to PNG files, so layouts can be checked without opening the app.
@MainActor
public enum SnapshotRenderer {
    public static func renderScreens(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("tact-snapshot-\(UUID().uuidString)")
        let store = AppStore(directory: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let provider = Provider.named("anthropic")!
        store.settings.setupDone = true
        store.register(provider, models: [ModelInfo(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5"), ModelInfo(id: "claude-haiku-5-5", name: "Claude Haiku 5.5")])
        store.addHistory(HistoryEntry(original: "can we push", result: "Quick update: we likely can't ship by Friday. Can we move to Wednesday?", style: "Work", model: "Claude Haiku 5.5"))

        let draft = "hey so i checked and we prob cant ship by friday, api thing still broken and sam is out. can we push to wed or smth"
        let result = "Quick update: we likely can't ship by Friday. The API issue is still open and Sam is out. Can we move to Wednesday?"
        let actions = PanelActions(useResult: {}, send: {}, copy: {}, close: {}, openSettings: { _ in })
        let bridge = TextBridge()
        let control = ShortcutControl(suspend: {}, apply: { [] })

        func session(_ tab: RewriteSession.Tab, error: String? = nil, source: CapturedText.Source = .wholeBox) -> RewriteSession {
            let session = RewriteSession(store: store, captured: CapturedText(text: draft, source: source))
            session.styleID = "work"
            session.tab = tab
            session.errorText = error
            if error == nil {
                session.versions = [.init(text: "First attempt", label: "Clear"), .init(text: result, label: "Work")]
                session.index = 1
            }
            return session
        }

        func panel(_ session: RewriteSession) -> some View {
            RewritePanelView(session: session, actions: actions, useGlass: false)
        }

        func settings(_ tab: SettingsTab) -> some View {
            let router = SettingsRouter()
            router.tab = tab
            return SettingsView(store: store, router: router, bridge: bridge, hotkeys: control)
                .background(Color(nsColor: .windowBackgroundColor))
        }

        func setup(_ step: SetupView.Step) -> some View {
            SetupView(store: store, bridge: bridge, onFinish: {}, step: step)
                .background(Color(nsColor: .windowBackgroundColor))
        }

        for (mode, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", NSAppearance.Name.aqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            func save<V: View>(_ name: String, _ view: V) throws {
                try write(view, to: directory.appendingPathComponent("\(mode)-\(name).png"))
            }
            try save("panel-result", panel(session(.result)))
            try save("panel-changes", panel(session(.changes)))
            try save("panel-original", panel(session(.original)))
            try save("panel-error", panel(session(.result, error: LLMError.badKey("Anthropic").localizedDescription)))
            try save("panel-clipboard", panel(session(.result, source: .clipboard)))
            try save("setup-key", setup(.key))
            try save("setup-permission", setup(.permission))
            try save("setup-done", setup(.done))
            for tab in SettingsTab.allCases {
                try save("settings-\(tab.rawValue.lowercased())", settings(tab))
            }
        }
    }

    private static func write<V: View>(_ view: V, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    public static func renderIconSet(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
            let pixels = points * scale
            let suffix = scale == 2 ? "@2x" : ""
            let data = iconPNG(pixels: pixels)
            try data?.write(to: directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        }
    }

    private static func iconPNG(pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(pixels)

        // macOS icons leave a margin around the rounded square.
        let tile = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
        NSColor(red: 0.369, green: 0.859, blue: 0.753, alpha: 1).setFill()
        NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18).fill()

        let ink = NSColor(red: 0.043, green: 0.082, blue: 0.071, alpha: 1)
        ink.setFill()
        let bubble = NSBezierPath(roundedRect: CGRect(x: s * 0.24, y: s * 0.36, width: s * 0.52, height: s * 0.38), xRadius: s * 0.09, yRadius: s * 0.09)
        bubble.move(to: CGPoint(x: s * 0.34, y: s * 0.38))
        bubble.line(to: CGPoint(x: s * 0.30, y: s * 0.25))
        bubble.line(to: CGPoint(x: s * 0.47, y: s * 0.38))
        bubble.close()
        bubble.fill()

        NSColor(red: 0.369, green: 0.859, blue: 0.753, alpha: 1).setFill()
        for (y, width) in [(CGFloat(0.59), CGFloat(0.34)), (0.49, 0.22)] {
            NSBezierPath(roundedRect: CGRect(x: s * 0.33, y: s * y, width: s * width, height: s * 0.05), xRadius: s * 0.025, yRadius: s * 0.025).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
