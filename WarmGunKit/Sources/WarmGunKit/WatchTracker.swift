import Foundation

/// The three things playback can say about a clip. The raw values are the
/// vocabulary of the journal, which the desktop stage counts by name
/// (`evolver/tasks/watch_weights.py`), so they are a contract, not labels.
public enum WatchEvent: String, Sendable {
    case completion
    case skip
    case lock
}

/// Turns a run of playback samples into watch events.
///
/// Player-agnostic, exactly as the desktop's is: fed periodic (path, fraction)
/// samples plus notice of user navigation and of discards, it says which clips
/// were watched through and which were skipped. A held clip counts again on
/// every repeat-one wrap. Anything else — the automatic advance on unlock, a
/// clip that vanished — is deliberately neutral, because only what the viewer
/// did should move a clip's weight.
///
/// Nothing is totted up here: each event is journalled and the desktop sums the
/// two apps' journals into the weight both of them then read.
public struct WatchTracker: Sendable {
    /// At or past this fraction the clip counts as watched.
    public static let completeFraction = 0.85
    /// At or below this fraction, leaving counts against the clip.
    public static let skipFraction = 0.60
    /// How recently a tap must have happened for a departure to be the viewer's doing.
    public static let navWindow: TimeInterval = 3.0
    /// How far back a position has to jump before it is a wrap and not jitter.
    private static let wrapDrop = 0.5

    private var path = ""
    private var maxFraction = 0.0
    private var lastNavAt = Date.distantPast
    private var suppressDeparted = false

    public init() {}

    public mutating func noteUserNav(now: Date) {
        lastNavAt = now
    }

    public mutating func noteDiscard() {
        suppressDeparted = true
    }

    /// One position report. Two things can happen: the clip on screen looped,
    /// or a different clip took its place — the tracker never sees an "ended".
    public mutating func sample(path: String, fraction: Double, now: Date) -> [(event: WatchEvent, path: String)] {
        if path == self.path { return wrapped(to: fraction) }
        let departure = departureEvent(now: now)
        self.path = path
        maxFraction = max(0.0, fraction)
        suppressDeparted = false
        return departure.map { [$0] } ?? []
    }

    /// The clip is still on screen, so the only news a sample can carry is a
    /// jump back to the top: a satellite has no seek control, so a big backward
    /// move from near the end can only be a repeat-one wrap, and a held clip
    /// books one full watch for each of them.
    private mutating func wrapped(to fraction: Double) -> [(event: WatchEvent, path: String)] {
        guard !path.isEmpty, maxFraction >= Self.completeFraction,
              fraction < maxFraction - Self.wrapDrop else {
            maxFraction = max(maxFraction, fraction)
            return []
        }
        maxFraction = max(0.0, fraction)
        return [(.completion, path)]
    }

    /// What the clip leaving the screen earned. Reaching the end is a watch
    /// however the roll-on happened; leaving it barely started counts against it
    /// only when a tap just before says the viewer chose to leave. A discard —
    /// the clip marked weird and pulled out of the playlist — is a harder
    /// judgement already made, so it swallows the departure entirely.
    private func departureEvent(now: Date) -> (event: WatchEvent, path: String)? {
        guard !path.isEmpty, !suppressDeparted else { return nil }
        if maxFraction >= Self.completeFraction { return (.completion, path) }
        let navRecent = now.timeIntervalSince(lastNavAt) <= Self.navWindow
        guard navRecent, maxFraction <= Self.skipFraction else { return nil }
        return (.skip, path)
    }
}
