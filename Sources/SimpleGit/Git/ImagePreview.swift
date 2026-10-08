import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImagePreviewVersion {
    let thumbnail: CGImage?
    let width: Int
    let height: Int
    let error: String?

    static func unavailable(_ message: String) -> Self {
        Self(thumbnail: nil, width: 0, height: 0, error: message)
    }
}

struct FileImagePreview {
    let path: String
    let before: ImagePreviewVersion?
    let after: ImagePreviewVersion?

    static func supports(path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return UTType(filenameExtension: ext)?.conforms(to: .image) == true
    }
}

extension GitService {
    private static let maxImagePreviewBytes = 32 * 1024 * 1024

    func commitImagePreview(commit: Commit, file: ChangedFile) async -> FileImagePreview {
        let before: ImagePreviewVersion?
        if !file.status.hasPrefix("A"), let parent = commit.parents.first {
            before = await gitImage(revision: parent, file: file.oldPath ?? file.path)
        } else {
            before = nil
        }
        let after = file.status.hasPrefix("D")
            ? nil
            : await gitImage(revision: commit.hash, file: file.path)
                ?? .unavailable("无法读取该提交中的图片。")
        return FileImagePreview(path: file.path, before: before, after: after)
    }

    func workingImagePreview(file: WorkingFile) async -> FileImagePreview {
        let before: ImagePreviewVersion?
        if file.badge != "?", file.badge != "A",
           let head = try? await GitRunner(workingDirectory: path).run(["rev-parse", "--verify", "HEAD"]) {
            before = await gitImage(
                revision: head.trimmingCharacters(in: .whitespacesAndNewlines),
                file: file.oldPath ?? file.path
            )
        } else {
            before = nil
        }
        let after = file.badge == "D" ? nil : workingImage(file: file.path)
        return FileImagePreview(path: file.path, before: before, after: after)
    }

    private func gitImage(revision: String, file: String) async -> ImagePreviewVersion? {
        let runner = GitRunner(workingDirectory: path)
        // Resolve the exact blob first. Its immutable size can be checked before
        // reading, and filenames with spaces/colons remain a single argument.
        guard let object = try? await runner.run([
            "rev-parse", "--verify", "--end-of-options", "\(revision):\(file)"
        ]) else { return nil }
        let oid = object.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let sizeText = try await runner.run(["cat-file", "-s", oid])
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return .unavailable("无法读取图片大小。")
            }
            guard size <= Self.maxImagePreviewBytes else { return Self.imageTooLarge }
            return Self.decodeImage(try await runner.runData(["cat-file", "blob", oid]))
        } catch {
            return .unavailable("无法读取图片。")
        }
    }

    private func workingImage(file: String) -> ImagePreviewVersion {
        let url = URL(fileURLWithPath: path).appendingPathComponent(file)
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            // A bounded read also handles a file growing after the size check.
            let data = try handle.read(upToCount: Self.maxImagePreviewBytes + 1) ?? Data()
            guard data.count <= Self.maxImagePreviewBytes else { return Self.imageTooLarge }
            return Self.decodeImage(data)
        } catch {
            return .unavailable("无法读取工作区中的图片。")
        }
    }

    private static var imageTooLarge: ImagePreviewVersion {
        .unavailable("图片超过 32 MB，已跳过预览。")
    }

    private static func decodeImage(_ data: Data) -> ImagePreviewVersion {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int,
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else {
            return .unavailable("该图片格式暂无法预览，或文件已损坏。")
        }
        return ImagePreviewVersion(thumbnail: image, width: width, height: height, error: nil)
    }
}
