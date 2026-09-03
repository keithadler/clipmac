//  "Check for Updates…" without Sparkle: one GET to the GitHub Releases API, compare versions,
//  open the release page. Nothing automatic, nothing in the background, no identifiers sent.

import Foundation
import AppKit

/// Update state the menu bar and Settings observe.
@MainActor
final class UpdateState: ObservableObject {
    static let shared = UpdateState()
    @Published var available: (version: String, page: URL)?
    @Published var lastChecked: Date? = Prefs.lastUpdateCheck
    @Published var checking = false
    @Published var lastError: String?
}

enum Updates {
    static let repo = "keithadler/clipmac"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!
    /// Injectable for tests.
    nonisolated(unsafe) static var session: URLSession = .shared

    enum Result: Equatable { case upToDate(String), available(String, URL), unknown(String) }

    /// One GET to GitHub's releases API; no identifiers, no cookies.
    static func check() async -> Result {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .unknown("no response") }
            return parse(status: http.statusCode, body: data, current: Capabilities.appVersion)
        } catch {
            return .unknown(error.localizedDescription)
        }
    }

    /// Pure: what a GitHub "latest release" response means for the running version.
    static func parse(status: Int, body: Data, current: String) -> Result {
        if status == 404 { return .unknown(String(localized: "No public release yet.")) }
        guard status == 200, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let tag = json["tag_name"] as? String else { return .unknown("HTTP \(status)") }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
        return isNewer(latest, than: current) ? .available(latest, page) : .upToDate(latest)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Background checks (opt-in)

    static let interval: TimeInterval = 24 * 3600

    /// Pure: whether a background check is due. At most one per day, only when the user opted in.
    static func shouldCheck(enabled: Bool, last: Date?, now: Date = Date()) -> Bool {
        guard enabled else { return false }
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval - 3600   // a little slack so a daily launch still checks
    }

    private nonisolated(unsafe) static var timer: Timer?

    /// Called at launch. Checks shortly after start when due, then once an hour re-evaluates.
    @MainActor
    static func scheduleBackgroundChecks() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in Task { @MainActor in await checkIfDue() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { Task { @MainActor in await checkIfDue() } }
    }

    @MainActor
    static func checkIfDue() async {
        guard shouldCheck(enabled: Prefs.autoUpdateCheck, last: Prefs.lastUpdateCheck) else { return }
        await runCheck(quiet: true)
    }

    /// Runs a check and records the result in UpdateState. Quiet checks never show dialogs.
    @MainActor
    static func runCheck(quiet: Bool) async {
        let state = UpdateState.shared
        state.checking = true
        let r = await check()
        state.checking = false
        state.lastChecked = Date()
        Prefs.lastUpdateCheck = state.lastChecked
        switch r {
        case .available(let v, let url):
            state.lastError = nil
            state.available = Prefs.skippedVersion == v && quiet ? nil : (v, url)
        case .upToDate:
            state.lastError = nil; state.available = nil
        case .unknown(let why):
            state.lastError = why
        }
    }

    @MainActor
    static func skip(_ version: String) {
        Prefs.skippedVersion = version
        UpdateState.shared.available = nil
    }

    @MainActor
    static func checkAndPresent() {
        Task {
            await runCheck(quiet: false)
            let state = UpdateState.shared
            let alert = NSAlert()
            if let (v, url) = state.available {
                alert.messageText = String(format: String(localized: "Clip for Mac %@ is available"), v)
                alert.informativeText = String(format: String(localized: "You have %@. The release page has the download and the notes."), Capabilities.appVersion)
                alert.addButton(withTitle: String(localized: "Open Release Page"))
                alert.addButton(withTitle: String(localized: "Later"))
                alert.addButton(withTitle: String(localized: "Skip This Version"))
                NSApp.activate()
                switch alert.runModal() {
                case .alertFirstButtonReturn: NSWorkspace.shared.open(url)
                case .alertThirdButtonReturn: skip(v)
                default: break
                }
                return
            }
            if let why = state.lastError {
                alert.messageText = String(localized: "Couldn't check for updates")
                alert.informativeText = why
            } else {
                alert.messageText = String(localized: "You're up to date")
                alert.informativeText = String(format: String(localized: "Clip for Mac %@ is the latest version."), Capabilities.appVersion)
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
