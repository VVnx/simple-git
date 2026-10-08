import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SimpleGit

final class ImagePreviewTests: XCTestCase {
    func testBinaryGitOutputPreservesPNGBytes() async throws {
        let repo = try ImageRepository()
        defer { repo.remove() }
        try await repo.initialize()
        let data = try repo.writeImage("图片 空格:测试.PNG", width: 64)
        let commit = try await repo.commit()
        let result = try await repo.runner.runData(["show", "\(commit.hash):图片 空格:测试.PNG"])
        XCTAssertEqual(result, data)
        XCTAssertTrue(FileImagePreview.supports(path: "图片 空格:测试.PNG"))
        XCTAssertFalse(FileImagePreview.supports(path: "README.md"))
    }

    func testHistoricalPreviewUsesCommitInsteadOfWorkingCopy() async throws {
        let repo = try ImageRepository()
        defer { repo.remove() }
        try await repo.initialize()
        try repo.writeImage("portrait.png", width: 64)
        let added = try await repo.commit()
        try repo.writeImage("portrait.png", width: 80)
        let modified = try await repo.commit()
        try repo.writeImage("portrait.png", width: 96)

        let addedFiles = try await repo.service.changedFiles(of: added)
        let addedPreview = await repo.service.commitImagePreview(commit: added, file: try XCTUnwrap(addedFiles.first))
        XCTAssertNil(addedPreview.before)
        XCTAssertEqual(addedPreview.after?.width, 64)

        let modifiedFiles = try await repo.service.changedFiles(of: modified)
        let preview = await repo.service.commitImagePreview(commit: modified, file: try XCTUnwrap(modifiedFiles.first))
        XCTAssertEqual(preview.before?.width, 64)
        XCTAssertEqual(preview.after?.width, 80)
        XCTAssertNotNil(preview.after?.thumbnail)
    }

    func testRenameAndDeletionPreviewTheirOriginalPaths() async throws {
        let repo = try ImageRepository()
        defer { repo.remove() }
        try await repo.initialize()
        try repo.writeImage("旧 图片.png", width: 64)
        _ = try await repo.commit()
        try await repo.runner.run(["mv", "旧 图片.png", "新 图片.png"])
        let renamed = try await repo.commit()
        let renamedFiles = try await repo.service.changedFiles(of: renamed)
        let file = try XCTUnwrap(renamedFiles.first)
        XCTAssertEqual(file.oldPath, "旧 图片.png")
        let renamedPreview = await repo.service.commitImagePreview(commit: renamed, file: file)
        XCTAssertEqual(renamedPreview.before?.width, 64)
        XCTAssertEqual(renamedPreview.after?.width, 64)

        try await repo.runner.run(["rm", "新 图片.png"])
        let deleted = try await repo.commit()
        let deletedFiles = try await repo.service.changedFiles(of: deleted)
        let deletedPreview = await repo.service.commitImagePreview(commit: deleted, file: try XCTUnwrap(deletedFiles.first))
        XCTAssertEqual(deletedPreview.before?.width, 64)
        XCTAssertNil(deletedPreview.after)
    }

    func testWorkingPreviewComparesHEADWithDiskAndShowsDeletedImage() async throws {
        let repo = try ImageRepository()
        defer { repo.remove() }
        try await repo.initialize()
        try repo.writeImage("portrait.png", width: 64)
        _ = try await repo.commit()
        try repo.writeImage("portrait.png", width: 96)
        let modifiedFiles = try await repo.service.workingFiles()
        let preview = await repo.service.workingImagePreview(file: try XCTUnwrap(modifiedFiles.first))
        XCTAssertEqual(preview.before?.width, 64)
        XCTAssertEqual(preview.after?.width, 96)

        try FileManager.default.removeItem(at: repo.root.appendingPathComponent("portrait.png"))
        let deletedFiles = try await repo.service.workingFiles()
        let deletedPreview = await repo.service.workingImagePreview(file: try XCTUnwrap(deletedFiles.first))
        XCTAssertEqual(deletedPreview.before?.width, 64)
        XCTAssertNil(deletedPreview.after)
    }

    func testUntrackedImageWorksInRepositoryWithoutHEAD() async throws {
        let repo = try ImageRepository()
        defer { repo.remove() }
        try await repo.initialize()
        try repo.writeImage("new.png", width: 48)
        let files = try await repo.service.workingFiles()
        let preview = await repo.service.workingImagePreview(file: try XCTUnwrap(files.first))
        XCTAssertNil(preview.before)
        XCTAssertEqual(preview.after?.width, 48)
    }

    func testLargeImagesAreDownsampledAndInvalidOrOversizedFilesHavePlaceholders() async throws {
        let repo = try ImageRepository()
        defer { repo.remove() }
        try await repo.initialize()
        try repo.writeImage("wide.png", width: 4096)
        let wide = await repo.service.workingImagePreview(file: WorkingFile(badge: "?", path: "wide.png", oldPath: nil))
        XCTAssertEqual(wide.after?.width, 4096)
        XCTAssertEqual(wide.after?.thumbnail?.width, 2048)

        let invalidURL = repo.root.appendingPathComponent("invalid.png")
        try Data("invalid image".utf8).write(to: invalidURL)
        let invalid = await repo.service.workingImagePreview(file: WorkingFile(badge: "?", path: "invalid.png", oldPath: nil))
        XCTAssertNil(invalid.after?.thumbnail)
        XCTAssertNotNil(invalid.after?.error)

        let handle = try FileHandle(forWritingTo: invalidURL)
        try handle.truncate(atOffset: 32 * 1024 * 1024 + 1)
        try handle.close()
        let oversized = await repo.service.workingImagePreview(file: WorkingFile(badge: "?", path: "invalid.png", oldPath: nil))
        XCTAssertNil(oversized.after?.thumbnail)
        XCTAssertTrue(oversized.after?.error?.contains("32 MB") == true)
    }

    @MainActor
    func testSelectingDeletedImageBeforeFileListLoadsKeepsPreviousVersion() async throws {
        let repo = try ImageRepository()
        defer { repo.remove() }
        try await repo.initialize()
        try repo.writeImage("portrait.png", width: 64)
        _ = try await repo.commit()
        try FileManager.default.removeItem(at: repo.root.appendingPathComponent("portrait.png"))

        let store = AppStore()
        store.repositories = [Repository(name: "test", path: repo.root.path)]
        store.selectedRepoID = repo.root.path
        store.selectUncommitted()
        store.selectFile("portrait.png")
        for _ in 0..<100 where store.isLoadingDiff {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(store.isLoadingDiff)
        XCTAssertEqual(store.fileImagePreview?.before?.width, 64)
        XCTAssertNil(store.fileImagePreview?.after)
        store.clearSelection()
    }

    @MainActor
    func testSwitchingToTextFileDoesNotPublishPreviousImage() async throws {
        let repo = try ImageRepository()
        defer { repo.remove() }
        try await repo.initialize()
        try repo.writeImage("portrait.png", width: 64)
        try Data("original\n".utf8).write(to: repo.root.appendingPathComponent("note.txt"))
        _ = try await repo.commit()
        try repo.writeImage("portrait.png", width: 96)
        try Data("changed\n".utf8).write(to: repo.root.appendingPathComponent("note.txt"))

        let store = AppStore()
        store.repositories = [Repository(name: "test", path: repo.root.path)]
        store.selectedRepoID = repo.root.path
        store.selectUncommitted()
        for _ in 0..<100 where store.isLoadingFiles {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(store.isLoadingFiles)
        store.selectFile("portrait.png")
        store.selectFile("note.txt")
        for _ in 0..<100 where store.isLoadingDiff {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        // The image takes more Git reads than the text; allow the superseded
        // request to finish as well, then inspect what the user would see.
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(store.isLoadingDiff)
        XCTAssertEqual(store.selectedFilePath, "note.txt")
        XCTAssertTrue(store.fileDiff.contains("+changed"))
        XCTAssertNil(store.fileImagePreview)
        store.clearSelection()
    }
}

private final class ImageRepository {
    let root: URL
    var runner: GitRunner { GitRunner(workingDirectory: root.path) }
    var service: GitService { GitService(path: root.path) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("simple-git-image-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func initialize() async throws {
        try await runner.run(["init", "-q"])
        try await runner.run(["config", "user.name", "Image Test"])
        try await runner.run(["config", "user.email", "test@example.invalid"])
    }

    func commit() async throws -> Commit {
        try await runner.run(["add", "--all"])
        try await runner.run(["-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "commit", "-qm", "图片测试"])
        let commits = try await service.log(limit: 1)
        return try XCTUnwrap(commits.first)
    }

    @discardableResult
    func writeImage(_ path: String, width: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: 12, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 12))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try (data as Data).write(to: root.appendingPathComponent(path))
        return data as Data
    }
}
