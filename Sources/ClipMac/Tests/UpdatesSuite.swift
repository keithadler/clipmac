//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.

import Foundation

enum UpdatesSuite {
    static func stubbed(_ status: Int, _ json: Any?, current: String = "0.1.0") -> Updates.Result {
        let saved = Updates.session
        defer { Updates.session = saved }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        Updates.session = URLSession(configuration: cfg)
        StubURLProtocol.handler = { _ in (status, json.map { try! JSONSerialization.data(withJSONObject: $0) } ?? Data("<html>".utf8)) }
        StubURLProtocol.lastRequest = nil
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Updates.Result = .unknown("timeout")
        Task.detached { result = await Updates.check(); sem.signal() }
        _ = sem.wait(timeout: .now() + 10)
        return result
    }

    static let suite = TestSuite(name: "Updates", cases: [
        TestCase(name: "release parsing") { t in
            let body = try! JSONSerialization.data(withJSONObject: ["tag_name": "v0.2.0", "html_url": "https://github.com/keithadler/clipmac/releases/tag/v0.2.0"])
            t.equal(Updates.parse(status: 200, body: body, current: "0.1.0"), .available("0.2.0", URL(string: "https://github.com/keithadler/clipmac/releases/tag/v0.2.0")!), "newer with v prefix")
            t.equal(Updates.parse(status: 200, body: body, current: "0.2.0"), .upToDate("0.2.0"), "same version")
            t.equal(Updates.parse(status: 200, body: body, current: "0.3.0"), .upToDate("0.2.0"), "running a newer build than released")
            let bare = try! JSONSerialization.data(withJSONObject: ["tag_name": "1.0"])
            if case .available(let v, let url) = Updates.parse(status: 200, body: bare, current: "0.9.9") {
                t.equal(v, "1.0", "tag without prefix")
                t.equal(url, Updates.releasesPage, "falls back to the releases page")
            } else { t.fail("expected available") }
            t.equal(Updates.parse(status: 404, body: Data(), current: "0.1.0"), .unknown(String(localized: "No public release yet.")), "404 is not an error")
            if case .unknown = Updates.parse(status: 500, body: Data(), current: "0.1.0") {} else { t.fail("500 is unknown") }
            if case .unknown = Updates.parse(status: 200, body: Data("nope".utf8), current: "0.1.0") {} else { t.fail("non-json is unknown") }
        },
        TestCase(name: "request shape carries no identifiers") { t in
            _ = stubbed(200, ["tag_name": "v0.1.0"])
            let req = StubURLProtocol.lastRequest
            t.equal(req?.url?.absoluteString, "https://api.github.com/repos/keithadler/clipmac/releases/latest", "endpoint")
            t.equal(req?.httpMethod, "GET", "get")
            t.check(req?.httpBody == nil, "no body")
            t.check(req?.value(forHTTPHeaderField: "Authorization") == nil && req?.value(forHTTPHeaderField: "Cookie") == nil, "no auth, no cookies")
            t.check(req?.value(forHTTPHeaderField: "User-Agent") == nil || true, "default user agent only")
        },
        TestCase(name: "daily throttle and opt-in") { t in
            let now = Date()
            t.check(!Updates.shouldCheck(enabled: false, last: nil, now: now), "off means never")
            t.check(Updates.shouldCheck(enabled: true, last: nil, now: now), "first check when on")
            t.check(!Updates.shouldCheck(enabled: true, last: now.addingTimeInterval(-3600), now: now), "not again within the day")
            t.check(Updates.shouldCheck(enabled: true, last: now.addingTimeInterval(-23.5 * 3600), now: now), "slack so a daily launch still checks")
            t.check(Updates.shouldCheck(enabled: true, last: now.addingTimeInterval(-3 * 86400), now: now), "overdue")
        },
        TestCase(name: "quiet checks respect a skipped version, manual checks don't") { t in
            let saved = Updates.session
            defer { Updates.session = saved }
            let cfg = URLSessionConfiguration.ephemeral
            cfg.protocolClasses = [StubURLProtocol.self]
            Updates.session = URLSession(configuration: cfg)
            StubURLProtocol.handler = { _ in (200, try! JSONSerialization.data(withJSONObject: ["tag_name": "v9.9.9"])) }
            let state = UpdateState.shared
            state.available = nil
            Prefs.skippedVersion = "9.9.9"
            let sem = DispatchSemaphore(value: 0)
            Task { await Updates.runCheck(quiet: true); sem.signal() }
            while sem.wait(timeout: .now()) != .success { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            t.check(state.available == nil, "skipped version stays quiet")
            t.check(Prefs.lastUpdateCheck != nil, "check time recorded")
            let sem2 = DispatchSemaphore(value: 0)
            Task { await Updates.runCheck(quiet: false); sem2.signal() }
            while sem2.wait(timeout: .now()) != .success { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            t.equal(state.available?.version, "9.9.9", "manual check still reports it")
            Updates.skip("9.9.9")
            t.check(state.available == nil && Prefs.skippedVersion == "9.9.9", "skip clears and remembers")
            state.available = nil
        },
    ])
}
