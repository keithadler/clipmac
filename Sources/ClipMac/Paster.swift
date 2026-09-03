//  Putting an item back on the pasteboard, and optionally pasting it.
//
//  Two mechanisms, and the app is honest about which one it's using:
//   1. Copy only — no permission needed. Write, close the panel, the user presses ⌘V.
//   2. Auto-paste — needs Accessibility. Same write, then a synthesized ⌘V into the app that was
//      frontmost (the panel never activates Clip for Mac, so that app is still active).
//
//  After an auto-paste the previous pasteboard is put back after a short delay. There is no way to
//  know when the target app has finished reading the pasteboard (reads don't bump changeCount), so
//  the delay is a setting, default 500 ms, and restore itself can be turned off.

import Foundation
import AppKit

enum Paster {
    struct Snapshot { let items: [[NSPasteboard.PasteboardType: Data]] }

    static func snapshot() -> Snapshot {
        let pb = NSPasteboard.general
        var out: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pb.pasteboardItems ?? [] {
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types where !Monitor.concealedTypes.contains(t.rawValue) {
                if let data = item.data(forType: t) { d[t] = data }
            }
            if !d.isEmpty { out.append(d) }
        }
        return Snapshot(items: out)
    }

    @MainActor
    static func restore(_ s: Snapshot) {
        let pb = NSPasteboard.general
        Monitor.shared.expectOwnChange()
        pb.clearContents()
        let items: [NSPasteboardItem] = s.items.map { dict in
            let it = NSPasteboardItem()
            for (t, d) in dict { it.setData(d, forType: t) }
            return it
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }

    /// Writes the item to the general pasteboard. `plain` strips everything but the string.
    @MainActor
    static func write(_ item: Item, plain: Bool) {
        let pb = NSPasteboard.general
        Monitor.shared.expectOwnChange()
        pb.clearContents()
        if plain || (item.kind != .image && item.kind != .file && item.blobHash == nil) {
            pb.setString(item.plain, forType: .string)
        } else {
            switch item.kind {
            case .file:
                pb.writeObjects(item.filePaths.map { URL(fileURLWithPath: $0) as NSURL })
            case .image:
                if let data = Store.shared.blob(item.blobHash), let type = item.blobType {
                    pb.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
            case .rtf, .html:
                if let data = Store.shared.blob(item.blobHash), let type = item.blobType {
                    pb.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
                pb.setString(item.plain, forType: .string)
            case .text, .url:
                pb.setString(item.plain, forType: .string)
            }
        }
        Store.shared.touch(item.id)
    }

    /// Copy to the pasteboard and, when Accessibility allows it, paste into the frontmost app.
    /// Returns true when a ⌘V was actually sent.
    @MainActor
    @discardableResult
    static func paste(_ item: Item, plain: Bool) -> Bool {
        let previous = Prefs.restorePrevious ? snapshot() : nil
        write(item, plain: plain)
        guard Prefs.autoPaste, Capabilities.accessibilityTrusted else { return false }
        // Give the panel a moment to close so the key event lands in the previous app.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(60)) {
            sendCommandV()
            if let previous {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Prefs.restoreDelayMs)) {
                    restore(previous)
                }
            }
        }
        return true
    }

    static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

extension Paster {
    /// The current clipboard, stripped to its string, pasted (or just re-copied when there is no
    /// Accessibility permission). Nothing happens for images and files.
    @MainActor
    static func pasteCurrentAsPlain() {
        let pb = NSPasteboard.general
        guard let s = pb.string(forType: .string), !s.isEmpty else { NSSound.beep(); return }
        Monitor.shared.expectOwnChange()
        pb.clearContents()
        pb.setString(s, forType: .string)
        guard Prefs.autoPaste, Capabilities.accessibilityTrusted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { sendCommandV() }
    }
}
