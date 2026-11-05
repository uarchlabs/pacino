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
# The working specifications (DOC-013, DOC-014, SR-17 to SR-19): TestSpec checks
# the line handling and the rendered Markdown of a page with a spec: list, local
# and in CI with a tag, a document missing at the tag, and a page without a
# list. The local and tag builds of TestBuild check the built page; the tag
# build reads a copy of planning/arch and planning/interfaces with one line
# added and one document removed. TestBuild also checks the top menu's order.
#
# The unit pages (DOC-015, SR-17a): TestUnit checks the rendered Markdown of
# a unit page, a heading entry, the Overview's single sections and a
# Specification link, and the generator's handling of a unit page. The
# builds check the built branch prediction unit page.
#
#   python3 -m unittest discover -s tools/tests -v

import hashlib
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
            "SHOWCASE_SHOW_ALL", "SHOWCASE_SPEC_DIR"]

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


@unittest.skipIf(hook is None, "mkdocs is not installed")
class TestSpec(unittest.TestCase):
    ENTRY = {"rtl": "done", "docs": "planned", "covers": "the unit",
             "spec": ["planning/arch/a_decisions.md",
                      "planning/interfaces/a_interfaces.md"]}
    PAGE = ("<!-- SPDX-License-Identifier: CC-BY-4.0 -->\n# Unit\n\n"
            "<!-- placeholder:start -->\nold\n<!-- placeholder:end -->\n")
    DOC = ("<!-- SPDX-License-Identifier: Apache-2.0 -->\n"
           "<!-- SPDX-FileCopyrightText: J <j@example.com> -->\n"
           "# Title\n```\n# not a heading\n```\n\n## Part\n\n"
           "Captures:\n  a -- first\n    b -- second\n")

    def setUp(self):
        self.saved = {k: os.environ.pop(k) for k in ENV_KEYS
                      if k in os.environ}
        self.tmp = tempfile.mkdtemp(prefix="test_mkdocs_spec.")
        for path in self.ENTRY["spec"]:
            full = os.path.join(self.tmp, path)
            os.makedirs(os.path.dirname(full))
            with open(full, "w") as f:
                f.write(self.DOC)
        hook.SPECS = {"unit.md": self.ENTRY}

    def tearDown(self):
        hook.SPECS = {}
        shutil.rmtree(self.tmp)
        for k in ENV_KEYS:
            os.environ.pop(k, None)
        os.environ.update(self.saved)

    def render(self, src="unit.md", page=None):
        return hook.on_page_markdown(page or self.PAGE, Page(src),
                                     {"repo_url": REPO + "/"}, None)

    def test_keep_indented(self):
        cases = [
            # A paragraph holding an indented line is fenced whole.
            (["Captures:", "  a", "    b"],
             ["", "```", "Captures:", "  a", "    b", "```", ""]),
            (["  a", "  b"], ["", "```", "  a", "  b", "```", ""]),
            # A hand-aligned list continuation is fenced too.
            (["- x : p0", "        u0"],
             ["", "```", "- x : p0", "        u0", "```", ""]),
            # Plain text, wrapped list items, four-space nesting and
            # indented code are left to Markdown.
            (["one", "two"], ["one", "two"]),
            (["- a", "  wrapped", "1. b", "   wrapped"],
             ["- a", "  wrapped", "1. b", "   wrapped"]),
            (["-   a", "    -   b"], ["-   a", "    -   b"]),
            (["    code", "    more"], ["    code", "    more"]),
            (["| a |", "  | b |"], ["| a |", "  | b |"]),
            # A nested item at two spaces would be flattened.
            (["- a", "  - b"], ["", "```", "- a", "  - b", "```", ""]),
            # A heading and a rule end a paragraph.
            (["### H", "- a", "  b"], ["### H", "", "- a", "  b"]),
            (["text", "---"], ["text", "", "---", ""]),
            # Fenced lines are not touched.
            (["```", "x", "  y", "```"], ["```", "x", "  y", "```"]),
            # A name pattern keeps its asterisk.
            (["A_* and B_*, `C_*`"], ["A_\\* and B_\\*, `C_*`"]),
            # A name in angle brackets is shown; an autolink stays a link.
            (["(<PRED>_X, `<PRED>_Y`) <https://a.b/c>"],
             ["(&lt;PRED&gt;_X, `<PRED>_Y`) <https://a.b/c>"]),
        ]
        for lines, want in cases:
            self.assertEqual(hook.keep_indented(lines), want, lines)

    def test_demote_headings(self):
        self.assertEqual(
            hook.demote_headings(["# a", "## b", "#### c", "##### d",
                                  "#not", "```", "# e", "```"]),
            ["### a", "#### b", "###### c", "###### d",
             "#not", "```", "# e", "```"])

    def check_page(self, out, advisory, ref):
        self.assertIn('!!! note "Working specification"\n\n    ' + advisory
                      + "\n", out)
        self.assertNotIn("Not written yet", out)
        self.assertNotIn("Meanwhile", out)
        self.assertNotIn("placeholder:", out)
        self.assertNotIn("This page will cover", out)
        self.assertTrue(out.startswith(
            "<!-- SPDX-License-Identifier: CC-BY-4.0 -->\n# Unit\n\n"
            "**Status:** RTL complete, interim documentation\n\n"
            '!!! note "Working specification"'), out)
        a = out.index('??? abstract "a_decisions.md"')
        b = out.index('??? abstract "a_interfaces.md"')
        self.assertLess(out.index('!!! note "Working'), a)
        self.assertLess(a, b)
        for path in self.ENTRY["spec"]:
            self.assertIn(f"    [{path} on GitHub]({REPO}/blob/{ref}/{path})",
                          out)
        section = out[a:b]
        # The SPDX header kept, unindented, the text indented in the section.
        self.assertIn("<!-- SPDX-FileCopyrightText: J <j@example.com> -->\n",
                      out[:a])
        self.assertIn("    ### Title\n", section)
        self.assertIn("    #### Part\n", section)
        self.assertIn("    # not a heading\n", section)
        self.assertIn("    ```\n    Captures:\n      a -- first\n"
                      "        b -- second\n    ```\n", section)

    def test_local(self):
        out = hook.spec_page(self.PAGE, "unit.md", dict(
            self.ENTRY, spec=["planning/arch/tage_cntrl_decisions.md"]), REPO)
        self.assertIn("    This page shows the planning documents and"
                      " specifications for the working tree.\n", out)
        self.assertIn(f"{REPO}/blob/main/planning/arch/"
                      "tage_cntrl_decisions.md", out)
        self.assertIn('??? abstract "tage_cntrl_decisions.md"', out)
        self.assertIn("    ### tage_cntrl Design Decisions\n", out)

    def test_ci_tag(self):
        os.environ.update(SHOWCASE_CI="1", SHOWCASE_TAG="fe-1.2.3",
                          SHOWCASE_SPEC_DIR=self.tmp)
        self.check_page(self.render(), "This page shows the planning documents"
                        " and specifications for RTL tag fe-1.2.3.", "fe-1.2.3")

    def test_status_uses_the_rtl_words(self):
        out = hook.spec_page(self.PAGE, "unit.md", dict(
            self.ENTRY, rtl="not-in-design",
            spec=["planning/arch/tage_cntrl_decisions.md"]), REPO)
        self.assertIn("**Status:** Not in the current design, interim"
                      " documentation\n", out)

    def test_ci_no_tag_reads_the_branch(self):
        os.environ["SHOWCASE_CI"] = "1"
        base, name, ref = hook.spec_source()
        self.assertEqual((base, name, ref), (hook.ROOT, "the main branch",
                                             "main"))

    def test_tag_without_spec_dir_fails(self):
        os.environ.update(SHOWCASE_CI="1", SHOWCASE_TAG="fe-1.2.3")
        with self.assertRaises(OSError):
            self.render()

    def test_document_not_in_tag_is_a_note(self):
        gone, kept = self.ENTRY["spec"]
        os.remove(os.path.join(self.tmp, gone))
        os.environ.update(SHOWCASE_CI="1", SHOWCASE_TAG="fe-1.2.3",
                          SHOWCASE_SPEC_DIR=self.tmp)
        with self.assertLogs("mkdocs.plugins", "WARNING") as logs:
            out = self.render()
        self.assertEqual(len(logs.output), 1)
        self.assertIn("unit.md", logs.output[0])
        self.assertIn(gone, logs.output[0])
        self.assertIn(f"\n`{gone}` is not in RTL tag fe-1.2.3.\n", out)
        self.assertNotIn('??? abstract "a_decisions.md"', out)
        self.assertIn('??? abstract "a_interfaces.md"', out)
        self.assertLess(out.index(f"`{gone}`"),
                        out.index(os.path.basename(kept)))

    def test_document_missing_with_no_tag_fails(self):
        # Local and CI with no tag read the checkout, where it is a table error.
        with self.assertRaises(OSError):
            hook.spec_page(self.PAGE, "unit.md", dict(
                self.ENTRY, spec=["planning/arch/no_such_doc.md"]), REPO)
        os.environ["SHOWCASE_CI"] = "1"
        with self.assertRaises(OSError):
            hook.spec_page(self.PAGE, "unit.md", dict(
                self.ENTRY, spec=["planning/arch/no_such_doc.md"]), REPO)

    def test_written_page_fails(self):
        with self.assertRaises(ValueError):
            self.render(page="# Unit\n\nWritten text.\n")

    def test_page_without_list_unchanged(self):
        self.assertEqual(self.render("other.md"), self.PAGE)
        os.environ.update(SHOWCASE_CI="1", SHOWCASE_TAG="fe-1.2.3",
                          SHOWCASE_SPEC_DIR=self.tmp)
        self.assertEqual(self.render("other.md"), self.PAGE)

    def test_hidden_scenario_link_in_document_dropped(self):
        path = os.path.join(self.tmp, self.ENTRY["spec"][0])
        with open(path, "a") as f:
            f.write("\n- See [B](fd02_b.md).\n- Kept.\n")
        os.environ.update(SHOWCASE_CI="1", SHOWCASE_TAG="fe-1.2.3",
                          SHOWCASE_SPEC_DIR=self.tmp)
        hook.HIDDEN = {"fd02_b"}
        try:
            out = self.render()
        finally:
            hook.HIDDEN = set()
        self.assertNotIn("fd02_b", out)
        self.assertIn("    - Kept.", out)

    def test_spec_errors(self):
        import gen_doc_placeholders as gen
        self.assertEqual(gen.spec_errors(self.ENTRY["spec"]), [])
        for bad in ([], "planning/arch/a.md", ["docs/a.md"],
                    ["planning/testbenches/a.md"],
                    ["planning/arch/../../a.md"], [1],
                    ["planning/arch/a.md", "planning/arch/a.md"]):
            self.assertTrue(gen.spec_errors(bad), bad)

    def test_load_specs_repo_table(self):
        specs = hook.load_specs()
        units = hook.load_units()
        # Page entries only; the unit pages' headings are in units.
        self.assertIn("system/csr.md", specs)
        self.assertFalse([k for k in specs if "#" in k])
        self.assertEqual(sorted(units), [
            "frontend/bpu/index.md", "frontend/decode/index.md",
            "frontend/fetch/index.md", "frontend/icache/index.md",
            "mmu/index.md"])
        self.assertIn("spec", units["frontend/bpu/index.md"]["TAGE"])
        # A written page, and a heading no document covers.
        self.assertNotIn("frontend/overview.md", specs)
        self.assertNotIn("frontend/overview.md", units)
        self.assertNotIn("spec",
                         units["frontend/decode/index.md"]["Fusion Combiner"])
        # Not cited (PROJECT_CORE): on no list.
        for heads in units.values():
            for e in heads.values():
                self.assertNotIn("planning/arch/pacino_cache.md",
                                 e.get("spec", []))


@unittest.skipIf(hook is None, "mkdocs is not installed")
class TestUnit(unittest.TestCase):
    """A unit page (SR-17a), rendered from a table of its own."""
    A = "planning/arch/a_decisions.md"
    B = "planning/interfaces/b_interfaces.md"
    C = "planning/arch/c_decisions.md"
    HEADS = {
        "Overview": {"rtl": "done", "docs": "planned", "covers": "the unit",
                     "see": [{"tasks": ["BP-084"]}], "spec": [A]},
        "Tags": {"rtl": "done", "docs": "planned",
                 "covers": "the tag arrays and the hit check",
                 "see": [{"tasks": ["TOOLS-004"]}, {"demo": "fd13_l1i"}],
                 "spec": [C, A]},
        "Data Arrays": {"rtl": "not-in-design", "docs": "planned",
                        "covers": "why there are none.", "spec": [B, C]},
        "Fusion": {"rtl": "planned", "docs": "planned",
                   "covers": "macro-op fusion"},
    }
    BLOCK = ("<!-- placeholder:start -->\nold\n<!-- placeholder:end -->\n")
    PAGE = ("<!-- SPDX-License-Identifier: CC-BY-4.0 -->\n# Unit\n\n"
            "## Overview\n\n" + BLOCK + "\n## Tags\n\n" + BLOCK
            + "\n## Group\n\n### Data Arrays\n\n" + BLOCK
            + "\n### Fusion\n\n" + BLOCK)
    DOC = "<!-- SPDX-License-Identifier: Apache-2.0 -->\n# Title {}\n\nText.\n"

    def setUp(self):
        self.saved = {k: os.environ.pop(k) for k in ENV_KEYS
                      if k in os.environ}
        self.tmp = tempfile.mkdtemp(prefix="test_mkdocs_unit.")
        for path in (self.A, self.B, self.C):
            full = os.path.join(self.tmp, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as f:
                f.write(self.DOC.format(os.path.basename(path)))
        os.environ.update(SHOWCASE_CI="1", SHOWCASE_TAG="fe-1.2.3",
                          SHOWCASE_SPEC_DIR=self.tmp)
        hook.UNITS = {"unit/index.md": self.HEADS}

    def tearDown(self):
        hook.UNITS = {}
        hook.HIDDEN = set()
        shutil.rmtree(self.tmp)
        for k in ENV_KEYS:
            os.environ.pop(k, None)
        os.environ.update(self.saved)

    def render(self, page=None):
        return hook.on_page_markdown(page or self.PAGE, Page("unit/index.md"),
                                     {"repo_url": REPO + "/"}, None)

    def part(self, out, heading, end):
        return out[out.index(heading + "\n"):out.index(end + "\n")]

    def test_heading_entry(self):
        import gen_doc_placeholders as gen
        out = self.render()
        tags = self.part(out, "## Tags", "## Group")
        self.assertEqual(tags, (
            "## Tags\n\n"
            "**Status:** RTL complete, interim documentation\n\n"
            "The tag arrays and the hit check.\n\n"
            "Specification: [c_decisions.md](#spec-c-decisions-md),"
            " [a_decisions.md](#spec-a-decisions-md) (in the Overview"
            " above)\n\n"
            "Related: " + gen.see_line({"tasks": ["TOOLS-004"]}) + "; "
            + gen.see_line({"demo": "fd13_l1i"}) + "\n\n"))
        # A sentence already ending in a period; no see: list, no Related.
        arrays = self.part(out, "### Data Arrays", "### Fusion")
        self.assertIn("\n\nWhy there are none.\n\n", arrays)
        self.assertIn("**Status:** Not in the current design, interim"
                      " documentation\n", arrays)
        self.assertNotIn("Related", arrays)
        # No document: the generator's status form, no Specification line.
        fusion = out[out.index("### Fusion\n"):]
        self.assertEqual(fusion, (
            "### Fusion\n\n**Status:** RTL planned. Documentation planned.\n\n"
            "Macro-op fusion.\n"))
        for text in ("Not written yet", "This page will cover", "Meanwhile",
                     "placeholder:"):
            self.assertNotIn(text, out)
        self.assertTrue(out.startswith(
            "<!-- SPDX-License-Identifier: CC-BY-4.0 -->\n# Unit\n\n"
            "## Overview\n\n**Status:** RTL complete, interim documentation"
            "\n\nThe unit.\n\nRelated: IA task: [BP-084]("), out)
        self.assertIn("\n## Group\n\n### Data Arrays\n", out)

    def test_overview_single_sections(self):
        out = self.render()
        overview = self.part(out, "## Overview", "## Tags")
        # Each document once, the Overview's own first, then each heading's
        # in page order; the advisory once, after the related links.
        self.assertEqual(re.findall(r'\?\?\? abstract "([^"]*)"', out),
                         ["a_decisions.md", "c_decisions.md",
                          "b_interfaces.md"])
        self.assertEqual(out.count("Working specification"), 1)
        self.assertLess(overview.index("Related:"),
                        overview.index('!!! note "Working specification"'))
        self.assertIn("    This page shows the planning documents and"
                      " specifications for RTL tag fe-1.2.3.\n", overview)
        self.assertEqual(overview.count("??? abstract"), 3)
        self.assertNotIn("Specification:", overview)
        for path in (self.A, self.B, self.C):
            self.assertEqual(out.count(f"{path} on GitHub"), 1)

    def test_specification_link(self):
        out = self.render()
        overview = self.part(out, "## Overview", "## Tags")
        for path in (self.A, self.B, self.C):
            anchor = hook.spec_anchor(path)
            # The target is the first line of its own section.
            self.assertIn(f'??? abstract "{os.path.basename(path)}"\n\n'
                          f'    <a id="{anchor}"></a>[{path} on GitHub]',
                          overview)
            self.assertIn(f"(#{anchor})", out[len(overview):])
        self.assertEqual(hook.spec_anchor(self.B), "spec-b-interfaces-md")

    def test_document_not_in_tag_is_a_note_with_its_target(self):
        os.remove(os.path.join(self.tmp, self.C))
        with self.assertLogs("mkdocs.plugins", "WARNING") as logs:
            out = self.render()
        self.assertEqual(len(logs.output), 1)
        self.assertIn("unit/index.md", logs.output[0])
        overview = self.part(out, "## Overview", "## Tags")
        self.assertIn(f'<a id="{hook.spec_anchor(self.C)}"></a>`{self.C}` is'
                      " not in RTL tag fe-1.2.3.\n", overview)
        self.assertNotIn('??? abstract "c_decisions.md"', out)

    def test_hidden_demo_dropped_from_related(self):
        hook.HIDDEN = {"fd13_l1i"}
        tags = self.part(self.render(), "## Tags", "## Group")
        self.assertNotIn("fd13_l1i", tags)
        self.assertIn("Related: IA task: [TOOLS-004]", tags)

    def test_written_heading_with_list_fails(self):
        page = self.PAGE.replace("## Group", "Written.\n\n## Group")
        with self.assertRaises(ValueError):
            self.render(page)

    def test_written_heading_without_list_kept(self):
        page = self.PAGE + "\nWritten.\n"
        out = self.render(page)
        self.assertTrue(out.endswith("### Fusion\n\n" + self.BLOCK.rstrip()
                                     + "\n\nWritten.\n"), out)

    def test_listed_heading_missing_fails(self):
        with self.assertRaises(ValueError):
            self.render(self.PAGE.replace("## Tags", "## Tagz"))

    def test_plain_ids(self):
        # A document's heading took tage; the page's own TAGE heading is
        # given it back, and each link follows its heading.
        html = ('<h3 id="tage">TAGE</h3><a href="#tage">doc</a>'
                '<h2 id="tage_1">TAGE<a href="#tage_1">x</a></h2>'
                '<h2 id="ras">RAS</h2>')
        items = [type("A", (), {"id": "tage_1", "children": []})(),
                 type("A", (), {"id": "ras", "children": []})()]
        self.assertEqual(hook.plain_ids(html, items),
                         '<h3 id="tage_1">TAGE</h3><a href="#tage_1">doc</a>'
                         '<h2 id="tage">TAGE<a href="#tage">x</a></h2>'
                         '<h2 id="ras">RAS</h2>')
        self.assertEqual([i.id for i in items], ["tage", "ras"])

    def test_toc_keeps_own_headings(self):
        def item(title, *children):
            return type("A", (), {"title": title, "children": list(children),
                                  "id": title.lower().replace(" ", "-")})

        self.render()
        toc = [item("Unit", item("Overview", item("Title a_decisions.md")),
                    item("Tags"),
                    item("Group", item("Data Arrays", item("Stray")),
                         item("Fusion")))]
        hook.on_page_content("", type("P", (), {
            "file": Page("unit/index.md").file, "toc": toc})(), None, None)

        def titles(items):
            return [(i.title, titles(i.children)) for i in items]

        self.assertEqual(titles(toc[0].children), [
            ("Overview", []), ("Tags", []),
            ("Group", [("Data Arrays", []), ("Fusion", [])])])

    def test_generator_unit_page(self):
        import gen_doc_placeholders as gen
        heads = {h: (f"unit/index.md#{h}", e) for h, e in self.HEADS.items()}
        new, skipped, unlisted = gen.render_unit(self.PAGE, heads)
        self.assertEqual((skipped, unlisted), ([], []))
        self.assertEqual(gen.render_unit(new, heads)[0], new)
        self.assertIn("## Tags\n\n<!-- placeholder:start -->", new)
        self.assertIn("## Group\n\n### Data Arrays\n\n<!-- placeholder:start",
                      new)
        self.assertIn("This page will cover the tag arrays", new)
        self.assertEqual(gen.unit_errors("unit/index.md", self.PAGE, heads),
                         [])
        bad = self.PAGE.replace("## Tags", "## Tagz") + "\n## Fusion\n"
        errors = gen.unit_errors("unit/index.md", bad, heads)
        self.assertEqual(len(errors), 2, errors)
        self.assertIn("'Fusion' appears twice", errors[0])
        self.assertIn("#Tags: no such heading", errors[1])
        # Written content under a heading is skipped and listed; a heading
        # the table does not list is reported.
        page = self.PAGE.replace("## Group", "Written.\n\n## Group")
        page += "\n## Extra\n"
        new, skipped, unlisted = gen.render_unit(page, heads)
        self.assertEqual((skipped, unlisted), (["unit/index.md#Tags"],
                                               ["Extra"]))
        self.assertIn("Written.\n\n## Group", new)
        self.assertEqual(gen.split_key("a/index.md#I-TLB"),
                         ("a/index.md", "I-TLB"))
        self.assertEqual(gen.split_key("system/csr.md"),
                         ("system/csr.md", None))


@unittest.skipIf(MKDOCS is None, "mkdocs is not installed")
class TestBuild(unittest.TestCase):
    MARK = "TAG_ONLY_LINE_DOC008"
    SPEC_MARK = "TAG_ONLY_LINE_DOC013"
    TAGE_DOC = "planning/arch/tage_cntrl_decisions.md"
    BPU = "frontend/bpu/index.md"
    TAGE_PAGE = os.path.join(ROOT, "docs", "frontend", "bpu", "index.md")
    # The branch prediction unit page's headings, in nav order (SR-17a).
    BPU_HEADS = ["Overview", "uBTB", "TAGE", "Statistical Corrector",
                 "Fetch Target Buffer", "Loop Predictor", "ITTage",
                 "Return Address Stack", "History Module", "Dual Prediction"]
    # The TAGE heading's nine documents, then the unit's, in display order.
    TAGE_SECTIONS = ["tage_cntrl_decisions.md", "tage_cntrl_alloc_rules.md",
                     "tage_cntrl_ctr_update_rules.md",
                     "tage_cntrl_uaon_update_rules.md",
                     "tage_cntrl_use_update_rules.md",
                     "tage_table_entry_formats.md", "tage_table_hash_rules.md",
                     "tage_interfaces.md", "tage_table_interfaces.md",
                     "bp_cluster.md", "bp_arb_spec.md",
                     "bpu_port_inventory.md"]
    # Removed from the tag's copy: a listed document missing at the tag.
    GONE_DOC = "planning/interfaces/ubtb_interfaces.md"
    # The top menu, in order (DOC-014).
    MENU = ["Home", "Overview", "IA Tasks", "Showcase", "Frontend", "Backend",
            "Memory", "Caches", "MMU", "System"]

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
        # The tag's planning documents, with one line added to one of them.
        cls.spec = os.path.join(cls.tmp, "tag")
        for sub in ("arch", "interfaces"):
            shutil.copytree(os.path.join(ROOT, "planning", sub),
                            os.path.join(cls.spec, "planning", sub))
        with open(os.path.join(cls.spec, cls.TAGE_DOC), "a") as f:
            f.write(f"\n{cls.SPEC_MARK}\n")
        os.remove(os.path.join(cls.spec, cls.GONE_DOC))
        with open(cls.TAGE_PAGE, "rb") as f:
            cls.page_md5 = hashlib.md5(f.read()).hexdigest()
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

    # The architecture pages that link scenarios, read once per build. A page
    # with a spec: list shows no placeholder, so has no such link.
    ARCH = ["system/exceptions"]

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
        # Not -q, which hides the warnings test_ci_tag looks for.
        r = subprocess.run([MKDOCS, "build", "-d", site], cwd=ROOT,
                           env=env(**kw), text=True, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.log = r.stdout

        def read(rel):
            with open(os.path.join(site, rel)) as f:
                return f.read()
        self.site_has = lambda rel: os.path.isfile(os.path.join(site, rel))
        return read

    def check_spec(self, read, name, ref, gone=()):
        """The branch prediction unit page (SR-17a): its headings, each
        document once in the Overview, the TAGE heading's Specification
        line, and the decode page's Fusion Combiner heading as one with no
        document; the source page not written."""
        page = read("frontend/bpu/index.html")
        self.assertEqual(page.count("This page shows the planning documents"
                                    f" and specifications for {name}."), 1)
        self.assertIn("<strong>Status:</strong> RTL complete, interim"
                      " documentation</p>", page)
        self.assertNotIn("This page will cover", page)
        self.assertNotIn("Not written yet", page)
        self.assertNotIn("Meanwhile", page)
        sections = re.findall(
            r'<details class="abstract">\s*<summary>([^<]*)</summary>', page)
        # Each document once, the Overview's first, then each heading's in
        # page order.
        import yaml
        with open(os.path.join(ROOT, "tools", "doc_status.yaml")) as f:
            table = yaml.safe_load(f)
        want = []
        for h in self.BPU_HEADS:
            for p in table[f"{self.BPU}#{h}"].get("spec", []):
                if os.path.basename(p) not in want and p not in gone:
                    want.append(os.path.basename(p))
        self.assertEqual(sections, want)
        for s in self.TAGE_SECTIONS:
            self.assertIn(s, sections)
        self.assertIn(f"{REPO}/blob/{ref}/{self.TAGE_DOC}", page)
        # The TAGE heading names its nine documents and the unit's, each
        # linked to its section in the Overview, which holds the target.
        tage = page[page.index('<h2 id="tage">'):
                    page.index('<h2 id="statistical-corrector">')]
        links = re.findall(r'<a href="#(spec-[^"]*)">([^<]*)</a>', tage)
        self.assertEqual([t for _, t in links], self.TAGE_SECTIONS)
        self.assertIn("<p>Specification: ", tage)
        self.assertIn(" (in the Overview above)</p>", tage)
        self.assertNotIn("<details", tage)
        for anchor, doc in links:
            self.assertRegex(page, r'<summary>' + re.escape(doc)
                             + r'</summary>\s*<p><a id="' + anchor + '">')
        # The page's table of contents lists its own headings only, each at
        # its plain id; the theme prints it twice, in the primary sidebar
        # and the secondary. A scenario page's entries show the form looked
        # for.
        entry = (r'<a href="#([^"]*)" class="md-nav__link">\s*'
                 r'<span class="md-ellipsis">\s*(.*?)\s*</span>')
        ids = [re.sub(r"[^a-z0-9]+", "-", h.lower()) for h in self.BPU_HEADS]
        self.assertEqual(re.findall(entry, page, re.S),
                         2 * list(zip(ids, self.BPU_HEADS)))
        for i in ids:
            self.assertIn(f'<h2 id="{i}">', page)
        self.assertTrue(re.findall(
            entry, read("showcase/fe_demo/fd02_steady/index.html"), re.S))
        self.assertIn('<h3 id="tage_cntrl-design-decisions">', page)
        self.assertIn("<!-- SPDX-FileCopyrightText: 2026 Jeff Nye "
                      "<jeff@uarchlabs.com> -->", page)
        # An indented run keeps its line breaks and indentation.
        self.assertIn("Captures into meta:\n"
                      "  tage_prm_idx       -- already-hashed", page)
        decode = read("frontend/decode/index.html")
        fusion = decode[decode.index('<h2 id="fusion-combiner">'):
                        decode.index('<h2 id="integer-decode">')]
        self.assertIn("<strong>Status:</strong> RTL planned. Documentation"
                      " planned.</p>", fusion)
        self.assertNotIn("Specification:", fusion)
        self.assertNotIn("Not written yet", decode)
        with open(self.TAGE_PAGE, "rb") as f:
            self.assertEqual(hashlib.md5(f.read()).hexdigest(), self.page_md5)
        return page

    def check_menu(self, read):
        """The top menu's entries, in order, and its dimming style."""
        page = read("overview/index.html")
        self.assertEqual(re.findall(
            r'<a href="[^"]*" class="md-tabs__link[^"]*">\s*(.*?)\s*</a>',
            page, re.S), self.MENU)
        self.assertIn(".md-tabs__item:nth-child(n+6) .md-tabs__link", page)

    def test_local(self):
        read = self.build("local")
        self.check_shown(read, self.site_has)
        self.check_menu(read)
        page = self.check_spec(read, "the working tree", "main")
        self.assertNotIn(self.SPEC_MARK, page)
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
                          SHOWCASE_DEMO_DIR=self.demo,
                          SHOWCASE_SPEC_DIR=self.spec)
        spec = self.check_spec(read, "RTL tag fe-9.9.9", "fe-9.9.9",
                               gone=(self.GONE_DOC,))
        self.assertIn(self.SPEC_MARK, spec)
        # The document removed from the tag's copy: a note and a warning, in
        # the Overview of the one page listing it, and the build went on.
        ubtb = spec[:spec.index('<h2 id="ubtb">')]
        self.assertIn(f"<code>{self.GONE_DOC}</code> is not in RTL tag"
                      " fe-9.9.9.", ubtb)
        self.assertNotIn('<summary>ubtb_interfaces.md', spec)
        self.assertIn("frontend/bpu/index.md", self.log)
        self.assertIn(self.GONE_DOC, self.log)
        self.assertEqual(self.log.count(f"{self.GONE_DOC} is not in"), 1)
        with open(os.path.join(ROOT, self.TAGE_DOC)) as f:
            self.assertNotIn(self.SPEC_MARK, f.read())
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
