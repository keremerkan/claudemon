import Foundation
import Testing
@testable import ClaudemonCore

struct UsageAlertPolicyTests {

    private static let allEnabled = Set(UsageAlertThreshold.allCases)

    // MARK: - Threshold decisions

    /// One `decide` call: the inputs and the expected fire/fired outcome.
    struct DecideCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let percentUsed: Int
        var window = "w1"
        var priorWindow: String?
        var alreadyFired: Set<Int> = []
        var enabled = UsageAlertPolicyTests.allEnabled
        let fire: UsageAlertThreshold?
        let fired: Set<Int>
    }

    static let decideCases: [DecideCase] = [
        // Crossing
        DecideCase(testDescription: "50% used: above the 25% point, nothing fires",
                   percentUsed: 50, fire: nil, fired: []),
        DecideCase(testDescription: "Exactly 25% remaining fires the quarter alert",
                   percentUsed: 75, fire: .quarter, fired: [25]),
        DecideCase(testDescription: "5% remaining fires low",
                   percentUsed: 95, priorWindow: "w1", alreadyFired: [25], fire: .low, fired: [25, 5]),
        DecideCase(testDescription: "0% remaining fires depleted",
                   percentUsed: 100, priorWindow: "w1", alreadyFired: [25, 5],
                   fire: .depleted, fired: [25, 5, 0]),
        DecideCase(testDescription: "Over 100% used is treated as depleted",
                   percentUsed: 130, fire: .depleted, fired: [25, 5, 0]),
        // De-duplication
        DecideCase(testDescription: "An already-fired threshold does not re-fire",
                   percentUsed: 75, priorWindow: "w1", alreadyFired: [25], fire: nil, fired: [25]),
        // Most-severe-only on a jump
        DecideCase(testDescription: "A jump to 2% remaining fires only low but marks 25 and 5",
                   percentUsed: 98, fire: .low, fired: [25, 5]),
        DecideCase(testDescription: "A jump to depleted fires only depleted",
                   percentUsed: 100, fire: .depleted, fired: [25, 5, 0]),
        // Window reset re-arms
        DecideCase(testDescription: "A new window clears fired flags and the current level fires again",
                   percentUsed: 96, window: "w2", priorWindow: "w1", alreadyFired: [25, 5, 0],
                   fire: .low, fired: [25, 5]),
        DecideCase(testDescription: "A new window with healthy usage fires nothing",
                   percentUsed: 10, window: "w2", priorWindow: "w1", alreadyFired: [25, 5, 0],
                   fire: nil, fired: []),
        // Disabled thresholds
        DecideCase(testDescription: "Only depleted enabled: nothing fires at 25% remaining",
                   percentUsed: 75, enabled: [.depleted], fire: nil, fired: []),
        DecideCase(testDescription: "Quarter disabled: low still fires and only low is marked",
                   percentUsed: 96, enabled: [.low, .depleted], fire: .low, fired: [5]),
    ]

    @Test(arguments: decideCases)
    func `Threshold decision`(_ c: DecideCase) {
        let d = UsageAlertPolicy.decide(
            percentUsed: c.percentUsed, windowSignature: c.window, priorSignature: c.priorWindow,
            firedThresholds: c.alreadyFired, enabledThresholds: c.enabled)
        #expect(d.fire == c.fire)
        #expect(d.fired == c.fired)
    }

    @Test func `Repeated polls at the same level fire only once`() {
        var prior: UsageAlertPolicy.Decision?
        var fireCount = 0
        for _ in 0..<5 {
            let d = UsageAlertPolicy.decide(
                percentUsed: 96, windowSignature: "w1",
                priorSignature: prior?.signature,
                firedThresholds: prior?.fired ?? [],
                enabledThresholds: Self.allEnabled)
            if d.fire != nil { fireCount += 1 }
            prior = d
        }
        // 96% used → 4% remaining crosses both 25 and 5; only the most severe
        // (low) fires, and only on the first poll.
        #expect(fireCount == 1)
    }

    // MARK: - Window signature robustness (regression: notification flood)

    /// The reported reset time can jitter by a minute across polls
    /// ("9:59am" ↔ "10am" ↔ "10:01am"). Those must NOT produce different
    /// signatures, or the fired flags re-arm every poll and the user is flooded.
    @Test func `Minute jitter in the reset time keeps the same signature`() {
        // 9:59, 10:00, 10:01 on the same day — all within one rounded hour.
        let base = Date(timeIntervalSince1970: 1_800_000_000) // arbitrary fixed instant
        let nineFiftyNine = base.addingTimeInterval(-60)
        let ten = base
        let tenOhOne = base.addingTimeInterval(60)

        let s1 = UsageAlertPolicy.windowSignature(resetDate: nineFiftyNine, prior: nil)
        let s2 = UsageAlertPolicy.windowSignature(resetDate: ten, prior: s1)
        let s3 = UsageAlertPolicy.windowSignature(resetDate: tenOhOne, prior: s2)

        #expect(s1 == s2)
        #expect(s2 == s3)
    }

    /// A single poll that fails to parse the reset clause (resetDate == nil)
    /// must inherit the prior window rather than mint a fresh "unknown" one,
    /// so a transient parse-miss can't re-arm and re-fire every threshold.
    @Test func `A transient parse miss inherits the prior signature`() {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let good = UsageAlertPolicy.windowSignature(resetDate: reset, prior: nil)
        let miss = UsageAlertPolicy.windowSignature(resetDate: nil, prior: good)
        #expect(miss == good, "nil resetDate should carry the prior signature")
    }

    /// End-to-end: repeated polls where the signature flip-flops the way the CLI
    /// does in the wild (parsed → miss → parsed) must still fire exactly once.
    @Test func `A flip-flopping reset does not re-fire`() {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        var prior: UsageAlertPolicy.Decision?
        var fireCount = 0

        // Alternate a valid reset date with a parse-miss (nil) across polls.
        let resetSequence: [Date?] = [reset, nil, reset, nil, reset, nil]
        for r in resetSequence {
            let signature = UsageAlertPolicy.windowSignature(resetDate: r, prior: prior?.signature)
            let d = UsageAlertPolicy.decide(
                percentUsed: 75, windowSignature: signature,
                priorSignature: prior?.signature,
                firedThresholds: prior?.fired ?? [],
                enabledThresholds: Self.allEnabled)
            if d.fire != nil { fireCount += 1 }
            prior = d
        }
        #expect(fireCount == 1, "A flip-flopping reset signal must not re-notify")
    }

    /// A genuine new quota window (reset moved by days) must still re-arm once.
    @Test func `A genuine new window still re-arms`() {
        let week1 = Date(timeIntervalSince1970: 1_800_000_000)
        let week2 = week1.addingTimeInterval(7 * 24 * 3600)
        let s1 = UsageAlertPolicy.windowSignature(resetDate: week1, prior: nil)
        let s2 = UsageAlertPolicy.windowSignature(resetDate: week2, prior: s1)
        #expect(s1 != s2)

        let d = UsageAlertPolicy.decide(
            percentUsed: 75, windowSignature: s2, priorSignature: s1,
            firedThresholds: [25], enabledThresholds: Self.allEnabled)
        #expect(d.fire == .quarter, "A real new window re-arms the quarter alert")
    }

    // MARK: - Reset alerts

    /// A fixed instant used as "now" so the tests are timezone/clock independent.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// First observation after launch: even if the reported reset already lies in
    /// the past (a reset happened while the app was closed), nothing fires — we
    /// only announce resets the running app actually witnesses.
    @Test func `Reset does not fire on the first observation of a past reset`() {
        let past = now.addingTimeInterval(-3600)
        let d = UsageAlertPolicy.decideReset(
            now: now, resetDate: past, percentUsed: 100, prior: .init())
        #expect(!d.fireReset)
        // A past reset date doesn't arm a pending window.
        #expect(d.state.pendingResetDate == nil)
    }

    /// The core flow: observe a future reset while the window has some usage,
    /// then the reset time passes → fire exactly once.
    @Test func `Reset fires once when a used window rolls over`() {
        let reset = now.addingTimeInterval(1800)

        // Poll 1: window active in the future, some usage recorded.
        var d = UsageAlertPolicy.decideReset(
            now: now, resetDate: reset, percentUsed: 100, prior: .init())
        #expect(!d.fireReset)
        #expect(d.state.pendingResetDate == reset)
        #expect(d.state.didUse)

        // Poll 2: the reset time has passed (CLI now reports the fresh window).
        let after = reset.addingTimeInterval(60)
        let fresh = reset.addingTimeInterval(5 * 3600)
        d = UsageAlertPolicy.decideReset(
            now: after, resetDate: fresh, percentUsed: 0, prior: d.state)
        #expect(d.fireReset)
        #expect(d.state.pendingResetDate == fresh)
        #expect(!d.state.didUse, "fresh window starts clean")
    }

    /// Any usage counts, not just full depletion: a window that only reached
    /// 10% still announces when it resets.
    @Test func `Reset fires for a partially used window`() {
        let reset = now.addingTimeInterval(1800)
        var d = UsageAlertPolicy.decideReset(
            now: now, resetDate: reset, percentUsed: 10, prior: .init())
        #expect(!d.fireReset)
        #expect(d.state.didUse)

        let after = reset.addingTimeInterval(60)
        let fresh = reset.addingTimeInterval(5 * 3600)
        d = UsageAlertPolicy.decideReset(
            now: after, resetDate: fresh, percentUsed: 0, prior: d.state)
        #expect(d.fireReset, "a partially-used window still announces its reset")
    }

    /// A completely untouched window (0% used) rolls over silently.
    @Test func `Reset does not fire when the window was never used`() {
        let reset = now.addingTimeInterval(1800)
        var d = UsageAlertPolicy.decideReset(
            now: now, resetDate: reset, percentUsed: 0, prior: .init())
        #expect(!d.fireReset)

        let after = reset.addingTimeInterval(60)
        d = UsageAlertPolicy.decideReset(
            now: after, resetDate: nil, percentUsed: 0, prior: d.state)
        #expect(!d.fireReset, "no announcement for a window that was never used")
    }

    /// Once a reset has fired, subsequent polls in the fresh window don't re-fire.
    @Test func `Reset fires only once per rollover`() {
        let reset = now.addingTimeInterval(1800)
        var state = UsageAlertPolicy.decideReset(
            now: now, resetDate: reset, percentUsed: 100, prior: .init()).state

        var fireCount = 0
        // The rollover poll plus several steady polls afterward.
        let fresh = reset.addingTimeInterval(5 * 3600)
        var t = reset.addingTimeInterval(60)
        for _ in 0..<5 {
            let d = UsageAlertPolicy.decideReset(
                now: t, resetDate: fresh, percentUsed: 10, prior: state)
            if d.fireReset { fireCount += 1 }
            state = d.state
            t = t.addingTimeInterval(60)
        }
        #expect(fireCount == 1)
    }

    /// After a reset fires, if the fresh window is used again its own reset
    /// fires once more — the alert re-arms each window.
    @Test func `Reset re-arms for each used window`() {
        // Window 1 used then rolls over → fire #1.
        let reset1 = now.addingTimeInterval(1800)
        var state = UsageAlertPolicy.decideReset(
            now: now, resetDate: reset1, percentUsed: 100, prior: .init()).state

        let reset2 = reset1.addingTimeInterval(5 * 3600)
        var d = UsageAlertPolicy.decideReset(
            now: reset1.addingTimeInterval(60), resetDate: reset2, percentUsed: 0, prior: state)
        #expect(d.fireReset)
        state = d.state

        // Window 2 gets used too.
        state = UsageAlertPolicy.decideReset(
            now: reset1.addingTimeInterval(3600), resetDate: reset2, percentUsed: 100, prior: state).state

        // Window 2 rolls over → fire #2.
        let reset3 = reset2.addingTimeInterval(5 * 3600)
        d = UsageAlertPolicy.decideReset(
            now: reset2.addingTimeInterval(60), resetDate: reset3, percentUsed: 0, prior: state)
        #expect(d.fireReset, "a second used window announces its own reset")
    }
}
