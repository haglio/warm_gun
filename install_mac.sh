#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
source tools/require_overlay.sh

# xcodebuild's `generic/platform=macOS` names the native Mac build; a bare `platform=macOS` can
# also match the "Designed for iPhone" variant.
xcodebuild -project WarmGun.xcodeproj -scheme WarmGun \
  -destination "generic/platform=macOS" \
  -configuration Release \
  -derivedDataPath build build

APP="build/Build/Products/Release/Warm Gun.app"
DEST="$HOME/Applications/Warm Gun.app"
mkdir -p "$HOME/Applications"
# With a copy still running, macOS's `open` would only bring the old build to the front.
pkill -f "$DEST/Contents/MacOS/Warm Gun" 2>/dev/null || true
rm -rf "$DEST"
ditto "$APP" "$DEST"
echo "Installed $DEST"
if [[ "${OPEN:-1}" != 0 ]]; then open "$DEST"; fi
