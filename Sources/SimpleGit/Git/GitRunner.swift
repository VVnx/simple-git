import Darwin
import Foundation

struct GitError: LocalizedError {
    let command: String
    let exitCode: Int32
    let message: String
    var errorDescription: String? {
        message.isEmpty ? "\(command) 失败 (exit \(exitCode))" : message
    }
}

struct GitTimeoutError: LocalizedError {
    enum Kind {
        case total
        case idle
    }

    let command: String
    let timeout: TimeInterval
    let kind: Kind

    var errorDescription: String? {
        switch kind {
        case .total:
            "\(command) 超时(\(Int(timeout.rounded())) 秒)"
        case .idle:
            "\(command) 超时(\(Int(timeout.rounded())) 秒内没有响应)"
        }
    }
}

/// Thin async wrapper around the `git` executable.
struct GitRunner {
    let workingDirectory: String

    @discardableResult
    func run(
        _ args: [String],
        allowNonZero: Bool = false,
        timeout: TimeInterval? = nil,
        idleTimeout: TimeInterval? = nil,
        environment: [String: String] = [:]
    ) async throws -> String {
        try await GitRunner.run(
            args,
            in: workingDirectory,
            allowNonZero: allowNonZero,
            timeout: timeout,
            idleTimeout: idleTimeout,
            environment: environment
        )
    }

    /// Runs `git args...`. `directory` is the working directory (nil to inherit;
    /// callers that need a specific repo usually pass `-C <path>` in `args`).
    /// `allowNonZero` returns stdout instead of throwing on a non-zero exit —
    /// useful for `git diff --no-index`, which exits 1 when files differ.
    ///
    /// Fully non-blocking: the pipes are drained via `readabilityHandler` and the
    /// process is awaited via `terminationHandler`, so no thread is ever parked on
    /// a `wait()`. This matters because the app fires several git reads per reload
    /// (refs + status + log) and FSEvents can stack reloads — an implementation
    /// that blocks a GCD worker per call would exhaust the global thread pool,
    /// leaving no thread to drain the pipes, so git blocks forever writing to a
    /// full stdout pipe and the whole UI wedges. Holding no threads avoids that.
    static func run(
        _ args: [String],
        in directory: String?,
        allowNonZero: Bool = false,
        timeout: TimeInterval? = nil,
        idleTimeout: TimeInterval? = nil,
        environment: [String: String] = [:]
    ) async throws -> String {
        let command = "git " + args.joined(separator: " ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }

        // A GUI app launched from Finder/Xcode has a minimal PATH, so make sure
        // the common git locations are reachable. Also disable any interactive
        // prompting so a credential request can't hang the UI.
        var env = ProcessInfo.processInfo.environment
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = env["PATH"].map { "\(extraPath):\($0)" } ?? extraPath
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // All mutable state is confined to this serial queue, so the pipe handlers,
        // the termination handler and the timeout fire without racing.
        let stateQueue = DispatchQueue(label: "git.run.state")
        var outData = Data()
        var errData = Data()
        var outDone = false
        var errDone = false
        var exited = false
        var timedOut = false
        var timedOutAfter: TimeInterval = timeout ?? idleTimeout ?? 0
        var timeoutKind = GitTimeoutError.Kind.total
        var idleTimerGeneration = 0
        var finished = false

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                // Resume the continuation exactly once, after the process has exited
                // (or timed out) AND both pipes have reached EOF — so we never drop
                // buffered output. Must be called on `stateQueue`.
                func finishIfReady() {
                    guard !finished else { return }
                    guard timedOut || (exited && outDone && errDone) else { return }
                    finished = true

                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil

                    if timedOut {
                        cont.resume(throwing: GitTimeoutError(command: command, timeout: timedOutAfter, kind: timeoutKind))
                        return
                    }
                    let out = String(decoding: outData, as: UTF8.self)
                    let err = String(decoding: errData, as: UTF8.self)
                    if process.terminationStatus == 0 || allowNonZero {
                        cont.resume(returning: out)
                    } else {
                        let raw = err.isEmpty ? out : err
                        cont.resume(throwing: GitError(
                            command: command,
                            exitCode: process.terminationStatus,
                            message: raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                    }
                }

                func timeOut(kind: GitTimeoutError.Kind, after duration: TimeInterval) {
                    guard !finished, !exited else { return }
                    timedOut = true
                    timeoutKind = kind
                    timedOutAfter = duration
                    if process.isRunning { process.terminate() }
                    stateQueue.asyncAfter(deadline: .now() + 2) {
                        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                    }
                    finishIfReady()
                }

                func scheduleIdleTimeout(generation: Int) {
                    guard let idleTimeout else { return }
                    stateQueue.asyncAfter(deadline: .now() + idleTimeout) {
                        guard generation == idleTimerGeneration else { return }
                        timeOut(kind: .idle, after: idleTimeout)
                    }
                }

                func markOutputActivity() {
                    guard idleTimeout != nil else { return }
                    idleTimerGeneration += 1
                    scheduleIdleTimeout(generation: idleTimerGeneration)
                }

                outPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    stateQueue.async {
                        if chunk.isEmpty {
                            outDone = true
                            handle.readabilityHandler = nil
                            finishIfReady()
                        } else {
                            outData.append(chunk)
                            markOutputActivity()
                        }
                    }
                }
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    stateQueue.async {
                        if chunk.isEmpty {
                            errDone = true
                            handle.readabilityHandler = nil
                            finishIfReady()
                        } else {
                            errData.append(chunk)
                            markOutputActivity()
                        }
                    }
                }

                process.terminationHandler = { _ in
                    stateQueue.async {
                        exited = true
                        finishIfReady()
                    }
                }

                do {
                    try process.run()
                } catch {
                    stateQueue.async {
                        guard !finished else { return }
                        finished = true
                        outPipe.fileHandleForReading.readabilityHandler = nil
                        errPipe.fileHandleForReading.readabilityHandler = nil
                        cont.resume(throwing: error)
                    }
                    return
                }

                stateQueue.async {
                    markOutputActivity()
                }

                // Safety net: a timeout terminates the process so a stuck git can
                // never wedge a caller. SIGTERM first, then SIGKILL if it lingers.
                if let timeout {
                    stateQueue.asyncAfter(deadline: .now() + timeout) {
                        timeOut(kind: .total, after: timeout)
                    }
                }
            }
        } onCancel: {
            // The owning Task was cancelled (e.g. a superseded reload): stop the
            // git child so orphans don't pile up. The handlers above still resume
            // the continuation when it exits.
            if process.isRunning { process.terminate() }
        }
    }
}
