import Foundation
import SwiftUI
import WidgetKit
import ClaudemonCore

/// The single source of truth for usage data. Owns the 60s polling timer,
/// performs an immediate refresh on launch, runs the subprocess off the main
/// thread, parses, and publishes state to all observing surfaces.
@MainActor
@Observable
final class UsageStore {

    enum State: Equatable {
        case loading                          // first load in progress, no data yet
        case loaded(UsageReport)              // fresh data this tick
        case staleRender(UsageReport)         // last-good kept; CLI returned no new
                                              // limit lines this cycle (NOT an error)
        case staleError(UsageReport, error: String) // last-good kept; real failure
        case error(String)                    // no data and a real error
    }

    /// A classified failure, used to drive distinct, friendly onboarding UI.
    enum Diagnostic: Equatable {
        case notInstalled   // claude binary not found anywhere → onboarding
        case notSignedIn    // claude present but not logged in / no subscription
        case other          // any other genuine error (timeout, launch, etc.)
    }

    private(set) var state: State = .loading
    private(set) var isRefreshing: Bool = false
    /// The current classified diagnostic, if the latest poll genuinely failed.
    /// nil while loading, fresh, or in a calm stale-render.
    private(set) var diagnostic: Diagnostic?

    /// Whether the floating widget is shown. Persisted in UserDefaults.
    var floatingEnabled: Bool {
        didSet {
            defaults.set(floatingEnabled, forKey: Self.floatingDefaultsKey)
            floatingChange?(floatingEnabled)
        }
    }

    /// Callback fired when the floating toggle changes (wired by the app).
    @ObservationIgnored var floatingChange: ((Bool) -> Void)?

    /// Whether the floating widget shows the compact (mini) form rather than the
    /// full form. Persisted in UserDefaults and toggled by a double-click on the
    /// panel.
    var floatingCompact: Bool {
        didSet {
            defaults.set(floatingCompact, forKey: Self.floatingCompactKey)
            floatingCompactChange?(floatingCompact)
        }
    }

    /// Callback fired when the compact form toggles (wired by the panel
    /// controller so it can resize the panel).
    @ObservationIgnored var floatingCompactChange: ((Bool) -> Void)?

    /// How the menu-bar label presents the session percent. Persisted as the
    /// case's rawValue. Defaults to `.iconAndText`.
    var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            defaults.set(menuBarDisplayMode.rawValue, forKey: Self.menuBarDisplayModeKey)
        }
    }

    // Sub-options for the `.bars` menu-bar style. Only consulted when that
    // style is active; persisted individually so they survive style switches.

    /// Show a weekly limit (see `menuBarWeekBarSource`) as a second bar
    /// under/next to the session bar.
    var menuBarShowsWeekBar: Bool {
        didSet {
            defaults.set(menuBarShowsWeekBar, forKey: Self.menuBarShowsWeekBarKey)
        }
    }

    /// Which weekly limit the second bar tracks (all models vs. per model).
    var menuBarWeekBarSource: MenuBarWeekBarSource {
        didSet {
            defaults.set(menuBarWeekBarSource.rawValue, forKey: Self.menuBarWeekBarSourceKey)
        }
    }

    // Menu-bar choices for accounts WITHOUT a session limit (Max plans), kept
    // apart from the session-account options above so neither overwrites the
    // other's.

    /// The weekly limit the menu bar shows first (text and bars) when there is
    /// no session limit.
    var menuBarMainWeekLimit: MenuBarWeekBarSource {
        didSet {
            defaults.set(menuBarMainWeekLimit.rawValue, forKey: Self.menuBarMainWeekLimitKey)
        }
    }

    /// Show the other weekly limit as a second bar when there is no session
    /// limit.
    var menuBarShowsSecondWeekBar: Bool {
        didSet {
            defaults.set(menuBarShowsSecondWeekBar, forKey: Self.menuBarShowsSecondWeekBarKey)
        }
    }

    /// Show the percent value(s) beside the bar(s).
    var menuBarShowsPercent: Bool {
        didSet {
            defaults.set(menuBarShowsPercent, forKey: Self.menuBarShowsPercentKey)
        }
    }

    /// Use vertical (bottom-up) bars instead of horizontal ones.
    var menuBarBarsVertical: Bool {
        didSet {
            defaults.set(menuBarBarsVertical, forKey: Self.menuBarBarsVerticalKey)
        }
    }

    /// Horizontal bars at half the standard width (ignored in vertical mode).
    var menuBarBarsHalfWidth: Bool {
        didSet {
            defaults.set(menuBarBarsHalfWidth, forKey: Self.menuBarBarsHalfWidthKey)
        }
    }

    /// Draw all usage-bar fills at their exact proportional width (straight
    /// edges, no minimum sliver) so small values are visually distinct.
    /// Persisted in the App Group defaults suite — not standard defaults — so
    /// the widget process sees it too; a direct reload nudges the widget to
    /// redraw promptly instead of waiting out its ~15-minute timeline policy.
    var preciseBars: Bool {
        didSet {
            SharedPreference.preciseBars.write(preciseBars)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Show what's left of each limit (100% → 0%) instead of what's used, on
    /// every surface: numbers, bars, rings and gauge icons. Shared with the
    /// widget through the App Group suite, like `preciseBars`.
    var showsRemaining: Bool {
        didSet {
            SharedPreference.showsRemaining.write(showsRemaining)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static let floatingDefaultsKey = "floatingWidgetEnabled"
    static let floatingCompactKey = "floatingWidgetCompact"
    static let menuBarDisplayModeKey = "menuBarDisplayMode"
    static let menuBarShowsWeekBarKey = "menuBarShowsWeekBar"
    static let menuBarWeekBarSourceKey = "menuBarWeekBarSource"
    static let menuBarMainWeekLimitKey = "menuBarMainWeekLimit"
    static let menuBarShowsSecondWeekBarKey = "menuBarShowsSecondWeekBar"
    static let menuBarShowsPercentKey = "menuBarShowsPercent"
    static let menuBarBarsVerticalKey = "menuBarBarsVertical"
    static let menuBarBarsHalfWidthKey = "menuBarBarsHalfWidth"
    private let pollInterval: TimeInterval = 60
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var currentTask: Task<Void, Never>?

    // Accelerated follow-up after a stale-render miss. The `claude` CLI refreshes
    // its limit lines on a ~1-minute internal cadence and returns a local-only
    // body in between; tight retries are proven useless and only burn quota. So
    // after a MISS we poll once sooner (~28s) to catch the next refresh window,
    // capped to a couple in a row, then fall back to the normal 60s cadence.
    private let acceleratedInterval: TimeInterval = 28
    private let maxAcceleratedPolls = 2
    @ObservationIgnored private var acceleratedPollsRemaining = 0
    @ObservationIgnored private var followUpTask: Task<Void, Never>?

    // Cold-start escalation. On a fresh launch with no last-good report, a
    // no-metrics body keeps us calmly in `.loading`. But if EVERY poll returns
    // no metrics (e.g. the `claude` CLI returns an empty body forever), we'd be
    // pinned at "Waiting for usage data…" indefinitely. Count consecutive cold
    // misses (no last-good) and, past a threshold, surface a gentle, recoverable
    // error instead. Any success or genuine failure resets the counter.
    private let maxColdNoMetrics = 5
    @ObservationIgnored private var consecutiveColdNoMetrics = 0
    // Wall-clock floor for cold escalation. The cold-miss count alone couples to
    // the accelerated-poll cadence (it can reach the threshold in ~88s), which
    // could falsely escalate a slow-but-healthy first load (the CLI refreshes its
    // limit lines on a ~45-60s window). Require at least this much real time
    // since polling began before surfacing a recoverable error. Fully
    // recoverable: a later applySuccess still clears state/diagnostic/counter.
    private let minColdEscalationDelay: TimeInterval = 120
    @ObservationIgnored private var startedAt: Date?

    // Widget reload rate-limiting. Apple throttles widget reloads (~40-70/day),
    // so we only reload when the data meaningfully changed OR at most every 15
    // minutes. The menu bar / floating panel stay genuinely live regardless.
    private let cache: SharedUsageCache
    private let defaults: UserDefaults
    private let minReloadInterval: TimeInterval = 15 * 60
    @ObservationIgnored private var lastReloadAt: Date?
    @ObservationIgnored private var lastReloadedSnapshot: [UsageMetric.Kind: Int] = [:]

    /// `cache` and `defaults` are injectable so tests can verify launch
    /// priming against a temp-directory cache (without the App Group
    /// entitlement) and settings against a throwaway defaults suite.
    /// Production uses the shared App Group cache and standard defaults.
    init(cache: SharedUsageCache = .shared, defaults: UserDefaults = .standard) {
        self.cache = cache
        self.defaults = defaults
        self.floatingEnabled = defaults.bool(forKey: Self.floatingDefaultsKey)
        self.floatingCompact = defaults.bool(forKey: Self.floatingCompactKey)
        let storedMode = defaults.string(forKey: Self.menuBarDisplayModeKey)
        self.menuBarDisplayMode = storedMode.flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .iconAndText
        self.menuBarShowsWeekBar = defaults.bool(forKey: Self.menuBarShowsWeekBarKey)
        let storedSource = defaults.string(forKey: Self.menuBarWeekBarSourceKey)
        self.menuBarWeekBarSource = storedSource.flatMap(MenuBarWeekBarSource.init(rawValue:)) ?? .allModels
        let storedMainLimit = defaults.string(forKey: Self.menuBarMainWeekLimitKey)
        self.menuBarMainWeekLimit = storedMainLimit.flatMap(MenuBarWeekBarSource.init(rawValue:)) ?? .allModels
        // The second weekly bar defaults ON (absent key reads nil, not false).
        self.menuBarShowsSecondWeekBar = (defaults.object(forKey: Self.menuBarShowsSecondWeekBarKey) as? Bool) ?? true
        // Percentages default ON (absent key reads nil, not false).
        self.menuBarShowsPercent = (defaults.object(forKey: Self.menuBarShowsPercentKey) as? Bool) ?? true
        self.menuBarBarsVertical = defaults.bool(forKey: Self.menuBarBarsVerticalKey)
        self.menuBarBarsHalfWidth = defaults.bool(forKey: Self.menuBarBarsHalfWidthKey)
        self.preciseBars = SharedPreference.preciseBars.read()
        self.showsRemaining = SharedPreference.showsRemaining.read()
    }

    // MARK: - Lifecycle

    func start() {
        // Stamp the polling start once so cold escalation can enforce a
        // wall-clock floor independent of the accelerated-poll cadence.
        if startedAt == nil { startedAt = Date() }
        // Seed last-good data from the cache BEFORE the first live fetch so the
        // UI shows instantly and a first-fetch stale-render keeps this data
        // instead of dropping back to the blank `.loading` placeholder.
        primeFromCache()
        // One-shot nudge across ALL widget kinds right after launch priming so a
        // widget that installed while the app was closed (and may be frozen on an
        // older snapshot) re-reads the now-canonical shared cache immediately,
        // instead of waiting for its own ~15-minute timeline policy. This is a
        // single reload at start, not part of the per-poll rate-limited path.
        WidgetCenter.shared.reloadAllTimelines()
        refresh()
        scheduleTimer()
    }

    /// Prime the store from the App Group cache on launch. Only acts from the
    /// initial `.loading` state (never clobbers live data) and only when the
    /// cache holds a usable report. This makes `lastGoodReport` non-nil before
    /// any fetch completes, so a subsequent `noMetricsFound` stale-render is
    /// kept as last-good rather than forced back to `.loading`.
    /// Internal (not private) so the launch-priming behaviour is unit-testable.
    func primeFromCache() {
        guard case .loading = state else { return }
        guard let cached = cache.read(), let report = cached.report else { return }
        state = .staleRender(report)
        // Push the primed content to the widget too. The rate-limit keys
        // "changed" off the metric snapshot, so this reloads only when the cache
        // content differs from what the widget was last told (e.g. on launch).
        reloadWidgetIfNeeded(for: report)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentTask?.cancel()
        currentTask = nil
        followUpTask?.cancel()
        followUpTask = nil
        acceleratedPollsRemaining = 0
        // Reset the cold-miss counter so a refresh cancelled mid-flight can't
        // leave a stray increment that carries across a sleep/wake cycle.
        consecutiveColdNoMetrics = 0
        // Clear the in-flight flag so a later start() is never permanently
        // blocked by a refresh that was cancelled mid-flight.
        isRefreshing = false
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Tolerance reduces wakeups / battery impact.
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Refresh

    func refresh() {
        // Don't pile up overlapping fetches.
        guard !isRefreshing else { return }
        isRefreshing = true

        // Run the whole fetch + parse off the main actor. resolveClaudePath()
        // and whichClaude() spawn a synchronous login shell, so they must not
        // execute on the main thread (would hang the menu-bar UI on first
        // launch / after wake). Only the result is marshalled back.
        currentTask = Task.detached(priority: .utility) { [weak self] in
            let result: Result<UsageReport, Error>
            do {
                result = .success(try UsageParser.parse(jsonData: try await UsageFetcher.fetchUsageJSON()))
            } catch {
                result = .failure(error)
            }
            await self?.finishRefresh(result)
        }
    }

    private func finishRefresh(_ result: Result<UsageReport, Error>) {
        // stop() cancelled this refresh and reset the in-flight flag itself.
        // The fetch still runs to its end, so drop the late result: it must
        // not touch state a newer refresh may already own.
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let report):
            applySuccess(report)
        case .failure(let parseError as UsageParseError) where parseError.isStaleRender:
            // SUCCESS body that simply lacked the limit lines this cycle.
            // Not a failure: keep last-good data, no alarming error.
            applyStaleRender()
        case .failure(let error):
            applyFailure(error)
        }
    }

    private func applySuccess(_ report: UsageReport) {
        // A genuine hit: cancel any accelerated follow-up and resume normal pace.
        acceleratedPollsRemaining = 0
        consecutiveColdNoMetrics = 0
        followUpTask?.cancel()
        followUpTask = nil

        state = .loaded(report)
        diagnostic = nil
        isRefreshing = false

        // Fire usage-limit alerts on genuinely fresh data only (never on
        // stale-render or error states, which reuse last-good data).
        NotificationManager.shared.evaluate(report)

        // Bridge to the widget via the App Group cache, then reload the widget
        // timeline only when something meaningfully changed or the rate-limit
        // window has elapsed.
        cache.writeSuccess(report)
        reloadWidgetIfNeeded(for: report)
    }

    /// The CLI returned a real body but without the limit lines (it only
    /// refreshes them on its own ~1-minute cadence). Keep last-good data and
    /// show a CALM state — never an error. Schedule a sooner follow-up poll to
    /// catch the next refresh window without hammering the CLI.
    private func applyStaleRender() {
        if let report = lastGoodReport {
            // Warm path: we have last-good data. Calm stale-render, unchanged.
            diagnostic = nil   // calm: not an error
            consecutiveColdNoMetrics = 0
            state = .staleRender(report)
            // Keep the cache "ok" with the last-good data; this isn't an error.
            // The report keeps its original capture time, so the widget's
            // "updated" line stays honest (no newer data this tick).
            cache.writeSuccess(report)
            // Reload on this warm path too, not only on applySuccess. The
            // snapshot-based rate-limit makes this a no-op when the content is
            // unchanged, so genuinely-new last-good data still reaches the widget
            // without spamming reloads.
            reloadWidgetIfNeeded(for: report)
        } else {
            // Cold path: no data yet (e.g. right after launch before the first
            // hit). Normally stay in a neutral loading/waiting state, NOT an
            // error. But if EVERY poll keeps returning no metrics we'd hang on
            // "Waiting…" forever, so escalate after a few consecutive misses to
            // a gentle, recoverable error. A later success clears it.
            consecutiveColdNoMetrics += 1
            // Escalate only when BOTH the miss count AND a wall-clock floor are
            // met, so a normal slow startup never falsely surfaces an error.
            let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
            if consecutiveColdNoMetrics >= maxColdNoMetrics,
               elapsed >= minColdEscalationDelay {
                let message = "Couldn't read usage. Try Refresh, or relaunch Claudemon."
                diagnostic = .other
                state = .error(message)
                cache.writeError()
            } else {
                diagnostic = nil   // calm: not an error yet
                state = .loading
            }
        }
        isRefreshing = false
        scheduleAcceleratedFollowUpIfNeeded()
    }

    private func applyFailure(_ error: Error) {
        consecutiveColdNoMetrics = 0
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        diagnostic = Self.classify(error)
        // Preserve last good data as a (real) error-stale, if we have any.
        if let report = lastGoodReport {
            state = .staleError(report, error: message)
            cache.writeStale(report)
        } else {
            state = .error(message)
            cache.writeError()
        }
        isRefreshing = false
        // Do not force a widget reload on transient failures; the widget keeps
        // showing its last-good cache and refreshes on its own timeline policy.
    }

    /// Map a fetch error to a user-facing diagnostic category.
    private static func classify(_ error: Error) -> Diagnostic {
        switch error as? UsageFetchError {
        case .claudeNotFound: return .notInstalled
        case .notSignedIn: return .notSignedIn
        default: return .other
        }
    }

    /// Schedule one sooner follow-up poll after a stale-render miss, capped so we
    /// don't accelerate indefinitely. A genuine hit resets the counter.
    private func scheduleAcceleratedFollowUpIfNeeded() {
        guard timer != nil else { return } // only while actively polling
        if acceleratedPollsRemaining == 0 {
            acceleratedPollsRemaining = maxAcceleratedPolls
        } else {
            acceleratedPollsRemaining -= 1
            guard acceleratedPollsRemaining > 0 else { return }
        }
        followUpTask?.cancel()
        followUpTask = Task { [weak self, acceleratedInterval] in
            // Cancellation (a hit, stop(), or a newer follow-up) ends the
            // sleep early; that is the expected way out, not an error.
            try? await Task.sleep(for: .seconds(acceleratedInterval))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Reload the widget timeline only if a percent changed or it has been at
    /// least `minReloadInterval` since the last reload (whichever comes first).
    private func reloadWidgetIfNeeded(for report: UsageReport) {
        let snapshot = Dictionary(uniqueKeysWithValues: report.metrics.map { ($0.kind, $0.percent) })
        let changed = snapshot != lastReloadedSnapshot
        let now = Date()
        let elapsedEnough = lastReloadAt.map { now.timeIntervalSince($0) >= minReloadInterval } ?? true

        guard changed || elapsedEnough else { return }

        WidgetCenter.shared.reloadAllTimelines()
        lastReloadAt = now
        lastReloadedSnapshot = snapshot
    }

    // MARK: - Derived accessors

    /// The last successfully parsed report, regardless of current state.
    var lastGoodReport: UsageReport? {
        switch state {
        case .loaded(let r), .staleRender(let r), .staleError(let r, _): return r
        case .loading, .error: return nil
        }
    }

    /// A genuine error message to surface in the error UI. nil for calm states
    /// (loaded / stale-render / loading) — those must NOT look like problems.
    var errorMessage: String? {
        switch state {
        case .error(let m), .staleError(_, let m): return m
        case .loading, .loaded, .staleRender: return nil
        }
    }

    /// True only for a REAL failure while showing last-good data (alarming UI).
    var isStaleError: Bool {
        if case .staleError = state { return true }
        return false
    }

    /// Claude Code isn't installed anywhere we can find → friendly onboarding.
    var isNotInstalled: Bool { diagnostic == .notInstalled }

    /// Claude is present but the user needs to sign in.
    var isNotSignedIn: Bool { diagnostic == .notSignedIn }

    /// When the shown data was captured: the last SUCCESSFUL fetch, never the
    /// time of a later failed one.
    var lastUpdated: Date? { lastGoodReport?.capturedAt }

    /// A muted " · stale" footer suffix once the shown data is over 10
    /// minutes old; empty before that. Never alarming.
    func staleHint(now: Date = Date()) -> String {
        guard let lastUpdated, now.timeIntervalSince(lastUpdated) > 10 * 60 else { return "" }
        return " · stale"
    }

    /// The headline limit for the floating window (see `UsageReport.primary`).
    var primaryMetric: UsageMetric? {
        lastGoodReport?.primary
    }

    /// False when the account has no session limit (the CLI reports none, as
    /// on Max plans). True until the first report lands.
    var hasSessionLimit: Bool {
        lastGoodReport.map { $0.session != nil } ?? true
    }

    /// The limit the menu bar shows first (its percent, or the first bar): the
    /// session, or without one the user's `menuBarMainWeekLimit`, falling back
    /// to the report's primary if that limit is missing from the report.
    var menuBarPrimaryMetric: UsageMetric? {
        guard let report = lastGoodReport else { return nil }
        if let session = report.session { return session }
        return report.metric(menuBarMainWeekLimit.metricKind) ?? report.primary
    }

    /// The bar graph's second bar, or nil when the user hides it. With a
    /// session limit: the chosen weekly limit (`menuBarShowsWeekBar` /
    /// `menuBarWeekBarSource`). Without one: the weekly limit that isn't the
    /// main one (`menuBarShowsSecondWeekBar`).
    var menuBarSecondMetric: UsageMetric? {
        guard let report = lastGoodReport, let primary = menuBarPrimaryMetric else { return nil }
        if primary.kind == .session {
            return menuBarShowsWeekBar ? report.metric(menuBarWeekBarSource.metricKind) : nil
        }
        guard menuBarShowsSecondWeekBar else { return nil }
        return report.metrics.first { $0.kind != .session && $0.kind != primary.kind }
    }

    /// The percent to show for a used percentage, per `showsRemaining`.
    func shownPercent(_ used: Int) -> Int {
        UsageDisplay.percent(used, remaining: showsRemaining)
    }

    /// The gauge icon for the menu bar's main limit, shared by the menu-bar
    /// label and the panel header.
    var menuBarGaugeSymbol: String {
        UsageGauge.symbolName(for: menuBarPrimaryMetric.map { shownPercent($0.percent) })
    }

    /// Settings label for the second weekly bar without a session limit: the
    /// weekly limit that isn't the main one.
    var secondWeekLimitName: String {
        menuBarMainWeekLimit == .allModels ? weekModelName : "All models"
    }

    /// Settings label for the per-model weekly source: the model name Anthropic
    /// currently reports there ("Fable"), or a generic fallback before the
    /// first report lands.
    var weekModelName: String {
        lastGoodReport?.weekModel?.shortLabel ?? UsageMetric.Kind.weekModel.shortName
    }
}
