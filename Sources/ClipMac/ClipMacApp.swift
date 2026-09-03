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
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PanelController.shared.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Hotkey.unregister()
    }
}
