import AppKit
import SwiftUI

@MainActor
final class IssueBoardModel: ObservableObject {
    @Published private(set) var issues: [GitHubIssue] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isCreating = false
    @Published var loadError: String?
    @Published var actionError: String?
    @Published var successMessage: String?

    private var activeRepositoryPath: String?
    private var loadedRepositoryPath: String?
    private var successClearTask: Task<Void, Never>?

    func issues(for status: IssueBoardStatus) -> [GitHubIssue] {
        issues.filter { $0.boardStatus == status }
    }

    func loadIfNeeded(repository: Repository) async {
        guard loadedRepositoryPath != repository.path else { return }
        await load(repository: repository)
    }

    @discardableResult
    func load(repository: Repository) async -> Bool {
        let path = repository.path
        if activeRepositoryPath != path {
            issues = []
            loadedRepositoryPath = nil
        }
        activeRepositoryPath = path
        isLoading = true
        loadError = nil

        do {
            let loaded = try await GitHubIssueService(repositoryPath: path).listIssues()
            guard !Task.isCancelled, activeRepositoryPath == path else { return false }
            issues = loaded
            loadedRepositoryPath = path
            isLoading = false
            return true
        } catch {
            guard !Task.isCancelled, activeRepositoryPath == path else { return false }
            loadError = GitHubIssueService.friendlyMessage(error)
            isLoading = false
            return false
        }
    }

    func createIssue(repository: Repository, title: String, body: String) async -> Bool {
        guard !isCreating else { return false }
        isCreating = true
        actionError = nil

        do {
            let url = try await GitHubIssueService(repositoryPath: repository.path)
                .createIssue(title: title, body: body)
            isCreating = false
            flashSuccess("已创建 Issue #\(url.lastPathComponent)")
            return true
        } catch {
            isCreating = false
            actionError = GitHubIssueService.friendlyMessage(error)
            return false
        }
    }

    private func flashSuccess(_ text: String) {
        successClearTask?.cancel()
        successMessage = text
        successClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.successMessage = nil
        }
    }
}

struct IssueBoardView: View {
    let repository: Repository
    @ObservedObject var model: IssueBoardModel
    @Binding var showingNewIssue: Bool

    var body: some View {
        boardContent
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task(id: repository.id) {
            await model.loadIfNeeded(repository: repository)
        }
        .sheet(isPresented: $showingNewIssue) {
            NewIssueSheet(
                isCreating: model.isCreating,
                onCancel: { showingNewIssue = false },
                onCreate: { title, body in
                    Task {
                        if await model.createIssue(repository: repository, title: title, body: body) {
                            showingNewIssue = false
                            await model.load(repository: repository)
                        }
                    }
                }
            )
        }
        .alert(
            "无法创建 Issue",
            isPresented: Binding(
                get: { model.actionError != nil },
                set: { if !$0 { model.actionError = nil } }
            )
        ) {
            Button("好") { model.actionError = nil }
        } message: {
            Text(model.actionError ?? "")
        }
    }

    @ViewBuilder
    private var boardContent: some View {
        if model.isLoading && model.issues.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在读取 GitHub Issues…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.loadError, model.issues.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.orange)
                Text("暂时无法加载 Issue")
                    .font(.title3.weight(.semibold))
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                Button("重试") {
                    Task { await model.load(repository: repository) }
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geometry in
                let spacing: CGFloat = 12
                let columnWidth = max(230, (geometry.size.width - spacing * 2 - 32) / 3)

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(IssueBoardStatus.allCases) { status in
                            IssueBoardColumn(
                                status: status,
                                issues: model.issues(for: status)
                            )
                            .frame(width: columnWidth)
                        }
                    }
                    .padding(16)
                    .frame(minWidth: geometry.size.width, alignment: .leading)
                }
            }
        }
    }
}

private struct IssueBoardColumn: View {
    let status: IssueBoardStatus
    let issues: [GitHubIssue]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status.tint)
                Text(status.title)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(issues.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 12)
            .frame(height: 42)

            Divider()

            if issues.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: status.emptySystemImage)
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(status.emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(issues) { issue in
                            IssueCard(issue: issue, tint: status.tint)
                        }
                    }
                    .padding(9)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(status.tint.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct IssueCard: View {
    let issue: GitHubIssue
    let tint: Color
    @State private var linkCopied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Link(destination: issue.url) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("#\(issue.number)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(tint)
                        Spacer()
                        Text(RelativeDate.string(from: issue.updatedAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.trailing, 27)
                    }

                    Text(issue.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !issue.labels.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(Array(issue.labels.prefix(2)), id: \.self) { label in
                                Text(label.name)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(label.tint.opacity(0.16), in: Capsule())
                                    .foregroundStyle(label.tint)
                            }
                            if issue.labels.count > 2 {
                                Text("+\(issue.labels.count - 2)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !issue.assignees.isEmpty {
                        Label(issue.assignees.joined(separator: ", "), systemImage: "person.crop.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(11)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("在 GitHub 打开 Issue #\(issue.number)")

            Button(action: copyLink) {
                Image(systemName: linkCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(linkCopied ? Color.green : Color.secondary)
                    .frame(width: 22, height: 22)
                    .background(.regularMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 7)
            .padding(.trailing, 7)
            .help(linkCopied ? "链接已复制" : "复制 Issue 链接")
            .accessibilityLabel(linkCopied ? "链接已复制" : "复制 Issue 链接")
        }
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(issue.url.absoluteString, forType: .string)
        linkCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            linkCopied = false
        }
    }
}

private struct NewIssueSheet: View {
    let isCreating: Bool
    let onCancel: () -> Void
    let onCreate: (String, String) -> Void

    @State private var title = ""
    @State private var bodyText = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("新建 GitHub Issue")
                        .font(.headline)
                    Text("创建后会出现在“待处理”列")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("标题")
                    .font(.callout.weight(.medium))
                TextField("简要描述要完成的任务", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFocused)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("说明")
                    .font(.callout.weight(.medium))
                TextEditor(text: $bodyText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if bodyText.isEmpty {
                            Text("补充背景、验收标准或实现提示(可选)")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                    }
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCreating)
                Button {
                    onCreate(title, bodyText)
                } label: {
                    if isCreating {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("创建中…")
                        }
                    } else {
                        Text("创建 Issue")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            }
        }
        .padding(22)
        .frame(width: 540, height: 390)
        .interactiveDismissDisabled(isCreating)
        .task { titleFocused = true }
    }
}

private extension IssueBoardStatus {
    var tint: Color {
        switch self {
        case .todo: return .orange
        case .inProgress: return .blue
        case .done: return .green
        }
    }

    var emptySystemImage: String {
        switch self {
        case .todo: return "tray"
        case .inProgress: return "hammer"
        case .done: return "checkmark"
        }
    }

    var emptyMessage: String {
        switch self {
        case .todo: return "没有待处理 Issue"
        case .inProgress: return "添加 in-progress 标签后显示在这里"
        case .done: return "关闭的 Issue 会显示在这里"
        }
    }
}

private extension GitHubIssueLabel {
    var tint: Color {
        guard color.count == 6, let value = UInt64(color, radix: 16) else { return .secondary }
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}
