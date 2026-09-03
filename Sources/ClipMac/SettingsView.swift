//  Settings. Every optional feature reports its real state (permission granted, model available,
//  FileVault on) next to its control, so nothing is a dead switch.

import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            CaptureTab().tabItem { Label("Capture", systemImage: "eye.slash") }
            HistoryTab().tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            PasteTab().tabItem { Label("Paste", systemImage: "keyboard") }
            AssistTab().tabItem { Label("Assist", systemImage: "sparkles") }
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - General

struct GeneralTab: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("menuBarIcon", store: Prefs.defaults) private var menuBarIcon = true
    @State private var plainOn = Hotkey.Kind.plainPaste.enabled
    @State private var nextOn = Hotkey.Kind.pasteNext.enabled
    @AppStorage("autoUpdateCheck", store: Prefs.defaults) private var autoUpdate = false
    @ObservedObject private var updates = UpdateState.shared

    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                HotkeyRow(kind: .panel)
                HotkeyRow(kind: .plainPaste, enabled: $plainOn)
                HotkeyRow(kind: .pasteNext, enabled: $nextOn)
                Text("Click a box, then press the keys you want; esc cancels. No Accessibility permission is needed for shortcuts. Paste-as-plain and paste-next press ⌘V for you only when Accessibility is granted; otherwise they put the text on the clipboard and you press ⌘V.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Open at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
                Toggle("Show the menu bar icon", isOn: $menuBarIcon)
                if !menuBarIcon { Text("With the icon hidden, the shortcut and `clipmac` are the only ways in.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Updates") {
                Toggle("Check for updates once a day", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, on in if on { Task { await Updates.checkIfDue() } } }
                Text("One request to GitHub's releases API, with no identifiers. When a newer version exists the menu bar icon fills in and offers the download; nothing is downloaded or installed by itself.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Check Now") { Updates.checkAndPresent() }.disabled(updates.checking)
                    if updates.checking { ProgressView().controlSize(.small) }
                    Spacer()
                    if let (v, _) = updates.available { Text(String(format: String(localized: "%@ is available"), v)).font(.caption).foregroundStyle(Color.accentColor) }
                    else if let d = updates.lastChecked { Text(String(format: String(localized: "Last checked %@"), d.formatted(date: .abbreviated, time: .shortened))).font(.caption).foregroundStyle(.secondary) }
                    else { Text("Never checked").font(.caption).foregroundStyle(.secondary) }
                }
                if let skipped = Prefs.skippedVersion {
                    HStack {
                        Text(String(format: String(localized: "Skipping %@"), skipped)).font(.caption).foregroundStyle(.secondary)
                        Button("Stop Skipping") { Prefs.skippedVersion = nil; Task { await Updates.runCheck(quiet: true) } }.font(.caption)
                    }
                }
            }
            Section {
                Text("Clip for Mac \(Capabilities.appVersion) · MIT licensed · no account, no telemetry, no network unless you add a key or turn on the update check.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// One shortcut: label, optional on/off toggle, recorder box, conflict note.
struct HotkeyRow: View {
    let kind: Hotkey.Kind
    var enabled: Binding<Bool>? = nil
    @State private var description = ""
    @State private var conflict = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if let enabled {
                    Toggle(kind.label, isOn: enabled).onChange(of: enabled.wrappedValue) { _, on in
                        Hotkey.setEnabled(kind, on); conflict = Hotkey.conflicts.contains(kind)
                    }
                } else {
                    Text(kind.label)
                }
                Spacer()
                HotkeyRecorder(kind: kind, description: $description, conflict: $conflict)
                    .frame(width: 150, height: 26)
                    .disabled(enabled?.wrappedValue == false)
                    .opacity(enabled?.wrappedValue == false ? 0.5 : 1)
            }
            if conflict { Text("Another app already uses this shortcut. Choose a different one.").font(.caption).foregroundStyle(.red) }
        }
        .onAppear { description = Hotkey.describe(kind); conflict = Hotkey.conflicts.contains(kind) }
    }
}

/// A box that records the next key combination pressed while it has focus.
struct HotkeyRecorder: NSViewRepresentable {
    let kind: Hotkey.Kind
    @Binding var description: String
    @Binding var conflict: Bool

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onRecord = { code, mods in
            let ok = Hotkey.set(kind, keyCode: code, modifiers: mods)
            description = Hotkey.describe(keyCode: code, modifiers: mods)
            conflict = !ok
        }
        v.label = description
        return v
    }

    func updateNSView(_ v: RecorderView, context: Context) { v.label = description; v.needsDisplay = true }

    final class RecorderView: NSView {
        var onRecord: ((Int, Int) -> Void)?
        var label = ""
        private var recording = false

        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); recording = true; needsDisplay = true }
        override func resignFirstResponder() -> Bool { recording = false; needsDisplay = true; return true }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            let mods = Hotkey.carbonModifiers(event.modifierFlags)
            if event.keyCode == 53 { recording = false; window?.makeFirstResponder(nil); needsDisplay = true; return }
            guard mods != 0 else { NSSound.beep(); return }  // a bare key would swallow typing everywhere
            onRecord?(Int(event.keyCode), mods)
            recording = false
            window?.makeFirstResponder(nil)
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill(); path.fill()
            (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke(); path.stroke()
            let text = recording ? String(localized: "Press keys…") : label
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
        }
    }
}

// MARK: - Capture

struct CaptureTab: View {
    @ObservedObject private var monitor = Monitor.shared
    @State private var exclusions = Prefs.excludedBundleIDs
    @State private var newID = ""
    @AppStorage("sizeCapMB", store: Prefs.defaults) private var sizeCapMB = 50
    @AppStorage("recordWindowTitles", store: Prefs.defaults) private var titles = true
    @AppStorage("skipToasts", store: Prefs.defaults) private var toasts = true
    @AppStorage("ocrImages", store: Prefs.defaults) private var ocr = true

    var body: some View {
        Form {
            Section("Never captured") {
                Text("Anything a password manager marks as concealed or transient, anything copied while a password field has focus, and anything copied from the apps below. These rules cannot be turned off.")
                    .font(.caption).foregroundStyle(.secondary)
                if monitor.secureInput { Label("A password field has focus right now; nothing is being captured.", systemImage: "lock.fill").font(.caption).foregroundStyle(.orange) }
                if let skip = monitor.lastSkip { Text(String(format: String(localized: "Last skipped item: %@"), skip)).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Excluded apps (bundle identifiers)") {
                List {
                    ForEach(exclusions, id: \.self) { id in
                        HStack {
                            Text(id).font(.callout.monospaced())
                            Spacer()
                            Button { exclusions.removeAll { $0 == id }; save() } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                        }
                    }
                }.frame(minHeight: 150)
                HStack {
                    TextField("com.example.app", text: $newID).textFieldStyle(.roundedBorder)
                    Button("Add") { add() }.disabled(newID.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Pick app…") { pickApp() }
                    Button("Reset") { exclusions = Prefs.defaultExclusions; save() }
                }
            }
            Section {
                Stepper(value: $sizeCapMB, in: 1...500, step: 5) { Text(String(format: String(localized: "Skip items larger than %lld MB"), sizeCapMB)) }
                Toggle("Show a note when something isn't saved", isOn: $toasts)
                Toggle("Remember the window title an item came from", isOn: $titles)
                Text(Capabilities.accessibilityTrusted ? "\"Safari · GitHub issue #42\" instead of just \"Safari\". Titles stay on this Mac like everything else." : "Needs the Accessibility permission (Settings › Paste); until then only the app name is kept.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Read the text in images so screenshots are searchable", isOn: $ocr)
                Text("On-device, with Apple's Vision framework. The recognised text becomes the item's searchable text.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let id = newID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !exclusions.contains(id) else { return }
        exclusions.append(id); newID = ""; save()
    }

    private func save() { Prefs.excludedBundleIDs = exclusions }

    private func pickApp() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.applicationBundle]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        if p.runModal() == .OK, let url = p.url, let id = Bundle(url: url)?.bundleIdentifier, !exclusions.contains(id) {
            exclusions.append(id); save()
        }
    }
}

// MARK: - History

struct HistoryTab: View {
    private func chooseSyncFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.message = String(localized: "Choose a folder that is already synced between your Macs.")
        NSApp.activate()
        if p.runModal() == .OK, let url = p.url {
            Prefs.syncFolder = url.path; syncFolder = url.path
            PinSync.pushIfConfigured()
            if let n = PinSync.pullIfChanged() { pinNote = String(format: String(localized: "merged %lld pins"), n) }
        }
    }
    private func exportPins() {
        let p = NSSavePanel(); p.nameFieldStringValue = PinSync.fileName; p.allowedContentTypes = [.json]
        NSApp.activate()
        if p.runModal() == .OK, let url = p.url {
            do { pinNote = String(format: String(localized: "exported %lld pins"), try PinSync.export(to: url)) } catch { pinNote = error.localizedDescription }
        }
    }
    private func importPins() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]
        NSApp.activate()
        if p.runModal() == .OK, let url = p.url {
            do { pinNote = String(format: String(localized: "merged %lld pins"), try PinSync.importFile(url)) } catch { pinNote = error.localizedDescription }
        }
    }

    @AppStorage("sessionOnly", store: Prefs.defaults) private var sessionOnly = false
    @AppStorage("retentionDays", store: Prefs.defaults) private var days = 30
    @AppStorage("retentionItems", store: Prefs.defaults) private var items = 2000
    @AppStorage("retentionMB", store: Prefs.defaults) private var mb = 1024
    @State private var fileVault: Bool? = nil
    @State private var confirmWipe = false
    @State private var count = Store.shared.count()
    @State private var bytes = Store.shared.totalBytes()
    @State private var syncFolder = Prefs.syncFolder
    @State private var pinNote = ""

    var body: some View {
        Form {
            Section("Keep") {
                Stepper(value: $days, in: 1...365) { Text(String(format: String(localized: "%lld days"), days)) }
                Stepper(value: $items, in: 100...20000, step: 100) { Text(String(format: String(localized: "%lld items"), items)) }
                Stepper(value: $mb, in: 64...10240, step: 64) { Text(String(format: String(localized: "%lld MB in total"), mb)) }
                Text("Pinned items are exempt. Deleted items are really deleted; there is no undo and no receipt.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Session only (forget everything when the app quits)", isOn: $sessionOnly)
                Text("Takes effect the next time Clip for Mac opens.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Pins on other Macs") {
                Text("Pins (never history) can travel as a small JSON file. Put it in a folder that iCloud Drive, Dropbox or anything else already syncs, and every Mac running Clip for Mac keeps its pins in step. No account, no server.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if let f = syncFolder { Text(f).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle) } else { Text("No sync folder").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button(syncFolder == nil ? "Choose Folder…" : "Change…") { chooseSyncFolder() }
                    if syncFolder != nil { Button("Stop") { Prefs.syncFolder = nil; syncFolder = nil } }
                }
                HStack {
                    Button("Export Pins…") { exportPins() }
                    Button("Import Pins…") { importPins() }
                    if !pinNote.isEmpty { Text(pinNote).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section("On disk") {
                Text(String(format: String(localized: "%lld items, %@, in %@"), count, ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file), Store.dbURL.deletingLastPathComponent().path))
                    .font(.caption).foregroundStyle(.secondary)
                switch fileVault {
                case .some(true): Label("FileVault is on, so the history is encrypted at rest.", systemImage: "lock.shield").font(.caption)
                case .some(false): Label("FileVault is OFF. Clip for Mac does not encrypt the history itself; turn on FileVault in System Settings › Privacy & Security.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                case .none: Text("Checking FileVault…").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Store.dbURL]) }
                    Button("Forget everything…", role: .destructive) { confirmWipe = true }
                }
            }
        }
        .formStyle(.grouped)
        .task { fileVault = await Task.detached { Capabilities.fileVaultOn }.value }
        .confirmationDialog("Delete the whole clipboard history, including pinned items?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                Store.shared.wipe(); count = 0; bytes = 0
                NotificationCenter.default.post(name: .clipHistoryChanged, object: nil)
            }
        }
    }
}

// MARK: - Paste

struct PasteTab: View {
    @AppStorage("autoPaste", store: Prefs.defaults) private var autoPaste = true
    @AppStorage("restorePrevious", store: Prefs.defaults) private var restore = true
    @AppStorage("restoreDelayMs", store: Prefs.defaults) private var delay = 500
    @State private var trusted = Capabilities.accessibilityTrusted
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("How items get pasted") {
                Toggle("Paste into the app I was using", isOn: $autoPaste)
                if autoPaste {
                    if trusted {
                        Label("Accessibility is granted: choosing an item pastes it.", systemImage: "checkmark.circle").font(.caption)
                    } else {
                        Label("Needs the Accessibility permission, which is how macOS lets an app press ⌘V for you. Until then, choosing an item copies it and you press ⌘V yourself.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Grant Accessibility…") { Capabilities.requestAccessibility(); Capabilities.openAccessibilitySettings() }
                            Button("Re-check") { trusted = Capabilities.accessibilityTrusted }
                        }
                    }
                } else {
                    Text("Copy only: choosing an item puts it on the clipboard and closes the panel. Nothing is pressed for you.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("After pasting") {
                Toggle("Put my previous clipboard back afterwards", isOn: $restore).disabled(!autoPaste)
                Stepper(value: $delay, in: 100...3000, step: 100) { Text(String(format: String(localized: "after %lld ms"), delay)) }.disabled(!restore || !autoPaste)
                Text("There is no way to know when the other app has finished reading the clipboard, so this is a delay. Raise it if a slow app pastes the wrong thing.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("⌘↩ in the panel always pastes as plain text, whatever the item was.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(tick) { _ in trusted = Capabilities.accessibilityTrusted }
    }
}

// MARK: - Assist

struct AssistTab: View {
    @AppStorage("semanticSearch", store: Prefs.defaults) private var semantic = true
    @AppStorage("onDeviceModel", store: Prefs.defaults) private var onDevice = false
    @AppStorage("cloudAssist", store: Prefs.defaults) private var cloud = false
    @AppStorage("cloudProvider", store: Prefs.defaults) private var provider = "anthropic"
    @AppStorage("cloudModel", store: Prefs.defaults) private var model = ""
    @State private var key = ""
    @State private var hasKey = false
    @State private var log = Store.shared.assistLog(limit: 20)

    private var prov: Assist.Provider { Assist.Provider(rawValue: provider) ?? .anthropic }

    var body: some View {
        Form {
            Section("On this Mac") {
                Toggle("Search by meaning (on-device word embeddings, no network)", isOn: $semantic).disabled(!Capabilities.sentenceEmbeddingAvailable)
                    .onChange(of: semantic) { _, on in if on { Assist.shared.indexSoon() } }
                Toggle("Ask Apple's on-device model", isOn: $onDevice).disabled(!Capabilities.onDeviceModelAvailable)
                Text(Capabilities.onDeviceModelNote).font(.caption).foregroundStyle(.secondary)
            }
            Section("Bring your own key") {
                Toggle("Allow sending selected items to a cloud model", isOn: $cloud)
                if cloud {
                    Picker("Provider", selection: $provider) { ForEach(Assist.Provider.allCases) { Text($0.label).tag($0.rawValue) } }
                        .onChange(of: provider) { _, _ in load() }
                    TextField("Model", text: $model, prompt: Text(prov == .anthropic ? "claude-opus-5" : "gpt-5"))
                    HStack {
                        SecureField(hasKey ? "A key is stored in your Keychain" : "Paste your API key", text: $key)
                        Button(hasKey ? "Replace" : "Save") { Assist.setAPIKey(key, for: prov); key = ""; load() }.disabled(key.isEmpty)
                        if hasKey { Button("Remove") { Assist.setAPIKey(nil, for: prov); load() } }
                    }
                    Text("Nothing is sent automatically. You pick the items, see the redacted payload, and confirm every request. This uses the provider's metered API, which is billed separately from a Claude Pro or ChatGPT Plus subscription. Their key, their bill, their data: no proxy, no account, no relay.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Request log") {
                if log.isEmpty { Text("Nothing has been sent.").font(.caption).foregroundStyle(.secondary) }
                ForEach(log) { e in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(e.at.formatted(date: .abbreviated, time: .shortened)) · \(e.provider) · \(e.model)").font(.caption)
                        Text(String(format: String(localized: "%lld items, %lld characters, %lld in / %lld out tokens · “%@”"), e.itemCount, e.chars, e.inputTokens, e.outputTokens, String(e.prompt.prefix(60)))).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Ask your clipboard…") { AssistWindowController.shared.show() }
                    .disabled(!(onDevice && Capabilities.onDeviceModelAvailable) && !cloud)
            }
        }
        .formStyle(.grouped)
        .onAppear { load() }
    }

    private func load() { hasKey = Assist.apiKey(for: prov) != nil; log = Store.shared.assistLog(limit: 20) }
}
