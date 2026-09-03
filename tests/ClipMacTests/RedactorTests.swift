import XCTest
@testable import ClipMac

final class RedactorTests: XCTestCase {
    func testAnthropicKeyIsFlaggedAndMasked() {
        let s = "export ANTHROPIC_API_KEY=sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdef"
        XCTAssertTrue(Redactor.flags(in: s).contains(.apiKey))
        let masked = Redactor.mask(s)
        XCTAssertFalse(masked.text.contains("sk-ant-"))
        XCTAssertTrue(masked.text.contains("[REDACTED"))
        XCTAssertTrue(masked.labels.contains("API KEY"))
    }

    func testJWT() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        XCTAssertTrue(Redactor.flags(in: "token: " + jwt).contains(.jwt))
        XCTAssertFalse(Redactor.mask(jwt).text.contains("eyJ"))
    }

    func testPrivateKeyBlock() {
        let pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIEow\n-----END RSA PRIVATE KEY-----"
        XCTAssertTrue(Redactor.flags(in: pem).contains(.privateKey))
        XCTAssertEqual(Redactor.mask(pem).text, "[REDACTED PRIVATE KEY]")
    }

    func testCardNumberNeedsLuhn() {
        XCTAssertTrue(Redactor.luhn("4111 1111 1111 1111"))
        XCTAssertTrue(Redactor.flags(in: "card 4111 1111 1111 1111").contains(.cardNumber))
        XCTAssertFalse(Redactor.flags(in: "order 4111 1111 1111 1112").contains(.cardNumber))
        XCTAssertFalse(Redactor.flags(in: "Invoice #4471 due Friday").contains(.cardNumber))
    }

    func testCredentialKeepsKeyMasksValue() {
        let m = Redactor.mask("password=hunter2hunter2")
        XCTAssertTrue(m.text.hasPrefix("password="))
        XCTAssertFalse(m.text.contains("hunter2"))
    }

    func testOrdinaryTextIsClean() {
        XCTAssertTrue(Redactor.flags(in: "meeting notes: ship the clipboard app next week").isEmpty)
        XCTAssertTrue(Redactor.flags(in: "https://example.com/docs/setup").isEmpty)
    }
}
