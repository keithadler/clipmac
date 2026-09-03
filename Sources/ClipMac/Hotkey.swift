//  Global hotkey through Carbon's RegisterEventHotKey. Works without Accessibility permission,
//  reports a conflict when another app already owns the combination.

import Foundation
import Carbon.HIToolbox
import AppKit

enum Hotkey {
    private static var ref: EventHotKeyRef?
    private static var handlerInstalled = false
    static var onPress: (() -> Void)?
    private(set) static var conflict = false

    private static let signature: OSType = 0x434C4950 // "CLIP"

    @discardableResult
    static func register(keyCode: Int = Prefs.hotkeyCode, modifiers: Int = Prefs.hotkeyModifiers) -> Bool {
        unregister()
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
                if id.signature == Hotkey.signature { DispatchQueue.main.async { Hotkey.onPress?() } }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
        conflict = status != noErr
        return status == noErr
    }

    static func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    /// "⌥⌘V" style description.
    static func describe(keyCode: Int = Prefs.hotkeyCode, modifiers: Int = Prefs.hotkeyModifiers) -> String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + keyName(keyCode)
    }

    static func keyName(_ code: Int) -> String {
        let names: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 49: "Space", 50: "`", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return names[code] ?? "key \(code)"
    }

    /// Carbon modifier mask from an AppKit event.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.shift) { m |= shiftKey }
        return m
    }
}
