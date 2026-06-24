import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @State private var showCloneSheet = false
    @State private var repoPendingRemoval: Repository?
    @State private var draggingRepoID: Repository.ID?

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                repositoryRows(for: .active)
            } header: {
                GroupHeader(title: RepositoryGroup.active.title,
                            count: store.activeRepositories.count)
            }

            Section {
                repositoryRows(for: .inactive)
            } header: {
                GroupHeader(title: RepositoryGroup.inactive.title,
                            count: store.inactiveRepositories.count)
            }
        }
        .listStyle(.sidebar)
        .disabled(store.isRepositorySelectionLocked)
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
                .disabled(store.isRepositoryOperationInProgress)
                .help("添加仓库:打开本地或克隆 URL")

                Spacer()

                Button {
                    store.fetchActiveRepositories()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .disabled(store.isRepositoryOperationInProgress || store.activeRepositories.isEmpty)
                .help("Fetch Active 仓库")
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

    @ViewBuilder
    private func repositoryRows(for group: RepositoryGroup) -> some View {
        let repos = store.repositories(in: group)
        if repos.isEmpty {
            if !store.repositories.isEmpty {
                GroupDropTarget(group: group, isEmpty: true)
                    .onDrop(of: [.plainText], delegate: RepositoryDropDelegate(
                        targetRepo: nil,
                        targetGroup: group,
                        draggingRepoID: $draggingRepoID,
                        move: store.moveRepository
                    ))
            }
        } else {
            ForEach(repos) { repo in
                RepoRow(
                    repo: repo,
                    status: group == .active ? store.sidebarStatuses[repo.id] : nil,
                    showsStatus: group == .active,
                    onSelect: { store.select(repo.id) },
                    onRefresh: { store.refreshRepository(repo) },
                    onOpen: { revealInFinder(repo) },
                    onToggleMask: { store.toggleMask(repo) },
                    onMoveToGroup: { store.moveRepository(repo, to: group == .active ? .inactive : .active) },
                    onRemove: { repoPendingRemoval = repo }
                )
                .tag(repo.id)
                .opacity(draggingRepoID == repo.id ? 0.45 : 1)
                .onDrag {
                    draggingRepoID = repo.id
                    return NSItemProvider(object: repo.id as NSString)
                }
                .onDrop(of: [.plainText], delegate: RepositoryDropDelegate(
                    targetRepo: repo,
                    targetGroup: group,
                    draggingRepoID: $draggingRepoID,
                    move: store.moveRepository
                ))
            }

            GroupDropTarget(group: group, isEmpty: false)
                .onDrop(of: [.plainText], delegate: RepositoryDropDelegate(
                    targetRepo: nil,
                    targetGroup: group,
                    draggingRepoID: $draggingRepoID,
                    move: store.moveRepository
                ))
        }
    }

    private var selectionBinding: Binding<Repository.ID?> {
        Binding(
            get: { store.selectedRepoID },
            set: {
                guard !store.isRepositorySelectionLocked else { return }
                store.select($0)
            }
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
    let status: RepoSidebarStatus?
    let showsStatus: Bool
    let onSelect: () -> Void
    let onRefresh: () -> Void
    let onOpen: () -> Void
    let onToggleMask: () -> Void
    let onMoveToGroup: () -> Void
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
                    iconButton(repo.masked ? "eye" : "eye.slash",
                               help: repo.masked ? "显示名称" : "隐藏名称",
                               action: onToggleMask)
                    iconButton("trash", help: "移除", action: onRemove)
                }
                .foregroundStyle(.secondary)
            } else if showsStatus {
                RepoStatusBadges(status: status)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .help(repo.masked ? "已隐藏名称" : repo.path)
        .contextMenu {
            Button("刷新") { onRefresh() }
            Divider()
            Button("在 Finder 中显示") { onOpen() }
            Button(repo.masked ? "显示名称" : "隐藏名称") { onToggleMask() }
            Button("移到 \(repo.group == .active ? RepositoryGroup.inactive.title : RepositoryGroup.active.title)") {
                onMoveToGroup()
            }
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

private struct GroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Text("\(count)")
                .foregroundStyle(.secondary)
        }
    }
}

private struct GroupDropTarget: View {
    let group: RepositoryGroup
    let isEmpty: Bool

    var body: some View {
        if isEmpty {
            Text("拖到这里移入 \(group.title)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
        } else {
            Color.clear
                .frame(height: 8)
                .contentShape(Rectangle())
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }
}

private struct RepoStatusBadges: View {
    let status: RepoSidebarStatus?

    var body: some View {
        HStack(spacing: 5) {
            if let status {
                if status.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 28, alignment: .trailing)
                } else if let error = status.errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help(error)
                } else {
                    if status.hasUpstream {
                        RepoMetric(systemName: "arrow.up", value: status.ahead,
                                   color: status.ahead > 0 ? .secondary : Color.secondary.opacity(0.45))
                        RepoMetric(systemName: "arrow.down", value: status.behind,
                                   color: status.behind > 0 ? .orange : Color.secondary.opacity(0.45))
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .help("当前分支没有 upstream")
                    }

                    Image(systemName: status.hasChanges ? "circle.fill" : "circle")
                        .font(.system(size: 7))
                        .foregroundStyle(status.hasChanges ? Color.orange : Color.secondary.opacity(0.45))
                        .help(status.hasChanges ? "有未提交代码" : "工作区干净")
                }
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .font(.caption)
        .monospacedDigit()
    }
}

private struct RepoMetric: View {
    let systemName: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .medium))
            Text("\(value)")
                .frame(minWidth: 8, alignment: .trailing)
        }
        .foregroundStyle(color)
    }
}

private struct RepositoryDropDelegate: DropDelegate {
    let targetRepo: Repository?
    let targetGroup: RepositoryGroup
    @Binding var draggingRepoID: Repository.ID?
    let move: (Repository.ID, RepositoryGroup, Repository.ID?) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingRepoID else { return }
        move(draggingRepoID, targetGroup, targetRepo?.id)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingRepoID = nil
        return true
    }
}
