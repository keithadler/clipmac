//  Secret detection and masking. Shared by the capture path (to flag rows), the panel (to warn), and
//  the cloud assist path (to mask before anything leaves the machine). Patterns are deliberately
//  broad: a false positive costs a "[REDACTED]" in a summary, a false negative costs a leaked key.

import Foundation

enum Redactor {
    struct Flag: OptionSet {
        let rawValue: Int
        static let apiKey      = Flag(rawValue: 1 << 0)
        static let jwt         = Flag(rawValue: 1 << 1)
        static let privateKey  = Flag(rawValue: 1 << 2)
        static let cardNumber  = Flag(rawValue: 1 << 3)
        static let longBase64  = Flag(rawValue: 1 << 4)
        static let credential  = Flag(rawValue: 1 << 5)   // password=…, token: …
        static let excludedApp = Flag(rawValue: 1 << 6)   // set by the caller, not by pattern

        var labels: [String] {
            var out: [String] = []
            if contains(.apiKey) { out.append("API key") }
            if contains(.jwt) { out.append("JWT") }
            if contains(.privateKey) { out.append("private key") }
            if contains(.cardNumber) { out.append("card number") }
            if contains(.longBase64) { out.append("long base64") }
            if contains(.credential) { out.append("credential") }
            if contains(.excludedApp) { out.append("excluded app") }
            return out
        }
    }

    private struct Pattern { let flag: Flag; let label: String; let regex: NSRegularExpression; let luhn: Bool }

    private static func re(_ p: String, _ opts: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: opts)
    }

    private static let patterns: [Pattern] = [
        Pattern(flag: .privateKey, label: "PRIVATE KEY", regex: re("-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----|-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*"), luhn: false),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\bsk-ant-[A-Za-z0-9_\\-]{20,}"), luhn: false),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\bsk-(?:proj-|live-|test-)?[A-Za-z0-9_\\-]{20,}"), luhn: false),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\b(?:AKIA|ASIA)[0-9A-Z]{16}\\b"), luhn: false),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\\b|\\bgithub_pat_[A-Za-z0-9_]{60,}"), luhn: false),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\bxox[abprs]-[A-Za-z0-9\\-]{10,}"), luhn: false),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\bAIza[0-9A-Za-z_\\-]{35}\\b"), luhn: false),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\b(?:glpat|pypi|npm|hf|shpat|shpss|sq0atp|SG\\.)[A-Za-z0-9_\\-.]{20,}"), luhn: false),
        Pattern(flag: .jwt, label: "JWT", regex: re("\\beyJ[A-Za-z0-9_\\-]{8,}\\.[A-Za-z0-9_\\-]{8,}\\.[A-Za-z0-9_\\-]{8,}\\b"), luhn: false),
        Pattern(flag: .credential, label: "CREDENTIAL", regex: re("(?i)\\b(?:api[_\\-]?key|secret|token|passw(?:or)?d|auth|bearer)\\b\\s*[:=]\\s*[\"']?([^\\s\"',;]{8,})"), luhn: false),
        Pattern(flag: .cardNumber, label: "CARD", regex: re("\\b(?:\\d[ \\-]?){13,19}\\b"), luhn: true),
        Pattern(flag: .longBase64, label: "BASE64", regex: re("(?<![A-Za-z0-9+/=])[A-Za-z0-9+/]{48,}={0,2}(?![A-Za-z0-9+/=])"), luhn: false),
    ]

    static func luhn(_ s: String) -> Bool {
        let digits = s.compactMap { $0.wholeNumberValue }
        guard digits.count >= 13 else { return false }
        var sum = 0
        for (i, d) in digits.reversed().enumerated() {
            if i % 2 == 1 { let x = d * 2; sum += x > 9 ? x - 9 : x } else { sum += d }
        }
        return sum % 10 == 0
    }

    /// Which categories the text trips. Cheap enough to run on every capture.
    static func flags(in text: String) -> Flag {
        var f: Flag = []
        let ns = text as NSString
        let range = NSRange(location: 0, length: min(ns.length, 200_000))
        for p in patterns where !f.contains(p.flag) {
            for m in p.regex.matches(in: text, options: [], range: range) {
                if p.luhn && !luhn(ns.substring(with: m.range)) { continue }
                f.insert(p.flag); break
            }
        }
        return f
    }

    /// Masked copy of the text plus the list of categories that were masked. The masked text is what
    /// the user sees before anything is sent to a cloud model.
    static func mask(_ text: String) -> (text: String, labels: [String]) {
        var out = text
        var labels: [String] = []
        for p in patterns {
            let ns = out as NSString
            let matches = p.regex.matches(in: out, options: [], range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() {
                let hit = ns.substring(with: m.range)
                if p.luhn && !luhn(hit) { continue }
                let replacement: String
                if p.flag == .credential, m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
                    // keep "password=" so the summary still makes sense, mask only the value
                    let valueRange = m.range(at: 1)
                    out = (out as NSString).replacingCharacters(in: valueRange, with: "[REDACTED \(p.label)]")
                    if !labels.contains(p.label) { labels.append(p.label) }
                    continue
                } else {
                    replacement = "[REDACTED \(p.label)]"
                }
                out = (out as NSString).replacingCharacters(in: m.range, with: replacement)
                if !labels.contains(p.label) { labels.append(p.label) }
            }
        }
        return (out, labels)
    }
}
