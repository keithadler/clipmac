import XCTest
@testable import ClipMac

final class StoreTests: XCTestCase {
    private func cap(_ s: String, kind: ItemKind = .text, app: String? = "com.example.app") -> Capture {
        Capture(kind: kind, plain: s, blobData: nil, blobType: nil, sourceBundleID: app, sourceName: "Example", size: s.utf8.count)
    }

    func testInsertSearchAndDedup() {
        let store = Store(inMemory: true)
        let a = store.insert(cap("Invoice #4471 for the Woodland project is due Friday"))
        _ = store.insert(cap("recipe: two eggs, flour, milk"))
        XCTAssertEqual(store.count(), 2)
        let again = store.insert(cap("Invoice #4471 for the Woodland project is due Friday"))
        XCTAssertEqual(again.id, a.id, "identical content bumps the existing row instead of adding one")
        XCTAssertEqual(store.count(), 2)
        XCTAssertEqual(store.item(atPosition: 1)?.id, a.id, "the bumped row is newest")

        XCTAssertEqual(store.search("invoice").map(\.id), [a.id])
        XCTAssertEqual(store.search("Wood").first?.id, a.id, "prefix token match")
        XCTAssertEqual(store.search("471").first?.id, a.id, "short queries are substring matches")
        XCTAssertTrue(store.search("pancake").isEmpty)
    }

    func testPinsSnippetsAndRetention() {
        let store = Store(inMemory: true)
        let sig = store.insert(cap("Keith Adler\nkeith@example.com"))
        store.setPinned(sig.id, true, keyword: "sig")
        XCTAssertEqual(store.snippet(keyword: "SIG")?.id, sig.id)
        for i in 0..<20 { _ = store.insert(cap("item \(i)")) }
        XCTAssertEqual(store.count(), 21)
        let removed = store.enforceRetention(days: 30, maxItems: 5, maxBytes: 1 << 30)
        XCTAssertEqual(removed, 15)
        XCTAssertEqual(store.count(), 6, "five newest plus the pinned one")
        XCTAssertNotNil(store.get(sig.id), "pinned items survive retention")
    }

    func testForgetByAppAndSensitiveFlag() {
        let store = Store(inMemory: true)
        _ = store.insert(cap("token: sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", app: "com.other"))
        _ = store.insert(cap("plain text"))
        XCTAssertTrue(store.all().first { $0.sourceBundleID == "com.other" }!.looksSensitive)
        XCTAssertEqual(store.delete(bundleID: "com.other"), 1)
        XCTAssertEqual(store.count(), 1)
        store.wipe()
        XCTAssertEqual(store.count(), 0)
    }

    func testVectorsRoundTrip() {
        let store = Store(inMemory: true)
        let it = store.insert(cap("hello"))
        store.setVector(it.id, model: "t", [0.1, 0.2, 0.3])
        XCTAssertEqual(store.vector(for: it.id, model: "t")!, [0.1, 0.2, 0.3])
        XCTAssertTrue(store.itemsMissingVectors(model: "t").isEmpty)
        XCTAssertEqual(store.itemsMissingVectors(model: "other").count, 1)
    }
}
