#!/bin/zsh
# Build WarmGun for this Mac and put it in ~/Applications -- the laptop's
# counterpart of install.sh. The same code, built against the macOS SDK: the
# window takes the whole screen, taps are clicks, and the Portrait/Landscape
# chips on the overlay stand in for turning the phone. Signed with the
# development certificate alone (no provisioning profile, so no device
# registration and no Apple-side step), sandboxed, with its own container.
#
#   ./install_mac.sh             # build, install to ~/Applications/WarmGun.app, open it
#   OPEN=0 ./install_mac.sh      # build and install without opening
set -euo pipefail
cd "$(dirname "$0")"
source tools/require_overlay.sh

xcodebuild -project WarmGun.xcodeproj -scheme WarmGun \
  -destination "platform=macOS,arch=arm64" \
  -configuration Release \
  -derivedDataPath build build

APP="build/Build/Products/Release/WarmGun.app"
DEST="$HOME/Applications/WarmGun.app"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$APP" "$DEST"
echo "Installed $DEST"
if [[ "${OPEN:-1}" != 0 ]]; then open "$DEST"; fi
