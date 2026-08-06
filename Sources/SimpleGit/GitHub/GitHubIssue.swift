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

struct GitHubIssueCounts {
    let todo: Int
    let inProgress: Int
}

struct RepoIssueSidebarStatus {
    var todoCount: Int
    var inProgressCount: Int
    var isLoading: Bool = false
    var errorMessage: String?

    init(
        todoCount: Int,
        inProgressCount: Int,
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) {
        self.todoCount = todoCount
        self.inProgressCount = inProgressCount
        self.isLoading = isLoading
        self.errorMessage = errorMessage
    }

    init(counts: GitHubIssueCounts) {
        todoCount = counts.todo
        inProgressCount = counts.inProgress
    }

    static func loading(from previous: RepoIssueSidebarStatus?) -> RepoIssueSidebarStatus {
        RepoIssueSidebarStatus(
            todoCount: previous?.todoCount ?? 0,
            inProgressCount: previous?.inProgressCount ?? 0,
            isLoading: true
        )
    }

    static func failed(_ message: String, previous: RepoIssueSidebarStatus?) -> RepoIssueSidebarStatus {
        RepoIssueSidebarStatus(
            todoCount: previous?.todoCount ?? 0,
            inProgressCount: previous?.inProgressCount ?? 0,
            errorMessage: message
        )
    }
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
