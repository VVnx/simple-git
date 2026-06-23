import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppStore: ObservableObject {
    // Repositories & selection
    @Published var repositories: [Repository] = []
    @Published var selectedRepoID: Repository.ID?

    // Loaded data for the selected repo
    @Published private(set) var nodes: [CommitNode] = []
    @Published private(set) var laneCount: Int = 1
    @Published private(set) var refsByCommit: [String: [Ref]] = [:]
    @Published private(set) var branches: [Branch] = []
    @Published private(set) var status: RepoStatus?

    // UI state
    @Published private(set) var isLoading = false
    @Published var busyMessage: String?
    @Published var errorMessage: String?
    /// Transient success banner ("Push 成功" …); auto-clears after a few seconds.
    @Published var successMessage: String?
    private var successClearTask: Task<Void, Never>?

    // Bottom detail panel: either a commit's diff or the working tree's changes.
    @Published var selection: GraphSelection = .none
    @Published private(set) var changedFiles: [ChangedFile] = []
    @Published private(set) var workingFiles: [WorkingFile] = []
    @Published private(set) var isLoadingFiles = false
    private var filesGeneration = 0

    // Within the detail panel: the file whose diff is shown on the right.
    @Published var selectedFilePath: String?
    @Published private(set) var fileDiff: String = ""
    @Published private(set) var isLoadingDiff = false
    private var diffGeneration = 0

    /// One-shot request for the graph to scroll to a commit. The token makes a
    /// repeated tap re-fire even when the target hash hasn't changed.
    struct ScrollTarget: Equatable { let hash: String; let token: Int }
    @Published private(set) var scrollTarget: ScrollTarget?
    private var scrollToken = 0

    /// Ticks once a minute so relative timestamps in the graph stay fresh.
    @Published private(set) var now = Date()
    private var clockTimer: Timer?

    /// Bumped on every (re)load; a load only publishes if it is still the latest,
    /// so a slow repo's results can't clobber a repo the user has since switched to.
    private var loadGeneration = 0

    /// Watches the selected repo's `.git` so external changes (e.g. a commit made
    /// in a terminal or agent) refresh the UI automatically. Recreated on switch.
    private var watcher: RepoWatcher?
    private var watchedPath: String?

    let commitLimit = 400
    private let defaultsKey = "repositories.v1"

    init() {
        loadPersisted()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    var selectedRepo: Repository? {
        repositories.first { $0.id == selectedRepoID }
    }

    /// Branches the user can merge into the current one (everything but HEAD).
    var mergeableBranches: [Branch] {
        branches.filter { !$0.isCurrent && $0.name != status?.branch }
    }

    /// The currently inspected commit, resolved against the loaded graph so it
    /// drops automatically if a reload no longer contains it.
    var selectedCommit: Commit? {
        guard case let .commit(hash) = selection else { return nil }
        return nodes.first { $0.commit.hash == hash }?.commit
    }

    var isUncommittedSelected: Bool { selection == .uncommitted }

    // MARK: - Persistence

    private func loadPersisted() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let repos = try? JSONDecoder().decode([Repository].self, from: data) else { return }
        repositories = repos
        selectedRepoID = repos.first?.id
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(repositories) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - Repository management

    func addRepository(at url: URL) {
        Task {
            do {
                let root = try await GitService.repoRoot(of: url.path)
                let repo = Repository(name: URL(fileURLWithPath: root).lastPathComponent, path: root)
                if !repositories.contains(where: { $0.id == repo.id }) {
                    repositories.append(repo)
                    persist()
                }
                select(repo.id)
            } catch let error as SimpleGitError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = "「\(url.lastPathComponent)」不是一个有效的 Git 仓库。"
            }
        }
    }

    /// Clones a remote repo into `parent`/<derived-name> and adds it. Throws so the
    /// clone sheet can show progress and surface failures inline.
    func cloneRepository(url: String, into parent: URL) async throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SimpleGitError("请输入仓库 URL。") }
        let name = Self.deriveRepoName(from: trimmed)
        guard !name.isEmpty else { throw SimpleGitError("无法从 URL 解析仓库名。") }
        let dest = parent.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            throw SimpleGitError("目标目录已存在:\(dest.path)")
        }
        try await GitService.clone(url: trimmed, into: dest.path)
        let root = try await GitService.repoRoot(of: dest.path)
        let repo = Repository(name: URL(fileURLWithPath: root).lastPathComponent, path: root)
        if !repositories.contains(where: { $0.id == repo.id }) {
            repositories.append(repo)
            persist()
        }
        select(repo.id)
        flashSuccess("克隆完成:\(name)")
    }

    /// Best-effort repo name from a clone URL: "git@host:user/repo.git" → "repo".
    static func deriveRepoName(from url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        if let idx = s.lastIndex(where: { $0 == "/" || $0 == ":" }) {
            s = String(s[s.index(after: idx)...])
        }
        return s
    }

    func removeRepository(_ repo: Repository) {
        repositories.removeAll { $0.id == repo.id }
        persist()
        if selectedRepoID == repo.id {
            select(repositories.first?.id)
        }
    }

    func select(_ id: Repository.ID?) {
        selectedRepoID = id
        clearSelection()
        reload()
    }

    // MARK: - Graph row inspection

    func selectCommit(_ commit: Commit) {
        selection = .commit(commit.hash)
        let generation = bumpFilesGeneration()
        guard let repo = selectedRepo else { isLoadingFiles = false; return }
        let service = GitService(path: repo.path)
        isLoadingFiles = true
        Task {
            let files = (try? await service.changedFiles(of: commit)) ?? []
            guard generation == filesGeneration else { return }
            changedFiles = files
            isLoadingFiles = false
        }
    }

    func selectUncommitted() {
        selection = .uncommitted
        let generation = bumpFilesGeneration()
        guard let repo = selectedRepo else { isLoadingFiles = false; return }
        let service = GitService(path: repo.path)
        isLoadingFiles = true
        Task {
            let files = (try? await service.workingFiles()) ?? []
            guard generation == filesGeneration else { return }
            workingFiles = files
            isLoadingFiles = false
        }
    }

    /// Scrolls the graph to — and selects — the tip of the current branch (HEAD).
    /// No-op on an unborn branch or if HEAD isn't in the loaded window.
    func locateCurrentHead() {
        guard let oid = status?.oid, oid != "(initial)",
              let node = nodes.first(where: { $0.commit.hash == oid }) else { return }
        selectCommit(node.commit)
        scrollToken += 1
        scrollTarget = ScrollTarget(hash: oid, token: scrollToken)
    }

    func clearSelection() {
        selection = .none
        changedFiles = []
        workingFiles = []
        resetFileDiff()
        filesGeneration += 1
        isLoadingFiles = false
    }

    private func bumpFilesGeneration() -> Int {
        changedFiles = []
        workingFiles = []
        resetFileDiff()
        filesGeneration += 1
        return filesGeneration
    }

    private func resetFileDiff() {
        selectedFilePath = nil
        fileDiff = ""
        isLoadingDiff = false
        diffGeneration += 1
    }

    /// Loads the diff for a file within the current selection (commit or working tree).
    func selectFile(_ path: String) {
        selectedFilePath = path
        diffGeneration += 1
        let generation = diffGeneration
        let currentSelection = selection
        guard let repo = selectedRepo else { fileDiff = ""; isLoadingDiff = false; return }
        let service = GitService(path: repo.path)
        isLoadingDiff = true
        Task {
            let text: String
            switch currentSelection {
            case .commit(let hash):
                text = (try? await service.commitFileDiff(hash: hash, path: path)) ?? ""
            case .uncommitted:
                text = (try? await service.workingFileDiff(path: path)) ?? ""
            case .none:
                text = ""
            }
            guard generation == diffGeneration else { return }
            fileDiff = text
            isLoadingDiff = false
        }
    }

    func copyCommitHash(_ commit: Commit) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commit.hash, forType: .string)
        flashSuccess("已复制 hash \(commit.shortHash)")
    }

    /// Launches an external app via `open -a`, optionally opening `path` with it
    /// (e.g. opening the current repo folder in VS Code).
    func openExternalApp(_ appName: String, path: String? = nil) {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            var args = ["-a", appName]
            if let path { args.append(path) }
            process.arguments = args
            try? process.run()
        }
    }

    // MARK: - Loading

    func reload() {
        guard let repo = selectedRepo else {
            clearLoadedData()
            stopWatching()
            return
        }
        startWatching(repo)
        loadGeneration += 1
        let generation = loadGeneration
        Task { await load(repo: repo, generation: generation) }
    }

    // MARK: - Auto-refresh on external changes

    private func startWatching(_ repo: Repository) {
        guard watchedPath != repo.path else { return }   // already watching this repo
        watcher = RepoWatcher(path: repo.path) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        watchedPath = repo.path
    }

    private func stopWatching() {
        watcher = nil
        watchedPath = nil
    }

    /// Re-reads on-disk state after an external change: the graph + status, plus
    /// the working-changes panel if that's the one open (a commit's file list is
    /// immutable, so it needs no refresh). Triggered by `RepoWatcher`.
    func refresh() {
        reload()
        if selection == .uncommitted {
            let keepFile = selectedFilePath
            selectUncommitted()
            if let keepFile { selectFile(keepFile) }
        }
    }

    private func clearLoadedData() {
        nodes = []; laneCount = 1; refsByCommit = [:]; branches = []; status = nil
    }

    private func load(repo: Repository, generation: Int) async {
        isLoading = true
        let service = GitService(path: repo.path)
        do {
            // Run the three reads concurrently. On a valid repo (even a brand-new
            // empty one) all three exit cleanly; only a genuinely broken/missing
            // repo throws, and we want to surface that rather than show a blank.
            async let rawRefsTask = service.allRefs()
            async let statusTask = service.status()
            async let commitsTask = service.log(limit: commitLimit)
            let raws = try await rawRefsTask
            let statusVal = try await statusTask
            let commits = try await commitsTask

            // Drop the result if a newer load has started for another repo.
            guard generation == loadGeneration else { return }

            var refsMap: [String: [Ref]] = [:]
            var branchList: [Branch] = []
            for raw in raws {
                if let name = stripPrefix(raw.refname, "refs/heads/") {
                    refsMap[raw.commit, default: []].append(Ref(kind: .localBranch, name: name))
                    branchList.append(Branch(name: name, fullRef: raw.refname, isCurrent: raw.isHead,
                                             isRemote: false, upstream: raw.upstream))
                } else if let name = stripPrefix(raw.refname, "refs/remotes/") {
                    if name.hasSuffix("/HEAD") { continue }   // skip the symbolic origin/HEAD
                    refsMap[raw.commit, default: []].append(Ref(kind: .remoteBranch, name: name))
                    branchList.append(Branch(name: name, fullRef: raw.refname, isCurrent: false,
                                             isRemote: true, upstream: nil))
                } else if let name = stripPrefix(raw.refname, "refs/tags/") {
                    refsMap[raw.commit, default: []].append(Ref(kind: .tag, name: name))
                }
            }
            for key in refsMap.keys {
                refsMap[key]?.sort { $0.kind.rawValue < $1.kind.rawValue }
            }

            // Inject a synthetic "uncommitted changes" node as a virtual child of
            // HEAD, so the graph connects it to the local branch — not the topmost
            // commit — exactly where the working tree is based.
            var graphCommits = commits
            if !statusVal.clean, let oid = statusVal.oid, oid != "(initial)",
               commits.contains(where: { $0.hash == oid }) {
                let uncommitted = Commit(
                    hash: Commit.uncommittedHash,
                    parents: [oid],
                    authorName: "",
                    authorEmail: "",
                    date: Date(),
                    subject: ""
                )
                graphCommits.insert(uncommitted, at: 0)
            }
            let layout = GraphLayout.compute(graphCommits)

            refsByCommit = refsMap
            branches = branchList.sorted { $0.name < $1.name }
            status = statusVal
            nodes = layout.nodes
            laneCount = layout.laneCount
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            clearLoadedData()
            errorMessage = loadErrorText(error, repo: repo)
            isLoading = false
        }
    }

    private func loadErrorText(_ error: Error, repo: Repository) -> String {
        if !FileManager.default.fileExists(atPath: repo.path) {
            return "仓库路径不存在或已被移动:\n\(repo.path)"
        }
        return "无法读取仓库「\(repo.name)」:\n\(error.localizedDescription)"
    }

    // MARK: - Actions

    func fetch() { perform("正在 Fetch…", success: "Fetch 完成") { try await $0.fetch() } }

    func pull() { perform("正在 Pull…", success: "Pull 完成") { try await $0.pull() } }

    func push() {
        // Capture status on the main actor before handing work to the background.
        let current = status
        perform("正在 Push…", success: "Push 成功") { service in
            if let current, current.upstream == nil, !current.detached {
                // No upstream yet — set one against the repo's remote so a freshly
                // created branch pushes without the user typing a command.
                let remotes = (try? await service.remotes()) ?? []
                guard let remote = remotes.first else {
                    throw SimpleGitError("当前仓库没有配置远程仓库,无法 push。")
                }
                try await service.push(setUpstreamTo: remote, branch: current.branch)
            } else {
                try await service.push()
            }
        }
    }

    func mergeCommit(_ commit: Commit) {
        perform("正在 Merge \(commit.shortHash)…", success: "已合并 \(commit.shortHash)") {
            try await $0.merge(commit.hash)
        }
    }

    private func perform(_ message: String, success: String, _ op: @escaping (GitService) async throws -> Void) {
        guard let repo = selectedRepo else { return }
        let service = GitService(path: repo.path)
        Task {
            busyMessage = message
            successMessage = nil
            var succeeded = false
            do {
                try await op(service)
                succeeded = true
            } catch {
                errorMessage = Self.friendlyGitMessage(error)
            }
            // Always refresh afterwards — even on failure — so a half-applied
            // action (e.g. a conflicted merge that left the tree MERGING) shows
            // the real on-disk state instead of the stale pre-action one.
            loadGeneration += 1
            let generation = loadGeneration
            await load(repo: repo, generation: generation)

            busyMessage = nil
            if succeeded { flashSuccess(success) }
        }
    }

    /// Maps raw `git` stderr into a short, actionable Chinese message for the
    /// error alert. Falls back to the raw text with git's verbose `hint:` noise
    /// stripped, so even unrecognized errors read more cleanly.
    static func friendlyGitMessage(_ error: Error) -> String {
        if let simple = error as? SimpleGitError { return simple.message }
        let raw = (error as? GitError)?.message ?? error.localizedDescription
        let lower = raw.lowercased()

        if lower.contains("fetch first") || lower.contains("non-fast-forward")
            || (lower.contains("rejected") && lower.contains("remote contains work")) {
            return "推送被拒绝:远端有你本地还没有的提交。请先 Pull 拉取合并,再 Push。"
        }
        if lower.contains("permission denied") || lower.contains("authentication failed")
            || lower.contains("could not read from remote") {
            return "无法访问远程仓库:认证失败或没有权限。\n检查 SSH key 是否已加到 GitHub,以及对该仓库的访问权限。"
        }
        if lower.contains("conflict") || lower.contains("automatic merge failed") {
            return "合并有冲突:需要手动解决。\n请到命令行处理冲突后,再回到 app 刷新。"
        }
        if lower.contains("divergent branches") || lower.contains("need to specify how to reconcile") {
            return "本地与远端已分叉:需要先合并或变基。可先点 Pull 再试。"
        }
        if lower.contains("couldn't find remote ref") || lower.contains("no configured push destination")
            || lower.contains("does not appear to be a git repository") {
            return "找不到远程仓库或对应分支,检查 remote 配置是否正确。"
        }

        // Fallback: drop git's verbose "hint:" lines, keep the real error.
        let core = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.lowercased().hasPrefix("hint:") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return core.isEmpty ? raw : core
    }

    /// Shows a transient success banner that fades out on its own.
    private func flashSuccess(_ text: String) {
        successClearTask?.cancel()
        successMessage = text
        successClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.successMessage = nil
        }
    }

    private func stripPrefix(_ s: String, _ prefix: String) -> String? {
        s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : nil
    }
}
