"""The coupling gates — numbers with a target of zero that fail the build.

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

Run: ``python3 tools/gates.py`` (exit 0 = all gates hold).
"""

from __future__ import annotations

import re
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


def kit_sources(root: Path) -> Path:
    return root / "WarmGunKit" / "Sources"


def app_sources(root: Path) -> Path:
    return root / "WarmGun"


def swift_files(directory: Path) -> list[Path]:
    return sorted(directory.rglob("*.swift"))


def code_lines(path: Path):
    """(line_number, line) with comment-only lines dropped — a gate must count
    code, not prose about code."""
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.strip().startswith("//"):
            continue
        yield number, line


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
    sys.exit(main())
