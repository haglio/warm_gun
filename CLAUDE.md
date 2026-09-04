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
  build), and the sanitize guard swept over the whole tree.
- End-to-end without credentials or library writes: build for the Simulator,
  run `python3 tools/fake_pcloud.py --root "<pCloud Drive mount>" --scratch
  <tmp> --no-probe`, and launch with the `WARMGUN_TOKEN` environment variable
  set (the simulator-only Keychain stand-in) and the API host
  `http://localhost:8765`.

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
  the same guard (`tools/sanitize_guard.py` + git hooks via `core.hooksPath`).
  Run `python3 tools/githooks/install.py` once per clone; the guard reads
  `sanitize/blocklist.local.txt`.

## Landing

No GitHub remote yet: commit to local `main`, whole `tools/check.sh` green
first. When the repo joins `github.com/haglio`, the siblings' PR + merge-queue
flow applies (`.github/workflows/merge-gate.yml` is already the required check).
