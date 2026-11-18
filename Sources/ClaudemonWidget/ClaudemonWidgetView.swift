import AppKit
import WidgetKit
import SwiftUI
import ClaudemonCore

/// Widget body: switches layout by family. Reuses ClaudemonCore color/format.
struct ClaudemonWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        if let report = entry.report {
            switch family {
            case .systemSmall:
                SmallUsageView(report: report, capturedAt: entry.capturedAt, isStale: entry.isStale)
            default:
                MediumUsageView(report: report, capturedAt: entry.capturedAt,
                                isStale: entry.isStale, preciseBars: entry.preciseBars)
            }
        } else {
            EmptyUsageView()
        }
    }
}

// MARK: - Small: primary-limit ring + the next limit's percent

/// The ring shows `UsageReport.primary` (the session, or the all-models week
/// for accounts without a session limit); the line below it shows the first
/// remaining limit.
struct SmallUsageView: View {
    let report: UsageReport
    let capturedAt: Date?
    let isStale: Bool

    private var primary: UsageMetric? { report.primary }
    private var ringPercent: Int { primary?.percent ?? 0 }
    private var ringLabel: String { primary?.shortLabel ?? UsageMetric.Kind.session.shortName }
    private var next: UsageMetric? { report.secondary.first }

    /// Blank space a `.callout` line keeps below its baseline. The "as of"
    /// line ends with it, so the ring gets the same inset on top and the
    /// visible gaps to the top and bottom edges match.
    private static let footerDescent = -NSFont.preferredFont(forTextStyle: .callout).descender

    var body: some View {
        // The ring sits at the top edge and the text block at the bottom edge,
        // so both get the same widget content margin. The ring takes all the
        // height the text doesn't need.
        VStack(spacing: 0) {
            ring
                .padding(.top, Self.footerDescent)
                .layoutPriority(1)

            VStack(spacing: 2) {
                if let next {
                    HStack(spacing: 4) {
                        Text(next.shortLabel)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("\(next.percent)%")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(UsageColor.color(for: next.percent))
                    }
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                }

                footerLine
            }
            // Claim the text's full height up front. Without this the stack
            // only reserves its minimumScaleFactor height, hands the rest to
            // the ring, then draws full-size text and overflows the margins.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([primary, next].compactMap { $0 }
            .map { "\($0.shortLabel) \($0.percent) percent" }
            .joined(separator: ", "))
    }

    /// Ring that scales to fill the available width using GeometryReader.
    private var ring: some View {
        GeometryReader { geo in
            let diameter = min(geo.size.width, geo.size.height)
            let lineWidth = max(diameter * 0.10, 4)
            let percentFont = diameter * 0.30
            let captionFont = diameter * 0.11

            ZStack {
                UsageRing(percent: ringPercent, lineWidth: lineWidth)
                VStack(spacing: 1) {
                    Text("\(ringPercent)%")
                        .font(.system(size: percentFont, weight: .bold).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(ringLabel)
                        .font(.system(size: captionFont, weight: .medium))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(lineWidth)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder private var footerLine: some View {
        if let capturedAt {
            Text("\(isStale ? "stale · " : "")as of \(UsageFormatting.shortClockString(capturedAt))")
                .font(.callout)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(isStale ? .orange : .secondary)
        }
    }
}

// MARK: - Medium: all three metrics as labeled bars

struct MediumUsageView: View {
    let report: UsageReport
    let capturedAt: Date?
    let isStale: Bool
    let preciseBars: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .foregroundStyle(.tint)
                Text("Claude Usage")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let capturedAt {
                    Text("\(isStale ? "stale · " : "")as of \(UsageFormatting.shortClockString(capturedAt))")
                        .font(.caption2)
                        .foregroundStyle(isStale ? .orange : .secondary)
                }
            }

            ForEach(report.metrics) { metric in
                bar(for: metric)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bar(for metric: UsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(metric.shortLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(metric.percent)%")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(UsageColor.color(for: metric.percent))
            }
            UsageBar(percent: metric.percent, height: 6, precise: preciseBars)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.displayLabel), \(metric.percent) percent")
    }
}

// MARK: - Empty / no-cache state

struct EmptyUsageView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Open Claudemon")
                .font(.subheadline.weight(.medium))
            Text("to load your usage")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No data. Open Claudemon to load your usage.")
    }
}
