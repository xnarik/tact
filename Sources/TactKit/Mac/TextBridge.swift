import AppKit
import ApplicationServices

public struct CapturedText {
    public enum Source {
        /// Only part of the message box was selected.
        case selection
        /// Nothing was selected, so the whole message box was taken.
        case wholeBox
        case clipboard
        case nothing
    }

    public var text: String
    public var source: Source
    public var app: NSRunningApplication?
    /// The message box on screen, in Cocoa coordinates, when the app reports it.
    public var anchor: CGRect?

    public var canWriteBack: Bool { source == .selection || source == .wholeBox }
    public var appName: String? { app?.localizedName }

    public init(text: String, source: Source, app: NSRunningApplication? = nil, anchor: CGRect? = nil) {
        self.text = text
        self.source = source
        self.app = app
        self.anchor = anchor
    }
}

@MainActor
final class TextBridge {
    private enum Key {
        static let a: CGKeyCode = 0, c: CGKeyCode = 8, v: CGKeyCode = 9, returnKey: CGKeyCode = 36, right: CGKeyCode = 124
    }

    private static let maxLength = 20_000
    private static let textRoles: Set<String> = [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole, "AXSearchField"]
    /// Roles where trying select-all could grab a whole page or a list of files.
    private static let keyboardFallbackRoles: Set<String> = [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole, "AXSearchField", kAXGroupRole, "AXWebArea"]

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Reading

    func capture() async -> CapturedText {
        let app = NSWorkspace.shared.frontmostApplication
        guard isTrusted else { return clipboardFallback(app: app, anchor: nil) }

        if let app { wakeAccessibility(in: app) }
        let focused = focusedElement(in: app)
        let role = focused.flatMap { string($0, kAXRoleAttribute) }
        let anchor = focused.flatMap(frame)

        if let focused {
            if let selected = string(focused, kAXSelectedTextAttribute), isUsable(selected) {
                return CapturedText(text: selected, source: .selection, app: app, anchor: anchor)
            }
            if let role, Self.textRoles.contains(role), let value = string(focused, kAXValueAttribute), isUsable(value),
               value != string(focused, kAXPlaceholderValueAttribute) {
                return CapturedText(text: value, source: .wholeBox, app: app, anchor: anchor)
            }
        }

        // Web-based chat apps often hide their text from Accessibility, so ask the app to copy it.
        if role == nil || Self.keyboardFallbackRoles.contains(role!) {
            if let found = await captureWithKeyboard() {
                return CapturedText(text: found.text, source: found.source, app: app, anchor: anchor)
            }
        }
        return clipboardFallback(app: app, anchor: anchor)
    }

    private func clipboardFallback(app: NSRunningApplication?, anchor: CGRect?) -> CapturedText {
        if let text = NSPasteboard.general.string(forType: .string), isUsable(text) {
            return CapturedText(text: text, source: .clipboard, app: app, anchor: anchor)
        }
        return CapturedText(text: "", source: .nothing, app: app, anchor: anchor)
    }

    private func isUsable(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= Self.maxLength
    }

    private func captureWithKeyboard() async -> (text: String, source: CapturedText.Source)? {
        await waitForModifierRelease()
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        defer { restore(saved, to: pasteboard) }

        var count = pasteboard.changeCount
        post(Key.c, flags: .maskCommand)
        if await waitForChange(from: count), let text = pasteboard.string(forType: .string), isUsable(text) {
            return (text, .selection)
        }

        count = pasteboard.changeCount
        post(Key.a, flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(50))
        post(Key.c, flags: .maskCommand)
        let changed = await waitForChange(from: count)
        // Collapse the selection so the box looks as it did.
        post(Key.right, flags: [])
        if changed, let text = pasteboard.string(forType: .string), isUsable(text) {
            return (text, .wholeBox)
        }
        return nil
    }

    private func waitForChange(from count: Int) async -> Bool {
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(25))
            if NSPasteboard.general.changeCount != count { return true }
        }
        return false
    }

    /// The shortcut's own keys are usually still held, and they would turn our ⌘C into something else.
    private func waitForModifierRelease() async {
        for _ in 0..<40 {
            let flags = CGEventSource.flagsState(.hidSystemState)
            if flags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift]).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Writing

    /// Pasting works everywhere, including web-based apps whose boxes ignore direct text changes.
    func replace(with text: String, in captured: CapturedText, send: Bool, restoreClipboard: Bool) async {
        if let app = captured.app, !app.isActive {
            app.activate()
            try? await Task.sleep(for: .milliseconds(120))
        }
        await waitForModifierRelease()

        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Tells clipboard managers not to record this.
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))

        if captured.source == .wholeBox {
            post(Key.a, flags: .maskCommand)
            try? await Task.sleep(for: .milliseconds(50))
        }
        post(Key.v, flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(150))
        if send { post(Key.returnKey, flags: []) }

        // Web apps can read the clipboard a beat after the keystroke.
        try? await Task.sleep(for: .milliseconds(350))
        if restoreClipboard { restore(saved, to: pasteboard) }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Accessibility helpers

    /// Electron apps such as Slack only build their accessibility tree when asked.
    private func wakeAccessibility(in app: NSRunningApplication) {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private func focusedElement(in app: NSRunningApplication?) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        if let element = attribute(system, kAXFocusedUIElementAttribute) { return (element as! AXUIElement) }
        guard let app else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        return attribute(appElement, kAXFocusedUIElementAttribute).map { $0 as! AXUIElement }
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute),
              let sizeValue = attribute(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size), size.width > 0 else { return nil }
        // Accessibility measures from the top of the primary screen, Cocoa from the bottom.
        guard let primary = NSScreen.screens.first else { return nil }
        return CGRect(x: origin.x, y: primary.frame.maxY - origin.y - size.height, width: size.width, height: size.height)
    }

    // MARK: Clipboard and keyboard helpers

    private func snapshot(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    private func restore(_ saved: [[(NSPasteboard.PasteboardType, Data)]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = saved.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            entries.forEach { item.setData($0.1, forType: $0.0) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private func post(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cgSessionEventTap)
        }
    }
}
