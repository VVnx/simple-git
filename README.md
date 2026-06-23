# simple-git

一个为自己用的、极简原生 macOS Git 客户端。左侧切换多个仓库,右侧看 commit graph,工具栏只保留最常用的几个操作。

> 设计目标:代码主要交给大模型写,人只需要看 tree 状态 + Fetch / Push / Merge。所以刻意不做 SourceTree 那一大堆功能。

## 功能(v1)

- 左侧 sidebar:添加 / 移除 / 切换仓库(列表持久化在 UserDefaults)
- 右侧 commit graph:自绘泳道图,显示分支 / 远程分支 / 标签彩色 chip、作者、相对时间、短 hash
- 工具栏:**Fetch**(`fetch --all --prune`)、**Push**、**Merge**(下拉选分支)、**刷新**
- 底部状态栏:当前分支、ahead/behind、工作区是否干净

## 技术栈

- SwiftUI + AppKit(macOS 13+)
- Git 操作全部通过命令行 `git` 子进程完成(Foundation `Process`),无第三方依赖
- commit graph 的泳道分配是自己实现的(见 `Sources/SimpleGit/Git/GraphLayout.swift`)

## 运行

命令行:

```sh
cd ~/simple-git
swift run
```

或用 Xcode 打开 `Package.swift` 后直接运行(⌘R)。

## 目录结构

```
Sources/SimpleGit/
  App.swift              # @main App + AppDelegate(负责把窗口拉到前台)
  Models.swift           # Repository / Commit / Branch / RepoStatus / 图模型
  AppStore.swift         # @MainActor ObservableObject,所有状态与动作
  Git/
    GitRunner.swift      # Process 封装:异步跑 git,并发读 stdout/stderr
    GitService.swift     # 高层命令:log / status / refs / fetch / push / merge
    GraphLayout.swift    # commit graph 泳道分配算法
  Views/
    ContentView.swift    # NavigationSplitView 骨架
    SidebarView.swift    # 左侧仓库列表
    RepoDetailView.swift # 右侧:工具栏 + 图 + 状态栏
    CommitGraphView.swift# 图渲染:行、连线、节点、ref chip、配色
    Support.swift        # 相对时间、空状态、状态栏等小组件
```

## 已知限制 / 后续可加

- merge 冲突暂不在 UI 内解决,失败会弹错误,需到命令行处理
- 没有 commit / stage / diff 视图(刻意不做)
- push 无 upstream 时会失败弹错(后续可加 `--set-upstream`)
- graph 默认加载最近 400 条提交(`--all --topo-order`)

## 许可证

[MIT](LICENSE) © 2026 wangxi
