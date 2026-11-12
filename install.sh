#!/bin/zsh
# Xcode's build outlasts the iPhone's auto-lock, so the install waits until the phone is unlocked.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
exec > >(tee build/install.log) 2>&1
echo "This run is logged to $PWD/build/install.log."

source tools/require_overlay.sh

xcodebuild -project WarmGun.xcodeproj -scheme WarmGun \
  -destination "generic/platform=iOS" \
  -derivedDataPath build \
  -allowProvisioningUpdates build

APP="build/Build/Products/Debug-iphoneos/Warm Gun.app"

# devicectl's table lists simulators and prints a sentence when none match, so read its JSON instead.
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

# The phone sometimes drops the connection mid-install (CoreDeviceError 4000); a retry gets through.
for attempt in 1 2 3; do
  xcrun devicectl device install app --device "$DEVICE" "$APP" && break
  (( attempt < 3 )) || exit 1
  echo "Install attempt $attempt failed. Retrying in 5 seconds..." >&2
  sleep 5
done
echo "Installed onto $DEVICE."
