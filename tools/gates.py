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

Run: ``python3 tools/gates.py`` (exit 0 = all gates hold).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KIT_SOURCES = ROOT / "WarmGunKit" / "Sources"
APP = ROOT / "WarmGun"

KIT_ALLOWED_IMPORTS = {"Foundation"}
MODEL_FILE = "AppModel.swift"
# The reference-typed machinery the model owns; views may not reach into it.
ACTORS = ("engine", "cache", "prefetcher", "client")


def swift_files(root: Path) -> list[Path]:
    return sorted(root.rglob("*.swift"))


def code_lines(path: Path):
    """(line_number, line) with comment-only lines dropped — a gate must count
    code, not prose about code."""
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if line.strip().startswith("//"):
            continue
        yield number, line


def gate_kit_purity() -> list[str]:
    hits = []
    for path in swift_files(KIT_SOURCES):
        for number, line in code_lines(path):
            match = re.match(r"\s*import\s+(\w+)", line)
            if match and match.group(1) not in KIT_ALLOWED_IMPORTS:
                hits.append(f"{path.relative_to(ROOT)}:{number}: import {match.group(1)}")
    return hits


def gate_published_ownership() -> list[str]:
    hits = []
    for path in swift_files(APP):
        if path.name == MODEL_FILE:
            continue
        for number, line in code_lines(path):
            if "@Published" in line:
                hits.append(f"{path.relative_to(ROOT)}:{number}: @Published outside {MODEL_FILE}")
    return hits


def gate_no_static_mutable() -> list[str]:
    hits = []
    for path in swift_files(KIT_SOURCES) + swift_files(APP):
        for number, line in code_lines(path):
            if re.search(r"\bstatic\s+var\b", line) and "{" not in line.split("static")[1][:80].replace("var", "", 1).split("=")[0]:
                # `static var x: T { ... }` is a computed accessor, not storage;
                # only stored `static var` is shared mutable state.
                if not re.search(r"\bstatic\s+var\b[^=\n]*\{", line):
                    hits.append(f"{path.relative_to(ROOT)}:{number}: stored static var")
    return hits


def gate_views_stay_out_of_actors() -> list[str]:
    hits = []
    for path in swift_files(APP):
        if path.name == MODEL_FILE:
            continue
        for number, line in code_lines(path):
            for actor in ACTORS:
                if re.search(rf"\bmodel\.{actor}\b", line):
                    hits.append(f"{path.relative_to(ROOT)}:{number}: model.{actor}")
    return hits


def main() -> int:
    gates = {
        "kit non-Foundation imports": gate_kit_purity(),
        "@Published outside AppModel": gate_published_ownership(),
        "stored static var": gate_no_static_mutable(),
        "view reach-through into model actors": gate_views_stay_out_of_actors(),
    }
    failed = False
    for name, hits in gates.items():
        print(f"{name}: {len(hits)}")
        for hit in hits:
            print(f"  {hit}")
        failed = failed or bool(hits)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
