import SwiftUI

/// A geometry-driven usage bar shared by the panel, the medium widget and the
/// menu-bar bar graph, horizontal (filling left to right) or vertical (filling
/// bottom-up).
///
/// Unlike `ProgressView(.linear)`, this guarantees the fill length tracks the
/// percentage exactly (0–100, clamped). The fill tracks the shown value (used,
/// or remaining when the `showsRemainingUsage` environment value is set); the
/// color always tracks the used percentage, with the shared `UsageColor`
/// thresholds.
///
/// Two fill styles:
/// - Default: a capsule fill with a small visible minimum, so low values like
///   2% still read as "some usage" at a glance.
/// - Precise (`precise: true`): a straight-edged fill at the exact
///   proportional length, clipped by the rounded track — no minimum — so 2%
///   and 8% are visually distinct.
public struct UsageBar: View {
    /// The limit's USED percentage.
    private let percent: Int
    @Environment(\.showsRemainingUsage) private var showsRemaining
    private let axis: Axis
    /// Height of a horizontal bar, width of a vertical one.
    private let thickness: CGFloat
    private let precise: Bool

    /// A horizontal bar `height` points tall.
    public init(percent: Int, height: CGFloat = 6, precise: Bool = false) {
        self.init(percent: percent, axis: .horizontal, thickness: height, precise: precise)
    }

    /// A vertical bar `width` points wide, filling bottom-up.
    public static func vertical(percent: Int, width: CGFloat = 6, precise: Bool = false) -> UsageBar {
        UsageBar(percent: percent, axis: .vertical, thickness: width, precise: precise)
    }

    private init(percent: Int, axis: Axis, thickness: CGFloat, precise: Bool) {
        self.percent = percent
        self.axis = axis
        self.thickness = thickness
        self.precise = precise
    }

    public var body: some View {
        let shown = UsageDisplay.percent(percent, remaining: showsRemaining)
        let horizontal = axis == .horizontal
        GeometryReader { geo in
            let length = horizontal ? geo.size.width : geo.size.height
            // Non-precise keeps a small visible sliver for any non-zero value
            // so e.g. 2% does not look empty; precise draws the exact length.
            let minVisible: CGFloat = (!precise && shown > 0) ? thickness : 0
            let fill = min(length, max(minVisible, length * (CGFloat(shown) / 100.0)))

            ZStack(alignment: horizontal ? .leading : .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                fillShape
                    .fill(UsageColor.color(for: percent))
                    .frame(width: horizontal ? fill : nil, height: horizontal ? nil : fill)
            }
            // Round only the track's outline: the precise fill keeps its
            // straight end, trimmed at the capsule ends.
            .clipShape(Capsule())
        }
        .frame(width: horizontal ? nil : thickness, height: horizontal ? thickness : nil)
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
/// "WEEK"), everything scaled to the largest square that fits the space it is
/// given (set a frame for a fixed size). Shared by the floating window and the
/// widgets. A nil percent (no data yet) shows `placeholderSymbol` in an empty
/// ring.
public struct UsageRingGauge: View {
    /// The limit's USED percentage, or nil without data.
    private let percent: Int?
    private let caption: String
    private let placeholderSymbol: String
    @Environment(\.showsRemainingUsage) private var showsRemaining

    public init(percent: Int?, caption: String, placeholderSymbol: String = "ellipsis") {
        self.percent = percent
        self.caption = caption
        self.placeholderSymbol = placeholderSymbol
    }

    public var body: some View {
        GeometryReader { geo in
            gauge(diameter: min(geo.size.width, geo.size.height))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func gauge(diameter: CGFloat) -> some View {
        let lineWidth = max(diameter * 0.105, 4)
        let percentFont = diameter * 0.24
        return ZStack {
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

/// A `UsageRingGauge` for every limit in `report`, the primary first (see
/// `UsageReport.primary` and `.secondary`), as large as the available width
/// and height allow (capped at `maxDiameter`). The row takes only the size it
/// uses, so a parent can center it with whatever sits around it. Shared by
/// the floating window and the rings widget. Without a report, one
/// placeholder ring.
public struct UsageRingRow: View {
    private let report: UsageReport?
    private let spacing: CGFloat
    private let maxDiameter: CGFloat
    private let placeholderSymbol: String

    public init(report: UsageReport?, spacing: CGFloat, maxDiameter: CGFloat = .infinity,
                placeholderSymbol: String = "ellipsis") {
        self.report = report
        self.spacing = spacing
        self.maxDiameter = maxDiameter
        self.placeholderSymbol = placeholderSymbol
    }

    public var body: some View {
        let metrics = report.map { [$0.primary].compactMap { $0 } + $0.secondary } ?? []
        SquareRowLayout(spacing: spacing, maxSide: maxDiameter) {
            if metrics.isEmpty {
                UsageRingGauge(percent: nil, caption: UsageMetric.Kind.session.shortName,
                               placeholderSymbol: placeholderSymbol)
            } else {
                ForEach(metrics) { metric in
                    UsageRingGauge(percent: metric.percent, caption: metric.shortLabel)
                }
            }
        }
    }
}

/// Equal squares in a centered row, each as large as the proposal allows
/// (capped at `maxSide`). Reports exactly the size it uses rather than filling
/// the proposal, unlike a GeometryReader.
private struct SquareRowLayout: Layout {
    let spacing: CGFloat
    let maxSide: CGFloat

    private func side(fitting size: ProposedViewSize, count: Int) -> CGFloat {
        let n = CGFloat(max(count, 1))
        let byWidth = size.width.map { ($0 - spacing * (n - 1)) / n } ?? .infinity
        let side = min(maxSide, byWidth, size.height ?? .infinity)
        // Unbounded proposal and no cap: fall back to a modest ideal size.
        return side.isFinite ? max(0, side) : 60
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let side = side(fitting: proposal, count: subviews.count)
        let n = CGFloat(subviews.count)
        return CGSize(width: n * side + spacing * max(n - 1, 0), height: side)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let side = side(fitting: ProposedViewSize(bounds.size), count: subviews.count)
        let n = CGFloat(subviews.count)
        var x = bounds.midX - (n * side + spacing * max(n - 1, 0)) / 2
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: side, height: side))
            x += side + spacing
        }
    }
}
