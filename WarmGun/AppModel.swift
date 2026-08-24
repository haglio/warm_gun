import AVFoundation
import UIKit
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
    @Published private(set) var paused = false
    @Published private(set) var waitingFor: String?
    @Published private(set) var cached: Set<String> = []
    @Published private(set) var cacheBytes: Int64 = 0
    @Published private(set) var backlog: (remaining: Int, total: Int)?
    @Published private(set) var lastProblem: String?
    /// pCloud answered the password with "provide a code" (1022) or "invalid
    /// code" (2012): the login form must grow a verification-code field.
    @Published private(set) var loginWantsCode = false
    /// A full two-factor challenge: the token to exchange, and whether other
    /// logged-in pCloud apps exist to push a code to.
    @Published private(set) var tfaToken: String?
    @Published private(set) var tfaHasDevices = false

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
    /// The clip actually on the glass — not `session.current`, which runs
    /// ahead of the screen whenever a download is still in flight. Every watch
    /// sample and journal line is labeled with this, never with the session.
    @Published private(set) var showing: String?
    private var planGeneration = 0
    private var consecutiveFailureSkips = 0
    private var persistTask: Task<Void, Never>?
    private var clipsByPath: [String: Clip] = [:]
    private var rng = SystemRandomNumberGenerator()
    private var journalDirty = false
    private var noticeTask: Task<Void, Never>?

    init(stateDirectory: URL = AppModel.defaultStateDirectory, cache: ClipCache? = nil) {
        self.stateDirectory = stateDirectory
        self.cache = cache ?? ClipCache(directory: ClipCache.defaultDirectory)
        settings = Settings.load()
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        engine.onAdvanced = { [weak self] url in self?.advanced(to: url) }
        engine.onProgress = { [weak self] fraction in self?.progressed(fraction) }
        engine.onItemFailed = { [weak self] url in self?.itemFailed(url) }
    }

    nonisolated static var defaultStateDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("State", isDirectory: true)
    }

    // MARK: - lifecycle

    func start() async {
        // F-mode is shelved until the desktop's favorites reach the phone —
        // the switch is gone from the sheet, so nothing may leave it stuck on.
        settings.browse.favoritesOnly = false
        cached = await cache.cachedPaths()
        cacheBytes = await cache.totalBytes()
        loadPersistedState()
        guard let token = Keychain.token() else { phase = .needsLogin; return }
        do {
            try connect(token: token)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        if settings.libraryPath.isEmpty {
            // Nobody should have to TELL the app where the library is: it is
            // the one folder in the account holding both pipeline stages, so
            // one folders-only listing finds it. The Settings field remains as
            // an override for the day the account grows a second skeleton.
            phase = .indexing
            do {
                guard let client, let found = try await Self.discoverLibrary(client: client) else {
                    lastProblem = "No folder holding both 1_sorted and 2_outbox found in this account"
                    phase = .needsLibrary
                    return
                }
                settings.libraryPath = found
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
        }
        if catalog == nil {
            await index()
        } else {
            phase = .ready
            if session.playlist.isEmpty { rebuild(startAtTop: true) } else { sync() }
            Task { await index() }
        }
    }

    /// True on success, so the form knows whether to clear the password or
    /// keep it for another try. Any failure lands in `lastProblem` verbatim.
    func login(username: String, password: String, code: String? = nil) async -> Bool {
        let trimmed = (code ?? "").trimmingCharacters(in: .whitespaces)
        settings.username = username
        Keychain.storePending(password: password)
        do {
            let response: LoginResponse
            if let tfaToken, !trimmed.isEmpty {
                // The second leg: exchange the challenge token and the code.
                // Recovery codes are long; pCloud tells them apart by length.
                response = try await PCloudClient.tfaLogin(apiHost: settings.apiHost, token: tfaToken,
                                                           code: trimmed, isRecovery: trimmed.count >= 16)
            } else {
                response = try await PCloudClient.login(apiHost: settings.apiHost, username: username, password: password,
                                                        code: trimmed.isEmpty ? nil : trimmed)
            }
            Keychain.store(token: response.auth)
            guard Keychain.token() != nil else {
                lastProblem = "The Keychain refused to store the token"
                return false
            }
            lastProblem = nil
            loginWantsCode = false
            tfaToken = nil
            tfaHasDevices = false
            Keychain.forgetPending()
            await start()
            return true
        } catch {
            lastProblem = error.localizedDescription
            guard let pcloud = error as? PCloudError else { return false }
            if let challenge = pcloud.token {
                tfaToken = challenge
                tfaHasDevices = pcloud.hasDevices ?? false
                loginWantsCode = true
                lastProblem = "pCloud wants a second factor. Enter a code from your authenticator app, or use a send button below."
            } else if pcloud.code == 1022 || pcloud.code == 2012 {
                loginWantsCode = true
                lastProblem = pcloud.code == 1022
                    ? "This account wants a verification code — check your authenticator app (or email/SMS from pCloud) and enter it below."
                    : "pCloud refused that verification code — try a fresh one."
            } else if pcloud.code == 2064 {
                // The challenge token has expired; the run starts over.
                tfaToken = nil
                loginWantsCode = false
                lastProblem = "That code session expired — log in with the password again."
            }
            return false
        }
    }

    /// Ask pCloud to deliver a code: by SMS, or pushed as a notification to
    /// every OTHER logged-in pCloud app (the drive on the Mac or PC).
    func sendTFACode(viaSMS: Bool) async {
        guard let tfaToken else { return }
        do {
            try await PCloudClient.sendTFACode(apiHost: settings.apiHost, token: tfaToken, viaSMS: viaSMS)
            lastProblem = viaSMS ? "Code sent by SMS." : "Code sent — check the pCloud app on your other machines."
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
        clipsByPath = [:]
        session = Session(playlist: [])
        // The persisted index describes the OLD library; left in place it would
        // be reloaded on the next start and played against the new path.
        try? FileManager.default.removeItem(at: catalogURL)
        persistState()
        await start()
    }

    /// Hunt for the library by its skeleton. pCloud refuses a recursive
    /// listing of the ROOT with 1101 (a 2025-era server change), so the walk
    /// starts shallow there and recurses per top-level folder, descending
    /// again wherever the refusal repeats.
    private static func discoverLibrary(client: PCloudClient) async throws -> String? {
        var queue = ["/"]
        var visited = 0
        while !queue.isEmpty, visited < 50 {
            let path = queue.removeFirst()
            visited += 1
            do {
                let tree = try await client.folderSkeleton(path: path, recursive: true)
                if let found = LibraryPaths.discoverLibrary(root: tree, at: path) { return found }
            } catch let error as PCloudError where error.code == 1101 {
                let shallow = try await client.folderSkeleton(path: path, recursive: false)
                let base = path == "/" ? "" : path
                if let found = LibraryPaths.discoverLibrary(root: shallow, at: path) { return found }
                for child in shallow.contents ?? [] where child.isfolder {
                    queue.append(base + "/" + child.name)
                }
            }
        }
        return nil
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
            consecutiveFailureSkips = 0
            cached.insert(path)
            cacheBytes = await cache.totalBytes()
            cached = await cache.cachedPaths()
            if path == waitingFor || path == session.staged { sync() }
        case .failed(let path, let message, let attempts, let loginRequired):
            lastProblem = "\(message) — \((path as NSString).lastPathComponent)"
            if loginRequired {
                // 1000/2000 means the token itself is refused; keeping it would
                // just show a "logged in" screen over an account that is not.
                Keychain.forget()
                phase = .needsLogin
                return
            }
            // Step past a clip only once it has genuinely refused three times,
            // and stop stepping altogether when everything is refusing — a dead
            // network must leave the run parked and retrying, not sprint it
            // silently through the whole playlist.
            if path == waitingFor && attempts >= 3 {
                if consecutiveFailureSkips < 5 {
                    consecutiveFailureSkips += 1
                    flash("Skipping — clip won't fetch", favorite: false)
                    session.step(1)
                    sync()
                } else {
                    lastProblem = "pCloud unreachable — holding here and retrying"
                }
            }
        case .backlog(let remaining, let total, let failures):
            backlog = total == 0 ? nil : (remaining, total)
            if total == 0 { cacheBytes = await cache.totalBytes() }
            if remaining == 0 && failures > 0 {
                lastProblem = "\(failures) clip\(failures == 1 ? "" : "s") could not be downloaded"
            }
        case .evicted(let paths):
            cached.subtract(paths)
            cacheBytes = await cache.totalBytes()
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
                // A background refresh must not reshuffle the run in progress —
                // that is exactly the clip-jumping the desktop's session resume
                // exists to prevent. Prune what the library no longer has; new
                // arrivals join on the next rebuild the user asks for.
                let known = Set(fresh.clips.map(\.path))
                let surviving = session.playlist.filter(known.contains)
                if surviving.count != session.playlist.count {
                    session.replacePlaylist(surviving)
                }
                sync()
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
            // Starting on a clip that is already on disk makes the switch
            // instant; the shuffle does not mind which entry opens it.
            session = Session(playlist: playlist, index: playlist.firstIndex(where: cached.contains) ?? 0)
        } else {
            session.replacePlaylist(playlist)
            if let current = session.current, !cached.contains(current),
               let nearby = playlist.first(where: cached.contains) {
                session.playFile(nearby)
            }
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
        paused = false
        session.step(1)
        sync()
    }

    func previous() {
        tracker.noteUserNav(now: Date())
        paused = false
        session.step(-1)
        sync()
    }

    /// A single tap in the middle. Navigation always unpauses — a tap that
    /// asks for a different clip is a tap that wants playback.
    func togglePause() {
        paused.toggle()
        if paused {
            engine.pause()
        } else {
            engine.resume()
        }
    }

    /// The phone was turned: the browse follows the screen, portrait clips
    /// upright and landscape clips wide, with no switch to remember.
    func deviceRotated(landscape: Bool) {
        let orientation: Orientation = landscape ? .landscape : .portrait
        guard settings.browse.orientation != orientation else { return }
        var browse = settings.browse
        browse.orientation = orientation
        update(browse: browse)
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
        // Either half of the demotion swallows the departure event, as the
        // desktop arms note_discard before it knows which half the press is.
        tracker.noteDiscard()
        if favorites.contains(path: path) {
            favorites.remove(path: path)
            journal("unfavorite", path)
            session.step(1)
            flash("Unfavorited", favorite: true)
        } else {
            weird.insert(path)
            journal("weird", path)
            if session.playlist.count <= 1 {
                // The desktop refuses to trash the last clip; here the honest
                // outcome is an empty run — the clip is weird now, and looping
                // it forever would contradict the gesture just made.
                session = Session(playlist: [])
            } else {
                _ = session.discard()
            }
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
        // "Download this browse" pinned the OLD browse; spending slots on it
        // after the switch would starve the window the user is now watching.
        Task { await prefetcher?.cancelBacklog() }
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
        planGeneration += 1
        let generation = planGeneration
        let plan = PrefetchPlanner.plan(playlist: session.playlist, index: session.index,
                                        ahead: settings.prefetchAhead, behind: settings.prefetchBehind)
        let clips = clipsByPath
        Task { await prefetcher.replan(plan, clips: clips, generation: generation) }
        guard let current = session.current else {
            engine.clear()
            showing = nil
            waitingFor = nil
            return
        }
        let loop = session.locked || settings.loopClip
        guard cached.contains(current) else {
            // The last picture keeps looping under the spinner, but nothing may
            // stay queued behind it: a stale roll-on would advance a session
            // that has already moved somewhere else.
            engine.holdCurrent()
            waitingFor = current
            return
        }
        waitingFor = nil
        showing = current
        let staged = session.staged.flatMap { cached.contains($0) ? $0 : nil }
        Task {
            let currentURL = await cache.fileURL(for: current)
            var nextURL: URL?
            if let staged { nextURL = await cache.fileURL(for: staged) }
            await cache.markUsed(current)
            engine.show(current: currentURL, next: nextURL, loop: loop, autoplay: !self.paused)
        }
        persistSoon()
    }

    /// The queue rolled on. Advance the session only when what it rolled onto
    /// is the clip the session staged — the engine's queue is not the session,
    /// and a roll that predates a gesture must not move it.
    private func advanced(to url: URL) {
        if let staged = session.staged, url.lastPathComponent == ClipCache.fileName(for: staged) {
            session.advance()
        }
        sync()
    }

    /// A clip the player refuses — a truncated body, a container AVFoundation
    /// cannot read. The cached copy is poison, so it leaves the disk; if it is
    /// the clip on screen the run steps past it rather than freezing.
    private func itemFailed(_ url: URL) {
        guard let path = session.playlist.first(where: { url.lastPathComponent == ClipCache.fileName(for: $0) })
        else { return }
        cached.remove(path)
        Task { await cache.remove([path]); cacheBytes = await cache.totalBytes() }
        lastProblem = "Unplayable clip — \((path as NSString).lastPathComponent)"
        if path == showing {
            flash("Skipping unplayable clip", favorite: false)
            session.step(1)
        }
        sync()
    }

    private func progressed(_ fraction: Double) {
        // While a download is in flight the engine is replaying the PREVIOUS
        // clip under a spinner; those frames speak for nothing the session
        // points at, so they are not sampled at all.
        guard waitingFor == nil, let path = showing else { return }
        for (event, eventPath) in tracker.sample(path: path, fraction: fraction, now: Date()) {
            stats.record(event, path: eventPath)
            journal(event.rawValue, eventPath)
        }
    }

    /// The scene is back on screen; AVPlayer does not resume by itself.
    func becameActive() {
        engine.resume()
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
        // The caller is usually the background transition; without an assertion
        // iOS suspends the app mid-upload and the journal never leaves.
        let assertion = UIApplication.shared.beginBackgroundTask()
        defer { if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) } }
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
        var locked: Bool?  // optional so older blobs still decode
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
                                   playlist: session.playlist, index: session.index,
                                   locked: session.locked)
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
        restored.setLocked(state.locked ?? false)
        session = restored
    }

    /// Auto-advance persists through here: at most one write per fifteen
    /// seconds, on the tail edge, because every write is the whole playlist
    /// plus all stats JSON-encoded on the main actor. Gestures persist
    /// immediately (they call `persistState` directly), and going to the
    /// background flushes whatever is pending.
    private func persistSoon() {
        guard persistTask == nil else { return }
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.persistTask = nil
            self?.persistState()
        }
    }

    func flushState() {
        persistTask?.cancel()
        persistTask = nil
        persistState()
    }
}
