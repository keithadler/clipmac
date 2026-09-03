// Puts an RTF string, a PNG image, and a file URL on the pasteboard one after another so the
// capture path for each kind can be checked with `clipmac list`.
import AppKit
let pb = NSPasteboard.general
func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.7)) }

// RTF
let attr = NSAttributedString(string: "Bold heading", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
let rtf = attr.rtf(from: NSRange(location: 0, length: attr.length), documentAttributes: [:])!
pb.clearContents()
let rtfItem = NSPasteboardItem()
rtfItem.setData(rtf, forType: .rtf)
rtfItem.setString("Bold heading", forType: .string)
pb.writeObjects([rtfItem]); print("rtf written"); settle()

// PNG
let img = NSImage(size: NSSize(width: 64, height: 64))
img.lockFocus(); NSColor.systemOrange.setFill(); NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 56, height: 56)).fill(); img.unlockFocus()
let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
pb.clearContents()
let imgItem = NSPasteboardItem()
imgItem.setData(png, forType: .png)
pb.writeObjects([imgItem]); print("png written (\(png.count) bytes)"); settle()

// File
pb.clearContents()
pb.writeObjects([URL(fileURLWithPath: "/Applications/Clip for Mac.app") as NSURL]); print("file url written"); settle()
