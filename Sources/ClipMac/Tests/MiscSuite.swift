import Foundation
import Carbon.HIToolbox

enum MiscSuite {
    static let suite = TestSuite(name: "Misc", cases: [
        TestCase(name: "version compare") { t in
            t.check(Updates.isNewer("0.2.0", than: "0.1.0"), "minor")
            t.check(Updates.isNewer("1.0", than: "0.9.9"), "major with fewer parts")
            t.check(!Updates.isNewer("0.1.0", than: "0.1.0"), "equal")
            t.check(!Updates.isNewer("0.1", than: "0.1.1"), "older with fewer parts")
            t.check(Updates.isNewer("0.1.10", than: "0.1.9"), "numeric not lexical")
        },
        TestCase(name: "hotkey descriptions and defaults") { t in
            t.equal(Hotkey.describe(keyCode: 9, modifiers: cmdKey | optionKey), "⌥⌘V", "panel default")
            t.equal(Hotkey.describe(keyCode: 9, modifiers: cmdKey | optionKey | shiftKey | controlKey), "⌃⌥⇧⌘V", "all modifiers in Apple order")
            t.equal(Hotkey.describe(keyCode: 49, modifiers: cmdKey), "⌘Space", "named key")
            t.equal(Hotkey.describe(kind: .panel), "⌥⌘V", "fresh defaults")
            t.equal(Hotkey.describe(kind: .plainPaste), "⌥⇧⌘V", "plain paste default")
            t.equal(Hotkey.describe(kind: .pasteNext), "⌃⌥⌘V", "paste next default")
            t.equal(Hotkey.carbonModifiers([.command, .shift]), cmdKey | shiftKey, "appkit → carbon")
            t.check(Hotkey.Kind.panel.enabled && Hotkey.Kind.plainPaste.enabled, "enabled by default")
        },
        TestCase(name: "url scheme parsing") { t in
            func p(_ s: String) -> URLCommands.Command? { URLCommands.parse(URL(string: s)!) }
            t.equal(p("clipmac://open"), .open, "open")
            t.equal(p("clipmac://close"), .close, "close")
            t.equal(p("clipmac://search?q=invoice%20due"), .search("invoice due"), "search decodes")
            t.equal(p("clipmac://paste/42"), .paste(ref: "#42", plain: false), "bare number is an id")
            t.equal(p("clipmac://paste/42?plain=1"), .paste(ref: "#42", plain: true), "plain flag")
            t.equal(p("clipmac://paste/3?by=position"), .paste(ref: "3", plain: false), "position when asked")
            t.equal(p("clipmac://copy/%2342"), .copy(ref: "#42", plain: false), "hash form")
            t.equal(p("clipmac://pause?minutes=30"), .pause(minutes: 30), "pause minutes")
            t.equal(p("clipmac://pause"), .pause(minutes: 10), "pause default")
            t.equal(p("clipmac://settings"), .settings, "settings")
            t.equal(p("clipmac://nope"), .unknown, "unknown host")
            t.equal(p("clipmac://paste"), .unknown, "paste without ref")
            t.check(p("https://example.com") == nil, "other schemes ignored")
        },
        TestCase(name: "text replacement export") { t in
            let s = Store.shared
            let a = s.insert(TestKit.capture("Keith Adler"))
            s.setPinned(a.id, true, keyword: "kk")
            let b = s.insert(TestKit.capture("no keyword"))
            s.setPinned(b.id, true)
            let img = s.insert(TestKit.capture("", kind: .image, blob: Data([1]), blobType: "public.png"))
            s.setPinned(img.id, true, keyword: "pic")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("clipmac-test-\(UUID().uuidString).plist")
            defer { try? FileManager.default.removeItem(at: url) }
            let n = try Snippets.exportTextReplacements(to: url, items: s.pinned())
            t.equal(n, 1, "only keyworded text pins export")
            let rows = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [[String: String]]
            t.equal(rows?.first?["shortcut"], "kk", "shortcut")
            t.equal(rows?.first?["phrase"], "Keith Adler", "phrase")
        },
        TestCase(name: "dump json shape") { t in
            let s = Store.shared
            let a = s.insert(TestKit.capture("token sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", app: "com.x", name: "X"))
            s.setPinned(a.id, true, keyword: "k")
            let d = Dump.dict(s.get(a.id)!, position: 1)
            t.equal(d["position"] as? Int, 1, "position")
            t.equal(d["keyword"] as? String, "k", "keyword")
            t.equal(d["sensitive"] as? Bool, true, "sensitive")
            t.equal(d["sensitive_kinds"] as? [String], ["API key"], "kinds")
            t.equal(d["source_bundle_id"] as? String, "com.x", "bundle id")
            t.check(JSONSerialization.isValidJSONObject(d), "valid json object")
            t.check(Dump.json(d).contains("\"created_at\""), "serializes")
            let table = Dump.table([s.get(a.id)!])
            t.check(table.contains("!") && table.contains("[k]"), "table marks sensitive and keyword")
            t.equal(Dump.table([]), "(no items)\n", "empty table")
        },
        TestCase(name: "snippets matching") { t in
            let s = Store.shared
            let a = s.insert(TestKit.capture("email signature"))
            s.setPinned(a.id, true, keyword: "sig")
            let b = s.insert(TestKit.capture("address block"))
            s.setPinned(b.id, true, keyword: "addr")
            t.equal(Snippets.matching("").count, 2, "empty query lists all pins")
            t.equal(Snippets.matching("si").map(\.id), [a.id], "keyword prefix")
            t.equal(Snippets.matching("block").map(\.id), [b.id], "content match")
            t.check(Snippets.matching("zzz").isEmpty, "no match")
        },
    ])
}
