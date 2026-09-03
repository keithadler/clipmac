//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  App entry point. Accessory app (no Dock icon): a menu bar extra, the floating panel, Settings,
//  and the Ask window. The init hook hands `clipmac <command>` invocations to CLI.swift, which
//  exits before any UI exists.

import SwiftUI
import AppKit

@main
struct ClipMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("menuBarIcon", store: Prefs.defaults) private var menuBarIcon = true

    init() {
        CLI.runIfRequested()   // `clipmac <command>` runs here and exits; otherwise the GUI starts
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $menuBarIcon) {
            MenuBarContent()
        } label: {
            MenuBarLabel()
        }

        Settings { SettingsView() }
            .commands {
                CommandGroup(replacing: .appInfo) { Button("About Clip for Mac") { Updates.showAbout() } }
                CommandGroup(after: .appInfo) { Button("Check for Updates…") { Updates.checkAndPresent() } }
                CommandGroup(replacing: .help) {
                    Button("Clip for Mac Help") { Help.open() }
                    Button("Welcome Tour") { WelcomeController.shared.show() }
                    Button("Report a Problem…") { NSWorkspace.shared.open(Help.issues) }
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var retentionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Monitor.shared.start()
        Hotkey.handlers[.panel] = { PanelController.shared.toggle() }
        Hotkey.handlers[.plainPaste] = { Paster.pasteCurrentAsPlain() }
        Hotkey.handlers[.pasteNext] = { PasteStack.shared.pasteNext() }
        Hotkey.registerAll()
        DispatchQueue.global(qos: .utility).async {
            Store.shared.enforceRetention()
            Assist.shared.indexPending()
        }
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            DispatchQueue.global(qos: .utility).async { Store.shared.enforceRetention() }
        }
        if WelcomeController.shouldShow { WelcomeController.shared.show() }
        Updates.scheduleBackgroundChecks()
        PinSync.start()
    }

    /// clipmac://open, clipmac://search?q=…, clipmac://paste/<id or position>[?plain=1], clipmac://copy/<id>,
    /// clipmac://pause?minutes=10, clipmac://resume, clipmac://settings. Lets Shortcuts and scripts drive the app.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { URLCommands.handle(url) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PanelController.shared.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Hotkey.unregisterAll()
    }
}

enum URLCommands {
    enum Command: Equatable {
        case open, close, welcome, settings, resume
        case search(String)
        case paste(ref: String, plain: Bool)
        case copy(ref: String, plain: Bool)
        case pause(minutes: Double)
        case unknown
    }

    /// clipmac://open, clipmac://search?q=…, clipmac://paste/<#id or position>[?plain=1], clipmac://copy/<ref>,
    /// clipmac://pause?minutes=10, clipmac://resume, clipmac://settings, clipmac://welcome, clipmac://close.
    /// A bare number in paste/copy is an id; add ?by=position for a position.
    static func parse(_ url: URL) -> Command? {
        guard url.scheme == "clipmac" else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary((comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let path = url.pathComponents.filter { $0 != "/" }
        let plain = query["plain"] == "1"
        func ref() -> String? {
            guard let r = path.first else { return nil }
            if r.hasPrefix("#") || query["by"] == "position" || Int64(r) == nil { return r }
            return "#" + r
        }
        switch url.host {
        case "open": return .open
        case "close": return .close
        case "welcome": return .welcome
        case "settings": return .settings
        case "resume": return .resume
        case "search": return .search(query["q"] ?? "")
        case "paste": return ref().map { .paste(ref: $0, plain: plain) } ?? .unknown
        case "copy": return ref().map { .copy(ref: $0, plain: plain) } ?? .unknown
        case "pause": return .pause(minutes: Double(query["minutes"] ?? "") ?? 10)
        default: return .unknown
        }
    }

    @MainActor
    static func handle(_ url: URL) {
        guard let cmd = parse(url) else { return }
        switch cmd {
        case .open: PanelController.shared.show()
        case .close: PanelController.shared.hide()
        case .welcome: WelcomeController.shared.show()
        case .settings: SettingsOpener.open()
        case .resume: Monitor.shared.resume()
        case .search(let q): PanelController.shared.show(); PanelController.shared.model.query = q
        case .paste(let ref, let plain):
            guard let item = CLI.resolve(ref) else { NSSound.beep(); return }
            Paster.paste(item, plain: plain)
        case .copy(let ref, let plain):
            guard let item = CLI.resolve(ref) else { NSSound.beep(); return }
            Paster.write(item, plain: plain)
        case .pause(let minutes): Monitor.shared.pause(for: minutes * 60)
        case .unknown: NSSound.beep()
        }
    }
}

/// SwiftUI's openSettings action only exists inside a view. The menu bar label is the one view that
/// is always alive, so it hands the action to this holder for the URL scheme and the welcome window.
@MainActor
enum SettingsOpener {
    static var action: OpenSettingsAction?
    static func open() {
        NSApp.activate()
        if let action { action() } else { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
    }
}

struct MenuBarLabel: View {
    @ObservedObject private var monitor = Monitor.shared
    @ObservedObject private var updates = UpdateState.shared
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Image(systemName: updates.available != nil ? "doc.on.clipboard.fill" : (monitor.paused ? "pause.circle" : (monitor.secureInput ? "lock.doc" : "doc.on.clipboard")))
            .onAppear { SettingsOpener.action = openSettings }
            .accessibilityLabel(Text("Clip for Mac"))
    }
}
