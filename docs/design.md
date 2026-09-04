# Warm Gun — the phone satellite

Written 2026-08-23 at kickoff. Warm Gun is an iPhone app that does what one of Fun
Time's satellite players does — an endless, silent, auto-advancing run of the AI
library's clips with four gestures — on a phone, away from home, off travel
wifi. No OSR2, no voice, no dashboard. The decisions below were made against the
research in this session (Fun Time's satellite/dispatch code, the library as it
sits in pCloud, the pCloud HTTP API, the Highdeas iOS project); change them with
the owner, not alone.

## What it is

- **Source of clips**: the library's *originals* — `1_sorted/<source>/<orientation>/<stem>.mp4`
  (~2.2 MB median H.264, 5 s median) — not the Topaz upscales in `2_outbox`
  (~256 MB median HEVC) that the desktop satellites play. The owner asked for "the
  non-upscaled ones"; on disk those are `1_sorted` (he named `2_outbox`, which is
  the upscale tree — the mapping between the two is total and bidirectional, so
  nothing is lost: every original has exactly one `2_outbox/upscaled_by_orientation/<orientation>/<source>/<stem>_topaz.mp4`,
  and stems are unique library-wide).
- **Transport**: the pCloud HTTP API straight from the phone (`api.pcloud.com`,
  the account is US-region). The owner logs in *inside the app* (username +
  password → the `login` method, introducing itself as a client the way pCloud's
  own apps do — a bare `userinfo?getauth=1` trips new-device verification whose
  code the API never delivers — → the `auth` token goes into the Keychain; the
  password is never stored), or pastes a token. The app lists the library once
  with one recursive `listfolder`, which also hands back each clip's size,
  duration, codec and dimensions for free — no probing.
- **Playback**: a clip is *always* fetched whole into an on-device cache before
  it is handed to AVPlayer. Never progressive streaming: 90% of the originals put
  `moov` after `mdat`, which would cost a tail round-trip before the first frame,
  and a whole 2 MB file is under two seconds even at the 1.2 MB/s measured off
  the pCloud mount. From the cache, start is instant and a transition is gapless.
- **Gestures** (single tap, fires immediately): left third → previous; right
  third → next; top-middle → weird; bottom-middle → lock (favorite); double tap
  in the middle → the controls sheet. Same meanings as the desktop satellite's
  arrow keys.
- **Controls sheet** (checkboxes): Landscape library (off = portrait); Favs
  (favorites only — on a satellite those are the same switch, `modes.py:253`);
  Shorts only; Latest (newest first, else weighted shuffle); Loop clip (repeat
  each clip instead of advancing); plus Settings (login, library path, cache
  size, "download everything"). The name of the clip on the glass sits under
  the pause button — the sheet is the one place the app says which file this is.

## Fidelity to the desktop satellite (what each gesture really does)

From `fun_time/command_dispatch.py`, `fun_time/lock.py`, `satellite/session.py`:

- **Next / Previous**: playlist-index steps that wrap; previous is the list
  neighbour, not a history stack. Any nav releases a lock.
- **Lock** (down): toggles. Locking = repeat-one on the current clip AND add it
  to the favorites AND count a `lock` watch event. Unlocking = stop repeating
  AND advance. Unlocking never unfavorites.
- **Weird** (up): two-step demotion. If the clip is a favorite → just remove
  it from the favorites and advance ("Unfavorited"). Otherwise → drop it from
  the playlist, advance, and move its *upscale* into `2_outbox/kinda_weird/`
  ("Marked weird"), which is what arms Evolver's purge of the original and its
  sidecar on the desktop's next run. Warm Gun does the same move through the pCloud
  API (`renamefile`), so a weird on the phone is a weird everywhere — exactly
  as irreversible as on the desktop. It never deletes the original itself.
  One accepted divergence: pCloud's `renamefile` replaces a same-named
  incumbent where the desktop's `move_to_weird` walks `__dup1`, `__dup2`…
  — harmless because stems are unique library-wide and re-marking the same
  clip renames the same file onto itself.
- **Auto-advance**: a clip plays once and the next one rolls on; only a lock
  loops it. The "Loop clip" checkbox is Warm Gun's addition for when one wants
  every clip to loop until tapped.
- **Ordering**: Shuffle = the desktop's watch-weighted Efraimidis–Spirakis
  shuffle with probabilistic inclusion. The weight is **read, never computed**:
  Evolver's Watch Weights stage sums what Fun Time and Warm Gun each completed,
  skipped and locked and stamps the result on every library video's sidecar as
  `watch.weight` (`evolver/util/watch.py`, 2^clamp((completions + 3·locks −
  skips)/3, −3, 3)), so one implementation serves both apps and what the PC
  watched moves the phone's order. A sidecar with no `watch` block weighs 1.
  Latest = newest modified first, unweighted. A filter change keeps the on-screen clip playing if it
  survives the rebuild (`session.replace_playlist`), and a filter that matches
  nothing leaves the current playlist in place instead of blanking the screen.
- **Since v1**: seed and action loops are in (the Loop control's Seed/Action
  segments) — the desktop's exact grouping over the metadata sidecars, fetched
  as one getzip of the mirror's AI branch and re-seated into the playlist with
  the anchor first, degenerating to a lock for a group of one. Still to come:
  the act filter, the HUD map
  (all need the 1 341 metadata sidecars); the desktop's group-collapse of the
  browse (one clip per subject) for the same reason. Indexing the sidecars is
  the one prerequisite for all of them and is the obvious next step.
- **Since the watch weights landed**: all three branches of the metadata mirror
  are indexed, not just the AI one — a genau loop and a real scene have
  sidecars too, and had none of this before. Their sidecars mirror the video
  path with the extension dropped; an AI original's is its upscale's, source
  and orientation nested the other way round (`LibraryPaths.MetadataBranch`).

## Shared state with the desktop

The desktop's `favs.csv` and `watch_stats.json` live in the fun_time checkout
on the PC, which is *not* in pCloud, and `watch_stats.json` prunes any key that
is not a path on the writing machine. So Warm Gun does not write either file. It
keeps its own stores on the phone (favorites, weird marks) and appends
every event to a journal
(`warm-gun-journal.jsonl`, one JSON object per line: `{"t": unix seconds, "event":
"favorite|unfavorite|weird|lock|completion|skip", "path": "<library-relative
original path>"}`) that it uploads to a pCloud folder outside the library
(`/WarmGun` by default; configurable). Merging that journal into the desktop's
stores is a later, desktop-side step. If a `favs.csv` is dropped into that same
folder, Warm Gun imports it: the second `=HYPERLINK(...)` argument of each row is a
Windows path to a `<stem>_topaz.mp4`, and the stem alone identifies the clip.

The return leg arrives on the sidecars. Evolver reads that journal, applies the
phone's favorites and unfavorites to `favs.csv`, and stamps every library
video's sidecar with a `watch` block and — for a favorite — `favorite: true`.
Warm Gun reads both: the weight is the only thing its shuffle draws on, and the
flag is folded into its own favorites (only ever added, exactly as a `favs.csv`
import is, because the flag is a snapshot from the last time the stage ran and
would otherwise undo a favorite made on the phone since). The phone therefore
keeps no watch counts of its own at all — it records events and reads a number.

## Performance design (the whole point)

1. **Local index, built once.** One recursive `listfolder` (≈2 MB of JSON with
   `filtermeta`, seconds) becomes a `Catalog` persisted on the phone. Every
   playlist rebuild is an in-memory operation on that index — no network on a
   checkbox tap. The index refreshes in the background on launch.
2. **Index-time exclusions.** Files over 25 MB (the 22 legacy HEVC upscales that
   sit in `1_sorted` and would take minutes to fetch) are excluded by size, a
   setting. Orientation comes from the folder, never from pixel dimensions (21
   clips are square).
3. **Whole-file cache, keyed by file, not by index.** Cached clips survive any
   reshuffle. Lives in Application Support, excluded from backup, with an LRU
   cap (default 2 GB). "Download everything" prefetches the whole current
   library (~3.8 GB for the non-outlier originals) so nothing ever waits.
4. **Deep, two-sided prefetch window.** The playlist is deterministic, so both
   the future and the past are knowable: the prefetcher keeps N clips ahead
   (default 12) and M behind (default 3) resident, fetching nearest-first with
   three parallel downloads, and re-plans on every index change, filter change
   or reshuffle (cancelling what fell out of the window). A locked clip is free
   time for the window to sprint ahead.
5. **Pre-built player items.** The engine keeps AVPlayerItems ready for the
   neighbours, so next/previous from cache is a swap, not a load; auto-advance
   is an AVQueuePlayer roll-on.
6. **Link caching.** `getfilelink` URLs expire; they are cached until then and
   refreshed lazily, and an expired-link failure means "re-link and retry", not
   "file gone".

## Module boundaries (the coupling gates enforce these)

- `WarmGunKit/` — pure Foundation, no UIKit/AVFoundation/SwiftUI imports (gate:
  count must be 0). Everything decidable without a device lives here and is
  TDD'd: `LibraryPaths` (rendition mapping, orientation/source parsing),
  `Catalog` + `Clip` (the index and its builder from pCloud listings),
  `PCloudAPI` (request building + response decoding, error mapping),
  `Playlist`/`BrowseOptions` (filters, ordering, weighted shuffle), `Session`
  (index, step, discard, lock, replacePlaylist), `WatchWeights` (the stamped
  weight, and the two draw primitives) + `WatchTracker` (samples → events),
  `Sidecar` + `GroupIndex` + `SidecarIndex` (the mirror joined to the catalog),
  `Favorites` (+ favs.csv import; a generated clip is filed under its stem,
  which is the only name the desktop's file can say, and the other two lanes
  under their whole path, where nothing promises two files differ by name),
  `PrefetchPlanner` (window → fetch order and
  eviction), `TapZones`, `Journal`, `LinkCache`.
- `WarmGun/` — the app: SwiftUI views, `PlayerEngine` (AVFoundation), `Downloader`
  (URLSession), `ClipCache` (disk), `PCloudClient` (transport), `Keychain`,
  `AppModel` (the one `ObservableObject`, owns the Kit state). Views hold no
  domain state; they read the model and post intents.
- No module shares mutable state with another: the Kit types are value types or
  single-owner classes handed in by the model; the app's actors own their own
  storage and talk through async methods.

## Verification

- `cd WarmGunKit && swift test` — the Kit, headless, on the Mac. Zero failures,
  zero skips, before every commit.
- `tools/gates.py` — the coupling/purity gates, numbers with a target of 0,
  fail the build. Runs in CI and from `tools/check.sh`.
- `tools/githooks/pre-commit` — the family's content guard,
  `app_support.sanitize`, over everything staged: a term is caught on its
  way in, which is the only point at which the fix is free.
- `tools/sanitize_tree.py` — the same guard over every file in the tree,
  tracked and untracked, which the hook cannot do: `--staged` reads a DIFF,
  so on a clean tree it scans nothing and exits 0. The siblings get this
  half from `app_support.sanitize.pytest_plugin`; a Swift repo has no suite
  for it to attach to, so `tools/check.sh` runs it directly.
- `tools/fake_pcloud.py` — a local stand-in for the pCloud API that serves the
  library straight off the pCloud Drive mount (`listfolder`, `getfilelink`,
  `renamefile` into a scratch folder, `uploadfile`), so the whole app can be
  driven end-to-end in the Simulator with no credentials and no writes to the
  real library.
- The Simulator flow needs no credentials: the simulator-only `WARMGUN_TOKEN`
  launch variable stands in for the Keychain, so the whole app boots straight
  into playback against the fake server (verified 2026-08-24: index, prefetch,
  playback, auto-advance, watch journal upload, all against the real library
  files read-only through the fake).
- The phone: `./install.sh` with the iPhone plugged in and unlocked (same
  flow as Highdeas' `ios/resign.sh`; the wildcard team profile already covers
  any bundle id under the team). Until that has run, nothing is on the phone.
