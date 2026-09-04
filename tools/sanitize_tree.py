"""The content guard over the whole tree, not just what has changed.

    python3 tools/sanitize_tree.py

The git hooks catch a term while it is still staged, which is the only point at
which the fix is free. They cannot catch one that landed before the guard did,
because `app_support.sanitize --staged` reads `git diff --cached`, a DIFF: a
file whose blob already matches HEAD is not in it, so on a clean tree that scan
reads nothing at all. Every sibling repo gets the whole-tree half from
`app_support.sanitize.pytest_plugin`, which appends a tracked-tree check to its
suite. This repo's suite is Swift, so the same check lives here instead, calling
the same guard -- the terms, the matching and the redaction all still come from
`app_support.sanitize` and nothing about them is repeated here.

Scans every tracked file plus every untracked one git would let you add, since
both are a commit away. Exits 1 on a hit, 2 when there is no blocklist to
enforce -- silence about an unscanned tree is how a guard becomes theater.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from app_support.sanitize.guard import blocklist_path, load_blocklist, scan_files


def _files(repo: Path) -> list[str]:
    def listed(*args: str) -> list[str]:
        out = subprocess.run(["git", "-C", str(repo), "ls-files", *args],
                             capture_output=True, text=True, check=True).stdout
        return [name for name in out.split("\0") if name]

    return listed("-z") + listed("-z", "--others", "--exclude-standard")


def main() -> int:
    # Resolved from this file, not from the working directory: run from anywhere
    # and it still means THIS checkout — including from a worktree, where the
    # answer is the worktree and not the primary.
    here = Path(__file__).resolve().parent
    found = subprocess.run(["git", "-C", str(here), "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True)
    if found.returncode:
        print(f"not a git checkout: {here}", file=sys.stderr)
        return 2
    repo = Path(found.stdout.strip())
    blocklist = blocklist_path(repo)
    terms = load_blocklist(blocklist) if blocklist.exists() else []
    if not terms:
        print(f"the tree was NOT scanned: no blocklist terms resolved at {blocklist}",
              file=sys.stderr)
        return 2

    files = _files(repo)
    if not files:
        print("the tree walk saw no files at all", file=sys.stderr)
        return 2

    violations = scan_files((repo / name for name in files), terms, root=repo)
    print(f"tracked-tree scan: {len(files)} files, {len(violations)} blocked terms")
    for hit in violations[:20]:
        # The excerpt is redacted by the guard; the term itself never prints.
        print(f"  {hit.path}:{hit.line}  {hit.excerpt}")
    return 1 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
