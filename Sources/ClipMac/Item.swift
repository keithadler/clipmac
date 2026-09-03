//  Clip for Mac — a clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  The one model type. A row in history.db plus, for images and rich text, a blob file on disk
//  referenced by its SHA-256 so duplicate copies cost nothing.

import Foundation

enum ItemKind: String, Codable, CaseIterable {
    case text, rtf, html, image, file, url

    var label: String {
        switch self {
        case .text: return String(localized: "Text")
        case .rtf: return String(localized: "Rich text")
        case .html: return String(localized: "HTML")
        case .image: return String(localized: "Image")
        case .file: return String(localized: "Files")
        case .url: return String(localized: "Link")
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .rtf: return "textformat"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        }
    }
}

struct Item: Identifiable, Hashable, Codable {
    let id: Int64
    var kind: ItemKind
    var preview: String
    var plain: String
    var blobHash: String?
    var blobType: String?          // pasteboard type of the blob (public.rtf, public.png, …)
    var sourceBundleID: String?
    var sourceName: String?
    var sourceTitle: String?        // front window title at capture time, when Accessibility allows it
    var createdAt: Date
    var lastUsedAt: Date
    var useCount: Int
    var pinned: Bool
    var keyword: String?
    var redactionFlags: Int        // Redactor.Flag bitmask, computed at capture time
    var size: Int
    var contentHash: String

    /// Paths, for file items (one per line in `plain`).
    var filePaths: [String] { kind == .file ? plain.split(separator: "\n").map(String.init) : [] }

    var looksSensitive: Bool { redactionFlags != 0 }

    /// Text as used for identity: trimmed, inner whitespace collapsed, so "foo " and "foo" are the same item.
    static func normalized(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// One line, trimmed, for lists and `clipmac list`.
    static func makePreview(_ s: String, limit: Int = 120) -> String {
        let collapsed = s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ⏎ ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }
}

/// What the Monitor hands the Store after a pasteboard change passed every capture rule.
struct Capture {
    var kind: ItemKind
    var plain: String
    var blobData: Data?
    var blobType: String?
    var sourceBundleID: String?
    var sourceName: String?
    var sourceTitle: String? = nil
    var size: Int
}

struct AssistLogEntry: Identifiable, Codable {
    let id: Int64
    var at: Date
    var provider: String
    var model: String
    var itemCount: Int
    var chars: Int
    var inputTokens: Int
    var outputTokens: Int
    var prompt: String
}
