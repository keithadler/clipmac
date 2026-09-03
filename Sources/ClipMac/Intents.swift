//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  Shortcuts actions. The code compiles anywhere; Shortcuts only discovers the actions when the
//  bundle carries Metadata.appintents, which build-app.sh generates when Xcode's metadata processor
//  is available (see make-appintents.sh). Without it the clipmac:// URL scheme still works.

import AppIntents
import AppKit

struct ClipItemEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Clipboard Item")
    static let defaultQuery = ClipItemQuery()

    let id: String
    let kind: String
    let text: String
    let sourceApp: String?
    let pinned: Bool
    let sensitive: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(String(text.prefix(60)))", subtitle: "\(sourceApp ?? kind)")
    }

    init(_ item: Item) {
        id = String(item.id); kind = item.kind.rawValue; text = item.plain; sourceApp = item.sourceName; pinned = item.pinned; sensitive = item.looksSensitive
    }
}

struct ClipItemQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ClipItemEntity] {
        identifiers.compactMap { Int64($0) }.compactMap { Store.shared.get($0) }.map(ClipItemEntity.init)
    }
    func suggestedEntities() async throws -> [ClipItemEntity] {
        Store.shared.recent(limit: 10).map(ClipItemEntity.init)
    }
}

struct GetRecentItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Recent Clipboard Items"
    static let description = IntentDescription("The most recent items in Clip for Mac's history. Items that look like secrets are left out unless you ask for them.")

    @Parameter(title: "How many", default: 10, inclusiveRange: (1, 200))
    var limit: Int
    @Parameter(title: "Include items that look like secrets", default: false)
    var includeSensitive: Bool

    static var parameterSummary: some ParameterSummary { Summary("Get the last \(\.$limit) clipboard items") }

    func perform() async throws -> some IntentResult & ReturnsValue<[ClipItemEntity]> {
        let items = Store.shared.recent(limit: limit * 2).filter { includeSensitive || !$0.looksSensitive }.prefix(limit)
        return .result(value: items.map(ClipItemEntity.init))
    }
}

struct SearchClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Clip for Mac"
    static let description = IntentDescription("Full-text and meaning search over the clipboard history.")

    @Parameter(title: "Query")
    var query: String
    @Parameter(title: "How many", default: 10, inclusiveRange: (1, 100))
    var limit: Int

    static var parameterSummary: some ParameterSummary { Summary("Search the clipboard for \(\.$query)") }

    func perform() async throws -> some IntentResult & ReturnsValue<[ClipItemEntity]> {
        var items = Array(Store.shared.search(query, limit: limit).prefix(limit))
        if items.count < limit {
            let seen = Set(items.map(\.id))
            items += Assist.shared.semanticSearch(query, limit: limit - items.count).map(\.0).filter { !seen.contains($0.id) }
        }
        return .result(value: items.map(ClipItemEntity.init))
    }
}

struct CopyItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Clipboard Item"
    static let description = IntentDescription("Puts a history item back on the clipboard.")

    @Parameter(title: "Item")
    var item: ClipItemEntity
    @Parameter(title: "As plain text", default: false)
    var plain: Bool

    static var parameterSummary: some ParameterSummary { Summary("Copy \(\.$item)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = Int64(item.id), let it = Store.shared.get(id) else { throw IntentError.missing }
        Paster.write(it, plain: plain)
        return .result()
    }
}

struct PauseCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Clipboard Capture"
    static let description = IntentDescription("Stops Clip for Mac recording copies for a while.")

    @Parameter(title: "Minutes", default: 10, inclusiveRange: (1, 1440))
    var minutes: Int

    static var parameterSummary: some ParameterSummary { Summary("Pause capture for \(\.$minutes) minutes") }

    @MainActor
    func perform() async throws -> some IntentResult {
        Monitor.shared.pause(for: Double(minutes) * 60)
        return .result()
    }
}

struct ResumeCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Clipboard Capture"
    @MainActor
    func perform() async throws -> some IntentResult {
        Monitor.shared.resume()
        return .result()
    }
}

struct OpenPanelIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Clip for Mac"
    static let description = IntentDescription("Shows the clipboard panel.")
    static let openAppWhenRun = true
    @MainActor
    func perform() async throws -> some IntentResult {
        PanelController.shared.show()
        return .result()
    }
}

enum IntentError: LocalizedError {
    case missing
    var errorDescription: String? { String(localized: "That clipboard item is no longer in the history.") }
}

struct ClipShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenPanelIntent(), phrases: ["Open \(.applicationName)"], shortTitle: "Open", systemImageName: "doc.on.clipboard")
        AppShortcut(intent: PauseCaptureIntent(), phrases: ["Pause \(.applicationName)"], shortTitle: "Pause", systemImageName: "pause.circle")
    }
}
