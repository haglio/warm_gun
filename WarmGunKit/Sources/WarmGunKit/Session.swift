import Foundation

/// Where the satellite is in its run: a list and an index, exactly as the
/// desktop keeps it (`satellite/session.py`).
public struct Session: Equatable, Sendable {
    public private(set) var playlist: [String]
    public private(set) var index: Int
    public private(set) var locked: Bool

    /// The index is wrapped into range rather than trusted: it arrives from a
    /// saved position restored onto a playlist that may have shrunk since, and
    /// the desktop wraps on load (`session.py`) rather than trapping.
    public init(playlist: [String], index: Int = 0) {
        self.playlist = playlist
        self.index = playlist.isEmpty ? 0 : Session.wrap(index, playlist.count)
        self.locked = false
    }

    public var current: String? {
        playlist.isEmpty ? nil : playlist[index]
    }

    /// The clip auto-advance will roll onto — what the prefetcher opens early.
    public var staged: String? {
        guard !locked, !playlist.isEmpty else { return nil }
        return playlist[(index + 1) % playlist.count]
    }

    /// Navigate *delta* entries, wrapping in both directions: previous is the
    /// list neighbour, never a history stack. A deliberate step off a held clip
    /// releases the lock, as the desktop dispatcher's UNLOCK-before-NEXT does.
    public mutating func step(_ delta: Int) {
        guard !playlist.isEmpty else { return }
        locked = false
        index = Session.wrap(index + delta, playlist.count)
    }

    /// Drop the current entry and play what follows it — the trash gesture the
    /// weird tap is built on. The next entry shifts into the same index, so the
    /// index itself does not move; off the end it wraps to the top. A satellite
    /// must always have something to play, so the last remaining entry cannot be
    /// discarded: that is a no-op, never an empty playlist.
    public mutating func discard() -> String? {
        // Discarding releases any hold first, as the desktop dispatcher's
        // UNLOCK-before-TRASH does: repeat-one must not survive onto the clip
        // that shifts into the discarded slot.
        locked = false
        guard playlist.count > 1 else { return nil }
        let dropped = playlist.remove(at: index)
        index %= playlist.count
        return dropped
    }

    /// Lock the satellite onto its clip (repeat-one) or let it run again.
    public mutating func setLocked(_ locked: Bool) {
        self.locked = locked
    }

    /// End of clip: the player rolled onto the staged entry, so the index
    /// follows it. A locked satellite is repeat-one and holds its clip instead.
    public mutating func advance() {
        guard !locked, !playlist.isEmpty else { return }
        index = (index + 1) % playlist.count
    }

    /// Play one exact clip: jump to it when the playlist already holds it, else
    /// splice it in right after the current entry and play it there — a clip
    /// reached from the favorites is not in the live list, and dropping the run
    /// to a one-entry playlist would strand it.
    public mutating func playFile(_ path: String) {
        if let found = playlist.firstIndex(of: path) {
            index = found
            return
        }
        let slot = playlist.isEmpty ? 0 : index + 1
        playlist.insert(path, at: slot)
        index = slot
    }

    /// Swap in a rebuilt playlist without interrupting the clip on screen: a
    /// filter toggle is not a navigation, so if the current entry survives the
    /// rebuild the index simply re-points at it and the lock stands.
    public mutating func replacePlaylist(_ playlist: [String]) {
        // An empty replacement is refused, as the desktop refuses it: a filter
        // that matches nothing leaves the run in place rather than blanking it.
        guard !playlist.isEmpty else { return }
        let playing = current
        self.playlist = playlist
        if let kept = playing.flatMap(playlist.firstIndex(of:)) {
            index = kept
        } else {
            // The held clip is gone, and repeat-one must not be inherited by
            // whatever lands at the top — the desktop cancels the lock on
            // every rebuild that moves a player for the same reason.
            index = 0
            locked = false
        }
    }

    /// Swift's `%` keeps the sign of the dividend, which would put a backward
    /// step off the front of the list; the playlist is a ring.
    private static func wrap(_ value: Int, _ count: Int) -> Int {
        let remainder = value % count
        return remainder < 0 ? remainder + count : remainder
    }
}
