# Warm Gun

An iPhone satellite player for the Fun Time library: a never-ending,
auto-advancing run of the AI library's clips, streamed from pCloud and cached
on the phone so nothing ever waits. No OSR2, no voice — four taps and a
controls sheet. The name and the magenta 5x5 lettermark follow Fun Time's.
The same app builds for the Mac, where it takes the whole screen, taps are
clicks, and a Portrait/Landscape pair on the overlay stands in for turning
the phone.

- **Taps**: left third = previous, right third = next, top-middle = weird,
  lower-middle = lock (favorite + repeat-one). Tap the middle for the
  controls overlay — the kind chips (Genau, Clips, Full), Shuffle/Latest and
  Favs, the Loop control, the act buttons, the four gestures as buttons and
  pause in the center, with Portrait/Landscape on the Mac — and double-tap
  it to pause.
- **Source**: the originals under `1_sorted/` (small H.264), fetched whole via
  the pCloud HTTP API and played from an on-device LRU cache; a deep two-sided
  prefetch window keeps the neighbours resident, and "Download this browse"
  pins the whole run. The Topaz upscales stay home.
- **Shared state**: favorites and weird marks live on the phone, and every
  event streams out as a journal to a pCloud folder. Evolver reads that
  journal, sums it with Fun Time's own viewing, and stamps the playback weight
  and a favorites flag back onto each video's metadata sidecar — which is where
  the phone reads both, so neither app keeps a copy of the formula and what the
  PC watched moves the phone's shuffle. A `favs.csv` dropped in the sync folder
  is still imported. The weird gesture parks the clip's upscale in
  `2_outbox/kinda_weird/`, where it waits to be reviewed — same as the desktop.

## Layout

- `WarmGun/` — the SwiftUI app: player engine (AVQueuePlayer), downloader,
  clip cache, prefetcher, pCloud transport, Keychain, settings, views, and
  `Platform.swift`, the one file where the phone and the Mac part ways.
- `WarmGunKit/` — the pure logic, Foundation-only, fully tested headlessly:
  library paths, catalog, pCloud request/response shapes, playlist filters and
  watch-weighted shuffle, session, prefetch planning, journal, favorites, and
  the metadata mirror joined to the catalog lane by lane.
- `docs/design.md` — every decision, with the desktop code it mirrors.
- `tools/` — `check.sh` (suite + gates + guard), `gates.py` (coupling gates),
  `sanitize_tree.py` (the family's guard over every file, since a Swift repo
  has no pytest suite to host the plugin that does it elsewhere),
  `fake_pcloud.py` (local API stand-in for Simulator runs), `make_icon.py`,
  and the git hooks that run `app_support.sanitize`, the one guard the
  family shares.

## Running

- Tests: `cd WarmGunKit && swift test`; everything: `sh tools/check.sh`.
- Phone: `./install.sh` with the iPhone plugged in and unlocked.
- Mac: `./install_mac.sh` builds a Release app into `~/Applications/Warm Gun.app`
  and opens it. It signs with the development certificate alone, so there is
  no device registration and no Apple-side step.
- Simulator or a Mac debug build, no credentials: `python3 tools/fake_pcloud.py
  --root "<pCloud Drive mount>" --scratch /tmp/wg-scratch --no-probe`, then
  launch the app with `WARMGUN_TOKEN=dev-token` and
  `WARMGUN_API_HOST=http://localhost:8765` in its environment.

On first run on the phone: log in to pCloud in Settings (the password is used
once for a token; only the token is kept, in the Keychain), enter the library
path (the pCloud folder holding `1_sorted`), and play.
