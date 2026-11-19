import Foundation
import Testing
@testable import ClaudemonCore

struct UsageParserTests {

    // MARK: - Helpers

    /// Extract wall-clock components of a Date in a specific timezone.
    private func components(of date: Date, tz: String) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        return cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    /// A "now" before every fixture's reset, so inferred years stay in 2026.
    private let june23 = makeDate(2026, 6, 23, 12, 0)

    // The real verified /usage result block (post Fable rollout — Anthropic
    // renamed the per-model line from "(Sonnet only)" to "(Fable)").
    private let realResult = """
    Current session: 27% used · resets Jun 24 at 2:49am (Europe/Istanbul)
    Current week (all models): 29% used · resets Jun 26 at 9:59am (Europe/Istanbul)
    Current week (Fable): 2% used · resets Jun 26 at 10am (Europe/Istanbul)
    """

    // MARK: - Real verified block

    @Test func `Real result block parses three metrics`() throws {
        let report = try UsageParser.parse(resultText: realResult, now: june23)

        #expect(report.metrics.count == 3, "Expected exactly 3 metrics")

        // Ordering: session, weekAll, weekModel
        #expect(report.metrics.map(\.kind) == [.session, .weekAll, .weekModel])

        let session = try #require(report.session)
        let weekAll = try #require(report.weekAll)
        let weekModel = try #require(report.weekModel)

        #expect(session.percent == 27)
        #expect(weekAll.percent == 29)
        #expect(weekModel.percent == 2)
        #expect(weekModel.shortLabel == "Fable", "Model name should be read from the label, not hardcoded")

        #expect(session.timezoneIdentifier == "Europe/Istanbul")
        #expect(weekAll.timezoneIdentifier == "Europe/Istanbul")
        #expect(weekModel.timezoneIdentifier == "Europe/Istanbul")

        // Session: Jun 24 2:49am Europe/Istanbul
        let sc = components(of: try #require(session.resetDate), tz: "Europe/Istanbul")
        #expect(sc.year == 2026)
        #expect(sc.month == 6)
        #expect(sc.day == 24)
        #expect(sc.hour == 2)
        #expect(sc.minute == 49)

        // Week all: Jun 26 9:59am
        let wc = components(of: try #require(weekAll.resetDate), tz: "Europe/Istanbul")
        #expect(wc.month == 6)
        #expect(wc.day == 26)
        #expect(wc.hour == 9)
        #expect(wc.minute == 59)

        // Week model: Jun 26 10am (no minutes → 00)
        let mc = components(of: try #require(weekModel.resetDate), tz: "Europe/Istanbul")
        #expect(mc.month == 6)
        #expect(mc.day == 26)
        #expect(mc.hour == 10)
        #expect(mc.minute == 0)
    }

    /// The classifier must not hardcode any specific model name — it should
    /// treat ANY "Current week (<model>)" line (that isn't "all models") as
    /// the per-model kind. This is a regression test for the bug where the
    /// old parser only recognized lines containing the literal word "sonnet"
    /// and silently dropped the line once Anthropic renamed it to "(Fable)".
    @Test(arguments: ["Sonnet only", "Fable", "Opus", "Haiku 4.5", "SomeFutureModelXYZ"])
    func `Per-model line is generic, not hardcoded to Sonnet`(modelName: String) throws {
        let text = "Current week (\(modelName)): 12% used · resets Jul 1 at 10am (Europe/Istanbul)"
        let report = try UsageParser.parse(resultText: text, now: june23)
        let m = try #require(report.weekModel, "Model line '\(modelName)' should classify as weekModel")
        #expect(m.percent == 12)
        #expect(m.shortLabel == modelName)
    }

    @Test func `Parses via the outer JSON`() throws {
        let json = try JSONSerialization.data(withJSONObject: ["result": realResult])
        let report = try UsageParser.parse(jsonData: json, now: june23)
        #expect(report.metrics.count == 3)
        #expect(report.session?.percent == 27)
    }

    // MARK: - Reset clock times (no minutes, 12am / 12pm boundaries)

    @Test(arguments: [
        ("10am", 10, 0),    // no minutes → :00
        ("12am", 0, 0),     // 12am must map to 00:00
        ("12pm", 12, 0),    // 12pm must map to 12:00
        ("1:30pm", 13, 30),
    ])
    func `Reset clock time maps to 24-hour`(time: String, hour: Int, minute: Int) throws {
        let text = "Current session: 10% used · resets Jun 24 at \(time) (Europe/Istanbul)"
        let report = try UsageParser.parse(resultText: text, now: june23)
        let c = components(of: try #require(report.session?.resetDate), tz: "Europe/Istanbul")
        #expect(c.day == 24)
        #expect(c.hour == hour)
        #expect(c.minute == minute)
    }

    // MARK: - Year inference

    @Test func `A past month and day rolls to next year`() throws {
        // now = mid-December 2026. Reset "Jan 5" is earlier in the calendar →
        // should roll to 2027.
        let now = makeDate(2026, 12, 15, 12, 0)
        let text = "Current session: 10% used · resets Jan 5 at 9am (Europe/Istanbul)"
        let report = try UsageParser.parse(resultText: text, now: now)
        let c = components(of: try #require(report.session?.resetDate), tz: "Europe/Istanbul")
        #expect(c.year == 2027, "A reset earlier in the calendar than now should roll to next year")
        #expect(c.month == 1)
        #expect(c.day == 5)
    }

    /// Regression: a reset read moments after it happened (the poll lands in
    /// the minute after 2:49am) used to roll to next year and show a countdown
    /// of about 8760 hours. A date that only just passed stays this year.
    @Test func `A reset that just passed stays this year`() throws {
        let now = makeDate(2026, 6, 24, 2, 50)
        let text = "Current session: 10% used · resets Jun 24 at 2:49am (Europe/Istanbul)"
        let report = try UsageParser.parse(resultText: text, now: now)
        let c = components(of: try #require(report.session?.resetDate), tz: "Europe/Istanbul")
        #expect(c.year == 2026, "A reset a minute ago is this year's, not next year's")
        #expect(c.month == 6)
        #expect(c.day == 24)
    }

    @Test func `A future month and day stays this year`() throws {
        // now = Jan 2026. Reset "Dec 31" is later this year → stays 2026.
        let now = makeDate(2026, 1, 10, 12, 0)
        let text = "Current session: 10% used · resets Dec 31 at 9am (Europe/Istanbul)"
        let report = try UsageParser.parse(resultText: text, now: now)
        let c = components(of: try #require(report.session?.resetDate), tz: "Europe/Istanbul")
        #expect(c.year == 2026, "A future reset within the year should stay this year")
        #expect(c.month == 12)
        #expect(c.day == 31)
    }

    // MARK: - Alternate timezone

    @Test func `An alternate timezone resolves`() throws {
        let text = "Current session: 10% used · resets Jun 24 at 2:49am (America/New_York)"
        let report = try UsageParser.parse(resultText: text, now: june23)
        let m = try #require(report.session)
        #expect(m.timezoneIdentifier == "America/New_York")
        #expect(m.timezone == TimeZone(identifier: "America/New_York"))
        // Verify the date carries the correct wall-clock in New York.
        let c = components(of: try #require(m.resetDate), tz: "America/New_York")
        #expect(c.hour == 2)
        #expect(c.minute == 49)
        #expect(c.day == 24)
    }

    // MARK: - Malformed / missing input (no crash)

    @Test(arguments: ["", "   \n  \t "])
    func `Empty or whitespace text throws emptyResult`(text: String) {
        #expect(throws: UsageParseError.emptyResult) {
            try UsageParser.parse(resultText: text)
        }
    }

    @Test func `Garbage text throws noMetricsFound`() {
        #expect(throws: UsageParseError.noMetricsFound) {
            try UsageParser.parse(resultText: "hello world\nnothing here")
        }
    }

    /// The REAL local-only body the `claude` CLI returns between its ~1-minute
    /// limit-line refreshes: a successful, non-empty `.result` that simply omits
    /// the three "Current session/week" lines. This must map to a STALE-RENDER
    /// signal (keep last-good data), NOT a hard error.
    @Test func `A success body without limit lines is a stale render, not an error`() {
        let localOnlyBody = """
        You are currently using your subscription to power your Claude Code usage

        What's contributing to your limits usage?
        Approximate, based on local sessions on this machine.

        Last 24h · 1691 requests · 11 sessions
        Last 7d · 4199 requests · 22 sessions
        """
        let error = #expect(throws: UsageParseError.noMetricsFound) {
            try UsageParser.parse(resultText: localOnlyBody)
        }
        #expect(error?.isStaleRender == true,
                "A success body without limit lines is a stale render, not a failure")
    }

    /// An empty `.result` is a genuine failure, NOT a stale render.
    @Test func `An empty result is not a stale render`() {
        let error = #expect(throws: UsageParseError.emptyResult) {
            try UsageParser.parse(resultText: "")
        }
        #expect(error?.isStaleRender == false,
                "An empty body is a real failure, not a stale render")
    }

    @Test func `Non-usage JSON throws emptyResult`() throws {
        let json = try JSONSerialization.data(withJSONObject: ["error": "boom"])
        #expect(throws: UsageParseError.emptyResult) {
            try UsageParser.parse(jsonData: json)
        }
    }

    @Test func `Invalid JSON data throws emptyResult`() {
        #expect(throws: UsageParseError.emptyResult) {
            try UsageParser.parse(jsonData: Data("not json".utf8))
        }
    }

    @Test func `A line with a percent but no reset does not crash`() throws {
        // Has a recognizable usage line (percent) but no valid reset clause.
        let report = try UsageParser.parse(resultText: "Current session: 42% used", now: june23)
        let m = try #require(report.session)
        #expect(m.percent == 42)
        #expect(m.resetDate == nil, "Missing reset clause should yield nil date, not a crash")
        #expect(m.timezoneIdentifier == nil)
    }

    @Test func `A reset without a timezone falls back to current`() throws {
        let text = "Current session: 42% used · resets Jun 24 at 2:49am"
        let report = try UsageParser.parse(resultText: text, now: june23)
        let m = try #require(report.session)
        #expect(m.timezoneIdentifier == nil, "No tz in text → identifier should be nil")
        #expect(m.resetDate != nil, "Date should still resolve using current tz")
    }

    @Test func `Percent is clamped and duplicate kinds are ignored`() throws {
        // Two session lines: first wins. Also an over-100 percent gets clamped.
        let text = """
        Current session: 27% used · resets Jun 24 at 2:49am (Europe/Istanbul)
        Current session: 150% used · resets Jun 25 at 2:49am (Europe/Istanbul)
        """
        let report = try UsageParser.parse(resultText: text, now: june23)
        #expect(report.metrics.count == 1)
        #expect(report.session?.percent == 27, "First matching line wins")
    }

    @Test func `Order tolerance and extra noise`() throws {
        // Lines out of order, with leading garbage lines.
        let text = """
        Some banner text
        Current week (Fable): 2% used · resets Jun 26 at 10am (Europe/Istanbul)
        Current session: 27% used · resets Jun 24 at 2:49am (Europe/Istanbul)
        Current week (all models): 29% used · resets Jun 26 at 9:59am (Europe/Istanbul)
        """
        let report = try UsageParser.parse(resultText: text, now: june23)
        #expect(report.metrics.map(\.kind) == [.session, .weekAll, .weekModel],
                "Output ordering must be stable regardless of input order")
    }

    /// The CLI now appends a "What's contributing to your usage?" section of
    /// percent-led tips. Only "Current …" lines are limits; a tip mentioning
    /// sessions must not become a bogus session metric. Shape copied from a
    /// real 2026-11 body, which also omits the session line (no active window).
    @Test func `Contribution tips are not parsed as limits`() throws {
        let text = """
        You are currently using your subscription to power your Claude Code usage

        Current week (all models): 31% used · resets Nov 19 at 8:59am (Europe/Istanbul)
        Current week (Fable): 53% used · resets Nov 19 at 8:59am (Europe/Istanbul)

        What's contributing to your usage?
        Approximate · sessions on this machine only · shares overlap

        Last 7d · 2887 requests · 3 sessions
          100%  Review sessions active over many hours · whole sessions with requests in 8 or more separate hours
          40%  Sessions that used subagents · resets context less often
        """
        let report = try UsageParser.parse(resultText: text, now: Date(timeIntervalSince1970: 1_795_000_000))
        #expect(report.session == nil, "A tip line must not be read as the session limit")
        #expect(report.weekAll?.percent == 31)
        #expect(report.weekModel?.percent == 53)
        #expect(report.metrics.count == 2)
    }
}
