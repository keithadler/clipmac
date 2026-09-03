//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
import Foundation

enum PanelSuite {
    static let suite = TestSuite(name: "Panel", cases: [
        TestCase(name: "pins first, history after, selection starts at top") { t in
            let s = Store.shared
            let a = s.insert(TestKit.capture("alpha"))
            let b = s.insert(TestKit.capture("beta"))
            s.setPinned(a.id, true, keyword: "al")
            let m = PanelModel()
            m.reset()
            t.equal(m.pins.map(\.id), [a.id], "pinned section")
            t.equal(m.items.map(\.id), [b.id], "history excludes pinned rows")
            t.equal(m.combined.map(\.id), [a.id, b.id], "combined order")
            t.equal(m.selected, 0, "top selected")
            t.equal(m.selectedItem?.id, a.id, "selected item")
        },
        TestCase(name: "query filters and keeps selection when possible") { t in
            let s = Store.shared
            let inv = s.insert(TestKit.capture("invoice for woodland"))
            _ = s.insert(TestKit.capture("recipe with eggs"))
            let m = PanelModel()
            m.reset()
            m.query = "invoice"
            t.equal(m.combined.map(\.id), [inv.id], "filtered")
            m.query = "zzz"
            t.check(m.combined.isEmpty && m.selectedItem == nil, "no matches")
            m.query = ""
            t.equal(m.combined.count, 2, "cleared")
            m.selected = 1
            m.refresh(keeping: m.selectedItem?.id)
            t.equal(m.selected, 1, "selection kept by id")
        },
        TestCase(name: "movement is clamped") { t in
            for i in 0..<3 { _ = Store.shared.insert(TestKit.capture("row \(i)")) }
            let m = PanelModel()
            m.reset()
            m.move(-5); t.equal(m.selected, 0, "no negative")
            m.move(1); t.equal(m.selected, 1, "down one")
            m.move(10); t.equal(m.selected, 2, "clamped to last")
            m.move(-1); t.equal(m.selected, 1, "up one")
            let empty = PanelModel()
            empty.query = "nothing-matches-this"
            empty.move(1)
            t.equal(empty.selected, 0, "empty list stays at zero")
        },
        TestCase(name: "delete keeps a sensible selection") { t in
            for i in 0..<3 { _ = Store.shared.insert(TestKit.capture("row \(i)")) }
            let m = PanelModel()
            m.reset()
            m.selected = 2
            m.deleteSelected()
            t.equal(Store.shared.count(), 2, "row deleted")
            t.equal(m.selected, 1, "selection moves up when the last row goes")
            m.selected = 0
            m.deleteSelected()
            t.equal(m.selected, 0, "selection stays at the top")
            m.deleteSelected()
            t.check(m.combined.isEmpty && m.selected == 0, "empty after deleting everything")
            m.deleteSelected()
            t.check(true, "deleting with nothing selected is a no-op")
        },
        TestCase(name: "pin toggle, keyword, queue") { t in
            let a = Store.shared.insert(TestKit.capture("pin me"))
            let m = PanelModel()
            m.reset()
            m.togglePin()
            t.check(Store.shared.get(a.id)?.pinned == true, "pinned")
            t.equal(m.pins.map(\.id), [a.id], "moved to pins")
            m.setKeyword(a, "pm")
            t.equal(Store.shared.get(a.id)?.keyword, "pm", "keyword saved")
            t.equal(m.selectedItem?.id, a.id, "selection follows the item")
            m.togglePin()
            t.check(Store.shared.get(a.id)?.pinned == false, "unpinned")
            PasteStack.shared.clear()
            m.queue(a)
            t.equal(PasteStack.shared.count, 1, "queued")
            PasteStack.shared.clear()
        },
    ])
}
