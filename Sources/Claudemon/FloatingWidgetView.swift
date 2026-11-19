import SwiftUI
import ClaudemonCore

/// Compact always-on-top widget content. Renders one of two forms:
/// - LARGE: a ring for the primary limit + bars for the other limits + footer.
/// - MINI:  just the ring (percent + "SESSION", or "WEEK" for accounts
///          without a session limit; see `UsageReport.primary`).
/// Double-clicking the panel toggles between them (wired in the controller).
struct FloatingWidgetView: View {

    /// Content sizes for each form, shared with `FloatingPanelController` so it
    /// can resize the hosting panel to match the rendered form.
    static let largeContentSize = CGSize(width: 210, height: 112)
    static let miniContentSize = CGSize(width: 88, height: 88)

    let store: UsageStore

    private var showOnboarding: Bool {
        !hasData && (store.isNotInstalled || store.isNotSignedIn)
    }

    /// Onboarding has nothing meaningful to show in the mini ring, so it always
    /// falls back to the large form.
    private var isCompact: Bool { store.floatingCompact && !showOnboarding }

    var body: some View {
        Group {
            if isCompact {
                miniBody
            } else {
                largeBody
            }
        }
        // Allow dragging the borderless panel from anywhere on the surface.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Double-click to switch between the mini and full view")
        .environment(\.showsRemainingUsage, store.showsRemaining)
    }

    // MARK: - Large form

    private var largeBody: some View {
        Group {
            if showOnboarding {
                onboardingContent
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 14) {
                        primaryRing
                        weeklyColumn
                    }
                    footer
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .panelChrome(size: Self.largeContentSize)
    }

    // MARK: - Mini form

    /// A single, larger ring centered in a compact rounded-square panel.
    /// Reuses the exact ring rendering/colors of the large form.
    private var miniBody: some View {
        ringView(diameter: 69, lineWidth: 7, percentFont: 18, labelFont: 8)
            .panelChrome(size: Self.miniContentSize)
    }

    // MARK: - Onboarding (calm)

    private var onboardingContent: some View {
        VStack(spacing: 8) {
            Image(systemName: store.isNotInstalled ? "shippingbox" : "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(store.isNotInstalled ? "Claude Code isn't installed" : "Sign in to Claude Code")
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(store.isNotInstalled ? "Install the CLI, then Claudemon picks it up." : "Run claude, then /login.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var primary: UsageMetric? { store.primaryMetric }
    private var primaryPercent: Int { primary?.percent ?? 0 }

    private var hasData: Bool { store.lastGoodReport != nil }

    // MARK: - Ring

    /// The large form's ring (preserved sizing).
    private var primaryRing: some View {
        ringView(diameter: 65, lineWidth: 7, percentFont: 17, labelFont: 8)
    }

    /// Shared ring rendering for the primary limit, used by both the large and
    /// mini forms. Same track/trim/color logic; only the dimensions and type
    /// scale differ.
    private func ringView(
        diameter: CGFloat,
        lineWidth: CGFloat,
        percentFont: CGFloat,
        labelFont: CGFloat
    ) -> some View {
        ZStack {
            UsageRing(percent: primaryPercent, lineWidth: lineWidth)
            VStack(spacing: 1) {
                if hasData {
                    Text("\(store.shownPercent(primaryPercent))%")
                        .font(.system(size: percentFont, weight: .bold).monospacedDigit())
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: store.errorMessage != nil ? "exclamationmark.triangle" : "ellipsis")
                        .font(.system(size: percentFont * 0.82, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Text(primary?.shortLabel ?? UsageMetric.Kind.session.shortName)
                    .font(.system(size: labelFont, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: - Right column

    private var weeklyColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let report = store.lastGoodReport {
                ForEach(report.secondary) { metric in
                    metricLine(label: metric.shortLabel, percent: metric.percent)
                }
            } else {
                metricLine(label: UsageMetric.Kind.weekAll.shortName, percent: nil)
                metricLine(label: UsageMetric.Kind.weekModel.shortName, percent: nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A labeled bar; a nil percent (no data yet) shows a dash and an empty bar.
    private func metricLine(label: String, percent: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(percent.map { "\(store.shownPercent($0))%" } ?? "—")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(percent.map { UsageColor.color(for: $0) } ?? .secondary)
            }
            UsageBar(percent: percent ?? 0, height: 5, precise: store.preciseBars)
        }
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        HStack(spacing: 4) {
            if !hasData {
                // No data yet OR genuine error with nothing to show.
                if let error = store.errorMessage {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Waiting for usage data…")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if store.isStaleError {
                // A real failure while showing last-good data — calm orange hint.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                Text(footerTimeText(prefix: "last update "))
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                // Fresh OR stale-render (no new limit lines this cycle): calm.
                Text(footerTimeText(prefix: "updated "))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footerTimeText(prefix: String) -> String {
        guard let updated = store.lastUpdated else { return prefix.trimmingCharacters(in: .whitespaces) }
        let resetSuffix = resetHint.map { " · " + $0 } ?? ""
        let staleHint = (store.dataAge ?? 0) > 10 * 60 ? " · stale" : ""
        return prefix + UsageFormatting.shortClockString(updated) + resetSuffix + staleHint
    }

    /// When the primary limit resets, in its own timezone: "resets at HH:mm"
    /// for the 5-hour session, "resets Nov 19" for a week. Nil without a date.
    private var resetHint: String? {
        guard let primary, let resetDate = primary.resetDate else { return nil }
        return primary.kind == .session
            ? "resets at " + UsageFormatting.shortClockString(resetDate, timeZone: primary.timezone)
            : "resets " + UsageFormatting.shortDateString(resetDate, timeZone: primary.timezone)
    }

    private var accessibilitySummary: String {
        if store.isNotInstalled { return "Claude Code isn't installed. Install the CLI to see usage." }
        if store.isNotSignedIn { return "Sign in to Claude Code. Run claude then slash login." }
        guard let report = store.lastGoodReport else { return store.errorMessage ?? "Loading usage" }
        var summary = report.metrics
            .map { "\($0.shortLabel) \(UsageDisplay.spoken($0.percent, remaining: store.showsRemaining))" }
            .joined(separator: ", ")
        if let resetHint, let primary {
            summary += ", \(primary.shortLabel.lowercased()) \(resetHint)"
        }
        return summary
    }
}

private extension View {
    /// The floating panel's fixed size, frosted rounded background and
    /// hairline border, shared by the large and mini forms.
    func panelChrome(size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        return frame(width: size.width, height: size.height)
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.08))
            }
    }
}
