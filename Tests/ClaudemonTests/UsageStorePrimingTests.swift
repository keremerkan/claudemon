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

    /// A per-test cache directory and settings suite, removed when the
    /// test's suite instance goes.
    private let directory: TemporaryDirectory
    private let settings = TestDefaults()

    init() throws {
        directory = try TemporaryDirectory(prefix: "claudemon-store-tests")
    }

    private func makeCache() -> SharedUsageCache {
        SharedUsageCache(baseDirectory: directory.url)
    }

    /// A store on this test's cache and clean settings.
    private func makeStore(_ cache: SharedUsageCache) -> UsageStore {
        UsageStore(cache: cache, defaults: settings.defaults)
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
        let cache = makeCache()
        let report = sampleReport()
        cache.writeSuccess(report)

        let store = makeStore(cache)
        // Sanity: nothing seeded yet.
        #expect(store.lastGoodReport == nil)
        #expect(store.state == .loading)

        // Prime only (no refresh) — never spawns the real `claude` subprocess.
        store.primeFromCache()

        #expect(store.lastGoodReport == report, "Cached report must be exposed as last-good")
        #expect(store.state == .staleRender(report), "Primed state must be a calm stale-render")
        #expect(store.lastUpdated == report.capturedAt,
                "lastUpdated must reflect the report's own capture time, not the cache write time")
        #expect(store.errorMessage == nil, "Priming must never look like an error")
    }

    /// Priming from a stale cache whose report was captured long ago must surface
    /// the OLD capture time as `lastUpdated`, so the stale detection
    /// (`staleHint`, the "· stale" footer suffix past 10 minutes) fires.
    /// The cache file itself was written just now (at the last failure), which
    /// must NOT be mistaken for a fresh update.
    @Test func `Priming from a stale cache reflects the old capture time`() {
        // Floor to whole seconds so the dates survive the cache's `.iso8601`
        // round-trip (which truncates sub-second precision) and compare exactly.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        // Report captured 30 minutes ago, but the stale cache is written now.
        let oldCapture = now.addingTimeInterval(-30 * 60)
        let session = UsageMetric(
            kind: .session, rawLabel: "Current session", percent: 27,
            resetDate: nil, timezoneIdentifier: "Europe/Istanbul"
        )
        let report = UsageReport(metrics: [session], capturedAt: oldCapture)

        let cache = makeCache()
        cache.writeStale(report)

        let store = makeStore(cache)
        store.primeFromCache()

        #expect(store.lastUpdated == oldCapture,
                "lastUpdated must be the report's old capture time, not the failure write time")
        #expect(store.staleHint(now: now) == " · stale",
                "The stale footer hint must fire for genuinely old primed data")
        #expect(store.staleHint(now: oldCapture.addingTimeInterval(10 * 60)).isEmpty,
                "Data exactly 10 minutes old is not stale yet")
    }

    /// With no cache present, priming is a no-op and the store stays loading.
    @Test func `Priming is a no-op when the cache is empty`() {
        let store = makeStore(makeCache()) // nothing written

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
        cache.writeSuccess(sampleReport())

        let store = makeStore(cache)
        store.primeFromCache()

        // The stale-render branch keeps last-good iff lastGoodReport != nil.
        #expect(store.lastGoodReport != nil, "Primed last-good guards against a drop to .loading")
    }

    // MARK: - Menu bar limits

    /// A store primed with a report holding the given limits (31% all models,
    /// 53% Fable, and a 12% session when `withSession`).
    private func primedStore(withSession: Bool, includesModelWeek: Bool = true) -> UsageStore {
        func metric(_ kind: UsageMetric.Kind, _ label: String, _ percent: Int) -> UsageMetric {
            UsageMetric(kind: kind, rawLabel: label, percent: percent,
                        resetDate: makeDate(2026, 11, 19, 8, 59), timezoneIdentifier: "Europe/Istanbul")
        }
        var metrics = [metric(.weekAll, "Current week (all models)", 31)]
        if withSession { metrics.insert(metric(.session, "Current session", 12), at: 0) }
        if includesModelWeek { metrics.append(metric(.weekModel, "Current week (Fable)", 53)) }
        let report = UsageReport(metrics: metrics, capturedAt: makeDate(2026, 11, 18, 10, 0))
        let cache = makeCache()
        cache.writeSuccess(report)
        let store = makeStore(cache)
        store.primeFromCache()
        return store
    }

    /// With a session limit the session leads, and the second bar follows the
    /// "Weekly bar" checkbox and its source picker (off by default).
    @Test func `Session accounts: session first, weekly bar opt-in`() {
        let store = primedStore(withSession: true)
        #expect(store.hasSessionLimit)
        #expect(store.menuBarPrimaryMetric?.kind == .session)
        #expect(store.menuBarSecondMetric == nil, "The weekly bar is off by default")

        store.menuBarShowsWeekBar = true
        #expect(store.menuBarSecondMetric?.kind == .weekAll)
        store.menuBarWeekBarSource = .perModel
        #expect(store.menuBarSecondMetric?.kind == .weekModel)

        // The Max-only choices must not affect a session account.
        store.menuBarMainWeekLimit = .perModel
        #expect(store.menuBarPrimaryMetric?.kind == .session)
    }

    /// Accounts without a session limit (Max plans) get no session line from
    /// the CLI. By default the all-models week leads and the Fable week shows
    /// as the second bar; the user can swap them or hide the second bar.
    @Test func `No session limit: main weekly limit and second bar`() {
        let empty = makeStore(makeCache())
        #expect(empty.menuBarPrimaryMetric == nil, "No data yet: no primary limit")
        #expect(empty.hasSessionLimit, "Assume a session limit until a report says otherwise")

        let store = primedStore(withSession: false)
        #expect(!store.hasSessionLimit)
        #expect(store.menuBarPrimaryMetric?.kind == .weekAll)
        #expect(store.menuBarPrimaryMetric?.percent == 31)
        #expect(store.menuBarSecondMetric?.kind == .weekModel, "The second bar is on by default")
        #expect(store.secondWeekLimitName == "Fable")

        store.menuBarMainWeekLimit = .perModel
        #expect(store.menuBarPrimaryMetric?.kind == .weekModel)
        #expect(store.menuBarSecondMetric?.kind == .weekAll)
        #expect(store.secondWeekLimitName == "All models")

        store.menuBarShowsSecondWeekBar = false
        #expect(store.menuBarSecondMetric == nil)
        #expect(store.menuBarPrimaryMetric?.kind == .weekModel, "Hiding the second bar keeps the main one")
    }

    /// A chosen main limit missing from the report falls back to the report's
    /// primary instead of leaving the menu bar empty.
    @Test func `Main limit falls back when the chosen limit is missing`() {
        let store = primedStore(withSession: false, includesModelWeek: false)
        store.menuBarMainWeekLimit = .perModel
        #expect(store.menuBarPrimaryMetric?.kind == .weekAll)
        #expect(store.menuBarSecondMetric == nil, "No other weekly limit to show")
    }

    /// The new choices persist in the injected defaults across store instances.
    @Test func `No-session menu bar choices persist`() {
        let store = makeStore(makeCache())
        store.menuBarMainWeekLimit = .perModel
        store.menuBarShowsSecondWeekBar = false

        let reloaded = makeStore(makeCache())
        #expect(reloaded.menuBarMainWeekLimit == .perModel)
        #expect(!reloaded.menuBarShowsSecondWeekBar)
    }

    @Test func `Floating form defaults to rings and persists`() {
        let store = makeStore(makeCache())
        #expect(store.floatingForm == .rings)
        store.floatingForm = .slim

        #expect(makeStore(makeCache()).floatingForm == .slim)
    }

    @Test func `Legacy compact setting becomes the mini form`() {
        settings.defaults.set(true, forKey: "floatingWidgetCompact")
        #expect(makeStore(makeCache()).floatingForm == .mini)
    }

    @Test func `Stored form wins over the legacy compact setting`() {
        settings.defaults.set(true, forKey: "floatingWidgetCompact")
        settings.defaults.set("slim", forKey: UsageStore.floatingFormKey)
        #expect(makeStore(makeCache()).floatingForm == .slim)
    }
}
