import AppKit
import SwiftUI

@MainActor
public final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = AppStore()
    private let bridge = TextBridge()
    private let hotkeys = HotkeyManager()
    private let router = SettingsRouter()
    private lazy var panel = RewritePanelController(store: store)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = makeMainMenu()
        applyAppearance(store.settings.appearance)
        setUpStatusItem()

        hotkeys.onAction = { [weak self] in self?.perform($0) }
        hotkeys.register(store.settings.hotkeys)

        panel.onUseResult = { [weak self] session, send in self?.useResult(of: session, send: send) }
        panel.onCopy = { [weak self] session in self?.copyResult(of: session) }
        panel.onOpenSettings = { [weak self] tab in self?.openSettings(tab) }

        if !store.settings.setupDone { openSetup() }
    }

    // MARK: Shortcuts

    private func perform(_ action: HotkeyAction) {
        guard store.settings.setupDone else {
            openSetup()
            return
        }
        switch action {
        case .rewrite: toggleRewrite()
        case .instantFix: runInstant(styleID: store.settings.instantStyleID)
        case .repeatLast: runInstant(styleID: store.settings.lastStyleID)
        case .history: openSettings(.history)
        }
    }

    private func toggleRewrite() {
        if panel.isOpen {
            panel.close()
            return
        }
        Task {
            let captured = await bridge.capture()
            panel.show(captured: captured)
        }
    }

    /// Rewrites and puts the result back with no panel. Anything unexpected falls back to the panel.
    private func runInstant(styleID: String) {
        guard !panel.isOpen else { return }
        Task {
            let captured = await bridge.capture()
            guard captured.canWriteBack, let style = store.style(id: styleID) else {
                panel.show(captured: captured)
                return
            }
            setBusy(true)
            defer { setBusy(false) }
            do {
                let request = try store.request(style: style, model: nil, draft: captured.text)
                let output = try await LLMClient.complete(request)
                let result = PromptBuilder.clean(output, draft: captured.text)
                guard !result.isEmpty else { throw LLMError.empty }
                record(original: captured.text, result: result, style: style.name, model: store.model(for: style)?.modelName)
                await bridge.replace(with: result, in: captured, send: false, restoreClipboard: store.settings.restoreClipboard)
            } catch {
                NSSound.beep()
                panel.show(captured: captured)
            }
        }
    }

    // MARK: Results

    private func useResult(of session: RewriteSession, send: Bool) {
        let text = session.currentText
        let captured = session.captured
        record(session)
        panel.close()
        guard captured.canWriteBack else {
            bridge.copy(text)
            return
        }
        Task {
            // Keys must land in the chat app, which only happens once the panel has gone.
            try? await Task.sleep(for: .milliseconds(60))
            await bridge.replace(with: text, in: captured, send: send, restoreClipboard: store.settings.restoreClipboard)
        }
    }

    private func copyResult(of session: RewriteSession) {
        bridge.copy(session.currentText)
        record(session)
    }

    private func record(_ session: RewriteSession) {
        record(original: session.draft, result: session.currentText, style: session.style?.name, model: session.model?.modelName)
    }

    private func record(original: String, result: String, style: String?, model: String?) {
        store.addHistory(HistoryEntry(original: original, result: result, style: style ?? "", model: model ?? ""))
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        menuNeedsUpdate(menu)
        setBusy(false)
    }

    private func setBusy(_ busy: Bool) {
        let name = busy ? "ellipsis.bubble" : "text.bubble"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Tact")
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let shortcut = store.settings.hotkeys[HotkeyAction.rewrite.rawValue]?.text ?? ""
        menu.addItem(item("Rewrite my message   \(shortcut)", #selector(menuRewrite)))
        menu.addItem(item("History", #selector(menuHistory)))
        menu.addItem(item("Settings", #selector(menuSettings)))
        if !bridge.isTrusted {
            menu.addItem(.separator())
            menu.addItem(item("Allow text replacement", #selector(menuPermission)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit Tact", #selector(menuQuit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func menuRewrite() { perform(.rewrite) }
    @objc private func menuHistory() { openSettings(.history) }
    @objc private func menuSettings() { store.settings.setupDone ? openSettings(.models) : openSetup() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuPermission() {
        bridge.requestTrust()
        openAccessibilitySettings()
    }

    /// Without an Edit menu, ⌘V doesn't reach text fields, which would block pasting an API key.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Tact", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }

    // MARK: Windows

    private func makeWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func openSetup() {
        if setupWindow == nil {
            let view = SetupView(store: store, bridge: bridge) { [weak self] in
                self?.setupWindow?.close()
                self?.setupWindow = nil
            }
            setupWindow = makeWindow(title: "Welcome to Tact", content: view)
        }
        present(setupWindow!)
    }

    private func openSettings(_ tab: SettingsTab) {
        router.tab = tab
        if settingsWindow == nil {
            let control = ShortcutControl(
                suspend: { [weak self] in self?.hotkeys.unregisterAll() },
                apply: { [weak self] in
                    guard let self else { return [] }
                    return self.hotkeys.register(self.store.settings.hotkeys)
                })
            let view = SettingsView(store: store, router: router, bridge: bridge, hotkeys: control)
            settingsWindow = makeWindow(title: "Tact Settings", content: view)
        }
        present(settingsWindow!)
    }
}
