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
    /// Which loop the run is in: the whole browse, one clip, or the current
    /// clip's seed family / action group — the desktop satellite's axes.
    enum LoopMode: String { case all, single, seed, action }
    @Published private(set) var loopMode: LoopMode = .all
    /// Whether the CURRENT clip has a group to loop — the sheet greys the
    /// segment out rather than letting a press dead-end.
    @Published private(set) var seedLoopAvailable = false
    @Published private(set) var actionLoopAvailable = false

    /// Clip lengths measured off the cached files, path-keyed — the real
    /// pCloud listing carries no durations, so the phone learns them itself.
    private var measuredSeconds: [String: Double] = [:]
    /// The seed/action grouping over the metadata sidecars, refreshed once per
    /// launch in the background; empty until the first fetch lands.
    private var groupIndex = GroupIndex(sidecars: [:])
    private var refreshedMetadata = false
    @Published private(set) var notice: Notice?
    @Published private(set) var paused = false
    /// The video layer has a frame on the glass. False is the truthful "you
    /// are looking at black" signal — rate alone lies during the first seconds
    /// of a big file.
    @Published private(set) var layerReady = false
    /// The player is stalled mid-buffer for long enough to say so — debounced,
    /// so a loop wrap's momentary hiccup does not flash a loading screen.
    @Published private(set) var buffering = false
    private var bufferingTask: Task<Void, Never>?
    @Published private(set) var waitingFor: String?
    @Published private(set) var cached: Set<String> = []
    @Published private(set) var cacheBytes: Int64 = 0
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
    /// The lanes the repo cannot name (see ContentOverlay): bundled from the
    /// git-ignored content.local.json, empty when the bundle carries none.
    let overlay: ContentOverlay
    /// A clip past this size streams straight off its pCloud link instead of
    /// being fetched whole — a real scene runs to hundreds of megabytes, and
    /// most carry their index up front, so playback starts in seconds.
    private let streamThresholdBytes: Int64 = 25_000_000
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
    /// A browse/filter change whose new clip is not on disk yet must VISIBLY
    /// take effect: the old picture clears to the spinner instead of looping
    /// on as if the switch did nothing. Nav stalls keep the old picture — a
    /// fast tap run reads better over motion than over black.
    private var clearOnNextWait = false
    private var noticeTask: Task<Void, Never>?

    init(stateDirectory: URL = AppModel.defaultStateDirectory, cache: ClipCache? = nil) {
        if let url = Bundle.main.url(forResource: "content.local", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode(ContentOverlay.self, from: data) {
            overlay = loaded
        } else {
            overlay = .empty
        }
        self.stateDirectory = stateDirectory
        self.cache = cache ?? ClipCache(directory: ClipCache.defaultDirectory)
        settings = Settings.load()
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        engine.onAdvanced = { [weak self] url in self?.advanced(to: url) }
        engine.onFinished = { [weak self] in self?.finished() }
        engine.onBuffering = { [weak self] stalled in self?.buffering(stalled) }
        // The library follows the physical rotation. The view's geometry hook
        // also reports this, but the device notification arrives even when a
        // layout pass does not, so both roads lead here.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                switch UIDevice.current.orientation {
                case .portrait, .portraitUpsideDown: self?.deviceRotated(landscape: false)
                case .landscapeLeft, .landscapeRight: self?.deviceRotated(landscape: true)
                default: break  // face up/down says nothing about the screen
                }
            }
        }
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
            if session.playlist.isEmpty {
                rebuild(startAtTop: true)
            } else if currentClipFightsBrowse() {
                // The resumed playlist was built under other switches — the
                // launch-in-portrait-sees-landscape bug: orientation changed
                // while no catalog was loaded, and the restored run was never
                // re-judged. A mismatch rebuilds; a match keeps the run.
                rebuild(startAtTop: false)
            } else {
                sync()
            }
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
            measureDuration(of: path)
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
            var files = try await client.listLibrary(path: settings.libraryPath)
            // The genau loops live beside the library, not inside it — Evolver
            // delivers them out of the pipeline into videos/genau/clips. A
            // missing folder is fine; the source simply contributes nothing.
            if let genauPath = LibraryPaths.genauClipsPath(forLibrary: settings.libraryPath),
               let loops = try? await client.listLibrary(path: genauPath) {
                files += loops.map { $0.prefixed(LibraryPaths.genauPrefix) }
            }
            // The real scenes — "full length" in Fun Time's sense is the
            // non-AI library, the AI folder's sibling.
            if let nonAIPath = LibraryPaths.nonAIPath(forLibrary: settings.libraryPath),
               let scenes = try? await client.listLibrary(path: nonAIPath) {
                files += scenes.map { $0.prefixed(LibraryPaths.nonAIPrefix) }
            }
            let fresh = Catalog(files: files)
            let changed = fresh != catalog
            catalog = fresh
            clipsByPath = Dictionary(uniqueKeysWithValues: fresh.clips.map { ($0.path, $0) })
            if changed { persistCatalog() }
            phase = .ready
            refreshMetadata()
            if session.playlist.isEmpty {
                rebuild(startAtTop: true)
            } else if currentClipFightsBrowse() {
                rebuild(startAtTop: false)
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

    /// The sidecar corpus, fetched as one zip and kept beside the state files;
    /// the launch's copy serves until the fetch lands.
    private func refreshMetadata() {
        guard !refreshedMetadata, let client else { return }
        refreshedMetadata = true
        let libraryPath = settings.libraryPath
        Task {
            do {
                guard let metadataPath = LibraryPaths.metadataAIPath(forLibrary: libraryPath) else { return }
                // One cheap listing decides whether anything moved: same count
                // and same newest write means the persisted index still speaks
                // for the mirror, and nothing is fetched at all.
                let listing = try await client.listLibrary(path: metadataPath)
                    .filter { $0.path.hasSuffix(".json") }
                let fingerprint = MetadataFetcher.fingerprint(of: listing)
                let stored = UserDefaults.standard.string(forKey: "warm-gun.metadata-fingerprint")
                if fingerprint == stored, !groupIndex.isEmpty {
                    recomputeLoopAvailability()
                    return
                }
                let sidecars = try await MetadataFetcher.fetchSidecars(client: client, libraryPath: libraryPath,
                                                                       listing: listing) { _ in }
                guard !sidecars.isEmpty else {
                    lastProblem = "Metadata: the metadata folder came back empty"
                    return
                }
                groupIndex = GroupIndex(sidecars: sidecars)
                recomputeLoopAvailability()
                if let data = try? JSONEncoder().encode(sidecars) {
                    try? data.write(to: sidecarsURL, options: .atomic)
                    UserDefaults.standard.set(fingerprint, forKey: "warm-gun.metadata-fingerprint")
                }
            } catch {
                lastProblem = "Metadata: \(error.localizedDescription)"
            }
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
                                             stats: stats, measuredSeconds: measuredSeconds,
                                             overlay: overlay, acts: groupIndex.actsByPath, rng: &rng)
        if playlist.isEmpty {
            // Nothing fits these switches: say exactly that on a blank screen
            // (the view reads the empty playlist) rather than playing on as if
            // the switch had not landed.
            session = Session(playlist: [])
            sync()
            return
        }
        let before = session.current
        if startAtTop {
            // The top means the top: Latest must open on the newest clip, and
            // a fresh shuffle on its own first draw — never on whatever
            // happened to be cached nearby.
            session = Session(playlist: playlist)
        } else {
            session.replacePlaylist(playlist)
            if let current = session.current, !cached.contains(current),
               let nearby = playlist.first(where: cached.contains) {
                session.playFile(nearby)
            }
        }
        clearOnNextWait = session.current != before
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
    func setLayerReady(_ ready: Bool) {
        if layerReady != ready { layerReady = ready }
    }

    func togglePause() {
        paused.toggle()
        if paused {
            engine.pause()
        } else {
            engine.resume()
        }
    }

    /// Does the clip on screen belong to a different orientation than the
    /// browse asks for? Genau loops play either way; a lane's orientation
    /// outranks the pixels, as in the build itself.
    private func currentClipFightsBrowse() -> Bool {
        guard let current = session.current, let clip = clipsByPath[current] else { return false }
        let type = ClipType.classify(clip, shortsMaxSeconds: settings.browse.shortsMaxSeconds,
                                     measuredSeconds: measuredSeconds[current], overlay: overlay,
                                     act: groupIndex.actsByPath[current])
        guard type != .genau else { return false }
        let orientation = overlay.lane(for: current)?.orientation ?? clip.orientation
        return orientation != settings.browse.orientation
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
        if loopMode == .seed || loopMode == .action { loopMode = .all }
        rebuild(startAtTop: orderChanged)
    }

    /// The Loop control. All and 1 are playback modes; Seed and Action are the
    /// desktop's group loops: the playlist is re-seated with the current
    /// clip's group (anchor first) and cycles it by ordinary auto-advance —
    /// the clip on screen never restarts. A group of one turns the press into
    /// a lock rather than a dead end, exactly as the desktop does.
    func setLoop(_ mode: LoopMode) {
        switch mode {
        case .all, .single:
            let wasGrouped = loopMode == .seed || loopMode == .action
            loopMode = mode
            settings.loopClip = mode == .single
            if wasGrouped {
                rebuild(startAtTop: false)
                flash("Loop off", favorite: false)
            } else {
                sync()
            }
        case .seed, .action:
            guard let current = session.current else { return }
            let members = mode == .seed ? groupIndex.seedMembers(of: current)
                                        : groupIndex.actionMembers(of: current)
            settings.loopClip = false
            if members.count < 2 {
                session.setLocked(true)
                loopMode = .all
                flash("Locked — no group", favorite: true)
            } else {
                session.setLocked(false)
                session.replacePlaylist(members)
                loopMode = mode
                flash("\(mode == .seed ? "Seed" : "Action") loop — \(members.count) clips", favorite: false)
            }
            sync()
        }
    }

    func update(cacheCapMB: Int) {
        settings.cacheCapMB = cacheCapMB
        Task { await prefetcher?.setCap(bytes: settings.cacheCapBytes) }
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
        // The scenes too big to cache whole are not planned — they stream.
        let plan = PrefetchPlanner.plan(playlist: session.playlist, index: session.index,
                                        ahead: settings.prefetchAhead, behind: settings.prefetchBehind)
            .filter { clipsByPath[$0].map { $0.size <= streamThresholdBytes } ?? true }
        let clips = clipsByPath
        Task { await prefetcher.replan(plan, clips: clips, generation: generation) }
        recomputeLoopAvailability()
        guard let current = session.current else {
            engine.clear()
            showing = nil
            waitingFor = nil
            return
        }
        let loop = session.locked || settings.loopClip
        if let clip = clipsByPath[current], clip.size > streamThresholdBytes, !cached.contains(current) {
            // Stream a scene straight off its link: playback starts on the
            // first ranges, nothing lands in the cache, nothing is staged
            // behind it (the next clip syncs when this one finishes).
            waitingFor = nil
            showing = current
            Task {
                do {
                    let url = try await prefetcher.streamURL(for: clip)
                    engine.show(current: url, next: nil, loop: loop, autoplay: !self.paused)
                } catch {
                    lastProblem = error.localizedDescription
                    flash("Scene won't stream", favorite: false)
                }
            }
            persistSoon()
            return
        }
        guard cached.contains(current) else {
            if clearOnNextWait {
                // The browse just changed: the switch must be seen to land.
                engine.clear()
                showing = nil
            } else {
                // A nav stall: the last picture keeps looping under the pill,
                // but nothing may stay queued behind it — a stale roll-on
                // would advance a session that has already moved elsewhere.
                engine.holdCurrent()
            }
            waitingFor = current
            return
        }
        clearOnNextWait = false
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

    private func buffering(_ stalled: Bool) {
        bufferingTask?.cancel()
        guard stalled else { buffering = false; return }
        bufferingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.buffering = true
        }
    }

    /// The clip played out with nothing staged behind it — a streamed scene,
    /// or a cached clip whose neighbour has not landed yet. The session moves
    /// on; the picture replays or holds until the next clip is ready.
    private func finished() {
        session.advance()
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

    /// The listing never times the clips, so each one is measured the moment
    /// its file lands — from then on the shorts checkbox judges it by truth
    /// rather than by the size stand-in.
    private func measureDuration(of path: String) {
        guard measuredSeconds[path] == nil else { return }
        Task {
            let url = await cache.fileURL(for: path)
            guard let duration = try? await AVURLAsset(url: url).load(.duration).seconds,
                  duration.isFinite, duration > 0 else { return }
            measuredSeconds[path] = duration
            persistSoon()
        }
    }

    private func recomputeLoopAvailability() {
        guard let current = session.current, !groupIndex.isEmpty else {
            seedLoopAvailable = false
            actionLoopAvailable = false
            return
        }
        seedLoopAvailable = groupIndex.seedMembers(of: current).count > 1
        actionLoopAvailable = groupIndex.actionMembers(of: current).count > 1
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
        var measuredSeconds: [String: Double]?
    }

    private var catalogURL: URL { stateDirectory.appendingPathComponent("catalog.json") }
    private var sidecarsURL: URL { stateDirectory.appendingPathComponent("sidecars.json") }
    private var stateURL: URL { stateDirectory.appendingPathComponent("state.json") }

    private func persistCatalog() {
        if let catalog, let data = try? JSONEncoder().encode(catalog) {
            try? data.write(to: catalogURL, options: .atomic)
        }
    }

    private func persistState() {
        let state = PersistedState(favorites: favorites, weird: weird, stats: stats,
                                   playlist: session.playlist, index: session.index,
                                   locked: session.locked, measuredSeconds: measuredSeconds)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    /// A relaunch picks up where it left off: same order, same clip, minus
    /// anything the index no longer has (the desktop's `resume_playlists`).
    private func loadPersistedState() {
        if let data = try? Data(contentsOf: sidecarsURL),
           let sidecars = try? JSONDecoder().decode([String: Sidecar].self, from: data) {
            groupIndex = GroupIndex(sidecars: sidecars)
        }
        if let data = try? Data(contentsOf: catalogURL), let saved = try? JSONDecoder().decode(Catalog.self, from: data) {
            catalog = saved
            clipsByPath = Dictionary(uniqueKeysWithValues: saved.clips.map { ($0.path, $0) })
        }
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        favorites = state.favorites
        weird = state.weird
        stats = state.stats
        measuredSeconds = state.measuredSeconds ?? [:]
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
