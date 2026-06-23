import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List(selection: selectionBinding) {
            Section("仓库") {
                ForEach(store.repositories) { repo in
                    Label(repo.name, systemImage: "folder")
                        .tag(repo.id)
                        .help(repo.path)
                        .contextMenu {
                            Button("在 Finder 中显示") { revealInFinder(repo) }
                            Divider()
                            Button("移除", role: .destructive) { store.removeRepository(repo) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.repositories.isEmpty {
                Text("还没有仓库\n点下方「添加仓库」")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: addRepo) {
                Label("添加仓库", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    private var selectionBinding: Binding<Repository.ID?> {
        Binding(
            get: { store.selectedRepoID },
            set: { store.select($0) }
        )
    }

    private func addRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "添加"
        panel.message = "选择一个 Git 仓库目录"
        if panel.runModal() == .OK, let url = panel.url {
            store.addRepository(at: url)
        }
    }

    private func revealInFinder(_ repo: Repository) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: repo.path)])
    }
}
