import SwiftUI

/// Bottom panel for a selected commit: header + (file list | file diff).
struct CommitDetailPanel: View {
    @EnvironmentObject var store: AppStore
    let commit: Commit

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                fileList
                    .frame(width: 320)
                Divider()
                FileDiffPane(
                    diff: store.fileDiff,
                    isLoading: store.isLoadingDiff,
                    hasSelection: store.selectedFilePath != nil
                )
            }
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
                    Button { store.copyCommitHash(commit) } label: {
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

            Button { store.clearSelection() } label: {
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
    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("变更文件 (\(store.changedFiles.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            if store.isLoadingFiles {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.changedFiles.isEmpty {
                Text(commit.parents.count > 1 ? "合并提交:相对第一个父提交无差异" : "此提交没有文件变更")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.changedFiles) { file in
                            ChangedFileRow(
                                file: file,
                                isSelected: file.path == store.selectedFilePath,
                                onSelect: { store.selectFile(file.path) }
                            )
                        }
                    }
                }
            }
        }
    }
}

struct ChangedFileRow: View {
    let file: ChangedFile
    let isSelected: Bool
    let onSelect: () -> Void

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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
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
