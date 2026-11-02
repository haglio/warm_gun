"""The coupling gates — numbers with a target of zero that fail the build —
and the ceiling on comment lines.

Length and lint say nothing about coupling, which is what actually rots a
codebase, so the load-bearing invariants are counted here and a nonzero count
is a failing exit. The invariants, from docs/design.md:

1. ``WarmGunKit`` is pure Foundation. Everything decidable without a device
   lives there and is tested headlessly; one stray UIKit/AVFoundation/SwiftUI
   import and that stops being true.
2. ``AppModel`` is the only owner of published app state. A second
   ``@Published`` home is the first step toward two sources of truth.
3. No module shares mutable state with another: no ``static var`` anywhere —
   a global is shared mutable state whichever file it hides in.
4. Views do not reach through the model into its actors. The model hands out
   values and intents; ``model.<actor>.<anything>`` from a view couples the
   view to machinery the model exists to own.
5. The phone and the Mac part ways in ``Platform.swift`` and nowhere else:
   every ``#if`` but ``DEBUG`` and every UIKit, AppKit or Cocoa import
   outside it (the Kit included) is a second place the two can drift apart,
   and the one place is what keeps the app above it one program. Any ``#if``,
   not only ``os(...)``: a custom compilation condition set per SDK would
   spell the same fork differently.
6. A comment is a claim nothing runs, so what a name or a test can say is
   said there, and the comment lines of each Swift source, test and shell
   script are held to that file's entry in ``tools/quality_baseline.json``,
   which only comes down: ``--lower`` takes every fall and refuses every rise,
   and a file added enters at zero.

Run: ``python3 tools/gates.py`` (exit 0 = all gates hold).
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

KIT_ALLOWED_IMPORTS = {"Foundation"}
KIT_IMPORT = re.compile(r"\s*import\s+(\w+)")
STORED_STATIC_VAR = re.compile(r"\bstatic\s+var\b[^{=\n]*(=|$)")
MODEL_FILE = "AppModel.swift"
PLATFORM_FILE = "Platform.swift"
PLATFORM_CONDITION = re.compile(r"#\s*(if|elseif)\b(?!\s*!?DEBUG\s*$)")
PLATFORM_IMPORT = re.compile(r"(^|;)\s*(@\w+(\([^)]*\))?\s+)*import\s+(\w+\s+)?(UIKit|AppKit|Cocoa)\b")
ACTORS = ("engine", "cache", "prefetcher", "client")
SHELL_SHEBANG = re.compile(rb"#!.*\b(sh|bash|zsh)\b")
BASELINE_PATH = "tools/quality_baseline.json"
PROSE_SECTION = "prose_lines"


def kit_sources(root: Path) -> Path:
    return root / "WarmGunKit" / "Sources"


def kit_tests(root: Path) -> Path:
    return root / "WarmGunKit" / "Tests"


def app_sources(root: Path) -> Path:
    return root / "WarmGun"


def swift_files(directory: Path) -> list[Path]:
    return sorted(directory.rglob("*.swift"))


def is_comment(line: str, marker: str = "//") -> bool:
    return line.strip().startswith(marker)


def code_lines(path: Path):
    """(line_number, line) with comment-only lines dropped — a gate must count
    code, not prose about code."""
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if is_comment(line):
            continue
        yield number, line


def is_shell_script(path: Path) -> bool:
    if path.suffix:
        return path.suffix == ".sh"
    with path.open("rb") as script:
        return bool(SHELL_SHEBANG.match(script.readline()))


def prose_files(root: Path) -> list[Path]:
    scripts = [path for path in sorted(root.glob("*")) + sorted((root / "tools").rglob("*"))
               if path.is_file() and is_shell_script(path)]
    return (swift_files(kit_sources(root)) + swift_files(kit_tests(root))
            + swift_files(app_sources(root)) + scripts)


def _comment_lines_in(path: Path) -> int:
    marker = "//" if path.suffix == ".swift" else "#"
    lines = path.read_text(encoding="utf-8").splitlines()
    if lines and lines[0].startswith("#!"):
        lines = lines[1:]
    return sum(is_comment(line, marker) for line in lines)


def prose_by_file(root: Path) -> dict[str, int]:
    counted = {path.relative_to(root).as_posix(): _comment_lines_in(path) for path in prose_files(root)}
    return {name: lines for name, lines in counted.items() if lines}


def _entries(root: Path) -> dict[str, int]:
    return json.loads((root / BASELINE_PATH).read_text(encoding="utf-8"))[PROSE_SECTION]


def _git(root: Path, *args: str) -> str | None:
    done = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, encoding="utf-8", check=False)
    return done.stdout if done.returncode == 0 else None


def _where_this_left_main(root: Path) -> str | None:
    left = _git(root, "merge-base", "HEAD", "origin/main")
    return left.strip() if left else None


def _renamed_since_main(root: Path) -> dict[str, str]:
    left = _where_this_left_main(root)
    listed = _git(root, "diff", "-M", "--name-status", "--diff-filter=R", left) if left else None
    return {old: new for _, old, new in (line.split("\t") for line in (listed or "").splitlines())}


def lower_entries(root: Path) -> list[str]:
    renames = _renamed_since_main(root)
    on_file = _entries(root)
    said = [f"carried {old} to {new}" for old, new in renames.items() if old in on_file]
    entries = {renames.get(name, name): entry for name, entry in on_file.items()}
    live = prose_by_file(root)
    kept = {name: min(live.get(name, 0), entry) for name, entry in entries.items() if live.get(name, 0)}
    said += [f"lowered {name} from {entry} to {live.get(name, 0)}" for name, entry in sorted(entries.items())
             if live.get(name, 0) < entry and (root / name).exists()]
    said += [f"refused {name}: it holds {held}, over its entry of {entries.get(name, 0)}"
             for name, held in sorted(live.items()) if held > entries.get(name, 0)]
    said += [f"could not match {name}: nothing is there now and git names no rename of it"
             for name in sorted(entries) if not (root / name).exists()]
    text = json.dumps({PROSE_SECTION: kept}, indent=2, sort_keys=True) + "\n"
    (root / BASELINE_PATH).write_bytes(text.encode("utf-8"))
    return said


def where(path: Path, root: Path, number: int) -> str:
    return f"{path.relative_to(root).as_posix()}:{number}"


def gate_kit_purity(root: Path) -> list[str]:
    hits = []
    for path in swift_files(kit_sources(root)):
        for number, line in code_lines(path):
            match = KIT_IMPORT.match(line)
            if match and match.group(1) not in KIT_ALLOWED_IMPORTS:
                hits.append(f"{where(path, root, number)}: import {match.group(1)}")
    return hits


def gate_published_ownership(root: Path) -> list[str]:
    hits = []
    for path in swift_files(app_sources(root)):
        if path.name == MODEL_FILE:
            continue
        for number, line in code_lines(path):
            if "@Published" in line:
                hits.append(f"{where(path, root, number)}: @Published outside {MODEL_FILE}")
    return hits


def gate_no_static_mutable(root: Path) -> list[str]:
    hits = []
    for path in swift_files(kit_sources(root)) + swift_files(app_sources(root)):
        for number, line in code_lines(path):
            if STORED_STATIC_VAR.search(line):
                hits.append(f"{where(path, root, number)}: stored static var")
    return hits


def gate_views_stay_out_of_actors(root: Path) -> list[str]:
    hits = []
    for path in swift_files(app_sources(root)):
        if path.name == MODEL_FILE:
            continue
        for number, line in code_lines(path):
            for actor in ACTORS:
                if re.search(rf"\bmodel\.{actor}\b", line):
                    hits.append(f"{where(path, root, number)}: model.{actor}")
    return hits


def gate_prose_ceiling(root: Path) -> list[str]:
    entries, live = _entries(root), prose_by_file(root)
    hits = []
    for name in sorted({*entries, *live}):
        held, entry = live.get(name, 0), entries.get(name, 0)
        if held > entry:
            hits.append(f"{name} holds {held} comment lines, over its entry of {entry}: say it in a name or a test")
        elif held < entry:
            hits.append(f"{name} holds {held} comment lines, under its entry of {entry}: "
                        "run python3 tools/gates.py --lower")
    return hits


def gate_no_entry_above_main(root: Path) -> list[str]:
    left = _where_this_left_main(root)
    held = _git(root, "show", f"{left}:{BASELINE_PATH}") if left else None
    if not held:
        return []
    renames = _renamed_since_main(root)
    at_main = {renames.get(name, name): entry for name, entry in json.loads(held)[PROSE_SECTION].items()}
    return [f"{name} stands at {entry}, above the {at_main.get(name, 0)} main holds: an entry only comes down"
            for name, entry in sorted(_entries(root).items()) if entry > at_main.get(name, 0)]


def gate_platform_seam(root: Path) -> list[str]:
    hits = []
    for path in swift_files(kit_sources(root)) + swift_files(app_sources(root)):
        if path.name == PLATFORM_FILE:
            continue
        for number, line in code_lines(path):
            code = line.split("//", 1)[0]
            if PLATFORM_CONDITION.search(code) or PLATFORM_IMPORT.search(code):
                hits.append(f"{where(path, root, number)}: {line.strip()}")
    return hits


GATES = {
    "kit non-Foundation imports": gate_kit_purity,
    "@Published outside AppModel": gate_published_ownership,
    "stored static var": gate_no_static_mutable,
    "view reach-through into model actors": gate_views_stay_out_of_actors,
    f"platform-specific code outside {PLATFORM_FILE}": gate_platform_seam,
    "comment lines off their entries": gate_prose_ceiling,
    "comment line entries raised above main": gate_no_entry_above_main,
}


def main(root: Path = ROOT) -> int:
    failed = False
    for name, gate in GATES.items():
        hits = gate(root)
        print(f"{name}: {len(hits)}")
        for hit in hits:
            print(f"  {hit}")
        failed = failed or bool(hits)
    return 1 if failed else 0


if __name__ == "__main__":
    if "--lower" in sys.argv:
        print("\n".join(lower_entries(ROOT)))
    sys.exit(main())
