import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @State private var showCloneSheet = false
    @State private var repoPendingRemoval: Repository?

    var body: some View {
        List(selection: selectionBinding) {
            Section("仓库") {
                ForEach(store.repositories) { repo in
                    RepoRow(
                        repo: repo,
                        onOpen: { revealInFinder(repo) },
                        onToggleMask: { store.toggleMask(repo) },
                        onRemove: { repoPendingRemoval = repo }
                    )
                    .tag(repo.id)
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
        .confirmationDialog(
            "移除仓库",
            isPresented: Binding(
                get: { repoPendingRemoval != nil },
                set: { if !$0 { repoPendingRemoval = nil } }
            ),
            presenting: repoPendingRemoval
        ) { repo in
            Button("移除「\(repo.displayName)」", role: .destructive) {
                store.removeRepository(repo)
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("仅从列表移除,不会删除磁盘上的文件。")
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

/// A sidebar repository row: name (masked when encrypted) plus hover-revealed
/// open / encrypt / remove icons, with the same actions in the context menu.
private struct RepoRow: View {
    let repo: Repository
    let onOpen: () -> Void
    let onToggleMask: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(repo.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if hovering {
                HStack(spacing: 2) {
                    iconButton("folder", help: "在 Finder 中打开", action: onOpen)
                    iconButton(repo.masked ? "lock.open" : "lock",
                               help: repo.masked ? "解密(显示名称)" : "加密(隐藏名称)",
                               action: onToggleMask)
                    iconButton("trash", help: "移除", action: onRemove)
                }
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(repo.masked ? "已加密(已隐藏路径)" : repo.path)
        .contextMenu {
            Button("在 Finder 中显示") { onOpen() }
            Button(repo.masked ? "解密(显示名称)" : "加密(隐藏名称)") { onToggleMask() }
            Divider()
            Button("移除", role: .destructive) { onRemove() }
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
