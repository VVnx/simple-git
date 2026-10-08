import SwiftUI

/// Image versions occupy the same bottom detail pane as a text file's diff.
struct ImagePreviewPane: View {
    let preview: FileImagePreview

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("图片预览", systemImage: "photo")
                    .font(.caption.weight(.semibold))
                Text((preview.path as NSString).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(preview.path)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            HStack(spacing: 0) {
                if let before = preview.before {
                    version(before, title: "修改前")
                }
                if preview.before != nil, preview.after != nil { Divider() }
                if let after = preview.after {
                    version(after, title: "修改后")
                }
                if preview.before == nil, preview.after == nil {
                    Text("此版本中没有可预览的图片")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func version(_ version: ImagePreviewVersion, title: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                Spacer(minLength: 0)
                if version.thumbnail != nil {
                    Text("\(version.width) × \(version.height) 像素")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            GeometryReader { geometry in
                if let image = version.thumbnail {
                    Image(image, scale: 1, label: Text("\(title)图片"))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(8)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Text(version.error ?? "无法预览图片")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .background(TransparencyBackground())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TransparencyBackground: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 12
            for row in 0..<Int(ceil(size.height / tile)) {
                for column in 0..<Int(ceil(size.width / tile)) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                    context.fill(Path(rect), with: .color(.secondary.opacity(0.08)))
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityHidden(true)
    }
}
