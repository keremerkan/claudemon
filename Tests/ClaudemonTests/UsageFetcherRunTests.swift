import Foundation
import Testing
@testable import Claudemon

/// Tests for the child-process runner behind both the usage fetch and the
/// shell lookup of `claude`. A child that never finishes must end in
/// `.timedOut` instead of stalling every later usage check.
struct UsageFetcherRunTests {

    private func isTimeout(_ error: any Error) -> Bool {
        if case UsageFetchError.timedOut = error { return true }
        return false
    }

    @Test func `Collects status, stdout and stderr`() async throws {
        let output = try await UsageFetcher.run(
            "/bin/sh", arguments: ["-c", "echo out; echo err >&2; exit 3"], timeout: 10)

        #expect(output.status == 3)
        #expect(String(decoding: output.stdout, as: UTF8.self) == "out\n")
        #expect(String(decoding: output.stderr, as: UTF8.self) == "err\n")
    }

    @Test func `A child that reads input gets end-of-file instead of waiting`() async throws {
        // `read` fails at once on the null device; with a terminal or an open
        // pipe as stdin it would wait until the timeout.
        let output = try await UsageFetcher.run(
            "/bin/sh", arguments: ["-c", "read answer; echo done"], timeout: 10)

        #expect(String(decoding: output.stdout, as: UTF8.self) == "done\n")
    }

    @Test func `A child that never exits times out`() async {
        await #expect(performing: {
            _ = try await UsageFetcher.run("/bin/sh", arguments: ["-c", "sleep 30"], timeout: 0.5)
        }, throws: isTimeout)
    }

    @Test func `A grandchild holding the output open times out`() async {
        // The shell exits at once, but the background sleep inherits its
        // stdout, so the pipe never reaches end-of-file.
        await #expect(performing: {
            _ = try await UsageFetcher.run("/bin/sh", arguments: ["-c", "sleep 30 & echo started"], timeout: 0.5)
        }, throws: isTimeout)
    }

    @Test func `A missing executable fails to launch`() async {
        await #expect(performing: {
            _ = try await UsageFetcher.run("/nonexistent/claudemon-test-binary", arguments: [], timeout: 10)
        }, throws: { error in
            if case UsageFetchError.launchFailed = error { return true }
            return false
        })
    }
}
