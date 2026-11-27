from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from app_support.sanitize import ListUnreadable, scan_files, the_computers_terms


def _files(repo: Path) -> list[str]:
    def listed(*args: str) -> list[str]:
        out = subprocess.run(["git", "-C", str(repo), "ls-files", *args],
                             capture_output=True, text=True, check=True).stdout
        return [name for name in out.split("\0") if name]

    return listed("-z") + listed("-z", "--others", "--exclude-standard")


def main() -> int:
    here = Path(__file__).resolve().parent
    found = subprocess.run(["git", "-C", str(here), "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True)
    if found.returncode:
        print(f"not a git checkout: {here}", file=sys.stderr)
        return 2
    repo = Path(found.stdout.strip())
    try:
        terms = the_computers_terms()
    except ListUnreadable as unreadable:
        print(f"the tree was NOT scanned: {unreadable}", file=sys.stderr)
        return 2
    if terms is None:
        print("the tree was NOT scanned: this computer keeps no blocklist, since it has no Haglio settings",
              file=sys.stderr)
        return 2

    files = _files(repo)
    if not files:
        print("the tree walk saw no files at all", file=sys.stderr)
        return 2

    violations = scan_files((repo / name for name in files), terms, root=repo)
    print(f"tracked-tree scan: {len(files)} files, {len(violations)} blocked terms")
    for hit in violations[:20]:
        print(f"  {hit.path}:{hit.line}  {hit.excerpt}")
    return 1 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
