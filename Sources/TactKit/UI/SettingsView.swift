import AppKit
import Observation
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case models = "Models", styles = "Styles", shortcuts = "Shortcuts", history = "History", general = "General"
    var id: String { rawValue }
}

@MainActor
@Observable
final class SettingsRouter {
    var tab = SettingsTab.models
}

struct SettingsView: View {
    @Bindable var store: AppStore
    @Bindable var router: SettingsRouter
    let bridge: TextBridge
    let hotkeys: ShortcutControl

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    Button { router.tab = tab } label: {
                        Text(tab.rawValue)
                            .fontWeight(router.tab == tab ? .semibold : .regular)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(router.tab == tab ? Color.surfaceStrong : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 20)
            .frame(width: 180)
            .background(Color.surface.opacity(0.5))

            Divider()

            ScrollView {
                Group {
                    switch router.tab {
                    case .models: ModelsTab(store: store)
                    case .styles: StylesTab(store: store)
                    case .shortcuts: ShortcutsTab(store: store, hotkeys: hotkeys)
                    case .history: HistoryTab(store: store, bridge: bridge)
                    case .general: GeneralTab(store: store, bridge: bridge)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
        }
        .frame(width: 900, height: 640)
    }
}

private struct TabHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .semibold))
            if let detail { Text(detail).foregroundStyle(.secondary) }
        }
    }
}

private struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 13, weight: .medium))
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.hairline))
    }
}

/// Picks from every connected provider's live list.
private struct ModelPicker: View {
    let store: AppStore
    let selection: ModelRef?
    var allowsDefault = false
    let onPick: (ModelRef?) -> Void

    var body: some View {
        Menu {
            if allowsDefault {
                Button("Default model") { onPick(nil) }
            }
            ForEach(store.connectedProviders) { provider in
                Menu(provider.name) {
                    ForEach(store.models(for: provider)) { model in
                        Button(model.name) {
                            onPick(ModelRef(providerID: provider.id, modelID: model.id, modelName: model.name))
                        }
                    }
                }
            }
            if store.connectedProviders.isEmpty { Text("Add a provider first") }
        } label: {
            Text(selection?.modelName ?? (allowsDefault ? "Default model" : "Choose a model"))
        }
        .fixedSize()
    }
}

// MARK: Models

private struct ModelsTab: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Models", detail: "Add a key for any provider you use. New models appear on their own.")

            Card {
                HStack {
                    FieldLabel("Default model")
                    Spacer()
                    ModelPicker(store: store, selection: store.settings.defaultModel) { store.settings.defaultModel = $0 }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            Card {
                ForEach(Array(Provider.all.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 { Divider() }
                    ProviderRow(store: store, provider: provider)
                }
            }
        }
    }
}

private struct ProviderRow: View {
    @Bindable var store: AppStore
    let provider: Provider
    @State private var isOpen = false
    @State private var key = ""
    @State private var address = ""
    @State private var isBusy = false
    @State private var message: String?

    private var isConnected: Bool { store.settings.connected.contains(provider.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(provider.name).fontWeight(.medium)
                Text(provider.note).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                if isConnected { Text("Connected").font(.system(size: 13)).foregroundStyle(Color.connected) }
                Button(isOpen ? "Close" : isConnected ? "Manage" : provider.needsKey ? "Add key" : "Set up") {
                    isOpen.toggle()
                    message = nil
                    address = store.baseURL(for: provider)
                }
                .buttonStyle(GhostButtonStyle(bordered: true))
            }
            .frame(minHeight: 40)

            if isOpen { details }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if provider.isLocal {
                TextField("Server address, like http://localhost:11434/v1", text: $address).inputField()
            }
            if !isConnected || provider.isLocal {
                HStack(spacing: 8) {
                    SecureField(provider.needsKey ? "Paste your \(provider.name) API key" : "API key, if your server needs one", text: $key).inputField()
                    Button(isBusy ? "Checking..." : "Save and test", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isBusy || (provider.needsKey && key.isEmpty) || (provider.isLocal && address.isEmpty))
                }
            }
            if isConnected {
                HStack {
                    Text("\(store.models(for: provider).count) models. Key saved in Keychain.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh models", action: refresh).buttonStyle(GhostButtonStyle())
                    Button("Remove") {
                        store.disconnect(provider)
                        isOpen = false
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            } else if let page = provider.keyPage, let url = URL(string: page) {
                Link("Get a \(provider.name) key", destination: url).font(.system(size: 13))
            }
            if let message {
                Text(message).font(.system(size: 13)).foregroundStyle(Color.diffRemoved)
            }
        }
        .padding(.bottom, 8)
    }

    private func save() {
        isBusy = true
        message = nil
        Task {
            do {
                try await store.connect(provider, key: key.isEmpty ? nil : key, baseURL: provider.isLocal ? address : nil)
                key = ""
                isOpen = false
            } catch {
                message = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func refresh() {
        Task {
            do {
                try await store.refreshModels(provider)
                message = nil
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

// MARK: Styles

private struct StylesTab: View {
    @Bindable var store: AppStore
    @State private var selectedID: String?

    private var index: Int? {
        let id = selectedID ?? store.settings.styles.first?.id
        return store.settings.styles.firstIndex { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                TabHeader(title: "Styles", detail: "A style is one reusable recipe. Set it up once, then pick it with one key.")
                Spacer()
                Menu("New style") {
                    Button("Blank") { add(Style(name: "New style", instruction: "")) }
                    Divider()
                    ForEach(Style.templates, id: \.name) { template in
                        Button(template.name) { add(template) }
                    }
                }
                .fixedSize()
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(store.settings.styles.enumerated()), id: \.element.id) { position, style in
                        Button { selectedID = style.id } label: {
                            HStack(spacing: 8) {
                                if position < 9 { KeyCap(text: "\(position + 1)") }
                                Text(style.name).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 8).fill(position == index ? Color.surfaceStrong : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 170)

                if let index { editor(index) }
            }
        }
    }

    private func add(_ template: Style) {
        var style = template
        style.id = UUID().uuidString
        store.settings.styles.append(style)
        selectedID = style.id
    }

    private func editor(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                FieldLabel("Name")
                TextField("Name", text: $store.settings.styles[index].name).inputField()
            }

            VStack(alignment: .leading, spacing: 4) {
                FieldLabel("What should it do?")
                TextEditor(text: $store.settings.styles[index].instruction)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 76)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.surface))
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    FieldLabel("Tone")
                    Picker("Tone", selection: $store.settings.styles[index].tone) {
                        ForEach(Tone.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    FieldLabel("Model")
                    ModelPicker(store: store, selection: store.settings.styles[index].model, allowsDefault: true) {
                        store.settings.styles[index].model = $0
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                FieldLabel("How much can it change?")
                Picker("How much can it change?", selection: $store.settings.styles[index].creativity) {
                    ForEach(Creativity.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 4) {
                FieldLabel("Pick this style on its own in these apps")
                TextField("Slack, Teams", text: $store.settings.styles[index].apps).inputField()
            }

            HStack(spacing: 8) {
                Button("Move up") { move(index, by: -1) }.disabled(index == 0)
                Button("Move down") { move(index, by: 1) }.disabled(index == store.settings.styles.count - 1)
                Spacer()
                Button("Delete style") {
                    let id = store.settings.styles[index].id
                    store.settings.styles.remove(at: index)
                    if selectedID == id { selectedID = nil }
                }
                .disabled(store.settings.styles.count == 1)
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private func move(_ index: Int, by step: Int) {
        store.settings.styles.swapAt(index, index + step)
    }
}

// MARK: Shortcuts

/// Lets the recorder pause the live shortcuts, so pressing one doesn't trigger it.
@MainActor
struct ShortcutControl {
    var suspend: () -> Void
    /// Returns the actions whose shortcut couldn't be claimed.
    var apply: () -> [HotkeyAction]
}

private struct ShortcutsTab: View {
    @Bindable var store: AppStore
    let hotkeys: ShortcutControl
    @State private var recording: HotkeyAction?
    @State private var monitor: Any?
    @State private var failed: [HotkeyAction] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Shortcuts", detail: "These work in every app. Click one to change it.")

            Card {
                ForEach(Array(HotkeyAction.allCases.enumerated()), id: \.element) { index, action in
                    if index > 0 { Divider() }
                    row(action)
                }
            }

            ForEach(failed) { action in
                Text("Another app is using the shortcut for \(action.title). Pick a different one.")
                    .font(.system(size: 13)).foregroundStyle(Color.diffRemoved)
            }

            HStack {
                FieldLabel("Instant fix uses this style")
                Spacer()
                Picker("Instant fix style", selection: $store.settings.instantStyleID) {
                    ForEach(store.styles) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func row(_ action: HotkeyAction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title).fontWeight(.medium)
                Text(action.note).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { recording == action ? stopRecording() : startRecording(action) } label: {
                if recording == action {
                    Text("Press new keys...")
                } else {
                    KeyCaps(keys: (store.settings.hotkeys[action.rawValue] ?? HotkeyCombo.defaults[action]!).symbols)
                }
            }
            .buttonStyle(GhostButtonStyle(bordered: true))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func startRecording(_ action: HotkeyAction) {
        stopRecording()
        recording = action
        hotkeys.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= HotkeyCombo.command }
            if flags.contains(.control) { modifiers |= HotkeyCombo.control }
            if flags.contains(.option) { modifiers |= HotkeyCombo.option }
            // Shift alone would stop capitals from typing, so a real modifier is required.
            guard modifiers != 0 else { return nil }
            if flags.contains(.shift) { modifiers |= HotkeyCombo.shift }
            store.settings.hotkeys[action.rawValue] = HotkeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording != nil { failed = hotkeys.apply() }
        recording = nil
    }
}

// MARK: History

private struct HistoryTab: View {
    @Bindable var store: AppStore
    let bridge: TextBridge
    @State private var search = ""
    @State private var copiedID: UUID?

    private var entries: [HistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return store.history }
        return store.history.filter { ($0.result + " " + $0.original + " " + $0.style).lowercased().contains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                TabHeader(title: "History", detail: "Saved only on this Mac.")
                Spacer()
                Picker("Keep for", selection: $store.settings.keepHistory) {
                    ForEach(KeepHistory.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
                .onChange(of: store.settings.keepHistory) { store.applyHistoryPolicy() }
                Button("Clear all") { store.clearHistory() }.buttonStyle(GhostButtonStyle(bordered: true))
            }

            TextField("Search your past messages", text: $search).inputField()

            if entries.isEmpty {
                Text(store.history.isEmpty ? "Messages you use will show up here." : "Nothing matches that search.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }

            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        Text("·")
                        Text(entry.style)
                        Text("·")
                        Text(entry.model)
                        Spacer()
                        Button(copiedID == entry.id ? "Copied" : "Copy") {
                            bridge.copy(entry.result)
                            copiedID = entry.id
                        }
                        Button("Delete") { store.removeHistory(entry) }
                    }
                    .buttonStyle(GhostButtonStyle())
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    Text(entry.result).textSelection(.enabled)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.hairline))
            }
        }
    }
}

// MARK: General

private struct GeneralTab: View {
    @Bindable var store: AppStore
    let bridge: TextBridge
    @State private var startsAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var trusted = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "General")

            Card {
                row("Start when I log in", isOn: Binding(get: { startsAtLogin }, set: setLogin))
                Divider()
                row("Show a Send button in the panel", isOn: $store.settings.showSend)
                Divider()
                row("Keep my clipboard as it was after replacing text", isOn: $store.settings.restoreClipboard)
                Divider()
                row("Reply in the same language as my draft", isOn: $store.settings.matchLanguage)
                Divider()
                HStack {
                    Text("Appearance")
                    Spacer()
                    Picker("Appearance", selection: $store.settings.appearance) {
                        ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: store.settings.appearance) { applyAppearance($1) }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Accessibility")
                        Text(trusted ? "Allowed. Tact can read and replace your message." : "Not allowed. Tact can only use your clipboard.")
                            .font(.system(size: 13)).foregroundStyle(trusted ? Color.connected : Color.secondary)
                    }
                    Spacer()
                    if !trusted {
                        Button("Open System Settings") {
                            bridge.requestTrust()
                            openAccessibilitySettings()
                        }
                        .buttonStyle(GhostButtonStyle(bordered: true))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            if let loginError {
                Text(loginError).font(.system(size: 13)).foregroundStyle(Color.diffRemoved)
            }

            Text("Your text goes straight from this Mac to the provider you picked. Tact has no server and no analytics.")
                .foregroundStyle(.secondary)
        }
        .onAppear { trusted = bridge.isTrusted }
        .onReceive(timer) { _ in trusted = bridge.isTrusted }
    }

    private func row(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(Color.tactAccent)
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            startsAtLogin = enabled
            loginError = nil
        } catch {
            loginError = "macOS wouldn't change this: \(error.localizedDescription)"
        }
    }
}

@MainActor
func applyAppearance(_ appearance: Appearance) {
    switch appearance {
    case .system: NSApp.appearance = nil
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}
