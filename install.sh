#!/bin/zsh
# Xcode's build outlasts the iPhone's auto-lock, so the install waits until the phone is unlocked.
set -euo pipefail
cd "$(dirname "$0")"

source tools/require_overlay.sh

xcodebuild -project WarmGun.xcodeproj -scheme WarmGun \
  -destination "generic/platform=iOS" \
  -derivedDataPath build \
  -allowProvisioningUpdates build

APP="build/Build/Products/Debug-iphoneos/Warm Gun.app"

# devicectl lists the Simulator's devices beside the real ones, and its table prints a sentence
# where none matches, so the phone is picked by what it is and read out of the JSON.
if [[ -z "${DEVICE:-}" ]]; then
  DEVICE=$(xcrun devicectl list devices --quiet --json-output - \
    --filter "properties.hardware.platform == 'iOS' AND properties.hardware.reality != 'simulated'" 2>/dev/null \
    | python3 -c 'import json, sys; found = json.load(sys.stdin)["result"]["devices"]; print(found[0]["identifier"] if found else "")')
fi
if [[ -z "$DEVICE" ]]; then
  echo "No iPhone found. Plug it in (unlock it), or pass DEVICE=<udid>." >&2
  exit 1
fi

locked() {
  xcrun devicectl device info lockState --device "$DEVICE" --quiet --json-output - 2>/dev/null \
    | python3 -c 'import json, sys; sys.exit(0 if json.load(sys.stdin)["result"]["passcodeRequired"] else 1)'
}
if locked; then
  echo "Unlock the iPhone to install. Waiting..." >&2
  while locked; do sleep 2; done
fi

xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "Installed onto $DEVICE."
