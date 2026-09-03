//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  Search field, result list, preview pane. Never renders HTML: it shows the source.

import SwiftUI
import AppKit

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject private var stack = PasteStack.shared
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    searchField
                    Divider()
                    resultList
                }
                .frame(width: 400)
                Divider()
                PreviewPane(model: model, item: model.selectedItem)
            }
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.12)))
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { _, _ in searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search your clipboard", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
                .accessibilityLabel(Text("Search your clipboard"))
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    if model.combined.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "clipboard").font(.largeTitle).foregroundStyle(.tertiary)
                            Text(model.query.isEmpty ? "Nothing copied yet." : "No matches.").foregroundStyle(.secondary)
                        }.padding(.top, 60)
                    }
                    if !model.pins.isEmpty { sectionHeader("Pinned") }
                    ForEach(Array(model.pins.enumerated()), id: \.element.id) { i, it in row(it, index: i) }
                    if !model.items.isEmpty && !model.pins.isEmpty { sectionHeader("History") }
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { i, it in row(it, index: model.pins.count + i) }
                    if !model.related.isEmpty { sectionHeader("Similar meaning") }
                    ForEach(Array(model.related.enumerated()), id: \.element.id) { i, it in row(it, index: model.pins.count + model.items.count + i) }
                }
            }
            .onChange(of: model.selected) { _, i in
                if let it = model.selectedItem { proxy.scrollTo(it.id, anchor: .center) }
                _ = i
            }
        }
    }

    private func sectionHeader(_ s: LocalizedStringKey) -> some View {
        Text(s).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 2)
    }

    @State private var hovered: Int64?

    private func row(_ it: Item, index: Int) -> some View {
        let selected = index == model.selected
        return HStack(spacing: 10) {
            Image(systemName: it.kind.symbol).frame(width: 18).foregroundStyle(selected ? .white : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(it.kind == .image ? String(localized: "Image") : (it.preview.isEmpty ? " " : it.preview))
                    .lineLimit(1).truncationMode(.tail)
                HStack(spacing: 4) {
                    if let k = it.keyword { Text(k).font(.caption2).padding(.horizontal, 4).background(Color.accentColor.opacity(0.25)).clipShape(Capsule()) }
                    Text("\(it.sourceName ?? "") · \(Dump.relative(it.createdAt))").font(.caption).lineLimit(1)
                }.foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            }
            Spacer(minLength: 4)
            if it.looksSensitive { Image(systemName: "exclamationmark.shield").foregroundStyle(selected ? .white : .orange).help("Looks like a secret") }
            if it.pinned && it.keyword == nil { Image(systemName: "pin.fill").font(.caption).foregroundStyle(selected ? .white : .secondary) }
            if index < 9 { Text("⌘\(index + 1)").font(.caption.monospaced()).foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary) }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(selected ? Color.accentColor : (hovered == it.id ? Color.primary.opacity(0.06) : Color.clear), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .id(it.id)
        .onHover { hovered = $0 ? it.id : (hovered == it.id ? nil : hovered) }
        .onTapGesture(count: 2) { PanelController.shared.hide(); model.paste(it, plain: false) }
        .onTapGesture { model.selected = index }
        .contextMenu { contextMenu(it) }
        .draggable(it.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(it.kind.label): \(it.kind == .image ? String(localized: "Image") : it.preview)"))
        .accessibilityValue(Text("\(it.sourceName ?? "") \(Dump.relative(it.createdAt))\(it.pinned ? ", " + String(localized: "pinned") : "")\(it.looksSensitive ? ", " + String(localized: "looks like a secret") : "")"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(Text("Press Return to paste"))
    }

    @ViewBuilder
    private func contextMenu(_ it: Item) -> some View {
        Button("Paste") { PanelController.shared.hide(); model.paste(it, plain: false) }
        Button("Paste as Plain Text") { PanelController.shared.hide(); model.paste(it, plain: true) }
        Button("Copy") { model.copy(it); PanelController.shared.hide() }
        Button("Add to Paste Stack") { model.queue(it) }
        Divider()
        Button(it.pinned ? "Unpin" : "Pin") { Store.shared.setPinned(it.id, !it.pinned); model.refresh(keeping: it.id) }
        if it.kind == .file { Button("Show in Finder") { model.revealInFinder(it) } }
        if it.kind == .url, let u = URL(string: it.plain.trimmingCharacters(in: .whitespacesAndNewlines)) { Button("Open Link") { NSWorkspace.shared.open(u) } }
        if let b = it.sourceBundleID {
            Button(String(format: String(localized: "Forget everything from %@"), it.sourceName ?? b)) { _ = Store.shared.delete(bundleID: b); model.refresh() }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(it) }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↩", "Paste"); hint("⌘↩", "Plain"); hint("⇧↩", "Queue"); hint("⌘C", "Copy"); hint("⌘P", "Pin"); hint("⌘⌫", "Delete"); hint("esc", "Close")
            Button { Help.open(anchor: "keys") } label: { Image(systemName: "questionmark.circle") }.buttonStyle(.plain).foregroundStyle(.secondary).help("All shortcuts")
            Spacer()
            if !stack.isEmpty {
                Text(String(format: String(localized: "%lld queued · %@ pastes next"), stack.count, Hotkey.describe(.pasteNext)))
                    .font(.caption).foregroundStyle(Color.accentColor)
                Button { stack.clear() } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).help("Clear the paste stack")
            }
            if !Capabilities.accessibilityTrusted || !Prefs.autoPaste {
                Text("Copy only: press ⌘V after choosing").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    private func hint(_ key: String, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.caption.monospaced()).padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PreviewPane: View {
    @ObservedObject var model: PanelModel
    let item: Item?
    @State private var keyword = ""

    var body: some View {
        Group {
            if let item {
                VStack(alignment: .leading, spacing: 8) {
                    header(item)
                    if item.looksSensitive {
                        Label(String(format: String(localized: "Looks like it contains a %@. It stays on this Mac and is masked before any cloud request."),
                                     Redactor.Flag(rawValue: item.redactionFlags).labels.joined(separator: ", ")), systemImage: "exclamationmark.shield")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    content(item)
                    if item.pinned { keywordRow(item) }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("Select an item to preview it").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: item?.id) { _, _ in keyword = item?.keyword ?? "" }
        .onAppear { keyword = item?.keyword ?? "" }
    }

    private func header(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label(item.kind.label, systemImage: item.kind.symbol).font(.headline)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(item.sourceName ?? String(localized: "Unknown app")) · \(item.createdAt.formatted(date: .abbreviated, time: .shortened))" +
                 (item.useCount > 0 ? " · " + String(format: String(localized: "used %lld times"), item.useCount) : ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func content(_ item: Item) -> some View {
        switch item.kind {
        case .image:
            if let data = Store.shared.blob(item.blobHash), let img = NSImage(data: data) {
                Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Image data is missing.").foregroundStyle(.secondary)
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.filePaths, id: \.self) { p in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable().frame(width: 20, height: 20)
                            Text(p).font(.callout).textSelection(.enabled).lineLimit(2)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            ScrollView {
                Text(item.plain)
                    .font(item.kind == .html ? .callout.monospaced() : .callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func keywordRow(_ item: Item) -> some View {
        HStack {
            Image(systemName: "pin.fill").foregroundStyle(.secondary)
            TextField("Keyword for clipmac snip", text: $keyword)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.setKeyword(item, keyword) }
            Button("Save") { model.setKeyword(item, keyword) }
        }.font(.callout)
    }
}
