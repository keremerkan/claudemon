import Foundation
import Testing
@testable import Claudemon
@testable import ClaudemonCore

/// Verifies that `UsageStore` seeds last-good data from the App Group cache on
/// launch, so the menu bar shows instantly and a first-fetch stale-render does
/// not drop the store back to the blank `.loading` placeholder.
@MainActor
struct UsageStorePrimingTests {

    // MARK: - Helpers

    /// A per-test cache directory, removed when the test's suite instance goes.
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory(prefix: "claudemon-store-tests")
    }

    private func makeCache() -> SharedUsageCache {
        SharedUsageCache(baseDirectory: directory.url)
    }

    private func sampleReport() -> UsageReport {
        let session = UsageMetric(
            kind: .session, rawLabel: "Current session", percent: 27,
            resetDate: makeDate(2026, 6, 24, 2, 49), timezoneIdentifier: "Europe/Istanbul"
        )
        let weekAll = UsageMetric(
            kind: .weekAll, rawLabel: "Current week (all models)", percent: 29,
            resetDate: makeDate(2026, 6, 26, 9, 59, tz: "America/New_York"),
            timezoneIdentifier: "America/New_York"
        )
        return UsageReport(metrics: [session, weekAll], capturedAt: makeDate(2026, 6, 23, 12, 0))
    }

    // MARK: - Priming

    /// With a valid cached report, a freshly-started store exposes that report
    /// as last-good (and a calm stale-render state) BEFORE any live fetch runs.
    @Test func `Priming from cache seeds the last-good report`() {
        let writtenAt = makeDate(2026, 6, 23, 12, 1, 30)
        let cache = makeCache()
        let report = sampleReport()
        cache.write(CachedUsage(report: report, state: .ok, errorMessage: nil, writtenAt: writtenAt))

        let store = UsageStore(cache: cache)
        // Sanity: nothing seeded yet.
        #expect(store.lastGoodReport == nil)
        #expect(store.state == .loading)

        // Prime only (no refresh) — never spawns the real `claude` subprocess.
        store.primeFromCache()

        #expect(store.lastGoodReport == report, "Cached report must be exposed as last-good")
        #expect(store.state == .staleRender(report), "Primed state must be a calm stale-render")
        #expect(store.lastUpdated == report.capturedAt,
                "lastUpdated must reflect the report's own capture time, not the cache write time")
        #expect(store.lastUpdated != writtenAt,
                "lastUpdated must NOT be the cache write timestamp (which is the last failure time for stale caches)")
        #expect(store.errorMessage == nil, "Priming must never look like an error")
        #expect(!store.hasNoData)
    }

    /// Priming from a stale cache whose report was captured long ago must surface
    /// the OLD capture time as `lastUpdated`, so the existing stale-detection
    /// (`dataAge` > 10 min, driving the "· stale" footer hint) correctly fires.
    /// The cache's `writtenAt` here is "now" (it is stamped at the last failure),
    /// which must NOT be mistaken for a fresh update.
    @Test func `Priming from a stale cache reflects the old capture time`() throws {
        // Floor to whole seconds so the dates survive the cache's `.iso8601`
        // round-trip (which truncates sub-second precision) and compare exactly.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        // Report captured 30 minutes ago, but the stale cache was written "now"
        // (writeStale stamps writtenAt: Date() on the last failure).
        let oldCapture = now.addingTimeInterval(-30 * 60)
        let session = UsageMetric(
            kind: .session, rawLabel: "Current session", percent: 27,
            resetDate: nil, timezoneIdentifier: "Europe/Istanbul"
        )
        let report = UsageReport(metrics: [session], capturedAt: oldCapture)

        let cache = makeCache()
        cache.write(CachedUsage(report: report, state: .stale,
                                errorMessage: "Couldn't read usage", writtenAt: now))

        let store = UsageStore(cache: cache)
        store.primeFromCache()

        #expect(store.lastUpdated == oldCapture,
                "lastUpdated must be the report's old capture time, not the failure write time")
        let age = try #require(store.dataAge)
        #expect(age > 10 * 60, "Old primed data must be detected as stale (> 10 min)")
        #expect(store.calmFooterText(now: now) == "updated \(UsageFormatting.shortClockString(oldCapture)) · stale",
                "The stale footer hint must fire for genuinely old primed data")
    }

    /// With no cache present, priming is a no-op and the store stays loading.
    @Test func `Priming is a no-op when the cache is empty`() {
        let store = UsageStore(cache: makeCache()) // nothing written

        store.primeFromCache()

        #expect(store.state == .loading)
        #expect(store.lastGoodReport == nil)
        #expect(store.lastUpdated == nil)
    }

    /// Once primed, a first-fetch stale-render (`noMetricsFound`) must KEEP the
    /// primed data rather than dropping back to `.loading`. The non-nil
    /// `lastGoodReport` after priming is exactly what makes that branch hold.
    @Test func `Primed report survives the stale-render branch`() {
        let cache = makeCache()
        cache.write(CachedUsage(report: sampleReport(), state: .ok, errorMessage: nil, writtenAt: Date()))

        let store = UsageStore(cache: cache)
        store.primeFromCache()

        // The stale-render branch keeps last-good iff lastGoodReport != nil.
        #expect(store.lastGoodReport != nil, "Primed last-good guards against a drop to .loading")
    }

    /// Accounts without a session limit (Max plans) get no session line from
    /// the CLI. The all-models week must take over the menu bar, and the
    /// second bar must then show the per-model week, not the same limit again.
    @Test func `Without a session limit the all-models week is primary`() {
        let weekAll = UsageMetric(
            kind: .weekAll, rawLabel: "Current week (all models)", percent: 31,
            resetDate: makeDate(2026, 11, 19, 8, 59), timezoneIdentifier: "Europe/Istanbul"
        )
        let weekModel = UsageMetric(
            kind: .weekModel, rawLabel: "Current week (Fable)", percent: 53,
            resetDate: makeDate(2026, 11, 19, 8, 59), timezoneIdentifier: "Europe/Istanbul"
        )
        let report = UsageReport(metrics: [weekAll, weekModel], capturedAt: makeDate(2026, 11, 18, 10, 0))
        let cache = makeCache()
        cache.write(CachedUsage(report: report, state: .ok, errorMessage: nil, writtenAt: report.capturedAt))

        let store = UsageStore(cache: cache)
        #expect(store.primaryMetric == nil, "No data yet: no primary limit")
        #expect(store.hasSessionLimit, "Assume a session limit until a report says otherwise")
        store.primeFromCache()
        #expect(!store.hasSessionLimit)
        #expect(store.primaryMetric?.kind == .weekAll)
        #expect(store.primaryMetric?.percent == 31)
        store.menuBarWeekBarSource = .allModels
        #expect(store.menuBarWeekMetric?.kind == .weekModel,
                "The second bar must not repeat the all-models week")
    }
}
