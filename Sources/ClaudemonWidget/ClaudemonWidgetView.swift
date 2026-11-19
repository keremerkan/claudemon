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

// MARK: - Small: the primary limit's ring

/// Only the main limit, as a ring: `UsageReport.primary` (the session, or the
/// all-models week for accounts without a session limit). The medium widget
/// lists every limit.
struct SmallUsageView: View {
    let report: UsageReport
    let capturedAt: Date?
    let isStale: Bool

    private var primary: UsageMetric? { report.primary }

    @Environment(\.showsRemainingUsage) private var showsRemaining

    var body: some View {
        RingsOverFooter {
            ring
        } footer: {
            UpdatedText(capturedAt: capturedAt, isStale: isStale, font: .callout)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(primary.map {
            "\($0.shortLabel) \(UsageDisplay.spoken($0.percent, remaining: showsRemaining))"
        } ?? "No usage data")
    }

    /// The shared ring gauge; it scales itself to the largest square that fits.
    private var ring: some View {
        UsageRingGauge(percent: primary?.percent,
                       caption: primary?.shortLabel ?? UsageMetric.Kind.session.shortName)
    }
}

// MARK: - Medium: every limit as a ring (the floating window's layout)

/// A ring per limit, the main one first, over an "updated · resets" line:
/// the same layout and wording as the app's floating window.
struct RingsUsageView: View {
    let report: UsageReport
    let capturedAt: Date?
    let isStale: Bool

    @Environment(\.showsRemainingUsage) private var showsRemaining

    var body: some View {
        RingsOverFooter {
            UsageRingRow(report: report, spacing: 16)
        } footer: {
            UpdatedText(capturedAt: capturedAt, isStale: isStale,
                        suffix: report.primary.flatMap(UsageFormatting.resetHint(for:)),
                        font: .callout)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(report.metrics
            .map { "\($0.shortLabel) \(UsageDisplay.spoken($0.percent, remaining: showsRemaining))" }
            .joined(separator: ", "))
    }
}

// MARK: - Shared pieces

/// Rings over a one-line footer, the rings taking all the height the footer
/// doesn't need. When the rings are height-bound they sit flush with the top
/// margin and the footer with the bottom; when width-bound (three rings) the
/// pair is centered, so the top and bottom gaps match either way.
private struct RingsOverFooter<Rings: View, Footer: View>: View {
    @ViewBuilder let rings: Rings
    @ViewBuilder let footer: Footer

    /// Blank space a `.callout` line keeps below its baseline. The footer ends
    /// with it, so the rings get the same inset on top and the visible gaps to
    /// the top and bottom edges match.
    private static var footerDescent: CGFloat {
        -NSFont.preferredFont(forTextStyle: .callout).descender
    }

    var body: some View {
        VStack(spacing: 0) {
            rings
                .padding(.top, Self.footerDescent)
                .layoutPriority(1)

            footer
                // Claim the text's full height up front. Without this the
                // stack only reserves its minimumScaleFactor height, hands the
                // rest to the rings, then draws full-size text and overflows.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "updated 14:32" (plus an optional " · suffix"), or "last update 14:32" in
/// orange when the app's latest fetch failed: the floating window's wording.
private struct UpdatedText: View {
    let capturedAt: Date?
    let isStale: Bool
    var suffix: String?
    let font: Font

    var body: some View {
        if let capturedAt {
            let clock = UsageFormatting.shortClockString(capturedAt)
            Text((isStale ? "last update " : "updated ") + clock + (suffix.map { " · " + $0 } ?? ""))
                .font(font)
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

    @Environment(\.showsRemainingUsage) private var showsRemaining

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // The needle follows the main limit (see `UsageReport.primary`).
                Image(systemName: UsageGauge.symbolName(
                    for: report.primary.map { UsageDisplay.percent($0.percent, remaining: showsRemaining) }))
                    .foregroundStyle(.tint)
                Text("Claude Usage")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                UpdatedText(capturedAt: capturedAt, isStale: isStale, font: .caption2)
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
                Text("\(UsageDisplay.percent(metric.percent, remaining: showsRemaining))%")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(UsageColor.color(for: metric.percent))
            }
            UsageBar(percent: metric.percent, height: 6, precise: preciseBars)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.displayLabel), \(UsageDisplay.spoken(metric.percent, remaining: showsRemaining))")
    }
}

// MARK: - Empty / no-cache state

struct EmptyUsageView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: UsageGauge.symbolName(for: nil))
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
