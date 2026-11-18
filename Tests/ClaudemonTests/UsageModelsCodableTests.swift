import XCTest
@testable import ClaudemonCore

final class UsageModelsCodableTests: XCTestCase {

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        tz: String = "Europe/Istanbul"
    ) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        return cal.date(from: c)!
    }

    /// JSONEncoder/Decoder mirroring SharedUsageCache (iso8601 dates).
    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - UsageMetric

    func testUsageMetricCodableRoundTripPreservesAllFields() throws {
        let metric = UsageMetric(
            kind: .session,
            rawLabel: "Current session",
            percent: 27,
            resetDate: date(2026, 6, 24, 2, 49, 30, tz: "Europe/Istanbul"),
            timezoneIdentifier: "Europe/Istanbul"
        )

        let data = try encoder().encode(metric)
        let decoded = try decoder().decode(UsageMetric.self, from: data)

        XCTAssertEqual(decoded.kind, .session)
        XCTAssertEqual(decoded.rawLabel, "Current session")
        XCTAssertEqual(decoded.percent, 27)
        XCTAssertEqual(decoded.resetDate, metric.resetDate)
        XCTAssertEqual(decoded.timezoneIdentifier, "Europe/Istanbul")
        XCTAssertEqual(decoded.timezone, TimeZone(identifier: "Europe/Istanbul"))
        XCTAssertEqual(decoded, metric)
    }

    func testUsageMetricNilDateAndTimezoneRoundTrip() throws {
        let metric = UsageMetric(
            kind: .weekModel,
            rawLabel: "Current week (Fable)",
            percent: 0,
            resetDate: nil,
            timezoneIdentifier: nil
        )

        let data = try encoder().encode(metric)
        let decoded = try decoder().decode(UsageMetric.self, from: data)

        XCTAssertNil(decoded.resetDate)
        XCTAssertNil(decoded.timezoneIdentifier)
        XCTAssertNil(decoded.timezone)
        XCTAssertEqual(decoded, metric)
    }

    // MARK: - UsageReport

    func testUsageReportCodableRoundTripPreservesDatesAndTimezones() throws {
        let report = UsageReport(
            metrics: [
                UsageMetric(kind: .session, rawLabel: "s", percent: 27,
                            resetDate: date(2026, 6, 24, 2, 49, tz: "Europe/Istanbul"),
                            timezoneIdentifier: "Europe/Istanbul"),
                UsageMetric(kind: .weekAll, rawLabel: "wa", percent: 29,
                            resetDate: date(2026, 6, 26, 9, 59, tz: "America/New_York"),
                            timezoneIdentifier: "America/New_York"),
                UsageMetric(kind: .weekModel, rawLabel: "wm", percent: 2,
                            resetDate: date(2026, 6, 26, 10, 0, tz: "Asia/Tokyo"),
                            timezoneIdentifier: "Asia/Tokyo"),
            ],
            capturedAt: date(2026, 6, 23, 12, 0, tz: "Europe/Istanbul")
        )

        let data = try encoder().encode(report)
        let decoded = try decoder().decode(UsageReport.self, from: data)

        XCTAssertEqual(decoded.capturedAt, report.capturedAt)
        XCTAssertEqual(decoded.metrics.count, 3)
        XCTAssertEqual(decoded.session?.resetDate, report.session?.resetDate)
        XCTAssertEqual(decoded.weekAll?.timezoneIdentifier, "America/New_York")
        XCTAssertEqual(decoded.weekModel?.timezoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(decoded, report)
    }

    func testCachedUsageCodableRoundTrip() throws {
        let report = UsageReport(
            metrics: [
                UsageMetric(kind: .session, rawLabel: "s", percent: 50,
                            resetDate: date(2026, 6, 24, 2, 49, tz: "Europe/Istanbul"),
                            timezoneIdentifier: "Europe/Istanbul"),
            ],
            capturedAt: date(2026, 6, 23, 12, 0, tz: "Europe/Istanbul")
        )
        let payload = CachedUsage(
            report: report,
            state: .stale,
            errorMessage: "network down",
            writtenAt: date(2026, 6, 23, 22, 30, 15, tz: "Europe/Istanbul")
        )

        let data = try encoder().encode(payload)
        let decoded = try decoder().decode(CachedUsage.self, from: data)

        XCTAssertEqual(decoded.state, .stale)
        XCTAssertEqual(decoded.errorMessage, "network down")
        XCTAssertEqual(decoded.writtenAt, payload.writtenAt)
        XCTAssertEqual(decoded.report, report)
    }

    // MARK: - Primary / secondary limits

    private func metric(_ kind: UsageMetric.Kind, _ label: String, _ percent: Int) -> UsageMetric {
        UsageMetric(kind: kind, rawLabel: label, percent: percent, resetDate: nil, timezoneIdentifier: nil)
    }

    /// With a session limit, the session is primary and both weeks follow.
    func testPrimaryIsSessionWhenReported() {
        let report = UsageReport(metrics: [
            metric(.session, "Current session", 12),
            metric(.weekAll, "Current week (all models)", 31),
            metric(.weekModel, "Current week (Fable)", 53),
        ], capturedAt: Date())
        XCTAssertEqual(report.primary?.kind, .session)
        XCTAssertEqual(report.secondary.map(\.kind), [.weekAll, .weekModel])
    }

    /// Max plans have no session limit (no session line): the all-models week
    /// becomes primary and only the per-model week follows.
    func testPrimaryFallsBackToWeekAllWithoutSession() {
        let report = UsageReport(metrics: [
            metric(.weekAll, "Current week (all models)", 31),
            metric(.weekModel, "Current week (Fable)", 53),
        ], capturedAt: Date())
        XCTAssertEqual(report.primary?.kind, .weekAll)
        XCTAssertEqual(report.secondary.map(\.kind), [.weekModel])
        XCTAssertEqual(report.primary?.shortLabel, "Week")
        XCTAssertEqual(report.secondary.first?.shortLabel, "Fable")
    }

    func testShortDateStringUsesMetricTimezone() throws {
        // 2026-11-18 22:30 UTC is already Nov 19 in Istanbul (UTC+3).
        let date = Date(timeIntervalSince1970: 1_795_041_000)
        XCTAssertEqual(UsageFormatting.shortDateString(date, timeZone: TimeZone(identifier: "UTC")), "Nov 18")
        XCTAssertEqual(UsageFormatting.shortDateString(date, timeZone: TimeZone(identifier: "Europe/Istanbul")), "Nov 19")
    }
}
