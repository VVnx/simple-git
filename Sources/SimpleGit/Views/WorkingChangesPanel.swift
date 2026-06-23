import SwiftUI

/// Bottom panel shown when the "未提交的更改" row is selected: a flat list of the
/// working-tree's changed files, same layout as a commit's file list.
struct WorkingChangesPanel: View {
    let files: [WorkingFile]
    let isLoading: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("未提交的更改", systemImage: "pencil.circle")
                    .font(.headline)
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

            Divider()

            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if files.isEmpty {
            Text("工作区是干净的")
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
                        ForEach(files) { WorkingFileRow(file: $0) }
                    }
                }
            }
        }
    }
}

struct WorkingFileRow: View {
    let file: WorkingFile

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
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2.5)
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
