import SwiftUI
import AppKit

/// Brand glyphs for the external-app buttons, bundled as resources and flagged as
/// template images so they follow the control's foreground color (and dark mode),
/// exactly like the SF Symbols they replaced.
enum ToolGlyph {
    static let codex = template("codex")
    static let claude = template("claude")

    private static func template(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
}

// MARK: - Relative date formatting

enum RelativeDate {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        // A commit notably in the future (clock skew, advanced committer time)
        // would otherwise collapse to "刚刚"; show its actual date instead.
        if seconds < -60 { return dayFormatter.string(from: date) }
        if seconds < 60 { return "刚刚" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = Int(seconds / 3600)
        if hours < 24 { return "\(hours) 小时前" }
        let days = Int(seconds / 86400)
        if days < 30 { return "\(days) 天前" }
        let months = Int(seconds / (86400 * 30))
        if months < 12 { return "\(months) 个月前" }
        return "\(Int(seconds / (86400 * 365))) 年前"
    }

    /// Absolute timestamp for tooltips.
    static func absoluteString(from date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String = ""

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)
            if !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Success toast

struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.green.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

// MARK: - Status bar

struct StatusBarView: View {
    let status: RepoStatus?
    let busy: String?
    var onOpenCodex: (() -> Void)? = nil
    var onOpenClaude: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            if let status {
                Label(status.branch, systemImage: status.detached ? "scissors" : "arrow.triangle.branch")
                    .font(.callout.weight(.medium))

                if status.upstream != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up").font(.caption2)
                        Text("\(status.ahead)")
                        Image(systemName: "arrow.down").font(.caption2)
                        Text("\(status.behind)")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("—").foregroundStyle(.secondary)
            }

            Spacer()

            if let busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(busy).foregroundStyle(.secondary)
                }
            }

            if onOpenCodex != nil || onOpenClaude != nil {
                HStack(spacing: 8) {
                    if let onOpenCodex {
                        Button(action: onOpenCodex) {
                            Label {
                                Text("Codex")
                            } icon: {
                                glyph(ToolGlyph.codex, fallback: "chevron.left.forwardslash.chevron.right")
                            }
                        }
                    }
                    if let onOpenClaude {
                        Button(action: onOpenClaude) {
                            Label {
                                Text("Claude")
                            } icon: {
                                glyph(ToolGlyph.claude, fallback: "sparkles")
                            }
                        }
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.bar)
    }

    /// A bundled template glyph sized to sit next to the small button labels,
    /// falling back to an SF Symbol if the resource is missing.
    @ViewBuilder
    private func glyph(_ image: NSImage?, fallback: String) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: fallback)
        }
    }
}
