import AppKit
import SwiftUI

struct ErrorSheet: View {
    let error: ErrorPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var showsDetails = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(error.title)
                    .font(.headline)
            }

            ScrollView {
                Text(error.summary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 100)

            if let details = error.details {
                DisclosureGroup("错误详情", isExpanded: $showsDetails) {
                    ScrollView([.horizontal, .vertical]) {
                        Text(details)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(10)
                    }
                    .frame(height: 220)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 8)
                }
            }

            Divider()
            HStack {
                Button(copied ? "已复制" : "复制错误信息") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        "\(error.title)\n\n\(error.summary)" + (error.details.map { "\n\n\($0)" } ?? ""),
                        forType: .string
                    )
                    copied = true
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 580)
        .onExitCommand { dismiss() }
    }
}
