import Foundation
import CoreServices

/// Watches a repository's `.git` directory with FSEvents and fires `onChange`
/// (coalesced) whenever git state changes on disk — a commit, stage, branch
/// switch, fetch or merge from any tool, including an external agent — so the UI
/// can refresh without the user pressing ⌘R.
///
/// The app's own reads run with `GIT_OPTIONAL_LOCKS=0` (see GitRunner), so they
/// never write `.git` and can't feed back into the watcher as a refresh loop.
final class RepoWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init(path: String, onChange: @escaping () -> Void) {
        self.onChange = onChange
        start(watching: (path as NSString).appendingPathComponent(".git"))
    }

    deinit { stop() }

    private func start(watching gitDir: String) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        // C callback: pull `self` back out of the context's `info` pointer.
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<RepoWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [gitDir] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.4,  // latency: coalesce the burst of writes a single commit produces
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    private func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
