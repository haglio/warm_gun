from __future__ import annotations

import contextlib
import io
import unittest
from unittest import mock

from app_support.sanitize import ListUnreadable

from tools import sanitize_tree


def _run_with_terms(**the_computers_terms) -> tuple[int, str]:
    told = io.StringIO()
    with mock.patch.object(sanitize_tree, "the_computers_terms", **the_computers_terms), \
            contextlib.redirect_stderr(told), contextlib.redirect_stdout(io.StringIO()):
        code = sanitize_tree.main()
    return code, told.getvalue()


class SanitizeTreeTests(unittest.TestCase):
    def test_a_computer_that_keeps_no_list_leaves_the_tree_unscanned(self):
        code, told = _run_with_terms(return_value=None)
        self.assertEqual(code, 2)
        self.assertIn("NOT scanned", told)

    def test_a_list_that_should_be_there_and_cannot_be_read_leaves_the_tree_unscanned(self):
        code, told = _run_with_terms(side_effect=ListUnreadable("the blocklist at /made/up cannot be read"))
        self.assertEqual(code, 2)
        self.assertIn("the blocklist at /made/up cannot be read", told)

    def test_the_tree_is_scanned_against_the_computers_terms(self):
        a_word_no_file_holds = "q" * 40
        code, told = _run_with_terms(return_value=[a_word_no_file_holds])
        self.assertEqual(code, 0)
        self.assertEqual(told, "")


if __name__ == "__main__":
    unittest.main()
