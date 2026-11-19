import Foundation
import Testing
@testable import ClaudemonCore

/// Tests for the menu-bar settings' stored values and order, and the display
/// preferences shared with the widget.
struct MenuBarMiniBarTests {

    // MARK: - Stored settings

    /// The raw values are what UserDefaults stores. Renaming a case would
    /// silently reset everyone's saved choice to the default, so pin them.
    @Test func `Persisted raw values are stable`() {
        #expect(MenuBarDisplayMode.allCases.map(\.rawValue) == ["iconAndText", "textOnly", "iconOnly", "bars"])
        #expect(MenuBarWeekBarSource.allCases.map(\.rawValue) == ["allModels", "perModel"])
    }

    @Test func `Display mode case order`() {
        #expect(MenuBarDisplayMode.allCases == [.iconAndText, .textOnly, .iconOnly, .bars],
                "Order is user-facing (drives the settings Picker) — pin it down")
    }

    @Test func `Week bar source maps to metric kinds in picker order`() {
        #expect(MenuBarWeekBarSource.allModels.metricKind == .weekAll)
        #expect(MenuBarWeekBarSource.perModel.metricKind == .weekModel)
        #expect(MenuBarWeekBarSource.allCases == [.allModels, .perModel],
                "Order is user-facing (drives the settings Picker)")
    }

    // MARK: - Shared display preferences

    @Test(arguments: [SharedPreference.preciseBars, .showsRemaining])
    func `Shared preference round-trips and defaults to false`(preference: SharedPreference) {
        let suite = TestDefaults()

        #expect(!preference.read(from: suite.defaults),
                "absent key must read as false (the default style)")
        preference.write(true, to: suite.defaults)
        #expect(preference.read(from: suite.defaults))
        preference.write(false, to: suite.defaults)
        #expect(!preference.read(from: suite.defaults))

        // A nil suite (unresolvable container) must fail soft to false.
        #expect(!preference.read(from: nil))
    }

    @Test func `Shared preference keys are stable`() {
        // The app writes and the widget reads these by key; changing one loses
        // the user's setting.
        #expect(SharedPreference.preciseBars.key == "preciseBarFill")
        #expect(SharedPreference.showsRemaining.key == "showsRemainingUsage")
    }
}
