import SwiftUI

/// Bottom panel for the working tree: header + (file list | file diff).
struct WorkingChangesPanel: View {
    @EnvironmentObject var store: AppStore

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
        HStack {
            Label("未提交的更改", systemImage: "pencil.circle")
                .font(.headline)
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
            Text("变更文件 (\(store.workingFiles.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            if store.isLoadingFiles {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.workingFiles.isEmpty {
                Text("工作区是干净的")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.workingFiles) { file in
                            WorkingFileRow(
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

struct WorkingFileRow: View {
    let file: WorkingFile
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(file.badge)
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

    private var displayPath: String {
        if let old = file.oldPath { return "\(old) → \(file.path)" }
        return file.path
    }

    private var color: Color {
        switch file.badge {
        case "A", "?": return .green
        case "M": return .orange
        case "D": return .red
        case "R", "C": return .blue
        case "U": return .red
        default: return .gray
        }
    }
}
