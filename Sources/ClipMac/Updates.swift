//  "Check for Updates…" without Sparkle: one GET to the GitHub Releases API, compare versions,
//  open the release page. Nothing automatic, nothing in the background, no identifiers sent.

import Foundation
import AppKit

enum Updates {
    static let repo = "keithadler/clipmac"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!

    enum Result { case upToDate(String), available(String, URL), unknown(String) }

    static func check() async -> Result {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .unknown("no response") }
            if http.statusCode == 404 { return .unknown(String(localized: "No public release yet.")) }
            guard http.statusCode == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return .unknown("HTTP \(http.statusCode)") }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
            return isNewer(latest, than: Capabilities.appVersion) ? .available(latest, page) : .upToDate(latest)
        } catch {
            return .unknown(error.localizedDescription)
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    @MainActor
    static func checkAndPresent() {
        Task {
            let r = await check()
            let alert = NSAlert()
            switch r {
            case .upToDate(let v):
                alert.messageText = String(localized: "You're up to date")
                alert.informativeText = String(format: String(localized: "Clip for Mac %@ is the latest version."), v)
            case .available(let v, let url):
                alert.messageText = String(format: String(localized: "Clip for Mac %@ is available"), v)
                alert.informativeText = String(format: String(localized: "You have %@. The release page has the download and the notes."), Capabilities.appVersion)
                alert.addButton(withTitle: String(localized: "Open Release Page"))
                alert.addButton(withTitle: String(localized: "Later"))
                NSApp.activate()
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
                return
            case .unknown(let why):
                alert.messageText = String(localized: "Couldn't check for updates")
                alert.informativeText = why
            }
            NSApp.activate()
            alert.runModal()
        }
    }

    @MainActor
    static func showAbout() {
        NSApp.activate()
        let credits = NSAttributedString(string: String(localized: "Clipboard history that refuses to capture secrets.\nMIT licensed. No account, no telemetry.\nhttps://github.com/keithadler/clipmac"),
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Clip for Mac",
            .applicationVersion: Capabilities.appVersion,
            .version: "",
            .credits: credits,
        ])
    }
}

/// Help lives inside the bundle (docs/Help.html) so it works offline and before the repo is public;
/// the GitHub README is the fallback when running the bare binary from a build directory.
enum Help {
    static let readme = URL(string: "https://github.com/keithadler/clipmac#readme")!
    static let issues = URL(string: "https://github.com/keithadler/clipmac/issues")!

    /// "Help.es.html" for Spanish speakers, "Help.html" otherwise.
    static var pageName: String { (Locale.preferredLanguages.first ?? "en").hasPrefix("es") ? "Help.es" : "Help" }

    static var bundledPage: URL? {
        if let url = Bundle.main.url(forResource: pageName, withExtension: "html") { return url }
        // Launched through the clipmac symlink: find the enclosing .app the way Capabilities.appVersion does.
        var url = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app", let u = Bundle(url: url)?.url(forResource: pageName, withExtension: "html") { return u }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    @MainActor
    static func open(anchor: String? = nil) {
        if let page = bundledPage {
            var comps = URLComponents(url: page, resolvingAgainstBaseURL: false)!
            comps.fragment = anchor
            NSWorkspace.shared.open(comps.url ?? page)
        } else {
            NSWorkspace.shared.open(readme)
        }
    }
}
