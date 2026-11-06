import Foundation
import Observation
import Security

public enum Keychain {
    private static let service = "com.kirants.tact.apikeys"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    public static func load(account: String) -> String? {
        var item = query(account)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

public enum HotkeyAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case rewrite, instantFix, repeatLast, history

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rewrite: return "Rewrite"
        case .instantFix: return "Instant fix"
        case .repeatLast: return "Repeat last style"
        case .history: return "Open history"
        }
    }

    public var note: String {
        switch self {
        case .rewrite: return "Opens the panel on the message you typed"
        case .instantFix: return "Rewrites your message right away, no panel"
        case .repeatLast: return "Same style on a new message, no panel"
        case .history: return "Find something you wrote earlier"
        }
    }
}

public struct HotkeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public static let command: UInt32 = 256, shift: UInt32 = 512, option: UInt32 = 2048, control: UInt32 = 4096

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var symbols: [String] {
        var parts: [String] = []
        if modifiers & Self.control != 0 { parts.append("⌃") }
        if modifiers & Self.option != 0 { parts.append("⌥") }
        if modifiers & Self.shift != 0 { parts.append("⇧") }
        if modifiers & Self.command != 0 { parts.append("⌘") }
        parts.append(Self.keyNames[keyCode] ?? "Key \(keyCode)")
        return parts
    }

    public var text: String { symbols.joined() }

    static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab",
        49: "Space", 50: "`", 51: "Delete", 53: "Esc", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    public static let defaults: [HotkeyAction: HotkeyCombo] = [
        .rewrite: HotkeyCombo(keyCode: 15, modifiers: control | option),
        .instantFix: HotkeyCombo(keyCode: 3, modifiers: control | option),
        .repeatLast: HotkeyCombo(keyCode: 37, modifiers: control | option),
        .history: HotkeyCombo(keyCode: 4, modifiers: control | option),
    ]
}

public enum KeepHistory: String, Codable, CaseIterable, Identifiable, Sendable {
    case week = "7 days", month = "30 days", forever = "Forever", never = "Don't save"

    public var id: String { rawValue }

    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .forever, .never: return nil
        }
    }
}

public enum Appearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "Match macOS", light = "Light", dark = "Dark"
    public var id: String { rawValue }
}

public struct AppSettings: Codable, Sendable {
    public var setupDone = false
    public var styles = Style.defaults
    public var lastStyleID = "clear"
    public var instantStyleID = "fix"
    public var defaultModel: ModelRef?
    public var connected: [String] = []
    public var models: [String: [ModelInfo]] = [:]
    public var baseURLs: [String: String] = [:]
    public var hotkeys: [String: HotkeyCombo] = Dictionary(uniqueKeysWithValues: HotkeyCombo.defaults.map { ($0.key.rawValue, $0.value) })
    public var keepHistory = KeepHistory.month
    public var showSend = true
    public var restoreClipboard = true
    public var matchLanguage = true
    public var appearance = Appearance.system

    public init() {}

    enum CodingKeys: String, CodingKey {
        case setupDone, styles, lastStyleID, instantStyleID, defaultModel, connected, models, baseURLs
        case hotkeys, keepHistory, showSend, restoreClipboard, matchLanguage, appearance
    }

    /// Reads whatever is present and falls back to the defaults, so that adding a setting later
    /// doesn't throw away a saved file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        setupDone = (try? c.decode(Bool.self, forKey: .setupDone)) ?? d.setupDone
        styles = (try? c.decode([Style].self, forKey: .styles)) ?? d.styles
        lastStyleID = (try? c.decode(String.self, forKey: .lastStyleID)) ?? d.lastStyleID
        instantStyleID = (try? c.decode(String.self, forKey: .instantStyleID)) ?? d.instantStyleID
        defaultModel = try? c.decode(ModelRef.self, forKey: .defaultModel)
        connected = (try? c.decode([String].self, forKey: .connected)) ?? d.connected
        models = (try? c.decode([String: [ModelInfo]].self, forKey: .models)) ?? d.models
        baseURLs = (try? c.decode([String: String].self, forKey: .baseURLs)) ?? d.baseURLs
        hotkeys = (try? c.decode([String: HotkeyCombo].self, forKey: .hotkeys)) ?? d.hotkeys
        keepHistory = (try? c.decode(KeepHistory.self, forKey: .keepHistory)) ?? d.keepHistory
        showSend = (try? c.decode(Bool.self, forKey: .showSend)) ?? d.showSend
        restoreClipboard = (try? c.decode(Bool.self, forKey: .restoreClipboard)) ?? d.restoreClipboard
        matchLanguage = (try? c.decode(Bool.self, forKey: .matchLanguage)) ?? d.matchLanguage
        appearance = (try? c.decode(Appearance.self, forKey: .appearance)) ?? d.appearance
    }
}

public struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var original: String
    public var result: String
    public var style: String
    public var model: String

    public init(original: String, result: String, style: String, model: String) {
        self.original = original
        self.result = result
        self.style = style
        self.model = model
    }
}

@MainActor
@Observable
public final class AppStore {
    public var settings: AppSettings {
        didSet { write(settings, to: settingsURL) }
    }
    public private(set) var history: [HistoryEntry]

    private static let historyLimit = 500
    @ObservationIgnored private let settingsURL: URL
    @ObservationIgnored private let historyURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tact", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        settingsURL = base.appendingPathComponent("settings.json")
        historyURL = base.appendingPathComponent("history.json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        settings = (try? Data(contentsOf: settingsURL)).flatMap { try? decoder.decode(AppSettings.self, from: $0) } ?? AppSettings()
        history = (try? Data(contentsOf: historyURL)).flatMap { try? decoder.decode([HistoryEntry].self, from: $0) } ?? []
        pruneHistory()
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: Styles

    public var styles: [Style] { settings.styles }

    public func style(id: String) -> Style? {
        settings.styles.first { $0.id == id }
    }

    /// The style for this app if one claims it, otherwise whatever was used last.
    public func styleID(forApp app: String?) -> String {
        if let match = settings.styles.first(where: { $0.matches(app: app) }) { return match.id }
        if style(id: settings.lastStyleID) != nil { return settings.lastStyleID }
        return settings.styles.first?.id ?? ""
    }

    // MARK: Providers

    public func baseURL(for provider: Provider) -> String {
        let custom = settings.baseURLs[provider.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom?.isEmpty == false ? custom! : provider.baseURL
    }

    public var connectedProviders: [Provider] {
        Provider.all.filter { settings.connected.contains($0.id) }
    }

    public func models(for provider: Provider) -> [ModelInfo] {
        settings.models[provider.id] ?? []
    }

    /// The key is only stored once the provider has accepted it.
    @discardableResult
    public func connect(_ provider: Provider, key: String?, baseURL: String? = nil) async throws -> [ModelInfo] {
        let key = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let baseURL { settings.baseURLs[provider.id] = baseURL }
        let models = try await LLMClient.listModels(provider: provider, key: key, baseURL: self.baseURL(for: provider))
        if let key, !key.isEmpty { Keychain.save(key, account: provider.id) }
        register(provider, models: models)
        return models
    }

    /// Tries each provider a key could belong to, moving on only when one clearly rejects it.
    public func connect(key: String, candidates: [Provider]) async throws -> Provider {
        var rejection: Error?
        for provider in candidates {
            do {
                try await connect(provider, key: key)
                return provider
            } catch let error as LLMError where error.isKeyRejection {
                rejection = rejection ?? error
            } catch {
                // A later provider being unreachable shouldn't hide that the likely one said no.
                throw rejection ?? error
            }
        }
        throw rejection ?? LLMError.noModel
    }

    func register(_ provider: Provider, models: [ModelInfo]) {
        settings.models[provider.id] = models
        if !settings.connected.contains(provider.id) { settings.connected.append(provider.id) }
        if settings.defaultModel == nil, let best = ModelRanker.fastest(models, for: provider) {
            settings.defaultModel = ModelRef(providerID: provider.id, modelID: best.id, modelName: best.name)
        }
    }

    public func refreshModels(_ provider: Provider) async throws {
        let models = try await LLMClient.listModels(provider: provider, key: Keychain.load(account: provider.id), baseURL: baseURL(for: provider))
        settings.models[provider.id] = models
    }

    public func disconnect(_ provider: Provider) {
        Keychain.delete(account: provider.id)
        settings.connected.removeAll { $0 == provider.id }
        settings.models[provider.id] = nil
        if settings.defaultModel?.providerID == provider.id {
            settings.defaultModel = connectedProviders.lazy.compactMap { p in
                ModelRanker.fastest(self.models(for: p), for: p).map { ModelRef(providerID: p.id, modelID: $0.id, modelName: $0.name) }
            }.first
        }
        for index in settings.styles.indices where settings.styles[index].model?.providerID == provider.id {
            settings.styles[index].model = nil
        }
    }

    public func model(for style: Style?) -> ModelRef? {
        style?.model ?? settings.defaultModel
    }

    public func request(style: Style, model: ModelRef?, draft: String, previous: String? = nil, correction: String? = nil) throws -> LLMRequest {
        guard let ref = model ?? self.model(for: style), let provider = Provider.named(ref.providerID) else { throw LLMError.noModel }
        let key = Keychain.load(account: provider.id)
        if provider.needsKey, key?.isEmpty != false { throw LLMError.missingKey(provider.name) }
        return LLMRequest(
            provider: provider, modelID: ref.modelID, apiKey: key, baseURL: baseURL(for: provider),
            system: PromptBuilder.system(style: style, matchLanguage: settings.matchLanguage),
            user: PromptBuilder.user(draft: draft, previous: previous, correction: correction))
    }

    // MARK: History

    public func addHistory(_ entry: HistoryEntry) {
        guard settings.keepHistory != .never else { return }
        history.insert(entry, at: 0)
        pruneHistory()
        write(history, to: historyURL)
    }

    public func removeHistory(_ entry: HistoryEntry) {
        history.removeAll { $0.id == entry.id }
        write(history, to: historyURL)
    }

    public func clearHistory() {
        history = []
        write(history, to: historyURL)
    }

    public func pruneHistory() {
        if settings.keepHistory == .never {
            history = []
        } else if let days = settings.keepHistory.days {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            history.removeAll { $0.date < cutoff }
        }
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
    }

    public func applyHistoryPolicy() {
        pruneHistory()
        write(history, to: historyURL)
    }
}
