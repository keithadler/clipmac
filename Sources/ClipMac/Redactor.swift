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

    private struct Pattern {
        let flag: Flag
        let label: String
        let regex: NSRegularExpression
        /// Extra check on the matched text (character mix for base64) to cut false positives.
        let validate: ((String) -> Bool)?
        /// Replaces the regex entirely when a rule needs more than a pattern (card numbers).
        let finder: ((String) -> [NSRange])?
        init(flag: Flag, label: String, regex: NSRegularExpression, validate: ((String) -> Bool)? = nil, finder: ((String) -> [NSRange])? = nil) {
            self.flag = flag; self.label = label; self.regex = regex; self.validate = validate; self.finder = finder
        }
        func ranges(in text: String, limit: Int) -> [NSRange] {
            if let finder { return finder(text) }
            let ns = text as NSString
            return regex.matches(in: text, options: [], range: NSRange(location: 0, length: min(ns.length, limit)))
                .map(\.range).filter { validate?(ns.substring(with: $0)) ?? true }
        }
    }

    /// Card numbers: within a run of digits separated by single spaces or dashes, any window of
    /// consecutive groups that looks like a card (13-19 digits, every group 4-6 digits, or one
    /// unbroken group) and passes Luhn. Neighbouring digits such as "order 6 4111 …" or a trailing
    /// year no longer hide the card, and phone-number lists with 3-digit groups are left alone.
    private static let digitRun = re("\\d(?:[ \\-]?\\d)*")

    static func cardRanges(in text: String) -> [NSRange] {
        let ns = text as NSString
        var out: [NSRange] = []
        for m in digitRun.matches(in: text, options: [], range: NSRange(location: 0, length: min(ns.length, 200_000))) {
            let run = ns.substring(with: m.range)
            guard run.filter(\.isNumber).count >= 13 else { continue }
            // groups as (offset, length) within the run
            var groups: [(Int, Int)] = []
            var start = 0
            let chars = Array(run)
            for (i, c) in chars.enumerated() where !c.isNumber {
                groups.append((start, i - start)); start = i + 1
            }
            groups.append((start, chars.count - start))
            if groups.count == 1 {
                if (13...19).contains(chars.count), luhn(run) { out.append(m.range) }
                continue
            }
            var i = 0
            while i < groups.count {
                var found = false
                var j = groups.count - 1
                while j >= i {
                    let window = groups[i...j]
                    let digits = window.reduce(0) { $0 + $1.1 }
                    if (13...19).contains(digits), window.allSatisfy({ (4...6).contains($0.1) }) {
                        let lo = groups[i].0, hi = groups[j].0 + groups[j].1
                        let slice = String(chars[lo..<hi])
                        if luhn(slice) {
                            out.append(NSRange(location: m.range.location + lo, length: hi - lo))
                            i = j + 1; found = true; break
                        }
                    }
                    j -= 1
                }
                if !found { i += 1 }
            }
        }
        return out
    }

    /// Real base64 secrets mix cases and digits; a long run of one class is prose, a hash, or padding.
    static func looksLikeBase64Secret(_ s: String) -> Bool {
        var upper = false, lower = false, digit = false
        for c in s { if c.isUppercase { upper = true } else if c.isLowercase { lower = true } else if c.isNumber { digit = true } }
        return upper && lower && digit
    }

    private static func re(_ p: String, _ opts: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: opts)
    }

    private static let patterns: [Pattern] = [
        Pattern(flag: .privateKey, label: "PRIVATE KEY", regex: re("-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----|-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*")),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\bsk-ant-[A-Za-z0-9_\\-]{20,}")),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\bsk-(?:proj-|live-|test-)?[A-Za-z0-9_\\-]{20,}")),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\b(?:AKIA|ASIA)[0-9A-Z]{16}\\b")),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\\b|\\bgithub_pat_[A-Za-z0-9_]{60,}")),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\bxox[abprs]-[A-Za-z0-9\\-]{10,}")),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\bAIza[0-9A-Za-z_\\-]{35}\\b")),
        Pattern(flag: .apiKey, label: "API KEY", regex: re("\\b(?:glpat|pypi|npm|hf|shpat|shpss|sq0atp|SG\\.)[A-Za-z0-9_\\-.]{20,}")),
        Pattern(flag: .jwt, label: "JWT", regex: re("\\beyJ[A-Za-z0-9_\\-]{8,}\\.[A-Za-z0-9_\\-]{8,}\\.[A-Za-z0-9_\\-]{8,}\\b")),
        Pattern(flag: .credential, label: "CREDENTIAL", regex: re("(?i)\\b(?:api[_\\-]?key|secret|token|passw(?:or)?d|auth|bearer)\\b\\s*[:=]\\s*[\"']?(?!\\[REDACTED)([^\\s\"',;]{8,})")),
        Pattern(flag: .cardNumber, label: "CARD", regex: re("\\d{13,19}"), finder: cardRanges),
        Pattern(flag: .longBase64, label: "BASE64", regex: re("(?<![A-Za-z0-9+/=])[A-Za-z0-9+/]{48,}={0,2}(?![A-Za-z0-9+/=])"), validate: looksLikeBase64Secret),
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
        for p in patterns where !f.contains(p.flag) {
            if !p.ranges(in: text, limit: 200_000).isEmpty { f.insert(p.flag) }
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
            if p.flag == .credential {
                // keep "password=" so the summary still makes sense, mask only the value
                for m in p.regex.matches(in: out, options: [], range: NSRange(location: 0, length: ns.length)).reversed()
                where m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound {
                    out = (out as NSString).replacingCharacters(in: m.range(at: 1), with: "[REDACTED \(p.label)]")
                    if !labels.contains(p.label) { labels.append(p.label) }
                }
                continue
            }
            for r in p.ranges(in: out, limit: ns.length).reversed() {
                out = (out as NSString).replacingCharacters(in: r, with: "[REDACTED \(p.label)]")
                if !labels.contains(p.label) { labels.append(p.label) }
            }
        }
        return (out, labels)
    }
}
