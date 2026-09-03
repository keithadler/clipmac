//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  Announcement images. Rendered by `clipmac screenshots <dir>` into <dir>/promo from the same demo
//  data as the README screenshots, at 1600×900 (16:9 for X, Mastodon, Product Hunt) with a 2× store.
//  Concrete view types on purpose: opaque `some View` helpers shared across cards have crashed
//  SwiftUI's off-screen rendering before.

import SwiftUI
import AppKit

enum Promo {
    static let size = CGSize(width: 1600, height: 900)

    static var blue: LinearGradient {
        LinearGradient(colors: [Color(red: 0.12, green: 0.30, blue: 0.78), Color(red: 0.20, green: 0.45, blue: 0.92), Color(red: 0.32, green: 0.58, blue: 0.98)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var night: LinearGradient {
        LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.12), Color(red: 0.12, green: 0.15, blue: 0.24)], startPoint: .top, endPoint: .bottom)
    }

    struct Shot: View {
        let image: NSImage?
        let width: CGFloat
        var body: some View {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: width)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 16)
            } else {
                Color.clear.frame(width: width, height: 10)
            }
        }
    }

    struct Bullet: View {
        let text: String
        var symbol = "checkmark.circle.fill"
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.white)
                Text(text).font(.system(size: 26)).foregroundStyle(.white)
            }
        }
    }

    // 1. Hero
    struct Hero: View {
        let icon: NSImage
        let panel: NSImage?
        var body: some View {
            ZStack {
                blue
                HStack(spacing: 40) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 18) {
                            Image(nsImage: icon).resizable().frame(width: 110, height: 110)
                            Text("Clip for Mac").font(.system(size: 64, weight: .bold)).foregroundStyle(.white)
                        }
                        Text("A clipboard manager that\nrefuses to capture secrets.")
                            .font(.system(size: 36, weight: .medium)).foregroundStyle(.white.opacity(0.95)).lineSpacing(4)
                        VStack(alignment: .leading, spacing: 12) {
                            Bullet(text: "Honors password managers and password fields")
                            Bullet(text: "Flags keys, tokens and card numbers")
                            Bullet(text: "Searches by meaning, on-device")
                            Bullet(text: "Free and open source · MIT · no account")
                        }
                        .padding(.top, 6)
                    }
                    .frame(width: 720, alignment: .leading)
                    Shot(image: panel, width: 700)
                }
                .padding(.horizontal, 70)
            }
        }
    }

    // 2. The refusal rules
    struct Rules: View {
        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.20), Color(red: 0.16, green: 0.22, blue: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 60) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("These rules have\nno off switch.").font(.system(size: 58, weight: .bold)).foregroundStyle(.white).lineSpacing(2)
                        Text("Every clipboard manager keeps a plain-text diary of what you copy, including the password your password manager just put there. Clip for Mac starts from what it will never keep.")
                            .font(.system(size: 24)).foregroundStyle(.white.opacity(0.9)).lineSpacing(4)
                    }
                    .frame(width: 640, alignment: .leading)
                    VStack(alignment: .leading, spacing: 22) {
                        Rule(symbol: "key.fill", title: "Concealed and transient", detail: "The org.nspasteboard convention 1Password, Bitwarden, Keychain Access and others set on secrets.")
                        Rule(symbol: "lock.fill", title: "Password fields", detail: "Nothing is recorded while macOS secure input is on. The menu bar shows a lock.")
                        Rule(symbol: "eye.slash.fill", title: "Excluded apps", detail: "Pre-filled with the common password managers. Add any app.")
                        Rule(symbol: "exclamationmark.shield.fill", title: "Secret-shaped items are flagged", detail: "API keys, JWTs, private keys, Luhn-valid card numbers, password=… One command forgets them all.")
                    }
                    .frame(width: 720, alignment: .leading)
                }
                .padding(.horizontal, 70)
            }
        }
    }

    struct Rule: View {
        let symbol: String, title: String, detail: String
        var body: some View {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Color(red: 0.98, green: 0.80, blue: 0.25)).frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 27, weight: .semibold)).foregroundStyle(.white)
                    Text(detail).font(.system(size: 20)).foregroundStyle(.white.opacity(0.85)).lineSpacing(2)
                }
            }
        }
    }

    // 3. Meaning, stack, shortcuts
    struct Features: View {
        let search: NSImage?
        var body: some View {
            ZStack {
                blue
                HStack(spacing: 44) {
                    Shot(image: search, width: 780)
                    VStack(alignment: .leading, spacing: 26) {
                        Text("Finds it by meaning.").font(.system(size: 54, weight: .bold)).foregroundStyle(.white)
                        Text("\"money owed\" finds the invoice and the bill without either word. Apple's on-device word embeddings, no network, on by default.")
                            .font(.system(size: 24)).foregroundStyle(.white.opacity(0.95)).lineSpacing(4)
                        VStack(alignment: .leading, spacing: 12) {
                            Bullet(text: "⌥⌘V opens the panel over any app", symbol: "keyboard")
                            Bullet(text: "⌥⇧⌘V pastes anything as plain text", symbol: "textformat")
                            Bullet(text: "⇧↩ queues, ⌃⌥⌘V pastes the next one", symbol: "square.stack.3d.up")
                            Bullet(text: "Pins with keywords, Text Replacement export", symbol: "pin")
                        }
                    }
                    .frame(width: 660, alignment: .leading)
                }
                .padding(.horizontal, 60)
            }
        }
    }

    // 4. Command line
    struct CLIcard: View {
        var body: some View {
            ZStack {
                night
                HStack(spacing: 50) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Also a real\ncommand line.").font(.system(size: 58, weight: .bold)).foregroundStyle(.white)
                        Text("Same binary as the app. --json everywhere, exit codes, a man page, and a clipmac:// URL scheme for Shortcuts.")
                            .font(.system(size: 24)).foregroundStyle(.white.opacity(0.9)).lineSpacing(4)
                        Text("Swift, SQLite + FTS5, no dependencies, no Xcode project. Universal binary, macOS 14+.")
                            .font(.system(size: 20)).foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(width: 600, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 14, height: 14)
                            Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 14, height: 14)
                            Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.26)).frame(width: 14, height: 14)
                            Spacer()
                        }
                        .padding(16)
                        Text("""
                        $ clipmac search "money owed" --semantic
                            #12   text   The quarterly bill for Woodland Ave is overdue
                            #11   text   Invoice #4471 for Woodland Ave is due Friday

                        $ clipmac list --limit 3 --json | jq '.[].sensitive'
                        false
                        true
                        false

                        $ clipmac forget --sensitive
                        forgot 1 item that looked like a secret

                        $ clipmac assist "what did I work on today" --local
                        Mostly the Woodland Ave invoice and the launch post.

                        $ clipmac status
                        capture:        on
                        FileVault:      on
                        """)
                        .font(.system(size: 19, design: .monospaced)).foregroundStyle(Color(red: 0.85, green: 0.93, blue: 0.85))
                        .padding(.horizontal, 22).padding(.bottom, 22)
                    }
                    .frame(width: 800, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.05, green: 0.06, blue: 0.09)))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.15)))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
                }
                .padding(.horizontal, 70)
            }
        }
    }

    /// Renders all four cards into `dir/promo` from the screenshots already in `dir`.
    @MainActor
    static func render(into dir: URL, icon: NSImage) -> [URL] {
        let out = dir.appendingPathComponent("promo")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func img(_ n: String) -> NSImage? { NSImage(contentsOf: dir.appendingPathComponent("\(n).png")) }
        let cards: [(String, AnyView)] = [
            ("1-hero", AnyView(Hero(icon: icon, panel: img("panel")))),
            ("2-rules", AnyView(Rules())),
            ("3-meaning", AnyView(Features(search: img("panel-search")))),
            ("4-cli", AnyView(CLIcard())),
        ]
        var written: [URL] = []
        for (name, view) in cards {
            if let png = snapshot(view, size: size) {
                let url = out.appendingPathComponent("\(name).png")
                try? png.write(to: url)
                written.append(url)
            }
        }
        return written
    }

    /// Off-screen render of a SwiftUI view at 2×. The window sits far off-screen and is never visible.
    @MainActor
    static func snapshot(_ view: AnyView, size: CGSize) -> Data? {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let win = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        win.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        win.orderFront(nil)
        for _ in 0..<6 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        win.orderOut(nil)
        return rep.representation(using: .png, properties: [:])
    }
}
