from __future__ import annotations

import subprocess
import sys
from pathlib import Path

HOOKS_DIR = "tools/githooks"


def _git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], capture_output=True, text=True, check=True,
    ).stdout.strip()


def _current() -> str | None:
    got = subprocess.run(
        ["git", "config", "--local", "core.hooksPath"],
        capture_output=True, text=True,
    )
    return got.stdout.strip() or None


def main(argv: list[str]) -> int:
    repo = Path(_git("rev-parse", "--show-toplevel"))
    if not (repo / HOOKS_DIR / "pre-commit").exists():
        print(f"no {HOOKS_DIR}/pre-commit in {repo}", file=sys.stderr)
        return 1

    if "--uninstall" in argv:
        subprocess.run(["git", "config", "--local", "--unset", "core.hooksPath"])
        print("core.hooksPath unset; git is back to .git/hooks")
        return 0

    was = _current()
    if was == HOOKS_DIR:
        print(f"already installed: core.hooksPath = {HOOKS_DIR}")
        return 0
    _git("config", "--local", "core.hooksPath", HOOKS_DIR)
    if was:
        print(f"core.hooksPath was {was!r} — replaced with {HOOKS_DIR!r}")
    else:
        print(f"core.hooksPath = {HOOKS_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
