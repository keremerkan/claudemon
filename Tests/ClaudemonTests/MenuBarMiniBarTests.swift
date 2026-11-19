import Foundation
import Testing
@testable import ClaudemonCore

/// Unit tests for the pure value-level logic in `MenuBarMiniBar.swift`: the
/// `MenuBarDisplayMode` enum that drives the menu-bar label presentation.
struct MenuBarMiniBarTests {

    // MARK: - MenuBarDisplayMode

    @Test(arguments: MenuBarDisplayMode.allCases)
    func `Display mode raw value round-trips and matches its id`(mode: MenuBarDisplayMode) {
        #expect(MenuBarDisplayMode(rawValue: mode.rawValue) == mode,
                "rawValue round-trip must reconstruct the same case (persistence relies on this)")
        #expect(mode.id == mode.rawValue)
    }

    @Test func `Display mode rejects unknown raw values`() {
        #expect(MenuBarDisplayMode(rawValue: "notAMode") == nil)
        #expect(MenuBarDisplayMode(rawValue: "") == nil)
        // A removed/unknown rawValue must no longer resolve, so persisted old
        // bar values fall back to the default at the call site.
        #expect(MenuBarDisplayMode(rawValue: "removedLegacyMode") == nil)
    }

    @Test func `Display mode case order`() {
        #expect(MenuBarDisplayMode.allCases == [.iconAndText, .textOnly, .iconOnly, .bars],
                "Order is user-facing (drives the settings Picker) — pin it down")
    }

    // MARK: - MenuBarWeekBarSource

    @Test(arguments: MenuBarWeekBarSource.allCases)
    func `Week bar source raw value round-trips and matches its id`(source: MenuBarWeekBarSource) {
        #expect(MenuBarWeekBarSource(rawValue: source.rawValue) == source)
        #expect(source.id == source.rawValue)
    }

    @Test func `Week bar source maps to metric kinds in picker order`() {
        #expect(MenuBarWeekBarSource(rawValue: "sonnet") == nil)
        #expect(MenuBarWeekBarSource.allModels.metricKind == .weekAll)
        #expect(MenuBarWeekBarSource.perModel.metricKind == .weekModel)
        #expect(MenuBarWeekBarSource.allCases == [.allModels, .perModel],
                "Order is user-facing (drives the settings Picker)")
    }

    // MARK: - MenuBarBarsView.Configuration

    @Test func `Bars configuration equality covers every field`() {
        let base = MenuBarBarsView.Configuration(
            primaryPercent: 40, weekPercent: 20, showsPercent: true, isVertical: false)
        #expect(base == MenuBarBarsView.Configuration(
            primaryPercent: 40, weekPercent: 20, showsPercent: true, isVertical: false))

        #expect(!base.preciseFill, "preciseFill must default to false")
        #expect(!base.halfWidthBars, "halfWidthBars must default to false")

        // Each field independently participates in equality — the app relies
        // on this to know when the menu-bar raster must change.
        var changed = base
        changed.primaryPercent = 41
        #expect(base != changed)

        changed = base
        changed.weekPercent = nil
        #expect(base != changed)

        changed = base
        changed.showsPercent = false
        #expect(base != changed)

        changed = base
        changed.isVertical = true
        #expect(base != changed)

        changed = base
        changed.preciseFill = true
        #expect(base != changed)

        changed = base
        changed.halfWidthBars = true
        #expect(base != changed)
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

    @Test func `Shared preferences use distinct keys`() {
        // The widget reads these by key; the precise-bars key predates the
        // shared type and must not change, or users lose their setting.
        #expect(SharedPreference.preciseBars.key == "preciseBarFill")
        #expect(SharedPreference.preciseBars.key != SharedPreference.showsRemaining.key)
    }
}
