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

// MARK: - Pins export, import and folder sync

/// Pins travel as a JSON file the user can drop in iCloud Drive, Dropbox or a USB stick themselves.
/// No account, no server. History never travels, only pins.
enum PinSync {
    static let fileName = "Clip for Mac pins.json"
    static let format = 1

    struct File: Codable {
        var format = PinSync.format
        var exportedAt = Date()
        var device = Host.current().localizedName ?? "Mac"
        var pins: [Pin]
        /// SHA-256 of the pins array as encoded, so a truncated or edited file is noticed.
        var checksum = ""
    }

    struct Pin: Codable, Equatable {
        var kind: String
        var plain: String
        var keyword: String?
        var blobType: String?
        var blob: String?     // base64 for images and rich text
    }

    static func pins(from items: [Item], store: Store = Store.shared) -> [Pin] {
        items.filter(\.pinned).map { it in
            Pin(kind: it.kind.rawValue, plain: it.plain, keyword: it.keyword, blobType: it.blobType,
                blob: it.blobHash.flatMap { store.blob($0)?.base64EncodedString() })
        }
    }

    static func encode(_ pins: [Pin]) throws -> Data {
        var file = File(pins: pins)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        file.checksum = Store.sha256(try enc.encode(pins))
        return try enc.encode(file)
    }

    static func decode(_ data: Data) throws -> File {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let file = try dec.decode(File.self, from: data)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        guard file.checksum == Store.sha256(try enc.encode(file.pins)) else { throw PinSyncError.checksum }
        guard file.format <= format else { throw PinSyncError.newerFormat(file.format) }
        return file
    }

    @discardableResult
    static func export(to url: URL, store: Store = Store.shared) throws -> Int {
        let p = pins(from: store.pinned(), store: store)
        try encode(p).write(to: url, options: .atomic)
        return p.count
    }

    /// Merges pins into the store: existing identical content is pinned (and given the keyword when it
    /// has none); new content is inserted pinned. Returns how many pins were added or updated.
    @discardableResult
    static func importFile(_ url: URL, store: Store = Store.shared) throws -> Int {
        let file = try decode(try Data(contentsOf: url))
        var changed = 0
        for pin in file.pins {
            let kind = ItemKind(rawValue: pin.kind) ?? .text
            let blob = pin.blob.flatMap { Data(base64Encoded: $0) }
            let cap = Capture(kind: kind, plain: pin.plain, blobData: blob, blobType: pin.blobType, sourceBundleID: nil, sourceName: file.device,
                              size: (blob?.count ?? 0) + pin.plain.utf8.count)
            let before = store.count()
            let item = store.insert(cap)
            let wasPinned = item.pinned && item.keyword == pin.keyword
            if !wasPinned { store.setPinned(item.id, true, keyword: pin.keyword ?? item.keyword); changed += 1 }
            else if store.count() != before { changed += 1 }
        }
        Assist.shared.indexSoon()
        NotificationCenter.default.post(name: .clipHistoryChanged, object: nil)
        return changed
    }

    // Folder sync: write on every pin change, read when the file changed since we last read it.

    static var folderURL: URL? { Prefs.syncFolder.map { URL(fileURLWithPath: $0, isDirectory: true) } }
    static var fileURL: URL? { folderURL?.appendingPathComponent(fileName) }
    private static var lastImported: Date? {
        get { let t = Prefs.defaults.double(forKey: "pinSyncLastImport"); return t > 0 ? Date(timeIntervalSince1970: t) : nil }
        set { Prefs.defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "pinSyncLastImport") }
    }

    /// Writes the current pins to the sync folder, if one is set.
    static func pushIfConfigured() {
        guard let url = fileURL else { return }
        do { try export(to: url); lastImported = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date() }
        catch { NSLog("clipmac pin sync: \(error.localizedDescription)") }
    }

    /// Reads the sync file when another Mac changed it. Returns the number of pins merged, or nil when nothing was due.
    @discardableResult
    static func pullIfChanged() -> Int? {
        guard let url = fileURL, let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
        if let last = lastImported, modified <= last { return nil }
        do {
            let n = try importFile(url)
            lastImported = modified
            return n
        } catch { NSLog("clipmac pin sync: \(error.localizedDescription)"); return nil }
    }

    private static var timer: Timer?
    @MainActor
    static func start() {
        _ = pullIfChanged()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in _ = pullIfChanged() }
        NotificationCenter.default.addObserver(forName: .clipPinsChanged, object: nil, queue: .main) { _ in pushIfConfigured() }
    }
}

enum PinSyncError: LocalizedError {
    case checksum, newerFormat(Int)
    var errorDescription: String? {
        switch self {
        case .checksum: return String(localized: "The pins file is damaged or was edited by hand.")
        case .newerFormat(let f): return String(format: String(localized: "The pins file was written by a newer Clip for Mac (format %lld)."), f)
        }
    }
}

extension Notification.Name {
    static let clipPinsChanged = Notification.Name("com.keithadler.clipmac.pinsChanged")
}
