import SwiftUI

/// How the menu-bar label presents the live usage (its main limit). Persisted
/// by `UsageStore` as a raw string and chosen in the panel's settings.
public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case iconAndText
    case textOnly
    case iconOnly
    case bars

    public var id: String { rawValue }

    /// Human-readable name for the settings Picker.
    public var label: String {
        switch self {
        case .iconAndText: return "Icon + Text"
        case .textOnly: return "Text only"
        case .iconOnly: return "Icon only"
        case .bars: return "Bar graph"
        }
    }
}

/// Which weekly limit the menu-bar bar graph's second bar tracks. Persisted
/// by `UsageStore` as a raw string. The per-model case's user-facing label is
/// the model name Anthropic currently reports (see `UsageMetric.shortLabel`),
/// so it is not hardcoded here.
public enum MenuBarWeekBarSource: String, CaseIterable, Identifiable, Sendable {
    /// Current Week (all models).
    case allModels
    /// The per-model current-week limit (e.g. Current Week (Fable)).
    case perModel

    public var id: String { rawValue }

    /// Picks the matching weekly metric out of a report.
    public var metricKind: UsageMetric.Kind {
        switch self {
        case .allModels: return .weekAll
        case .perModel: return .weekModel
        }
    }
}

/// Fixed-size bar-graph content for the menu-bar label: the main limit (the
/// session, or the user's Main limit for accounts without one) as a bar,
/// optionally a weekly limit as a second bar, and
/// optionally the percent value(s) beside the bars. Bars use the shared
/// `UsageColor` thresholds so they match the in-app usage bars.
///
/// The menu bar renders live SwiftUI label views as template (monochrome)
/// content, so the app rasterizes this view into a non-template `NSImage` —
/// which is why every dimension here is fixed: the rendered image must have a
/// stable size so the menu-bar item never jitters as values change.
public struct MenuBarBarsView: View {

    /// Everything that affects the rendered pixels.
    public struct Configuration {
        /// The menu bar's main limit (see `UsageStore.menuBarPrimaryMetric`).
        public var primaryPercent: Int
        /// The second bar's weekly percent; nil renders the primary bar only.
        public var weekPercent: Int?
        public var showsPercent: Bool
        public var isVertical: Bool
        /// Exact straight-edged fills instead of the min-sliver capsule fill.
        public var preciseFill: Bool
        /// Horizontal bars at half the standard width. Ignored in vertical
        /// mode, where the bar length is the menu-bar content height.
        public var halfWidthBars: Bool

        public init(primaryPercent: Int, weekPercent: Int?,
                    showsPercent: Bool, isVertical: Bool,
                    preciseFill: Bool = false,
                    halfWidthBars: Bool = false) {
            self.primaryPercent = primaryPercent
            self.weekPercent = weekPercent
            self.showsPercent = showsPercent
            self.isVertical = isVertical
            self.preciseFill = preciseFill
            self.halfWidthBars = halfWidthBars
        }
    }

    private let config: Configuration
    /// Count down from 100% (what's left) instead of up from 0%. Read from the
    /// environment like the bars it labels, so set it on the rendered view.
    @Environment(\.showsRemainingUsage) private var showsRemaining

    /// The menu bar's usable content height.
    private static let contentHeight: CGFloat = 16
    /// The standard "set width" of a horizontal bar (a vertical bar's length
    /// is `contentHeight`), independent of the percentage shown.
    private static let fullBarLength: CGFloat = 40

    /// The horizontal bar width for this configuration.
    private var barLength: CGFloat {
        config.halfWidthBars ? Self.fullBarLength / 2 : Self.fullBarLength
    }

    public init(_ config: Configuration) {
        self.config = config
    }

    public var body: some View {
        HStack(spacing: 4) {
            if config.isVertical {
                verticalBars
            } else {
                horizontalBars
            }
            if config.showsPercent {
                percentColumn
            }
        }
        .frame(height: Self.contentHeight)
        .accessibilityHidden(true) // the label view supplies the a11y string
    }

    // MARK: - Bars

    private var horizontalBars: some View {
        VStack(alignment: .leading, spacing: 2) {
            UsageBar(percent: config.primaryPercent, height: barThickness,
                     precise: config.preciseFill)
                .frame(width: barLength)
            if let week = config.weekPercent {
                UsageBar(percent: week, height: barThickness,
                         precise: config.preciseFill)
                    .frame(width: barLength)
            }
        }
    }

    private var verticalBars: some View {
        HStack(spacing: 3) {
            UsageBar.vertical(percent: config.primaryPercent, width: barThickness,
                             precise: config.preciseFill)
                .frame(height: Self.contentHeight)
            if let week = config.weekPercent {
                UsageBar.vertical(percent: week, width: barThickness,
                                 precise: config.preciseFill)
                    .frame(height: Self.contentHeight)
            }
        }
    }

    /// Single bars get a little more presence; paired bars slim down so two
    /// stacked horizontal bars still fit the menu-bar content height.
    private var barThickness: CGFloat {
        config.weekPercent == nil ? 7 : 6
    }

    // MARK: - Percent labels

    @ViewBuilder
    private var percentColumn: some View {
        if let week = config.weekPercent {
            // Two bars: both percents, vertically stacked in a smaller font.
            // Order matches the bars (session first, week second).
            VStack(alignment: .leading, spacing: 0) {
                percentText(config.primaryPercent, size: 8)
                percentText(week, size: 8)
            }
            .frame(width: 25, alignment: .leading)
        } else {
            percentText(config.primaryPercent, size: 11)
                .frame(width: 33, alignment: .leading)
        }
    }

    // Percent column widths are sized to the worst case ("100%": 24.1pt at 8pt,
    // 32.2pt at 11pt, monospaced digits) so the item width never jitters; the
    // leading alignment means shorter values leave their slack on the right.

    /// Fixed-width, monospaced-digit percent so the image width is stable.
    private func percentText(_ percent: Int, size: CGFloat) -> some View {
        Text("\(UsageDisplay.percent(percent, remaining: showsRemaining))%")
            .font(.system(size: size, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
    }
}
