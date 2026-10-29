#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# test_mkdocs_showcase.py -- the Showcase release handling of
# tools/mkdocs_showcase.py (DOC-008, SR-6 to SR-8). No git.
#
# TestBuild runs mkdocs build three times into a temporary directory, as
# a local preview, as CI with no tag, and as CI with a tag whose pages
# are a copy of examples/fe_demo/docs/ with one line added. It is skipped
# when mkdocs is not installed.
#
#   python3 -m unittest discover -s tools/tests -v

import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

TESTS = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(TESTS)
ROOT = os.path.dirname(TOOLS)
DEMO = os.path.join(ROOT, "examples", "fe_demo")
ENV_KEYS = ["SHOWCASE_CI", "SHOWCASE_TAG", "SHOWCASE_DEMO_DIR"]

try:
    sys.path.insert(0, TOOLS)
    import mkdocs_showcase as hook
except ImportError:
    hook = None

MKDOCS = shutil.which("mkdocs")
REPO = "https://github.com/uarchlabs/pacino"
LANDING = ("# Showcase\n\n<!-- RELEASE_BEGIN -->\nLocal preview text.\n"
           "<!-- RELEASE_END -->\n\nBody.\n")


class Page:
    def __init__(self, src_uri):
        self.file = type("F", (), {"src_uri": src_uri})()


def env(**kw):
    e = {k: v for k, v in os.environ.items() if k not in ENV_KEYS}
    e.update(kw)
    return e


@unittest.skipIf(hook is None, "mkdocs is not installed")
class TestLanding(unittest.TestCase):
    def setUp(self):
        self.saved = {k: os.environ.pop(k) for k in ENV_KEYS
                      if k in os.environ}

    def tearDown(self):
        for k in ENV_KEYS:
            os.environ.pop(k, None)
        os.environ.update(self.saved)

    def landing(self):
        return hook.on_page_markdown(LANDING, Page("showcase/index.md"),
                                     {"repo_url": REPO + "/"}, None)

    def test_local_keeps_text(self):
        self.assertEqual(self.landing(), LANDING)

    def test_ci_unreleased(self):
        os.environ["SHOWCASE_CI"] = "1"
        out = self.landing()
        self.assertIn("<!-- RELEASE_BEGIN -->\n**Unreleased.**", out)
        self.assertNotIn("Local preview text", out)
        self.assertTrue(out.endswith("<!-- RELEASE_END -->\n\nBody.\n"))

    def test_ci_tag(self):
        os.environ.update(SHOWCASE_CI="1", SHOWCASE_TAG="fe-1.2.3")
        out = self.landing()
        self.assertIn(f"**Release fe-1.2.3.**", out)
        self.assertIn(f"[fe-1.2.3]({REPO}/tree/fe-1.2.3)", out)
        self.assertNotIn("Local preview text", out)

    def test_ci_missing_markers_fails(self):
        os.environ["SHOWCASE_CI"] = "1"
        with self.assertRaises(ValueError):
            hook.on_page_markdown("# Showcase\n", Page("showcase/index.md"),
                                  {"repo_url": REPO}, None)


@unittest.skipIf(MKDOCS is None, "mkdocs is not installed")
class TestBuild(unittest.TestCase):
    MARK = "TAG_ONLY_LINE_DOC008"

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="test_mkdocs_showcase.")
        # The tag's examples/fe_demo as git archive would extract it:
        # docs/ and waves/ copied, programs/ as empty files of the right
        # names (the hook only tests that they exist).
        cls.demo = os.path.join(cls.tmp, "tag", "examples", "fe_demo")
        shutil.copytree(os.path.join(DEMO, "docs"),
                        os.path.join(cls.demo, "docs"))
        shutil.copytree(os.path.join(DEMO, "waves"),
                        os.path.join(cls.demo, "waves"),
                        ignore=shutil.ignore_patterns("__pycache__"))
        os.makedirs(os.path.join(cls.demo, "programs"))
        for n in os.listdir(os.path.join(cls.demo, "docs")):
            if re.fullmatch(r"fd\d\d_[a-z0-9_]+\.md", n):
                open(os.path.join(cls.demo, "programs",
                                  n[:-3] + ".svh"), "w").close()
        with open(os.path.join(cls.demo, "docs", "fd02_steady.md"), "a") as f:
            f.write(f"\n{cls.MARK}\n")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def build(self, name, **kw):
        site = os.path.join(self.tmp, "site_" + name)
        r = subprocess.run([MKDOCS, "build", "-q", "-d", site], cwd=ROOT,
                           env=env(**kw), text=True, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT)
        self.assertEqual(r.returncode, 0, r.stdout)

        def read(rel):
            with open(os.path.join(site, rel)) as f:
                return f.read()
        return read

    def test_local(self):
        read = self.build("local")
        self.assertIn("<strong>Local preview of the branch.</strong>",
                      read("showcase/index.html"))
        page = read("showcase/fe_demo/fd02_steady/index.html")
        self.assertNotIn(self.MARK, page)
        self.assertIn("blob/main/examples/fe_demo/docs/fd02_steady.md", page)

    def test_ci_unreleased(self):
        read = self.build("unreleased", SHOWCASE_CI="1")
        self.assertIn("<strong>Unreleased.</strong>",
                      read("showcase/index.html"))
        self.assertNotIn(self.MARK,
                         read("showcase/fe_demo/fd02_steady/index.html"))

    def test_ci_tag(self):
        read = self.build("tag", SHOWCASE_CI="1", SHOWCASE_TAG="fe-9.9.9",
                          SHOWCASE_DEMO_DIR=self.demo)
        index = read("showcase/index.html")
        self.assertIn("<strong>Release fe-9.9.9.</strong>", index)
        self.assertIn(f'href="{REPO}/tree/fe-9.9.9"', index)
        page = read("showcase/fe_demo/fd02_steady/index.html")
        self.assertIn(self.MARK, page)
        self.assertIn("blob/fe-9.9.9/examples/fe_demo/docs/fd02_steady.md",
                      page)
        self.assertIn("<strong>Files:</strong>", page)
        # Nothing was written into the tracked pages.
        with open(os.path.join(DEMO, "docs", "fd02_steady.md")) as f:
            self.assertNotIn(self.MARK, f.read())


if __name__ == "__main__":
    unittest.main()
