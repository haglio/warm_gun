# Warm Gun

An iPhone satellite player for the Fun Time library: a never-ending,
auto-advancing run of the library's clips, cached on the phone so nothing
ever waits. No OSR2, no voice — four taps and the controls laid over the
picture. The name and the magenta 5x5 lettermark follow Fun Time's. The
same app builds for the Mac, where it takes the whole screen, taps are
clicks, and the P and L keys stand in for turning the phone.

- **Taps**: left third = previous, right third = next, top-middle = weird,
  lower-middle = lock (favorite + repeat-one). Tap the middle for the
  controls — the type buttons (Genau, Clips, Full), Shuffle/Latest and Favs,
  the Loop control, the act buttons, the four gestures as buttons and pause
  in the center — and double-tap it to pause. On the Mac the keyboard does
  the same: the arrows and WASD are previous, next, weird and lock (left,
  right, up, down), E steps the Loop control clockwise round its grid (All,
  1, Seed, Action), space and Esc pause and play, and P and L pick the
  portrait or the landscape library.
- **Source**: the AI library's originals under `1_sorted/` (small H.264),
  Genau's 2D flicks and the non-AI scenes, through the pCloud HTTP API. Small
  clips are fetched whole and played from an on-device cache, with a deep
  two-sided prefetch window keeping the neighbors resident; a real scene
  streams. The Topaz upscales stay home.
- **Shared state**: favorites and weird marks live on the phone, and every
  event goes out as a journal to a pCloud folder. Evolver reads that
  journal, sums it with Fun Time's own viewing, and stamps the playback weight
  and a favorites flag back onto each video's metadata sidecar — which is where
  the phone reads both, so neither app keeps a copy of the formula and what the
  PC watched moves the phone's shuffle. A `favs.csv` dropped in the sync folder
  is still imported. The weird gesture parks the clip's upscale in
  `2_outbox/kinda_weird/`, where it waits to be reviewed — same as the desktop.

## Layout

- `WarmGun/` — the SwiftUI app: player engine (AVQueuePlayer), prefetcher,
  clip cache, pCloud transport, metadata fetcher, Keychain, settings, views,
  and `Platform.swift`, the one file where the phone and the Mac part ways.
- `WarmGunKit/` — the pure logic, Foundation-only, fully tested headlessly:
  library paths, catalog, pCloud request/response shapes and the login's
  steps, playlist filters and watch-weighted shuffle, session, prefetch
  planning, journal, favorites, the Loop control, and the metadata mirror
  joined to the catalog lane by lane.
- `docs/design.md` — every decision in force, with the desktop code it mirrors.
- `tools/` — `check.sh` (suite + gates + guard), `gates.py` (the coupling
  gates and the comment-line ceiling) and `test_gates.py` (their patterns,
  pinned), `sanitize_tree.py` (the family's guard over every file, since a
  Swift repo has no pytest suite to host the plugin that does it elsewhere),
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

On first run: log in to pCloud (the token goes in the Keychain; the password
is kept only until a login succeeds), and the app finds the library itself.
