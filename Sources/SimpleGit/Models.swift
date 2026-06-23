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
    var id: String { path }
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
