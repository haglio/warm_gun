import AVFoundation
import Foundation
import WarmGunKit

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case needsLogin
        case needsLibrary
        case indexing
        case ready
        case failed(String)
    }

    struct Message: Equatable {
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
    @Published private(set) var trash: Set<String> = []
    @Published private(set) var loopMode: LoopMode = .all

    /// pCloud's listing carries no durations, so the phone measures them off the cached files.
    private var measuredSeconds: [String: Double] = [:]
    @Published private var groupIndex = GroupIndex(sidecars: [:])
    private var weights = WatchWeights()
    private var corpus = SidecarCorpus()
    private var refreshedMetadata = false
    private var metadataAttempts = 0
    private var genauFlicksFolder: String?
    @Published private(set) var message: Message?
    @Published private(set) var paused = false
    /// AVPlayer's rate reads as playing through a big file's black first seconds; the layer does not.
    @Published private(set) var layerReady = false
    @Published private(set) var buffering = false
    private var bufferingTask: Task<Void, Never>?
    @Published private(set) var waitingFor: String?
    private var cached: Set<String> = []
    @Published private(set) var lastProblem: String?
    @Published private(set) var loginForm = LoginState()

    private let engine = PlayerEngine()
    var player: AVPlayer { engine.player }
    private let cache: VideoCache
    private let stateDirectory: URL
    let overlay: ContentOverlay
    private var client: PCloudClient?
    private var prefetcher: Prefetcher?
    private var eventPump: Task<Void, Never>?
    private var tracker = WatchTracker()
    @Published private(set) var showing: String?
    private var planGeneration = 0
    private var fetchFailures = FetchFailures()
    private var persistTask: Task<Void, Never>?
    private var videosByPath: [String: Video] = [:]
    private var rng = SystemRandomNumberGenerator()
    private var clearOnNextWait = false
    private var messageTask: Task<Void, Never>?
    private var launched = false
    private var stateLoaded = false
    private var syncInFlight: Task<Void, Never>?
    private var syncWanted = false

    init(stateDirectory: URL = AppModel.defaultStateDirectory, cache: VideoCache? = nil) {
        var overlayProblem: String?
        if let url = Bundle.main.url(forResource: "content.local", withExtension: "json") {
            do {
                overlay = try JSONDecoder().decode(ContentOverlay.self, from: Data(contentsOf: url))
            } catch {
                overlay = .empty
                overlayProblem = "Content overlay unreadable — no lanes: "
                    + error.localizedDescription
            }
        } else {
            overlay = .empty
        }
        self.stateDirectory = stateDirectory
        self.cache = cache ?? VideoCache(directory: VideoCache.defaultDirectory)
        settings = Settings.load()
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        engine.onAdvanced = { [weak self] url in self?.advanced(to: url) }
        engine.onFinished = { [weak self] in self?.finished() }
        engine.onBuffering = { [weak self] stalled in self?.buffering(stalled) }
        Platform.observeRotation { [weak self] landscape in self?.deviceRotated(landscape: landscape) }
        engine.onProgress = { [weak self] fraction in self?.progressed(fraction) }
        engine.onItemFailed = { [weak self] url in self?.itemFailed(url) }
        lastProblem = overlayProblem
    }

    nonisolated static var defaultStateDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("State", isDirectory: true)
    }

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
        if journalDirty { Task { await syncWithCloud() } }
        if settings.libraryPath.isEmpty {
            phase = .indexing
            do {
                guard let client, let found = try await Self.discoverLibrary(client: client) else {
                    lastProblem = "No folder holding both 0_inbox and 1_sorted found in this account"
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

    /// pCloud refuses a recursive listing of the root (error 1101), so the walk starts shallow there
    /// and recurses per top-level folder.
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
                Keychain.forget()
                phase = .needsLogin
                return
            }
            guard path == waitingFor else { return }
            switch fetchFailures.failed(attempts: attempts) {
            case .skip:
                flash("Skipping — video won't fetch", favorite: false)
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

    func index() async {
        guard let client else { return }
        if catalog == nil { phase = .indexing }
        do {
            var files = try await client.listLibrary(path: settings.libraryPath)
            if let genauPath = LibraryPaths.genauPath(forLibrary: settings.libraryPath),
               let genau = try? await client.folderSkeleton(path: genauPath),
               let folder = LibraryPaths.genauFlicksFolder(in: genau),
               let flicks = try? await client.listLibrary(path: genauPath + "/" + folder) {
                genauFlicksFolder = folder
                files += flicks.map { $0.prefixed(LibraryPaths.genauPrefix) }
            }
            if let nonAIPath = LibraryPaths.nonAIPath(forLibrary: settings.libraryPath),
               let scenes = try? await client.listLibrary(path: nonAIPath) {
                files += scenes.map { $0.prefixed(LibraryPaths.nonAIPrefix) }
            }
            let fresh = Catalog(files: files)
            carryFlatGenauNames(to: Set(fresh.videos.map(\.path)))
            let changed = fresh != catalog
            catalog = fresh
            videosByPath = Dictionary(uniqueKeysWithValues: fresh.videos.map { ($0.path, $0) })
            if changed { persistCatalog() }
            phase = .ready
            refreshMetadata()
            if !rebuildIfStale(), changed {
                let known = Set(fresh.videos.map(\.path))
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

    private func carryFlatGenauNames(to paths: Set<String>) {
        let before = (trash, favorites)
        trash = LibraryPaths.rekeyedFlatGenau(trash, against: paths)
        favorites.rekeyFlatGenau(against: Set(paths.compactMap(LibraryPaths.favoriteKey(forVideo:))))
        if before != (trash, favorites) { persistState() }
    }

    private func refreshMetadata() {
        guard !refreshedMetadata, let client, let catalog else { return }
        refreshedMetadata = true
        metadataAttempts += 1
        let libraryPath = settings.libraryPath
        let flicksFolder = self.genauFlicksFolder
        let videoPaths = catalog.videos.map(\.path)
        Task {
            let branches = await MetadataFetcher.survey(client: client, libraryPath: libraryPath,
                                                      genauFlicksFolder: flicksFolder, videoPaths: videoPaths)
            guard !branches.isEmpty else {
                lastProblem = "Metadata: no branch of the metadata mirror answered"
                MetadataFetcher.log.error("no branch of the metadata mirror answered")
                retryMetadataLater()
                return
            }
            var missed = 0
            for branch in branches {
                let stale = corpus.stale(in: branch)
                MetadataFetcher.log.notice("\(branch.path, privacy: .private): \(stale.count) sidecars to fetch")
                for start in stride(from: 0, to: stale.count, by: Self.sidecarsPerSave) {
                    let batch = Array(stale[start..<min(start + Self.sidecarsPerSave, stale.count)])
                    let fetched = await MetadataFetcher.fetch(client: client, files: batch)
                    var grown = corpus
                    for file in batch {
                        guard let record = fetched[file.path],
                              let video = branch.index.videosByListedSidecar[file.path] else { continue }
                        grown.keep(record, for: video, written: file.modified)
                    }
                    missed += batch.count - fetched.count
                    adopt(grown)
                    if session.playlist.isEmpty { rebuild(startAtTop: true) }
                    try? JSONEncoder().encode(corpus).write(to: sidecarsURL, options: .atomic)
                }
            }
            if missed > 0 {
                lastProblem = "Metadata: \(missed) sidecars would not download"
                MetadataFetcher.log.error("\(missed) sidecars would not download")
                retryMetadataLater()
            }
        }
    }

    private static let sidecarsPerSave = 100

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

    private func adopt(_ corpus: SidecarCorpus) {
        self.corpus = corpus
        let sidecars = corpus.sidecars
        groupIndex = GroupIndex(sidecars: sidecars)
        weights = WatchWeights(sidecars: sidecars)
        let flagged = Set(sidecars.filter(\.value.favorite).keys.compactMap(LibraryPaths.favoriteKey(forVideo:)))
        let before = favorites
        favorites.adopt(flagged: flagged,
                        covering: Set(sidecars.keys.compactMap(LibraryPaths.favoriteKey(forVideo:))))
        if favorites != before { persistState() }
    }

    private func rebuild(startAtTop: Bool) {
        guard let catalog else { return }
        let playlist = PlaylistBuilder.build(catalog: catalog, options: settings.filters,
                                             favoriteKeys: favorites.held, trash: trash,
                                             weights: weights, measuredSeconds: measuredSeconds,
                                             overlay: overlay, labels: groupIndex.labelsByPath,
                                             recordedTypes: groupIndex.typesByPath, rng: &rng)
        if playlist.isEmpty {
            session = Session(playlist: [])
            sync()
            return
        }
        let before = session.current
        if startAtTop {
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

    func tap(_ action: TapAction) {
        switch action {
        case .previous: previous()
        case .next: next()
        case .trash: sendToTrash()
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
        switch session.resumption(currentFits: currentVideoFits()) {
        case .startFromTop: rebuild(startAtTop: true)
        case .rebuildAroundCurrent: rebuild(startAtTop: false)
        case .keep: return false
        }
        return true
    }

    private func currentVideoFits() -> Bool {
        guard let current = session.current, let video = videosByPath[current] else { return true }
        return PlaylistBuilder.playsInShape(video, options: settings.filters,
                                                  recorded: groupIndex.typesByPath[current],
                                                  measuredSeconds: measuredSeconds[current], overlay: overlay)
    }

    func deviceRotated(landscape: Bool) {
        guard Platform.screenTurns else { return }
        setShape(landscape ? .landscape : .portrait)
    }

    func setShape(_ shape: VideoShape) {
        guard settings.filters.shape != shape else { return }
        var filters = settings.filters
        filters.shape = shape
        update(filters: filters)
    }

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

    func sendToTrash() {
        guard let path = session.current else { return }
        tracker.noteDiscard()
        if favorites.contains(path: path) {
            _ = favorites.remove(path: path)
            journal("unfavorite", path)
            session.step(1)
            flash("Unfavorited", favorite: true)
        } else {
            trash.insert(path)
            journal("trash", path)
            if session.playlist.count <= 1 {
                session = Session(playlist: [])
            } else {
                _ = session.discard()
            }
            flash("Sent to Trash", favorite: false)
            dropFromCache(path)
            Task { await moveUpscaleToTrash(path) }
        }
        persistState()
        sync()
    }

    private func moveUpscaleToTrash(_ path: String) async {
        guard let client, let upscale = LibraryPaths.upscalePath(forOriginal: path),
              let kino = LibraryPaths.kinoPath(forLibrary: settings.libraryPath) else { return }
        let trashDir = kino + "/" + LibraryPaths.kinoTrashFolder
        do {
            try await client.createFolderIfNotExists(path: trashDir)
            try await client.renameFile(path: kino + "/" + upscale,
                                         toPath: trashDir + "/" + (upscale as NSString).lastPathComponent)
        } catch {
            lastProblem = "Could not move the upscale to trash: \(error.localizedDescription)"
        }
    }

    func update(filters: Filters) {
        let orderChanged = filters.latest != settings.filters.latest
        settings.filters = filters
        if loopMode == .seed || loopMode == .action { loopMode = .all }
        rebuild(startAtTop: orderChanged)
    }

    func setLoop(_ mode: LoopMode) {
        switch mode {
        case .all, .single:
            let wasGrouped = loopMode == .seed || loopMode == .action
            loopMode = mode
            settings.loopVideo = mode == .single
            if wasGrouped {
                rebuild(startAtTop: false)
                flash("Loop off", favorite: false)
            } else {
                sync()
            }
        case .seed, .action:
            guard let current = session.current, let videos = groupIndex.group(mode, of: current) else { return }
            settings.loopVideo = false
            if groupIndex.canLoop(mode, from: current) {
                session.setLocked(false)
                session.replacePlaylist(videos)
                loopMode = mode
                flash("\(mode == .seed ? "Seed" : "Action") loop — \(videos.count) videos", favorite: false)
            } else {
                session.setLocked(true)
                loopMode = .all
                flash("Locked — no group", favorite: true)
            }
            sync()
        }
    }

    var labelNames: [String] { groupIndex.labelNames }

    func canLoop(_ mode: LoopMode) -> Bool {
        session.current.map { groupIndex.canLoop(mode, from: $0) } ?? false
    }

    func cycleLoop() {
        guard let current = session.current else { return }
        setLoop(LoopCycle.next(after: loopMode) { groupIndex.canLoop($0, from: current) })
    }

    private func sync() {
        guard let prefetcher else { return }
        planGeneration += 1
        let generation = planGeneration
        let plan = PrefetchPlanner.plan(playlist: session.playlist, index: session.index,
                                        ahead: settings.prefetchAhead, back: settings.prefetchBehind)
            .filter { videosByPath[$0].map { !$0.streams } ?? true }
        let videos = videosByPath
        Task { await prefetcher.replan(plan, videos: videos, generation: generation) }
        guard let current = session.current else {
            engine.clear()
            showing = nil
            waitingFor = nil
            return
        }
        let loop = session.locked || settings.loopVideo
        if let video = videosByPath[current], video.streams, !cached.contains(current) {
            waitingFor = nil
            showing = current
            Task {
                do {
                    let url = try await prefetcher.streamURL(for: video)
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
                engine.clear()
                showing = nil
            } else {
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

    private func advanced(to url: URL) {
        if let staged = session.staged, url.lastPathComponent == VideoCache.fileName(for: staged) {
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

    private func finished() {
        session.advance()
        sync()
    }

    private func itemFailed(_ url: URL) {
        guard let path = session.playlist.first(where: { url.lastPathComponent == VideoCache.fileName(for: $0) })
        else { return }
        dropFromCache(path)
        lastProblem = "Unplayable video — \((path as NSString).lastPathComponent)"
        if path == showing {
            flash("Skipping unplayable video", favorite: false)
            session.step(1)
        }
        sync()
    }

    private func dropFromCache(_ path: String) {
        cached.remove(path)
        Task { await cache.remove([path]) }
    }

    private func progressed(_ fraction: Double) {
        guard waitingFor == nil, let path = showing else { return }
        for (event, eventPath) in tracker.sample(path: path, fraction: fraction, now: Date()) {
            journal(event.rawValue, eventPath)
        }
    }

    func becameActive() {
        if !paused { engine.resume() }
    }

    func steppedAside() {
        engine.pause()
        flushState()
        Task { await syncWithCloud() }
    }

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
        message = Message(text: text, favorite: favorite)
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    private var journalURL: URL { stateDirectory.appendingPathComponent("warm-gun-journal.jsonl") }

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
        let release = Platform.holdForBackgroundWork()
        defer { release() }
        do {
            try await client.createFolderIfNotExists(path: settings.syncFolder)
            if journalDirty, let data = try? Data(contentsOf: journalURL) {
                try await client.upload(data: data, folderPath: settings.syncFolder, filename: Platform.journalFileName)
                UserDefaults.standard.set(data.count, forKey: Self.journalUploadedKey)
            }
        } catch {
            lastProblem = "Cloud sync: \(error.localizedDescription)"
        }
    }

    private struct PersistedState: Codable {
        var favorites: Favorites
        var trash: Set<String>?
        var playlist: [String]
        var index: Int
        var locked: Bool?
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
        let state = PersistedState(favorites: favorites, trash: trash,
                                   playlist: session.playlist, index: session.index,
                                   locked: session.locked, measuredSeconds: measuredSeconds)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    private func loadPersistedState() {
        if let data = try? Data(contentsOf: catalogURL), let saved = try? JSONDecoder().decode(Catalog.self, from: data) {
            catalog = saved
            videosByPath = Dictionary(uniqueKeysWithValues: saved.videos.map { ($0.path, $0) })
        }
        restoreSession()
        foldSavedCorpusIntoRestoredFavorites()
        stateLoaded = true
    }

    private func foldSavedCorpusIntoRestoredFavorites() {
        if let data = try? Data(contentsOf: sidecarsURL),
           let corpus = try? JSONDecoder().decode(SidecarCorpus.self, from: data) {
            adopt(corpus)
        }
    }

    private func restoreSession() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        favorites = state.favorites
        trash = state.trash ?? []
        measuredSeconds = state.measuredSeconds ?? [:]
        session = Session(restoring: state.playlist, at: state.index, locked: state.locked ?? false,
                          keeping: Set(videosByPath.keys))
    }

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
