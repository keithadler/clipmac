//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  A small test kit that runs in two places from one source: `clipmac selftest` (no Xcode needed)
//  and the XCTest bridge in Tests/ClipMacTests (CI, or any Mac with Xcode). Every case runs with an
//  isolated in-memory store and a throwaway defaults suite, so tests never touch real history.

import Foundation

final class T {
    private(set) var failures: [String] = []
    private(set) var checks = 0

    func check(_ condition: @autoclosure () -> Bool, _ what: String, file: StaticString = #fileID, line: UInt = #line) {
        checks += 1
        if !condition() { failures.append("\(what)  (\(file):\(line))") }
    }

    func equal<E: Equatable>(_ actual: E, _ expected: E, _ what: String, file: StaticString = #fileID, line: UInt = #line) {
        checks += 1
        if actual != expected { failures.append("\(what): got \(actual), expected \(expected)  (\(file):\(line))") }
    }

    func fail(_ what: String, file: StaticString = #fileID, line: UInt = #line) {
        checks += 1
        failures.append("\(what)  (\(file):\(line))")
    }

    /// Marks the case as skipped (counted, reported, not failed).
    var skipped: String?
    func skip(_ why: String) { skipped = why }
}

struct TestCase {
    let name: String
    let run: @MainActor (T) throws -> Void
}

struct TestSuite {
    let name: String
    let cases: [TestCase]
}

enum TestKit {
    static var suites: [TestSuite] {
        [RedactorSuite.suite, RedactorSuite.regressions, StoreSuite.suite, CaptureSuite.suite, MonitorSuite.suite, PasterSuite.suite, PanelSuite.suite,
         CLISuite.suite, AssistSuite.suite, CloudSuite.suite, UpdatesSuite.suite, TransformSuite.suite, MiscSuite.suite, PropertySuite.suite]
    }

    struct Result {
        let suite: String
        let name: String
        let failures: [String]
        let skipped: String?
        let checks: Int
        let ms: Double
        var passed: Bool { failures.isEmpty && skipped == nil }
    }

    /// Runs every case whose "Suite/name" contains the filter, each in isolation.
    @MainActor
    static func run(filter: String? = nil) -> [Result] {
        var out: [Result] = []
        for suite in suites {
            for c in suite.cases {
                let full = "\(suite.name)/\(c.name)"
                if let filter, !full.localizedCaseInsensitiveContains(filter) { continue }
                let t = T()
                let start = Date()
                isolated {
                    do { try c.run(t) } catch { t.fail("threw \(error)") }
                }
                out.append(Result(suite: suite.name, name: c.name, failures: t.failures, skipped: t.skipped, checks: t.checks,
                                  ms: Date().timeIntervalSince(start) * 1000))
            }
        }
        return out
    }

    /// Swaps the shared store for an in-memory one and the defaults for a fresh suite, then restores both.
    @MainActor
    static func isolated(_ body: () -> Void) {
        let savedStore = Store.shared
        let savedDefaults = Prefs.defaults
        let suiteName = "com.keithadler.clipmac.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        Store.shared = Store(inMemory: true)
        Prefs.defaults = defaults
        Assist.shared.invalidateCache()
        body()
        Assist.shared.invalidateCache()
        Store.shared = savedStore
        Prefs.defaults = savedDefaults
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// Prints results; exit code 0 when everything passed, 2 otherwise.
    static func report(_ results: [Result], json: Bool) -> Int32 {
        let failed = results.filter { !$0.failures.isEmpty }
        if json {
            print(Dump.json([
                "passed": results.filter(\.passed).count, "failed": failed.count, "skipped": results.filter { $0.skipped != nil }.count,
                "checks": results.reduce(0) { $0 + $1.checks },
                "results": results.map { ["suite": $0.suite, "name": $0.name, "failures": $0.failures, "skipped": $0.skipped ?? "", "ms": Int($0.ms)] },
            ]))
        } else {
            var lastSuite = ""
            for r in results {
                if r.suite != lastSuite { print(r.suite); lastSuite = r.suite }
                let mark = r.skipped != nil ? "–" : (r.failures.isEmpty ? "✓" : "✗")
                print(String(format: "  %@ %@ (%d checks, %.0f ms)%@", mark, r.name, r.checks, r.ms, r.skipped.map { " skipped: \($0)" } ?? ""))
                for f in r.failures { print("      \(f)") }
            }
            print("\(results.filter(\.passed).count) passed, \(failed.count) failed, \(results.filter { $0.skipped != nil }.count) skipped, \(results.reduce(0) { $0 + $1.checks }) checks")
        }
        return failed.isEmpty ? 0 : 2
    }

    static func list() {
        for s in suites { for c in s.cases { print("\(s.name)/\(c.name)") } }
    }

    // MARK: - Helpers shared by suites

    static func capture(_ s: String, kind: ItemKind = .text, app: String? = "com.example.app", name: String? = "Example",
                        blob: Data? = nil, blobType: String? = nil) -> Capture {
        Capture(kind: kind, plain: s, blobData: blob, blobType: blobType, sourceBundleID: app, sourceName: name, size: (blob?.count ?? 0) + s.utf8.count)
    }

    /// Runs the body with stdout sent to /dev/null (CLI commands print).
    static func silenced<R>(_ body: () -> R) -> R {
        fflush(stdout); fflush(stderr)
        let savedOut = dup(STDOUT_FILENO), savedErr = dup(STDERR_FILENO)
        let null = open("/dev/null", O_WRONLY)
        dup2(null, STDOUT_FILENO); dup2(null, STDERR_FILENO)
        let r = body()
        fflush(stdout); fflush(stderr)
        dup2(savedOut, STDOUT_FILENO); dup2(savedErr, STDERR_FILENO)
        close(savedOut); close(savedErr); close(null)
        return r
    }
}
