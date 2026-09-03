//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  The paste stack: queue several items from the panel (⇧↩), then paste them one after another
//  with the "paste next" hotkey without reopening the panel. Lives in memory only.

import Foundation
import AppKit

@MainActor
final class PasteStack: ObservableObject {
    static let shared = PasteStack()
    @Published private(set) var items: [Item] = []

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    func push(_ item: Item) {
        items.append(item)
    }

    func clear() { items.removeAll() }

    /// Pastes the oldest queued item and drops it. Beeps when the stack is empty.
    func pop() -> Item? { items.isEmpty ? nil : items.removeFirst() }

    func pasteNext() {
        guard let item = pop() else { NSSound.beep(); return }
        Paster.paste(item, plain: false)
    }
}
