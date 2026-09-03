//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  What this Mac and this permission set allow. Every optional feature checks here before showing
//  a control, so nothing in the UI is a dead button.

import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

enum Capabilities {
    /// Accessibility permission: required only for auto-paste (synthesizing ⌘V). Copy-only works without it.
    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// A password field has focus somewhere (Terminal with a sudo prompt, a browser password box, …).
    static var secureInputActive: Bool { IsSecureEventInputEnabled() }

    /// nil when the check couldn't run. `fdesetup status` needs no privileges.
    static var fileVaultOn: Bool? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
        p.arguments = ["status"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if out.contains("FileVault is On") { return true }
        if out.contains("FileVault is Off") { return false }
        return nil
    }

    /// Tier 1: on-device word embeddings ship with macOS for a handful of languages.
    static var embeddingLanguage: NLLanguage {
        let code = Locale.preferredLanguages.first?.prefix(2) ?? "en"
        return code == "es" ? .spanish : .english
    }
    static var sentenceEmbeddingAvailable: Bool { NLEmbedding.wordEmbedding(for: embeddingLanguage) != nil }

    /// Tier 2: Apple's on-device model. macOS 26+, Apple Intelligence enabled, supported hardware.
    static var onDeviceModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var onDeviceModelNote: String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return String(localized: "Apple's on-device model is ready. Nothing leaves this Mac.")
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return String(localized: "This Mac can't run Apple's on-device model.")
                case .appleIntelligenceNotEnabled: return String(localized: "Turn on Apple Intelligence in System Settings to use the on-device model.")
                case .modelNotReady: return String(localized: "Apple's on-device model is still downloading.")
                @unknown default: return String(localized: "Apple's on-device model isn't available.")
                }
            }
        }
        #endif
        return String(localized: "The on-device model needs macOS 26 or later.")
    }

    static var appVersion: String {
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
        var url = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        while url.path != "/" {
            // Only Clip's own bundle counts: under XCTest the binary lives inside Xcode.app.
            if url.pathExtension == "app", let b = Bundle(url: url), b.bundleIdentifier == "com.keithadler.clipmac",
               let v = b.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
            url = url.deletingLastPathComponent()
        }
        return "dev"
    }
}
