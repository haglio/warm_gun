import AVFoundation
import Foundation

/// The screen's player: an AVQueuePlayer holding exactly the clip on screen
/// and the one staged to follow it, the same two-entry window the desktop
/// satellite keeps in mpv. Both come from local files, so a swap is a swap.
///
/// It reports two things up: the clip that just reached its end (for the watch
/// tracker, and for looping) and the fraction played (sampled, for the same
/// tracker). It decides nothing about what plays next.
@MainActor
final class PlayerEngine {
    let player = AVQueuePlayer()

    /// Called when the queue rolled from one clip onto the next by itself.
    var onAdvanced: (() -> Void)?
    /// Called with the fraction played, a few times a second.
    var onProgress: ((Double) -> Void)?

    private(set) var currentURL: URL?
    private var stagedURL: URL?
    private var loop = false
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .advance
        player.isMuted = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self, let item = self.player.currentItem else { return }
            let duration = item.duration.seconds
            guard duration.isFinite, duration > 0 else { return }
            self.onProgress?(time.seconds / duration)
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard let self, let item = note.object as? AVPlayerItem else { return }
            self.itemEnded(item)
        }
        itemObservation = player.observe(\.currentItem, options: [.old, .new]) { [weak self] _, change in
            guard let self, let old = change.oldValue ?? nil, let new = change.newValue ?? nil, old !== new else { return }
            Task { @MainActor in self.queueAdvanced(to: new) }
        }
    }

    /// Shows `current`, with `next` ready behind it. Re-showing the clip already
    /// on screen only refreshes what is staged — it never restarts the picture.
    func show(current: URL, next: URL?, loop: Bool) {
        self.loop = loop
        if currentURL != current {
            player.removeAllItems()
            player.insert(AVPlayerItem(url: current), after: nil)
            currentURL = current
            stagedURL = nil
        }
        stage(next)
        player.play()
    }

    func setLoop(_ loop: Bool) {
        self.loop = loop
        if loop { stage(nil) }
    }

    func clear() {
        player.removeAllItems()
        currentURL = nil
        stagedURL = nil
    }

    private func stage(_ next: URL?) {
        let wanted = loop ? nil : next
        // With nothing staged the queue must not advance off its only item into
        // an empty (black) queue; it holds the last frame until the end handler
        // replays it.
        player.actionAtItemEnd = wanted == nil ? .none : .advance
        guard stagedURL != wanted else { return }
        for item in player.items().dropFirst() { player.remove(item) }
        stagedURL = wanted
        if let wanted, let last = player.items().last {
            player.insert(AVPlayerItem(url: wanted), after: last)
        }
    }

    /// Looping, or nothing staged yet: replay rather than let the queue empty.
    /// A late notification for an item the queue already advanced past seeks a
    /// detached item, which is harmless.
    private func itemEnded(_ item: AVPlayerItem) {
        guard loop || stagedURL == nil else { return }
        item.seek(to: .zero, completionHandler: nil)
        player.play()
    }

    private func queueAdvanced(to item: AVPlayerItem) {
        guard let asset = item.asset as? AVURLAsset, asset.url == stagedURL else { return }
        currentURL = stagedURL
        stagedURL = nil
        onAdvanced?()
    }
}
