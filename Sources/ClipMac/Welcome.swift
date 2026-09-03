//  First-launch welcome: the shortcut, the two paste modes, login item, and the privacy promise.
//  Shown once, and again from the menu bar on request.

import SwiftUI
import AppKit
import ServiceManagement

@MainActor
final class WelcomeController {
    static let shared = WelcomeController()
    private var window: NSWindow?

    static var shouldShow: Bool { !Prefs.defaults.bool(forKey: "welcomed") }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = String(localized: "Welcome to Clip for Mac")
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: WelcomeView { [weak self] in self?.window?.close() })
            w.center()
            window = w
        }
        Prefs.defaults.set(true, forKey: "welcomed")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct WelcomeView: View {
    let done: () -> Void
    @State private var trusted = Capabilities.accessibilityTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let tick = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clip for Mac").font(.title).bold()
                    Text("Clipboard history that refuses to capture secrets.").foregroundStyle(.secondary)
                }
            }
            step("keyboard", "Press \(Hotkey.describe()) anywhere", "The panel opens over whatever you're doing. Type to search, ↩ to paste, ⌘↩ for plain text, esc to close. Change the shortcut in Settings › General.")
            step("lock.shield", "Secrets are never captured", "Anything a password manager marks as concealed, anything copied while a password field has focus, and anything from an excluded app is skipped. These rules can't be turned off.")
            VStack(alignment: .leading, spacing: 6) {
                step("arrow.down.doc", "Paste for you, or copy only", trusted
                     ? "Accessibility is granted, so choosing an item pastes it into the app you were using."
                     : "To paste into the app you were using, Clip for Mac needs the Accessibility permission (that's how macOS lets an app press ⌘V for you). Without it, choosing an item copies it and you press ⌘V.")
                if !trusted {
                    HStack {
                        Button("Grant Accessibility…") { Capabilities.requestAccessibility(); Capabilities.openAccessibilitySettings() }
                        Button("Skip for now") { }.buttonStyle(.link).font(.caption)
                    }.padding(.leading, 34)
                }
            }
            Toggle("Open Clip for Mac at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
                .padding(.leading, 34)
            step("hand.raised", "Nothing leaves this Mac", "No account, no telemetry, no network. The optional \"ask your clipboard\" feature is off until you add your own API key, and even then you see every redacted payload before it is sent.")
            Spacer()
            HStack {
                Button("Open Settings…") { done(); SettingsOpener.open() }.buttonStyle(.link)
                Button("Help") { Help.open() }.buttonStyle(.link)
                Spacer()
                Button("Get started") { done() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520, height: 560)
        .onReceive(tick) { _ in trusted = Capabilities.accessibilityTrusted }
    }

    private func step(_ symbol: String, _ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).frame(width: 22).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
