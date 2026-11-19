import SwiftUI

/// A compact, geometry-driven usage bar shared by the floating mini-window and
/// the WidgetKit widget so both surfaces fill identically.
///
/// Unlike `ProgressView(.linear)`, this guarantees the fill width tracks the
/// percentage exactly (0–100, clamped). The fill color uses the shared
/// `UsageColor` thresholds, matching the session ring.
///
/// The fill tracks the shown value (used, or remaining when the
/// `showsRemainingUsage` environment value is set); the color always tracks
/// the used percentage.
///
/// Two fill styles:
/// - Default: a capsule fill with a small visible minimum, so low values like
///   2% still read as "some usage" at a glance.
/// - Precise (`precise: true`): a straight-edged fill at the exact
///   proportional width, clipped by the rounded track — no minimum — so 2%
///   and 8% are visually distinct.
public struct UsageBar: View {
    /// The limit's USED percentage.
    private let percent: Int
    @Environment(\.showsRemainingUsage) private var showsRemaining
    private let height: CGFloat
    private let precise: Bool

    public init(percent: Int, height: CGFloat = 6, precise: Bool = false) {
        self.percent = percent
        self.height = height
        self.precise = precise
    }

    public var body: some View {
        let shown = UsageDisplay.percent(percent, remaining: showsRemaining)
        GeometryReader { geo in
            let fullWidth = geo.size.width
            let fraction = CGFloat(shown) / 100.0
            // Non-precise keeps a small visible sliver for any non-zero value
            // so e.g. 2% does not look empty; precise draws the exact width.
            let minVisible: CGFloat = (!precise && shown > 0) ? height : 0
            let fillWidth = max(minVisible, fullWidth * fraction)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                fillShape
                    .fill(UsageColor.color(for: percent))
                    .frame(width: min(fullWidth, fillWidth))
            }
            // Round only the track's outline: the precise fill keeps its
            // straight trailing edge, trimmed at the capsule ends.
            .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var fillShape: AnyShape {
        precise ? AnyShape(Rectangle()) : AnyShape(Capsule())
    }
}

/// The vertical counterpart of `UsageBar`: same track/fill/color language and
/// fill styles, but the fill grows bottom-up. Used by the menu-bar bar-graph
/// label's vertical layout.
public struct VerticalUsageBar: View {
    /// The limit's USED percentage.
    private let percent: Int
    @Environment(\.showsRemainingUsage) private var showsRemaining
    private let width: CGFloat
    private let precise: Bool

    public init(percent: Int, width: CGFloat = 6, precise: Bool = false) {
        self.percent = percent
        self.width = width
        self.precise = precise
    }

    public var body: some View {
        let shown = UsageDisplay.percent(percent, remaining: showsRemaining)
        GeometryReader { geo in
            let fullHeight = geo.size.height
            // Same readability rule as the horizontal bar: a small visible
            // sliver in the default style, the exact height in precise style.
            let fraction = CGFloat(shown) / 100.0
            let minVisible: CGFloat = (!precise && shown > 0) ? width : 0
            let fillHeight = max(minVisible, fullHeight * fraction)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                fillShape
                    .fill(UsageColor.color(for: percent))
                    .frame(height: min(fullHeight, fillHeight))
            }
            .clipShape(Capsule())
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }

    private var fillShape: AnyShape {
        precise ? AnyShape(Rectangle()) : AnyShape(Capsule())
    }
}

/// A circular usage gauge shared by the floating window and the widget: a
/// faint full track plus an arc for the shown value (used, or remaining when
/// `showsRemainingUsage` is set), colored by the used percentage with the
/// shared `UsageColor` thresholds. The stroke is inset so the ring stays
/// inside its frame; a plain `.stroke` is centered on the path and would
/// spill half the line width onto neighboring views.
public struct UsageRing: View {
    /// The limit's USED percentage; nil (no data yet) draws only the track.
    private let percent: Int?
    @Environment(\.showsRemainingUsage) private var showsRemaining
    private let lineWidth: CGFloat

    public init(percent: Int?, lineWidth: CGFloat) {
        self.percent = percent
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            if let percent {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: CGFloat(UsageDisplay.percent(percent, remaining: showsRemaining)) / 100)
                    .stroke(UsageColor.color(for: percent),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

/// A `UsageRing` with its shown percent over a caption inside ("73%" over
/// "WEEK"), everything scaled from `diameter`. Shared by the floating window
/// and the small widget. A nil percent (no data yet) shows `placeholderSymbol`
/// in an empty ring.
public struct UsageRingGauge: View {
    /// The limit's USED percentage, or nil without data.
    private let percent: Int?
    private let caption: String
    private let diameter: CGFloat
    private let placeholderSymbol: String
    @Environment(\.showsRemainingUsage) private var showsRemaining

    public init(percent: Int?, caption: String, diameter: CGFloat,
                placeholderSymbol: String = "ellipsis") {
        self.percent = percent
        self.caption = caption
        self.diameter = diameter
        self.placeholderSymbol = placeholderSymbol
    }

    public var body: some View {
        let lineWidth = max(diameter * 0.105, 4)
        let percentFont = diameter * 0.24
        ZStack {
            UsageRing(percent: percent, lineWidth: lineWidth)
            VStack(spacing: 1) {
                if let percent {
                    Text("\(UsageDisplay.percent(percent, remaining: showsRemaining))%")
                        .font(.system(size: percentFont, weight: .bold).monospacedDigit())
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: placeholderSymbol)
                        .font(.system(size: percentFont * 0.82, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Text(caption)
                    .font(.system(size: diameter * 0.115, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            // Keep the text well inside the ring's opening: sized to the full
            // inner width, "100%" ran into the stroke.
            .frame(maxWidth: (diameter - 2 * lineWidth) * 0.78)
        }
        .frame(width: diameter, height: diameter)
    }
}
