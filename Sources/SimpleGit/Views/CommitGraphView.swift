import SwiftUI

// MARK: - Palette

enum GraphPalette {
    static let colors: [Color] = [
        Color(red: 0.27, green: 0.54, blue: 0.95),  // blue
        Color(red: 0.20, green: 0.70, blue: 0.42),  // green
        Color(red: 0.93, green: 0.49, blue: 0.19),  // orange
        Color(red: 0.64, green: 0.36, blue: 0.86),  // purple
        Color(red: 0.87, green: 0.30, blue: 0.46),  // pink
        Color(red: 0.18, green: 0.66, blue: 0.71),  // teal
        Color(red: 0.80, green: 0.66, blue: 0.20),  // gold
        Color(red: 0.45, green: 0.51, blue: 0.94)   // indigo
    ]

    static func color(_ index: Int) -> Color {
        let count = colors.count
        return colors[((index % count) + count) % count]
    }
}

// MARK: - Graph list

struct CommitGraphView: View {
    let nodes: [CommitNode]
    let laneCount: Int
    let refsByCommit: [String: [Ref]]
    let currentBranch: String?
    let now: Date
    let selectedHash: String?
    let onSelect: (Commit) -> Void
    let onCopyHash: (Commit) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(nodes) { node in
                    CommitRowView(
                        node: node,
                        laneCount: laneCount,
                        refs: refsByCommit[node.commit.hash] ?? [],
                        currentBranch: currentBranch,
                        now: now,
                        isSelected: node.commit.hash == selectedHash,
                        onSelect: { onSelect(node.commit) },
                        onCopyHash: { onCopyHash(node.commit) }
                    )
                    Divider().opacity(0.2)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - One row

struct CommitRowView: View {
    let node: CommitNode
    let laneCount: Int
    let refs: [Ref]
    let currentBranch: String?
    let now: Date
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopyHash: () -> Void

    static let rowHeight: CGFloat = 32
    static let laneSpacing: CGFloat = 16
    static let leftPad: CGFloat = 8
    static let dotRadius: CGFloat = 4.5

    private var graphWidth: CGFloat {
        Self.leftPad + CGFloat(max(laneCount, 1)) * Self.laneSpacing
    }

    var body: some View {
        HStack(spacing: 8) {
            Canvas { context, size in draw(in: context, size: size) }
                .frame(width: graphWidth, height: Self.rowHeight)

            HStack(spacing: 6) {
                ForEach(refs) { ref in
                    RefChip(ref: ref, isCurrent: ref.kind == .localBranch && ref.name == currentBranch)
                }
                Text(node.commit.subject)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Text(node.commit.authorName)
                        .foregroundStyle(.secondary)
                    Text(node.commit.authorEmail)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 260, alignment: .trailing)

                Text(RelativeDate.string(from: node.commit.date, now: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 78, alignment: .trailing)

                Button(action: onCopyHash) {
                    Text(node.commit.shortHash)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("点击复制完整 hash")
            }
            .padding(.trailing, 12)
        }
        .frame(height: Self.rowHeight)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .help("\(node.commit.shortHash) · \(node.commit.authorName) <\(node.commit.authorEmail)> · \(RelativeDate.absoluteString(from: node.commit.date))\n\(node.commit.subject)")
    }

    private func x(_ column: Int) -> CGFloat {
        Self.leftPad + CGFloat(column) * Self.laneSpacing + Self.laneSpacing / 2
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let mid = size.height / 2

        for edge in node.edges {
            let path = edgePath(edge, height: size.height, mid: mid)
            context.stroke(path, with: .color(GraphPalette.color(edge.colorIndex)), lineWidth: 1.7)
        }

        // Node dot, drawn on top of the lines.
        let center = CGPoint(x: x(node.column), y: mid)
        let r = Self.dotRadius
        let dot = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        context.fill(dot, with: .color(GraphPalette.color(node.colorIndex)))
        context.stroke(dot, with: .color(Color(nsColor: .textBackgroundColor)), lineWidth: 1.2)
    }

    private func edgePath(_ edge: GraphEdge, height: CGFloat, mid: CGFloat) -> Path {
        var path = Path()
        let x1 = x(edge.fromColumn)
        let x2 = x(edge.toColumn)

        switch edge.half {
        case .top:
            if x1 == x2 {
                path.move(to: CGPoint(x: x1, y: 0))
                path.addLine(to: CGPoint(x: x1, y: mid))
            } else {
                path.move(to: CGPoint(x: x1, y: 0))
                path.addCurve(
                    to: CGPoint(x: x2, y: mid),
                    control1: CGPoint(x: x1, y: mid * 0.6),
                    control2: CGPoint(x: x2, y: mid * 0.4)
                )
            }
        case .bottom:
            if x1 == x2 {
                path.move(to: CGPoint(x: x1, y: mid))
                path.addLine(to: CGPoint(x: x1, y: height))
            } else {
                path.move(to: CGPoint(x: x1, y: mid))
                path.addCurve(
                    to: CGPoint(x: x2, y: height),
                    control1: CGPoint(x: x1, y: mid + (height - mid) * 0.4),
                    control2: CGPoint(x: x2, y: mid + (height - mid) * 0.6)
                )
            }
        }
        return path
    }
}

// MARK: - Ref chip

struct RefChip: View {
    let ref: Ref
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8))
            Text(ref.name).font(.system(size: 10, weight: isCurrent ? .bold : .medium))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(tint.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(isCurrent ? 0.9 : 0.45), lineWidth: isCurrent ? 1.1 : 0.7))
        .foregroundStyle(tint)
        .lineLimit(1)
        .fixedSize()
    }

    private var icon: String {
        switch ref.kind {
        case .tag: return "tag.fill"
        case .remoteBranch: return "cloud"
        default: return "arrow.triangle.branch"
        }
    }

    private var tint: Color {
        switch ref.kind {
        case .tag: return .orange
        case .remoteBranch: return .gray
        case .localBranch, .head: return .blue
        case .other: return .gray
        }
    }
}
