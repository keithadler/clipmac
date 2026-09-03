//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
import Foundation
import AppKit

enum MonitorSuite {
    @MainActor
    static func fresh() -> (Monitor, NSPasteboard) {
        let pb = CaptureSuite.pasteboard()
        let m = Monitor(pasteboard: pb)
        m.secureInputProbe = { false }
        m.frontmostProbe = { (nil, nil, nil) }
        return (m, pb)
    }

    /// A real copy always clears the pasteboard first; that is what bumps changeCount.
    static func copy(_ pb: NSPasteboard, _ s: String) { pb.clearContents(); pb.setString(s, forType: .string) }

    static let suite = TestSuite(name: "Monitor", cases: [
        TestCase(name: "a change is captured once") { t in
            let (m, pb) = fresh()
            m.poll()
            t.equal(Store.shared.count(), 0, "nothing before a change")
            copy(pb, "first copy")
            m.poll()
            t.equal(Store.shared.count(), 1, "captured")
            t.equal(m.lastCaptured?.plain, "first copy", "lastCaptured")
            t.check(m.lastSkip == nil, "no skip reason")
            m.poll(); m.poll()
            t.equal(Store.shared.count(), 1, "same changeCount is not re-captured")
        },
        TestCase(name: "own writes are ignored") { t in
            let (m, pb) = fresh()
            m.expectOwnChange()
            copy(pb, "we wrote this")
            m.poll()
            t.equal(Store.shared.count(), 0, "own change skipped")
            copy(pb, "user wrote this")
            m.poll()
            t.equal(Store.shared.count(), 1, "later user change captured")
        },
        TestCase(name: "refusals set a reason and store nothing") { t in
            let (m, pb) = fresh()
            let item = NSPasteboardItem()
            item.setString("hunter2", forType: .string)
            item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            pb.clearContents(); pb.writeObjects([item])
            m.poll()
            t.equal(Store.shared.count(), 0, "concealed not stored")
            t.equal(m.lastSkip, Monitor.Refusal.concealed.description, "reason: concealed")

            m.secureInputProbe = { true }
            copy(pb, "typed into a password box")
            m.poll()
            t.equal(Store.shared.count(), 0, "secure input not stored")
            t.check(m.secureInput, "secure input flag published")
            t.equal(m.lastSkip, Monitor.Refusal.secureInput.description, "reason: secure input")
            m.secureInputProbe = { false }

            m.frontmostProbe = { ("com.1password.1password", "1Password", nil) }
            copy(pb, "from an excluded app")
            m.poll()
            t.equal(Store.shared.count(), 0, "excluded app not stored")
            t.equal(m.lastSkip, Monitor.Refusal.excludedApp("").description, "reason: excluded app")
            m.frontmostProbe = { ("com.apple.Safari", "Safari", "GitHub issue #42") }
            copy(pb, "from an ordinary app")
            m.poll()
            t.equal(Store.shared.count(), 1, "ordinary app stored")
            t.equal(m.lastCaptured?.sourceName, "Safari", "source app recorded")
            t.equal(m.lastCaptured?.sourceTitle, "GitHub issue #42", "window title recorded")
            Store.shared.wipe()

            Prefs.defaults.set(1, forKey: "sizeCapMB")
            copy(pb, String(repeating: "x", count: 1_100_000))
            m.poll()
            t.equal(Store.shared.count(), 0, "over the cap not stored")
            t.equal(m.lastSkip, Monitor.Refusal.tooLarge.description, "reason: too large")
        },
        TestCase(name: "pause and resume") { t in
            let (m, pb) = fresh()
            m.pause(for: 60)
            t.check(m.paused && Prefs.isPaused, "paused state shared through defaults")
            copy(pb, "while paused")
            m.poll()
            t.equal(Store.shared.count(), 0, "not captured while paused")
            t.equal(m.lastSkip, Monitor.Refusal.paused.description, "reason: paused")
            m.resume()
            t.check(!m.paused && !Prefs.isPaused, "resumed")
            copy(pb, "after resume")
            m.poll()
            t.equal(Store.shared.count(), 1, "captured after resume")
        },
        TestCase(name: "history change notification fires") { t in
            let (m, pb) = fresh()
            nonisolated(unsafe) var fired = 0
            let token = NotificationCenter.default.addObserver(forName: .clipHistoryChanged, object: nil, queue: nil) { _ in fired += 1 }
            defer { NotificationCenter.default.removeObserver(token) }
            copy(pb, "notify me")
            m.poll()
            t.equal(fired, 1, "one notification per capture")
        },
    ])
}
