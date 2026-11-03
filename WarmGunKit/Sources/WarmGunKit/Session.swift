import Foundation

public struct Session: Equatable, Sendable {
    public private(set) var playlist: [String]
    public private(set) var index: Int
    public private(set) var locked: Bool

    public init(playlist: [String], index: Int = 0) {
        self.playlist = playlist
        self.index = playlist.isEmpty ? 0 : index.wrapped(into: playlist.count)
        self.locked = false
    }

    public init(restoring playlist: [String], at index: Int, locked: Bool, keeping known: Set<String>) {
        self.init(playlist: playlist.filter(known.contains))
        guard playlist.indices.contains(index), known.contains(playlist[index]) else { return }
        playFile(playlist[index])
        self.locked = locked
    }

    public var current: String? {
        playlist.isEmpty ? nil : playlist[index]
    }

    public var staged: String? {
        guard !locked, !playlist.isEmpty else { return nil }
        return playlist[(index + 1) % playlist.count]
    }

    public mutating func step(_ delta: Int) {
        guard !playlist.isEmpty else { return }
        locked = false
        index = (index + delta).wrapped(into: playlist.count)
    }

    public mutating func discard() -> String? {
        locked = false
        guard playlist.count > 1 else { return nil }
        let dropped = playlist.remove(at: index)
        index %= playlist.count
        return dropped
    }

    public mutating func setLocked(_ locked: Bool) {
        self.locked = locked
    }

    public mutating func advance() {
        guard !locked, !playlist.isEmpty else { return }
        index = (index + 1) % playlist.count
    }

    public mutating func playFile(_ path: String) {
        if let found = playlist.firstIndex(of: path) {
            index = found
            return
        }
        let slot = playlist.isEmpty ? 0 : index + 1
        playlist.insert(path, at: slot)
        index = slot
    }

    public mutating func replacePlaylist(_ playlist: [String]) {
        guard !playlist.isEmpty else { return }
        let playing = current
        self.playlist = playlist
        if let kept = playing.flatMap(playlist.firstIndex(of:)) {
            index = kept
        } else {
            index = 0
            locked = false
        }
    }

    public func resumption(currentFits: Bool) -> Resumption {
        if playlist.isEmpty { return .startFromTop }
        return currentFits ? .keep : .rebuildAroundCurrent
    }
}

public enum Resumption: Equatable, Sendable {
    case startFromTop
    case rebuildAroundCurrent
    case keep
}
