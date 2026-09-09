import Foundation

struct ErrorPresentation: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let details: String?

    init(title: String = "操作失败", message: String, details: String? = nil) {
        self.title = title
        summary = ErrorMessageFormatter.summary(message)
        self.details = details ?? (summary == message ? nil : message)
    }
}

enum ErrorMessageFormatter {
    /// Keep the useful diagnostics near the end of Git's output, not its progress updates.
    /// The full, unmodified output belongs in the scrollable details view.
    static func summary(_ raw: String) -> String {
        let plain = raw.replacingOccurrences(
            of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression
        )
        let lines = plain.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isNoise($0) }
        let diagnostics = lines.filter { line in
            let lower = line.lowercased()
            return lower.hasPrefix("fatal:") || lower.hasPrefix("error:")
                || lower.hasPrefix("remote: error:") || lower.hasPrefix("remote: fatal:")
                || lower.contains("[rejected]") || lower.contains("[remote rejected]")
        }
        // "failed to push some refs" is a consequence; show the specific cause first.
        let causes = diagnostics.filter { !$0.lowercased().contains("failed to push some refs") }
        let selected = !causes.isEmpty ? causes : (!diagnostics.isEmpty ? diagnostics : lines)
        guard !selected.isEmpty else {
            return "Git 操作未完成，日志中没有明确的失败原因。请展开详情查看完整输出。"
        }
        let text = selected.suffix(3).joined(separator: "\n")
        return text.count > 300 ? String(text.prefix(299)) + "…" : text
    }

    private static func isNoise(_ line: String) -> Bool {
        var lower = line.lowercased()
        if lower.hasPrefix("remote:") {
            lower = String(lower.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        return lower.hasPrefix("hint:") || lower.range(
            of: "^(enumerating objects|counting objects|compressing objects|writing objects|receiving objects|resolving deltas|updating files|checking out files|filtering content):|^delta compression using |^total [0-9]+ ",
            options: .regularExpression
        ) != nil
    }
}
