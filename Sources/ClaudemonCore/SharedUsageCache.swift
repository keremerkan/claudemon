import Foundation
import os

/// Lightweight logger for App Group container diagnostics. A file-private
/// constant so it is created once and never allocates per call.
private let sharedUsageCacheLogger = Logger(
    subsystem: "com.claudemon.app",
    category: "SharedUsageCache"
)

/// The single, canonical App Group identifier used by BOTH the app (writer) and
/// the widget (reader). It is the team-prefixed ID declared in both
/// `Support/Claudemon.entitlements` and `Support/ClaudemonWidget.entitlements`.
/// There is intentionally NO fallback: writer and reader must resolve the exact
/// same container, otherwise the widget silently reads a divergent stale file.
public let claudemonAppGroupID = "GH4CGS3B5H.group.com.claudemon.app"

/// The widget kind strings. Kinds identify placed widgets, so never rename
/// them: a placed widget whose kind disappears goes blank.
public let claudemonWidgetKind = "ClaudemonWidget"
public let claudemonRingsWidgetKind = "ClaudemonRingsWidget"

/// A display preference shared between the app (writer) and the widget
/// (reader) through the App Group defaults suite — the widget runs in its own
/// process and cannot see the app's standard defaults. Absent reads as false.
public struct SharedPreference: Sendable {
    public let key: String

    /// Exact straight-edged bar fills instead of the min-sliver capsule.
    public static let preciseBars = SharedPreference(key: "preciseBarFill")
    /// Show what's left of each limit (100% → 0%) instead of what's used.
    public static let showsRemaining = SharedPreference(key: "showsRemainingUsage")

    /// `defaults` is injectable for tests; production uses the App Group suite.
    public func read(from defaults: UserDefaults? = UserDefaults(suiteName: claudemonAppGroupID)) -> Bool {
        defaults?.bool(forKey: key) ?? false
    }

    public func write(_ value: Bool, to defaults: UserDefaults? = UserDefaults(suiteName: claudemonAppGroupID)) {
        defaults?.set(value, forKey: key)
    }
}

/// High-level freshness flag persisted alongside the cached report.
public enum CachedUsageState: String, Codable, Sendable {
    case ok       // last write was a successful fresh poll
    case stale    // app is showing last-good data but the latest poll failed
    case error    // no data and an error
}

/// The full payload written to the App Group container.
public struct CachedUsage: Codable, Sendable {
    public let report: UsageReport?
    public let state: CachedUsageState
}

/// Reads/writes the latest `UsageReport` (as JSON) into the App Group container
/// so the network-free widget can read it. The app writes; the widget reads.
public struct SharedUsageCache: Sendable {

    public static let shared = SharedUsageCache()

    private static let fileName = "usage-cache.json"

    /// The cache file, or nil when the App Group container can't be resolved.
    private let fileURL: URL?

    /// The cache in the App Group container (production).
    public init() {
        // Resolve the ONE canonical App Group container. The non-sandboxed app
        // (writer) and the sandboxed widget (reader) run this identical logic, so
        // they converge on the exact same directory. There is deliberately no
        // fallback to another identifier: a silent fallback let the writer and
        // reader land in different containers, leaving the widget frozen on a
        // stale file.
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: claudemonAppGroupID) else {
            // Loud signal: the canonical container could not be resolved, so
            // the widget cache will not be shared. This surfaces signing or
            // entitlement regressions instead of silently producing an empty
            // (or stale) widget. We do NOT fall back to another container.
            sharedUsageCacheLogger.error(
                "App Group container could not be resolved for \(claudemonAppGroupID, privacy: .public); widget cache will not be shared."
            )
            fileURL = nil
            return
        }
        fileURL = container.appendingPathComponent(Self.fileName, conformingTo: .json)
    }

    /// A cache in an explicit directory (e.g. a temp dir), so tests can verify
    /// round-trips without the App Group entitlement.
    init(baseDirectory: URL) {
        fileURL = baseDirectory.appendingPathComponent(Self.fileName, conformingTo: .json)
    }

    // MARK: - Write (app side)

    /// Persist a cache payload. Silently no-ops if the container is unavailable
    /// (e.g. running unsandboxed without the entitlement).
    private func write(_ cached: CachedUsage) {
        guard let url = fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cached)
            try data.write(to: url, options: .atomic)
        } catch {
            // Non-fatal: the live surfaces are unaffected by a cache write miss.
        }
    }

    /// The app's data is current: a fresh poll, or last-good data the CLI had
    /// nothing newer for.
    public func writeSuccess(_ report: UsageReport) {
        write(CachedUsage(report: report, state: .ok))
    }

    /// The latest poll failed; keep the last-good data.
    public func writeStale(_ report: UsageReport) {
        write(CachedUsage(report: report, state: .stale))
    }

    /// The latest poll failed and there is no data to show.
    public func writeError() {
        write(CachedUsage(report: nil, state: .error))
    }

    // MARK: - Read (widget side)

    /// Read the most recent cache payload, or nil if none exists / unreadable.
    public func read() -> CachedUsage? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedUsage.self, from: data)
    }
}
