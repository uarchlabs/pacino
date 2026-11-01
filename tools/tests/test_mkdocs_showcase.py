#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# test_mkdocs_showcase.py -- the Showcase release handling of
# tools/mkdocs_showcase.py (DOC-008, SR-6 to SR-8). No git.
#
# TestBuild runs mkdocs build four times into a temporary directory, as
# a local preview, as CI with no tag, as CI with a tag whose pages are a
# copy of examples/fe_demo/docs/ with one line added, and with
# SHOWCASE_SHOW_ALL=1. It is skipped when mkdocs is not installed. The
# builds check the shown list of the repo's mkdocs.yml: the scenarios it
# hides have no page, no nav entry and no landing table row; TestShownList
# checks the list, the nav filter and the link handling on their own.
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
ENV_KEYS = ["SHOWCASE_CI", "SHOWCASE_TAG", "SHOWCASE_DEMO_DIR",
            "SHOWCASE_SHOW_ALL"]

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


@unittest.skipIf(hook is None, "mkdocs is not installed")
class TestShownList(unittest.TestCase):
    SHOWN = {"fd01_a"}

    def tearDown(self):
        hook.HIDDEN = set()
        os.environ.pop("SHOWCASE_SHOW_ALL", None)

    def test_shown_list(self):
        self.assertIsNone(hook.shown_list({"extra": {}}))
        self.assertEqual(hook.shown_list(
            {"extra": {"showcase_shown": ["fd01_a"]}}), {"fd01_a"})
        os.environ["SHOWCASE_SHOW_ALL"] = "1"
        self.assertIsNone(hook.shown_list(
            {"extra": {"showcase_shown": ["fd01_a"]}}))
        os.environ.pop("SHOWCASE_SHOW_ALL")
        for bad in ("fd01_a", ["demo_explainer"], [1]):
            with self.assertRaises(ValueError):
                hook.shown_list({"extra": {"showcase_shown": bad}})

    def test_drop_nav(self):
        nav = [{"Home": "index.md"},
               {"Showcase": ["showcase/index.md",
                             {"Demos": [
                                 {"Explainer": "showcase/fe_demo/x.md"},
                                 {"A": "showcase/fe_demo/fd01_a.md"},
                                 {"B": "showcase/fe_demo/fd02_b.md"}]},
                             {"Only hidden": [
                                 {"C": "showcase/fe_demo/fd03_c.md"}]}]}]
        self.assertEqual(hook.drop_nav(nav, self.SHOWN),
                         [{"Home": "index.md"},
                          {"Showcase": ["showcase/index.md",
                                        {"Demos": [
                                            {"Explainer":
                                             "showcase/fe_demo/x.md"},
                                            {"A": "showcase/fe_demo/"
                                                  "fd01_a.md"}]}]}])
        self.assertEqual(hook.drop_nav(nav, None), nav)

    def test_unlink_hidden(self):
        hook.HIDDEN = {"fd02_b"}
        gh = "https://github.com/u/p/blob/main/examples/fe_demo/docs"
        md = ("| 1 | [A](fe_demo/fd01_a.md) | x |\n"
              "| 2 | [B](fe_demo/fd02_b.md) | y |\n"
              f"    - Frontend demo: [fd01_a: A]({gh}/fd01_a.md)\n"
              f"    - Frontend demo: [fd02_b: B]({gh}/fd02_b.md)\n"
              "See [B](fd02_b.md#3-program) and [A](fd01_a.md).")
        self.assertEqual(hook.unlink_hidden(md),
                         "| 1 | [A](fe_demo/fd01_a.md) | x |\n"
                         f"    - Frontend demo: [fd01_a: A]({gh}/fd01_a.md)\n"
                         "See B and [A](fd01_a.md).")
        hook.HIDDEN = set()
        self.assertEqual(hook.unlink_hidden(md), md)


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
        # The repo's shown list, and the scenario pages it hides.
        import yaml
        with open(os.path.join(ROOT, "mkdocs.yml")) as f:
            extra = yaml.safe_load(f).get("extra") or {}
        shown = extra.get("showcase_shown")
        pages = sorted(n[:-3] for n in os.listdir(os.path.join(DEMO, "docs"))
                       if re.fullmatch(r"fd\d\d_[a-z0-9_]+\.md", n))
        cls.shown = pages if shown is None else sorted(shown)
        cls.hidden = [p for p in pages if p not in cls.shown]

    def check_shown(self, read, site_has, every=False):
        """The shown scenarios' pages built, the hidden ones absent from
        the build, the nav and the landing table (all built when
        every)."""
        index = read("showcase/index.html")
        for s in self.shown:
            self.assertTrue(site_has(f"showcase/fe_demo/{s}/index.html"), s)
            self.assertIn(f'href="fe_demo/{s}/"', index, s)
        for s in self.hidden:
            built = site_has(f"showcase/fe_demo/{s}/index.html")
            self.assertEqual(built, every, s)
            self.assertEqual(f'href="fe_demo/{s}/"' in index, every, s)
            self.assertEqual(f"/{s}/" in read("index.html"), every, s)
            # The architecture pages' "Frontend demo:" items.
            linked = f"docs/{s}.md" in self.arch_src()
            self.assertEqual(f"docs/{s}.md" in self.arch(read),
                             every and linked, s)
        if "fd09_tage" in self.shown:
            self.assertTrue(site_has("showcase/fe_demo/fd09_blocks.svg"))

    # The architecture pages that link scenarios, read once per build.
    ARCH = ["frontend/fetch/overview", "frontend/bpu/dual_prediction",
            "frontend/bpu/sc", "mmu/pma"]

    def arch(self, read):
        return "".join(read(f"{p}/index.html") for p in self.ARCH)

    def arch_src(self):
        out = ""
        for p in self.ARCH:
            with open(os.path.join(ROOT, "docs", p + ".md")) as f:
                out += f.read()
        return out

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
        self.site_has = lambda rel: os.path.isfile(os.path.join(site, rel))
        return read

    def test_local(self):
        read = self.build("local")
        self.check_shown(read, self.site_has)
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
        self.check_shown(read, self.site_has)
        # Nothing was written into the tracked pages.
        with open(os.path.join(DEMO, "docs", "fd02_steady.md")) as f:
            self.assertNotIn(self.MARK, f.read())

    def test_show_all(self):
        read = self.build("show_all", SHOWCASE_SHOW_ALL="1")
        self.check_shown(read, self.site_has, every=True)


if __name__ == "__main__":
    unittest.main()
