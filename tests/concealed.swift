// Writes a string marked with org.nspasteboard.ConcealedType, the convention password managers use.
// Clip for Mac must not capture it. Run: swift tests/concealed.swift && clipmac list --limit 1
import AppKit
let pb = NSPasteboard.general
pb.clearContents()
let item = NSPasteboardItem()
item.setString("hunter2-this-must-never-appear", forType: .string)
item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
pb.writeObjects([item])
print("wrote concealed string, changeCount \(pb.changeCount)")
