import SwiftUI

/// Right-hand pane of a detail panel: shows the selected file's unified diff.
struct FileDiffPane: View {
    let diff: String
    let isLoading: Bool
    let hasSelection: Bool

    var body: some View {
        Group {
            if !hasSelection {
                placeholder("选择左侧文件查看变更内容")
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diff.isEmpty {
                placeholder("(无文本差异,可能是二进制文件)")
            } else {
                DiffView(text: diff)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Renders a unified diff with +/- line coloring.
struct DiffView: View {
    let text: String

    private var lines: [Substring] { text.split(separator: "\n", omittingEmptySubsequences: false) }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : String(line))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(color(for: line))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(for: line))
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func color(for line: Substring) -> Color {
        if line.hasPrefix("@@") { return .purple }
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
            return .secondary
        }
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .primary
    }

    private func background(for line: Substring) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .clear }
        if line.hasPrefix("+") { return .green.opacity(0.10) }
        if line.hasPrefix("-") { return .red.opacity(0.10) }
        return .clear
    }
}
