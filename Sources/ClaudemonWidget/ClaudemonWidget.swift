import WidgetKit
import SwiftUI
import ClaudemonCore

// MARK: - Timeline entry

struct UsageEntry: TimelineEntry {
    let date: Date
    /// The cached report, or nil when no cache is available yet.
    let report: UsageReport?
    /// When the shown data was captured (for the "updated" line).
    let capturedAt: Date?
    let isStale: Bool
    /// Exact straight-edged bar fills (app setting, shared via the App Group
    /// defaults suite).
    let preciseBars: Bool
    /// Count down from 100% (app setting, shared the same way).
    let showsRemaining: Bool
}

// MARK: - Provider (network-free: reads ONLY the App Group cache)

struct UsageProvider: TimelineProvider {

    private let cache = SharedUsageCache.shared

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), report: Self.sampleReport, capturedAt: Date(),
                   isStale: false, preciseBars: false, showsRemaining: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = makeEntry()
        // Best-effort glance view: ask the system to refresh in ~15 minutes.
        // The app also pushes reloads when values change.
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    /// Build an entry from the shared cache, falling back gracefully.
    private func makeEntry() -> UsageEntry {
        let precise = SharedPreference.preciseBars.read()
        let remaining = SharedPreference.showsRemaining.read()
        guard let cached = cache.read() else {
            return UsageEntry(date: Date(), report: nil, capturedAt: nil,
                              isStale: false, preciseBars: precise, showsRemaining: remaining)
        }
        return UsageEntry(
            date: Date(),
            report: cached.report,
            // The report's own capture time, not the cache write time: after
            // a failed fetch the app rewrites the cache with the old report,
            // and "last update" must name when that data was captured.
            capturedAt: cached.report?.capturedAt,
            isStale: cached.state != .ok,
            preciseBars: precise,
            showsRemaining: remaining
        )
    }

    /// Sample data for placeholder/preview.
    static var sampleReport: UsageReport {
        UsageReport(metrics: [
            UsageMetric(kind: .session, rawLabel: "Session", percent: 27, resetDate: nil, timezoneIdentifier: nil),
            UsageMetric(kind: .weekAll, rawLabel: "Week", percent: 29, resetDate: nil, timezoneIdentifier: nil),
            UsageMetric(kind: .weekModel, rawLabel: "Current week (Fable)", percent: 2, resetDate: nil, timezoneIdentifier: nil)
        ], capturedAt: Date())
    }
}

// MARK: - Widget definition

struct ClaudemonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: claudemonWidgetKind, provider: UsageProvider()) { entry in
            ClaudemonWidgetView(entry: entry)
                .widgetChrome(entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Your Claude Code usage limits at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// The floating window's layout as a medium widget: a ring per limit.
struct ClaudemonRingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: claudemonRingsWidgetKind, provider: UsageProvider()) { entry in
            Group {
                if let report = entry.report {
                    RingsUsageView(report: report, capturedAt: entry.capturedAt, isStale: entry.isStale)
                } else {
                    EmptyUsageView()
                }
            }
            .widgetChrome(entry)
        }
        .configurationDisplayName("Claude Usage Rings")
        .description("Every usage limit as a ring, like the floating window.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct ClaudemonWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudemonWidget()
        ClaudemonRingsWidget()
    }
}

private extension View {
    /// The app's display settings plus the standard widget background.
    func widgetChrome(_ entry: UsageEntry) -> some View {
        environment(\.showsRemainingUsage, entry.showsRemaining)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}
