"""Each gate counts what it exists to count, in a tree planted for the purpose.

    python3 -m unittest tools.test_gates
"""
from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from tools import gates


class GateTests(unittest.TestCase):
    def plant(self, files: dict[str, str]) -> Path:
        root = Path(tempfile.mkdtemp(prefix="warm-gun-gates-"))
        self.addCleanup(shutil.rmtree, root)
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
        self.assertEqual(gates.prose_lines(root), 5)

    def test_the_comment_lines_hold_their_ceiling_and_a_drop_must_lower_it(self):
        root = self.plant({"WarmGun/A.swift": "// one\n// two\nlet x = 1\n"})
        self.assertEqual(gates.gate_prose_ceiling(root, ceiling=2), [])
        self.assertEqual(gates.gate_prose_ceiling(root, ceiling=1), [
            "2 comment lines, over the ceiling of 1: say it in a name or a test, or remove as many elsewhere"])
        self.assertEqual(gates.gate_prose_ceiling(root, ceiling=3), [
            "2 comment lines, under the ceiling of 3: lower PROSE_CEILING to 2"])

    def test_main_runs_every_gate_this_file_defines(self):
        defined = {name for name in dir(gates) if name.startswith("gate_")}
        self.assertEqual({gate.__name__ for gate in gates.GATES.values()}, defined)


if __name__ == "__main__":
    unittest.main()
