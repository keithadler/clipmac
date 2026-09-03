//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  Global hotkeys through Carbon's RegisterEventHotKey. Works without Accessibility permission,
//  reports a conflict when another app already owns the combination. Three of them:
//  open the panel, paste the current clipboard as plain text, paste the next item off the stack.

import Foundation
import Carbon.HIToolbox
import AppKit

enum Hotkey {
    enum Kind: UInt32, CaseIterable, Identifiable {
        case panel = 1, plainPaste = 2, pasteNext = 3
        var id: UInt32 { rawValue }

        var defaultCode: Int { 9 }   // V
        var defaultModifiers: Int {
            switch self {
            case .panel: return cmdKey | optionKey
            case .plainPaste: return cmdKey | optionKey | shiftKey
            case .pasteNext: return cmdKey | optionKey | controlKey
            }
        }
        var codeKey: String { self == .panel ? "hotkeyCode" : "hotkey\(rawValue)Code" }
        var modifiersKey: String { self == .panel ? "hotkeyModifiers" : "hotkey\(rawValue)Modifiers" }
        var enabledKey: String { "hotkey\(rawValue)Enabled" }

        var keyCode: Int { Prefs.defaults.object(forKey: codeKey) as? Int ?? defaultCode }
        var modifiers: Int { Prefs.defaults.object(forKey: modifiersKey) as? Int ?? defaultModifiers }
        var enabled: Bool { self == .panel ? true : (Prefs.defaults.object(forKey: enabledKey) as? Bool ?? true) }

        var label: String {
            switch self {
            case .panel: return String(localized: "Open the panel")
            case .plainPaste: return String(localized: "Paste clipboard as plain text")
            case .pasteNext: return String(localized: "Paste next item from the stack")
            }
        }
    }

    private static var refs: [Kind: EventHotKeyRef] = [:]
    private static var handlerInstalled = false
    static var handlers: [Kind: () -> Void] = [:]
    private(set) static var conflicts: Set<Kind> = []
    static var conflict: Bool { conflicts.contains(.panel) }

    private static let signature: OSType = 0x434C4950 // "CLIP"

    private static func installHandler() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            if id.signature == Hotkey.signature, let kind = Kind(rawValue: id.id) {
                DispatchQueue.main.async { Hotkey.handlers[kind]?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }

    /// Registers (or re-registers) one hotkey from its stored settings. False on conflict.
    @discardableResult
    static func register(_ kind: Kind) -> Bool {
        installHandler()
        unregister(kind)
        guard kind.enabled else { conflicts.remove(kind); return true }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: kind.rawValue)
        let status = RegisterEventHotKey(UInt32(kind.keyCode), UInt32(kind.modifiers), id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[kind] = ref; conflicts.remove(kind) } else { conflicts.insert(kind) }
        return status == noErr
    }

    static func registerAll() { Kind.allCases.forEach { register($0) } }

    static func unregister(_ kind: Kind) {
        if let ref = refs[kind] { UnregisterEventHotKey(ref) }
        refs[kind] = nil
    }

    static func unregisterAll() { Kind.allCases.forEach(unregister) }

    static func set(_ kind: Kind, keyCode: Int, modifiers: Int) -> Bool {
        Prefs.defaults.set(keyCode, forKey: kind.codeKey)
        Prefs.defaults.set(modifiers, forKey: kind.modifiersKey)
        return register(kind)
    }

    static func setEnabled(_ kind: Kind, _ on: Bool) {
        Prefs.defaults.set(on, forKey: kind.enabledKey)
        register(kind)
    }

    /// "⌥⌘V" style description.
    static func describe(_ kind: Kind = .panel) -> String { describe(keyCode: kind.keyCode, modifiers: kind.modifiers) }
    static func describe(kind: Kind) -> String { describe(kind) }

    static func describe(keyCode: Int, modifiers: Int) -> String {
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
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
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
