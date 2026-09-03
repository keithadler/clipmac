//  The floating panel. Non-activating, so the app that was frontmost stays active and the paste
//  target never changes. Keyboard handling lives in a local event monitor rather than SwiftUI key
//  handlers so ⌘-shortcuts work no matter which subview has focus.

import AppKit
import SwiftUI

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    static let shared = PanelController()
    let model = PanelModel()
    private var panel: KeyPanel?
    private var keyMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        if panel == nil { build() }
        guard let panel else { return }
        model.reset()
        if !hasSavedFrame { position(panel) }
        panel.makeKeyAndOrderFront(nil)
        installMonitor()
        model.focusToken += 1
    }

    func hide() {
        removeMonitor()
        panel?.orderOut(nil)
    }

    private func build() {
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 780, height: 470),
                         styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = NSHostingView(rootView: PanelView(model: model))
        p.setFrameAutosaveName("ClipPanel")
        p.minSize = NSSize(width: 640, height: 360)
        p.animationBehavior = .utilityWindow
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { _ in
            Prefs.defaults.set(true, forKey: "panelMoved")
        }
        panel = p
    }

    private var hasSavedFrame: Bool { Prefs.defaults.bool(forKey: "panelMoved") }

    private func position(_ p: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = p.frame.size
        p.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + frame.height * 0.06))
    }

    private func installMonitor() {
        removeMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let panel = self.panel, e.window === panel else { return e }
            return self.handle(e) ? nil : e
        }
    }

    private func removeMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    /// True when the event was consumed.
    private func handle(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        switch e.keyCode {
        case 53: hide(); return true                                  // esc
        case 126: model.move(-1); return true                         // ↑
        case 125: model.move(1); return true                          // ↓
        case 116: model.move(-10); return true                        // page up
        case 121: model.move(10); return true                         // page down
        case 36, 76:                                                  // return / enter
            guard let it = model.selectedItem else { return true }
            if e.modifierFlags.contains(.shift) { model.queue(it) }         // ⇧↩ adds to the paste stack
            else { hide(); model.paste(it, plain: cmd) }
            return true
        case 51 where cmd: model.deleteSelected(); return true        // ⌘⌫
        default: break
        }
        guard cmd, let ch = e.charactersIgnoringModifiers?.lowercased() else { return false }
        switch ch {
        case "c": if let it = model.selectedItem { model.copy(it); hide() }; return true
        case "p": model.togglePin(); return true
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            let i = Int(ch)! - 1
            if model.combined.indices.contains(i) { let it = model.combined[i]; hide(); model.paste(it, plain: false) }
            return true
        default: return false
        }
    }
}

@MainActor
final class PanelModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { refresh() } } }
    @Published private(set) var pins: [Item] = []
    @Published private(set) var items: [Item] = []
    @Published private(set) var related: [Item] = []
    @Published var selected = 0
    @Published var focusToken = 0

    var combined: [Item] { pins + items + related }
    var selectedItem: Item? { combined.indices.contains(selected) ? combined[selected] : nil }

    init() {
        NotificationCenter.default.addObserver(forName: .clipHistoryChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, PanelController.shared.isVisible else { return }
                let keep = self.selectedItem?.id
                self.refresh(keeping: keep)
            }
        }
    }

    func reset() { query = ""; selected = 0; refresh() }

    func refresh(keeping id: Int64? = nil) {
        pins = Array(Snippets.matching(query).prefix(query.isEmpty ? 5 : 30))
        let pinIDs = Set(pins.map(\.id))
        items = Store.shared.search(query, limit: 300).filter { !pinIDs.contains($0.id) }
        if query.count >= 3 {
            let seen = pinIDs.union(items.map(\.id))
            related = Assist.shared.semanticSearch(query).map(\.0).filter { !seen.contains($0.id) }
        } else {
            related = []
        }
        if let id, let i = combined.firstIndex(where: { $0.id == id }) { selected = i }
        else { selected = min(selected, max(0, combined.count - 1)) }
    }

    func move(_ d: Int) {
        guard !combined.isEmpty else { return }
        selected = max(0, min(combined.count - 1, selected + d))
    }

    func paste(_ item: Item, plain: Bool) { Paster.paste(item, plain: plain) }

    func copy(_ item: Item) { Paster.write(item, plain: false) }

    func queue(_ item: Item) { PasteStack.shared.push(item) }

    func togglePin() {
        guard let it = selectedItem else { return }
        Store.shared.setPinned(it.id, !it.pinned)
        refresh(keeping: it.id)
    }

    func setKeyword(_ item: Item, _ keyword: String) {
        Store.shared.setKeyword(item.id, keyword)
        refresh(keeping: item.id)
    }

    func delete(_ item: Item) {
        Store.shared.delete(item.id)
        refresh()
    }

    func revealInFinder(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting(item.filePaths.map { URL(fileURLWithPath: $0) })
    }

    func deleteSelected() {
        guard let it = selectedItem else { return }
        let idx = selected
        Store.shared.delete(it.id)
        refresh()
        selected = min(idx, max(0, combined.count - 1))
    }
}
