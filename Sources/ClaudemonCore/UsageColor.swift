import SwiftUI

extension EnvironmentValues {
    /// Show what's left of each limit (counting down from 100%) instead of
    /// what's used. Set once at each window's root; the shared bars, rings and
    /// percent labels read it.
    @Entry public var showsRemainingUsage = false
}

/// Turns a limit's used percentage into what the UI shows. Colors always
/// follow the USED percentage (see `UsageColor`), so a limit running out
/// turns yellow/red whichever way the numbers count.
public enum UsageDisplay {
    /// The percent to show: the used percentage, or what's left (0–100).
    public static func percent(_ used: Int, remaining: Bool) -> Int {
        let clamped = max(0, min(100, used))
        return remaining ? 100 - clamped : clamped
    }

    /// "27 percent used" / "73 percent left", for VoiceOver.
    public static func spoken(_ used: Int, remaining: Bool) -> String {
        "\(percent(used, remaining: remaining)) percent \(remaining ? "left" : "used")"
    }
}

/// Threshold-based color for a usage percentage, shared by the app UI and the
/// widget so both surfaces use identical green/yellow/red bands.
public enum UsageColor {
    public static func color(for percent: Int) -> Color {
        switch percent {
        case ..<60: return .green
        case 60..<86: return .yellow
        default: return .red
        }
    }
}

/// The gauge SF Symbol for a shown percentage (see `UsageDisplay.percent`),
/// shared by the menu bar, the panel header and the widget so every gauge icon
/// shows the same needle.
public enum UsageGauge {
    /// The needle positions SF Symbols provides for this gauge.
    private static let steps = [0, 33, 50, 67, 100]

    /// The symbol whose needle is nearest to `percent` (clamped 0–100); the
    /// empty gauge when there is no data.
    public static func symbolName(for percent: Int?) -> String {
        let clamped = max(0, min(100, percent ?? 0))
        let step = steps.min { abs($0 - clamped) < abs($1 - clamped) } ?? 0
        return "gauge.with.dots.needle.\(step)percent"
    }
}
