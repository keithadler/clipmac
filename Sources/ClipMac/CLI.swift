//  The command-line face. The same binary that runs the app answers to `clipmac <command>` through
//  the symlink build-app.sh --install creates. Commands read the same history.db the app writes
//  (WAL mode handles the two processes) and exit before any UI exists.
//
//  Exit codes: 0 fine, 1 warning, 2 problem, 64 usage error.

import Foundation
import AppKit
import ServiceManagement

enum CLI {
    static let usage = """
    clipmac — clipboard history that refuses to capture secrets (command-line face)

    USAGE
      clipmac list [--limit N] [--pinned] [--json]
      clipmac get <item>                 print an item to stdout (text, or the image/file bytes)
      clipmac copy <item> [--plain]      put an item back on the pasteboard
      clipmac search <query> [--limit N] [--semantic] [--json]
      clipmac pin <item> [--keyword K]   pin (and optionally name) an item
      clipmac unpin <item>
      clipmac snip <keyword>             print a pinned snippet
      clipmac snippets [--json]          list pins; --export <file.plist> writes a Text Replacement list
      clipmac pause [10m|1h|…]           pause capture (default 10m); clipmac resume
      clipmac forget <item> | --app <bundle-id> | --sensitive
      clipmac wipe --yes                 delete everything, no confirmation dance in scripts
      clipmac assist "<question>" [--local | --cloud] [--last N | --today] [--yes] [--json]
      clipmac assist log [--json]
      clipmac status [--json]
      clipmac selftest [--filter S] [--list] [--json]   run the built-in test suites (no Xcode needed)
      clipmac screenshots <dir>         render every window with demo data (dark and light) for the README
      clipmac help | version

    ITEMS
      A position (1 = newest) or a stable id written as #12. Positions shift on every copy, so
      scripts should use ids from `clipmac list --json`.

    ASSIST
      --local uses Apple's on-device model (macOS 26+, nothing leaves the Mac). --cloud uses the
      key stored in Settings › Assist and prints the redacted payload first; it is only sent after
      you answer y, or with --yes. Every cloud request is logged: clipmac assist log.
    """

    /// Returns only when the process should continue into the GUI.
    static func runIfRequested() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first, !cmd.hasPrefix("-psn") else { return }
        exit(run(cmd, Array(args.dropFirst())))
    }

    private static func flag(_ name: String, _ args: [String]) -> Bool { args.contains(name) }
    private static func value(_ name: String, _ args: [String]) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    private static func positional(_ args: [String]) -> [String] {
        var out: [String] = []; var skip = false
        let valued: Set<String> = ["--limit", "--keyword", "--app", "--export", "--last", "--filter"]
        for a in args {
            if skip { skip = false; continue }
            if valued.contains(a) { skip = true; continue }
            if a.hasPrefix("--") { continue }
            out.append(a)
        }
        return out
    }

    static var loginItemState: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requires approval in System Settings › General › Login Items"
        case .notRegistered: return "off"
        case .notFound: return "not found (app not in /Applications?)"
        @unknown default: return "unknown"
        }
    }

    static func resolve(_ ref: String?) -> Item? {
        guard let ref else { return nil }
        if ref.hasPrefix("#"), let id = Int64(ref.dropFirst()) { return Store.shared.get(id) }
        if let pos = Int(ref) { return Store.shared.item(atPosition: pos) }
        return nil
    }

    static func parseDuration(_ s: String?) -> TimeInterval {
        guard let s, let n = Double(s.filter { $0.isNumber || $0 == "." }) else { return 600 }
        if s.hasSuffix("h") { return n * 3600 }
        if s.hasSuffix("s") { return n }
        if s.hasSuffix("d") { return n * 86400 }
        return n * 60
    }

    static func run(_ cmd: String, _ args: [String]) -> Int32 {
        let json = flag("--json", args)
        let store = Store.shared
        let pos = positional(args)

        switch cmd {
        case "help", "--help", "-h": print(usage); return 0
        case "version", "--version": print("clipmac \(Capabilities.appVersion)"); return 0

        case "list":
            let limit = Int(value("--limit", args) ?? "") ?? 20
            let items = flag("--pinned", args) ? store.pinned() : store.recent(limit: limit)
            if json { print(Dump.json(items.enumerated().map { Dump.dict($1, position: flag("--pinned", args) ? nil : $0 + 1) })) }
            else { print(Dump.table(items, positions: !flag("--pinned", args)), terminator: "") }
            return 0

        case "get":
            guard let item = resolve(pos.first) else { fputs("no such item\n", stderr); return 2 }
            if json { print(Dump.json(Dump.dict(item))); return 0 }
            if item.kind == .image, let data = store.blob(item.blobHash) { FileHandle.standardOutput.write(data); return 0 }
            print(item.plain, terminator: item.plain.hasSuffix("\n") ? "" : "\n")
            return 0

        case "copy":
            guard let item = resolve(pos.first) else { fputs("no such item\n", stderr); return 2 }
            MainActor.assumeIsolated { Paster.write(item, plain: flag("--plain", args)) }
            if json { print(Dump.json(["copied": item.id])) } else { print("copied #\(item.id)") }
            return 0

        case "search":
            let q = pos.joined(separator: " ")
            guard !q.isEmpty else { fputs("search needs a query\n", stderr); return 64 }
            let limit = Int(value("--limit", args) ?? "") ?? 20
            var items = Array(store.search(q, limit: limit).prefix(limit))
            if flag("--semantic", args) {
                Assist.shared.indexPending()
                let ids = Set(items.map(\.id))
                items += Assist.shared.semanticSearch(q, limit: limit).map(\.0).filter { !ids.contains($0.id) }
            }
            if json { print(Dump.json(items.map { Dump.dict($0) })) } else { print(Dump.table(items, positions: false), terminator: "") }
            return items.isEmpty ? 1 : 0

        case "pin":
            guard let item = resolve(pos.first) else { fputs("no such item\n", stderr); return 2 }
            store.setPinned(item.id, true, keyword: value("--keyword", args))
            print(json ? Dump.json(["pinned": item.id]) : "pinned #\(item.id)" + (value("--keyword", args).map { " as \($0)" } ?? ""))
            return 0

        case "unpin":
            guard let item = resolve(pos.first) else { fputs("no such item\n", stderr); return 2 }
            store.setPinned(item.id, false)
            print(json ? Dump.json(["unpinned": item.id]) : "unpinned #\(item.id)")
            return 0

        case "snip":
            guard let k = pos.first else { fputs("snip needs a keyword\n", stderr); return 64 }
            guard let item = Snippets.lookup(k) else { fputs("no snippet named \(k)\n", stderr); return 2 }
            if json { print(Dump.json(Dump.dict(item))) } else { print(item.plain, terminator: item.plain.hasSuffix("\n") ? "" : "\n") }
            return 0

        case "snippets":
            if let path = value("--export", args) {
                do {
                    let n = try Snippets.exportTextReplacements(to: URL(fileURLWithPath: path))
                    print(json ? Dump.json(["exported": n, "path": path]) : "wrote \(n) text replacements to \(path)")
                    return 0
                } catch { fputs("export failed: \(error.localizedDescription)\n", stderr); return 2 }
            }
            let items = store.pinned()
            if json { print(Dump.json(items.map { Dump.dict($0) })) } else { print(Dump.table(items, positions: false), terminator: "") }
            return 0

        case "pause":
            let secs = parseDuration(pos.first)
            Prefs.pausedUntil = Date().addingTimeInterval(secs)
            print(json ? Dump.json(["paused_until": Dump.iso.string(from: Prefs.pausedUntil!)]) : "capture paused for \(Int(secs / 60)) min")
            return 0

        case "resume":
            Prefs.pausedUntil = nil
            print(json ? Dump.json(["paused": false]) : "capture resumed")
            return 0

        case "forget":
            if let app = value("--app", args) {
                let n = store.delete(bundleID: app)
                print(json ? Dump.json(["forgot": n, "app": app]) : "forgot \(n) items from \(app)")
                return 0
            }
            if flag("--sensitive", args) {
                let doomed = store.all().filter(\.looksSensitive)
                doomed.forEach { store.delete($0.id) }
                print(json ? Dump.json(["forgot": doomed.count]) : "forgot \(doomed.count) items that looked like secrets")
                return 0
            }
            guard let item = resolve(pos.first) else { fputs("no such item\n", stderr); return 2 }
            store.delete(item.id)
            print(json ? Dump.json(["forgot": item.id]) : "forgot #\(item.id)")
            return 0

        case "wipe":
            guard flag("--yes", args) else { fputs("wipe deletes everything, including pins. Add --yes.\n", stderr); return 64 }
            store.wipe()
            print(json ? Dump.json(["wiped": true]) : "history wiped")
            return 0

        case "status":
            let fv = Capabilities.fileVaultOn
            let info: [String: Any] = [
                "items": store.count(), "bytes": store.totalBytes(), "pinned": store.pinned().count,
                "paused": Prefs.isPaused, "session_only": Prefs.sessionOnly,
                "accessibility": Capabilities.accessibilityTrusted, "secure_input": Capabilities.secureInputActive,
                "filevault": fv as Any, "semantic_search": Prefs.semanticSearch && Capabilities.sentenceEmbeddingAvailable,
                "on_device_model": Capabilities.onDeviceModelAvailable, "cloud_assist": Prefs.cloudAssist,
                "hotkey": Hotkey.describe(), "database": Store.dbURL.path, "excluded_apps": Prefs.excludedBundleIDs,
                "login_item": loginItemState,
            ]
            if json { print(Dump.json(info)); return fv == false ? 1 : 0 }
            print("""
            items:          \(store.count()) (\(ByteCountFormatter.string(fromByteCount: Int64(store.totalBytes()), countStyle: .file))), \(store.pinned().count) pinned
            capture:        \(Prefs.isPaused ? "paused" : "on")\(Capabilities.secureInputActive ? " (secure input active, nothing captured right now)" : "")
            storage:        \(Prefs.sessionOnly ? "session only" : Store.dbURL.path)
            FileVault:      \(fv.map { $0 ? "on" : "OFF — history.db is not encrypted by Clip for Mac; turn on FileVault" } ?? "unknown")
            auto-paste:     \(Capabilities.accessibilityTrusted ? "on (Accessibility granted)" : "copy-only (no Accessibility permission)")
            hotkey:         \(Hotkey.describe())
            semantic:       \(Prefs.semanticSearch && Capabilities.sentenceEmbeddingAvailable ? "on" : "off")
            on-device AI:   \(Capabilities.onDeviceModelAvailable ? "available" : "not available")
            cloud AI:       \(Prefs.cloudAssist ? "on (\(Prefs.cloudProvider), \(Prefs.cloudModel))" : "off")
            excluded apps:  \(Prefs.excludedBundleIDs.count)
            login item:     \(loginItemState)
            """)
            return fv == false ? 1 : 0

        case "assist":
            return assist(args, json: json)

        case "screenshots":
            guard let dir = pos.first else { fputs("screenshots needs a directory\n", stderr); return 64 }
            do {
                let files = try MainActor.assumeIsolated { try Screenshots.render(to: URL(fileURLWithPath: dir)) }
                print(json ? Dump.json(["written": files.map(\.path)]) : files.map { "wrote \($0.path)" }.joined(separator: "\n"))
                return 0
            } catch { fputs("\(error.localizedDescription)\n", stderr); return 2 }

        case "selftest":
            if flag("--list", args) { TestKit.list(); return 0 }
            let results = MainActor.assumeIsolated { TestKit.run(filter: value("--filter", args)) }
            return TestKit.report(results, json: json)

        default:
            fputs("unknown command: \(cmd)\n\n\(usage)\n", stderr)
            return 64
        }
    }

    private static func assist(_ args: [String], json: Bool) -> Int32 {
        let pos = positional(args)
        if pos.first == "log" {
            let log = Store.shared.assistLog()
            if json { print(Dump.json(log.map { Dump.dict($0) })) } else { print(Dump.logTable(log), terminator: "") }
            return 0
        }
        let question = pos.joined(separator: " ")
        guard !question.isEmpty else { fputs("assist needs a question\n", stderr); return 64 }
        let items: [Item]
        if flag("--today", args) { items = Store.shared.items(since: Calendar.current.startOfDay(for: Date())) }
        else { items = Store.shared.recent(limit: Int(value("--last", args) ?? "") ?? 25) }
        guard !items.isEmpty else { fputs("nothing in history to ask about\n", stderr); return 1 }

        let cloud = flag("--cloud", args)
        if !cloud {
            guard Capabilities.onDeviceModelAvailable else {
                fputs("\(Capabilities.onDeviceModelNote)\nUse --cloud to ask with your own API key instead.\n", stderr); return 2
            }
            let sem = DispatchSemaphore(value: 0)
            var result: Result<String, Error> = .failure(AssistError.cancelled)
            Task { do { result = .success(try await Assist.shared.askOnDevice(question, items: items)) } catch { result = .failure(error) }; sem.signal() }
            sem.wait()
            switch result {
            case .success(let text): print(json ? Dump.json(["answer": text, "provider": "apple-on-device", "items": items.count]) : text); return 0
            case .failure(let e): fputs("\(e.localizedDescription)\n", stderr); return 2
            }
        }

        guard Prefs.cloudAssist else { fputs("Cloud assist is off. Turn it on in Settings › Assist and add a key.\n", stderr); return 2 }
        let prepared = Assist.shared.prepareCloud(question, items: items)
        if !flag("--yes", args) {
            print("This is exactly what would be sent to \(Prefs.cloudProvider) (\(Prefs.cloudModel)), \(prepared.chars) characters, \(prepared.itemCount) items" +
                  (prepared.labels.isEmpty ? ":" : ", with \(prepared.labels.joined(separator: ", ")) redacted:"))
            print("----\n\(prepared.maskedContext)\nQuestion: \(question)\n----")
            guard isatty(STDIN_FILENO) != 0 else { fputs("Not a terminal; add --yes to send.\n", stderr); return 2 }
            print("Send it? [y/N] ", terminator: "")
            guard let line = readLine(), line.lowercased().hasPrefix("y") else { print("not sent"); return 1 }
        }
        let sem = DispatchSemaphore(value: 0)
        var result: Result<Assist.CloudReply, Error> = .failure(AssistError.cancelled)
        Task { do { result = .success(try await Assist.shared.sendCloud(prepared)) } catch { result = .failure(error) }; sem.signal() }
        sem.wait()
        switch result {
        case .success(let r):
            if json { print(Dump.json(["answer": r.text, "provider": Prefs.cloudProvider, "model": r.model, "items": prepared.itemCount,
                                       "input_tokens": r.inputTokens, "output_tokens": r.outputTokens, "redacted": prepared.labels])) }
            else { print(r.text); print("\n(\(r.model): \(r.inputTokens) in, \(r.outputTokens) out — logged)") }
            return 0
        case .failure(let e): fputs("\(e.localizedDescription)\n", stderr); return 2
        }
    }
}
