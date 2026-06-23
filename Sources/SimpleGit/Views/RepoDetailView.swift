import SwiftUI

struct RepoDetailView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if store.selectedRepo == nil {
                EmptyStateView(
                    title: "未选择仓库",
                    systemImage: "tray",
                    message: "从左侧选择,或点「添加仓库」"
                )
            } else {
                VStack(spacing: 0) {
                    graph
                    if let commit = store.selectedCommit {
                        Divider()
                        CommitDetailPanel(
                            commit: commit,
                            files: store.changedFiles,
                            isLoading: store.isLoadingFiles,
                            onClose: { store.selectCommit(nil) },
                            onCopyHash: { store.copyCommitHash(commit) }
                        )
                        .frame(height: 220)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Divider()
                    StatusBarView(status: store.status, busy: store.busyMessage)
                }
                .animation(.easeInOut(duration: 0.2), value: store.selectedCommitID)
            }
        }
        .overlay(alignment: .top) {
            if let success = store.successMessage {
                ToastView(text: success)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.successMessage)
        .toolbar { toolbarContent }
        .navigationTitle(store.selectedRepo?.name ?? "simple-git")
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
                selectedHash: store.selectedCommitID,
                onSelect: { store.selectCommit($0) },
                onCopyHash: { store.copyCommitHash($0) }
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                store.fetch()
            } label: {
                Label("Fetch", systemImage: "arrow.down.circle")
            }
            .labelStyle(.titleAndIcon)
            .help("git fetch --all --prune:只下载远程更新,不改动工作区")

            Button {
                store.pull()
            } label: {
                Label("Pull", systemImage: "arrow.down.to.line")
            }
            .labelStyle(.titleAndIcon)
            .help("git pull:下载并合并到当前分支")

            Button {
                store.push()
            } label: {
                Label("Push", systemImage: "arrow.up.circle")
            }
            .labelStyle(.titleAndIcon)
            .help("git push:推送当前分支(无 upstream 时自动 -u)")

            Menu {
                if store.mergeableBranches.isEmpty {
                    Text("没有可合并的分支")
                } else {
                    ForEach(store.mergeableBranches) { branch in
                        Button {
                            store.merge(branch)
                        } label: {
                            Label(branch.name, systemImage: branch.isRemote ? "cloud" : "arrow.triangle.branch")
                        }
                    }
                }
            } label: {
                Label("Merge", systemImage: "arrow.triangle.merge")
            }
            .labelStyle(.titleAndIcon)
            .help("把所选分支合并进当前分支")

            Button {
                store.reload()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .labelStyle(.titleAndIcon)
            .keyboardShortcut("r", modifiers: .command)
            .help("重新读取仓库状态(⌘R)")
        }
    }
}
