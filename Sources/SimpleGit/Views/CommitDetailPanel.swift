import SwiftUI

/// Bottom panel shown when a commit is clicked: header info + list of changed files.
struct CommitDetailPanel: View {
    let commit: Commit
    let files: [ChangedFile]
    let isLoading: Bool
    let onClose: () -> Void
    let onCopyHash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(commit.subject)
                    .font(.headline)
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Button(action: onCopyHash) {
                        Label(commit.shortHash, systemImage: "doc.on.doc")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .help("点击复制完整 hash")

                    Text("\(commit.authorName) <\(commit.authorEmail)>")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Text(RelativeDate.absoluteString(from: commit.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(10)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if files.isEmpty {
            Text(commit.parents.count > 1
                 ? "合并提交:相对第一个父提交没有文件差异"
                 : "此提交没有文件变更")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("变更文件 (\(files.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(files) { file in
                            ChangedFileRow(file: file)
                        }
                    }
                }
            }
        }
    }
}

struct ChangedFileRow: View {
    let file: ChangedFile

    var body: some View {
        HStack(spacing: 8) {
            Text(badge)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 18, alignment: .leading)
            Text(displayPath)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2.5)
    }

    private var head: String { String(file.status.prefix(1)) }
    private var badge: String { head }

    private var displayPath: String {
        if let old = file.oldPath { return "\(old) → \(file.path)" }
        return file.path
    }

    private var color: Color {
        switch head {
        case "A": return .green
        case "M": return .orange
        case "D": return .red
        case "R": return .blue
        case "C": return .teal
        default: return .gray
        }
    }
}
