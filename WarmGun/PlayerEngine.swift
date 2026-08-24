import AVFoundation
import Foundation

/// The screen's player: an AVQueuePlayer holding exactly the clip on screen
/// and the one staged to follow it, the same two-entry window the desktop
/// satellite keeps in mpv. Both come from local files, so a swap is a swap.
///
/// It reports three things up, each named by the FILE it concerns, because the
/// queue is not the session: the clip that rolled on (so the model can check
/// the roll matches what it staged), the fraction played, and a clip that
/// failed to play at all. It decides nothing about what plays next.
@MainActor
final class PlayerEngine {
    let player = AVQueuePlayer()

    /// Called when the queue rolled from one clip onto the next by itself,
    /// with the URL it rolled onto — the model advances only when that is the
    /// clip it staged, so a stale roll can never move the session.
    var onAdvanced: ((URL) -> Void)?
    /// Called with the fraction played, a few times a second.
    var onProgress: ((Double) -> Void)?
    /// Called when the clip played out with nothing staged behind it and no
    /// loop holding it — the session's cue to move on.
    var onFinished: (() -> Void)?
    /// Called when a clip cannot be played at all — a truncated download, a
    /// container AVFoundation refuses. Without this an unplayable file would
    /// freeze the endless run silently and forever.
    var onItemFailed: ((URL) -> Void)?

    private(set) var currentURL: URL?
    private var stagedURL: URL?
    private var loop = false
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var statusObservations: [NSKeyValueObservation] = []

    init() {
        // Ambient, mixed: this player is muted video — it must never barge in
        // on whatever the phone is already playing (the default solo-ambient
        // session pauses other audio the moment playback starts).
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
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
        failObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard let self, let item = note.object as? AVPlayerItem else { return }
            self.itemFailed(item)
        }
        itemObservation = player.observe(\.currentItem, options: [.old, .new]) { [weak self] _, change in
            guard let self, let old = change.oldValue ?? nil, let new = change.newValue ?? nil, old !== new else { return }
            Task { @MainActor in self.queueAdvanced(to: new) }
        }
    }

    /// Shows `current`, with `next` ready behind it. Re-showing the clip already
    /// on screen only refreshes what is staged — it never restarts the picture.
    func show(current: URL, next: URL?, loop: Bool, autoplay: Bool = true) {
        self.loop = loop
        if currentURL != current {
            player.removeAllItems()
            statusObservations.removeAll()
            insert(url: current)
            currentURL = current
            stagedURL = nil
        }
        stage(next)
        if autoplay { player.play() }
    }

    func pause() {
        player.pause()
    }

    /// The session has moved somewhere the cache cannot serve yet: keep the
    /// last picture looping under the spinner, but empty the queue behind it so
    /// nothing stale can roll on and nothing half-relevant is reported up.
    func holdCurrent() {
        stage(nil)
    }

    /// The scene came back to the foreground; AVPlayer does not resume itself.
    func resume() {
        player.play()
    }

    func setLoop(_ loop: Bool) {
        self.loop = loop
        if loop { stage(nil) }
    }

    func clear() {
        player.removeAllItems()
        statusObservations.removeAll()
        currentURL = nil
        stagedURL = nil
    }

    private func insert(url: URL) {
        let item = AVPlayerItem(url: url)
        // An item that fails to LOAD emits no end-of-play notification at all;
        // its status flipping to .failed is the only word it ever says.
        statusObservations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.itemFailed(item) }
        })
        player.insert(item, after: player.items().last)
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
        if let wanted, player.items().last != nil {
            insert(url: wanted)
        }
    }

    /// Looping, or nothing staged yet: replay rather than let the queue empty.
    /// A late notification for an item the queue already advanced past seeks a
    /// detached item, which is harmless.
    private func itemEnded(_ item: AVPlayerItem) {
        guard loop || stagedURL == nil else { return }
        if !loop { onFinished?() }
        item.seek(to: .zero, completionHandler: nil)
        player.play()
    }

    private func itemFailed(_ item: AVPlayerItem) {
        guard let asset = item.asset as? AVURLAsset else { return }
        onItemFailed?(asset.url)
    }

    private func queueAdvanced(to item: AVPlayerItem) {
        guard let asset = item.asset as? AVURLAsset, asset.url == stagedURL else { return }
        currentURL = stagedURL
        stagedURL = nil
        onAdvanced?(asset.url)
    }
}
