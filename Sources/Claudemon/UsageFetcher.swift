import Foundation
import os
import ClaudemonCore

/// Diagnostics logger for the fetch layer.
private let fetchLog = Logger(subsystem: "com.claudemon.app", category: "UsageFetcher")

/// Errors that can arise while invoking the `claude` CLI.
enum UsageFetchError: Error, LocalizedError {
    case claudeNotFound
    case notSignedIn
    case launchFailed(String)
    case timedOut
    case nonZeroExit(code: Int32, stderr: String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Claude Code isn't installed"
        case .notSignedIn:
            return "Sign in to Claude Code"
        case .launchFailed(let msg):
            return "Couldn't launch claude: \(msg)"
        case .timedOut:
            return "Claude CLI timed out"
        case .nonZeroExit(let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "claude exited (\(code))" + (detail.isEmpty ? "" : ": \(detail)")
        case .emptyOutput:
            return "Couldn't read usage"
        }
    }

    /// Heuristic: does a non-zero exit's stderr look like an auth / login issue?
    /// Delegates to the pure, unit-tested classifier in ClaudemonCore.
    static func looksLikeAuthFailure(stderr: String) -> Bool {
        ClaudeDiagnostics.looksLikeAuthFailure(stderr: stderr)
    }
}

/// Runs `claude -p "/usage" --output-format json` off the main thread and
/// returns the raw stdout JSON data.
struct UsageFetcher {

    /// A stable, app-owned, NON-protected working directory for child
    /// processes. We pin both spawns here so the `claude` CLI never anchors
    /// its scans at the user's home/project dir — which would otherwise cause
    /// macOS to attribute Documents/Desktop/Downloads/Photos (TCC) accesses to
    /// the unsandboxed Claudemon parent and trigger permission prompts.
    private static var neutralWorkingDirectoryURL: URL {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = caches.appendingPathComponent("com.claudemon.app", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // If creation failed for any reason, fall back to the temp dir, which is
        // always present and never a TCC-protected location.
        if fm.fileExists(atPath: dir.path) { return dir }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    /// Apply neutral directory anchors to an environment WITHOUT breaking
    /// credentials: KEEP HOME (claude needs it to find ~/.claude config), keep
    /// the PATH prepend, but point PWD/OLDPWD at the neutral dir so claude does
    /// not scan the previous working directory.
    private static func neutralizedEnvironment(workingDir: URL) -> [String: String] {
        makeEnvironment(base: ProcessInfo.processInfo.environment, workingDir: workingDir)
    }

    /// Pure, injectable environment builder so the spawn env is unit-testable.
    /// Given a base environment, apply the neutral directory anchors and PATH
    /// prepend, and GUARANTEE USER/LOGNAME are present.
    ///
    /// Why USER/LOGNAME matter: the `claude` CLI silently returns a generic
    /// empty body (exit 0, no metrics) when USER is absent from its environment.
    /// Finder-launched apps inherit USER, but launchd / login-item processes
    /// often get a minimal environment WITHOUT it — which made Claudemon hang on
    /// "Waiting for usage data…" forever after a login launch. `NSUserName()`
    /// returns the current user's short name even under launchd, so set it
    /// unconditionally.
    static func makeEnvironment(base: [String: String], workingDir: URL) -> [String: String] {
        var env = base
        let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = (env["PATH"].map { "\(extra):\($0)" }) ?? extra
        env["PWD"] = workingDir.path
        env["OLDPWD"] = workingDir.path
        env["USER"] = NSUserName()
        env["LOGNAME"] = NSUserName()
        return env
    }

    /// Cached resolved path for the session so we don't spawn a lookup shell on
    /// every poll. Cleared by `invalidateCache()` when a launch fails.
    private static let cachedClaudePath = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// Resolve the absolute path of the `claude` executable, or nil.
    /// Order: session cache → filesystem candidates/globs (ClaudeLocator) →
    /// login-shell fallback (zsh, then bash). The result is cached for the
    /// session.
    static func resolveClaudePath() -> String? {
        if let cached = cachedClaudePath.withLock({ $0 }) {
            return cached
        }

        let fm = FileManager.default

        // 1+2. Concrete candidate paths, then version-manager globs (nvm/fnm),
        // via the testable, process-free `ClaudeLocator` in ClaudemonCore.
        if let found = ClaudeLocator().locateFromFilesystem() {
            return cache(found)
        }

        // 3. Login-shell fallback so version-manager PATHs (set in rc files) load.
        //    Pinned to the neutral working dir + neutralized env so we do NOT
        //    reintroduce the TCC prompts. Try zsh, then bash.
        for shell in ["/bin/zsh", "/bin/bash"] where fm.isExecutableFile(atPath: shell) {
            if let resolved = whichClaude(shell: shell, login: true) {
                return cache(resolved)
            }
        }

        fetchLog.error("claude binary not found in candidate paths, globs, or login-shell lookup")
        return nil
    }

    private static func cache(_ path: String) -> String {
        cachedClaudePath.withLock { $0 = path }
        return path
    }

    /// Clear the cached resolved path so the next `resolveClaudePath()` re-runs
    /// full discovery. Called when a launch fails (e.g. an nvm/fnm node-version
    /// switch moved the binary), so the app self-heals without a restart.
    static func invalidateCache() {
        cachedClaudePath.withLock { $0 = nil }
    }

    /// Resolve `claude` via a shell's `command -v`. When `login` is true a login
    /// shell (`-lc`) sources the user's rc files so nvm/fnm/volta PATHs load.
    /// Always pinned to the neutral working dir with PWD/OLDPWD neutralized and
    /// HOME preserved, so the lookup never triggers TCC prompts.
    private static func whichClaude(shell: String, login: Bool) -> String? {
        let workingDir = neutralWorkingDirectoryURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = [login ? "-lc" : "-c", "command -v claude"]
        process.currentDirectoryURL = workingDir
        process.environment = neutralizedEnvironment(workingDir: workingDir)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        // `command -v` may emit multiple lines; take the first executable hit.
        let output = String(decoding: data, as: UTF8.self)
        for line in output.split(separator: "\n") {
            let path = line.trimmingCharacters(in: .whitespaces)
            if !path.isEmpty, path.hasPrefix("/"),
               FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Fetch raw stdout from the CLI. Async, runs the process on a background
    /// thread. Enforces a timeout (default 15s).
    static func fetchUsageJSON(timeout: TimeInterval = 15) async throws -> Data {
        guard let claudePath = resolveClaudePath() else {
            throw UsageFetchError.claudeNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Resume guard so we never double-resume.
            let resumed = ResumeGuard()

            let workingDir = neutralWorkingDirectoryURL

            let process = Process()
            process.executableURL = URL(fileURLWithPath: claudePath)
            process.arguments = ["-p", "/usage", "--output-format", "json"]

            // Pin the child to a neutral, non-protected working directory so it
            // does not scan the user's home/project dirs (which would surface
            // TCC prompts attributed to the unsandboxed parent).
            process.currentDirectoryURL = workingDir

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Keep HOME (claude needs it for ~/.claude credentials) and a sane
            // PATH, but neutralize PWD/OLDPWD so scans aren't anchored at the
            // previous cwd.
            process.environment = neutralizedEnvironment(workingDir: workingDir)

            // Drain stdout/stderr incrementally so the kernel pipe buffer
            // (~64KB) never fills and blocks the child before it exits. Without
            // this, a large /usage payload would deadlock and trip the timeout.
            let outBuffer = DataBuffer()
            let errBuffer = DataBuffer()
            let outHandle = stdoutPipe.fileHandleForReading
            let errHandle = stderrPipe.fileHandleForReading

            // Finish only once the process has exited AND both pipes hit EOF.
            // No blocking read after exit: if a grandchild keeps a pipe open,
            // the result waits and the timeout below can still fire, instead
            // of the fetch (and all later polls) hanging forever.
            let finished = DispatchGroup()
            finished.enter() // process exit
            drain(outHandle, into: outBuffer, group: finished)
            drain(errHandle, into: errBuffer, group: finished)

            // Timeout watchdog.
            let timeoutWork = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
                if resumed.tryResume() {
                    outHandle.readabilityHandler = nil
                    errHandle.readabilityHandler = nil
                    fetchLog.error("claude CLI timed out after \(timeout, privacy: .public)s")
                    continuation.resume(throwing: UsageFetchError.timedOut)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

            process.terminationHandler = { _ in finished.leave() }

            finished.notify(queue: .global()) {
                timeoutWork.cancel()
                guard resumed.tryResume() else { return }

                let outData = outBuffer.data
                let errData = errBuffer.data
                let status = process.terminationStatus

                if status != 0 {
                    let stderr = String(decoding: errData, as: UTF8.self)
                    fetchLog.error("claude exited non-zero (\(status, privacy: .public))")
                    if UsageFetchError.looksLikeAuthFailure(stderr: stderr) {
                        continuation.resume(throwing: UsageFetchError.notSignedIn)
                    } else {
                        continuation.resume(throwing: UsageFetchError.nonZeroExit(
                            code: status, stderr: stderr))
                    }
                    return
                }

                guard !outData.isEmpty else {
                    fetchLog.error("claude produced empty stdout")
                    continuation.resume(throwing: UsageFetchError.emptyOutput)
                    return
                }
                fetchLog.debug("claude usage fetch succeeded (\(outData.count, privacy: .public) bytes)")
                continuation.resume(returning: outData)
            }

            do {
                try process.run()
            } catch {
                timeoutWork.cancel()
                if resumed.tryResume() {
                    outHandle.readabilityHandler = nil
                    errHandle.readabilityHandler = nil
                    fetchLog.error("failed to launch claude: \(error.localizedDescription, privacy: .public)")
                    // The cached path may be stale (e.g. an nvm/fnm version
                    // switch moved the binary). Clear it so the NEXT poll
                    // re-discovers and self-heals without an app restart.
                    invalidateCache()
                    continuation.resume(throwing: UsageFetchError.launchFailed(error.localizedDescription))
                }
            }
        }
    }

    /// Accumulate a pipe's output as it arrives; leave `group` once at EOF.
    private static func drain(_ handle: FileHandle, into buffer: DataBuffer, group: DispatchGroup) {
        group.enter()
        handle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                group.leave()
            } else {
                buffer.append(chunk)
            }
        }
    }
}

/// Thread-safe accumulating byte buffer used to drain process pipes.
private final class DataBuffer: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: Data())

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        storage.withLock { $0.append(chunk) }
    }

    var data: Data {
        storage.withLock { $0 }
    }
}

/// Thread-safe single-shot guard to prevent double-resuming a continuation.
private final class ResumeGuard: Sendable {
    private let done = OSAllocatedUnfairLock(initialState: false)

    func tryResume() -> Bool {
        done.withLock { done in
            defer { done = true }
            return !done
        }
    }
}
