# Warm Gun

An iPhone satellite player for the Fun Time library: a never-ending,
auto-advancing run of the AI library's clips, streamed from pCloud and cached
on the phone so nothing ever waits. No OSR2, no voice — four taps and a
controls sheet. The name and the pink 5x5 lettermark follow Fun Time's.

- **Taps**: left third = previous, right third = next, top-middle = weird,
  bottom-middle = lock (favorite + repeat-one). Double-tap the middle for the
  controls sheet: portrait/landscape library, F-mode (favorites only), shorts
  only, latest-first, loop-each-clip, and Settings.
- **Source**: the originals under `1_sorted/` (small H.264), fetched whole via
  the pCloud HTTP API and played from an on-device LRU cache; a deep two-sided
  prefetch window keeps the neighbours resident, and "Download this browse"
  pins the whole run. The Topaz upscales stay home.
- **Shared state**: favorites, weird marks and watch counts live on the phone
  and stream out as a journal to a pCloud folder; a `favs.csv` dropped there is
  imported. The weird gesture parks the clip's upscale in
  `2_outbox/kinda_weird/`, arming Evolver's purge — same as the desktop.

## Layout

- `WarmGun/` — the SwiftUI app: player engine (AVQueuePlayer), downloader,
  clip cache, prefetcher, pCloud transport, Keychain, settings, views.
- `WarmGunKit/` — the pure logic, Foundation-only, fully tested headlessly:
  library paths, catalog, pCloud request/response shapes, playlist filters and
  watch-weighted shuffle, session, prefetch planning, journal, favorites.
- `docs/design.md` — every decision, with the desktop code it mirrors.
- `tools/` — `check.sh` (suite + gates + guard), `gates.py` (coupling gates),
  `fake_pcloud.py` (local API stand-in for Simulator runs), `make_icon.py`,
  and the sanitize guard + harvester + git hooks every sibling repo carries.

## Running

- Tests: `cd WarmGunKit && swift test`; everything: `sh tools/check.sh`.
- Phone: `./install.sh` with the iPhone plugged in and unlocked.
- Simulator, no credentials: `python3 tools/fake_pcloud.py --root "<pCloud
  Drive mount>" --scratch /tmp/wg-scratch --no-probe`, then launch the app
  with `WARMGUN_TOKEN=dev-token` and API host `http://localhost:8765`.

On first run on the phone: log in to pCloud in Settings (the password is used
once for a token; only the token is kept, in the Keychain), enter the library
path (the pCloud folder holding `1_sorted`), and play.
