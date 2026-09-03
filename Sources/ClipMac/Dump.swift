//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  CLI output: text tables for people, --json for scripts. Sizes are bytes, dates ISO 8601.

import Foundation

enum Dump {
    static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()

    static func json(_ obj: Any) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }

    static func dict(_ item: Item, position: Int? = nil) -> [String: Any] {
        var d: [String: Any] = [
            "id": item.id, "kind": item.kind.rawValue, "preview": item.preview, "plain": item.plain,
            "size": item.size, "created_at": iso.string(from: item.createdAt), "last_used_at": iso.string(from: item.lastUsedAt),
            "use_count": item.useCount, "pinned": item.pinned, "sensitive": item.looksSensitive,
            "sensitive_kinds": Redactor.Flag(rawValue: item.redactionFlags).labels,
        ]
        if let p = position { d["position"] = p }
        if let k = item.keyword { d["keyword"] = k }
        if let b = item.sourceBundleID { d["source_bundle_id"] = b }
        if let n = item.sourceName { d["source_name"] = n }
        if let h = item.blobHash { d["blob"] = h; d["blob_type"] = item.blobType ?? "" }
        if item.kind == .file { d["paths"] = item.filePaths }
        return d
    }

    static func dict(_ e: AssistLogEntry) -> [String: Any] {
        ["id": e.id, "at": iso.string(from: e.at), "provider": e.provider, "model": e.model, "items": e.itemCount,
         "chars": e.chars, "input_tokens": e.inputTokens, "output_tokens": e.outputTokens, "prompt": e.prompt]
    }

    static func relative(_ d: Date) -> String {
        if abs(d.timeIntervalSinceNow) < 60 { return String(localized: "just now") }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }

    static func table(_ items: [Item], positions: Bool = true) -> String {
        guard !items.isEmpty else { return "(no items)\n" }
        var out = ""
        for (i, it) in items.enumerated() {
            let pos = positions ? String(format: "%3d", i + 1) : "   "
            let flag = it.looksSensitive ? "!" : (it.pinned ? "*" : " ")
            let kw = it.keyword.map { " [\($0)]" } ?? ""
            let src = it.sourceName.map { " · \($0)" } ?? ""
            let preview = it.kind == .image ? "(image, \(ByteCountFormatter.string(fromByteCount: Int64(it.size), countStyle: .file)))" : String(it.preview.prefix(72))
            out += "\(pos) #\(it.id) \(flag) \(it.kind.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0))  \(preview)\(kw)  (\(relative(it.createdAt))\(src))\n"
        }
        return out
    }

    static func logTable(_ log: [AssistLogEntry]) -> String {
        guard !log.isEmpty else { return "(nothing has been sent)\n" }
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return log.map { e in
            "\(f.string(from: e.at))  \(e.provider)/\(e.model)  \(e.itemCount) items, \(e.chars) chars, \(e.inputTokens)+\(e.outputTokens) tokens  \"\(e.prompt.prefix(60))\""
        }.joined(separator: "\n") + "\n"
    }
}
