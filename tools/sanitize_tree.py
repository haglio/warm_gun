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
        print(f"  {hit.path}:{hit.line}  {hit.excerpt}")
    return 1 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
