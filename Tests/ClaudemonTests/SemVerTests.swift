import Testing
@testable import Claudemon

/// Unit tests for the minimal `major.minor.patch` `SemVer` used by the
/// "Check for Updates" comparison in `UpdateChecker`. These pin down parsing
/// (leading-`v` strip, missing components) and ordering semantics so a future
/// refactor of the update path can't silently break version comparison.
struct SemVerTests {

    // MARK: - Ordering

    @Test func `Patch ordering`() throws {
        let lower = try #require(SemVer("1.1.2"))
        let higher = try #require(SemVer("1.1.3"))
        #expect(lower < higher, "1.1.2 < 1.1.3")
        #expect(!(higher < lower))
    }

    @Test func `Minor outranks patch`() throws {
        let v120 = try #require(SemVer("1.2.0"))
        let v119 = try #require(SemVer("1.1.9"))
        #expect(v120 > v119, "1.2.0 > 1.1.9 (a higher minor beats a higher patch)")
    }

    // MARK: - Leading `v` strip

    @Test func `Leading v is stripped`() throws {
        let tagged = try #require(SemVer("v1.1.2"))
        let plain = try #require(SemVer("1.1.2"))
        #expect(tagged == plain, "v1.1.2 == 1.1.2")
        #expect(tagged.description == "1.1.2")
    }

    @Test func `Uppercase leading V is stripped`() throws {
        let tagged = try #require(SemVer("V2.0.1"))
        #expect(tagged == (try #require(SemVer("2.0.1"))))
    }

    // MARK: - Missing components default to zero

    @Test func `Missing patch defaults to zero`() throws {
        let short = try #require(SemVer("1.1"))
        let full = try #require(SemVer("1.1.0"))
        #expect(short == full, "1.1 == 1.1.0")
    }

    @Test func `Missing minor and patch still orders`() throws {
        let major = try #require(SemVer("2"))
        let lower = try #require(SemVer("1.9.9"))
        #expect(major > lower, "2 > 1.9.9 (2 parses as 2.0.0)")
        #expect(major.description == "2.0.0")
    }

    // MARK: - Equality

    @Test func `Equal versions are not ordered`() throws {
        let a = try #require(SemVer("1.1.2"))
        let b = try #require(SemVer("1.1.2"))
        #expect(a == b)
        #expect(!(a < b))
        #expect(!(b < a))
    }

    // MARK: - Rejects non-numeric / empty input

    @Test func `Non-numeric component fails to parse`() {
        #expect(SemVer("1.x.0") == nil, "Non-numeric components must not parse")
        #expect(SemVer("") == nil, "Empty string must not parse")
    }
}
