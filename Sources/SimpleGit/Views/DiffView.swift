import SwiftUI
import AppKit

/// Right-hand pane of a detail panel: shows the selected file's unified diff.
struct FileDiffPane: View {
    let diff: String
    let isLoading: Bool
    let hasSelection: Bool

    var body: some View {
        Group {
            if !hasSelection {
                placeholder("选择左侧文件查看变更内容")
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diff.isEmpty {
                placeholder("(无文本差异,可能是二进制文件)")
            } else {
                DiffView(text: diff)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Caps applied before the diff is colored and handed to the text view, so a
/// multi-megabyte file (e.g. a vendored source blob) can never stall the UI.
private enum DiffLimits {
    static let maxLines = 4000        // rows of diff actually rendered
    static let maxLineLength = 5000   // chars per line (guards minified one-liners)
}

/// Renders a unified diff with +/- line coloring.
///
/// Backed by an `NSTextView` rather than a SwiftUI `LazyVStack`: TextKit lays the
/// text out lazily, so even a huge diff scrolls smoothly, and the user gets free
/// text selection / copy. A pure-SwiftUI list inside a two-axis `ScrollView`
/// would materialize every row up front (the horizontal axis defeats laziness)
/// and beach-ball on large files.
struct DiffView: View {
    let text: String

    var body: some View {
        DiffTextView(text: text)
    }
}

private struct DiffTextView: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)

        // Don't wrap — let long lines run wide and scroll horizontally instead.
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        let big = CGFloat.greatestFiniteMagnitude
        textView.maxSize = NSSize(width: big, height: big)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: big, height: big)

        context.coordinator.textView = textView
        context.coordinator.apply(text: text)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.apply(text: text)
    }

    final class Coordinator {
        weak var textView: NSTextView?
        private var lastText: String?

        func apply(text: String) {
            guard text != lastText, let textView else { return }
            lastText = text
            textView.textStorage?.setAttributedString(DiffTextView.attributed(from: text))
            // Reset to the top-left when a new file's diff is shown.
            if let clip = textView.enclosingScrollView?.contentView {
                clip.scroll(to: .zero)
                textView.enclosingScrollView?.reflectScrolledClipView(clip)
            }
        }
    }

    /// Builds the colored attributed string, capping both the number of lines and
    /// the length of any single line so the cost is always bounded.
    static func attributed(from text: String) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        let result = NSMutableAttributedString()

        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let total = lines.count
        let truncated = lines.count > DiffLimits.maxLines
        if truncated { lines = Array(lines.prefix(DiffLimits.maxLines)) }

        for (i, raw) in lines.enumerated() {
            // `dropFirst(n).isEmpty` is O(n)-bounded, unlike `.count` on a huge line.
            let tooLong = !raw.dropFirst(DiffLimits.maxLineLength).isEmpty
            let body = tooLong ? String(raw.prefix(DiffLimits.maxLineLength)) + " …(本行过长,已截断)"
                               : String(raw)
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground(for: raw)]
            if let bg = background(for: raw) { attrs[.backgroundColor] = bg }
            result.append(NSAttributedString(string: body, attributes: attrs))
            if i < lines.count - 1 { result.append(NSAttributedString(string: "\n")) }
        }

        if truncated {
            let note = "\n\n… 差异过大,仅显示前 \(DiffLimits.maxLines) 行(共约 \(total) 行)。\n如需完整内容,请用编辑器打开该文件。"
            result.append(NSAttributedString(string: note, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .bold),
                .foregroundColor: NSColor.systemOrange,
            ]))
        }
        return result
    }

    private static func foreground(for line: Substring) -> NSColor {
        if line.hasPrefix("@@") { return .systemPurple }
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
            return .secondaryLabelColor
        }
        if line.hasPrefix("+") { return .systemGreen }
        if line.hasPrefix("-") { return .systemRed }
        return .labelColor
    }

    private static func background(for line: Substring) -> NSColor? {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return nil }
        if line.hasPrefix("+") { return NSColor.systemGreen.withAlphaComponent(0.12) }
        if line.hasPrefix("-") { return NSColor.systemRed.withAlphaComponent(0.12) }
        return nil
    }
}
