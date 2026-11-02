# warm_gun — Project-Specific Instructions

Shared rules are in the global `~/.claude/CLAUDE.md`. This file contains only
warm_gun-specific overrides.

**Keep this file short.** No redundancy with the global CLAUDE.md. One bullet
per rule. If editing this file, remove or consolidate — never just append.

## What this is

The iPhone satellite player for the Fun Time library — see `docs/design.md`
for every decision and the module map. SwiftUI app in `WarmGun/`, pure-logic
SwiftPM package in `WarmGunKit/` (Foundation only, enforced by a gate).

## Verification

- Unit suite (run freely, no permission needed): `cd WarmGunKit && swift test`
- Everything local in one command: `sh tools/check.sh` — the suite, the
  coupling gates (`tools/gates.py`, counts with a target of 0 that fail the
  build) and their tests, and the sanitize guard swept over the whole tree.
- `tools/quality_baseline.json` holds each file's comment lines, and an entry
  only comes down: `python3 tools/gates.py --lower` takes every fall, carries a
  renamed file's entry and refuses every rise; a file added enters at zero.
- On a machine with no Swift (the Windows PC), the merge gate is the only
  place the Kit runs and the app compiles: push each red or green step to a
  throwaway branch whose own copy of `merge-gate.yml` names it under
  `push:`, read that run, and delete the branch when the work ships.
- End-to-end without credentials or library writes: build for the Simulator
  or for the Mac (`-destination 'generic/platform=macOS'`, Debug), run
  `python3 tools/fake_pcloud.py --root "<pCloud Drive mount>" --scratch
  <tmp> --no-probe`, and launch with `WARMGUN_TOKEN` and
  `WARMGUN_API_HOST=http://localhost:8765` in the environment (the
  development stand-ins for the Keychain and the host; device builds and a
  Mac Release build compile them out). A Mac debug build runs with
  `open --env ...` and has a bundle id of its own, so its container, cache
  and journal never meet the installed app's.
- The Mac app goes full screen only once its window becomes key, which a
  locked screen never allows: with the Mac locked, the window stays at its
  launch size however correct the code is, so judge that part unlocked.

## The phone does not self-update

A change reaches the iPhone only by `./install.sh` with the phone plugged in
and *unlocked* (the build outlasts the auto-lock; unlock again for the install
step). Until that has run, a phone fix is NOT fixed, however green the suite —
say so rather than reporting it landed. If you need the phone, **ask for it**;
never verify around its absence when the change is about device behavior.

## The library is sacred

- Never write into the real library or the real pCloud account from
  development. The fake server exists so the whole app can be driven with no
  credentials and no writes; `renamefile` against it only records the move.
- Every fixture value is fabricated — the same law as every sibling repo, and
  the same guard: `app_support.sanitize`, run by the git hooks that
  `core.hooksPath` points at. Run `python3 tools/githooks/install.py` once
  per clone. The blocklist is one file beside the twelve checkouts, in no
  repository at all, so there is nothing to copy here.

## Landing

Same as every sibling: work in a worktree, `tools/check.sh` green first, then
push the branch and open a PR against `github.com/haglio/warm_gun`. Auto-merge
arms itself and the queue lands it when `.github/workflows/merge-gate.yml`,
the required check, goes green. Never push `main` directly.

The gate also compiles the app for the Mac and the phone, each the way its
install script builds it, so an app change that does not build for either
cannot ship; what it does on a device is still seen only by running it there.
