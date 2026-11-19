import Foundation
import Testing
@testable import ClaudemonCore

struct SharedUsageCacheTests {

    // MARK: - Helpers

    /// A per-test cache directory, removed when the test's suite instance goes.
    private let directory: TemporaryDirectory
    private let cache: SharedUsageCache
    private let fileURL: URL

    init() throws {
        directory = try TemporaryDirectory(prefix: "claudemon-cache-tests")
        cache = SharedUsageCache(baseDirectory: directory.url)
        fileURL = directory.url.appendingPathComponent("usage-cache.json", conformingTo: .json)
    }

    /// A full report with all three metrics, dates, and distinct timezones.
    private func sampleReport() -> UsageReport {
        let session = UsageMetric(
            kind: .session,
            rawLabel: "Current session",
            percent: 27,
            resetDate: makeDate(2026, 6, 24, 2, 49, tz: "Europe/Istanbul"),
            timezoneIdentifier: "Europe/Istanbul"
        )
        let weekAll = UsageMetric(
            kind: .weekAll,
            rawLabel: "Current week (all models)",
            percent: 29,
            resetDate: makeDate(2026, 6, 26, 9, 59, tz: "America/New_York"),
            timezoneIdentifier: "America/New_York"
        )
        let weekModel = UsageMetric(
            kind: .weekModel,
            rawLabel: "Current week (Fable)",
            percent: 2,
            resetDate: makeDate(2026, 6, 26, 10, 0, tz: "Asia/Tokyo"),
            timezoneIdentifier: "Asia/Tokyo"
        )
        return UsageReport(
            metrics: [session, weekAll, weekModel],
            capturedAt: makeDate(2026, 6, 23, 12, 0, tz: "Europe/Istanbul")
        )
    }

    // MARK: - Round-trip (write → read)

    @Test func `Successful write round-trip preserves all fields`() throws {
        let report = sampleReport()

        cache.writeSuccess(report)
        let cached = try #require(cache.read(), "Reading back a freshly-written cache must succeed")

        #expect(cached.state == .ok)

        let readReport = try #require(cached.report)
        #expect(readReport.metrics.count == 3)
        #expect(readReport.metrics.map(\.kind) == [.session, .weekAll, .weekModel])

        // Percents
        #expect(readReport.session?.percent == 27)
        #expect(readReport.weekAll?.percent == 29)
        #expect(readReport.weekModel?.percent == 2)

        // Reset dates (compared against the original report's dates)
        #expect(readReport.session?.resetDate == report.session?.resetDate)
        #expect(readReport.weekAll?.resetDate == report.weekAll?.resetDate)
        #expect(readReport.weekModel?.resetDate == report.weekModel?.resetDate)

        // Timezone identifiers
        #expect(readReport.session?.timezoneIdentifier == "Europe/Istanbul")
        #expect(readReport.weekAll?.timezoneIdentifier == "America/New_York")
        #expect(readReport.weekModel?.timezoneIdentifier == "Asia/Tokyo")

        // Whole-report equality (covers rawLabel + capturedAt too)
        #expect(readReport == report)
    }

    @Test func `Write state is preserved across the round-trip`() throws {
        let report = sampleReport()

        cache.writeStale(report)
        let cached = try #require(cache.read())

        #expect(cached.state == .stale, "State flag must survive the round-trip")
        #expect(cached.report == report)
    }

    @Test func `Error write has a nil report and error state`() throws {
        cache.writeError()
        let cached = try #require(cache.read())

        #expect(cached.state == .error)
        #expect(cached.report == nil, "An error write should carry no report")
    }

    @Test func `A write overwrites the previous payload`() throws {
        cache.writeError()
        cache.writeSuccess(sampleReport())

        let cached = try #require(cache.read())
        #expect(cached.state == .ok, "Latest atomic write should win")
        #expect(cached.report != nil)
    }

    // MARK: - Empty / missing cache

    @Test func `Reading a missing cache returns nil`() {
        // Fresh temp dir, nothing written yet.
        #expect(cache.read() == nil, "Missing cache file must return nil, not crash")
    }

    @Test func `Reading after the file is removed returns nil`() throws {
        cache.writeSuccess(sampleReport())
        #expect(cache.read() != nil)

        // Remove everything in the temp dir, then read again.
        for url in try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }
        #expect(cache.read() == nil, "Reading after the file is gone must return nil")
    }

    // MARK: - Unreadable file contents

    @Test(arguments: [
        ("{ this is not valid json ]", "Malformed JSON must decode to nil, not crash"),
        // Syntactically valid JSON, but not a CachedUsage.
        (#"{"unexpected":"shape"}"#, "Valid-but-wrong-shape JSON must decode to nil, not crash"),
        ("", "An empty cache file must return nil, not crash"),
    ])
    func `Unreadable file contents return nil`(contents: String, reason: String) throws {
        try Data(contents.utf8).write(to: fileURL)
        #expect(cache.read() == nil, Comment(rawValue: reason))
    }
}
