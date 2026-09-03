//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  Paste transforms: pure string functions applied on the way out. "Clean" (trim + strip tracking
//  parameters) is on ⌥↩; the rest live in the item's context menu under "Paste As".

import Foundation

enum Transform: String, CaseIterable, Identifiable {
    case clean, lowercase, uppercase, titleCase, trimmed, withoutTracking, markdownLink, prettyJSON, oneLine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clean: return String(localized: "Cleaned (trimmed, no tracking parameters)")
        case .lowercase: return String(localized: "lowercase")
        case .uppercase: return String(localized: "UPPERCASE")
        case .titleCase: return String(localized: "Title Case")
        case .trimmed: return String(localized: "Trimmed")
        case .withoutTracking: return String(localized: "Link without tracking parameters")
        case .markdownLink: return String(localized: "Markdown link")
        case .prettyJSON: return String(localized: "Pretty-printed JSON")
        case .oneLine: return String(localized: "One line")
        }
    }

    /// Transforms that make sense for this item.
    static func available(for item: Item) -> [Transform] {
        switch item.kind {
        case .image, .file: return []
        case .url: return [.clean, .withoutTracking, .markdownLink, .lowercase]
        default:
            var t: [Transform] = [.clean, .trimmed, .oneLine, .lowercase, .uppercase, .titleCase]
            if looksLikeJSON(item.plain) { t.insert(.prettyJSON, at: 1) }
            if item.plain.contains("://") { t.append(.withoutTracking) }
            return t
        }
    }

    func apply(_ s: String, title: String? = nil) -> String {
        switch self {
        case .clean: return Transform.withoutTracking.apply(Transform.trimmed.apply(s))
        case .lowercase: return s.lowercased()
        case .uppercase: return s.uppercased()
        case .titleCase: return s.capitalized
        case .trimmed: return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case .oneLine: return s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        case .withoutTracking: return Transform.stripTracking(in: s)
        case .markdownLink:
            let url = s.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = (title?.isEmpty == false ? title! : (URL(string: url)?.host ?? url))
            return "[\(text)](\(url))"
        case .prettyJSON:
            guard let data = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) else { return s }
            return String(decoding: out, as: UTF8.self)
        }
    }

    static func looksLikeJSON(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (t.hasPrefix("{") && t.hasSuffix("}")) || (t.hasPrefix("[") && t.hasSuffix("]")) else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(t.utf8))) != nil
    }

    /// Query parameters that exist only to track the click.
    static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "msclkid", "twclid", "ttclid", "yclid", "igshid", "mc_cid", "mc_eid", "mkt_tok",
        "_hsenc", "_hsmi", "hsCtaTracking", "vero_id", "oly_anon_id", "oly_enc_id", "s_cid", "ref_src", "ref_url", "si", "spm", "_ga", "_gl",
    ]
    static func isTracking(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.hasPrefix("utm_") || n.hasPrefix("pk_") || n.hasPrefix("mtm_") || n.hasPrefix("ga_") || trackingParameters.contains(name)
    }

    /// Removes tracking parameters from every URL in the text; leaves everything else byte-for-byte.
    static func stripTracking(in text: String) -> String {
        let regex = try! NSRegularExpression(pattern: "https?://[^\\s<>\"')\\]]+")
        let ns = text as NSString
        var out = text
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let raw = ns.substring(with: m.range)
            guard var comps = URLComponents(string: raw), let items = comps.queryItems, !items.isEmpty else { continue }
            let kept = items.filter { !isTracking($0.name) }
            if kept.count == items.count { continue }
            comps.queryItems = kept.isEmpty ? nil : kept
            if var cleaned = comps.string {
                if cleaned.hasSuffix("?") { cleaned.removeLast() }
                out = (out as NSString).replacingCharacters(in: m.range, with: cleaned)
            }
        }
        return out
    }
}
