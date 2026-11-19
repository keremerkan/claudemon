import Foundation
import Testing
@testable import Claudemon

/// Regression tests for the spawn-environment builder. The `claude` CLI returns
/// a generic EMPTY body (exit 0, no metrics) when `USER` is missing from its
/// environment, which made the app hang on "Waiting for usage data…" forever
/// when launched as a login item (launchd gives a minimal env without USER).
/// `makeEnvironment` must therefore guarantee USER/LOGNAME are present.
struct UsageFetcherEnvTests {

    private let workingDir = URL(fileURLWithPath: "/tmp/claudemon-env-test", isDirectory: true)

    @Test func `Env includes USER and LOGNAME when the base lacks them`() {
        // Base env deliberately WITHOUT USER/LOGNAME (mirrors a launchd login item).
        let base = ["PATH": "/usr/bin"]
        let env = UsageFetcher.makeEnvironment(base: base, workingDir: workingDir)

        #expect(env["USER"] == NSUserName(),
                "USER must be set to the current user even when the base env lacks it")
        #expect(env["LOGNAME"] == NSUserName(),
                "LOGNAME must be set to the current user even when the base env lacks it")
        #expect(!(env["USER"]?.isEmpty ?? true))
        #expect(!(env["LOGNAME"]?.isEmpty ?? true))
    }

    @Test func `Env overrides a preexisting USER with the current user`() {
        // Even if a (stale/wrong) USER is present, normalize to the real user.
        let base = ["USER": "someone-else", "LOGNAME": "someone-else"]
        let env = UsageFetcher.makeEnvironment(base: base, workingDir: workingDir)

        #expect(env["USER"] == NSUserName())
        #expect(env["LOGNAME"] == NSUserName())
    }

    @Test func `Env still neutralizes working dir and PATH`() {
        // The pre-existing PATH/PWD/OLDPWD behaviour must be unchanged.
        let base = ["PATH": "/custom/bin"]
        let env = UsageFetcher.makeEnvironment(base: base, workingDir: workingDir)

        #expect(env["PWD"] == workingDir.path)
        #expect(env["OLDPWD"] == workingDir.path)
        #expect(env["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/custom/bin",
                "The homebrew PATH prepend must still wrap the base PATH")
    }
}
