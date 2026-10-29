#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# test_fe_release.py -- tools/fe_release.py, the release tag rules
# (DOC-008, SR-1, SR-4). No git.
#
#   python3 -m unittest discover -s tools/tests -v

import os
import subprocess
import sys
import unittest

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
import fe_release  # noqa: E402

# Names that are not fe-<major>.<minor>.<patch> with decimal fields and no
# leading zero (SR-1). U+0661 is an Arabic-Indic digit one.
NOT_TAGS = ["fe-1.0", "fe-1", "fe-1.0.0.0", "fe-01.0.0", "fe-1.00.0",
            "fe-1.0.01", "fe-1.0.0-rc1", "fe-1.0.0 ", " fe-1.0.0", "v1.0.0",
            "FE-1.0.0", "fe-1.0.x", "fe--1.0.0", "fe-1..0", "fe-\u0661.0.0",
            "fe-+1.0.0", ""]
TAGS = {"fe-0.0.0": (0, 0, 0), "fe-1.0.0": (1, 0, 0),
        "fe-10.20.30": (10, 20, 30), "fe-1.9.3": (1, 9, 3)}


class TestParse(unittest.TestCase):
    def test_tags(self):
        for name, ver in TAGS.items():
            self.assertEqual(fe_release.parse_tag(name), ver, name)

    def test_not_tags(self):
        for name in NOT_TAGS:
            self.assertIsNone(fe_release.parse_tag(name), repr(name))


class TestLatest(unittest.TestCase):
    def test_numeric_not_lexical(self):
        self.assertEqual(fe_release.latest_tag(["fe-1.9.3", "fe-1.10.0"]),
                         "fe-1.10.0")
        self.assertEqual(fe_release.latest_tag(["fe-1.10.0", "fe-1.9.3"]),
                         "fe-1.10.0")

    def test_field_order(self):
        self.assertEqual(fe_release.latest_tag(
            ["fe-1.99.99", "fe-2.0.0", "fe-1.100.0"]), "fe-2.0.0")
        self.assertEqual(fe_release.latest_tag(["fe-1.2.10", "fe-1.2.9"]),
                         "fe-1.2.10")

    def test_ignores_other_names(self):
        self.assertEqual(fe_release.latest_tag(
            NOT_TAGS + ["fe-1.0.0", "fe-9.0"]), "fe-1.0.0")
        self.assertEqual(fe_release.latest_tag(["fe-01.0.0", "fe-1.0.0"]),
                         "fe-1.0.0")

    def test_empty_selects_branch(self):
        self.assertIsNone(fe_release.latest_tag([]))
        self.assertIsNone(fe_release.latest_tag(NOT_TAGS))

    def test_one(self):
        self.assertEqual(fe_release.latest_tag(["fe-1.0.0"]), "fe-1.0.0")


class TestCli(unittest.TestCase):
    """The command docs.yml runs: names on stdin, the latest on stdout."""
    def latest(self, text):
        r = subprocess.run([sys.executable, os.path.join(TOOLS,
                            "fe_release.py"), "latest"], input=text,
                           text=True, stdout=subprocess.PIPE)
        self.assertEqual(r.returncode, 0)
        return r.stdout

    def test_latest(self):
        self.assertEqual(self.latest("fe-1.9.3\nfe-1.10.0\nfe-x\n"),
                         "fe-1.10.0\n")

    def test_none(self):
        self.assertEqual(self.latest(""), "")
        self.assertEqual(self.latest("fe-1.0\nv2.0.0\n"), "")


if __name__ == "__main__":
    unittest.main()
