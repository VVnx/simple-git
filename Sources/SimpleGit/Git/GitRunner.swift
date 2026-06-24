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
    let command: String
    let timeout: TimeInterval

    var errorDescription: String? {
        "\(command) 超时(\(Int(timeout.rounded())) 秒)"
    }
}

/// Thin async wrapper around the `git` executable.
struct GitRunner {
    let workingDirectory: String

    @discardableResult
    func run(_ args: [String], allowNonZero: Bool = false, timeout: TimeInterval? = nil) async throws -> String {
        try await GitRunner.run(args, in: workingDirectory, allowNonZero: allowNonZero, timeout: timeout)
    }

    /// Runs `git args...`. `directory` is the working directory (nil to inherit;
    /// callers that need a specific repo usually pass `-C <path>` in `args`).
    /// `allowNonZero` returns stdout instead of throwing on a non-zero exit —
    /// useful for `git diff --no-index`, which exits 1 when files differ.
    static func run(_ args: [String], in directory: String?, allowNonZero: Bool = false, timeout: TimeInterval? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let command = "git " + args.joined(separator: " ")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git"] + args
                if let directory {
                    process.currentDirectoryURL = URL(fileURLWithPath: directory)
                }

                // A GUI app launched from Finder/Xcode has a minimal PATH, so make
                // sure the common git locations are reachable. Also disable any
                // interactive prompting so a credential request can't hang the UI.
                var env = ProcessInfo.processInfo.environment
                let extraPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                env["PATH"] = env["PATH"].map { "\(extraPath):\($0)" } ?? extraPath
                env["GIT_TERMINAL_PROMPT"] = "0"
                env["GIT_OPTIONAL_LOCKS"] = "0"
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                let exitSemaphore = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in exitSemaphore.signal() }

                // Drain both pipes concurrently to avoid a deadlock when one fills
                // its buffer while we're blocked reading the other.
                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                let readQueue = DispatchQueue(label: "git.pipe.read", attributes: .concurrent)
                group.enter()
                readQueue.async {
                    outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                readQueue.async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                do {
                    try process.run()
                } catch {
                    // Unblock the readers (no process means no EOF otherwise).
                    try? outPipe.fileHandleForWriting.close()
                    try? errPipe.fileHandleForWriting.close()
                    group.wait()
                    cont.resume(throwing: error)
                    return
                }

                let timedOut: Bool
                if let timeout {
                    timedOut = exitSemaphore.wait(timeout: .now() + timeout) == .timedOut
                    if timedOut {
                        if process.isRunning { process.terminate() }
                        if exitSemaphore.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                            Darwin.kill(process.processIdentifier, SIGKILL)
                            _ = exitSemaphore.wait(timeout: .now() + 1)
                        }
                    }
                } else {
                    exitSemaphore.wait()
                    timedOut = false
                }

                if timedOut {
                    try? outPipe.fileHandleForReading.close()
                    try? errPipe.fileHandleForReading.close()
                }
                group.wait()

                let out = String(decoding: outData, as: UTF8.self)
                let err = String(decoding: errData, as: UTF8.self)

                if timedOut {
                    cont.resume(throwing: GitTimeoutError(command: command, timeout: timeout ?? 0))
                } else if process.terminationStatus == 0 || allowNonZero {
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
        }
    }
}
