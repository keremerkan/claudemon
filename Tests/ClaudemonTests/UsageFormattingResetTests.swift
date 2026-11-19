import Foundation
import Testing
@testable import ClaudemonCore

/// Tests for the timezone-aware 24-hour clock formatter used by the floating
/// widget footer's "resets at HH:mm" suffix. All cases are deterministic: the
/// Date is built from a fixed epoch and an explicit TimeZone is supplied, so
/// results never depend on the host machine's locale or timezone.
struct UsageFormattingResetTests {

    /// 2026-06-28 20:20:00 UTC.
    private let fixedDate = Date(timeIntervalSince1970: 1_782_678_000)

    @Test func `Short clock string in Istanbul`() {
        // Istanbul is UTC+3 in June: 20:20 UTC -> 23:20.
        let tz = TimeZone(identifier: "Europe/Istanbul")
        #expect(UsageFormatting.shortClockString(fixedDate, timeZone: tz) == "23:20")
    }

    @Test func `Short clock string in New York`() {
        // New York is UTC-4 (EDT) in June: 20:20 UTC -> 16:20.
        let tz = TimeZone(identifier: "America/New_York")
        #expect(UsageFormatting.shortClockString(fixedDate, timeZone: tz) == "16:20")
    }

    @Test func `Short clock string is zero-padded across midnight`() {
        // 2026-06-28 23:05:00 UTC -> Tokyo (UTC+9) is 08:05 next day.
        let date = Date(timeIntervalSince1970: 1_782_687_900)
        let tz = TimeZone(identifier: "Asia/Tokyo")
        #expect(UsageFormatting.shortClockString(date, timeZone: tz) == "08:05")
    }

    @Test func `Nil time zone falls back to current`() {
        // A nil timezone must behave exactly like the existing zero-arg helper,
        // which formats in the current timezone.
        #expect(
            UsageFormatting.shortClockString(fixedDate, timeZone: nil)
                == UsageFormatting.shortClockString(fixedDate)
        )
    }
}
