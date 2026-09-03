import Foundation
import AppKit

enum PasterSuite {
    static let suite = TestSuite(name: "Paster", cases: [
        TestCase(name: "text item writes a string") { t in
            let pb = CaptureSuite.pasteboard()
            let item = Store.shared.insert(TestKit.capture("hello"))
            Paster.write(item, plain: false, to: pb)
            t.equal(pb.string(forType: .string), "hello", "string on pasteboard")
            t.equal(pb.pasteboardItems?.first?.types.count, 1, "only one type")
            t.equal(Store.shared.get(item.id)?.useCount, 1, "use counted")
        },
        TestCase(name: "rich item writes rtf plus string; plain strips") { t in
            let pb = CaptureSuite.pasteboard()
            let rtf = Data("{\\rtf1\\ansi Bold}".utf8)
            let item = Store.shared.insert(TestKit.capture("Bold", kind: .rtf, blob: rtf, blobType: NSPasteboard.PasteboardType.rtf.rawValue))
            Paster.write(item, plain: false, to: pb)
            t.equal(pb.data(forType: .rtf), rtf, "rtf data")
            t.equal(pb.string(forType: .string), "Bold", "string alongside")
            Paster.write(item, plain: true, to: pb)
            t.check(pb.data(forType: .rtf) == nil, "plain drops rtf")
            t.equal(pb.string(forType: .string), "Bold", "plain keeps string")
        },
        TestCase(name: "image and file items") { t in
            let pb = CaptureSuite.pasteboard()
            let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
            let img = Store.shared.insert(TestKit.capture("", kind: .image, blob: png, blobType: NSPasteboard.PasteboardType.png.rawValue))
            Paster.write(img, plain: false, to: pb)
            t.equal(pb.data(forType: .png), png, "png bytes")
            let file = Store.shared.insert(TestKit.capture("/Applications\n/tmp", kind: .file))
            Paster.write(file, plain: false, to: pb)
            let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            t.equal(urls.map(\.path), ["/Applications", "/tmp"], "file urls")
            Paster.write(file, plain: true, to: pb)
            t.equal(pb.string(forType: .string), "/Applications\n/tmp", "plain gives the paths as text")
        },
        TestCase(name: "snapshot and restore") { t in
            let pb = CaptureSuite.pasteboard()
            let item = NSPasteboardItem()
            item.setString("keep me", forType: .string)
            item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            pb.writeObjects([item])
            let snap = Paster.snapshot(of: pb)
            t.equal(snap.items.count, 1, "one item captured")
            t.check(snap.items.first?[NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")] == nil, "concealed marker not carried")
            pb.clearContents(); pb.setString("other", forType: .string)
            Paster.restore(snap, to: pb)
            t.equal(pb.string(forType: .string), "keep me", "restored")
        },
        TestCase(name: "paste stack order") { t in
            let stack = PasteStack.shared
            stack.clear()
            let a = Store.shared.insert(TestKit.capture("first"))
            let b = Store.shared.insert(TestKit.capture("second"))
            stack.push(a); stack.push(b)
            t.equal(stack.count, 2, "two queued")
            t.equal(stack.pop()?.id, a.id, "oldest first")
            t.equal(stack.pop()?.id, b.id, "then next")
            t.check(stack.pop() == nil && stack.isEmpty, "empty")
            stack.push(a); stack.clear()
            t.check(stack.isEmpty, "clear")
        },
    ])
}
