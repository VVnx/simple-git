import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @State private var showCloneSheet = false

    var body: some View {
        List(selection: selectionBinding) {
            Section("仓库") {
                ForEach(store.repositories) { repo in
                    Text(repo.name)
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
            HStack {
                Menu {
                    Button {
                        addLocalRepo()
                    } label: {
                        Label("打开本地仓库…", systemImage: "folder")
                    }
                    Button {
                        showCloneSheet = true
                    } label: {
                        Label("克隆 URL…", systemImage: "arrow.down.doc")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .imageScale(.large)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("添加仓库:打开本地或克隆 URL")

                Spacer()
            }
            .padding(10)
        }
        .sheet(isPresented: $showCloneSheet) {
            CloneSheet()
                .environmentObject(store)
        }
    }

    private var selectionBinding: Binding<Repository.ID?> {
        Binding(
            get: { store.selectedRepoID },
            set: { store.select($0) }
        )
    }

    private func addLocalRepo() {
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
