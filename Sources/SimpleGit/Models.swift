import Foundation

/// A user-facing error with a ready-made Chinese message.
struct SimpleGitError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Repository

/// A tracked repository. `path` is the absolute path to the repo root and is
/// used as the stable identity.
struct Repository: Identifiable, Codable, Hashable {
    var name: String
    var path: String
    /// When true, the name is shown masked in the UI (privacy / screenshots).
    var masked: Bool = false

    var id: String { path }

    /// Name as shown in the list — masked to first+•••+last when `masked` is on.
    /// Fixed dot count so the real length isn't revealed.
    var displayName: String { masked ? Self.maskName(name) : name }

    static func maskName(_ name: String) -> String {
        let chars = Array(name)
        guard chars.count > 2 else { return chars.isEmpty ? "" : "\(chars[0])•••" }
        return "\(chars.first!)•••\(chars.last!)"
    }

    init(name: String, path: String, masked: Bool = false) {
        self.name = name
        self.path = path
        self.masked = masked
    }

    // Decode tolerantly so repos persisted before `masked` existed still load.
    enum CodingKeys: String, CodingKey { case name, path, masked }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        masked = try c.decodeIfPresent(Bool.self, forKey: .masked) ?? false
    }
}

// MARK: - Commit & refs

struct Ref: Hashable, Identifiable {
    enum Kind: Int { case head, localBranch, remoteBranch, tag, other }
    let kind: Kind
    let name: String          // short name: "main", "origin/main", "v1.0"
    var id: String { "\(kind.rawValue)-\(name)" }
}

struct Commit: Identifiable, Hashable {
    let hash: String
    let parents: [String]
    let authorName: String
    let authorEmail: String
    let date: Date
    let subject: String

    var id: String { hash }
    var shortHash: String { String(hash.prefix(7)) }

    /// Sentinel hash for the synthetic "uncommitted changes" node injected into
    /// the graph as a virtual child of HEAD.
    static let uncommittedHash = "·uncommitted·"
    var isUncommitted: Bool { hash == Commit.uncommittedHash }
}

// MARK: - Branch (for the merge picker)

struct Branch: Identifiable, Hashable {
    let name: String          // "main" or "origin/main"
    let fullRef: String       // "refs/heads/main"
    let isCurrent: Bool
    let isRemote: Bool
    let upstream: String?
    var id: String { fullRef }
}

// MARK: - Working-tree / branch status

struct RepoStatus {
    var branch: String
    var detached: Bool
    var ahead: Int
    var behind: Int
    var changedCount: Int      // staged + unstaged + conflicted
    var untrackedCount: Int
    var upstream: String?
    var oid: String?           // HEAD commit hash ("(initial)" on an unborn branch)
    var clean: Bool { changedCount == 0 && untrackedCount == 0 }
}

// MARK: - Graph layout model

/// One drawn segment of the graph within a single row. `top` segments run from
/// the row's top edge to its vertical center (the node); `bottom` segments run
/// from the center to the bottom edge. Because lane indices are stable across
/// rows, a straight segment in one row lines up with the next.
struct GraphEdge: Hashable {
    enum Half { case top, bottom }
    let fromColumn: Int
    let toColumn: Int
    let colorIndex: Int
    let half: Half
}

struct CommitNode: Identifiable {
    let commit: Commit
    let column: Int
    let colorIndex: Int
    let edges: [GraphEdge]
    var id: String { commit.hash }
}

struct GraphLayoutResult {
    let nodes: [CommitNode]
    let laneCount: Int
}

// MARK: - Graph selection (commit row vs. the uncommitted-changes row)

enum GraphSelection: Equatable {
    case none
    case uncommitted
    case commit(String)   // hash
}

// MARK: - Working-tree file (uncommitted changes)

struct WorkingFile: Identifiable {
    let badge: String       // M / A / D / R / C / T / U / ?
    let path: String
    let oldPath: String?
    var id: String { "\(badge)|\(oldPath ?? "")|\(path)" }
}

// MARK: - Changed file (commit detail)

struct ChangedFile: Identifiable {
    let status: String      // raw git status: "A", "M", "D", "T", "R100", "C75"…
    let path: String
    let oldPath: String?    // present for renames / copies

    var id: String { "\(status)|\(oldPath ?? "")|\(path)" }

    /// Parses one tab-separated line of `git diff-tree --name-status` output.
    init?(statusLine line: String) {
        let parts = line.components(separatedBy: "\t").filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let status = parts[0]
        if (status.hasPrefix("R") || status.hasPrefix("C")), parts.count >= 3 {
            self.status = status
            self.oldPath = parts[1]
            self.path = parts[2]
        } else {
            self.status = status
            self.oldPath = nil
            self.path = parts[1]
        }
    }
}
