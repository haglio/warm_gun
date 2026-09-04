#!/bin/sh
# The whole local verification, one command: the Kit suite headless on the Mac,
# the coupling gates, and the sanitize guard over every file in the tree.
# Green here is the bar for every commit; CI runs the suite and the gates.
#
# The guard runs through tools/sanitize_tree.py rather than through the
# pre-commit hook. The hook's `--staged` mode reads `git diff --cached`, so on a
# clean tree it scans NOTHING and still exits 0 -- fine for a hook, which exists
# to catch a term on its way in, and useless as the whole-tree sweep this claims
# to be. The interpreter search is the hook's, reused rather than repeated.
set -e
cd "$(dirname "$0")/.."

repo=$(git rev-parse --show-toplevel)
primary=$(cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd)
family=$(dirname "$primary")
for candidate in \
    "$repo/.venv/Scripts/python.exe" \
    "$repo/.venv/bin/python" \
    "$primary/.venv/Scripts/python.exe" \
    "$primary/.venv/bin/python" \
    "$family/.venv/Scripts/python.exe" \
    "$family/.venv/bin/python"
do
    if [ -x "$candidate" ]; then python="$candidate"; break; fi
done
python=${python:-$(command -v python3 || command -v python || echo python3)}

(cd WarmGunKit && swift test)
python3 tools/gates.py
"$python" tools/sanitize_tree.py
echo "all checks green"
