#!/bin/zsh
overlay="WarmGun/content.local.json"
primary=$(cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd)
if [[ ! -f "$overlay" && -f "$primary/$overlay" ]]; then
  echo "No $overlay in this checkout, but $primary has one." >&2
  echo "The build would install an app with no lanes. Run:" >&2
  echo "  cp \"$primary/$overlay\" $overlay" >&2
  exit 1
fi
