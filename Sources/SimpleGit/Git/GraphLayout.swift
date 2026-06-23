import Foundation

/// Assigns each commit to a column ("lane") and produces the line segments that
/// connect commits to their parents, à la SourceTree / GitKraken.
///
/// Lane indices are kept **stable**: once a lane is freed it becomes a hole that
/// can be reused, but existing lanes never shift left. That stability is what lets
/// the view draw each row independently — a straight segment at lane `i` in one
/// row lines up exactly with lane `i` in the next.
///
/// Commits must be supplied newest-first with every parent appearing *after* its
/// children (i.e. `git log --topo-order` / `--date-order` output).
enum GraphLayout {

    static func compute(_ commits: [Commit]) -> GraphLayoutResult {
        var lanes: [String?] = []          // lane slot -> hash the lane is reserved for
        var nodes: [CommitNode] = []
        nodes.reserveCapacity(commits.count)

        func firstFreeLane() -> Int {
            if let idx = lanes.firstIndex(where: { $0 == nil }) { return idx }
            lanes.append(nil)
            return lanes.count - 1
        }

        for commit in commits {
            let incoming = lanes               // snapshot before mutating

            // The commit's column: a lane a child already reserved for it, else a new lane.
            let reserved = incoming.indices.filter { incoming[$0] == commit.hash }
            let column = reserved.first ?? firstFreeLane()

            var edges: [GraphEdge] = []

            // Top half: every active incoming lane reaches down to this row's center.
            for i in incoming.indices {
                guard let hash = incoming[i] else { continue }
                if hash == commit.hash {
                    // A child of this commit (or the reservation for it) merges into the dot.
                    edges.append(GraphEdge(fromColumn: i, toColumn: column, colorIndex: column, half: .top))
                } else {
                    // Unrelated lane passing straight through.
                    edges.append(GraphEdge(fromColumn: i, toColumn: i, colorIndex: i, half: .top))
                }
            }

            // Close the extra reserved lanes (multiple children converging) and free
            // the commit's own lane so a parent can take it over.
            for i in reserved where i != column { lanes[i] = nil }
            lanes[column] = nil

            // Assign parents to lanes. A parent that already has an open lane
            // (another child reserved it) is reused so the same commit is never
            // drawn in two differently-coloured lanes — this is what makes a
            // diamond / criss-cross merge converge into a single line instead of
            // running two parallel lanes down to the shared ancestor.
            var parentColumns: [Int] = []
            for (index, parent) in commit.parents.enumerated() {
                if let existing = lanes.firstIndex(where: { $0 == parent }) {
                    parentColumns.append(existing)          // merge into the lane already heading there
                } else if index == 0 {
                    lanes[column] = parent                  // first parent continues straight in this column
                    parentColumns.append(column)
                } else {
                    let slot = firstFreeLane()              // an extra merge parent opens a new lane
                    lanes[slot] = parent
                    parentColumns.append(slot)
                }
            }

            // Bottom half — straight continuations: any lane whose hash is unchanged
            // across this row keeps going down in place.
            for j in lanes.indices {
                guard let hash = lanes[j] else { continue }
                if j < incoming.count, incoming[j] == hash {
                    edges.append(GraphEdge(fromColumn: j, toColumn: j, colorIndex: j, half: .bottom))
                }
            }
            // Bottom half — parent links: from the dot out to each parent's lane.
            for target in parentColumns {
                edges.append(GraphEdge(fromColumn: column, toColumn: target, colorIndex: target, half: .bottom))
            }

            nodes.append(CommitNode(commit: commit, column: column, colorIndex: column, edges: edges))

            // Trim trailing holes so the lane array (and graph width) stays tight.
            while let last = lanes.last, last == nil { lanes.removeLast() }
        }

        // Widest row determines the graph's column count.
        var widest = 1
        for node in nodes {
            widest = max(widest, node.column + 1)
            for edge in node.edges {
                widest = max(widest, edge.fromColumn + 1, edge.toColumn + 1)
            }
        }
        return GraphLayoutResult(nodes: nodes, laneCount: widest)
    }
}
