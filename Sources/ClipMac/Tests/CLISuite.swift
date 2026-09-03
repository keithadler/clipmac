//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
import Foundation

enum CLISuite {
    static let suite = TestSuite(name: "CLI", cases: [
        TestCase(name: "durations") { t in
            t.equal(CLI.parseDuration(nil), 600, "default ten minutes")
            t.equal(CLI.parseDuration("30m"), 1800, "minutes")
            t.equal(CLI.parseDuration("2h"), 7200, "hours")
            t.equal(CLI.parseDuration("45s"), 45, "seconds")
            t.equal(CLI.parseDuration("1d"), 86400, "days")
            t.equal(CLI.parseDuration("15"), 900, "bare number is minutes")
        },
        TestCase(name: "item references: positions and ids") { t in
            let a = Store.shared.insert(TestKit.capture("older"))
            let b = Store.shared.insert(TestKit.capture("newer"))
            t.equal(CLI.resolve("1")?.id, b.id, "position 1 is newest")
            t.equal(CLI.resolve("2")?.id, a.id, "position 2")
            t.equal(CLI.resolve("#\(a.id)")?.id, a.id, "id form")
            t.check(CLI.resolve("#999") == nil && CLI.resolve("9") == nil && CLI.resolve("x") == nil && CLI.resolve(nil) == nil, "misses are nil")
        },
        TestCase(name: "exit codes") { t in
            t.equal(TestKit.silenced { CLI.run("help", []) }, 0, "help")
            t.equal(TestKit.silenced { CLI.run("version", []) }, 0, "version")
            t.equal(TestKit.silenced { CLI.run("bogus", []) }, 64, "unknown command")
            t.equal(TestKit.silenced { CLI.run("get", ["7"]) }, 2, "missing item")
            t.equal(TestKit.silenced { CLI.run("search", []) }, 64, "search without query")
            t.equal(TestKit.silenced { CLI.run("search", ["nothing-here"]) }, 1, "no results is a warning")
            t.equal(TestKit.silenced { CLI.run("wipe", []) }, 64, "wipe needs --yes")
            t.equal(TestKit.silenced { CLI.run("snip", ["nope"]) }, 2, "unknown snippet")
            t.equal(TestKit.silenced { CLI.run("assist", []) }, 64, "assist needs a question")
        },
        TestCase(name: "pin, snip, forget, wipe change the store") { t in
            let s = Store.shared
            let a = s.insert(TestKit.capture("signature text", app: "com.other"))
            _ = s.insert(TestKit.capture("something else"))
            t.equal(TestKit.silenced { CLI.run("pin", ["#\(a.id)", "--keyword", "sig"]) }, 0, "pin exit")
            t.equal(s.snippet(keyword: "sig")?.id, a.id, "pinned with keyword")
            t.equal(TestKit.silenced { CLI.run("snip", ["sig"]) }, 0, "snip finds it")
            t.equal(TestKit.silenced { CLI.run("unpin", ["#\(a.id)"]) }, 0, "unpin")
            t.check(s.pinned().isEmpty, "unpinned")
            t.equal(TestKit.silenced { CLI.run("forget", ["--app", "com.other"]) }, 0, "forget by app")
            t.equal(s.count(), 1, "one left")
            t.equal(TestKit.silenced { CLI.run("wipe", ["--yes"]) }, 0, "wipe")
            t.equal(s.count(), 0, "empty")
        },
        TestCase(name: "pause and resume write shared defaults") { t in
            t.equal(TestKit.silenced { CLI.run("pause", ["5m"]) }, 0, "pause exit")
            t.check(Prefs.isPaused, "paused")
            let until = Prefs.pausedUntil?.timeIntervalSinceNow ?? 0
            t.check(until > 290 && until <= 300, "five minutes from now")
            t.equal(TestKit.silenced { CLI.run("resume", []) }, 0, "resume exit")
            t.check(!Prefs.isPaused, "resumed")
        },
        TestCase(name: "sensitive items can be forgotten together") { t in
            let s = Store.shared
            _ = s.insert(TestKit.capture("token: sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
            _ = s.insert(TestKit.capture("harmless"))
            t.equal(TestKit.silenced { CLI.run("forget", ["--sensitive"]) }, 0, "exit")
            t.equal(s.all().map(\.plain), ["harmless"], "only the secret went")
        },
        TestCase(name: "defaults have sane values in a fresh suite") { t in
            t.equal(Prefs.retentionDays, 30, "days")
            t.equal(Prefs.retentionItems, 2000, "items")
            t.equal(Prefs.retentionBytes, 1 << 30, "bytes")
            t.equal(Prefs.sizeCapBytes, 50 << 20, "size cap")
            t.check(Prefs.autoPaste && Prefs.restorePrevious && Prefs.semanticSearch, "paste and semantic on by default")
            t.check(!Prefs.cloudAssist && !Prefs.onDeviceModel && !Prefs.sessionOnly, "cloud, on-device model, session-only off by default")
            t.equal(Prefs.cloudModel, "claude-opus-5", "default cloud model")
        },
    ])
}
