import SwiftUI
import AppKit

/// Modal sheet for cloning a remote repository from an SSH or HTTPS URL.
struct CloneSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var destParent: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var cloning = false
    @State private var localError: String?

    private var repoName: String { AppStore.deriveRepoName(from: url) }
    private var canClone: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !cloning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("克隆远程仓库")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("仓库 URL(SSH 或 HTTPS)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("git@github.com:user/repo.git 或 https://github.com/user/repo.git", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .disabled(cloning)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("克隆到")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(destParent.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("选择…") { pickDirectory() }
                        .disabled(cloning)
                }
                if !repoName.isEmpty {
                    Text("将创建:\(destParent.appendingPathComponent(repoName).path)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let localError {
                Text(localError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if cloning {
                    ProgressView().controlSize(.small)
                    Text("正在克隆…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(cloning)
                Button("克隆") { startClone() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canClone)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func startClone() {
        cloning = true
        localError = nil
        Task {
            do {
                try await store.cloneRepository(url: url, into: destParent)
                dismiss()
            } catch {
                localError = error.localizedDescription
                cloning = false
            }
        }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择克隆到哪个父目录"
        panel.directoryURL = destParent
        if panel.runModal() == .OK, let dir = panel.url {
            destParent = dir
        }
    }
}
