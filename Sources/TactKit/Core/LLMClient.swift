import Foundation

public struct LLMRequest: Sendable {
    public var provider: Provider
    public var modelID: String
    public var apiKey: String?
    public var baseURL: String
    public var system: String
    public var user: String

    public init(provider: Provider, modelID: String, apiKey: String?, baseURL: String, system: String, user: String) {
        self.provider = provider
        self.modelID = modelID
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.system = system
        self.user = user
    }
}

public enum LLMError: LocalizedError, Equatable {
    case noModel
    case missingKey(String)
    case badKey(String)
    case rateLimited(String)
    case modelUnavailable(String)
    case badAddress
    case refused
    case empty
    case network(String)
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .noModel: return "No model is set up yet. Add a provider in Settings."
        case .missingKey(let name): return "Add your \(name) API key in Settings."
        case .badKey(let name): return "\(name) rejected this API key. Check it in Settings."
        case .rateLimited(let name): return "\(name) says you've hit a rate or credit limit. Try again shortly, or pick another model."
        case .modelUnavailable(let name): return "This model isn't available on \(name). Pick another one."
        case .badAddress: return "That server address isn't valid. Check it in Settings."
        case .refused: return "The model declined to rewrite this message. Try another model."
        case .empty: return "The model returned nothing. Try again."
        case .network(let message), .server(let message): return message
        }
    }

    /// Only a clear rejection means "wrong key", which is what lets us try the next candidate.
    var isKeyRejection: Bool {
        if case .badKey = self { return true }
        return false
    }
}

enum SSE {
    /// Pulls the text out of one streamed line. Lines that carry no text return nil.
    static func text(from line: String, kind: APIKind) throws -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let message = errorMessage(in: json) {
            throw LLMError.server(message)
        }

        switch kind {
        case .anthropic:
            let delta = json["delta"] as? [String: Any]
            if delta?["stop_reason"] as? String == "refusal" { throw LLMError.refused }
            guard json["type"] as? String == "content_block_delta", delta?["type"] as? String == "text_delta" else { return nil }
            return delta?["text"] as? String

        case .gemini:
            if (json["promptFeedback"] as? [String: Any])?["blockReason"] != nil { throw LLMError.refused }
            guard let candidate = (json["candidates"] as? [[String: Any]])?.first else { return nil }
            if candidate["finishReason"] as? String == "SAFETY" { throw LLMError.refused }
            let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]]
            let text = parts?.compactMap { $0["text"] as? String }.joined()
            return text?.isEmpty == false ? text : nil

        case .openAICompatible:
            let choice = (json["choices"] as? [[String: Any]])?.first
            let text = (choice?["delta"] as? [String: Any])?["content"] as? String
            return text?.isEmpty == false ? text : nil
        }
    }

    static func errorMessage(in json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let error = json["error"] as? String { return error }
        return json["detail"] as? String
    }
}

public enum LLMClient {
    static func endpoint(_ base: String, _ path: String) throws -> URL {
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n"))
        guard let url = URL(string: trimmed + path), url.scheme?.hasPrefix("http") == true else { throw LLMError.badAddress }
        return url
    }

    private static func addAuth(_ request: inout URLRequest, provider: Provider, key: String?) {
        guard let key, !key.isEmpty else { return }
        switch provider.kind {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        case .gemini:
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .openAICompatible:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        if provider.kind == .anthropic {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
    }

    /// Sampling settings such as temperature are left out on purpose: current models from several
    /// providers reject them, so creativity is expressed in the prompt instead.
    static func makeRequest(_ r: LLMRequest) throws -> URLRequest {
        let url: URL
        let body: [String: Any]

        switch r.provider.kind {
        case .anthropic:
            url = try endpoint(r.baseURL, "/messages")
            var fields: [String: Any] = [
                "model": r.modelID,
                "max_tokens": 4096,
                "stream": true,
                "system": r.system,
                "messages": [["role": "user", "content": r.user]],
            ]
            // A short rewrite doesn't need deep thought, and low effort keeps replies quick.
            if r.modelID.range(of: #"^claude-[a-z]+-5"#, options: .regularExpression) != nil {
                fields["output_config"] = ["effort": "low"]
            }
            body = fields

        case .gemini:
            let model = r.modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? r.modelID
            url = try endpoint(r.baseURL, "/models/\(model):streamGenerateContent?alt=sse")
            body = [
                "system_instruction": ["parts": [["text": r.system]]],
                "contents": [["role": "user", "parts": [["text": r.user]]]],
            ]

        case .openAICompatible:
            url = try endpoint(r.baseURL, "/chat/completions")
            body = [
                "model": r.modelID,
                "stream": true,
                "messages": [
                    ["role": "system", "content": r.system],
                    ["role": "user", "content": r.user],
                ],
            ]
        }

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request, provider: r.provider, key: r.apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func error(status: Int, body: Data, provider: Provider) -> LLMError {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let detail = json.flatMap(SSE.errorMessage)
        // Google and xAI report a bad key as a plain 400.
        if status == 400, detail?.lowercased().contains("api key") == true { return .badKey(provider.name) }
        switch status {
        case 401, 403: return .badKey(provider.name)
        case 402, 429: return .rateLimited(provider.name)
        case 404: return .modelUnavailable(provider.name)
        default:
            let summary = detail.map { String($0.prefix(200)) } ?? "HTTP \(status)"
            return .server("\(provider.name) returned an error: \(summary)")
        }
    }

    static func describe(_ error: Error, provider: Provider) -> Error {
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return LLMError.network("You seem to be offline.")
        case .timedOut:
            return LLMError.network("\(provider.name) took too long to reply. Try again.")
        case .cannotConnectToHost, .cannotFindHost:
            return LLMError.network(provider.isLocal ? "Can't reach \(provider.name). Is it running?" : "Can't reach \(provider.name).")
        default:
            return LLMError.network(urlError.localizedDescription)
        }
    }

    public static func stream(_ r: LLMRequest, session: URLSession = .shared) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: try makeRequest(r))
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                            if data.count > 16_384 { break }
                        }
                        throw error(status: http.statusCode, body: data, provider: r.provider)
                    }
                    for try await line in bytes.lines {
                        if let text = try SSE.text(from: line, kind: r.provider.kind) {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let urlError as URLError where urlError.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: describe(error, provider: r.provider))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static func complete(_ r: LLMRequest, session: URLSession = .shared) async throws -> String {
        var text = ""
        for try await chunk in stream(r, session: session) { text += chunk }
        return text
    }

    /// Also doubles as the key check, since it needs a working key and costs nothing to call.
    public static func listModels(provider: Provider, key: String?, baseURL: String, session: URLSession = .shared) async throws -> [ModelInfo] {
        let path: String
        switch provider.kind {
        case .anthropic: path = "/models?limit=1000"
        case .gemini: path = "/models?pageSize=1000"
        case .openAICompatible: path = "/models"
        }
        if let checkPath = provider.keyCheckPath {
            _ = try await fetch(try endpoint(baseURL, checkPath), provider: provider, key: key, session: session)
        }
        let data = try await fetch(try endpoint(baseURL, path), provider: provider, key: key, session: session)
        return try parseModels(data, kind: provider.kind)
    }

    private static func fetch(_ url: URL, provider: Provider, key: String?, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        addAuth(&request, provider: provider, key: key)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw describe(error, provider: provider)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw self.error(status: http.statusCode, body: data, provider: provider)
        }
        return data
    }

    static func parseModels(_ data: Data, kind: APIKind) throws -> [ModelInfo] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let models: [ModelInfo]
        switch kind {
        case .gemini:
            let items = json["models"] as? [[String: Any]] ?? []
            models = items.compactMap { item in
                guard let name = item["name"] as? String,
                      (item["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true
                else { return nil }
                return ModelInfo(id: name.replacingOccurrences(of: "models/", with: ""), name: item["displayName"] as? String)
            }
        case .anthropic, .openAICompatible:
            let items = json["data"] as? [[String: Any]] ?? []
            models = items.compactMap { item in
                guard let id = item["id"] as? String else { return nil }
                return ModelInfo(id: id, name: (item["display_name"] as? String) ?? (item["name"] as? String))
            }
        }
        return ModelRanker.sorted(models.filter { ModelRanker.isTextModel($0.id) })
    }
}
