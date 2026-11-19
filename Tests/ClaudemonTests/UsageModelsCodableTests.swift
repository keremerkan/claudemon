import Foundation
import Testing
@testable import ClaudemonCore

struct UsageModelsCodableTests {

    /// JSONEncoder/Decoder mirroring SharedUsageCache (iso8601 dates).
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - UsageMetric

    @Test func `Usage metric round-trip preserves all fields`() throws {
        let metric = UsageMetric(
            kind: .session,
            rawLabel: "Current session",
            percent: 27,
            resetDate: makeDate(2026, 6, 24, 2, 49, 30, tz: "Europe/Istanbul"),
            timezoneIdentifier: "Europe/Istanbul"
        )

        let data = try encoder.encode(metric)
        let decoded = try decoder.decode(UsageMetric.self, from: data)

        #expect(decoded.kind == .session)
        #expect(decoded.rawLabel == "Current session")
        #expect(decoded.percent == 27)
        #expect(decoded.resetDate == metric.resetDate)
        #expect(decoded.timezoneIdentifier == "Europe/Istanbul")
        #expect(decoded.timezone == TimeZone(identifier: "Europe/Istanbul"))
        #expect(decoded == metric)
    }

    @Test func `Usage metric nil date and timezone round-trip`() throws {
        let metric = UsageMetric(
            kind: .weekModel,
            rawLabel: "Current week (Fable)",
            percent: 0,
            resetDate: nil,
            timezoneIdentifier: nil
        )

        let data = try encoder.encode(metric)
        let decoded = try decoder.decode(UsageMetric.self, from: data)

        #expect(decoded.resetDate == nil)
        #expect(decoded.timezoneIdentifier == nil)
        #expect(decoded.timezone == nil)
        #expect(decoded == metric)
    }

    // MARK: - UsageReport

    @Test func `Usage report round-trip preserves dates and timezones`() throws {
        let report = UsageReport(
            metrics: [
                UsageMetric(kind: .session, rawLabel: "s", percent: 27,
                            resetDate: makeDate(2026, 6, 24, 2, 49, tz: "Europe/Istanbul"),
                            timezoneIdentifier: "Europe/Istanbul"),
                UsageMetric(kind: .weekAll, rawLabel: "wa", percent: 29,
                            resetDate: makeDate(2026, 6, 26, 9, 59, tz: "America/New_York"),
                            timezoneIdentifier: "America/New_York"),
                UsageMetric(kind: .weekModel, rawLabel: "wm", percent: 2,
                            resetDate: makeDate(2026, 6, 26, 10, 0, tz: "Asia/Tokyo"),
                            timezoneIdentifier: "Asia/Tokyo"),
            ],
            capturedAt: makeDate(2026, 6, 23, 12, 0, tz: "Europe/Istanbul")
        )

        let data = try encoder.encode(report)
        let decoded = try decoder.decode(UsageReport.self, from: data)

        #expect(decoded.capturedAt == report.capturedAt)
        #expect(decoded.metrics.count == 3)
        #expect(decoded.session?.resetDate == report.session?.resetDate)
        #expect(decoded.weekAll?.timezoneIdentifier == "America/New_York")
        #expect(decoded.weekModel?.timezoneIdentifier == "Asia/Tokyo")
        #expect(decoded == report)
    }

    @Test func `Cached usage round-trip`() throws {
        let report = UsageReport(
            metrics: [
                UsageMetric(kind: .session, rawLabel: "s", percent: 50,
                            resetDate: makeDate(2026, 6, 24, 2, 49, tz: "Europe/Istanbul"),
                            timezoneIdentifier: "Europe/Istanbul"),
            ],
            capturedAt: makeDate(2026, 6, 23, 12, 0, tz: "Europe/Istanbul")
        )
        let payload = CachedUsage(
            report: report,
            state: .stale,
            errorMessage: "network down",
            writtenAt: makeDate(2026, 6, 23, 22, 30, 15, tz: "Europe/Istanbul")
        )

        let data = try encoder.encode(payload)
        let decoded = try decoder.decode(CachedUsage.self, from: data)

        #expect(decoded.state == .stale)
        #expect(decoded.errorMessage == "network down")
        #expect(decoded.writtenAt == payload.writtenAt)
        #expect(decoded.report == report)
    }

    // MARK: - Primary / secondary limits

    private func metric(_ kind: UsageMetric.Kind, _ label: String, _ percent: Int) -> UsageMetric {
        UsageMetric(kind: kind, rawLabel: label, percent: percent, resetDate: nil, timezoneIdentifier: nil)
    }

    /// With a session limit, the session is primary and both weeks follow.
    @Test func `Primary is the session when reported`() {
        let report = UsageReport(metrics: [
            metric(.session, "Current session", 12),
            metric(.weekAll, "Current week (all models)", 31),
            metric(.weekModel, "Current week (Fable)", 53),
        ], capturedAt: Date())
        #expect(report.primary?.kind == .session)
        #expect(report.secondary.map(\.kind) == [.weekAll, .weekModel])
    }

    /// Max plans have no session limit (no session line): the all-models week
    /// becomes primary and only the per-model week follows.
    @Test func `Primary falls back to the all-models week without a session`() {
        let report = UsageReport(metrics: [
            metric(.weekAll, "Current week (all models)", 31),
            metric(.weekModel, "Current week (Fable)", 53),
        ], capturedAt: Date())
        #expect(report.primary?.kind == .weekAll)
        #expect(report.secondary.map(\.kind) == [.weekModel])
        #expect(report.primary?.shortLabel == "Week")
        #expect(report.secondary.first?.shortLabel == "Fable")
    }

    @Test func `Short date string uses the metric's timezone`() {
        // 2026-11-18 22:30 UTC is already Nov 19 in Istanbul (UTC+3).
        let date = Date(timeIntervalSince1970: 1_795_041_000)
        #expect(UsageFormatting.shortDateString(date, timeZone: TimeZone(identifier: "UTC")) == "Nov 18")
        #expect(UsageFormatting.shortDateString(date, timeZone: TimeZone(identifier: "Europe/Istanbul")) == "Nov 19")
    }

    // MARK: - Gauge icon

    /// The needle is the nearest of SF Symbols' 0/33/50/67/100 positions;
    /// these cases sit on both sides of each midpoint.
    @Test(arguments: [
        (nil, 0), (-5, 0), (0, 0), (16, 0),
        (17, 33), (41, 33),
        (42, 50), (58, 50),
        (59, 67), (83, 67),
        (84, 100), (100, 100), (130, 100),
    ] as [(Int?, Int)])
    func `Gauge needle is the nearest step`(percent: Int?, step: Int) {
        #expect(UsageGauge.symbolName(for: percent) == "gauge.with.dots.needle.\(step)percent")
    }

    // MARK: - Remaining display

    @Test(arguments: [
        (0, 0, 100), (27, 27, 73), (100, 100, 0),
        (-5, 0, 100), (130, 100, 0),   // out-of-range input clamps first
    ])
    func `Shown percent counts up or down`(used: Int, shownUsed: Int, shownLeft: Int) {
        #expect(UsageDisplay.percent(used, remaining: false) == shownUsed)
        #expect(UsageDisplay.percent(used, remaining: true) == shownLeft)
    }

    @Test func `Spoken percent names its direction`() {
        #expect(UsageDisplay.spoken(27, remaining: false) == "27 percent used")
        #expect(UsageDisplay.spoken(27, remaining: true) == "73 percent left")
    }

    @Test func `Reset hint names a clock time for sessions and a date for weeks`() {
        let reset = makeDate(2026, 11, 26, 8, 59)
        func metric(_ kind: UsageMetric.Kind) -> UsageMetric {
            UsageMetric(kind: kind, rawLabel: "", percent: 0, resetDate: reset, timezoneIdentifier: "Europe/Istanbul")
        }
        #expect(UsageFormatting.resetHint(for: metric(.session)) == "resets at 08:59")
        #expect(UsageFormatting.resetHint(for: metric(.weekAll)) == "resets Nov 26")
        #expect(UsageFormatting.resetHint(for: UsageMetric(kind: .session, rawLabel: "", percent: 0,
                                                           resetDate: nil, timezoneIdentifier: nil)) == nil)
    }
}
