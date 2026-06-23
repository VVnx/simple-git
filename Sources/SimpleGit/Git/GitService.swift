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
        let out = try await runner.run(["status", "--porcelain=v2", "--branch"])
        var branch = "HEAD"
        var detached = false
        var ahead = 0
        var behind = 0
        var upstream: String?
        var changed = 0
        var untracked = 0

        for raw in out.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if let v = value(of: line, prefix: "# branch.head ") {
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
                          changedCount: changed, untrackedCount: untracked, upstream: upstream)
    }

    // MARK: Mutations

    func fetch() async throws { try await runner.run(["fetch", "--all", "--prune"]) }

    func push() async throws { try await runner.run(["push"]) }

    func push(setUpstreamTo remote: String, branch: String) async throws {
        try await runner.run(["push", "--set-upstream", remote, branch])
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
        var args = ["diff-tree", "-r", "-M", "--name-status", "--no-commit-id"]
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
