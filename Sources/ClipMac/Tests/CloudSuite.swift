import Foundation

/// Serves canned HTTP responses to Assist without touching the network or the Keychain.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: [String: Any]?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        StubURLProtocol.lastRequest = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
            defer { buf.deallocate() }
            while stream.hasBytesAvailable { let n = stream.read(buf, maxLength: 65536); if n <= 0 { break }; data.append(buf, count: n) }
            StubURLProtocol.lastBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        } else if let body = request.httpBody {
            StubURLProtocol.lastBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        }
        let (status, data) = StubURLProtocol.handler?(request) ?? (500, Data())
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

enum CloudSuite {
    static func stubbed(_ status: Int, _ json: [String: Any], key: String? = "test-key", body: @escaping @Sendable () async throws -> Assist.CloudReply) -> Result<Assist.CloudReply, Error> {
        let assist = Assist.shared
        let savedSession = assist.session, savedKeys = assist.keyProvider
        defer { assist.session = savedSession; assist.keyProvider = savedKeys }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        assist.session = URLSession(configuration: cfg)
        assist.keyProvider = { _ in key }
        StubURLProtocol.handler = { _ in (status, try! JSONSerialization.data(withJSONObject: json)) }
        StubURLProtocol.lastRequest = nil; StubURLProtocol.lastBody = nil
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<Assist.CloudReply, Error> = .failure(AssistError.cancelled)
        let work = body
        Task.detached { do { result = .success(try await work()) } catch { result = .failure(error) }; sem.signal() }
        _ = sem.wait(timeout: .now() + 10)
        return result
    }

    static func prepared() -> Assist.Prepared {
        let s = Store.shared
        let a = s.insert(TestKit.capture("deploy with sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdef"))
        let b = s.insert(TestKit.capture("meeting at 3"))
        return Assist.shared.prepareCloud("what did I do?", items: [a, b])
    }

    static let suite = TestSuite(name: "Cloud", cases: [
        TestCase(name: "anthropic request shape and reply parsing") { t in
            let p = prepared()
            let r = stubbed(200, ["model": "claude-opus-5", "stop_reason": "end_turn",
                                  "content": [["type": "text", "text": "You deployed and met."]],
                                  "usage": ["input_tokens": 123, "output_tokens": 9]]) {
                try await Assist.shared.sendCloud(p, provider: .anthropic, model: "claude-opus-5")
            }
            guard case .success(let reply) = r else { t.fail("request failed: \(r)"); return }
            t.equal(reply.text, "You deployed and met.", "text block")
            t.equal(reply.inputTokens, 123, "input tokens")
            t.equal(reply.outputTokens, 9, "output tokens")
            let req = StubURLProtocol.lastRequest
            t.equal(req?.url?.absoluteString, "https://api.anthropic.com/v1/messages", "endpoint")
            t.equal(req?.value(forHTTPHeaderField: "x-api-key"), "test-key", "key header")
            t.equal(req?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01", "version header")
            t.check(req?.value(forHTTPHeaderField: "Authorization") == nil, "no bearer header for anthropic")
            let body = StubURLProtocol.lastBody
            t.equal(body?["model"] as? String, "claude-opus-5", "model")
            t.equal(body?["max_tokens"] as? Int, 4096, "max tokens")
            t.check((body?["system"] as? String)?.contains("clipboard") ?? false, "system prompt")
            let messages = body?["messages"] as? [[String: Any]]
            t.equal(messages?.count, 1, "one user message")
            let content = messages?.first?["content"] as? String ?? ""
            t.check(content.contains("meeting at 3") && content.contains("what did I do?"), "context and question sent")
            t.check(!content.contains("sk-ant-api03"), "the secret never leaves")
            t.check(content.contains("[REDACTED API KEY]"), "masked marker sent instead")
            let log = Store.shared.assistLog()
            t.equal(log.count, 1, "logged")
            t.equal(log.first?.provider, "anthropic", "provider logged")
            t.equal(log.first?.inputTokens, 123, "tokens logged")
            t.equal(log.first?.prompt, "what did I do?", "prompt logged")
        },
        TestCase(name: "anthropic refusal is surfaced, not hidden") { t in
            let p = prepared()
            let r = stubbed(200, ["model": "claude-opus-5", "stop_reason": "refusal", "content": [],
                                  "stop_details": ["type": "refusal", "category": "cyber", "explanation": "declined for policy"],
                                  "usage": ["input_tokens": 5, "output_tokens": 0]]) {
                try await Assist.shared.sendCloud(p, provider: .anthropic)
            }
            guard case .success(let reply) = r else { t.fail("request failed: \(r)"); return }
            t.check(reply.text.contains("declined"), "explains the refusal")
            t.check(reply.text.contains("policy"), "carries the explanation")
        },
        TestCase(name: "openai request shape and reply parsing") { t in
            let p = prepared()
            let r = stubbed(200, ["model": "gpt-5", "choices": [["message": ["role": "assistant", "content": "Two things."]]],
                                  "usage": ["prompt_tokens": 50, "completion_tokens": 3]]) {
                try await Assist.shared.sendCloud(p, provider: .openai, model: "gpt-5")
            }
            guard case .success(let reply) = r else { t.fail("request failed: \(r)"); return }
            t.equal(reply.text, "Two things.", "content")
            t.equal(reply.inputTokens, 50, "prompt tokens")
            t.equal(reply.outputTokens, 3, "completion tokens")
            let req = StubURLProtocol.lastRequest
            t.equal(req?.url?.host, "api.openai.com", "endpoint")
            t.equal(req?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key", "bearer header")
            t.check(req?.value(forHTTPHeaderField: "x-api-key") == nil, "no anthropic header for openai")
            let messages = StubURLProtocol.lastBody?["messages"] as? [[String: Any]]
            t.equal(messages?.count, 2, "system plus user")
            t.equal(messages?.first?["role"] as? String, "system", "system first")
            t.equal(Store.shared.assistLog().first?.provider, "openai", "logged as openai")
        },
        TestCase(name: "errors: missing key, http error, non-json") { t in
            let p = prepared()
            let noKey = stubbed(200, [:], key: nil) { try await Assist.shared.sendCloud(p, provider: .anthropic) }
            if case .failure(let e) = noKey, case AssistError.noKey(let prov) = e { t.equal(prov, .anthropic, "no key names provider") } else { t.fail("expected noKey, got \(noKey)") }
            t.check(StubURLProtocol.lastRequest == nil, "nothing sent without a key")

            let http = stubbed(401, ["type": "error", "error": ["type": "authentication_error", "message": "invalid x-api-key"]]) {
                try await Assist.shared.sendCloud(p, provider: .anthropic)
            }
            if case .failure(let e) = http { t.check(e.localizedDescription.contains("invalid x-api-key"), "server message surfaced") } else { t.fail("expected failure on 401") }
            t.check(Store.shared.assistLog().isEmpty, "failed requests are not logged as sent")

            let assist = Assist.shared
            let savedSession = assist.session, savedKeys = assist.keyProvider
            defer { assist.session = savedSession; assist.keyProvider = savedKeys }
            let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [StubURLProtocol.self]
            assist.session = URLSession(configuration: cfg); assist.keyProvider = { _ in "k" }
            StubURLProtocol.handler = { _ in (200, Data("<html>not json</html>".utf8)) }
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var failed = false
            Task.detached { do { _ = try await Assist.shared.sendCloud(p, provider: .anthropic) } catch { failed = true }; sem.signal() }
            _ = sem.wait(timeout: .now() + 10)
            t.check(failed, "non-json body is an error")
        },
    ])
}
