import Foundation

/// One raw ref straight out of `git for-each-ref`.
struct RawRef {
    let commit: String        // dereferenced (points at a commit even for annotated tags)
    let refname: String       // refs/heads/main, refs/remotes/origin/main, refs/tags/v1
    let isHead: Bool
    let upstream: String?
}

/// High-level git operations for a single repository. Stateless besides the path,
/// so it is safe to call methods concurrently (each spawns its own process).
struct GitService {
    let path: String

    private var runner: GitRunner { GitRunner(workingDirectory: path) }

    private static let unit = "\u{1f}"   // field separator inside a line
    private static let remoteOperationTimeout: TimeInterval = 180

    // MARK: Validation

    /// Resolves an arbitrary path to its work-tree root, throwing a clear error if
    /// it isn't a usable repository (bare repos are reported distinctly).
    static func repoRoot(of path: String) async throws -> String {
        do {
            let out = try await GitRunner.run(["-C", path, "rev-parse", "--show-toplevel"], in: nil)
            let root = out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !root.isEmpty else { throw SimpleGitError("无法确定仓库根目录。") }
            return root
        } catch {
            // `--show-toplevel` fails on a bare repo; give an accurate message
            // instead of the generic "not a valid repository".
            if let bare = try? await GitRunner.run(["-C", path, "rev-parse", "--is-bare-repository"], in: nil),
               bare.trimmingCharacters(in: .whitespacesAndNewlines) == "true" {
                throw SimpleGitError("这是一个 bare 仓库(没有工作区),暂不支持。")
            }
            throw error
        }
    }

    /// Clones `url` into `destination` (which must not yet exist).
    static func clone(url: String, into destination: String) async throws {
        _ = try await GitRunner.run(["clone", url, destination], in: nil)
    }

    // MARK: Reads

    func log(limit: Int) async throws -> [Commit] {
        let fields = ["%H", "%P", "%an", "%ae", "%at", "%s"].joined(separator: Self.unit)
        let out = try await runner.run([
            "log", "--all", "--topo-order",
            "-n", String(limit),
            "--pretty=format:\(fields)"
        ])
        return out
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { Self.parseCommit(String($0)) }
    }

    func allRefs() async throws -> [RawRef] {
        let u = Self.unit
        let fmt = "%(objectname)\(u)%(*objectname)\(u)%(refname)\(u)%(HEAD)\(u)%(upstream:short)"
        let out = try await runner.run([
            "for-each-ref",
            "--format=\(fmt)",
            "refs/heads", "refs/remotes", "refs/tags"
        ])
        return out
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { Self.parseRawRef(String($0)) }
    }

    func status() async throws -> RepoStatus {
        // --untracked-files=all expands untracked directories into individual files
        // so the count matches the per-file list in workingFiles().
        let out = try await runner.run(["status", "--porcelain=v2", "--branch", "--untracked-files=all"])
        var branch = "HEAD"
        var detached = false
        var ahead = 0
        var behind = 0
        var upstream: String?
        var oid: String?
        var changed = 0
        var untracked = 0

        for raw in out.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if let v = value(of: line, prefix: "# branch.oid ") {
                oid = v
            } else if let v = value(of: line, prefix: "# branch.head ") {
                if v == "(detached)" { detached = true; branch = "detached HEAD" }
                else { branch = v }
            } else if let v = value(of: line, prefix: "# branch.upstream ") {
                upstream = v
            } else if let v = value(of: line, prefix: "# branch.ab ") {
                for token in v.split(separator: " ") {
                    if token.hasPrefix("+") { ahead = Int(token.dropFirst()) ?? 0 }
                    else if token.hasPrefix("-") { behind = Int(token.dropFirst()) ?? 0 }
                }
            } else if line.hasPrefix("? ") {
                untracked += 1
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") || line.hasPrefix("u ") {
                changed += 1
            }
        }

        return RepoStatus(branch: branch, detached: detached, ahead: ahead, behind: behind,
                          changedCount: changed, untrackedCount: untracked, upstream: upstream, oid: oid)
    }

    /// Current working-tree changes — one entry per file (like a commit's file
    /// list). Badge prefers the work-tree status, falling back to the index one.
    func workingFiles() async throws -> [WorkingFile] {
        // core.quotePath=false keeps non-ASCII paths (e.g. Chinese) readable;
        // --untracked-files=all lists files inside untracked dirs instead of
        // collapsing them to a single "Assets/" entry.
        let out = try await runner.run(["-c", "core.quotePath=false", "status", "--porcelain=v2", "--untracked-files=all"])
        var result: [WorkingFile] = []
        for raw in out.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                let isRename = line.hasPrefix("2 ")
                let fixedCount = isRename ? 9 : 8
                let parts = Self.splitFields(line, count: fixedCount)
                guard parts.count == fixedCount + 1 else { continue }
                let xy = Array(parts[1])
                let x = xy.count > 0 ? String(xy[0]) : "."
                let y = xy.count > 1 ? String(xy[1]) : "."
                var path = parts[fixedCount]
                var oldPath: String?
                if isRename {
                    let comps = path.components(separatedBy: "\t")
                    if comps.count >= 2 { path = comps[0]; oldPath = comps[1] }
                }
                let badge = y != "." ? y : x
                result.append(WorkingFile(badge: badge, path: path, oldPath: oldPath))
            } else if line.hasPrefix("u ") {
                let parts = Self.splitFields(line, count: 10)
                guard parts.count == 11 else { continue }
                result.append(WorkingFile(badge: "U", path: parts[10], oldPath: nil))
            } else if line.hasPrefix("? ") {
                result.append(WorkingFile(badge: "?", path: String(line.dropFirst(2)), oldPath: nil))
            }
            // "! " (ignored) entries are skipped.
        }
        return result
    }

    /// Splits `line` into the first `count` space-separated fields plus the
    /// remaining tail as one final element (so a path with spaces stays intact).
    private static func splitFields(_ line: String, count: Int) -> [String] {
        var fields: [String] = []
        var rest = Substring(line)
        for _ in 0..<count {
            guard let space = rest.firstIndex(of: " ") else { return fields + [String(rest)] }
            fields.append(String(rest[..<space]))
            rest = rest[rest.index(after: space)...]
        }
        fields.append(String(rest))
        return fields
    }

    // MARK: Mutations

    func fetch() async throws {
        try await runner.run(["fetch", "--all", "--prune"], timeout: Self.remoteOperationTimeout)
    }

    func pull() async throws {
        try await runner.run(["pull", "--no-edit"], timeout: Self.remoteOperationTimeout)
    }

    func push() async throws {
        try await runner.run(["push"], timeout: Self.remoteOperationTimeout)
    }

    func push(setUpstreamTo remote: String, branch: String) async throws {
        try await runner.run(["push", "--set-upstream", remote, branch], timeout: Self.remoteOperationTimeout)
    }

    func merge(_ branch: String) async throws { try await runner.run(["merge", "--no-edit", branch]) }

    func remotes() async throws -> [String] {
        let out = try await runner.run(["remote"])
        return out.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// Files changed by a commit. For a normal/root commit this is the diff vs its
    /// parent (or the whole tree for the root); for a merge it's the net change vs
    /// the first parent.
    func changedFiles(of commit: Commit) async throws -> [ChangedFile] {
        // core.quotePath=false keeps non-ASCII paths (e.g. Chinese) raw, so the
        // path can be passed straight back to `git show` to load its diff.
        var args = ["-c", "core.quotePath=false", "diff-tree", "-r", "-M", "--name-status", "--no-commit-id"]
        if commit.parents.count > 1 {
            args += [commit.parents[0], commit.hash]
        } else {
            args += ["--root", commit.hash]
        }
        let out = try await runner.run(args)
        return out
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { ChangedFile(statusLine: String($0)) }
    }

    /// Unified diff of one file within a commit (vs its first parent).
    func commitFileDiff(hash: String, path: String) async throws -> String {
        let out = try await runner.run(["-c", "core.quotePath=false", "show", hash, "--format=", "-M", "--", path])
        return String(out.drop(while: { $0 == "\n" }))
    }

    /// Largest untracked file we'll render in full as a diff. Above this, showing
    /// the whole content as additions would mean reading (and coloring) megabytes
    /// of text — almost always a vendored blob (node_modules, build output) the
    /// user doesn't actually want to inspect here.
    private static let maxUntrackedPreviewBytes = 2_000_000

    /// Unified diff of one file in the working tree (HEAD → working copy). Falls
    /// back to showing a brand-new untracked file's contents as additions.
    func workingFileDiff(path: String) async throws -> String {
        let tracked = try await runner.run(["-c", "core.quotePath=false", "diff", "HEAD", "-M", "--", path])
        if !tracked.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return tracked }

        // Untracked (or unchanged-vs-HEAD) file: `--no-index` emits its entire
        // content as additions. Skip the preview for very large files so a big
        // vendored blob can't flood the diff view.
        let full = (self.path as NSString).appendingPathComponent(path)
        if let size = try? FileManager.default.attributesOfItem(atPath: full)[.size] as? Int,
           size > Self.maxUntrackedPreviewBytes {
            return "diff --git a/\(path) b/\(path)\n@@ 文件较大(约 \(size / 1024) KB),已跳过预览 @@\n这是一个未跟踪的大文件,完整内容请用编辑器打开。"
        }
        return try await runner.run(["-c", "core.quotePath=false", "diff", "--no-index", "--", "/dev/null", path], allowNonZero: true)
    }

    // MARK: Parsing

    private func value(of line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    private static func parseCommit(_ line: String) -> Commit? {
        let f = line.components(separatedBy: unit)
        guard f.count >= 6 else { return nil }
        let parents = f[1].split(separator: " ").map(String.init)
        let timestamp = TimeInterval(f[4]) ?? 0
        // Subject is the last field; rejoin in case it somehow contained the separator.
        let subject = f[5...].joined(separator: unit)
        return Commit(
            hash: f[0],
            parents: parents,
            authorName: f[2],
            authorEmail: f[3],
            date: Date(timeIntervalSince1970: timestamp),
            subject: subject
        )
    }

    private static func parseRawRef(_ line: String) -> RawRef? {
        let f = line.components(separatedBy: unit)
        guard f.count >= 5 else { return nil }
        let object = f[0]
        let deref = f[1]
        let commit = deref.isEmpty ? object : deref
        let upstream = f[4].isEmpty ? nil : f[4]
        return RawRef(commit: commit, refname: f[2], isHead: f[3] == "*", upstream: upstream)
    }
}
