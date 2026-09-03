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
    @ObservedObject private var monitor = Monitor.shared
    @AppStorage("menuBarIcon", store: Prefs.defaults) private var menuBarIcon = true

    init() {
        CLI.runIfRequested()   // `clipmac <command>` runs here and exits; otherwise the GUI starts
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $menuBarIcon) {
            MenuBarContent()
        } label: {
            Image(systemName: monitor.paused ? "pause.circle" : (monitor.secureInput ? "lock.doc" : "doc.on.clipboard"))
        }

        Settings { SettingsView() }

        Window("Ask Your Clipboard", id: "assist") { AssistView() }
            .defaultSize(width: 620, height: 520)
            .commands {
                CommandGroup(replacing: .appInfo) { Button("About Clip for Mac") { Updates.showAbout() } }
                CommandGroup(after: .appInfo) { Button("Check for Updates…") { Updates.checkAndPresent() } }
                CommandGroup(replacing: .help) {
                    Button("Clip for Mac Help") { NSWorkspace.shared.open(URL(string: "https://github.com/keithadler/clipmac#readme")!) }
                    Button("Welcome Tour") { WelcomeController.shared.show() }
                    Button("Report a Problem…") { NSWorkspace.shared.open(URL(string: "https://github.com/keithadler/clipmac/issues")!) }
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var retentionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Monitor.shared.start()
        Hotkey.onPress = { PanelController.shared.toggle() }
        Hotkey.register()
        DispatchQueue.global(qos: .utility).async {
            Store.shared.enforceRetention()
            Assist.shared.indexPending()
        }
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            DispatchQueue.global(qos: .utility).async { Store.shared.enforceRetention() }
        }
        if WelcomeController.shouldShow { WelcomeController.shared.show() }
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
        Hotkey.unregister()
    }
}

enum URLCommands {
    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme == "clipmac" else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let path = url.pathComponents.filter { $0 != "/" }
        switch url.host {
        case "open":
            PanelController.shared.show()
        case "close":
            PanelController.shared.hide()
        case "welcome":
            WelcomeController.shared.show()
        case "search":
            PanelController.shared.show()
            PanelController.shared.model.query = query["q"] ?? ""
        case "paste", "copy":
            guard let ref = path.first, let item = CLI.resolve(ref.hasPrefix("#") ? ref : (Int64(ref) != nil && url.host == "paste" && query["by"] != "position" ? "#" + ref : ref)) else { NSSound.beep(); return }
            if url.host == "copy" { Paster.write(item, plain: query["plain"] == "1") }
            else { Paster.paste(item, plain: query["plain"] == "1") }
        case "pause":
            Monitor.shared.pause(for: (Double(query["minutes"] ?? "") ?? 10) * 60)
        case "resume":
            Monitor.shared.resume()
        case "settings":
            NSApp.activate()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        default:
            NSSound.beep()
        }
    }
}
