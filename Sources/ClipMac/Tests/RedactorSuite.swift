import Foundation

enum RedactorSuite {
    static let suite = TestSuite(name: "Redactor", cases: [
        TestCase(name: "Anthropic and OpenAI keys") { t in
            for key in ["sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdef", "sk-proj-ABCDEFGHIJKLMNOPQRSTUVWXYZ01234567"] {
                t.check(Redactor.flags(in: "export KEY=\(key)").contains(.apiKey), "flagged: \(key.prefix(10))")
                let m = Redactor.mask("export KEY=\(key)")
                t.check(!m.text.contains(key), "masked: \(key.prefix(10))")
                t.check(m.text.hasPrefix("export KEY="), "surrounding text kept")
                t.check(m.labels.contains("API KEY"), "label reported")
            }
        },
        TestCase(name: "AWS, GitHub, Slack, Google keys") { t in
            let keys = ["AKIAIOSFODNN7EXAMPLE", "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij", "xoxb-1234567890-abcdefghijkl", "AIzaSyA1234567890abcdefghijklmnopqrstuv"]
            for k in keys { t.check(Redactor.flags(in: "token \(k) here").contains(.apiKey), "flagged \(k.prefix(6))") }
        },
        TestCase(name: "JWT") { t in
            let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
            t.check(Redactor.flags(in: "Authorization: Bearer \(jwt)").contains(.jwt), "flagged")
            t.check(!Redactor.mask(jwt).text.contains("eyJ"), "masked")
        },
        TestCase(name: "private key block") { t in
            let pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA\n-----END RSA PRIVATE KEY-----"
            t.check(Redactor.flags(in: "here:\n" + pem).contains(.privateKey), "flagged")
            t.equal(Redactor.mask(pem).text, "[REDACTED PRIVATE KEY]", "whole block masked")
            let open = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA"
            t.check(Redactor.flags(in: open).contains(.privateKey), "unterminated block still flagged")
        },
        TestCase(name: "card numbers need Luhn") { t in
            t.check(Redactor.luhn("4111 1111 1111 1111"), "visa test number valid")
            t.check(Redactor.luhn("5500-0000-0000-0004"), "mastercard test number valid")
            t.check(!Redactor.luhn("4111 1111 1111 1112"), "off by one invalid")
            t.check(Redactor.flags(in: "card 4111 1111 1111 1111 exp 12/29").contains(.cardNumber), "valid card flagged")
            t.check(!Redactor.flags(in: "order 4111 1111 1111 1112").contains(.cardNumber), "invalid digits ignored")
            t.check(!Redactor.flags(in: "Invoice #4471 due Friday, call 415-555-0199").contains(.cardNumber), "short numbers ignored")
            t.check(Redactor.mask("pay 4111111111111111 now").text.contains("[REDACTED CARD]"), "masked")
        },
        TestCase(name: "credential assignments keep the key, mask the value") { t in
            for s in ["password=hunter2hunter2", "api_key: abcdefgh12345", "token = \"xyzxyzxyzxyz\"", "PASSWORD:supersecret99"] {
                let m = Redactor.mask(s)
                t.check(Redactor.flags(in: s).contains(.credential), "flagged: \(s)")
                t.check(m.text.contains("[REDACTED CREDENTIAL]"), "value masked: \(s)")
                t.check(m.text.lowercased().hasPrefix(String(s.prefix(4)).lowercased()), "key kept: \(s)")
            }
            t.check(!Redactor.flags(in: "the password field is empty").contains(.credential), "prose mention not flagged")
        },
        TestCase(name: "long base64") { t in
            let b64 = String(repeating: "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo=", count: 3).replacingOccurrences(of: "=", with: "")
            t.check(Redactor.flags(in: "blob: \(b64)").contains(.longBase64), "flagged")
            t.check(!Redactor.flags(in: "short QUJDREVG").contains(.longBase64), "short run ignored")
        },
        TestCase(name: "ordinary text is clean") { t in
            for s in ["meeting notes: ship the clipboard app next week", "https://example.com/docs/setup?ref=home", "Call Sam at 3pm about the Woodland invoice",
                      "SELECT id, name FROM users WHERE active = 1", "def f(x): return x * 2"] {
                t.check(Redactor.flags(in: s).isEmpty, "clean: \(s.prefix(30))")
                t.equal(Redactor.mask(s).text, s, "unchanged: \(s.prefix(30))")
            }
        },
        TestCase(name: "multiple secrets report every label once") { t in
            let s = "k=sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 and again sk-ant-api03-ZYXWVUTSRQPONMLKJIHGFEDCBA9876543210 card 4111111111111111"
            let m = Redactor.mask(s)
            t.equal(m.labels.filter { $0 == "API KEY" }.count, 1, "API KEY label once")
            t.check(m.labels.contains("CARD"), "CARD label")
            t.check(!m.text.contains("sk-ant"), "both keys masked")
        },
        TestCase(name: "flag labels") { t in
            let f: Redactor.Flag = [.apiKey, .jwt, .excludedApp]
            t.equal(f.labels, ["API key", "JWT", "excluded app"], "labels in order")
            t.check(Redactor.Flag(rawValue: 0).labels.isEmpty, "empty")
        },
    ])
}

extension RedactorSuite {
    /// Regression cases found by the property test.
    static let regressions = TestSuite(name: "Redactor", cases: [
        TestCase(name: "masking is idempotent on credential markers") { t in
            let once = Redactor.mask("password=hunter2hunter2").text
            t.equal(Redactor.mask(once).text, once, "second pass leaves the marker alone")
        },
        TestCase(name: "long runs of letters are not base64 secrets") { t in
            t.check(Redactor.flags(in: String(repeating: "a", count: 200)).isEmpty, "one class only")
            t.check(Redactor.flags(in: "supercalifragilisticexpialidocioussupercalifragilisticexpialidocious").isEmpty, "long word")
            t.check(!Redactor.flags(in: "sha256: " + String(repeating: "0123456789abcdef", count: 4)).contains(.longBase64), "hex hash is not base64")
            t.check(Redactor.looksLikeBase64Secret("QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVowMTIzNDU2Nzg5"), "real base64 mixes classes")
        },
    ])
}
