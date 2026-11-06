import AppKit
import SwiftUI

struct PanelActions {
    var useResult: () -> Void
    var send: () -> Void
    var copy: () -> Void
    var close: () -> Void
    var openSettings: (SettingsTab) -> Void
}

struct RewritePanelView: View {
    static let size = CGSize(width: 680, height: 352)

    @Bindable var session: RewriteSession
    let actions: PanelActions
    var useGlass = true
    @State private var copied = false
    @FocusState private var refineFocused: Bool

    private var canWriteBack: Bool { session.captured.canWriteBack }

    var body: some View {
        VStack(spacing: 0) {
            styleRow
            tabRow
            content
            Divider().opacity(0.6)
            refineRow
            Divider().opacity(0.6)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            if useGlass { GlassBackground() } else { Color(nsColor: .windowBackgroundColor) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.hairline))
        .task {
            // The window only becomes key just after this view appears.
            try? await Task.sleep(for: .milliseconds(30))
            refineFocused = session.tab != .original
        }
    }

    private var styleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(session.store.styles.enumerated()), id: \.element.id) { index, style in
                    Button { session.pick(style) } label: {
                        HStack(spacing: 7) {
                            if index < 9 { KeyCap(text: "\(index + 1)", onAccent: style.id == session.styleID) }
                            Text(style.name).font(.system(size: 13, weight: .medium))
                        }
                        .padding(.leading, 7)
                        .padding(.trailing, 11)
                        .frame(height: 32)
                        .foregroundStyle(style.id == session.styleID ? Color.onAccent : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 9).fill(style.id == session.styleID ? Color.tactAccent : Color.surface))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button { actions.openSettings(.styles) } label: {
                    Image(systemName: "plus").frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Edit styles")
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var tabRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(RewriteSession.Tab.allCases) { tab in
                    Button { session.tab = tab } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(session.tab == tab ? Color.primary : Color.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 7).fill(session.tab == tab ? Color.surfaceStrong : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.surface))

            Text(session.sourceLabel).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)

            if session.versions.count > 1 {
                HStack(spacing: 2) {
                    Button { session.go(by: -1) } label: {
                        Image(systemName: "chevron.left").frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    Text("\(session.index + 1) of \(session.versions.count): \(session.current?.label ?? "")")
                        .lineLimit(1)
                    Button { session.go(by: 1) } label: {
                        Image(systemName: "chevron.right").frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let error = session.errorText, session.tab == .result {
                errorView(error)
            } else {
                switch session.tab {
                case .result: resultView
                case .changes: changesView
                case .original: originalView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var resultView: some View {
        ScrollView {
            Group {
                if session.currentText.isEmpty {
                    Text(session.isStreaming ? "Writing..." : "").foregroundStyle(.secondary)
                } else {
                    Text(session.currentText).textSelection(.enabled)
                }
            }
            .font(.system(size: 15))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
    }

    private var changesView: some View {
        ScrollView {
            Group {
                if let pieces = WordDiff.compare(session.draft, session.currentText) {
                    Text(attributed(pieces)).textSelection(.enabled)
                } else {
                    Text("This message is too long to compare.").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 15))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
    }

    private func attributed(_ pieces: [WordDiff.Piece]) -> AttributedString {
        var result = AttributedString()
        for piece in pieces {
            var part = AttributedString(piece.text)
            switch piece.kind {
            case .same: break
            case .added:
                part.foregroundColor = .diffAdded
                part.backgroundColor = .diffAddedBackground
            case .removed:
                part.foregroundColor = .diffRemoved
                part.strikethroughStyle = .single
            }
            result.append(part)
        }
        return result
    }

    private var originalView: some View {
        HStack(alignment: .top, spacing: 10) {
            TextEditor(text: $session.draft)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.surface))
            Button("Rewrite") { session.rewriteDraft() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.system(size: 14))
            HStack(spacing: 8) {
                Button("Try again") { session.retry() }.buttonStyle(GhostButtonStyle(bordered: true))
                Button("Open Settings") { actions.openSettings(.models) }.buttonStyle(GhostButtonStyle(bordered: true))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var refineRow: some View {
        HStack(spacing: 8) {
            TextField("Change anything: sound less annoyed, say sorry first...", text: $session.refine)
                .focused($refineFocused)
                .font(.system(size: 14))
                .inputField()
                .onSubmit { session.applyRefinement(session.refine) }
            ForEach(Self.tweaks, id: \.name) { tweak in
                Button(tweak.name) { session.applyRefinement(tweak.note, label: tweak.name) }
                    .buttonStyle(GhostButtonStyle(bordered: true))
                    .disabled(session.currentText.isEmpty || session.isStreaming)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private static let tweaks = [
        (name: "Shorter", note: "Make it shorter."),
        (name: "Warmer", note: "Make it warmer."),
        (name: "More polite", note: "Make it more polite."),
    ]

    private var footer: some View {
        HStack(spacing: 8) {
            ModelMenu(session: session)
            Spacer(minLength: 0)
            Button(action: actions.close) {
                HStack(spacing: 6) {
                    Text("Cancel")
                    KeyCap(text: "esc")
                }
            }
            .buttonStyle(GhostButtonStyle())

            if canWriteBack {
                Button {
                    actions.copy()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    HStack(spacing: 6) {
                        Text(copied ? "Copied" : "Copy")
                        KeyCaps(keys: ["⌘", "C"])
                    }
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(!session.canUseResult)

                if session.store.settings.showSend {
                    Button(action: actions.send) {
                        HStack(spacing: 6) {
                            Text("Send")
                            KeyCaps(keys: ["⌘", "↩"])
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(!session.canUseResult)
                }
            }

            Button(action: actions.useResult) {
                HStack(spacing: 8) {
                    Text(canWriteBack ? "Replace" : "Copy")
                    KeyCap(text: "↩", onAccent: true)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!session.canUseResult)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

/// Connected providers and their live model lists, as a native menu so long lists scroll.
struct ModelMenu: View {
    @Bindable var session: RewriteSession

    var body: some View {
        Menu {
            let providers = session.store.connectedProviders
            ForEach(providers) { provider in
                Menu(provider.name) {
                    ForEach(session.store.models(for: provider)) { model in
                        Button {
                            session.pickModel(ModelRef(providerID: provider.id, modelID: model.id, modelName: model.name))
                        } label: {
                            if model.id == session.model?.modelID {
                                Label(model.name, systemImage: "checkmark")
                            } else {
                                Text(model.name)
                            }
                        }
                    }
                }
            }
            if providers.isEmpty { Text("No providers yet") }
        } label: {
            Text(session.model?.modelName ?? "Choose a model").font(.system(size: 13))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.secondary)
    }
}

/// A floating window that takes the keyboard without taking focus away from the chat app.
final class RewritePanelWindow: NSPanel {
    init() {
        super.init(contentRect: CGRect(origin: .zero, size: RewritePanelView.size),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RewritePanelController {
    private let window = RewritePanelWindow()
    private var monitor: Any?
    private(set) var session: RewriteSession?
    private let store: AppStore

    var onUseResult: ((RewriteSession, _ send: Bool) -> Void)?
    var onCopy: ((RewriteSession) -> Void)?
    var onOpenSettings: ((SettingsTab) -> Void)?

    var isOpen: Bool { window.isVisible }

    init(store: AppStore) {
        self.store = store
    }

    func show(captured: CapturedText) {
        let session = RewriteSession(store: store, captured: captured)
        self.session = session

        let actions = PanelActions(
            useResult: { [weak self] in self?.useResult(send: false) },
            send: { [weak self] in self?.useResult(send: true) },
            copy: { [weak self] in self.map { c in c.session.map { c.onCopy?($0) } } },
            close: { [weak self] in self?.close() },
            openSettings: { [weak self] tab in
                self?.close()
                self?.onOpenSettings?(tab)
            })

        let host = NSHostingView(rootView: RewritePanelView(session: session, actions: actions))
        host.frame = CGRect(origin: .zero, size: RewritePanelView.size)
        window.contentView = host
        window.setFrameOrigin(origin(for: captured.anchor))
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isOpen else { return event }
            return self.handle(event) ? nil : event
        }
        session.begin()
    }

    func close() {
        session?.cancel()
        session = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        // The view stays until the next show, since a button inside it may be what called this.
        window.orderOut(nil)
    }

    private func useResult(send: Bool) {
        guard let session, session.canUseResult else { return }
        onUseResult?(session, send)
    }

    /// Sits just above the message box when the app reports where that is.
    private func origin(for anchor: CGRect?) -> CGPoint {
        let size = RewritePanelView.size
        let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        let screen = anchor.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } } ?? mouseScreen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        var x = visible.midX - size.width / 2
        var y = visible.midY + visible.height * 0.12 - size.height / 2
        // Very tall "boxes" usually mean the app reported its whole window.
        if let anchor, anchor.height < visible.height * 0.5 {
            x = anchor.midX - size.width / 2
            y = anchor.maxY + 10
            if y + size.height > visible.maxY { y = anchor.minY - size.height - 10 }
        }
        return CGPoint(x: min(max(x, visible.minX + 12), visible.maxX - size.width - 12),
                       y: min(max(y, visible.minY + 12), visible.maxY - size.height - 12))
    }

    /// Returns true when the key was used here. The chat app isn't active while the panel is up,
    /// so its menus can't handle edit commands and those are forwarded by hand.
    private func handle(_ event: NSEvent) -> Bool {
        guard let session else { return false }
        let command = event.modifierFlags.contains(.command)
        let characters = event.charactersIgnoringModifiers?.lowercased()
        let editing = session.tab == .original
        let refineEmpty = session.refine.isEmpty

        switch event.keyCode {
        case 53: // Esc
            close()
            return true
        case 36, 76: // Return
            if command {
                if editing {
                    session.rewriteDraft()
                } else {
                    useResult(send: store.settings.showSend && session.captured.canWriteBack)
                }
                return true
            }
            if editing { return false }
            if refineEmpty {
                useResult(send: false)
                return true
            }
            return false
        case 48: // Tab
            guard !editing || event.modifierFlags.contains(.shift), refineEmpty else { return false }
            let tabs = RewriteSession.Tab.allCases
            let next = (tabs.firstIndex(of: session.tab)! + 1) % tabs.count
            session.tab = tabs[next]
            return true
        default:
            break
        }

        if command {
            switch characters {
            case "c":
                if refineEmpty, !editing, !hasSelectedText {
                    if session.canUseResult { onCopy?(session) }
                    return true
                }
                return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            case "v": return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            case "x": return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            case "z": return NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            case "[":
                session.go(by: -1)
                return true
            case "]":
                session.go(by: 1)
                return true
            default:
                return false
            }
        }

        // Number keys pick a style until the person starts typing an edit.
        if !editing, refineEmpty, !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control),
           let character = characters, let number = Int(character), number >= 1, number <= store.styles.count {
            session.pick(store.styles[number - 1])
            return true
        }
        return false
    }

    private var hasSelectedText: Bool {
        guard let textView = window.firstResponder as? NSTextView else { return false }
        return textView.selectedRange().length > 0
    }
}
