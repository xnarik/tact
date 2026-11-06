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
            RewritePanelView(session: session, actions: actions)
        }

        func settings(_ tab: SettingsTab) -> some View {
            let router = SettingsRouter()
            router.tab = tab
            return SettingsView(store: store, router: router, bridge: bridge, hotkeys: control)
        }

        func setup(_ step: SetupView.Step) -> some View {
            SetupView(store: store, bridge: bridge, onFinish: {}, step: step)
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
            for theme in ColorTheme.all {
                store.settings.themeID = theme.id
                try save("theme-\(theme.id)", panel(session(.result)))
                try save("theme-\(theme.id)-changes", panel(session(.changes)))
            }
            store.settings.themeID = ColorTheme.defaultID
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
            let data = AppIcon.png(pixels: pixels, margin: true)
            try data?.write(to: directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        }
    }
}
