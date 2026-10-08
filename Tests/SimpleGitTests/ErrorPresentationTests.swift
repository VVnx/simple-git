import XCTest
@testable import SimpleGit

final class ErrorPresentationTests: XCTestCase {
    private var progress: String {
        "Enumerating objects: 37, done.\n"
            + (1...100).map { "Counting objects: \($0)% (\($0)/100)\r" }.joined()
            + "\nDelta compression using up to 8 threads\n"
            + "remote: Compressing objects: 100% (22/22), done.\r\n"
    }

    func testActualPushDisconnectHasShortSummaryAndCompleteLog() async {
        let raw = progress + """
        Writing objects: 50% (12/24)\rTimeout, server github.com not responding.
        send-pack: unexpected disconnect while reading sideband packet
        fatal: the remote end hung up unexpectedly
        """
        let error = GitError(command: "git push", exitCode: 128, message: raw)
        let summary = await AppStore.friendlyGitMessage(error)
        let presentation = ErrorPresentation(title: "Push 失败", message: summary, details: raw)
        XCTAssertEqual(presentation.summary, "与远程仓库的连接超时或中断。请检查网络连接，稍后重试。")
        XCTAssertEqual(presentation.details, raw)
    }

    func testUnknownRemoteErrorIsNotBuriedByProgressOrGenericPushFailure() {
        let raw = progress + """
        remote: error: custom server policy refused this commit
        error: failed to push some refs to 'example'
        hint: See the remote's policy.
        """
        let presentation = ErrorPresentation(message: raw)
        XCTAssertEqual(presentation.summary, "remote: error: custom server policy refused this commit")
        XCTAssertEqual(presentation.details, raw)
    }

    func testLongUnknownOutputAndSingleLinesStayBoundedWithoutLosingDetails() {
        for raw in [String(repeating: "很长的错误", count: 1_000),
                    (1...1_000).map { "server message \($0)" }.joined(separator: "\r\n")] {
            let presentation = ErrorPresentation(message: raw)
            XCTAssertLessThanOrEqual(presentation.summary.count, 300)
            XCTAssertLessThanOrEqual(presentation.summary.components(separatedBy: "\n").count, 3)
            XCTAssertEqual(presentation.details, raw)
        }
    }

    func testProgressOnlyDoesNotMasqueradeAsAnErrorReason() {
        let presentation = ErrorPresentation(message: progress)
        XCTAssertTrue(presentation.summary.contains("没有明确的失败原因"))
        XCTAssertFalse(presentation.summary.contains("Counting objects"))
        XCTAssertEqual(presentation.details, progress)
    }

    func testANSIColorsAndCarriageReturnsDoNotHideFatalError() {
        let raw = progress + "\u{001B}[31mfatal: server unavailable\u{001B}[0m\r\n"
        XCTAssertEqual(ErrorMessageFormatter.summary(raw), "fatal: server unavailable")
    }

    func testShortUserFacingMessageNeedsNoDetails() {
        let message = "当前仓库没有配置远程仓库,无法 push。"
        let presentation = ErrorPresentation(message: message)
        XCTAssertEqual(presentation.summary, message)
        XCTAssertNil(presentation.details)
    }

    func testExistingAuthenticationAndNonFastForwardMessagesRemainActionable() async {
        let auth = GitError(command: "git push", exitCode: 128, message: "Permission denied (publickey).")
        let rejected = GitError(command: "git push", exitCode: 1, message: "! [rejected] main -> main (fetch first)")
        let authMessage = await AppStore.friendlyGitMessage(auth)
        let rejectedMessage = await AppStore.friendlyGitMessage(rejected)
        XCTAssertTrue(authMessage.contains("认证失败"))
        XCTAssertTrue(rejectedMessage.contains("远端有你本地还没有的提交"))
    }
}
