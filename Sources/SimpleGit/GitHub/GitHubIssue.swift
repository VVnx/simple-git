import Foundation

enum GitHubIssueState: String, Hashable {
    case open = "OPEN"
    case closed = "CLOSED"
}

enum IssueBoardStatus: String, CaseIterable, Identifiable {
    case todo
    case inProgress
    case review
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: return "待处理"
        case .inProgress: return "开发中"
        case .review: return "开发完成待 Review"
        case .done: return "已完成"
        }
    }

    var systemImage: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .review: return "eye.circle.fill"
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
    let review: Int
}

struct RepoIssueSidebarStatus {
    var todoCount: Int
    var inProgressCount: Int
    var reviewCount: Int
    var isLoading: Bool = false
    var errorMessage: String?

    init(
        todoCount: Int,
        inProgressCount: Int,
        reviewCount: Int,
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) {
        self.todoCount = todoCount
        self.inProgressCount = inProgressCount
        self.reviewCount = reviewCount
        self.isLoading = isLoading
        self.errorMessage = errorMessage
    }

    init(counts: GitHubIssueCounts) {
        todoCount = counts.todo
        inProgressCount = counts.inProgress
        reviewCount = counts.review
    }

    static func loading(from previous: RepoIssueSidebarStatus?) -> RepoIssueSidebarStatus {
        RepoIssueSidebarStatus(
            todoCount: previous?.todoCount ?? 0,
            inProgressCount: previous?.inProgressCount ?? 0,
            reviewCount: previous?.reviewCount ?? 0,
            isLoading: true
        )
    }

    static func failed(_ message: String, previous: RepoIssueSidebarStatus?) -> RepoIssueSidebarStatus {
        RepoIssueSidebarStatus(
            todoCount: previous?.todoCount ?? 0,
            inProgressCount: previous?.inProgressCount ?? 0,
            reviewCount: previous?.reviewCount ?? 0,
            errorMessage: message
        )
    }
}

struct GitHubIssue: Identifiable, Hashable {
    let number: Int
    let title: String
    let state: GitHubIssueState
    let author: String?
    let labels: [GitHubIssueLabel]
    let assignees: [String]
    let updatedAt: Date
    let url: URL

    var id: Int { number }

    /// 提交人用户名(由 GitHub 登录名解析),用于“只看我的”过滤与卡片展示。
    var authorLogin: String? { author }

    var boardStatus: IssueBoardStatus {
        guard state == .open else { return .done }

        let statuses = labels.compactMap { Self.workflowStatus(forLabel: $0.name) }
        if statuses.contains(.review) { return .review }
        if statuses.contains(.inProgress) { return .inProgress }
        return .todo
    }

    var workflowLabelNames: [String] {
        labels.compactMap { label in
            Self.workflowStatus(forLabel: label.name) == nil ? nil : label.name
        }
    }

    static func workflowStatus(forLabel name: String) -> IssueBoardStatus? {
        let label = name
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let isReadyForReview = label == "review"
            || label == "needs review"
            || label == "ready for review"
            || label == "awaiting review"
            || label == "pending review"
            || label == "code review"
            || label == "待 review"
            || label == "待评审"
            || label == "待审核"
            || label == "开发完成"
            || label.contains("status:review")
            || label.contains("status: review")
            || label.contains("status:ready for review")
            || label.contains("status: ready for review")
        if isReadyForReview { return .review }

        let isInProgress = label == "doing"
            || label == "wip"
            || label == "in progress"
            || label == "进行中"
            || label == "处理中"
            || label.contains("status:in progress")
            || label.contains("status: in progress")
        if isInProgress { return .inProgress }

        return nil
    }
}
