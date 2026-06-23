import Foundation
import SwiftUI

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

    /// Ticks once a minute so relative timestamps in the graph stay fresh.
    @Published private(set) var now = Date()
    private var clockTimer: Timer?

    /// Bumped on every (re)load; a load only publishes if it is still the latest,
    /// so a slow repo's results can't clobber a repo the user has since switched to.
    private var loadGeneration = 0

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

    func removeRepository(_ repo: Repository) {
        repositories.removeAll { $0.id == repo.id }
        persist()
        if selectedRepoID == repo.id {
            select(repositories.first?.id)
        }
    }

    func select(_ id: Repository.ID?) {
        selectedRepoID = id
        reload()
    }

    // MARK: - Loading

    func reload() {
        guard let repo = selectedRepo else {
            clearLoadedData()
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        Task { await load(repo: repo, generation: generation) }
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

            let layout = GraphLayout.compute(commits)

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

    func merge(_ branch: Branch) {
        perform("正在 Merge \(branch.name)…", success: "已合并 \(branch.name)") { try await $0.merge(branch.name) }
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
                errorMessage = error.localizedDescription
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
