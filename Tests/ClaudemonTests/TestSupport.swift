import Foundation

/// A uniquely named temporary directory that exists for the lifetime of this
/// object. Swift Testing creates a fresh suite instance per test, so a suite
/// holding one gets its own directory, removed when the test's instance goes
/// away.
final class TemporaryDirectory: Sendable {
    let url: URL

    init(prefix: String) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A uniquely named, initially empty `UserDefaults` suite that is deleted
/// when this object goes away, so settings a test writes never leak into
/// other tests or later runs.
final class TestDefaults {
    let defaults: UserDefaults
    private let suiteName = "claudemon-tests-\(UUID().uuidString)"

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// A fixed wall-clock instant in the given IANA timezone, for deterministic
/// date fixtures.
func makeDate(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
    tz: String = "Europe/Istanbul"
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: tz)!
    let components = DateComponents(year: year, month: month, day: day,
                                    hour: hour, minute: minute, second: second)
    return calendar.date(from: components)!
}
