import SwiftUI
import ClaudemonCore

/// Compact always-on-top widget content. Renders one of two forms:
/// - LARGE: a ring per limit, the primary first (see `UsageReport.primary`
///          and `.secondary`), above a footer.
/// - MINI:  just the primary ring (percent + "SESSION", or "WEEK" for
///          accounts without a session limit).
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
                    rings
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
        UsageRingGauge(percent: primary?.percent,
                       caption: primary?.shortLabel ?? UsageMetric.Kind.session.shortName,
                       placeholderSymbol: placeholderSymbol)
            .frame(width: 69, height: 69)
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

    private var hasData: Bool { store.lastGoodReport != nil }

    // MARK: - Rings

    /// The rings' height in the large form: the most a ring may be, which also
    /// leaves room for the footer.
    private static let ringsHeight: CGFloat = 65

    /// One ring per limit, primary first (two fit at full size; three share
    /// the width). Before any data arrives, a single placeholder ring.
    private var rings: some View {
        UsageRingRow(report: store.lastGoodReport, spacing: 12, maxDiameter: Self.ringsHeight,
                     placeholderSymbol: placeholderSymbol)
            .frame(height: Self.ringsHeight)
    }

    /// The waiting/error symbol for a ring without data.
    private var placeholderSymbol: String {
        store.errorMessage != nil ? "exclamationmark.triangle" : "ellipsis"
    }

    // MARK: - Footer

    /// One calm line: the error or waiting text without data, otherwise when
    /// the shown data was captured. Orange with a warning icon when the latest
    /// fetch failed while showing last-good data.
    private var footer: some View {
        HStack(spacing: 4) {
            if store.isStaleError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
            }
            Text(footerText)
                .font(.system(size: 9))
                .lineLimit(1)
        }
        .foregroundStyle(store.isStaleError ? .orange : .secondary)
        // Centered under the centered rings.
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var footerText: String {
        guard let updated = store.lastUpdated else {
            return store.errorMessage ?? "Waiting for usage data…"
        }
        return (store.isStaleError ? "last update " : "updated ")
            + UsageFormatting.shortClockString(updated)
            + (resetHint.map { " · " + $0 } ?? "")
            + store.staleHint()
    }

    /// When the primary limit resets (see `UsageFormatting.resetHint`).
    private var resetHint: String? {
        primary.flatMap(UsageFormatting.resetHint(for:))
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
