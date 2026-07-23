import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 360)
        } detail: {
            RepoDetailView()
        }
        .task {
            // Reload the repo restored from the last session, once.
            if store.selectedRepoID != nil { store.reload() }
            store.refreshActiveSidebarStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshActiveSidebarStatusesOnActivation()
        }
        .alert(
            "出错了",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("好") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert(
            "远端有新提交",
            isPresented: $store.showFetchAfterRejectedPush
        ) {
            Button("确认并 Fetch") { store.fetchAfterRejectedPush() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Push 被拒绝，因为远端有本地尚未获取的提交。确认后会先 Fetch 更新远端分支，之后你可以选择需要的提交进行 Merge。")
        }
    }
}
