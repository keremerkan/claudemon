import Foundation
import Testing
@testable import ClaudemonCore

/// Tests for the process-free `claude` discovery used by the friend-failure fix.
struct ClaudeLocatorTests {

    private let tempHome: URL
    /// Keeps the fake home alive (and removes it afterwards) for one test.
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory(prefix: "claudemon-locator")
        tempHome = directory.url
    }

    private var locator: ClaudeLocator {
        ClaudeLocator(homeDirectory: tempHome.path, systemPaths: [])
    }

    /// Create an executable stub at the given relative path under the fake home.
    @discardableResult
    private func makeExecutable(at relativePath: String) throws -> String {
        let url = tempHome.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\necho hi\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    /// Resolved (symlink-canonical) form of a path, so /var vs /private/var
    /// temp-dir differences don't cause spurious failures.
    private func resolved(_ path: String?) -> String? {
        path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
    }

    @Test func `Finds claude in npm-global bin`() throws {
        let expected = try makeExecutable(at: ".npm-global/bin/claude")
        #expect(locator.locateFromFilesystem() == expected)
    }

    @Test func `Finds claude in pnpm dir`() throws {
        let expected = try makeExecutable(at: "Library/pnpm/claude")
        #expect(locator.locateFromFilesystem() == expected)
    }

    @Test func `Finds claude under nvm version glob`() throws {
        // nvm layout: ~/.nvm/versions/node/<version>/bin/claude
        let expected = try makeExecutable(at: ".nvm/versions/node/v22.3.0/bin/claude")
        #expect(resolved(locator.firstClaudeUnderGlobRoots()) == resolved(expected))
        #expect(resolved(locator.locateFromFilesystem()) == resolved(expected))
    }

    @Test func `Finds claude under fnm nested dir`() throws {
        // fnm nests node installs a few levels deep.
        let expected = try makeExecutable(at: ".fnm/node-versions/v20.11.1/installation/bin/claude")
        #expect(resolved(locator.firstClaudeUnderGlobRoots()) == resolved(expected))
    }

    @Test func `Returns nil when claude is missing everywhere`() {
        // Empty fake home, no claude anywhere the locator looks.
        #expect(locator.locateFromFilesystem() == nil,
                "A totally-missing claude must not be located from the filesystem")
    }

    @Test func `Ignores a non-executable file named claude`() throws {
        // A plain (non-executable) file named claude should NOT match.
        let url = tempHome.appendingPathComponent(".npm-global/bin/claude")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not executable".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        #expect(locator.locateFromFilesystem() == nil)
    }
}
