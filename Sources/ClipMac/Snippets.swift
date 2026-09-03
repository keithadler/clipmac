//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  Pinned items with keywords. Expansion is deliberately not keystroke interception: no input
//  monitoring, no text-replacement engine of our own. Instead pinned items sit at the top of the
//  panel, `clipmac snip <keyword>` serves scripts, and the pins can be exported as a macOS Text
//  Replacement list so the system does the expanding.

import Foundation
import AppKit

enum Snippets {
    static func all() -> [Item] { Store.shared.pinned() }

    static func lookup(_ keyword: String) -> Item? { Store.shared.snippet(keyword: keyword) }

    /// Pins that match a query by keyword prefix or content, for the top of the panel.
    static func matching(_ query: String) -> [Item] {
        let q = query.lowercased()
        return all().filter { q.isEmpty || ($0.keyword?.lowercased().hasPrefix(q) ?? false) || $0.plain.lowercased().contains(q) }
    }

    /// Writes a .plist that System Settings › Keyboard › Text Replacements accepts by drag-and-drop.
    static func exportTextReplacements(to url: URL, items: [Item] = Snippets.all()) throws -> Int {
        let rows: [[String: String]] = items.compactMap { item in
            guard let k = item.keyword, !k.isEmpty, item.kind != .image, item.kind != .file else { return nil }
            return ["shortcut": k, "phrase": item.plain]
        }
        let data = try PropertyListSerialization.data(fromPropertyList: rows, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
        return rows.count
    }

    @MainActor
    static func exportWithDialog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Clip for Mac snippets.plist"
        panel.title = String(localized: "Export Text Replacements")
        panel.message = String(localized: "Drop the saved file onto System Settings › Keyboard › Text Replacements to import it.")
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            _ = try? exportTextReplacements(to: url)
        }
    }
}
