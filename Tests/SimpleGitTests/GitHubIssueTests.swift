import XCTest
@testable import SimpleGit

final class GitHubIssueTests: XCTestCase {
    func testRESTPageReadsTypeAndKeepsPullRequestsOutOfTheBoard() throws {
        let page = try GitHubIssueService.decodeIssuePage(fixture)

        XCTAssertEqual(page.itemCount, 4)
        XCTAssertEqual(page.issues.map(\.number), [1, 2, 3])
        let issue = try XCTUnwrap(page.issues.first)
        XCTAssertEqual(issue.type, GitHubIssueType(name: "Feature", color: "blue"))
        XCTAssertEqual(issue.labels.map(\.name), ["bug"])
        XCTAssertEqual(issue.boardStatus, .done)
        XCTAssertEqual(issue.author, "alice")
        XCTAssertEqual(issue.assignees, ["bob"])
        XCTAssertEqual(issue.url.absoluteString, "https://github.com/example/repo/issues/1")
        XCTAssertEqual(issue.createdAt, ISO8601DateFormatter().date(from: "2026-10-20T01:00:00Z"))
        XCTAssertEqual(issue.updatedAt, ISO8601DateFormatter().date(from: "2026-11-10T01:00:00Z"))
        XCTAssertNil(page.issues[2].type)
    }

    func testFiltersUseTypeEvenWhenLabelsDisagreeOrTypeIsMissing() throws {
        let issues = try GitHubIssueService.decodeIssuePage(fixture).issues

        XCTAssertEqual(issues.filter(IssueBoardTypeFilter.all.matches).map(\.number), [1, 2, 3])
        XCTAssertEqual(issues.filter(IssueBoardTypeFilter.feature.matches).map(\.number), [1])
        XCTAssertEqual(issues.filter(IssueBoardTypeFilter.bug.matches).map(\.number), [2])
    }

    private var fixture: Data {
        Data("""
        [
          {
            "number": 1, "title": "功能需求", "state": "closed",
            "type": { "name": "Feature", "color": "blue" },
            "user": { "login": "alice" },
            "labels": [{ "name": "bug", "color": "ff0000" }],
            "assignees": [{ "login": "bob" }],
            "created_at": "2026-10-20T01:00:00Z",
            "updated_at": "2026-11-10T01:00:00Z",
            "html_url": "https://github.com/example/repo/issues/1"
          },
          {
            "number": 2, "title": "修复问题", "state": "open",
            "type": { "name": "BUG", "color": "red" },
            "user": null,
            "labels": [{ "name": "feature", "color": "0000ff" }],
            "assignees": [], "created_at": "2026-10-20T01:00:00Z",
            "updated_at": "2026-11-10T01:00:00Z",
            "html_url": "https://github.com/example/repo/issues/2"
          },
          {
            "number": 3, "title": "未设置类型", "state": "open",
            "type": null, "user": null,
            "labels": [{ "name": "bug", "color": "ff0000" }],
            "assignees": [], "created_at": "2026-10-20T01:00:00Z",
            "updated_at": "2026-11-10T01:00:00Z",
            "html_url": "https://github.com/example/repo/issues/3"
          },
          {
            "number": 4, "title": "这是 PR", "state": "open",
            "type": null, "user": null, "labels": [], "assignees": [],
            "created_at": "2026-10-20T01:00:00Z",
            "updated_at": "2026-11-10T01:00:00Z",
            "html_url": "https://github.com/example/repo/pull/4",
            "pull_request": { "url": "https://api.github.com/repos/example/repo/pulls/4" }
          }
        ]
        """.utf8)
    }
}
