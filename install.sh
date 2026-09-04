#!/bin/zsh
# Build WarmGun and install it onto the iPhone — the only way a change reaches the
# phone (it cannot pull from git). Same flow as Highdeas' ios/resign.sh: the
# paid Developer Program's wildcard team profile already covers this bundle id
# and the phone, so there is no Apple-side setup beyond being signed into Xcode.
#
#   ./install.sh                 # iPhone plugged in and UNLOCKED (the build is
#                                # long enough for it to auto-lock; unlock again
#                                # for the install step)
#   DEVICE=<udid> ./install.sh   # pick a device explicitly
set -euo pipefail
cd "$(dirname "$0")"

# The content overlay is git-ignored, so a WORKTREE does not have it -- and the
# app degrades silently without one: no lanes, no acts checkbox, and the eight
# act buttons simply absent from the corner. That is indistinguishable from a
# regression and no test can catch it, because the file is a build input rather
# than code. So: if the primary checkout has one and this tree does not, stop
# and say which file to copy.
overlay="WarmGun/content.local.json"
primary=$(cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd)
if [[ ! -f "$overlay" && -f "$primary/$overlay" ]]; then
  echo "No $overlay in this checkout, but $primary has one." >&2
  echo "The build would install an app with no lanes and no act buttons. Run:" >&2
  echo "  cp \"$primary/$overlay\" $overlay" >&2
  exit 1
fi

xcodebuild -project WarmGun.xcodeproj -scheme WarmGun \
  -destination "generic/platform=iOS" \
  -derivedDataPath build \
  -allowProvisioningUpdates build

APP="build/Build/Products/Debug-iphoneos/WarmGun.app"

if [[ -z "${DEVICE:-}" ]]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null \
    | grep -Eo '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}|[0-9a-f]{8}-[0-9a-f]{16}' \
    | head -1)
fi
if [[ -z "$DEVICE" ]]; then
  echo "No iPhone found. Plug it in (unlock it), or pass DEVICE=<udid>." >&2
  exit 1
fi

xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "Installed onto $DEVICE."
