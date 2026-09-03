import Foundation

enum StoreSuite {
    static let suite = TestSuite(name: "Store", cases: [
        TestCase(name: "insert, positions, dedup bumps to top") { t in
            let s = Store.shared
            let a = s.insert(TestKit.capture("Invoice #4471 for the Woodland project is due Friday"))
            let b = s.insert(TestKit.capture("recipe: two eggs, flour, milk"))
            t.equal(s.count(), 2, "two rows")
            t.equal(s.item(atPosition: 1)?.id, b.id, "position 1 is newest")
            t.equal(s.item(atPosition: 2)?.id, a.id, "position 2")
            t.check(s.item(atPosition: 3) == nil && s.item(atPosition: 0) == nil, "out of range is nil")
            let again = s.insert(TestKit.capture("Invoice #4471 for the Woodland project is due Friday", app: "com.other", name: "Other"))
            t.equal(again.id, a.id, "same content reuses the row")
            t.equal(s.count(), 2, "no new row")
            t.equal(s.item(atPosition: 1)?.id, a.id, "bumped to top")
            t.equal(again.useCount, 1, "use count incremented")
            t.equal(again.sourceName, "Other", "source updated to the latest app")
        },
        TestCase(name: "kinds and blobs are part of identity") { t in
            let s = Store.shared
            let text = s.insert(TestKit.capture("same words"))
            let rtf = s.insert(TestKit.capture("same words", kind: .rtf, blob: Data("{\\rtf1 same words}".utf8), blobType: "public.rtf"))
            t.check(text.id != rtf.id, "rtf and text with the same string are different items")
            t.check(rtf.blobHash != nil, "blob stored")
            t.equal(s.blob(rtf.blobHash), Data("{\\rtf1 same words}".utf8), "blob round trip")
        },
        TestCase(name: "search: words, prefixes, substrings, ranking") { t in
            let s = Store.shared
            let inv = s.insert(TestKit.capture("The quarterly invoice for Woodland is overdue"))
            let re = s.insert(TestKit.capture("please reinvoice the client"))
            _ = s.insert(TestKit.capture("recipe: two eggs, flour, milk"))
            t.equal(s.search("invoice").map(\.id), [inv.id, re.id], "word match first, substring match second")
            t.equal(s.search("Wood").first?.id, inv.id, "prefix token")
            t.equal(s.search("odl").map(\.id), [inv.id], "short query is substring only")
            t.equal(s.search("quarterly overdue").map(\.id), [inv.id], "all words must match")
            t.check(s.search("pancake").isEmpty, "no false positives")
            t.equal(s.search("   ").count, 3, "blank query lists everything")
            t.equal(s.search("100% sure_thing").count, 0, "LIKE wildcards are escaped")
        },
        TestCase(name: "pins, keywords, snippets") { t in
            let s = Store.shared
            let sig = s.insert(TestKit.capture("Keith Adler\nkeith@example.com"))
            s.setPinned(sig.id, true, keyword: "sig")
            t.equal(s.pinned().map(\.id), [sig.id], "pinned list")
            t.equal(s.snippet(keyword: "SIG")?.id, sig.id, "keyword lookup is case-insensitive")
            s.setKeyword(sig.id, "")
            t.check(s.get(sig.id)?.keyword == nil, "empty keyword clears")
            s.setPinned(sig.id, false)
            t.check(s.pinned().isEmpty && s.get(sig.id)?.keyword == nil, "unpin clears keyword")
        },
        TestCase(name: "retention by count, age and size; pinned exempt") { t in
            let s = Store.shared
            let sig = s.insert(TestKit.capture("pinned signature"))
            s.setPinned(sig.id, true)
            for i in 0..<20 { _ = s.insert(TestKit.capture("item \(i)")) }
            t.equal(s.enforceRetention(days: 30, maxItems: 5, maxBytes: 1 << 30), 15, "count cap removes the oldest")
            t.equal(s.count(), 6, "five newest plus the pin")
            t.check(s.get(sig.id) != nil, "pinned survives count cap")

            let old = s.insert(TestKit.capture("ancient"))
            s.backdate(old.id, to: Date().addingTimeInterval(-40 * 86400))
            t.equal(s.enforceRetention(days: 30, maxItems: 100, maxBytes: 1 << 30), 1, "age cap removes the old row")
            t.check(s.get(old.id) == nil, "old row gone")

            let big = s.insert(TestKit.capture(String(repeating: "x", count: 5000)))
            s.backdate(big.id, to: Date().addingTimeInterval(-3600))
            t.check(s.enforceRetention(days: 30, maxItems: 100, maxBytes: 4000) >= 1, "size cap removes oldest unpinned")
            t.check(s.get(big.id) == nil, "big old row gone")
            t.check(s.get(sig.id) != nil, "pinned survives size cap")
        },
        TestCase(name: "delete, forget by app, wipe, orphan blobs") { t in
            let s = Store.shared
            let img = s.insert(TestKit.capture("", kind: .image, app: "com.other", blob: Data([1, 2, 3, 4]), blobType: "public.png"))
            _ = s.insert(TestKit.capture("plain text"))
            _ = s.insert(TestKit.capture("token: sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", app: "com.other"))
            t.check(s.all().first { $0.sourceBundleID == "com.other" && $0.kind == .text }?.looksSensitive == true, "sensitive flag stored at insert")
            t.equal(s.delete(bundleID: "com.other"), 2, "forget by app counts rows")
            t.check(s.blob(img.blobHash) == nil, "orphan blob removed")
            t.equal(s.count(), 1, "one left")
            s.wipe()
            t.equal(s.count(), 0, "wipe empties")
            t.check(s.assistLog().isEmpty, "wipe clears the assist log")
        },
        TestCase(name: "touch, items since, assist log") { t in
            let s = Store.shared
            let a = s.insert(TestKit.capture("touch me"))
            s.touch(a.id); s.touch(a.id)
            t.equal(s.get(a.id)?.useCount, 2, "use count")
            t.equal(s.items(since: Date().addingTimeInterval(-60)).count, 1, "items since")
            t.equal(s.items(since: Date().addingTimeInterval(60)).count, 0, "nothing in the future")
            s.logAssist(provider: "anthropic", model: "claude-opus-5", itemCount: 3, chars: 120, inputTokens: 40, outputTokens: 12, prompt: "what?")
            let log = s.assistLog()
            t.equal(log.count, 1, "one entry")
            t.equal(log.first?.outputTokens, 12, "tokens stored")
        },
        TestCase(name: "vectors round trip") { t in
            let s = Store.shared
            let a = s.insert(TestKit.capture("hello"))
            let b = s.insert(TestKit.capture("", kind: .image, blob: Data([9]), blobType: "public.png"))
            s.setVector(a.id, model: "t", [0.1, 0.2, 0.3])
            t.equal(s.vector(for: a.id, model: "t") ?? [], [0.1, 0.2, 0.3], "vector round trip")
            t.check(s.vector(for: a.id, model: "other") == nil, "model tag matters")
            t.check(s.itemsMissingVectors(model: "t").isEmpty, "text item indexed")
            t.equal(s.itemsMissingVectors(model: "other").map(\.id), [a.id], "images are never embedded")
            _ = b
            t.equal(s.allVectors(model: "t").count, 1, "all vectors")
            s.delete(a.id)
            t.check(s.allVectors(model: "t").isEmpty, "vector deleted with item")
        },
    ])
}
