#!/bin/sh
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
python3 -m unittest -q tools.test_gates
python3 tools/gates.py
"$python" tools/sanitize_tree.py
echo "all checks green"
