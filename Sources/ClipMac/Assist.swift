//  The optional "ask your clipboard" layer. Three tiers, each stricter than the last about what
//  leaves the machine:
//
//   Tier 1  Semantic search with NLEmbedding. On-device, no download, on by default.
//   Tier 2  Apple's on-device Foundation Models framework (macOS 26+). Opt-in. Never leaves the Mac.
//   Tier 3  Bring your own key, plain HTTPS to the provider. Opt-in, per-query confirmation,
//           Redactor runs first and the masked payload is shown before anything is sent, and
//           every request is logged (`clipmac assist log`). No proxy, no account, no relay.

import Foundation
import NaturalLanguage
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

final class Assist {
    static let shared = Assist()

    // MARK: - Tier 1: semantic search

    private let embedding: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: Capabilities.embeddingLanguage)
    let modelTag = "nl-sentence-" + Capabilities.embeddingLanguage.rawValue
    private let indexQueue = DispatchQueue(label: "com.keithadler.clipmac.index", qos: .utility)
    private var indexScheduled = false
    private var cache: [(Int64, [Float])] = []
    private var cacheLoaded = false
    private let cacheLock = NSLock()

    func vector(for text: String) -> [Float]? {
        guard let embedding else { return nil }
        let clipped = String(text.prefix(2000))
        guard let v = embedding.vector(for: clipped) else { return nil }
        var f = v.map { Float($0) }
        let norm = sqrt(f.reduce(0) { $0 + $1 * $1 })
        if norm > 0 { f = f.map { $0 / norm } }
        return f
    }

    /// Embeds items that don't have a vector yet. Cheap; runs shortly after every capture.
    func indexSoon() {
        guard Prefs.semanticSearch, embedding != nil else { return }
        indexQueue.async { [self] in
            guard !indexScheduled else { return }
            indexScheduled = true
            indexQueue.asyncAfter(deadline: .now() + 1.5) { [self] in
                indexScheduled = false
                indexPending()
            }
        }
    }

    func indexPending(limit: Int = 200) {
        guard embedding != nil else { return }
        let missing = Store.shared.itemsMissingVectors(model: modelTag, limit: limit)
        for item in missing {
            guard let v = vector(for: item.plain) else { continue }
            Store.shared.setVector(item.id, model: modelTag, v)
        }
        if !missing.isEmpty { cacheLock.lock(); cacheLoaded = false; cacheLock.unlock() }
    }

    private func vectors() -> [(Int64, [Float])] {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if !cacheLoaded { cache = Store.shared.allVectors(model: modelTag); cacheLoaded = true }
        return cache
    }

    /// Items whose meaning is close to the query. Brute-force cosine over the whole history is a few
    /// milliseconds for the default 2,000-item cap.
    func semanticSearch(_ query: String, limit: Int = 6, floor: Float = 0.33, margin: Float = 0.10) -> [(Item, Float)] {
        // Apple's sentence embeddings score related text around 0.4-0.5 and unrelated text under 0.3, so
        // use a low floor and keep only results close to the best one.
        guard Prefs.semanticSearch, let q = vector(for: query) else { return [] }
        var scored: [(Int64, Float)] = []
        for (id, v) in vectors() where v.count == q.count {
            var dot: Float = 0
            for i in 0..<v.count { dot += v[i] * q[i] }
            if dot >= floor { scored.append((id, dot)) }
        }
        scored.sort { $0.1 > $1.1 }
        if let best = scored.first?.1 { scored = scored.filter { $0.1 >= best - margin } }
        return scored.prefix(limit).compactMap { pair in Store.shared.get(pair.0).map { ($0, pair.1) } }
    }

    // MARK: - Context building (shared by tiers 2 and 3)

    static func context(for items: [Item], maxChars: Int = 60_000) -> String {
        var out = ""
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        for (i, item) in items.enumerated() {
            let body: String
            switch item.kind {
            case .image: body = "[image, \(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))]"
            case .file: body = "[files] " + item.filePaths.joined(separator: ", ")
            default: body = item.plain
            }
            let entry = "### \(i + 1). \(f.string(from: item.createdAt)) · \(item.sourceName ?? "unknown app")\n\(body)\n\n"
            if out.count + entry.count > maxChars { out += "… (\(items.count - i) more items omitted for length)\n"; break }
            out += entry
        }
        return out
    }

    static let instructions = "You are helping someone recall and organize things they copied to their clipboard today. Answer from the items provided; say so when the answer isn't in them. Be brief."

    // MARK: - Tier 2: on-device model

    func askOnDevice(_ prompt: String, items: [Item]) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            guard Capabilities.onDeviceModelAvailable else { throw AssistError.unavailable(Capabilities.onDeviceModelNote) }
            let session = LanguageModelSession(instructions: Assist.instructions)
            let ctx = Assist.context(for: items, maxChars: 12_000)
            let response = try await session.respond(to: "Clipboard items:\n\n\(ctx)\nQuestion: \(prompt)")
            Store.shared.logAssist(provider: "apple-on-device", model: "SystemLanguageModel", itemCount: items.count,
                                   chars: ctx.count, inputTokens: 0, outputTokens: 0, prompt: prompt)
            return response.content
        }
        #endif
        throw AssistError.unavailable(Capabilities.onDeviceModelNote)
    }

    // MARK: - Tier 3: bring your own key

    enum Provider: String, CaseIterable, Identifiable {
        case anthropic, openai
        var id: String { rawValue }
        var label: String { self == .anthropic ? "Anthropic (Claude)" : "OpenAI" }
        var endpoint: URL { URL(string: self == .anthropic ? "https://api.anthropic.com/v1/messages" : "https://api.openai.com/v1/chat/completions")! }
    }

    struct Prepared {
        let prompt: String
        let maskedContext: String
        let labels: [String]
        let itemCount: Int
        var chars: Int { maskedContext.count + prompt.count }
    }

    /// Redacts, then returns exactly what would be sent, for the user to read before confirming.
    func prepareCloud(_ prompt: String, items: [Item]) -> Prepared {
        // Items copied from an excluded app should never be here, but belt and braces.
        let safe = items.filter { !($0.sourceBundleID.map { Prefs.excludedBundleIDs.contains($0) } ?? false) }
        let raw = Assist.context(for: safe)
        let (masked, labels) = Redactor.mask(raw)
        return Prepared(prompt: prompt, maskedContext: masked, labels: labels, itemCount: safe.count)
    }

    struct CloudReply { let text: String; let inputTokens: Int; let outputTokens: Int; let model: String }

    /// Sends the prepared (already masked and confirmed) payload. Their key, their bill, their data.
    func sendCloud(_ p: Prepared, provider: Provider = Provider(rawValue: Prefs.cloudProvider) ?? .anthropic,
                   model: String = Prefs.cloudModel) async throws -> CloudReply {
        guard let key = Assist.apiKey(for: provider), !key.isEmpty else { throw AssistError.noKey(provider) }
        var req = URLRequest(url: provider.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 120
        let user = "Clipboard items:\n\n\(p.maskedContext)\nQuestion: \(p.prompt)"
        let body: [String: Any]
        switch provider {
        case .anthropic:
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": model, "max_tokens": 4096, "system": Assist.instructions,
                    "messages": [["role": "user", "content": user]]]
        case .openai:
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = ["model": model,
                    "messages": [["role": "system", "content": Assist.instructions], ["role": "user", "content": user]]]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AssistError.badResponse("not JSON") }
        guard (200..<300).contains(status) else {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            throw AssistError.badResponse(msg)
        }
        let reply: CloudReply
        switch provider {
        case .anthropic:
            let usage = json["usage"] as? [String: Any] ?? [:]
            let blocks = json["content"] as? [[String: Any]] ?? []
            var text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
            if json["stop_reason"] as? String == "refusal" {
                let why = ((json["stop_details"] as? [String: Any])?["explanation"] as? String) ?? ""
                text = text.isEmpty ? String(localized: "The model declined this request.") + " " + why : text
            }
            reply = CloudReply(text: text, inputTokens: usage["input_tokens"] as? Int ?? 0, outputTokens: usage["output_tokens"] as? Int ?? 0,
                               model: json["model"] as? String ?? model)
        case .openai:
            let usage = json["usage"] as? [String: Any] ?? [:]
            let choice = (json["choices"] as? [[String: Any]])?.first
            let text = ((choice?["message"] as? [String: Any])?["content"] as? String) ?? ""
            reply = CloudReply(text: text, inputTokens: usage["prompt_tokens"] as? Int ?? 0, outputTokens: usage["completion_tokens"] as? Int ?? 0,
                               model: json["model"] as? String ?? model)
        }
        Store.shared.logAssist(provider: provider.rawValue, model: reply.model, itemCount: p.itemCount, chars: p.chars,
                               inputTokens: reply.inputTokens, outputTokens: reply.outputTokens, prompt: p.prompt)
        return reply
    }

    // MARK: - Keychain

    private static let service = "com.keithadler.clipmac"

    static func apiKey(for provider: Provider) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: provider.rawValue, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func setAPIKey(_ key: String?, for provider: Provider) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: provider.rawValue]
        SecItemDelete(base as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrLabel as String] = "Clip for Mac — \(provider.label) API key"
        SecItemAdd(add as CFDictionary, nil)
    }
}

enum AssistError: LocalizedError {
    case unavailable(String), noKey(Assist.Provider), badResponse(String), cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable(let s): return s
        case .noKey(let p): return String(format: String(localized: "No %@ API key is stored. Add one in Settings › Assist."), p.label)
        case .badResponse(let s): return s
        case .cancelled: return String(localized: "Cancelled.")
        }
    }
}
