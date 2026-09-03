//  `clipmac screenshots <dir>`: renders every window with demo data into PNGs for the README, in
//  dark and light appearance, without touching real history or needing any permission. The CLI
//  process is the same binary, so it can put the windows on screen for a moment and capture them.

import AppKit
import SwiftUI

enum Screenshots {
    @MainActor
    static func render(to dir: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)               // a regular app can become active: title bars render live
        app.activate(ignoringOtherApps: true)
        settle(0.4)
        if app.applicationIconImage.size.width == 0 || Bundle.main.bundleIdentifier == nil, let icon = bundledIcon() {
            app.applicationIconImage = icon              // running from a build directory: no bundle icon
        }

        // Isolated store and defaults with demo content.
        Store.shared = Store(inMemory: true)
        let suite = "com.keithadler.clipmac.screenshots"
        Prefs.defaults = UserDefaults(suiteName: suite)!
        defer { Prefs.defaults.removePersistentDomain(forName: suite) }
        Prefs.defaults.set(true, forKey: "welcomed")
        Prefs.defaults.set(true, forKey: "onDeviceModel")
        seed()

        var written: [URL] = []
        for (suffix, appearance) in [("", NSAppearance.Name.darkAqua), ("-light", .aqua)] {
            app.appearance = NSAppearance(named: appearance)

            PanelController.shared.show()
            settle()
            if let w = PanelController.shared.window { written.append(try capture(w, to: dir.appendingPathComponent("panel\(suffix).png"))) }
            // Search by meaning: "money owed" finds the invoice and the bill without either word.
            PanelController.shared.model.query = "money owed"
            settle()
            if let w = PanelController.shared.window { written.append(try capture(w, to: dir.appendingPathComponent("panel-search\(suffix).png"))) }
            PanelController.shared.hide()

            WelcomeController.shared.show()
            settle()
            if let w = WelcomeController.shared.window { written.append(try capture(w, to: dir.appendingPathComponent("welcome\(suffix).png"))); w.orderOut(nil) }

            let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            settings.title = String(localized: "General")
            settings.contentView = NSHostingView(rootView: SettingsView())
            settings.center(); settings.makeKeyAndOrderFront(nil)
            settle()
            written.append(try capture(settings, to: dir.appendingPathComponent("settings\(suffix).png")))
            settings.orderOut(nil)

            AssistWindowController.shared.show()
            settle()
            if let w = AssistWindowController.shared.window { written.append(try capture(w, to: dir.appendingPathComponent("ask\(suffix).png"))); w.orderOut(nil) }
        }
        app.setActivationPolicy(.accessory)
        return written
    }

    /// Lets SwiftUI lay out and the window server composite before capturing.
    @MainActor
    private static func settle(_ seconds: TimeInterval = 0.6) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// The app icon from the enclosing bundle, or AppIcon.icns in the working directory (source checkout).
    private static func bundledIcon() -> NSImage? {
        var url = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app", let i = NSImage(contentsOf: url.appendingPathComponent("Contents/Resources/AppIcon.icns")) { return i }
            url = url.deletingLastPathComponent()
        }
        return NSImage(contentsOfFile: FileManager.default.currentDirectoryPath + "/AppIcon.icns")
    }

    /// CGWindowListCreateImage is deprecated in favour of ScreenCaptureKit, which needs the Screen
    /// Recording permission even for the app's own windows. Capturing our own windows works fine
    /// without it, so the function is resolved at runtime to keep the build warning-free.
    private typealias WindowImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let windowImage: WindowImageFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }   // RTLD_DEFAULT
        return unsafeBitCast(sym, to: WindowImageFn.self)
    }()

    @MainActor
    private static func capture(_ window: NSWindow, to url: URL) throws -> URL {
        window.makeKeyAndOrderFront(nil)
        settle(0.3)
        let id = CGWindowID(window.windowNumber)
        let options = CGWindowListOption.optionIncludingWindow.rawValue
        let imageOptions = CGWindowImageOption.boundsIgnoreFraming.rawValue | CGWindowImageOption.bestResolution.rawValue
        var cg = windowImage?(.null, options, id, imageOptions)?.takeRetainedValue()
        if cg == nil || cg!.width < 10, let view = window.contentView {
            // Fallback that needs nothing from the window server: draw the view hierarchy ourselves.
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            cg = rep.cgImage
        }
        guard let image = cg else { throw NSError(domain: "clipmac", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not capture \(window.title)"]) }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "clipmac", code: 2) }
        try png.write(to: url, options: .atomic)
        return url
    }

    /// Demo history: an invoice, a link, a flagged secret, notes, a recipe, a pinned signature,
    /// an image and a file. Indexed so "Similar meaning" has something to show.
    private static func seed() {
        let s = Store.shared
        func text(_ t: String, app: String = "com.apple.Notes", name: String = "Notes", kind: ItemKind = .text) {
            _ = s.insert(Capture(kind: kind, plain: t, blobData: nil, blobType: nil, sourceBundleID: app, sourceName: name, size: t.utf8.count))
        }
        text("Sam Rivera\nsam@example.com", app: "com.apple.mail", name: "Mail")
        let sig = s.item(atPosition: 1)!
        s.setPinned(sig.id, true, keyword: "sig")
        text("/Users/sam/Documents/Woodland Ave lease.pdf", app: "com.apple.finder", name: "Finder", kind: .file)
        let img = NSImage(size: NSSize(width: 320, height: 200))
        img.lockFocus()
        NSGradient(colors: [NSColor.systemTeal, NSColor.systemIndigo])!.draw(in: NSRect(x: 0, y: 0, width: 320, height: 200), angle: 30)
        img.unlockFocus()
        let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        _ = s.insert(Capture(kind: .image, plain: "", blobData: png, blobType: NSPasteboard.PasteboardType.png.rawValue, sourceBundleID: "com.apple.Preview", sourceName: "Preview", size: png.count))
        text("recipe: two eggs, flour, milk, whisk until smooth", app: "com.apple.Safari", name: "Safari")
        text("Meeting notes: ship the clipboard app next week, then write the launch post")
        text("export STRIPE_KEY=sk-live-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", app: "com.apple.Terminal", name: "Terminal")
        text("https://developer.apple.com/documentation/appkit/nspasteboard", app: "com.apple.Safari", name: "Safari", kind: .url)
        text("The quarterly bill for the Woodland Ave project is overdue, pay by Friday")
        text("Invoice #4471 for the Woodland Ave project is due Friday", app: "com.apple.mail", name: "Mail")
        Assist.shared.indexPending()
    }
}
