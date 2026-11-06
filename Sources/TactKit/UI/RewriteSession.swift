import Foundation
import Observation

/// One trip through the panel: the draft, every version produced, and the current state.
@MainActor
@Observable
final class RewriteSession {
    enum Tab: String, CaseIterable, Identifiable {
        case result = "Result", changes = "Changes", original = "Original"
        var id: String { rawValue }
    }

    struct Version: Identifiable {
        let id = UUID()
        var text: String
        var label: String
    }

    let store: AppStore
    let captured: CapturedText
    var draft: String
    var styleID: String
    var tab: Tab = .result
    var versions: [Version] = []
    var index = 0
    var refine = ""
    var isStreaming = false
    var errorText: String?
    /// Picked in the panel. Overrides the style's model for this session.
    var modelOverride: ModelRef?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastRun: (() -> Void)?

    init(store: AppStore, captured: CapturedText) {
        self.store = store
        self.captured = captured
        draft = captured.text
        styleID = store.styleID(forApp: captured.appName)
    }

    var style: Style? { store.style(id: styleID) }
    var model: ModelRef? { modelOverride ?? store.model(for: style) }
    var current: Version? { versions.indices.contains(index) ? versions[index] : nil }
    var currentText: String { current?.text ?? "" }
    var canUseResult: Bool { !isStreaming && !currentText.isEmpty }
    var isPickedForApp: Bool { style?.matches(app: captured.appName) == true }

    var sourceLabel: String {
        switch captured.source {
        case .clipboard: return "From clipboard"
        case .nothing: return "Type or paste your draft"
        case .selection: return isPickedForApp ? "Picked for \(captured.appName ?? "this app")" : "From your selection"
        case .wholeBox: return isPickedForApp ? "Picked for \(captured.appName ?? "this app")" : "From your message box"
        }
    }

    func begin() {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tab = .original
        } else if let style {
            generate(style: style, label: style.name)
        }
    }

    func pick(_ style: Style) {
        styleID = style.id
        store.settings.lastStyleID = style.id
        guard !draft.isEmpty else { return }
        generate(style: style, label: style.name)
    }

    func pickModel(_ ref: ModelRef) {
        modelOverride = ref
        if style?.model == nil { store.settings.defaultModel = ref }
        retry()
    }

    func retry() {
        if let lastRun {
            lastRun()
        } else {
            begin()
        }
    }

    func rewriteDraft() {
        guard let style, !draft.isEmpty else { return }
        generate(style: style, label: style.name)
    }

    func applyRefinement(_ note: String, label: String? = nil) {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, let style else { return }
        refine = ""
        let previous = currentText
        generate(style: style, label: label ?? "Your edit", previous: previous.isEmpty ? nil : previous, correction: previous.isEmpty ? nil : note)
    }

    func go(by step: Int) {
        let target = index + step
        guard versions.indices.contains(target), !isStreaming else { return }
        index = target
    }

    func cancel() {
        task?.cancel()
        task = nil
        isStreaming = false
    }

    private func generate(style: Style, label: String, previous: String? = nil, correction: String? = nil) {
        cancel()
        errorText = nil
        if versions.last?.text.isEmpty == true { versions.removeLast() }
        lastRun = { [weak self] in self?.generate(style: style, label: label, previous: previous, correction: correction) }

        let request: LLMRequest
        do {
            request = try store.request(style: style, model: model, draft: draft, previous: previous, correction: correction)
        } catch {
            errorText = error.localizedDescription
            return
        }

        versions.append(Version(text: "", label: label))
        index = versions.count - 1
        tab = .result
        isStreaming = true
        let position = index
        let draft = self.draft

        task = Task { [weak self] in
            do {
                for try await chunk in LLMClient.stream(request) {
                    if Task.isCancelled { return }
                    self?.versions[position].text += chunk
                }
                if Task.isCancelled { return }
                self?.finish(position, draft: draft)
            } catch {
                self?.fail(position, error)
            }
        }
    }

    private func finish(_ position: Int, draft: String) {
        isStreaming = false
        let cleaned = PromptBuilder.clean(versions[position].text, draft: draft)
        if cleaned.isEmpty {
            fail(position, LLMError.empty)
        } else {
            versions[position].text = cleaned
        }
    }

    private func fail(_ position: Int, _ error: Error) {
        isStreaming = false
        errorText = error.localizedDescription
        if versions.indices.contains(position), versions[position].text.isEmpty {
            versions.remove(at: position)
            index = max(0, versions.count - 1)
        }
    }
}
