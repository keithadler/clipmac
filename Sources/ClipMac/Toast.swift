//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  A one-line note under the menu bar when something was deliberately not saved, so the refusal
//  rules read as a feature rather than a lost copy. Non-activating, fades out, rate-limited.

import AppKit
import SwiftUI

@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?
    private static var lastShown = Date.distantPast

    static func skipped(_ why: Monitor.Refusal) {
        guard Prefs.skipToasts else { return }
        if case .paused = why { return }   // the menu bar icon already says so, and pausing is deliberate
        show(String(localized: "Not saved: ") + why.description, symbol: "hand.raised.fill")
    }

    static func show(_ text: String, symbol: String = "info.circle") {
        guard Date().timeIntervalSince(lastShown) > 1.5 else { return }
        lastShown = Date()
        let view = HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(text).font(.callout)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.12)))
        .fixedSize()

        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let p = panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        p.contentView = host
        p.setContentSize(host.fittingSize)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.maxX - host.fittingSize.width - 16, y: f.maxY - host.fittingSize.height - 10))
        }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.15; p.animator().alphaValue = 1 }
        panel = p
        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.35; p.animator().alphaValue = 0 }) { p.orderOut(nil) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}
