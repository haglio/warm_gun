# Warm Gun — the phone satellite

Warm Gun does what one of Fun Time's Satellite Funestras does — an endless,
silent, auto-advancing run of the library's clips with four gestures — on an
iPhone away from home, and on the owner's Mac. No OSR2, no voice, no
dashboard. Kickoff was 2026-08-23; this file holds the decisions in force,
cut to them on 2026-10-30, and the code's history holds the rest. Change a
decision with the owner, not alone.

## What it plays

- **Three lanes, one catalog.** The AI library's *originals* —
  `1_sorted/<source>/<orientation>/<stem>.mp4`, about 2 MB of H.264 each —
  not the Topaz upscales the desktop satellites play: the owner asked for
  "the non-upscaled ones", and every original has exactly one upscale, so
  nothing is lost. Beside them, Genau's 2D flicks and the real scenes of
  the non-AI library, filed in the catalog under `genau/clips/` and
  `non_AI/`; a scene's processed copies and upscales stay out.
- **The library is found, never typed.** It is the one folder in the
  account holding both pipeline stages, `1_sorted` and `2_outbox`, so a
  folders-only listing finds it; a parked copy under an underscore folder
  loses to the live tree. pCloud refuses a recursive listing of the root
  (1101), so the hunt descends one shallow level at a time from there.
  Genau's flicks folder is found the same way, by its shape.
- **One recursive `listfolder` per lane** becomes a `Catalog` persisted on
  the device, refreshed in the background at each launch. Every rebuild is
  in memory, with no network on a tap. A refresh never reshuffles the run in
  progress: what left the library is pruned, new arrivals join at the next
  rebuild he asks for.
- **What kind a clip is comes from the desktop.** Evolver records one of
  `genau_flick` / `excerpt` / `short` / `full_length` on every video's
  metadata sidecar (`video.type`), and `ClipType` is that field's
  vocabulary, so a clip is the same kind here as in Fun Time. For a clip
  whose sidecar has not arrived, the overlay's lanes, the source folder and
  a running time stand in, in that order. The act a clip records
  (`video.action`) is a different axis, the act buttons'; it never decides
  a kind.
- **What the repo cannot name lives in a git-ignored overlay.** The non-AI
  lanes' folder names and the act buttons are library vocabulary, so they
  ship in `WarmGun/content.local.json`, bundled at build time and never
  committed (`content.example.json` documents the shape). Without it the
  app plays with no lanes and no act buttons, which looks like a
  regression, so the install scripts refuse to build without it when the
  primary checkout has one.

## Playback

- **Small clips are fetched whole, big ones stream.** A clip of 25 MB or
  less is downloaded into the on-device cache before it plays: most of the
  originals put `moov` after `mdat`, which would cost a tail round-trip
  before the first frame, and a whole 2 MB file is a second or two. A real
  scene runs to hundreds of megabytes and usually carries its index up
  front, so it streams straight off its link and is never planned for the
  cache.
- **The cache is keyed by file, not by position.** It lives in Application
  Support, which iOS does not empty under pressure, excluded from backups
  because the library is the backup, under a 2 GB least-recently-used cap.
- **A deep, two-sided prefetch window.** The playlist is known in advance,
  so the past is as fetchable as the future: twelve clips ahead and three
  back stay resident, fetched nearest first, two forward for every one
  back, three at a time, re-planned on every change and canceling what
  fell out of the window. A size that does not match the listing is not the
  clip (travel wifi answers with captive portals) and never reaches the
  player.
- **Links are kept until they die.** `getfilelink` URLs expire; they are
  cached by file id (the weird gesture renames paths) until a minute before
  expiry, and a fetch refused on a link the cache believed in means
  "re-link and retry", never "the clip is gone".
- **The player holds two clips**, the one on screen and the one staged
  after it, the same two-entry window the desktop satellite keeps in mpv,
  so auto-advance is a roll-on. Navigating to a clip not yet on disk keeps
  the old picture looping under a spinner; a change of filters clears it,
  so the switch is seen to land.
- **A clip that will not come is stepped past only on its third refusal**,
  and after five such skips in a row the run holds and keeps retrying: a
  dead network must not sprint it silently through the playlist. A clip the
  player refuses outright leaves the disk and is skipped.
- **The video is muted and mixes with other audio**, so it never pauses
  what else the phone is playing.

## Gestures and the controls

- **Taps** fire at once, in a three-by-three reading of the screen: the
  left third is previous, the right third next, and the middle column is
  weird above, lock below, and the controls in the center. Two taps in the
  center pause and play.
- **The controls appear over the picture** at a center tap, or when a
  pointer moves, and go six seconds after the last touch. The type buttons
  Genau, Clips and Full sit top left (Clips takes the shorts and the carved
  scenes in and out together); Shuffle, Latest and Favs top right; the Loop
  control lower left; the act buttons lower right; the four gestures as
  buttons at the edges where their zones are; pause in the center, with the
  clip's file name under it. The login screen appears by itself when a
  login is needed, so the controls have no settings door.
- **The orientation follows the screen.** The phone's library turns with
  the phone; a laptop's screen never turns, so there the P and L keys pick
  the portrait or the landscape library. A pair of buttons on the controls
  came first and read as one more filter, so it went. A Genau flick plays
  either way up.

## Fidelity to the desktop satellite

From `fun_time/command_dispatch.py`, `fun_time/lock.py`, `satellite/session.py`:

- **Next and previous** step the playlist and wrap; previous is the list
  neighbor, not a history stack. Any navigation releases a lock.
- **Lock** toggles. Locking repeats the clip, makes it a favorite and counts
  a `lock` event; unlocking moves on and never unfavorites.
- **Weird** is the two-step demotion. A favorite only loses its star and
  the run moves on ("Unfavorited"). Anything else leaves the run, and its
  upscale moves into `2_outbox/kinda_weird/` through the API's `renamefile`
  ("Marked weird"), to wait there with the original and its sidecar to be
  reviewed, so a weird on the phone is a weird everywhere. It never deletes
  anything. One accepted divergence: `renamefile` replaces a same-named
  file where the desktop's `move_to_weird` walks `__dup1`, `__dup2`…,
  harmless because stems are unique library-wide. The last clip marked
  weird leaves an empty run, which says so, rather than looping a clip just
  rejected.
- **Auto-advance** plays a clip once and rolls on; a lock holds it.
- **The Loop control** has four stops: All, the whole run; 1, every clip
  repeating until tapped (Warm Gun's own); and the desktop's group loops,
  Seed (the clip's act done by its other subjects) and Action (its subject
  doing other acts), grouped over the metadata sidecars exactly as
  `fun_time/media_metadata.py` groups them. A group loop re-seats the
  playlist with the clip on screen first, which never restarts; a group of
  one is no loop, so its stop is grayed out, and on the Mac E steps the four
  clockwise round the control, passing a group stop with nothing to loop.
  Fun Time's E walks three stops with no 1; the owner ruled on 2026-10-16
  that these four are right and Fun Time's cycle is the one to change.
- **Ordering.** Shuffle is the desktop's watch-weighted Efraimidis–Spirakis
  shuffle with probabilistic inclusion; the weight is read, never computed:
  Evolver sums what Fun Time and Warm Gun each completed, skipped and locked
  and stamps the result on every video's sidecar as `watch.weight`
  (`evolver/util/watch.py`), so one formula serves both apps. No weight
  weighs 1. Latest is newest first and carries no weighting, so a new
  arrival surfaces whatever its weight. A filter change keeps the
  clip on screen when it survives (`session.replace_playlist`); a filter
  that matches nothing says so on a blank screen.

## Shared state with the desktop

The desktop's `favs.csv` and `watch_stats.json` live in the fun_time
checkout on the PC, outside pCloud, and `watch_stats.json` prunes any path
not on the writing machine, so Warm Gun writes neither. It keeps its own
favorites and weird marks and appends every event to a journal, one JSON
object per line: `{"t": unix seconds, "event":
"favorite|unfavorite|weird|lock|completion|skip", "path": "<catalog
path>"}`. The journal goes to `/WarmGun` in pCloud, outside the library,
whenever the app steps aside, and at a launch with lines still waiting;
uploads run one at a time, so the size recorded as uploaded is the size the
cloud holds. The phone writes `warm-gun-journal.jsonl` and the Mac
`warm-gun-journal-mac.jsonl`, since Evolver reads every `.jsonl` there.

The return leg arrives on the sidecars. Evolver applies the journals'
favorites and unfavorites to `favs.csv`, through a cursor kept per journal
file, and stamps every video's sidecar with a `watch` block and, for a
favorite, `favorite: true`. Warm Gun reads both: the weight is all its
shuffle draws on, and the flag joins its favorites, only ever adding, since
the flag is a snapshot from the last time the stage ran and would otherwise
undo a favorite made away from home; an unfavorite made here is held until
the desktop agrees. A `favs.csv` dropped into `/WarmGun` is imported the
same way. The sidecars arrive as one `getzip` per branch of the metadata
mirror, falling back to one file at a time; a launch whose survey finds the
mirror unchanged fetches nothing.

## The Mac (2026-10-12)

The same target builds against the macOS SDK. Not Mac Catalyst and not
"Designed for iPhone": the first is a translation layer with its own
quirks, the second needs the Mac in the team's provisioning profile. A
native build is signed with the development certificate alone and runs in
the App Sandbox with a container of its own.

- **One program, one seam.** Every `#if` but `DEBUG` and every UIKit or
  AppKit import lives in `WarmGun/Platform.swift`; a coupling gate counts
  them anywhere else. The app above it asks one vocabulary — does the
  screen turn, hold the display awake, which journal file is mine, is the
  picture in front — and never knows which machine answers.
- **The keyboard is the desktop's.** The arrows mean what they mean on the
  desktop satellite — left previous, right next, up weird, down lock — and
  WASD is the same four for the other hand; E steps the Loop control; space
  and Esc pause and play; P and L pick the library.
- **Full screen on arrival.** The one window (a `Window` scene: no New
  Window, no second run on the one model) has no title bar and takes the
  whole screen the first time it becomes key after the player appears, once,
  so leaving full screen by hand sticks. A fresh install opens on the
  landscape library, the shape of the screen.
- **Stepping aside pauses the picture.** A Mac app is never suspended, so
  the run would play on minimized, covered or on another Space and book
  completions nobody watched. Both machines keep one fact, `Presence` — on
  the phone "not in the background", on the Mac "active and a window
  visible" — and losing it pauses, flushes the state and uploads the
  journal; regaining it resumes, unless he had paused.
- **A debug Mac build is a different app**, `com.cmloegcmluin.warmgun.debug`,
  so a run against the stand-in server has a container, cache, settings and
  journal of its own and a fixture line can never reach the real account.

## Module boundaries (the gates enforce these)

- `WarmGunKit/` — pure Foundation, and every decision that needs no device,
  each tested headlessly: `LibraryPaths` (the lanes, the upscale mapping,
  library discovery), `Catalog` + `Clip`, `PCloudAPI` (requests, responses,
  errors), `LoginState` (the login's next step and its refusals),
  `Playlist` (`ClipType`, the filters, the build), `Session` (the run, and
  what a resumed one keeps), `FetchFailures`, `PrefetchPlanner` (the window
  and eviction), `LinkCache`, `WatchWeights` + `WatchTracker`, `Sidecar` +
  `GroupIndex` + `SidecarIndex` + `MirrorSurvey` (whether the mirror moved,
  and whether a fetch caught all of it), `LoopMode` + `LoopCycle`,
  `Favorites` (+ `favs.csv`), `ContentOverlay`, `ZipArchive`, `TapZones`,
  `Journal`.
- `WarmGun/` — the app: the SwiftUI views, `PlayerEngine` (AVFoundation),
  `Prefetcher`, `ClipCache`, `PCloudClient`, `MetadataFetcher`, `Keychain`,
  `Settings`, `AppModel` (the one `ObservableObject`: it owns the state,
  asks the Kit, and wires the rest), and `Platform`. Views hold no domain
  state; they read the model and post intents.
- `tools/gates.py` counts, with a target of 0, a non-Foundation import in
  the Kit, `@Published` outside `AppModel`, a stored `static var`, a view
  reaching through the model into its actors, and a platform fork outside
  `Platform.swift`; and it holds the repo's comment lines to a ceiling that
  only comes down. `tools/test_gates.py` pins every one of its patterns.

## Verification

- `cd WarmGunKit && swift test` — the Kit, headless, on the Mac.
- `sh tools/check.sh` — the Kit, the gates and their tests, and
  `tools/sanitize_tree.py`, the family's content guard over every file in
  the tree, tracked and untracked; the git hooks run the same guard over
  what each commit stages and over its message.
- The merge gate runs the Kit, the gate tests and the gates, then compiles
  the app for the Mac and for the phone, signing off.
- `tools/fake_pcloud.py` stands in for the pCloud API off a local folder
  (`listfolder`, `getfilelink`, `getzip`, `renamefile` recorded and never
  performed, `uploadfile` into a scratch folder), so the Simulator or a
  Mac debug build runs end to end with no credentials and no writes:
  `WARMGUN_TOKEN` stands in for the Keychain and `WARMGUN_API_HOST` for the
  host, in those builds only.
- `./install_mac.sh` builds Release into `~/Applications/Warm Gun.app`;
  `./install.sh` builds for the iPhone, plugged in and unlocked. Until it
  has run, nothing is on the phone.
