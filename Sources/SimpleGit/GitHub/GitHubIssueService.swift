import Darwin
import Foundation

struct GitHubCommandError: LocalizedError {
    let exitCode: Int32
    let message: String

    var errorDescription: String? {
        message.isEmpty ? "GitHub CLI 执行失败(exit \(exitCode))" : message
    }
}

struct GitHubCommandTimeoutError: LocalizedError {
    let timeout: TimeInterval

    var errorDescription: String? {
        "GitHub 请求超过 \(Int(timeout.rounded())) 秒,已停止。"
    }
}

struct GitHubIssueService {
    let repositoryPath: String

    private static let requestTimeout: TimeInterval = 45

    func listIssues() async throws -> [GitHubIssue] {
        let output = try await GitHubCommandRunner(workingDirectory: repositoryPath).run(
            [
                "issue", "list",
                "--state", "all",
                "--limit", "200",
                "--json", "number,title,state,labels,assignees,updatedAt,url"
            ],
            timeout: Self.requestTimeout
        )

        do {
            let payloads = try JSONDecoder().decode([IssuePayload].self, from: Data(output.utf8))
            return payloads.map { payload in
                GitHubIssue(
                    number: payload.number,
                    title: payload.title,
                    state: GitHubIssueState(rawValue: payload.state) ?? .open,
                    labels: payload.labels.map { GitHubIssueLabel(name: $0.name, color: $0.color) },
                    assignees: payload.assignees.map(\.login),
                    updatedAt: Self.parseDate(payload.updatedAt) ?? .distantPast,
                    url: payload.url
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            throw SimpleGitError("GitHub 返回了无法识别的 Issue 数据,请升级 GitHub CLI 后重试。")
        }
    }

    @discardableResult
    func createIssue(title: String, body: String) async throws -> URL {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw SimpleGitError("Issue 标题不能为空。") }

        let output = try await GitHubCommandRunner(workingDirectory: repositoryPath).run(
            ["issue", "create", "--title", trimmedTitle, "--body-file", "-"],
            standardInput: body,
            timeout: Self.requestTimeout
        )
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value) else {
            throw SimpleGitError("Issue 已提交,但没有读到 GitHub 返回的链接。请刷新看板确认。")
        }
        return url
    }

    static func friendlyMessage(_ error: Error) -> String {
        if let simple = error as? SimpleGitError { return simple.message }
        if let timeout = error as? GitHubCommandTimeoutError { return timeout.localizedDescription }

        let commandError = error as? GitHubCommandError
        let raw = commandError?.message ?? error.localizedDescription
        let lower = raw.lowercased()

        if commandError?.exitCode == 127 || lower.contains("gh: no such file") {
            return "未找到 GitHub CLI。请先安装 gh,再重启应用。"
        }
        if lower.contains("gh auth login")
            || lower.contains("not logged into any github hosts")
            || lower.contains("authentication required") {
            return "GitHub 尚未登录。请先在终端运行 gh auth login。"
        }
        if lower.contains("no git remotes found")
            || lower.contains("no remotes found")
            || lower.contains("known github host")
            || lower.contains("unable to determine repository") {
            return "当前仓库没有可识别的 GitHub remote。请检查 origin 地址。"
        }
        if lower.contains("could not resolve host")
            || lower.contains("connection refused")
            || lower.contains("network is unreachable") {
            return "无法连接 GitHub,请检查网络后重试。"
        }

        let cleaned = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.lowercased().hasPrefix("hint:") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "GitHub 请求失败。" : cleaned
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = fractionalDateFormatter.date(from: value) { return date }
        return standardDateFormatter.date(from: value)
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private struct IssuePayload: Decodable {
        let number: Int
        let title: String
        let state: String
        let labels: [LabelPayload]
        let assignees: [AssigneePayload]
        let updatedAt: String
        let url: URL
    }

    private struct LabelPayload: Decodable {
        let name: String
        let color: String
    }

    private struct AssigneePayload: Decodable {
        let login: String
    }
}

/// Runs GitHub CLI without blocking a worker thread while stdout/stderr pipes fill.
private struct GitHubCommandRunner {
    let workingDirectory: String

    func run(
        _ args: [String],
        standardInput: String? = nil,
        timeout: TimeInterval
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + args
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        var environment = ProcessInfo.processInfo.environment
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["PATH"] = environment["PATH"].map { "\(extraPath):\($0)" } ?? extraPath
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_NO_UPDATE_NOTIFIER"] = "1"
        environment["GH_PAGER"] = "cat"
        environment["NO_COLOR"] = "1"
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let inputPipe = standardInput == nil ? nil : Pipe()
        process.standardInput = inputPipe

        let stateQueue = DispatchQueue(label: "github.command.state")
        var outputData = Data()
        var errorData = Data()
        var outputFinished = false
        var errorFinished = false
        var processExited = false
        var timedOut = false
        var continuationFinished = false

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                func finishIfReady() {
                    guard !continuationFinished else { return }
                    guard timedOut || (processExited && outputFinished && errorFinished) else { return }
                    continuationFinished = true
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil

                    if timedOut {
                        continuation.resume(throwing: GitHubCommandTimeoutError(timeout: timeout))
                        return
                    }

                    let output = String(decoding: outputData, as: UTF8.self)
                    let error = String(decoding: errorData, as: UTF8.self)
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        let message = (error.isEmpty ? output : error)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: GitHubCommandError(
                            exitCode: process.terminationStatus,
                            message: message
                        ))
                    }
                }

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    stateQueue.async {
                        if chunk.isEmpty {
                            outputFinished = true
                            handle.readabilityHandler = nil
                        } else {
                            outputData.append(chunk)
                        }
                        finishIfReady()
                    }
                }
                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    stateQueue.async {
                        if chunk.isEmpty {
                            errorFinished = true
                            handle.readabilityHandler = nil
                        } else {
                            errorData.append(chunk)
                        }
                        finishIfReady()
                    }
                }
                process.terminationHandler = { _ in
                    stateQueue.async {
                        processExited = true
                        finishIfReady()
                    }
                }

                do {
                    try process.run()
                    if let standardInput, let inputPipe {
                        inputPipe.fileHandleForWriting.write(Data(standardInput.utf8))
                        inputPipe.fileHandleForWriting.closeFile()
                    }
                } catch {
                    stateQueue.async {
                        guard !continuationFinished else { return }
                        continuationFinished = true
                        outputPipe.fileHandleForReading.readabilityHandler = nil
                        errorPipe.fileHandleForReading.readabilityHandler = nil
                        continuation.resume(throwing: error)
                    }
                    return
                }

                stateQueue.asyncAfter(deadline: .now() + timeout) {
                    guard !continuationFinished, !processExited else { return }
                    timedOut = true
                    if process.isRunning { process.terminate() }
                    stateQueue.asyncAfter(deadline: .now() + 2) {
                        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                    }
                    finishIfReady()
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
