import SwiftUI

struct RepoDetailView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var issueBoardModel = IssueBoardModel()
    @State private var showMergeConfirm = false
    @State private var showingNewIssue = false

    var body: some View {
        Group {
            if store.selectedRepo == nil {
                EmptyStateView(
                    title: "未选择仓库",
                    systemImage: "tray",
                    message: "从左侧选择,或点「添加仓库」"
                )
            } else if let repository = store.selectedRepo {
                VStack(spacing: 0) {
                    if store.isIssueBoardMode {
                        IssueBoardView(
                            repository: repository,
                            model: issueBoardModel,
                            showingNewIssue: $showingNewIssue
                        )
                            .transition(.opacity)
                    } else {
                        graph
                        if store.isUncommittedSelected {
                            Divider()
                            WorkingChangesPanel()
                                .frame(height: 260)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if let commit = store.selectedCommit {
                            Divider()
                            CommitDetailPanel(commit: commit)
                                .frame(height: 260)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    Divider()
                    StatusBarView(
                        status: store.status,
                        onTapBranch: { store.locateCurrentHead() },
                        onOpenCodex: { store.openExternalApp("Codex") },
                        onOpenClaude: { store.openExternalApp("Claude") },
                        onOpenVSCode: { store.openExternalApp("Visual Studio Code", path: store.selectedRepo?.path) }
                    )
                }
                .animation(.easeInOut(duration: 0.2), value: store.selection)
                .animation(.easeInOut(duration: 0.2), value: store.isIssueBoardMode)
            }
        }
        .overlay(alignment: .top) {
            Group {
                if let busy = store.busyMessage {
                    ToastView(text: busy, kind: .progress)
                } else if let success = store.successMessage {
                    ToastView(text: success, kind: .success)
                }
            }
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(1)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.busyMessage)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.successMessage)
        .toolbar { toolbarContent }
        .confirmationDialog(
            "合并提交",
            isPresented: $showMergeConfirm,
            presenting: store.selectedCommit
        ) { commit in
            Button("合并到 “\(store.status?.branch ?? "当前分支")”") {
                store.mergeCommit(commit)
            }
            Button("取消", role: .cancel) {}
        } message: { commit in
            Text("把提交 \(commit.shortHash)(\(commit.subject))合并到当前分支 “\(store.status?.branch ?? "")” 吗?")
        }
        .navigationTitle(store.selectedRepo?.displayName ?? "simple-git")
        .navigationSubtitle(store.status?.branch ?? "")
    }

    @ViewBuilder
    private var graph: some View {
        if store.nodes.isEmpty {
            EmptyStateView(
                title: store.isLoading ? "加载中…" : "没有可显示的提交",
                systemImage: store.isLoading ? "hourglass" : "point.3.connected.trianglepath.dotted",
                message: store.isLoading ? "" : "这个仓库还没有提交,或加载失败。试试刷新。"
            )
        } else {
            CommitGraphView(
                nodes: store.nodes,
                laneCount: store.laneCount,
                refsByCommit: store.refsByCommit,
                currentBranch: store.status?.branch,
                now: store.now,
                selectedHash: store.selectedCommit?.hash,
                onSelect: { store.selectCommit($0) },
                onCopyHash: { store.copyCommitHash($0) },
                uncommittedCount: store.status.map { $0.changedCount + $0.untrackedCount } ?? 0,
                isUncommittedSelected: store.isUncommittedSelected,
                onSelectUncommitted: { store.selectUncommitted() },
                scrollTarget: store.scrollTarget
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if store.isIssueBoardMode {
                if let currentUser = issueBoardModel.currentUser {
                    HStack(spacing: 6) {
                        Text("只看我的")
                            .font(.callout)
                        Toggle("只看我的", isOn: $issueBoardModel.showOnlyMine.animation(.easeInOut(duration: 0.15)))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                    .help("只显示由 @\(currentUser) 提交的 Issue")
                }

                Button {
                    guard let repository = store.selectedRepo else { return }
                    guard store.beginCurrentIssueRefresh() else { return }
                    Task {
                        let succeeded = await issueBoardModel.load(repository: repository)
                        if succeeded {
                            store.publishIssueSidebarStatus(
                                for: repository,
                                issues: issueBoardModel.issues
                            )
                        }
                        store.finishCurrentIssueRefresh(
                            succeeded: succeeded,
                            error: issueBoardModel.loadError
                        )
                    }
                } label: {
                    Label("刷新 Issues", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .disabled(
                    issueBoardModel.isLoading
                        || store.isRepositoryOperationInProgress
                        || store.selectedRepo == nil
                )
                .help("重新读取当前仓库的 GitHub Issue 列表")

                Button {
                    showingNewIssue = true
                } label: {
                    Label("新建 Issue", systemImage: "plus.circle")
                }
                .labelStyle(.iconOnly)
                .disabled(
                    issueBoardModel.isCreating
                        || store.isRepositoryOperationInProgress
                        || store.selectedRepo == nil
                )
                .help("在当前 GitHub 仓库创建一个新 Issue")
            } else {
                Button {
                    store.fetch()
                } label: {
                    Label("Fetch", systemImage: "arrow.down.to.line")
                }
                .labelStyle(.titleAndIcon)
                .disabled(store.isRepositoryOperationInProgress)
                .help("git fetch --all --prune --tags:下载远程更新和全量 tag,不改动工作区")

                Button {
                    store.pull()
                } label: {
                    Label("Pull", systemImage: "arrow.down.circle")
                }
                .labelStyle(.titleAndIcon)
                .disabled(store.isRepositoryOperationInProgress)
                .help("git pull:下载并合并到当前分支")

                Button {
                    store.push()
                } label: {
                    Label("Push", systemImage: "arrow.up.circle")
                }
                .labelStyle(.titleAndIcon)
                .disabled(store.isRepositoryOperationInProgress)
                .help("git push:推送当前分支(无 upstream 时自动 -u)")

                Button {
                    showMergeConfirm = true
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
                .labelStyle(.titleAndIcon)
                .disabled(store.isRepositoryOperationInProgress || store.selectedCommit == nil)
                .help(store.selectedCommit == nil
                      ? "先在下方点选一个提交,再合并到当前分支"
                      : "把所选提交合并到当前分支(会二次确认)")
            }

        }
    }
}
