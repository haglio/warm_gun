import AVFoundation
import Foundation
import WarmGunKit

/// The one owner of the app's state. Views read it and post intents; the
/// Kit decides; the actors (client, cache, prefetcher) do the I/O. Every
/// change to what is playing funnels through `sync()`, which is also where
/// the prefetch window is re-planned.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case needsLogin
        case needsLibrary
        case indexing
        case ready
        case failed(String)
    }

    struct Notice: Equatable {
        let id = UUID()
        let text: String
        let favorite: Bool
    }

    @Published var settings: Settings {
        didSet { settings.save() }
    }
    @Published private(set) var phase: Phase = .needsLogin
    @Published private(set) var catalog: Catalog?
    @Published private(set) var session = Session(playlist: [])
    @Published private(set) var favorites = Favorites()
    @Published private(set) var weird: Set<String> = []
    @Published private(set) var stats = WatchStats()
    @Published private(set) var notice: Notice?
    @Published private(set) var waitingFor: String?
    @Published private(set) var cached: Set<String> = []
    @Published private(set) var cacheBytes: Int64 = 0
    @Published private(set) var backlog: (remaining: Int, total: Int)?
    @Published private(set) var lastProblem: String?

    private let engine = PlayerEngine()
    /// The one AVFoundation object the view layer needs — the player the video
    /// surface renders. Handing it out directly (rather than the engine) keeps
    /// the engine's queue bookkeeping out of everyone else's reach.
    var player: AVPlayer { engine.player }
    private let cache: ClipCache
    private let stateDirectory: URL
    private var client: PCloudClient?
    private var prefetcher: Prefetcher?
    private var eventPump: Task<Void, Never>?
    private var tracker = WatchTracker()
    private var clipsByPath: [String: Clip] = [:]
    private var rng = SystemRandomNumberGenerator()
    private var journalDirty = false
    private var noticeTask: Task<Void, Never>?

    init(stateDirectory: URL = AppModel.defaultStateDirectory, cache: ClipCache? = nil) {
        self.stateDirectory = stateDirectory
        self.cache = cache ?? ClipCache(directory: ClipCache.defaultDirectory)
        settings = Settings.load()
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        engine.onAdvanced = { [weak self] in self?.advanced() }
        engine.onProgress = { [weak self] fraction in self?.progressed(fraction) }
    }

    nonisolated static var defaultStateDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("State", isDirectory: true)
    }

    // MARK: - lifecycle

    func start() async {
        cached = await cache.cachedPaths()
        cacheBytes = await cache.totalBytes()
        loadPersistedState()
        guard let token = Keychain.token() else { phase = .needsLogin; return }
        guard !settings.libraryPath.isEmpty else { phase = .needsLibrary; return }
        do {
            try connect(token: token)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        if catalog == nil {
            await index()
        } else {
            phase = .ready
            if session.playlist.isEmpty { rebuild(startAtTop: true) } else { sync() }
            Task { await index() }
        }
    }

    func login(username: String, password: String) async {
        do {
            let response = try await PCloudClient.login(apiHost: settings.apiHost, username: username, password: password)
            Keychain.store(token: response.auth)
            lastProblem = nil
            await start()
        } catch {
            lastProblem = error.localizedDescription
        }
    }

    func logout() {
        Keychain.forget()
        eventPump?.cancel()
        client = nil
        prefetcher = nil
        engine.clear()
        phase = .needsLogin
    }

    func setLibraryPath(_ path: String) async {
        settings.libraryPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        catalog = nil
        session = Session(playlist: [])
        persistState()
        await start()
    }

    private func connect(token: String) throws {
        let client = try PCloudClient(apiHost: settings.apiHost, auth: token)
        self.client = client
        let prefetcher = Prefetcher(client: client, cache: cache, capBytes: settings.cacheCapBytes)
        self.prefetcher = prefetcher
        eventPump?.cancel()
        eventPump = Task { [weak self] in
            for await event in prefetcher.events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: Prefetcher.Event) async {
        switch event {
        case .ready(let path):
            cached.insert(path)
            cacheBytes = await cache.totalBytes()
            cached = await cache.cachedPaths()
            if path == waitingFor || path == session.staged { sync() }
        case .failed(let path, let message):
            lastProblem = "\(message) — \((path as NSString).lastPathComponent)"
            if path == waitingFor { session.step(1); sync() }
        case .backlog(let remaining, let total):
            backlog = total == 0 ? nil : (remaining, total)
            if total == 0 { cacheBytes = await cache.totalBytes() }
        }
    }

    // MARK: - the index

    func index() async {
        guard let client else { return }
        if catalog == nil { phase = .indexing }
        do {
            let files = try await client.listLibrary(path: settings.libraryPath)
            let fresh = Catalog(files: files)
            let changed = fresh != catalog
            catalog = fresh
            clipsByPath = Dictionary(uniqueKeysWithValues: fresh.clips.map { ($0.path, $0) })
            if changed { persistCatalog() }
            phase = .ready
            if session.playlist.isEmpty {
                rebuild(startAtTop: true)
            } else if changed {
                rebuild(startAtTop: false)
            }
        } catch {
            if catalog == nil { phase = .failed(error.localizedDescription) } else { lastProblem = error.localizedDescription }
        }
    }

    /// Builds the browse from the index and hands it to the session. A change
    /// of filter keeps the clip on screen when it survives (the desktop's
    /// `replace_playlist`); a new order starts from the top. A filter that
    /// matches nothing leaves the current playlist in place rather than
    /// blanking the screen.
    private func rebuild(startAtTop: Bool) {
        guard let catalog else { return }
        let playlist = PlaylistBuilder.build(catalog: catalog, options: settings.browse,
                                             favoriteStems: favorites.stems, weird: weird,
                                             stats: stats, rng: &rng)
        if playlist.isEmpty {
            if !session.playlist.isEmpty { flash("Nothing matches", favorite: false) }
            if session.playlist.isEmpty { sync() }
            return
        }
        if startAtTop {
            session = Session(playlist: playlist)
        } else {
            session.replacePlaylist(playlist)
        }
        sync()
    }

    // MARK: - gestures

    func tap(_ action: TapAction) {
        switch action {
        case .previous: previous()
        case .next: next()
        case .weird: markWeird()
        case .lock: toggleLock()
        case .center: break
        }
    }

    func next() {
        tracker.noteUserNav(now: Date())
        session.step(1)
        sync()
    }

    func previous() {
        tracker.noteUserNav(now: Date())
        session.step(-1)
        sync()
    }

    /// Lock = repeat this clip, and it is a favorite from now on. Unlock moves
    /// on rather than replaying, and never unfavorites (that is the weird
    /// gesture's job).
    func toggleLock() {
        guard let path = session.current else { return }
        if session.locked {
            session.step(1)
            flash("Unlocked", favorite: false)
        } else {
            session.setLocked(true)
            if favorites.insert(path: path) { journal("favorite", path) }
            stats.record(.lock, path: path)
            journal("lock", path)
            flash("Locked", favorite: true)
        }
        persistState()
        sync()
    }

    /// The two-step demotion: a favorite only loses its star; anything else
    /// leaves the rotation and its upscale goes to `kinda_weird`, exactly as
    /// the desktop's up-arrow does.
    func markWeird() {
        guard let path = session.current else { return }
        if favorites.contains(path: path) {
            favorites.remove(path: path)
            journal("unfavorite", path)
            session.step(1)
            flash("Unfavorited", favorite: true)
        } else {
            tracker.noteDiscard()
            weird.insert(path)
            journal("weird", path)
            _ = session.discard()
            flash("Marked weird", favorite: false)
            cached.remove(path)
            Task { await cache.remove([path]); cacheBytes = await cache.totalBytes() }
            if settings.moveWeirdInCloud { Task { await moveUpscaleToWeird(path) } }
        }
        persistState()
        sync()
    }

    private func moveUpscaleToWeird(_ path: String) async {
        guard let client, let upscale = LibraryPaths.upscalePath(forOriginal: path) else { return }
        let root = settings.libraryPath
        let weirdDir = root + "/" + LibraryPaths.weirdDir
        do {
            try await client.createFolderIfNotExists(path: weirdDir)
            try await client.renameFile(path: root + "/" + upscale,
                                         toPath: weirdDir + "/" + (upscale as NSString).lastPathComponent)
        } catch {
            lastProblem = "Could not move the upscale to kinda_weird: \(error.localizedDescription)"
        }
    }

    func update(browse: BrowseOptions) {
        let orderChanged = browse.latest != settings.browse.latest
        settings.browse = browse
        rebuild(startAtTop: orderChanged)
    }

    func update(loopClip: Bool) {
        settings.loopClip = loopClip
        sync()
    }

    func update(cacheCapMB: Int) {
        settings.cacheCapMB = cacheCapMB
        Task { await prefetcher?.setCap(bytes: settings.cacheCapBytes) }
    }

    /// Prefetch the whole current browse, raising the cache cap to hold it.
    func downloadEverything() {
        guard let prefetcher else { return }
        let paths = session.playlist
        let needed = paths.compactMap { clipsByPath[$0]?.size }.reduce(0, +)
        let capMB = Int((Double(needed) * 1.1) / 1_000_000) + 1
        if capMB > settings.cacheCapMB { update(cacheCapMB: capMB) }
        let clips = clipsByPath
        Task { await prefetcher.downloadAll(paths, clips: clips) }
    }

    func cancelDownloadEverything() {
        Task { await prefetcher?.cancelBacklog() }
    }

    func clearCache() {
        Task {
            await cache.removeAll()
            cached = []
            cacheBytes = 0
            sync()
        }
    }

    // MARK: - playback plumbing

    /// The single place the screen and the prefetch window are brought in line
    /// with the session.
    private func sync() {
        guard let prefetcher else { return }
        let plan = PrefetchPlanner.plan(playlist: session.playlist, index: session.index,
                                        ahead: settings.prefetchAhead, behind: settings.prefetchBehind)
        let clips = clipsByPath
        Task { await prefetcher.replan(plan, clips: clips) }
        guard let current = session.current else {
            engine.clear()
            waitingFor = nil
            return
        }
        let loop = session.locked || settings.loopClip
        guard cached.contains(current) else {
            waitingFor = current
            return
        }
        waitingFor = nil
        let staged = session.staged.flatMap { cached.contains($0) ? $0 : nil }
        Task {
            let currentURL = await cache.fileURL(for: current)
            var nextURL: URL?
            if let staged { nextURL = await cache.fileURL(for: staged) }
            await cache.markUsed(current)
            engine.show(current: currentURL, next: nextURL, loop: loop)
        }
        persistState()
    }

    private func advanced() {
        session.advance()
        sync()
    }

    private func progressed(_ fraction: Double) {
        guard let path = session.current else { return }
        for (event, eventPath) in tracker.sample(path: path, fraction: fraction, now: Date()) {
            stats.record(event, path: eventPath)
            journal(event.rawValue, eventPath)
        }
    }

    private func flash(_ text: String, favorite: Bool) {
        notice = Notice(text: text, favorite: favorite)
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: - the journal and the favorites file

    private var journalURL: URL { stateDirectory.appendingPathComponent("warm-gun-journal.jsonl") }

    private func journal(_ event: String, _ path: String) {
        let line = Journal.line(JournalEvent(t: Int(Date().timeIntervalSince1970), event: event, path: path)) + "\n"
        if let handle = try? FileHandle(forWritingTo: journalURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: journalURL)
        }
        journalDirty = true
    }

    /// Pushes the journal to the sync folder and pulls a `favs.csv` from it if
    /// one is there. Called when the app goes to the background and from
    /// Settings; never in the way of playback.
    func syncWithCloud() async {
        guard let client, !settings.syncFolder.isEmpty else { return }
        do {
            try await client.createFolderIfNotExists(path: settings.syncFolder)
            if journalDirty, let data = try? Data(contentsOf: journalURL) {
                try await client.upload(data: data, folderPath: settings.syncFolder, filename: "warm-gun-journal.jsonl")
                journalDirty = false
            }
            let files = try await client.listLibrary(path: settings.syncFolder)
            if let favs = files.first(where: { $0.path.lowercased() == "favs.csv" }) {
                let link = try await client.fileLink(fileID: favs.fileID)
                guard let url = link.url else { return }
                let tmp = try await client.download(url)
                defer { try? FileManager.default.removeItem(at: tmp) }
                let text = try String(contentsOf: tmp, encoding: .utf8)
                let before = favorites.stems.count
                favorites.merge(stems: FavsCSV.stems(in: text))
                if favorites.stems.count != before { persistState() }
            }
        } catch {
            lastProblem = "Cloud sync: \(error.localizedDescription)"
        }
    }

    // MARK: - persistence

    private struct PersistedState: Codable {
        var favorites: Favorites
        var weird: Set<String>
        var stats: WatchStats
        var playlist: [String]
        var index: Int
    }

    private var catalogURL: URL { stateDirectory.appendingPathComponent("catalog.json") }
    private var stateURL: URL { stateDirectory.appendingPathComponent("state.json") }

    private func persistCatalog() {
        if let catalog, let data = try? JSONEncoder().encode(catalog) {
            try? data.write(to: catalogURL, options: .atomic)
        }
    }

    private func persistState() {
        let state = PersistedState(favorites: favorites, weird: weird, stats: stats,
                                   playlist: session.playlist, index: session.index)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    /// A relaunch picks up where it left off: same order, same clip, minus
    /// anything the index no longer has (the desktop's `resume_playlists`).
    private func loadPersistedState() {
        if let data = try? Data(contentsOf: catalogURL), let saved = try? JSONDecoder().decode(Catalog.self, from: data) {
            catalog = saved
            clipsByPath = Dictionary(uniqueKeysWithValues: saved.clips.map { ($0.path, $0) })
        }
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        favorites = state.favorites
        weird = state.weird
        stats = state.stats
        let surviving = state.playlist.filter { clipsByPath[$0] != nil }
        var restored = Session(playlist: surviving)
        if !surviving.isEmpty, state.index < state.playlist.count, let current = Optional(state.playlist[state.index]), clipsByPath[current] != nil {
            restored.playFile(current)
        }
        session = restored
    }
}
