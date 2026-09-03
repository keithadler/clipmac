//  XCTest bridge: runs the in-module suites (Sources/ClipMac/Tests) so `swift test` and CI report
//  the same cases as `clipmac selftest`. Each suite is one XCTest method; each case is an activity.

import XCTest
@testable import ClipMac

final class SuiteTests: XCTestCase {
    @MainActor
    private func runSuite(_ name: String) {
        let results = TestKit.run(filter: name + "/")
        XCTAssertFalse(results.isEmpty, "suite \(name) has cases")
        for r in results {
            XCTContext.runActivity(named: "\(r.suite)/\(r.name)") { _ in
                for f in r.failures { XCTFail("\(r.suite)/\(r.name): \(f)") }
            }
        }
    }

    @MainActor func testRedactor() { runSuite("Redactor") }
    @MainActor func testStore() { runSuite("Store") }
    @MainActor func testCapture() { runSuite("Capture") }
    @MainActor func testPaster() { runSuite("Paster") }
    @MainActor func testCLI() { runSuite("CLI") }
    @MainActor func testAssist() { runSuite("Assist") }
    @MainActor func testMisc() { runSuite("Misc") }
}
