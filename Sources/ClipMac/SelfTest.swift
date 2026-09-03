//  `clipmac selftest`: the unit checks, runnable without Xcode. The XCTest suite in Tests/ covers
//  the same ground for CI; this is the local, no-toolchain-required version.

import Foundation

enum SelfTest {
    private static var failures: [String] = []
    private static var passed = 0

    private static func check(_ cond: @autoclosure () -> Bool, _ what: String) {
        if cond() { passed += 1 } else { failures.append(what) }
    }

    static func run(json: Bool) -> Int32 {
        failures = []; passed = 0

        // Redactor
        let key = "export ANTHROPIC_API_KEY=sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdef"
        check(Redactor.flags(in: key).contains(.apiKey), "api key flagged")
        check(!Redactor.mask(key).text.contains("sk-ant-"), "api key masked")
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        check(Redactor.flags(in: jwt).contains(.jwt), "jwt flagged")
        let pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIEow\n-----END RSA PRIVATE KEY-----"
        check(Redactor.mask(pem).text == "[REDACTED PRIVATE KEY]", "private key masked whole")
        check(Redactor.luhn("4111 1111 1111 1111"), "luhn valid")
        check(Redactor.flags(in: "card 4111 1111 1111 1111").contains(.cardNumber), "card flagged")
        check(!Redactor.flags(in: "order 4111 1111 1111 1112").contains(.cardNumber), "non-luhn digits ignored")
        check(!Redactor.flags(in: "Invoice #4471 due Friday").contains(.cardNumber), "short numbers ignored")
        let cred = Redactor.mask("password=hunter2hunter2")
        check(cred.text.hasPrefix("password=") && !cred.text.contains("hunter2"), "credential keeps key, masks value")
        check(Redactor.flags(in: "meeting notes: ship the clipboard app next week").isEmpty, "ordinary text clean")

        // Store
        let store = Store(inMemory: true)
        func cap(_ s: String, app: String = "com.example.app") -> Capture {
            Capture(kind: .text, plain: s, blobData: nil, blobType: nil, sourceBundleID: app, sourceName: "Example", size: s.utf8.count)
        }
        let a = store.insert(cap("Invoice #4471 for the Woodland project is due Friday"))
        _ = store.insert(cap("recipe: two eggs, flour, milk"))
        check(store.count() == 2, "two inserts")
        check(store.insert(cap("Invoice #4471 for the Woodland project is due Friday")).id == a.id, "dedup bumps existing")
        check(store.item(atPosition: 1)?.id == a.id, "bumped row is newest")
        check(store.search("invoice").map(\.id) == [a.id], "fts word match")
        check(store.search("Wood").first?.id == a.id, "fts prefix match")
        check(store.search("471").first?.id == a.id, "substring match for short query")
        check(store.search("pancake").isEmpty, "no false match")
        let sig = store.insert(cap("Keith Adler\nkeith@example.com"))
        store.setPinned(sig.id, true, keyword: "sig")
        check(store.snippet(keyword: "SIG")?.id == sig.id, "snippet lookup case-insensitive")
        for i in 0..<20 { _ = store.insert(cap("item \(i)")) }
        check(store.enforceRetention(days: 30, maxItems: 5, maxBytes: 1 << 30) == 17, "retention removes surplus")
        check(store.get(sig.id) != nil, "pinned survives retention")
        _ = store.insert(cap("token: sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", app: "com.other"))
        check(store.all().first { $0.sourceBundleID == "com.other" }?.looksSensitive == true, "sensitive flag stored")
        check(store.delete(bundleID: "com.other") == 1, "forget by app")
        store.setVector(sig.id, model: "t", [0.1, 0.2, 0.3])
        check(store.vector(for: sig.id, model: "t") == [0.1, 0.2, 0.3], "vector round trip")
        store.wipe()
        check(store.count() == 0, "wipe empties")

        // Updates
        check(Updates.isNewer("0.2.0", than: "0.1.0") && !Updates.isNewer("0.1", than: "0.1.1"), "version compare")

        // Capabilities that must not crash
        _ = Capabilities.onDeviceModelNote
        _ = Hotkey.describe()

        if json {
            print(Dump.json(["passed": passed, "failed": failures.count, "failures": failures]))
        } else {
            for f in failures { print("FAIL  \(f)") }
            print("\(passed) passed, \(failures.count) failed")
        }
        return failures.isEmpty ? 0 : 2
    }
}
