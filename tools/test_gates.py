"""Each gate counts what it exists to count, in a tree planted for the purpose.

    python3 -m unittest tools.test_gates
"""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools import gates


class GateTests(unittest.TestCase):
    def plant(self, files: dict[str, str]) -> Path:
        root = Path(tempfile.mkdtemp(prefix="warm-gun-gates-"))
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        for relative, text in files.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        return root

    def test_the_kit_imports_foundation_and_nothing_else(self):
        root = self.plant({
            "WarmGunKit/Sources/WarmGunKit/Fine.swift": "import Foundation\n",
            "WarmGunKit/Sources/WarmGunKit/Stray.swift": "import Foundation\nimport SwiftUI\n// import UIKit\n",
        })
        self.assertEqual(gates.gate_kit_purity(root),
                         ["WarmGunKit/Sources/WarmGunKit/Stray.swift:2: import SwiftUI"])

    def test_published_state_has_one_home_in_the_app_model(self):
        root = self.plant({
            "WarmGun/AppModel.swift": "@Published var fine = 0\n",
            "WarmGun/Other.swift": "// @Published in prose\n    @Published var stray = 0\n",
        })
        self.assertEqual(gates.gate_published_ownership(root),
                         ["WarmGun/Other.swift:2: @Published outside AppModel.swift"])

    def test_a_stored_static_var_is_shared_state_and_a_computed_one_is_not(self):
        root = self.plant({"WarmGun/Statics.swift": "\n".join([
            "static var counter = 0",
            "private static var cache: [String: Int] = [:]",
            "static var made: Int = { 1 }()",
            "static var computed: Int { 1 }",
            "nonisolated static var directory: URL {",
            "static let constant = 0",
            "// static var inProse = 0",
        ]) + "\n"})
        self.assertEqual(gates.gate_no_static_mutable(root),
                         [f"WarmGun/Statics.swift:{n}: stored static var" for n in (1, 2, 3)])

    def test_a_view_reaches_the_model_and_never_its_machinery(self):
        root = self.plant({
            "WarmGun/AppModel.swift": "model.engine.play()\n",
            "WarmGun/SomeView.swift": "model.engine.play()\nmodel.engineering()\nmodel.cached\nmodel.client\n",
        })
        self.assertEqual(gates.gate_views_stay_out_of_actors(root),
                         ["WarmGun/SomeView.swift:1: model.engine", "WarmGun/SomeView.swift:4: model.client"])

    def test_the_phone_and_the_mac_part_ways_in_one_file(self):
        root = self.plant({
            "WarmGun/Platform.swift": "#if os(iOS)\nimport UIKit\n#endif\n",
            "WarmGun/Elsewhere.swift": "\n".join([
                "#if os(iOS)",
                "#elseif os(macOS)",
                "#if DEBUG",
                "#if !DEBUG",
                "#if DEBUG && os(iOS)",
                "#if targetEnvironment(simulator)",
                "import UIKit",
                "@_exported import AppKit",
                "import class UIKit.UIDevice",
                "import Foundation; import Cocoa",
                "// #if os(iOS)",
                "let x = 1 // import UIKit",
                "import Foundation",
            ]) + "\n",
            "WarmGunKit/Sources/WarmGunKit/Kit.swift": "#if canImport(UIKit)\n",
        })
        self.assertEqual(gates.gate_platform_seam(root), [
            "WarmGunKit/Sources/WarmGunKit/Kit.swift:1: #if canImport(UIKit)",
            "WarmGun/Elsewhere.swift:1: #if os(iOS)",
            "WarmGun/Elsewhere.swift:2: #elseif os(macOS)",
            "WarmGun/Elsewhere.swift:5: #if DEBUG && os(iOS)",
            "WarmGun/Elsewhere.swift:6: #if targetEnvironment(simulator)",
            "WarmGun/Elsewhere.swift:7: import UIKit",
            "WarmGun/Elsewhere.swift:8: @_exported import AppKit",
            "WarmGun/Elsewhere.swift:9: import class UIKit.UIDevice",
            "WarmGun/Elsewhere.swift:10: import Foundation; import Cocoa",
        ])

    def test_prose_is_every_swift_or_shell_line_that_is_only_a_comment(self):
        root = self.plant({
            "WarmGun/A.swift": "/// what it is\nlet x = 1 // a trailing note\n    // an aside\nlet y = 2\n",
            "WarmGunKit/Tests/WarmGunKitTests/T.swift": "// why the test asks this\n@Test func t() {}\n",
            "WarmGunKit/Package.swift": "// swift-tools-version: 6.0\n",
            "install.sh": "#!/bin/zsh\n# why it does this\nset -e\n",
            "tools/githooks/pre-commit": "#!/bin/sh\n# the hook's reason\nexec true\n",
            "tools/gates.py": "# not counted\nx = 1\n",
            ".gitignore": "# not a script\nbuild/\n",
            "README.md": "# Not a script\n",
        })
        self.assertEqual(sum(gates.prose_by_file(root).values()), 5)

    def test_prose_is_kept_per_file(self):
        root = self.plant({"WarmGun/A.swift": "// one\n// two\nlet x = 1\n", "WarmGun/B.swift": "let y = 2\n",
                           "install.sh": "#!/bin/sh\n# why\n"})
        self.assertEqual(gates.prose_by_file(root), {"WarmGun/A.swift": 2, "install.sh": 1})

    def with_entries(self, files: dict[str, str], entries: dict[str, int]) -> Path:
        return self.plant({**files, gates.BASELINE_PATH: json.dumps({gates.PROSE_SECTION: entries})})

    def test_a_file_at_its_entry_passes(self):
        root = self.with_entries({"WarmGun/A.swift": "// one\n"}, {"WarmGun/A.swift": 1})
        self.assertEqual(gates.gate_prose_ceiling(root), [])

    def test_a_file_that_grew_is_named_even_when_another_shrank_by_as_much(self):
        root = self.with_entries({"WarmGun/A.swift": "// one\n// two\n", "WarmGun/B.swift": "let y = 2\n"},
                                 {"WarmGun/A.swift": 1, "WarmGun/B.swift": 1})
        self.assertEqual(gates.gate_prose_ceiling(root), [
            "WarmGun/A.swift holds 2 comment lines, over its entry of 1: say it in a name or a test",
            "WarmGun/B.swift holds 0 comment lines, under its entry of 1: run python3 tools/gates.py --lower"])

    def test_a_new_file_enters_at_zero(self):
        root = self.with_entries({"WarmGun/New.swift": "// one\n"}, {})
        self.assertEqual(gates.gate_prose_ceiling(root), [
            "WarmGun/New.swift holds 1 comment lines, over its entry of 0: say it in a name or a test"])

    def test_lowering_takes_every_fall_and_refuses_every_rise(self):
        root = self.with_entries({"WarmGun/A.swift": "// one\n", "WarmGun/B.swift": "// one\n// two\n"},
                                 {"WarmGun/A.swift": 3, "WarmGun/B.swift": 1, "WarmGun/Gone.swift": 2})
        said = gates.lower_entries(root)
        self.assertEqual(json.loads((root / gates.BASELINE_PATH).read_text(encoding="utf-8")),
                         {gates.PROSE_SECTION: {"WarmGun/A.swift": 1, "WarmGun/B.swift": 1}})
        self.assertEqual(said, [
            "lowered WarmGun/A.swift from 3 to 1",
            "refused WarmGun/B.swift: it holds 2, over its entry of 1",
            "could not match WarmGun/Gone.swift: nothing is there now and git names no rename of it"])

    def git(self, root: Path, *args: str) -> None:
        subprocess.run(["git", "-C", str(root), "-c", "user.name=a", "-c", "user.email=a@example.invalid", *args],
                       capture_output=True, check=True)

    def with_a_main(self, files: dict[str, str], entries: dict[str, int]) -> Path:
        root = self.with_entries(files, entries)
        self.git(root, "init", "-q", "-b", "main")
        self.git(root, "add", "-A")
        self.git(root, "commit", "-q", "-m", "first")
        self.git(root, "update-ref", "refs/remotes/origin/main", "HEAD")
        return root

    def test_lowering_carries_a_renamed_files_entry(self):
        root = self.with_a_main({"WarmGun/A.swift": "// one\n// two\nlet x = 1\n"}, {"WarmGun/A.swift": 2})
        self.git(root, "mv", "WarmGun/A.swift", "WarmGun/B.swift")
        said = gates.lower_entries(root)
        self.assertEqual(json.loads((root / gates.BASELINE_PATH).read_text(encoding="utf-8")),
                         {gates.PROSE_SECTION: {"WarmGun/B.swift": 2}})
        self.assertEqual(said, ["carried WarmGun/A.swift to WarmGun/B.swift"])

    def test_an_entry_raised_by_hand_stands_above_what_main_holds(self):
        root = self.with_a_main({"WarmGun/A.swift": "// one\n"}, {"WarmGun/A.swift": 1})
        self.plant_over(root, {"WarmGun/A.swift": "// one\n// two\n",
                               gates.BASELINE_PATH: json.dumps({gates.PROSE_SECTION: {"WarmGun/A.swift": 2}})})
        self.assertEqual(gates.gate_no_entry_above_main(root), [
            "WarmGun/A.swift stands at 2, above the 1 main holds: an entry only comes down"])

    def test_a_renamed_files_entry_is_no_raise(self):
        root = self.with_a_main({"WarmGun/A.swift": "// one\n// two\nlet x = 1\n"}, {"WarmGun/A.swift": 2})
        self.git(root, "mv", "WarmGun/A.swift", "WarmGun/B.swift")
        self.plant_over(root, {gates.BASELINE_PATH: json.dumps({gates.PROSE_SECTION: {"WarmGun/B.swift": 2}})})
        self.assertEqual(gates.gate_no_entry_above_main(root), [])

    def plant_over(self, root: Path, files: dict[str, str]) -> None:
        for relative, text in files.items():
            (root / relative).write_text(text, encoding="utf-8")

    def test_main_runs_every_gate_this_file_defines(self):
        defined = {name for name in dir(gates) if name.startswith("gate_")}
        self.assertEqual({gate.__name__ for gate in gates.GATES.values()}, defined)


if __name__ == "__main__":
    unittest.main()
