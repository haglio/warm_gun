#!/bin/zsh
# Build WarmGun for this Mac and put it in ~/Applications -- the laptop's
# counterpart of install.sh. The same code, built against the macOS SDK: the
# window takes the whole screen, taps are clicks, and the Portrait/Landscape
# chips on the overlay stand in for turning the phone. Signed with the
# development certificate alone (no provisioning profile, so no device
# registration and no Apple-side step), sandboxed, with its own container.
#
#   ./install_mac.sh             # build, install to "~/Applications/Warm Gun.app", open it
#   OPEN=0 ./install_mac.sh      # build and install without opening
set -euo pipefail
cd "$(dirname "$0")"
source tools/require_overlay.sh

# generic/platform=macOS names the native Mac build and nothing else; a bare
# platform=macOS can also match the "Designed for iPhone" variant.
xcodebuild -project WarmGun.xcodeproj -scheme WarmGun \
  -destination "generic/platform=macOS" \
  -configuration Release \
  -derivedDataPath build build

APP="build/Build/Products/Release/Warm Gun.app"
DEST="$HOME/Applications/Warm Gun.app"
mkdir -p "$HOME/Applications"
# A copy still running would keep the old build on screen and `open` would
# only bring it to the front.
pkill -f "$DEST/Contents/MacOS/Warm Gun" 2>/dev/null || true
rm -rf "$DEST"
ditto "$APP" "$DEST"
echo "Installed $DEST"
if [[ "${OPEN:-1}" != 0 ]]; then open "$DEST"; fi
