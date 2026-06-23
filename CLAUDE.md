# CLAUDE.md

写给在本仓库工作的 Claude / agent 看的协作约定与项目速查。

## 工作约定

- **每完成一个任务就提交一次**。一个独立、可构建的改动 = 一个 commit；不要把多件事攒到一个大 commit 里。多步任务按步拆分提交。
- **提交前先 `swift build` 确认能编译通过**再 commit。
- 提交信息用**中文** + 约定式前缀:`feat:` / `fix:` / `refactor:` / `style:` / `chore:`,首行简洁,需要时空一行写要点。
- 每条 commit 结尾加一行:`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- 直接提交到当前分支(本项目是单人 `main` 流程);**不要自行 push**,等用户明确要求。

## 构建与运行

```sh
swift build                      # 编译
swift run simple-git             # 运行(裸可执行文件,无需 Xcode)
./Assets/make_app.sh /Applications  # release 打包成 .app 并安装(ad-hoc 签名,自用)
```

也可用 Xcode 打开 `Package.swift` 后 ⌘R。改动后要看效果需重启 app(旧实例跑的是旧二进制);若用户在用已安装的 `.app`,改完要重新跑 `make_app.sh` 覆盖安装。

## 架构速查

SwiftUI + AppKit(macOS 13+),所有 git 操作通过命令行 `git` 子进程完成,无第三方依赖。

- `App.swift` — `@main` + AppDelegate(拉窗口到前台、运行时设置 Dock 图标)
- `AppStore.swift` — `@MainActor` 状态中枢,所有状态与动作;`reload()` 是加载仓库的唯一入口
- `Models.swift` — Repository / Commit / Branch / RepoStatus / 图模型
- `Git/`
  - `GitRunner.swift` — Process 封装,异步跑 git;**已设 `GIT_OPTIONAL_LOCKS=0`**,读操作不写 `.git`
  - `GitService.swift` — 高层命令:log / status / refs / diff / fetch / push / merge
  - `GraphLayout.swift` — commit graph 泳道分配算法
  - `RepoWatcher.swift` — FSEvents 监听 `.git`,外部变更后自动刷新 UI
- `Views/` — `ContentView`(分栏骨架) / `SidebarView` / `RepoDetailView` / `CommitGraphView`(自绘图) / `WorkingChangesPanel` / `CommitDetailPanel` / `DiffView` / `Support.swift`(状态栏、toast 等)

## 注意点

- 加载用 `loadGeneration` 代际守卫:慢仓库的结果不会覆盖已切换到的新仓库。
- `RepoWatcher` 随仓库切换重建;app 自身的 git 读取不会触发刷新回环(见上 `GIT_OPTIONAL_LOCKS`)。

## 图标

单一矢量源 + 一键生成,不要手改生成出的 PNG/icns:

- `Assets/icon.svg` — App 图标源;`Assets/brand/*.svg` — 状态栏品牌图标源(Codex/Claude/VS Code)
- `Assets/generate_icon.sh` — 从 SVG 重新生成 `app-icon-1024.png` / `AppIcon.icns` / `AppIcon.appiconset` 及 `Sources/SimpleGit/Resources/AppIcon.png`
- 状态栏图标作为 SwiftPM 资源打包(`Package.swift` 的 `resources`),通过 `Bundle.module` 加载
