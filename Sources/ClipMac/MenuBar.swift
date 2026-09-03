//  Menu bar extra content and the "ask your clipboard" window.

import SwiftUI
import AppKit

struct MenuBarContent: View {
    @ObservedObject private var monitor = Monitor.shared
    @ObservedObject private var stack = PasteStack.shared
    var body: some View {
        Button { PanelController.shared.toggle() } label: { Text("Open Clipboard    \(Hotkey.describe())") }
        if Hotkey.conflict { Text("Shortcut taken by another app. Change it in Settings.") }
        Button { Paster.pasteCurrentAsPlain() } label: { Text("Paste as Plain Text    \(Hotkey.describe(.plainPaste))") }
        if !stack.isEmpty {
            Button { stack.pasteNext() } label: { Text(String(format: String(localized: "Paste Next of %lld    %@"), stack.count, Hotkey.describe(.pasteNext))) }
            Button("Clear Paste Stack") { stack.clear() }
        }
        Divider()
        // Flat, not a submenu: nested menus in a menu bar extra are hard to hover into.
        if monitor.paused {
            Button("Resume Capture") { monitor.resume() }
            if let u = monitor.pausedUntil, u.timeIntervalSinceNow < 86400 { Text("Paused until \(u.formatted(date: .omitted, time: .shortened))") }
        } else {
            Button("Pause Capture for 10 Minutes") { monitor.pause(for: 600) }
            Button("Pause Capture for 1 Hour") { monitor.pause(for: 3600) }
            Button("Pause Capture Until Resumed") { monitor.pause(for: 365 * 86400) }
        }
        if monitor.secureInput { Text("Password field active: not capturing") }
        Divider()
        Button("Ask Your Clipboard…") { AssistWindowController.shared.show() }
            .disabled(!((Prefs.onDeviceModel && Capabilities.onDeviceModelAvailable) || Prefs.cloudAssist))
        Button("Export Pins as Text Replacements…") { Snippets.exportWithDialog() }
        Divider()
        Button("Clip for Mac Help") { Help.open() }.keyboardShortcut("?")
        Button("Keyboard Shortcuts") { Help.open(anchor: "keys") }
        Button("Welcome Tour") { WelcomeController.shared.show() }
        Button("Check for Updates…") { Updates.checkAndPresent() }
        Button("About Clip for Mac") { Updates.showAbout() }
        Divider()
        Button("Settings…") { SettingsOpener.open() }.keyboardShortcut(",")
        Button("Quit Clip for Mac") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

// MARK: - Ask your clipboard

struct AssistView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case last10, last25, last50, today
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self { case .last10: return "Last 10 items"; case .last25: return "Last 25 items"; case .last50: return "Last 50 items"; case .today: return "Everything today" }
        }
        func items() -> [Item] {
            switch self {
            case .last10: return Store.shared.recent(limit: 10)
            case .last25: return Store.shared.recent(limit: 25)
            case .last50: return Store.shared.recent(limit: 50)
            case .today: return Store.shared.items(since: Calendar.current.startOfDay(for: Date()))
            }
        }
    }
    enum Where: String, CaseIterable, Identifiable { case onDevice, cloud; var id: String { rawValue } }

    @State private var scope: Scope = .last25
    @State private var target: Where = Capabilities.onDeviceModelAvailable && Prefs.onDeviceModel ? .onDevice : .cloud
    @State private var question = ""
    @State private var prepared: Assist.Prepared?
    @State private var answer = ""
    @State private var error = ""
    @State private var busy = false

    private var cloudOK: Bool { Prefs.cloudAssist }
    private var deviceOK: Bool { Prefs.onDeviceModel && Capabilities.onDeviceModelAvailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Items", selection: $scope) { ForEach(Scope.allCases) { Text($0.label).tag($0) } }
                Picker("Using", selection: $target) {
                    if deviceOK { Text("Apple's on-device model").tag(Where.onDevice) }
                    if cloudOK { Text("\(Assist.Provider(rawValue: Prefs.cloudProvider)?.label ?? "") · \(Prefs.cloudModel)").tag(Where.cloud) }
                }
            }
            if !deviceOK && !cloudOK { Text("Turn on a model in Settings › Assist first.").foregroundStyle(.secondary) }
            TextField("What did I copy about the invoice? Turn the last five items into a list…", text: $question, axis: .vertical)
                .lineLimit(2...4).textFieldStyle(.roundedBorder)
                .onSubmit { target == .cloud ? preview() : ask() }
            HStack {
                if target == .cloud {
                    Button("Show what would be sent") { preview() }.disabled(question.isEmpty || busy)
                    Button("Send") { ask() }.keyboardShortcut(.defaultAction).disabled(prepared == nil || busy)
                } else {
                    Button("Ask") { ask() }.keyboardShortcut(.defaultAction).disabled(question.isEmpty || busy || !deviceOK)
                    Text("Nothing leaves this Mac.").font(.caption).foregroundStyle(.secondary)
                }
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Request log") { NSWorkspace.shared.activateFileViewerSelecting([Store.dbURL]) }.font(.caption).buttonStyle(.link)
            }
            if let p = prepared, target == .cloud {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: String(localized: "This exact text will go to %@: %lld items, %lld characters%@"), Prefs.cloudProvider, p.itemCount, p.chars,
                                    p.labels.isEmpty ? "." : ". " + String(format: String(localized: "Masked: %@."), p.labels.joined(separator: ", "))))
                            .font(.caption).foregroundStyle(.secondary)
                        ScrollView { Text(p.maskedContext + "\nQuestion: " + p.prompt).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(minHeight: 80, maxHeight: 160)
                    }
                } label: { Label("Redacted payload", systemImage: "eye") }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.callout) }
            ScrollView { Text(answer).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 420)
        .onChange(of: question) { _, _ in prepared = nil }
        .onChange(of: scope) { _, _ in prepared = nil }
    }

    private func preview() {
        error = ""
        prepared = Assist.shared.prepareCloud(question, items: scope.items())
    }

    private func ask() {
        error = ""; answer = ""; busy = true
        let items = scope.items()
        Task {
            defer { busy = false }
            do {
                if target == .cloud {
                    guard let p = prepared else { preview(); return }
                    let r = try await Assist.shared.sendCloud(p)
                    answer = r.text + "\n\n(\(r.model): \(r.inputTokens) in, \(r.outputTokens) out tokens, logged)"
                } else {
                    answer = try await Assist.shared.askOnDevice(question, items: items)
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// The Ask window is managed by hand: a SwiftUI `Window` scene would open itself at launch, which
/// is wrong for a menu bar app.
@MainActor
final class AssistWindowController {
    static let shared = AssistWindowController()
    private(set) var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = String(localized: "Ask Your Clipboard")
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("AskWindow")
            w.contentView = NSHostingView(rootView: AssistView())
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
