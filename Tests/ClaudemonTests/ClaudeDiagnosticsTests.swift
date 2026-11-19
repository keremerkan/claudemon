import Testing
@testable import ClaudemonCore

/// Tests for the pure auth-failure stderr classifier. These guard against
/// false positives (a generic error misread as "Sign in") for the npm/nvm
/// friend audience.
struct ClaudeDiagnosticsTests {

    @Test(arguments: [
        "Invalid API key · please run /login",
        "Error: you are not logged in",
        "401 Unauthorized",
        "Authentication required",
        "Please log in to continue",
        "No subscription found for this account",
    ])
    func `Classifies as an auth failure`(stderr: String) {
        #expect(ClaudeDiagnostics.looksLikeAuthFailure(stderr: stderr))
    }

    @Test(arguments: [
        "network error: connection reset",
        // The whole point of dropping the bare "login" needle: "logging" must
        // NOT match.
        "logging output enabled",
        "TypeError: cannot read property of undefined",
        "",
    ])
    func `Does not classify as an auth failure`(stderr: String) {
        #expect(!ClaudeDiagnostics.looksLikeAuthFailure(stderr: stderr))
    }
}
