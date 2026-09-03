import Foundation

/// Seeded so a failure prints a seed that reproduces it.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum PropertySuite {
    static func randomText(_ rng: inout SeededRNG, _ n: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-=:.,/+\n\"'éñ日本🙂")
        return String((0..<n).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
    }

    static let suite = TestSuite(name: "Properties", cases: [
        TestCase(name: "redactor never crashes and masking is idempotent") { t in
            let seed = UInt64(Date().timeIntervalSince1970)
            var rng = SeededRNG(state: seed)
            let secrets = ["sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", "AKIAIOSFODNN7EXAMPLE", "password=hunter2hunter2", "4111 1111 1111 1111"]
            for i in 0..<300 {
                var s = randomText(&rng, Int.random(in: 0..<200, using: &rng))
                // A word after the secret: a digit directly after a card number extends the run past 19
                // digits and the rule (correctly) no longer sees a card number there.
                if i % 3 == 0 { s += " " + secrets[i % secrets.count] + " end " + randomText(&rng, 20) }
                let once = Redactor.mask(s)
                let twice = Redactor.mask(once.text)
                if once.text != twice.text { t.fail("seed \(seed): mask not idempotent for: \(s.prefix(60))"); break }
                if i % 3 == 0 && !once.text.contains("[REDACTED") { t.fail("seed \(seed): secret survived in: \(s.prefix(60))"); break }
                _ = Redactor.flags(in: s)
            }
            t.check(true, "300 random inputs (seed \(seed))")
            t.equal(Redactor.mask("").text, "", "empty")
            t.check(Redactor.flags(in: String(repeating: "a", count: 300_000)).isEmpty, "huge input bounded")
        },
        TestCase(name: "store survives concurrent inserts") { t in
            let s = Store.shared
            DispatchQueue.concurrentPerform(iterations: 8) { worker in
                for i in 0..<50 { _ = s.insert(TestKit.capture("worker \(worker) item \(i)")) }
            }
            t.equal(s.count(), 400, "every insert landed")
            t.equal(s.all().filter { $0.plain.hasPrefix("worker 3 ") }.count, 50, "each worker's rows are all there")
            t.check(s.search("worker 3 item 7").contains { $0.plain == "worker 3 item 7" }, "searchable")
            DispatchQueue.concurrentPerform(iterations: 4) { _ in _ = s.enforceRetention(days: 30, maxItems: 100, maxBytes: 1 << 30) }
            t.equal(s.count(), 100, "concurrent retention converges")
        },
        TestCase(name: "search and semantic search stay fast at the item cap") { t in
            let s = Store.shared
            for i in 0..<2000 { _ = s.insert(TestKit.capture("note number \(i) about \(["invoices", "recipes", "meetings", "links"][i % 4])")) }
            var start = Date()
            let hits = s.search("number 199")
            let searchMs = Date().timeIntervalSince(start) * 1000
            t.check(hits.contains { $0.plain.contains("number 1999") }, "finds the row")
            t.check(searchMs < 200, "fts search over 2,000 rows in \(Int(searchMs)) ms")

            guard let dim = Assist.shared.vector(for: "probe")?.count else { t.skip("no embedding"); return }
            for item in s.recent(limit: 2000) {
                var v = (0..<dim).map { _ in Float.random(in: -1...1) }
                let n = sqrt(v.reduce(0) { $0 + $1 * $1 }); v = v.map { $0 / n }
                s.setVector(item.id, model: Assist.shared.modelTag, v)
            }
            start = Date()
            _ = Assist.shared.semanticSearch("anything at all")
            let semMs = Date().timeIntervalSince(start) * 1000
            t.check(semMs < 300, "cosine over 2,000 vectors (first call loads cache) in \(Int(semMs)) ms")
        },
        TestCase(name: "file-backed store persists, writes blobs, cleans orphans") { t in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clipmac-store-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let path = dir.appendingPathComponent("history.db").path
            let blobs = dir.appendingPathComponent("blobs")
            var id: Int64 = 0, hash = ""
            do {
                let s = Store(path: path, blobDir: blobs)
                let img = s.insert(TestKit.capture("", kind: .image, blob: Data(repeating: 7, count: 300), blobType: "public.png"))
                _ = s.insert(TestKit.capture("persisted text"))
                id = img.id; hash = img.blobHash ?? ""
                t.check(FileManager.default.fileExists(atPath: blobs.appendingPathComponent(hash).path), "blob file written")
            }
            t.check(FileManager.default.fileExists(atPath: path), "database file exists")
            let s2 = Store(path: path, blobDir: blobs)
            t.equal(s2.count(), 2, "rows survive reopen")
            t.equal(s2.blob(hash)?.count, 300, "blob readable after reopen")
            s2.delete(id)
            t.check(!FileManager.default.fileExists(atPath: blobs.appendingPathComponent(hash).path), "orphan blob file removed")
            s2.wipe()
            t.equal(s2.count(), 0, "wipe on disk")
        },
    ])
}
