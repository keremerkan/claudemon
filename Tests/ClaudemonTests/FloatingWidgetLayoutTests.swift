import Foundation
import Testing
@testable import Claudemon
@testable import ClaudemonCore

struct FloatingWidgetLayoutTests {

    private func metric(_ kind: UsageMetric.Kind, _ label: String, _ percent: Int) -> UsageMetric {
        UsageMetric(kind: kind, rawLabel: label, percent: percent, resetDate: nil, timezoneIdentifier: nil)
    }

    private func report(_ metrics: [UsageMetric]) -> UsageReport {
        UsageReport(metrics: metrics, capturedAt: makeDate(2026, 11, 20, 11, 39))
    }

    @Test func `Each form has its own size`() {
        #expect(FloatingWidgetView.contentSize(for: .rings) == CGSize(width: 210, height: 112))
        #expect(FloatingWidgetView.contentSize(for: .slim) == CGSize(width: 210, height: 60))
        #expect(FloatingWidgetView.contentSize(for: .mini) == CGSize(width: 88, height: 88))
    }

    @Test func `Slim shows session and week`() {
        let all = report([metric(.session, "Current session", 5),
                          metric(.weekAll, "Current week (all models)", 18),
                          metric(.weekModel, "Current week (Fable)", 0)])
        #expect(FloatingWidgetView.slimMetrics(all).map(\.kind) == [.session, .weekAll])
    }

    @Test func `Slim without a session limit shows both weeks`() {
        let weeks = report([metric(.weekAll, "Current week (all models)", 18),
                            metric(.weekModel, "Current week (Fable)", 4)])
        #expect(FloatingWidgetView.slimMetrics(weeks).map(\.kind) == [.weekAll, .weekModel])
    }

    @Test func `Slim with one limit or no data`() {
        let single = report([metric(.weekAll, "Current week (all models)", 18)])
        #expect(FloatingWidgetView.slimMetrics(single).map(\.kind) == [.weekAll])
        #expect(FloatingWidgetView.slimMetrics(nil).isEmpty)
    }
}
