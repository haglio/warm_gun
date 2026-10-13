#!/bin/zsh
# Refuse to build an app with no content overlay when the primary checkout has
# one. The overlay is git-ignored, so a WORKTREE does not have it -- and the app
# degrades silently without one: no lanes, no acts checkbox, and the eight act
# buttons simply absent from the corner. That is indistinguishable from a
# regression and no test can catch it, because the file is a build input rather
# than code. Sourced by install.sh and install_mac.sh from the checkout root.
overlay="WarmGun/content.local.json"
primary=$(cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd)
if [[ ! -f "$overlay" && -f "$primary/$overlay" ]]; then
  echo "No $overlay in this checkout, but $primary has one." >&2
  echo "The build would install an app with no lanes and no act buttons. Run:" >&2
  echo "  cp \"$primary/$overlay\" $overlay" >&2
  exit 1
fi
