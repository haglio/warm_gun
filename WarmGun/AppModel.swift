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
    /// Which loop the run is in: the whole browse, one clip, or the current
    /// clip's seed family / action group — the desktop satellite's axes.
    @Published private(set) var loopMode: LoopMode = .all

    /// Clip lengths measured off the cached files, path-keyed — the real
    /// pCloud listing carries no durations, so the phone learns them itself.
    private var measuredSeconds: [String: Double] = [:]
    /// The seed/action grouping over the metadata sidecars, refreshed once per
    /// launch in the background; empty until the first fetch lands.
    @Published private var groupIndex = GroupIndex(sidecars: [:])
    /// The playback weights off those same sidecars — what BOTH apps did with
    /// each clip, summed and stamped by Evolver. Neutral until they land.
    private var weights = WatchWeights()
    /// The corpus both are built from, kept so a refresh can fold into it. A
    /// branch of the mirror that fails to list contributes nothing that run,
    /// and replacing rather than folding would make its silence erase the lane.
    private var sidecars: [String: Sidecar] = [:]
    private var refreshedMetadata = false
    /// A fetch that failed is tried again, a minute later, a few times: a
    /// launch into a bad moment on the network used to cost the whole run its
    /// groups, since nothing asked again until the next launch.
    private var metadataAttempts = 0
    private var genauFlicksFolder: String?
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
    private var cached: Set<String> = []
    @Published private(set) var lastProblem: String?
    @Published private(set) var loginForm = LoginState()

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
    private var client: PCloudClient?
    private var prefetcher: Prefetcher?
    private var eventPump: Task<Void, Never>?
    private var tracker = WatchTracker()
    /// The clip actually on the glass — not `session.current`, which runs
    /// ahead of the screen whenever a download is still in flight. Every watch
    /// sample and journal line is labeled with this, never with the session.
    @Published private(set) var showing: String?
    private var planGeneration = 0
    private var fetchFailures = FetchFailures()
    private var persistTask: Task<Void, Never>?
    private var clipsByPath: [String: Clip] = [:]
    private var rng = SystemRandomNumberGenerator()
    /// A browse/filter change whose new clip is not on disk yet must VISIBLY
    /// take effect: the old picture clears to the spinner instead of looping
    /// on as if the switch did nothing. Nav stalls keep the old picture — a
    /// fast tap run reads better over motion than over black.
    private var clearOnNextWait = false
    private var noticeTask: Task<Void, Never>?
    private var launched = false
    /// Nothing is written over the state files until they have been read:
    /// a step-aside in the first instant of a launch must not save an empty
    /// run over the one on disk.
    private var stateLoaded = false
    private var syncInFlight: Task<Void, Never>?
    private var syncWanted = false

    init(stateDirectory: URL = AppModel.defaultStateDirectory, cache: ClipCache? = nil) {
        // A bundle with no overlay is ordinary — the app is meant to run without
        // one. A bundle WITH an overlay it cannot read is not: it falls back to
        // the same empty value, so the lanes and every act button vanish and
        // nothing says why. That happened, on a phone, because the file spoke a
        // vocabulary this build did not have; it is reported now rather than
        // swallowed.
        var overlayProblem: String?
        if let url = Bundle.main.url(forResource: "content.local", withExtension: "json") {
            do {
                overlay = try JSONDecoder().decode(ContentOverlay.self, from: Data(contentsOf: url))
            } catch {
                overlay = .empty
                overlayProblem = "Content overlay unreadable — no lanes and no act buttons: "
                    + error.localizedDescription
            }
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
        // The library follows the physical rotation, where there is one.
        Platform.observeRotation { [weak self] landscape in self?.deviceRotated(landscape: landscape) }
        engine.onProgress = { [weak self] fraction in self?.progressed(fraction) }
        engine.onItemFailed = { [weak self] url in self?.itemFailed(url) }
        lastProblem = overlayProblem
    }

    nonisolated static var defaultStateDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("State", isDirectory: true)
    }

    // MARK: - lifecycle

    /// The window's first appearance. A Mac window can be closed and opened
    /// again, which places the view again; the run must not start twice.
    func launch() async {
        guard !launched else { return }
        launched = true
        await start()
    }

    func start() async {
        cached = await cache.cachedPaths()
        loadPersistedState()
        guard let token = Keychain.token() else { phase = .needsLogin; return }
        do {
            try connect(token: token)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        // Lines the last run never got to upload — a Mac is quit from the
        // front as often as not, with no step-aside to upload on.
        if journalDirty { Task { await syncWithCloud() } }
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
            if !rebuildIfStale() { sync() }
            Task { await index() }
        }
    }

    /// True on success, so the form knows whether to clear the password or
    /// keep it for another try.
    func login(username: String, password: String, code: String) async -> Bool {
        settings.username = username
        Keychain.storePending(password: password)
        do {
            let response: LoginResponse
            switch loginForm.attempt(code: code) {
            case .secondFactor(let token, let code, let isRecovery):
                response = try await PCloudClient.tfaLogin(apiHost: apiHost, token: token,
                                                           code: code, isRecovery: isRecovery)
            case .password(let code):
                response = try await PCloudClient.login(apiHost: apiHost, username: username,
                                                        password: password, code: code)
            }
            Keychain.store(token: response.auth)
            guard Keychain.token() != nil else {
                lastProblem = "The Keychain refused to store the token"
                return false
            }
            lastProblem = nil
            loginForm = LoginState()
            Keychain.forgetPending()
            await start()
            return true
        } catch let refusal as PCloudError {
            lastProblem = loginForm.refused(by: refusal)
            return false
        } catch {
            lastProblem = error.localizedDescription
            return false
        }
    }

    /// Ask pCloud to deliver a code: by SMS, or pushed as a notification to
    /// every OTHER logged-in pCloud app (the drive on the Mac or PC).
    func sendTFACode(viaSMS: Bool) async {
        guard let token = loginForm.challengeToken else { return }
        do {
            try await PCloudClient.sendTFACode(apiHost: apiHost, token: token, viaSMS: viaSMS)
            lastProblem = viaSMS ? "Code sent by SMS." : "Code sent — check the pCloud app on your other machines."
        } catch {
            lastProblem = error.localizedDescription
        }
    }

    func logout() {
        Keychain.forget()
        UserDefaults.standard.removeObject(forKey: Self.journalUploadedKey)
        eventPump?.cancel()
        client = nil
        prefetcher = nil
        engine.clear()
        phase = .needsLogin
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

    /// A development run against the stand-in server is pointed at it from
    /// the launch environment; everything else goes where the settings say.
    private var apiHost: String { Platform.developmentAPIHost ?? settings.apiHost }

    private func connect(token: String) throws {
        let client = try PCloudClient(apiHost: apiHost, auth: token)
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
            fetchFailures.fetched()
            cached.insert(path)
            measureDuration(of: path)
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
            guard path == waitingFor else { return }
            switch fetchFailures.failed(attempts: attempts) {
            case .skip:
                flash("Skipping — clip won't fetch", favorite: false)
                session.step(1)
                sync()
            case .hold:
                lastProblem = "pCloud unreachable — holding here and retrying"
            case .keepWaiting:
                break
            }
        case .evicted(let paths):
            cached.subtract(paths)
        }
    }

    // MARK: - the index

    func index() async {
        guard let client else { return }
        if catalog == nil { phase = .indexing }
        do {
            var files = try await client.listLibrary(path: settings.libraryPath)
            // A missing Genau folder is fine; the source simply contributes
            // nothing.
            if let genauPath = LibraryPaths.genauPath(forLibrary: settings.libraryPath),
               let genau = try? await client.folderSkeleton(path: genauPath),
               let folder = LibraryPaths.genauFlicksFolder(in: genau),
               let flicks = try? await client.listLibrary(path: genauPath + "/" + folder) {
                genauFlicksFolder = folder
                files += flicks.map { $0.prefixed(LibraryPaths.genauPrefix) }
            }
            // The real scenes: the non-AI library, the AI folder's sibling.
            if let nonAIPath = LibraryPaths.nonAIPath(forLibrary: settings.libraryPath),
               let scenes = try? await client.listLibrary(path: nonAIPath) {
                files += scenes.map { $0.prefixed(LibraryPaths.nonAIPrefix) }
            }
            let fresh = Catalog(files: files)
            carryFlatGenauNames(to: Set(fresh.clips.map(\.path)))
            let changed = fresh != catalog
            catalog = fresh
            clipsByPath = Dictionary(uniqueKeysWithValues: fresh.clips.map { ($0.path, $0) })
            if changed { persistCatalog() }
            phase = .ready
            refreshMetadata()
            if !rebuildIfStale(), changed {
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

    /// What this phone remembers of a Genau flick by its name from before
    /// Genau's flicks folder split into 2D and VR, carried to where the flick is.
    private func carryFlatGenauNames(to paths: Set<String>) {
        let before = (weird, favorites)
        weird = LibraryPaths.rekeyedFlatGenau(weird, against: paths)
        favorites.rekeyFlatGenau(against: Set(paths.compactMap(LibraryPaths.favoriteKey(forClip:))))
        if before != (weird, favorites) { persistState() }
    }

    /// The sidecar corpus — every branch of the metadata mirror, fetched as one
    /// zip apiece and kept beside the state files; the launch's copy serves
    /// until the fetch lands.
    private func refreshMetadata() {
        guard !refreshedMetadata, let client, let catalog else { return }
        refreshedMetadata = true
        metadataAttempts += 1
        let libraryPath = settings.libraryPath
        let flicksFolder = self.genauFlicksFolder
        let clipPaths = catalog.clips.map(\.path)
        Task {
            let survey = await MetadataFetcher.survey(client: client, libraryPath: libraryPath,
                                                      genauFlicksFolder: flicksFolder, clipPaths: clipPaths)
            guard !survey.branches.isEmpty else {
                lastProblem = "Metadata: no branch of the metadata mirror answered"
                MetadataFetcher.log.error("no branch of the metadata mirror answered")
                retryMetadataLater()
                return
            }
            let stored = UserDefaults.standard.string(forKey: Self.metadataFingerprintKey)
            if survey.fingerprint == stored, !groupIndex.isEmpty {
                MetadataFetcher.log.notice("mirror unchanged, the corpus on disk serves")
                return
            }
            let fetched = await MetadataFetcher.fetchSidecars(client: client, branches: survey.branches)
            guard !fetched.isEmpty else {
                lastProblem = "Metadata: the metadata folders came back empty"
                MetadataFetcher.log.error("the metadata folders came back empty")
                retryMetadataLater()
                return
            }
            MetadataFetcher.log.notice("adopting \(fetched.count) sidecars")
            // Folded in, never substituted: a branch that did not answer this
            // run keeps whatever it contributed to the last one.
            adopt(sidecars: sidecars.merging(fetched) { _, new in new })
            // A run that matched nothing is a dead end this corpus can end —
            // the favorites switch before any favorite had arrived is exactly
            // that screen. A run in progress is left alone: a background
            // refresh must never reshuffle what is playing.
            if session.playlist.isEmpty { rebuild(startAtTop: true) }
            guard let data = try? JSONEncoder().encode(sidecars),
                  (try? data.write(to: sidecarsURL, options: .atomic)) != nil else { return }
            if survey.isComplete(fetched) {
                UserDefaults.standard.set(survey.fingerprint, forKey: Self.metadataFingerprintKey)
            }
        }
    }

    private static let metadataFingerprintKey = "warm-gun.metadata-fingerprint"

    private func retryMetadataLater() {
        guard metadataAttempts < 5 else {
            MetadataFetcher.log.error("giving up on the metadata until the next launch")
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(60))
            refreshedMetadata = false
            refreshMetadata()
        }
    }

    /// Everything the corpus decides, decided in one place: the groups the loop
    /// buttons walk, the weights the shuffle draws on, and which clips the
    /// desktop is holding.
    ///
    /// The favorites only ever gain here, exactly as a `favs.csv` import does,
    /// and never gain back a stem this phone has let go of: the flag is a
    /// snapshot from the last time the stage ran, so taking it as the whole
    /// truth would undo every favorite made on the phone since, and taking it
    /// blindly would undo every unfavorite (`Favorites.adopt`).
    private func adopt(sidecars corpus: [String: Sidecar]) {
        sidecars = corpus
        groupIndex = GroupIndex(sidecars: corpus)
        weights = WatchWeights(sidecars: corpus)
        let flagged = Set(corpus.filter(\.value.favorite).keys.compactMap(LibraryPaths.favoriteKey(forClip:)))
        let before = favorites
        // The corpus is only ever as complete as the branches that answered, so
        // it says nothing about a clip it does not hold: `covering` is what it
        // could have spoken for, and a refusal outside that is kept.
        favorites.adopt(flagged: flagged,
                        covering: Set(corpus.keys.compactMap(LibraryPaths.favoriteKey(forClip:))))
        if favorites != before { persistState() }
    }

    /// Builds the browse from the index and hands it to the session. A change
    /// of filter keeps the clip on screen when it survives (the desktop's
    /// `replace_playlist`); a new order starts from the top. A filter that
    /// matches nothing leaves the current playlist in place rather than
    /// blanking the screen.
    private func rebuild(startAtTop: Bool) {
        guard let catalog else { return }
        let playlist = PlaylistBuilder.build(catalog: catalog, options: settings.browse,
                                             favoriteKeys: favorites.held, weird: weird,
                                             weights: weights, measuredSeconds: measuredSeconds,
                                             overlay: overlay, acts: groupIndex.actsByPath,
                                             kinds: groupIndex.kindsByPath, rng: &rng)
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

    private func rebuildIfStale() -> Bool {
        switch session.resumption(currentFits: currentClipFits()) {
        case .startFromTop: rebuild(startAtTop: true)
        case .rebuildAroundCurrent: rebuild(startAtTop: false)
        case .keep: return false
        }
        return true
    }

    private func currentClipFits() -> Bool {
        guard let current = session.current, let clip = clipsByPath[current] else { return true }
        return PlaylistBuilder.playsInOrientation(clip, options: settings.browse,
                                                  recorded: groupIndex.kindsByPath[current],
                                                  measuredSeconds: measuredSeconds[current], overlay: overlay)
    }

    /// The phone was turned: the browse follows the screen, portrait clips
    /// upright and landscape clips wide, with no switch to remember. A
    /// laptop's screen never turns, and its window's shape says nothing about
    /// which library is wanted — there the keys decide, through the road below.
    func deviceRotated(landscape: Bool) {
        guard Platform.screenTurns else { return }
        setOrientation(landscape ? .landscape : .portrait)
    }

    /// Which library plays: the P and L keys' road on a Mac, the rotation's
    /// on a phone.
    func setOrientation(_ orientation: Orientation) {
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
            _ = favorites.remove(path: path)
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
            dropFromCache(path)
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
            guard let current = session.current, let clips = groupIndex.group(mode, of: current) else { return }
            settings.loopClip = false
            if groupIndex.canLoop(mode, from: current) {
                session.setLocked(false)
                session.replacePlaylist(clips)
                loopMode = mode
                flash("\(mode == .seed ? "Seed" : "Action") loop — \(clips.count) clips", favorite: false)
            } else {
                session.setLocked(true)
                loopMode = .all
                flash("Locked — no group", favorite: true)
            }
            sync()
        }
    }

    /// Whether the Loop control's *mode* has anything to loop from the clip on
    /// screen.
    func canLoop(_ mode: LoopMode) -> Bool {
        session.current.map { groupIndex.canLoop(mode, from: $0) } ?? false
    }

    /// The E key: one step clockwise around the Loop control (the Kit's
    /// `LoopCycle`), each stop meaning what the control's segment means.
    func cycleLoop() {
        guard let current = session.current else { return }
        setLoop(LoopCycle.next(after: loopMode) { groupIndex.canLoop($0, from: current) })
    }

    // MARK: - playback plumbing

    /// The single place the screen and the prefetch window are brought in line
    /// with the session.
    private func sync() {
        guard let prefetcher else { return }
        planGeneration += 1
        let generation = planGeneration
        let plan = PrefetchPlanner.plan(playlist: session.playlist, index: session.index,
                                        ahead: settings.prefetchAhead, back: settings.prefetchBehind)
            .filter { clipsByPath[$0].map { !$0.streams } ?? true }
        let clips = clipsByPath
        Task { await prefetcher.replan(plan, clips: clips, generation: generation) }
        guard let current = session.current else {
            engine.clear()
            showing = nil
            waitingFor = nil
            return
        }
        let loop = session.locked || settings.loopClip
        if let clip = clipsByPath[current], clip.streams, !cached.contains(current) {
            // Stream a scene straight off its link: playback starts on the
            // first ranges, nothing lands in the cache, nothing is staged
            // after it (the next clip syncs when this one finishes).
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
                // but nothing may stay queued after it — a stale roll-on
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

    /// The clip played out with nothing staged after it — a streamed scene,
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
        dropFromCache(path)
        lastProblem = "Unplayable clip — \((path as NSString).lastPathComponent)"
        if path == showing {
            flash("Skipping unplayable clip", favorite: false)
            session.step(1)
        }
        sync()
    }

    private func dropFromCache(_ path: String) {
        cached.remove(path)
        Task { await cache.remove([path]) }
    }

    private func progressed(_ fraction: Double) {
        // While a download is in flight the engine is replaying the PREVIOUS
        // clip under a spinner; those frames speak for nothing the session
        // points at, so they are not sampled at all.
        guard waitingFor == nil, let path = showing else { return }
        for (event, eventPath) in tracker.sample(path: path, fraction: fraction, now: Date()) {
            journal(event.rawValue, eventPath)
        }
    }

    /// The app is back in front; AVPlayer does not resume by itself. A clip
    /// he paused stays paused — a return to the app is not a tap.
    func becameActive() {
        if !paused { engine.resume() }
    }

    /// The app has stepped aside: the picture stops — a run nobody is
    /// watching must not book completions — what is pending is written, and
    /// the journal leaves for the cloud.
    func steppedAside() {
        engine.pause()
        flushState()
        Task { await syncWithCloud() }
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

    /// How much of the journal has reached the cloud, kept across launches so
    /// a run can tell whether lines are still waiting: the file only ever
    /// grows, so its size against the size last uploaded is the whole answer.
    private static let journalUploadedKey = "warm-gun.journal-uploaded-bytes"

    private var journalBytes: Int {
        (try? FileManager.default.attributesOfItem(atPath: journalURL.path)[.size] as? Int) ?? 0
    }

    private var journalDirty: Bool {
        journalBytes != UserDefaults.standard.integer(forKey: Self.journalUploadedKey)
    }

    private func journal(_ event: String, _ path: String) {
        let line = Journal.line(JournalEvent(t: Int(Date().timeIntervalSince1970), event: event, path: path)) + "\n"
        if let handle = try? FileHandle(forWritingTo: journalURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: journalURL)
        }
    }

    /// Pushes the journal to the sync folder and pulls a `favs.csv` from it if
    /// one is there. Called when the app steps aside and at a launch with
    /// lines waiting; never in the way of playback.
    ///
    /// One at a time: two whole-file uploads in flight can land in either
    /// order, and the size recorded last would then overstate what the cloud
    /// holds. A call during a sync asks for one more after it.
    func syncWithCloud() async {
        if syncInFlight != nil {
            syncWanted = true
            return
        }
        repeat {
            syncWanted = false
            let sync = Task { await performCloudSync() }
            syncInFlight = sync
            await sync.value
            syncInFlight = nil
        } while syncWanted
    }

    private func performCloudSync() async {
        guard let client, !settings.syncFolder.isEmpty else { return }
        // The caller is usually the step-aside transition, which on the phone
        // would suspend the app mid-upload.
        let release = Platform.holdForBackgroundWork()
        defer { release() }
        do {
            try await client.createFolderIfNotExists(path: settings.syncFolder)
            if journalDirty, let data = try? Data(contentsOf: journalURL) {
                try await client.upload(data: data, folderPath: settings.syncFolder, filename: Platform.journalFileName)
                UserDefaults.standard.set(data.count, forKey: Self.journalUploadedKey)
            }
            let files = try await client.listLibrary(path: settings.syncFolder)
            if let favs = files.first(where: { $0.path.lowercased() == "favs.csv" }) {
                let link = try await client.fileLink(fileID: favs.fileID)
                guard let url = link.url else { return }
                let tmp = try await client.download(url)
                defer { try? FileManager.default.removeItem(at: tmp) }
                let text = try String(contentsOf: tmp, encoding: .utf8)
                let before = favorites
                // Complete by construction — the whole file, so every refusal
                // it does not name is one the desktop has settled.
                favorites.adopt(flagged: FavsCSV.keys(in: text))
                if favorites != before { persistState() }
            }
        } catch {
            lastProblem = "Cloud sync: \(error.localizedDescription)"
        }
    }

    // MARK: - persistence

    private struct PersistedState: Codable {
        var favorites: Favorites
        var weird: Set<String>
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
        guard stateLoaded else { return }
        let state = PersistedState(favorites: favorites, weird: weird,
                                   playlist: session.playlist, index: session.index,
                                   locked: session.locked, measuredSeconds: measuredSeconds)
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
        restoreSession()
        // Last of the three, so the corpus folds INTO the favorites just
        // restored rather than being overwritten by them.
        if let data = try? Data(contentsOf: sidecarsURL),
           let sidecars = try? JSONDecoder().decode([String: Sidecar].self, from: data) {
            adopt(sidecars: sidecars)
        }
        stateLoaded = true
    }

    private func restoreSession() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        favorites = state.favorites
        weird = state.weird
        measuredSeconds = state.measuredSeconds ?? [:]
        session = Session(restoring: state.playlist, at: state.index, locked: state.locked ?? false,
                          keeping: Set(clipsByPath.keys))
    }

    /// Auto-advance persists through here: at most one write per fifteen
    /// seconds, on the tail edge, because every write is the whole playlist
    /// and the favorites JSON-encoded on the main actor. Gestures persist
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
