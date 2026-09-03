//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.

import Foundation
import AppKit

enum TransformSuite {
    static let suite = TestSuite(name: "Transform", cases: [
        TestCase(name: "tracking parameters are stripped, everything else kept") { t in
            t.equal(Transform.stripTracking(in: "https://example.com/a?utm_source=x&id=7&fbclid=abc"), "https://example.com/a?id=7", "keeps real parameters")
            t.equal(Transform.stripTracking(in: "https://example.com/a?utm_source=x"), "https://example.com/a", "drops the question mark when nothing is left")
            t.equal(Transform.stripTracking(in: "see https://a.com/?gclid=1 and https://b.com/?q=2&mc_cid=3 ok"), "see https://a.com/ and https://b.com/?q=2 ok", "several links in prose")
            t.equal(Transform.stripTracking(in: "https://example.com/path#frag"), "https://example.com/path#frag", "untouched without a query")
            t.equal(Transform.stripTracking(in: "no links here"), "no links here", "plain text untouched")
            t.check(Transform.isTracking("utm_campaign") && Transform.isTracking("fbclid") && !Transform.isTracking("id"), "classification")
        },
        TestCase(name: "text transforms") { t in
            t.equal(Transform.lowercase.apply("Hello World"), "hello world", "lower")
            t.equal(Transform.uppercase.apply("Hello"), "HELLO", "upper")
            t.equal(Transform.titleCase.apply("hello big world"), "Hello Big World", "title")
            t.equal(Transform.trimmed.apply("  x \n"), "x", "trim")
            t.equal(Transform.oneLine.apply("a\n  b  \n\nc"), "a b c", "one line")
            t.equal(Transform.clean.apply("  https://e.com/?utm_medium=m \n"), "https://e.com/", "clean = trim + strip")
        },
        TestCase(name: "markdown link and json") { t in
            t.equal(Transform.markdownLink.apply("https://example.com/docs", title: "Example Docs"), "[Example Docs](https://example.com/docs)", "title from window")
            t.equal(Transform.markdownLink.apply("https://example.com/docs", title: nil), "[example.com](https://example.com/docs)", "host when no title")
            let pretty = Transform.prettyJSON.apply("{\"b\":1,\"a\":[1,2]}")
            t.check(pretty.contains("\n") && pretty.contains("\"a\" : ["), "pretty printed and sorted")
            t.equal(Transform.prettyJSON.apply("not json"), "not json", "non-json unchanged")
            t.check(Transform.looksLikeJSON("{\"a\":1}") && !Transform.looksLikeJSON("{a:1}") && !Transform.looksLikeJSON("hello"), "json detection")
        },
        TestCase(name: "availability per kind") { t in
            let url = Store.shared.insert(TestKit.capture("https://x.com/?utm_a=1", kind: .url))
            let text = Store.shared.insert(TestKit.capture("{\"a\":1}"))
            let img = Store.shared.insert(TestKit.capture("", kind: .image, blob: Data([1]), blobType: "public.png"))
            t.check(Transform.available(for: url).contains(.markdownLink) && !Transform.available(for: url).contains(.prettyJSON), "url set")
            t.check(Transform.available(for: text).contains(.prettyJSON), "json offered for json text")
            t.check(Transform.available(for: img).isEmpty, "nothing for images")
        },
        TestCase(name: "transform paste writes plain transformed text") { t in
            let pb = CaptureSuite.pasteboard()
            let item = Store.shared.insert(TestKit.capture("  Hello  ", kind: .rtf, blob: Data("{\\rtf1 Hello}".utf8), blobType: "public.rtf"))
            var copy = item
            copy.plain = Transform.clean.apply(item.plain); copy.blobHash = nil
            Paster.write(copy, plain: true, to: pb)
            t.equal(pb.string(forType: .string), "Hello", "cleaned text")
            t.check(pb.data(forType: .rtf) == nil, "rich data dropped")
        },
        TestCase(name: "paste stack joins queued items") { t in
            let stack = PasteStack.shared
            stack.clear()
            stack.push(Store.shared.insert(TestKit.capture(" first ")))
            stack.push(Store.shared.insert(TestKit.capture("second\nline")))
            stack.push(Store.shared.insert(TestKit.capture("/tmp/a\n/tmp/b", kind: .file)))
            t.equal(stack.joined(asList: false), "first\nsecond\nline\n/tmp/a\n/tmp/b", "newline joined, trimmed")
            t.equal(stack.joined(asList: true), "- first\n- second\n  line\n- /tmp/a\n  /tmp/b", "markdown list with continuation indent")
            stack.clear()
        },
        TestCase(name: "near-duplicates collapse and count") { t in
            let s = Store.shared
            let a = s.insert(TestKit.capture("foo bar"))
            let b = s.insert(TestKit.capture("  foo   bar\n"))
            t.equal(b.id, a.id, "whitespace differences are the same item")
            t.equal(s.get(a.id)?.useCount, 1, "counted as copied twice")
            t.equal(s.get(a.id)?.plain, "foo bar", "first text kept")
            let c = s.insert(TestKit.capture("Foo bar"))
            t.check(c.id != a.id, "case differences are different items")
            let img1 = s.insert(TestKit.capture("", kind: .image, blob: Data([1, 2]), blobType: "public.png"))
            let img2 = s.insert(TestKit.capture("", kind: .image, blob: Data([1, 2]), blobType: "public.png"))
            t.equal(img1.id, img2.id, "identical image bytes are one item")
        },
        TestCase(name: "window title is stored and shown") { t in
            var cap = TestKit.capture("from a window", app: "com.apple.Safari", name: "Safari")
            cap.sourceTitle = "GitHub issue #42"
            let item = Store.shared.insert(cap)
            t.equal(Store.shared.get(item.id)?.sourceTitle, "GitHub issue #42", "title round trip")
            var again = TestKit.capture("from a window", app: "com.apple.Safari", name: "Safari")
            again.sourceTitle = nil
            _ = Store.shared.insert(again)
            t.equal(Store.shared.get(item.id)?.sourceTitle, "GitHub issue #42", "a copy without a title keeps the known one")
            t.check(Dump.dict(Store.shared.get(item.id)!)["source_title"] as? String == "GitHub issue #42", "in json")
        },
        TestCase(name: "ocr reads text out of an image") { t in
            let size = NSSize(width: 600, height: 160)
            let img = NSImage(size: size)
            img.lockFocus()
            NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
            ("Invoice 4471 due Friday" as NSString).draw(at: NSPoint(x: 30, y: 50), withAttributes: [.font: NSFont.systemFont(ofSize: 48, weight: .semibold), .foregroundColor: NSColor.black])
            img.unlockFocus()
            let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            guard let text = OCR.recognize(png) else { t.fail("vision found no text"); return }
            t.check(text.lowercased().contains("invoice") && text.contains("4471"), "recognised: \(text)")
            let item = Store.shared.insert(TestKit.capture("", kind: .image, blob: png, blobType: "public.png"))
            Store.shared.setPlain(item.id, text, preview: "Image: " + text)
            t.check(Store.shared.search("invoice").contains { $0.id == item.id }, "screenshot is searchable")
        },
    ])
}
