import Foundation
import Testing
@testable import ClaudemonCore

struct FloatingFormTests {

    @Test func `Raw values are pinned`() {
        #expect(FloatingForm.allCases.map(\.rawValue) == ["rings", "slim", "mini"])
    }

    @Test func `Double-click cycles rings, slim, mini`() {
        #expect(FloatingForm.rings.next == .slim)
        #expect(FloatingForm.slim.next == .mini)
        #expect(FloatingForm.mini.next == .rings)
    }

    @Test func `Picker labels`() {
        #expect(FloatingForm.allCases.map(\.label) == ["Rings", "Slim", "Mini"])
    }

    @Test func `Legacy compact flag maps to a form`() {
        #expect(FloatingForm(legacyCompact: true) == .mini)
        #expect(FloatingForm(legacyCompact: false) == .rings)
    }
}
