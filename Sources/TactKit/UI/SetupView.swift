import AppKit
import SwiftUI

struct SetupView: View {
    enum Step: Int, CaseIterable {
        case key, permission, done

        var title: String {
            switch self {
            case .key: return "API key"
            case .permission: return "Permission"
            case .done: return "Done"
            }
        }
    }

    enum KeyState: Equatable {
        case empty, checking, connected(String), failed(String)
    }

    let store: AppStore
    let bridge: TextBridge
    let onFinish: () -> Void
    @State var step: Step = .key
    @State private var key = ""
    @State private var keyState = KeyState.empty
    @State private var pickedProviderID = ""
    @State private var trusted = false
    @State private var skippedPermission = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var candidates: [Provider] { KeyDetector.candidates(for: key) }
    private var needsProviderChoice: Bool { !key.isEmpty && candidates.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepper.padding(.bottom, 32)
            switch step {
            case .key: keyStep
            case .permission: permissionStep
            case .done: doneStep
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(width: 640, height: 500, alignment: .topLeading)
        .onReceive(timer) { _ in trusted = bridge.isTrusted }
        .onAppear { trusted = bridge.isTrusted }
    }

    private var stepper: some View {
        HStack(spacing: 10) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                HStack(spacing: 8) {
                    Text("\(item.rawValue + 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(item.rawValue <= step.rawValue ? Color.onAccent : Color.secondary)
                        .background(Circle().fill(item.rawValue <= step.rawValue ? Color.tactAccent : Color.surface))
                    Text(item.title)
                        .font(.system(size: 13, weight: item == step ? .semibold : .regular))
                        .foregroundStyle(item == step ? Color.primary : Color.secondary)
                }
                if item != .done {
                    Rectangle().fill(Color.hairline).frame(width: 28, height: 1)
                }
            }
        }
    }

    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 26, weight: .semibold))
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Paste an API key", "From any provider. Tact works out which one it is and picks a quick model for you.")

            VStack(alignment: .leading, spacing: 6) {
                SecureField("Paste here", text: $key)
                    .inputField()
                    .onChange(of: key) { _, new in
                        // The field is cleared after a successful check, which must not undo the result.
                        if !new.isEmpty { keyState = .empty }
                    }
                    .onSubmit(check)
                if needsProviderChoice {
                    Picker("Which provider is this key for?", selection: $pickedProviderID) {
                        Text("Choose").tag("")
                        ForEach(Provider.all.filter(\.needsKey)) { Text($0.name).tag($0.id) }
                    }
                    .fixedSize()
                }
                statusLine
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Your key stays in your Mac's Keychain and is only sent to that provider.")
                HStack(spacing: 4) {
                    Text("Need a key?")
                    ForEach(["anthropic", "openai", "google", "openrouter"], id: \.self) { id in
                        if let provider = Provider.named(id), let page = provider.keyPage, let url = URL(string: page) {
                            Link(provider.name, destination: url).underline().foregroundStyle(Color.primary)
                        }
                    }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)

            Spacer()
            HStack {
                Spacer()
                if case .connected = keyState {
                    Button("Continue") { step = .permission }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Check key", action: check)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(key.isEmpty || keyState == .checking || (needsProviderChoice && pickedProviderID.isEmpty))
                }
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch keyState {
        case .empty:
            if let first = candidates.first {
                Text("Looks like \(candidates.count > 1 ? candidates.map(\.name).joined(separator: " or ") : first.name)")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        case .checking:
            Text("Checking the key...").font(.system(size: 13)).foregroundStyle(.secondary)
        case .connected(let summary):
            Text(summary).font(.system(size: 13)).foregroundStyle(Color.connected)
        case .failed(let message):
            Text(message).font(.system(size: 13)).foregroundStyle(Color.diffRemoved)
        }
    }

    private func check() {
        let list = needsProviderChoice ? [Provider.named(pickedProviderID)].compactMap { $0 } : candidates
        guard !list.isEmpty else { return }
        keyState = .checking
        Task {
            do {
                let provider = try await store.connect(key: key, candidates: list)
                key = ""
                keyState = .connected("Connected to \(provider.name). Your model: \(store.settings.defaultModel?.modelName ?? "not set")")
            } catch {
                keyState = .failed(error.localizedDescription)
            }
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Let Tact reach your message box", "macOS asks for this once. It lets Tact read the message you typed and put the new version back in the box. It only runs when you press your shortcut.")

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility").fontWeight(.semibold)
                    Text(trusted ? "Allowed" : "Turn on Tact in the list, then come back here")
                        .font(.system(size: 13))
                        .foregroundStyle(trusted ? Color.connected : Color.secondary)
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
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.hairline))

            Spacer()
            HStack {
                Button("Back") { step = .key }.buttonStyle(GhostButtonStyle())
                Spacer()
                if !trusted {
                    Button("Skip, I'll copy results myself") {
                        skippedPermission = true
                        step = .done
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                Button("Continue") { step = .done }.buttonStyle(PrimaryButtonStyle()).disabled(!trusted)
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("That's it", "Type a message in any chat app, then press your shortcut. No need to select it.")

            HStack(spacing: 8) {
                ForEach(shortcutKeys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 24, weight: .medium))
                        .frame(minWidth: 64, minHeight: 64)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.surface))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hairline))

            VStack(alignment: .leading, spacing: 6) {
                Text("Find Tact in your menu bar, top right of the screen.")
                Text(skippedPermission || !trusted
                     ? "Results will be copied for you to paste. You can allow text replacement later in Settings."
                     : "Press Return in the panel and the new version goes straight into your message box.")
            }
            .foregroundStyle(.secondary)

            Spacer()
            HStack {
                Button("Back") { step = .permission }.buttonStyle(GhostButtonStyle())
                Spacer()
                Button("Start using Tact") {
                    store.settings.setupDone = true
                    onFinish()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var shortcutKeys: [String] {
        (store.settings.hotkeys[HotkeyAction.rewrite.rawValue] ?? HotkeyCombo.defaults[.rewrite]!).symbols
    }
}

func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
    }
}
