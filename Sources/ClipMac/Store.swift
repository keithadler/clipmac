//  SQLite storage: history.db (WAL) with an FTS5 index over the plain-text projection, a side table
//  of sentence-embedding vectors, the assist request log, and blob files for anything large.
//
//  At rest: this file is NOT encrypted by Clip for Mac. FTS5 cannot index ciphertext, and shipping
//  half-encryption would imply more than it delivers. The app relies on FileVault and says so in
//  Settings and the README. Capabilities.fileVaultOn reports the state.
//
//  Retention is real deletion: no soft-delete, no receipts. For a clipboard, forgetting is the feature.

import Foundation
import SQLite3
import CryptoKit

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class Store {
    /// Replaceable so tests can point everything at an in-memory store.
    static var shared = Store()

    /// CLIPMAC_HOME overrides the data directory (integration tests use a temporary one).
    static let supportDir: URL = {
        let dir: URL
        if let home = ProcessInfo.processInfo.environment["CLIPMAC_HOME"], !home.isEmpty {
            dir = URL(fileURLWithPath: home, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            dir = base.appendingPathComponent("Clip for Mac", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static var dbURL: URL { supportDir.appendingPathComponent("history.db") }
    static var blobDir: URL { supportDir.appendingPathComponent("blobs", isDirectory: true) }

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.keithadler.clipmac.store")
    let inMemory: Bool

    /// Session-only mode keeps everything in RAM; nothing is written and nothing survives quit.
    init(inMemory: Bool = Prefs.sessionOnly) {
        self.inMemory = inMemory
        let path = inMemory ? ":memory:" : Store.dbURL.path
        var handle: OpaquePointer?
        sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        db = handle
        try? FileManager.default.createDirectory(at: Store.blobDir, withIntermediateDirectories: true)
        migrate()
    }

    deinit { sqlite3_close(db) }

    // MARK: - Schema

    private func migrate() {
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA auto_vacuum=INCREMENTAL")
        exec("PRAGMA busy_timeout=2000")
        exec("""
        CREATE TABLE IF NOT EXISTS items(
            id INTEGER PRIMARY KEY,
            kind TEXT NOT NULL,
            preview TEXT NOT NULL,
            plain TEXT NOT NULL,
            blob_hash TEXT,
            blob_type TEXT,
            source_bundle_id TEXT,
            source_name TEXT,
            created_at REAL NOT NULL,
            last_used_at REAL NOT NULL,
            use_count INTEGER NOT NULL DEFAULT 0,
            pinned INTEGER NOT NULL DEFAULT 0,
            keyword TEXT,
            redaction_flags INTEGER NOT NULL DEFAULT 0,
            size INTEGER NOT NULL DEFAULT 0,
            content_hash TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS items_created ON items(created_at DESC);
        CREATE INDEX IF NOT EXISTS items_hash ON items(content_hash);
        CREATE INDEX IF NOT EXISTS items_keyword ON items(keyword);
        CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(plain, content='items', content_rowid='id', tokenize='unicode61');
        CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
            INSERT INTO items_fts(rowid, plain) VALUES (new.id, new.plain);
        END;
        CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
            INSERT INTO items_fts(items_fts, rowid, plain) VALUES('delete', old.id, old.plain);
        END;
        CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE OF plain ON items BEGIN
            INSERT INTO items_fts(items_fts, rowid, plain) VALUES('delete', old.id, old.plain);
            INSERT INTO items_fts(rowid, plain) VALUES (new.id, new.plain);
        END;
        CREATE TABLE IF NOT EXISTS vectors(
            item_id INTEGER PRIMARY KEY,
            model TEXT NOT NULL,
            vec BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS assist_log(
            id INTEGER PRIMARY KEY,
            at REAL NOT NULL,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            item_count INTEGER NOT NULL,
            chars INTEGER NOT NULL,
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            prompt TEXT NOT NULL
        );
        """)
    }

    // MARK: - Low-level helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK, let err { fputs("clipmac sqlite: \(String(cString: err))\n", stderr); sqlite3_free(err) }
        return rc == SQLITE_OK
    }

    private enum Bind { case text(String?), int(Int64), real(Double), blob(Data?) }

    private func prepare(_ sql: String, _ binds: [Bind]) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            fputs("clipmac sqlite prepare: \(String(cString: sqlite3_errmsg(db))) in \(sql)\n", stderr)
            return nil
        }
        for (i, b) in binds.enumerated() {
            let idx = Int32(i + 1)
            switch b {
            case .text(let s): if let s { sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, idx) }
            case .int(let n): sqlite3_bind_int64(stmt, idx, n)
            case .real(let d): sqlite3_bind_double(stmt, idx, d)
            case .blob(let d):
                if let d { _ = d.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(d.count), SQLITE_TRANSIENT) } }
                else { sqlite3_bind_null(stmt, idx) }
            }
        }
        return stmt
    }

    private func run(_ sql: String, _ binds: [Bind] = []) {
        queue.sync {
            guard let stmt = prepare(sql, binds) else { return }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    private func query<T>(_ sql: String, _ binds: [Bind] = [], _ row: (OpaquePointer) -> T) -> [T] {
        queue.sync {
            guard let stmt = prepare(sql, binds) else { return [] }
            defer { sqlite3_finalize(stmt) }
            var out: [T] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(row(stmt)) }
            return out
        }
    }

    private func scalar(_ sql: String, _ binds: [Bind] = []) -> Int64 {
        query(sql, binds) { sqlite3_column_int64($0, 0) }.first ?? 0
    }

    private static func col(_ s: OpaquePointer, _ i: Int32) -> String? {
        guard let c = sqlite3_column_text(s, i) else { return nil }
        return String(cString: c)
    }

    private static let itemColumns = "id, kind, preview, plain, blob_hash, blob_type, source_bundle_id, source_name, created_at, last_used_at, use_count, pinned, keyword, redaction_flags, size, content_hash"
    private static let qualifiedColumns = itemColumns.split(separator: ", ").map { "items." + $0 }.joined(separator: ", ")

    private static func item(_ s: OpaquePointer) -> Item {
        Item(id: sqlite3_column_int64(s, 0),
             kind: ItemKind(rawValue: col(s, 1) ?? "text") ?? .text,
             preview: col(s, 2) ?? "",
             plain: col(s, 3) ?? "",
             blobHash: col(s, 4),
             blobType: col(s, 5),
             sourceBundleID: col(s, 6),
             sourceName: col(s, 7),
             createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 8)),
             lastUsedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 9)),
             useCount: Int(sqlite3_column_int64(s, 10)),
             pinned: sqlite3_column_int64(s, 11) != 0,
             keyword: col(s, 12),
             redactionFlags: Int(sqlite3_column_int64(s, 13)),
             size: Int(sqlite3_column_int64(s, 14)),
             contentHash: col(s, 15) ?? "")
    }

    // MARK: - Blobs

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes a blob if it isn't already on disk; returns its hash. Session-only mode keeps blobs in RAM.
    private var memoryBlobs: [String: Data] = [:]

    func writeBlob(_ data: Data) -> String {
        let hash = Store.sha256(data)
        if inMemory { queue.sync { memoryBlobs[hash] = data }; return hash }
        let url = Store.blobDir.appendingPathComponent(hash)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
        return hash
    }

    func blob(_ hash: String?) -> Data? {
        guard let hash else { return nil }
        if inMemory { return queue.sync { memoryBlobs[hash] } }
        return try? Data(contentsOf: Store.blobDir.appendingPathComponent(hash))
    }

    private func deleteOrphanBlobs() {
        let referenced = Set(query("SELECT DISTINCT blob_hash FROM items WHERE blob_hash IS NOT NULL") { Store.col($0, 0) ?? "" })
        if inMemory { queue.sync { memoryBlobs = memoryBlobs.filter { referenced.contains($0.key) } }; return }
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: Store.blobDir.path) else { return }
        for f in files where !referenced.contains(f) {
            try? FileManager.default.removeItem(at: Store.blobDir.appendingPathComponent(f))
        }
    }

    // MARK: - Insert

    /// Inserts a capture, or if identical content already exists, bumps that row to the top.
    @discardableResult
    func insert(_ c: Capture) -> Item {
        let blobHash = c.blobData.map { writeBlob($0) }
        let hashInput = Data((c.kind.rawValue + "\u{0}" + c.plain + "\u{0}" + (blobHash ?? "")).utf8)
        let contentHash = Store.sha256(hashInput)
        let now = Date().timeIntervalSince1970
        if let existing = query("SELECT \(Store.itemColumns) FROM items WHERE content_hash = ? LIMIT 1", [.text(contentHash)], Store.item).first {
            run("UPDATE items SET created_at = ?, last_used_at = ?, use_count = use_count + 1, source_bundle_id = COALESCE(?, source_bundle_id), source_name = COALESCE(?, source_name) WHERE id = ?",
                [.real(now), .real(now), .text(c.sourceBundleID), .text(c.sourceName), .int(existing.id)])
            return get(existing.id) ?? existing
        }
        let flags = Redactor.flags(in: c.plain)
        run("""
        INSERT INTO items(kind, preview, plain, blob_hash, blob_type, source_bundle_id, source_name, created_at, last_used_at, use_count, pinned, keyword, redaction_flags, size, content_hash)
        VALUES(?,?,?,?,?,?,?,?,?,0,0,NULL,?,?,?)
        """, [.text(c.kind.rawValue), .text(Item.makePreview(c.plain)), .text(c.plain), .text(blobHash), .text(c.blobType),
              .text(c.sourceBundleID), .text(c.sourceName), .real(now), .real(now), .int(Int64(flags.rawValue)), .int(Int64(c.size)), .text(contentHash)])
        let id = queue.sync { sqlite3_last_insert_rowid(db) }
        return get(id)!
    }

    // MARK: - Read

    func get(_ id: Int64) -> Item? {
        query("SELECT \(Store.itemColumns) FROM items WHERE id = ?", [.int(id)], Store.item).first
    }

    /// 1 = newest.
    func item(atPosition pos: Int) -> Item? {
        guard pos >= 1 else { return nil }
        return query("SELECT \(Store.itemColumns) FROM items ORDER BY created_at DESC LIMIT 1 OFFSET ?", [.int(Int64(pos - 1))], Store.item).first
    }

    func recent(limit: Int = 200, offset: Int = 0) -> [Item] {
        query("SELECT \(Store.itemColumns) FROM items ORDER BY created_at DESC LIMIT ? OFFSET ?", [.int(Int64(limit)), .int(Int64(offset))], Store.item)
    }

    func all() -> [Item] {
        query("SELECT \(Store.itemColumns) FROM items ORDER BY created_at DESC", [], Store.item)
    }

    func pinned() -> [Item] {
        query("SELECT \(Store.itemColumns) FROM items WHERE pinned = 1 ORDER BY keyword IS NULL, keyword, created_at DESC", [], Store.item)
    }

    func snippet(keyword: String) -> Item? {
        query("SELECT \(Store.itemColumns) FROM items WHERE pinned = 1 AND keyword = ? COLLATE NOCASE LIMIT 1", [.text(keyword)], Store.item).first
    }

    func count() -> Int { Int(scalar("SELECT COUNT(*) FROM items")) }

    func totalBytes() -> Int { Int(scalar("SELECT COALESCE(SUM(size), 0) FROM items")) }

    func items(since: Date) -> [Item] {
        query("SELECT \(Store.itemColumns) FROM items WHERE created_at >= ? ORDER BY created_at DESC", [.real(since.timeIntervalSince1970)], Store.item)
    }

    /// FTS5 ranking first, then substring matches the tokenizer missed, newest first. Short queries
    /// (under three characters) are substring-only because prefix tokens match too much.
    func search(_ raw: String, limit: Int = 200) -> [Item] {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return recent(limit: limit) }
        var out: [Item] = []
        var seen = Set<Int64>()
        func add(_ items: [Item]) { for i in items where !seen.contains(i.id) { seen.insert(i.id); out.append(i) } }

        let substring = query("SELECT \(Store.itemColumns) FROM items WHERE plain LIKE ? ESCAPE '\\' ORDER BY created_at DESC LIMIT ?",
                              [.text("%" + Store.escapeLike(q) + "%"), .int(Int64(limit))], Store.item)
        if q.count < 3 { add(substring); return out }

        let tokens = q.split(whereSeparator: { $0.isWhitespace }).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
        let match = tokens.joined(separator: " ")
        let fts = query("""
            SELECT \(Store.qualifiedColumns) FROM items_fts JOIN items ON items.id = items_fts.rowid
            WHERE items_fts MATCH ? ORDER BY bm25(items_fts), items.created_at DESC, items.use_count DESC LIMIT ?
            """, [.text(match), .int(Int64(limit))], Store.item)
        add(fts)
        add(substring)
        return out
    }

    private static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: - Update

    func touch(_ id: Int64) {
        run("UPDATE items SET last_used_at = ?, use_count = use_count + 1 WHERE id = ?", [.real(Date().timeIntervalSince1970), .int(id)])
    }

    func setPinned(_ id: Int64, _ pinned: Bool, keyword: String? = nil) {
        if pinned {
            run("UPDATE items SET pinned = 1, keyword = COALESCE(?, keyword) WHERE id = ?", [.text(keyword?.isEmpty == true ? nil : keyword), .int(id)])
        } else {
            run("UPDATE items SET pinned = 0, keyword = NULL WHERE id = ?", [.int(id)])
        }
    }

    func setKeyword(_ id: Int64, _ keyword: String?) {
        run("UPDATE items SET keyword = ? WHERE id = ?", [.text(keyword?.isEmpty == true ? nil : keyword), .int(id)])
    }

    // MARK: - Delete

    func delete(_ id: Int64) {
        run("DELETE FROM vectors WHERE item_id = ?", [.int(id)])
        run("DELETE FROM items WHERE id = ?", [.int(id)])
        deleteOrphanBlobs()
    }

    func delete(bundleID: String) -> Int {
        let n = scalar("SELECT COUNT(*) FROM items WHERE source_bundle_id = ?", [.text(bundleID)])
        run("DELETE FROM vectors WHERE item_id IN (SELECT id FROM items WHERE source_bundle_id = ?)", [.text(bundleID)])
        run("DELETE FROM items WHERE source_bundle_id = ?", [.text(bundleID)])
        deleteOrphanBlobs()
        return Int(n)
    }

    /// Everything, including pinned items and the assist log.
    func wipe() {
        run("DELETE FROM vectors"); run("DELETE FROM items"); run("DELETE FROM assist_log")
        deleteOrphanBlobs()
        exec("PRAGMA incremental_vacuum")
        exec("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    /// Test hook: moves a row back in time so retention can be exercised.
    func backdate(_ id: Int64, to date: Date) {
        run("UPDATE items SET created_at = ?, last_used_at = ? WHERE id = ?", [.real(date.timeIntervalSince1970), .real(date.timeIntervalSince1970), .int(id)])
    }

    // MARK: - Retention

    /// Applies the age, count and size caps. Pinned items are exempt. Returns rows deleted.
    @discardableResult
    func enforceRetention(days: Int = Prefs.retentionDays, maxItems: Int = Prefs.retentionItems, maxBytes: Int = Prefs.retentionBytes) -> Int {
        let before = count()
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        run("DELETE FROM items WHERE pinned = 0 AND created_at < ?", [.real(cutoff)])
        run("""
            DELETE FROM items WHERE pinned = 0 AND id NOT IN (
                SELECT id FROM items WHERE pinned = 0 ORDER BY created_at DESC LIMIT ?)
            """, [.int(Int64(maxItems))])
        // Size cap: drop the oldest unpinned rows until under the limit.
        var total = totalBytes()
        if total > maxBytes {
            let oldest = query("SELECT id, size FROM items WHERE pinned = 0 ORDER BY created_at ASC") { (sqlite3_column_int64($0, 0), Int(sqlite3_column_int64($0, 1))) }
            var doomed: [Int64] = []
            for (id, size) in oldest where total > maxBytes { doomed.append(id); total -= size }
            for id in doomed { run("DELETE FROM items WHERE id = ?", [.int(id)]) }
        }
        run("DELETE FROM vectors WHERE item_id NOT IN (SELECT id FROM items)")
        deleteOrphanBlobs()
        let removed = before - count()
        if removed > 0 { exec("PRAGMA incremental_vacuum(200)") }
        return removed
    }

    // MARK: - Vectors (Assist tier 1)

    func vector(for id: Int64, model: String) -> [Float]? {
        query("SELECT vec FROM vectors WHERE item_id = ? AND model = ?", [.int(id), .text(model)]) { s -> [Float] in
            let n = Int(sqlite3_column_bytes(s, 0)) / MemoryLayout<Float>.size
            guard let p = sqlite3_column_blob(s, 0) else { return [] }
            return Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: Float.self), count: n))
        }.first
    }

    func setVector(_ id: Int64, model: String, _ v: [Float]) {
        let data = v.withUnsafeBufferPointer { Data(buffer: $0) }
        run("INSERT OR REPLACE INTO vectors(item_id, model, vec) VALUES(?,?,?)", [.int(id), .text(model), .blob(data)])
    }

    func allVectors(model: String) -> [(Int64, [Float])] {
        query("SELECT item_id, vec FROM vectors WHERE model = ?", [.text(model)]) { s -> (Int64, [Float]) in
            let n = Int(sqlite3_column_bytes(s, 1)) / MemoryLayout<Float>.size
            guard let p = sqlite3_column_blob(s, 1) else { return (sqlite3_column_int64(s, 0), []) }
            return (sqlite3_column_int64(s, 0), Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: Float.self), count: n)))
        }
    }

    func itemsMissingVectors(model: String, limit: Int = 50) -> [Item] {
        query("""
            SELECT \(Store.itemColumns) FROM items WHERE kind IN ('text','rtf','html','url')
            AND id NOT IN (SELECT item_id FROM vectors WHERE model = ?) ORDER BY created_at DESC LIMIT ?
            """, [.text(model), .int(Int64(limit))], Store.item)
    }

    // MARK: - Assist log

    func logAssist(provider: String, model: String, itemCount: Int, chars: Int, inputTokens: Int, outputTokens: Int, prompt: String) {
        run("INSERT INTO assist_log(at, provider, model, item_count, chars, input_tokens, output_tokens, prompt) VALUES(?,?,?,?,?,?,?,?)",
            [.real(Date().timeIntervalSince1970), .text(provider), .text(model), .int(Int64(itemCount)), .int(Int64(chars)),
             .int(Int64(inputTokens)), .int(Int64(outputTokens)), .text(prompt)])
    }

    func assistLog(limit: Int = 100) -> [AssistLogEntry] {
        query("SELECT id, at, provider, model, item_count, chars, input_tokens, output_tokens, prompt FROM assist_log ORDER BY at DESC LIMIT ?", [.int(Int64(limit))]) { s in
            AssistLogEntry(id: sqlite3_column_int64(s, 0), at: Date(timeIntervalSince1970: sqlite3_column_double(s, 1)),
                           provider: Store.col(s, 2) ?? "", model: Store.col(s, 3) ?? "", itemCount: Int(sqlite3_column_int64(s, 4)),
                           chars: Int(sqlite3_column_int64(s, 5)), inputTokens: Int(sqlite3_column_int64(s, 6)),
                           outputTokens: Int(sqlite3_column_int64(s, 7)), prompt: Store.col(s, 8) ?? "")
        }
    }
}

// MARK: - Settings (shared defaults so the CLI process and the app agree)

enum Prefs {
    static var defaults: UserDefaults = {
        let suite = ProcessInfo.processInfo.environment["CLIPMAC_HOME"] == nil ? "com.keithadler.clipmac.shared" : "com.keithadler.clipmac.test"
        return UserDefaults(suiteName: suite) ?? .standard
    }()

    static var sessionOnly: Bool { defaults.bool(forKey: "sessionOnly") }
    static var retentionDays: Int { let v = defaults.integer(forKey: "retentionDays"); return v > 0 ? v : 30 }
    static var retentionItems: Int { let v = defaults.integer(forKey: "retentionItems"); return v > 0 ? v : 2000 }
    static var retentionBytes: Int { let v = defaults.integer(forKey: "retentionMB"); return (v > 0 ? v : 1024) * 1_048_576 }
    static var sizeCapBytes: Int { let v = defaults.integer(forKey: "sizeCapMB"); return (v > 0 ? v : 50) * 1_048_576 }
    static var autoPaste: Bool { defaults.object(forKey: "autoPaste") as? Bool ?? true }
    static var restorePrevious: Bool { defaults.object(forKey: "restorePrevious") as? Bool ?? true }
    static var restoreDelayMs: Int { let v = defaults.integer(forKey: "restoreDelayMs"); return v > 0 ? v : 500 }
    static var pausedUntil: Date? {
        get { let t = defaults.double(forKey: "pausedUntil"); return t > 0 ? Date(timeIntervalSince1970: t) : nil }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "pausedUntil") }
    }
    static var isPaused: Bool { if let u = pausedUntil { return u > Date() }; return false }

    static let defaultExclusions: [String] = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx", "com.agilebits.onepassword4",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.apple.PasswordsMenuBarExtra",
        "com.bitwarden.desktop", "com.lastpass.LastPass", "com.dashlane.Dashlane", "com.dashlane.dashlanephonefinal",
        "org.keepassxc.keepassxc", "com.markmcguill.strongbox.mac", "com.enpass.Enpass", "com.roboform.RoboForm",
        "com.nordpass.macos", "com.keepersecurity.keeperdesktop", "com.proton.pass", "com.apple.Passwords-Prefs.extension",
    ]
    static var excludedBundleIDs: [String] {
        get { defaults.stringArray(forKey: "excludedBundleIDs") ?? defaultExclusions }
        set { defaults.set(newValue, forKey: "excludedBundleIDs") }
    }

    // Assist
    static var semanticSearch: Bool { defaults.object(forKey: "semanticSearch") as? Bool ?? true }
    static var onDeviceModel: Bool { defaults.bool(forKey: "onDeviceModel") }
    static var cloudAssist: Bool { defaults.bool(forKey: "cloudAssist") }
    static var cloudProvider: String { defaults.string(forKey: "cloudProvider") ?? "anthropic" }
    static var cloudModel: String {
        if let m = defaults.string(forKey: "cloudModel"), !m.isEmpty { return m }
        return cloudProvider == "openai" ? "gpt-5" : "claude-opus-5"
    }

    // Hotkey
    static var hotkeyCode: Int { defaults.object(forKey: "hotkeyCode") as? Int ?? 9 }          // kVK_ANSI_V
    static var hotkeyModifiers: Int { defaults.object(forKey: "hotkeyModifiers") as? Int ?? 0x0900 } // cmd + option (Carbon)
}
