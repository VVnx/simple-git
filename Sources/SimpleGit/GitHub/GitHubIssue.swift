import Foundation

enum GitHubIssueState: String, Hashable {
    case open = "OPEN"
    case closed = "CLOSED"
}

enum IssueBoardStatus: String, CaseIterable, Identifiable {
    case todo
    case inProgress
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: return "待处理"
        case .inProgress: return "进行中"
        case .done: return "已完成"
        }
    }

    var systemImage: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }
}

struct GitHubIssueLabel: Hashable {
    let name: String
    let color: String
}

struct GitHubIssue: Identifiable, Hashable {
    let number: Int
    let title: String
    let state: GitHubIssueState
    let labels: [GitHubIssueLabel]
    let assignees: [String]
    let updatedAt: Date
    let url: URL

    var id: Int { number }

    var boardStatus: IssueBoardStatus {
        guard state == .open else { return .done }

        let progressLabels = labels.map { label in
            label.name
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let isInProgress = progressLabels.contains { label in
            label == "doing"
                || label == "wip"
                || label == "in progress"
                || label == "进行中"
                || label == "处理中"
                || label.contains("status:in progress")
                || label.contains("status: in progress")
        }
        return isInProgress ? .inProgress : .todo
    }
}
