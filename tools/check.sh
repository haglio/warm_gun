#!/bin/sh
# The whole local verification, one command: the Kit suite headless on the Mac,
# the coupling gates, and the sanitize guard swept over the ENTIRE tree (staged
# into a throwaway index so --staged sees every file, tracked or not). Green
# here is the bar for every commit; CI runs the same checks.
set -e
cd "$(dirname "$0")/.."
(cd WarmGunKit && swift test)
python3 tools/gates.py
tmp_index=$(mktemp -u)
trap 'rm -f "$tmp_index"' EXIT
GIT_INDEX_FILE="$tmp_index" git add -A
GIT_INDEX_FILE="$tmp_index" python3 -m tools.sanitize_guard --staged
echo "all checks green"
