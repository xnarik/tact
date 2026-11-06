import Foundation

public enum APIKind: String, Codable, Sendable {
    case anthropic, gemini, openAICompatible
}

public struct Provider: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let note: String
    public let kind: APIKind
    public let baseURL: String
    public let keyPrefix: String?
    public let keyPage: String?
    /// False for servers that run on this Mac or on the user's own network.
    public let needsKey: Bool
    /// Hints tried in order to pick a quick model, since chat rewrites should feel instant.
    public let fastHints: [String]
    /// For providers whose model list is public, so listing models says nothing about the key.
    public var keyCheckPath: String? = nil

    public var isLocal: Bool { !needsKey }

    public static let all: [Provider] = [
        Provider(id: "anthropic", name: "Anthropic", note: "Claude", kind: .anthropic,
                 baseURL: "https://api.anthropic.com/v1", keyPrefix: "sk-ant-",
                 keyPage: "https://console.anthropic.com/settings/keys", needsKey: true, fastHints: ["haiku", "sonnet"]),
        Provider(id: "openai", name: "OpenAI", note: "GPT", kind: .openAICompatible,
                 baseURL: "https://api.openai.com/v1", keyPrefix: "sk-",
                 keyPage: "https://platform.openai.com/api-keys", needsKey: true, fastHints: ["luna", "mini", "gpt"]),
        Provider(id: "google", name: "Google", note: "Gemini", kind: .gemini,
                 baseURL: "https://generativelanguage.googleapis.com/v1beta", keyPrefix: "AIza",
                 keyPage: "https://aistudio.google.com/apikey", needsKey: true, fastHints: ["flash-lite", "flash"]),
        Provider(id: "xai", name: "xAI", note: "Grok", kind: .openAICompatible,
                 baseURL: "https://api.x.ai/v1", keyPrefix: "xai-",
                 keyPage: "https://console.x.ai", needsKey: true, fastHints: ["fast", "mini", "grok"]),
        Provider(id: "mistral", name: "Mistral", note: "Mistral", kind: .openAICompatible,
                 baseURL: "https://api.mistral.ai/v1", keyPrefix: nil,
                 keyPage: "https://console.mistral.ai/api-keys", needsKey: true, fastHints: ["small", "medium"]),
        Provider(id: "deepseek", name: "DeepSeek", note: "DeepSeek", kind: .openAICompatible,
                 baseURL: "https://api.deepseek.com/v1", keyPrefix: nil,
                 keyPage: "https://platform.deepseek.com/api_keys", needsKey: true, fastHints: ["flash", "chat"]),
        Provider(id: "groq", name: "Groq", note: "Open models, very fast", kind: .openAICompatible,
                 baseURL: "https://api.groq.com/openai/v1", keyPrefix: "gsk_",
                 keyPage: "https://console.groq.com/keys", needsKey: true, fastHints: ["instant", "llama"]),
        Provider(id: "openrouter", name: "OpenRouter", note: "Hundreds of models, one key", kind: .openAICompatible,
                 baseURL: "https://openrouter.ai/api/v1", keyPrefix: "sk-or-",
                 keyPage: "https://openrouter.ai/keys", needsKey: true, fastHints: ["anthropic/claude-haiku", "openai/gpt"], keyCheckPath: "/key"),
        Provider(id: "local", name: "Ollama or LM Studio", note: "Runs on this Mac, no key", kind: .openAICompatible,
                 baseURL: "http://localhost:11434/v1", keyPrefix: nil,
                 keyPage: nil, needsKey: false, fastHints: []),
        Provider(id: "custom", name: "Custom", note: "Any OpenAI-compatible server", kind: .openAICompatible,
                 baseURL: "", keyPrefix: nil,
                 keyPage: nil, needsKey: false, fastHints: []),
    ]

    public static func named(_ id: String) -> Provider? {
        all.first { $0.id == id }
    }
}

public struct ModelInfo: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String? = nil) {
        self.id = id
        self.name = name ?? id
    }
}

public struct ModelRef: Codable, Hashable, Sendable {
    public var providerID: String
    public var modelID: String
    public var modelName: String

    public init(providerID: String, modelID: String, modelName: String) {
        self.providerID = providerID
        self.modelID = modelID
        self.modelName = modelName
    }
}

public enum KeyDetector {
    /// Providers a pasted key could belong to, most likely first. An empty result means the key
    /// has no recognisable prefix, so the person picks the provider rather than us guessing and
    /// sending their key somewhere it may not belong.
    public static func candidates(for key: String) -> [Provider] {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids: [String]
        if key.hasPrefix("sk-ant-") {
            ids = ["anthropic"]
        } else if key.hasPrefix("sk-or-") {
            ids = ["openrouter"]
        } else if key.hasPrefix("AIza") {
            ids = ["google"]
        } else if key.hasPrefix("xai-") {
            ids = ["xai"]
        } else if key.hasPrefix("gsk_") {
            ids = ["groq"]
        } else if key.hasPrefix("sk-") {
            ids = ["openai", "deepseek"]
        } else {
            ids = []
        }
        return ids.compactMap(Provider.named)
    }
}

public enum ModelRanker {
    private static let nonTextWords = [
        "embed", "whisper", "tts", "audio", "realtime", "transcribe", "image", "dall-e", "moderation",
        "sora", "veo", "imagen", "lyria", "rerank", "ocr", "guard", "aqa", "computer", "robotics",
        "live", "deep-research", "babbage", "davinci", "instruct", "codex",
    ]

    public static func isTextModel(_ id: String) -> Bool {
        let lower = id.lowercased()
        return !nonTextWords.contains { lower.contains($0) }
    }

    /// Numbers in a model ID, newest-looking first when compared. Dates are ignored so that
    /// `claude-haiku-5-5` outranks an older dated snapshot.
    private static func version(_ id: String) -> [Int] {
        id.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { $0 < 1000 }
    }

    private static func isNewer(_ a: ModelInfo, _ b: ModelInfo) -> Bool {
        version(a.id).lexicographicallyPrecedes(version(b.id)) == false && version(a.id) != version(b.id)
    }

    public static func sorted(_ models: [ModelInfo]) -> [ModelInfo] {
        models.sorted { a, b in
            if version(a.id) == version(b.id) { return a.id < b.id }
            return isNewer(a, b)
        }
    }

    public static func fastest(_ models: [ModelInfo], for provider: Provider) -> ModelInfo? {
        let stable = models.filter { !$0.id.lowercased().contains("preview") && !$0.id.lowercased().contains("-exp") }
        let pool = stable.isEmpty ? models : stable
        for hint in provider.fastHints {
            let matches = pool.filter { $0.id.lowercased().contains(hint) }
            if let best = sorted(matches).first { return best }
        }
        return sorted(pool).first
    }
}
