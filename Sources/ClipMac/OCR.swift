//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  Text in captured images, recognised on-device with Vision and stored as the item's searchable
//  text, so screenshots turn up in word, substring and meaning searches. Runs after capture.

import Foundation
import AppKit
import Vision

enum OCR {
    private static let queue = DispatchQueue(label: "com.keithadler.clipmac.ocr", qos: .utility)

    static func recognizeSoon(_ item: Item) {
        guard Prefs.ocrImages, item.kind == .image, let hash = item.blobHash else { return }
        let store = Store.shared
        queue.async {
            guard let data = store.blob(hash), let text = recognize(data), !text.isEmpty else { return }
            store.setPlain(item.id, text, preview: String(localized: "Image: ") + Item.makePreview(text, limit: 100))
            Assist.shared.indexSoon()
            DispatchQueue.main.async { NotificationCenter.default.post(name: .clipHistoryChanged, object: nil) }
        }
    }

    /// Recognised lines joined with newlines, or nil when Vision found nothing. Synchronous.
    static func recognize(_ data: Data) -> String? {
        guard let image = NSImage(data: data), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
