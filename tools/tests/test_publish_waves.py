#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# test_publish_waves.py -- tools/publish_waves.py: the tag gate, the dry
# run, the manifest record, the digest and the staleness report (DOC-008,
# SR-9 to SR-12), and a publish's tag check and dirty-tree refusal
# (DOC-010, SR-9a, SR-10).
#
# Every run of the script has tools/tests/git_standin first on PATH: a
# git that records each call and exits 1, or prints a test's answers.
# Nothing here runs git, pushes or reaches the network. A publish (no
# --dry-run) is run with RVA_ROOT set to another directory, so one that
# passes the gate stops at the RVA_ROOT check, before anything is built.
#
# The dry runs here pass --no-build and read the FSTs already in
# examples/fe_demo/out/: run make -C examples/fe_demo scenarios first
# (TestDryRun fails, naming the missing FST, otherwise). TestTwoRuns runs
# one scenario twice itself.
#
#   python3 -m unittest discover -s tools/tests -v

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

TESTS = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(TESTS)
ROOT = os.path.dirname(TOOLS)
DEMO = os.path.join(ROOT, "examples", "fe_demo")
SCRIPT = os.path.join(TOOLS, "publish_waves.py")
STANDIN = os.path.join(TESTS, "git_standin")
sys.path.insert(0, TOOLS)
import publish_waves as pw  # noqa: E402

SHA = "0123456789abcdef0123456789abcdef01234567"
SHA2 = "89abcdef0123456789abcdef0123456789abcdef"
SCEN = pw.scenarios(dict(os.environ, RVA_ROOT=ROOT))
OLD_KEYS = ["scenarios", "files", "pacino_commit", "build_date"]


def background_manifest():
    """A published manifest.json in the format the DOC-008 Background
    gives: scenarios, files (one .fst and one .sucl per scenario, to its
    size), pacino_commit and build_date; no tag and no digest."""
    files = {}
    for i, s in enumerate(SCEN):
        files[f"{s}.fst"] = 100000 + i
        files[f"{s}.sucl"] = 2000 + i
    return {"scenarios": list(SCEN), "files": files,
            "pacino_commit": SHA2, "build_date": "2026-10-20T12:00:00Z"}


class Run:
    """One run of publish_waves.py under the stand-in git."""
    def __init__(self, tmp, args, answers=None, extra=None):
        log = os.path.join(tmp, "git.log")
        if os.path.exists(log):
            os.remove(log)
        env = dict(os.environ, PATH=STANDIN + os.pathsep + os.environ["PATH"],
                   GIT_STANDIN_LOG=log)
        env.pop("GIT_STANDIN_ANSWERS", None)
        env.pop("RVA_ROOT", None)
        env.update(extra or {})
        if answers is not None:
            path = os.path.join(tmp, "answers.json")
            with open(path, "w") as f:
                json.dump(answers, f)
            env["GIT_STANDIN_ANSWERS"] = path
        r = subprocess.run([sys.executable, SCRIPT] + args, env=env,
                           text=True, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE)
        self.rc, self.out, self.err = r.returncode, r.stdout, r.stderr
        self.git = []
        if os.path.exists(log):
            with open(log) as f:
                self.git = [json.loads(l) for l in f]

    def pushed(self):
        return any("push" in c for c in self.git)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="test_publish_waves.")
        self.out = os.path.join(self.tmp, "stage")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_pw(self, args, answers=None):
        return Run(self.tmp, args, answers)

    def manifest(self):
        with open(os.path.join(self.out, "manifest.json")) as f:
            return json.load(f)

    def refused(self, r, text):
        """Refused before building or pushing, saying why."""
        self.assertNotEqual(r.rc, 0, r.out + r.err)
        self.assertIn(text, r.err)
        self.assertNotIn("[building]", r.out)
        self.assertNotIn("[not built]", r.out)
        self.assertFalse(r.pushed())
        self.assertFalse(os.path.exists(self.out))


# ---------------------------------------------------------------------
# The tag gate (SR-1, SR-9, SR-10)
# ---------------------------------------------------------------------
class TestGate(Base):
    def test_bad_tag_refused(self):
        for tag in ["fe-1.0", "fe-01.0.0", "fe-1.00.0", "fe-1.0.01",
                    "fe-1.0.0-rc1", "v1.0.0", "FE-1.0.0", "fe-\u0661.0.0",
                    "fe-1.0.0.0"]:
            r = self.run_pw(["--tag", tag, "--commit", SHA, "--dry-run",
                             "--no-build", "--out", self.out])
            self.refused(r, "is not a release tag")
            self.assertEqual(r.git, [], tag)

    def test_bad_commit_refused(self):
        r = self.run_pw(["--tag", "fe-1.0.0", "--commit", SHA[:12],
                         "--dry-run", "--out", self.out])
        self.refused(r, "not a full 40-character sha")
        self.assertEqual(r.git, [])

    def test_no_tag_refused(self):
        # A commit and no tag, no override: no git call is made at all.
        r = self.run_pw(["--commit", SHA, "--dry-run", "--out", self.out])
        self.refused(r, "without --tag")
        self.assertEqual(r.git, [])

    def test_no_args_git_fails_refused(self):
        # The default lookup, with a git that fails every call.
        r = self.run_pw(["--dry-run", "--out", self.out])
        self.refused(r, "failed")
        self.assertEqual(r.git[0][-2:], ["--verify", "HEAD^{commit}"])

    def test_no_args_head_untagged_refused(self):
        r = self.run_pw(["--dry-run", "--out", self.out],
                        {"rev-parse": SHA + "\n", "for-each-ref": ""})
        self.refused(r, "at no annotated fe-<major>.<minor>.<patch> tag")
        self.assertIn("for-each-ref", r.git[1])
        self.assertIn("refs/tags/fe-*", r.git[1])

    def test_no_args_lightweight_refused(self):
        r = self.run_pw(["--dry-run", "--out", self.out],
                        {"rev-parse": SHA + "\n",
                         "for-each-ref": "commit fe-1.0.0\ntag fe-1.0\n"})
        self.refused(r, "at no annotated")
        self.assertIn("fe-1.0.0 at HEAD is not an annotated", r.out)

    def test_untagged_with_tag_refused(self):
        r = self.run_pw(["--untagged", "--tag", "fe-1.0.0", "--commit", SHA,
                         "--dry-run", "--out", self.out])
        self.refused(r, "--untagged and --tag together")

    def test_no_build_needs_dry_run(self):
        r = self.run_pw(["--tag", "fe-1.0.0", "--commit", SHA, "--no-build"])
        self.refused(r, "--no-build is for a dry run only")
        self.assertEqual(r.git, [])

    def test_unreadable_published_refused(self):
        r = self.run_pw(["--tag", "fe-1.0.0", "--commit", SHA, "--dry-run",
                         "--no-build", "--out", self.out, "--published",
                         os.path.join(self.tmp, "absent.json")])
        self.refused(r, "--published")
        self.assertEqual(r.git, [])


# ---------------------------------------------------------------------
# The dry run and the manifest record (SR-9, SR-10, SR-12)
# ---------------------------------------------------------------------
class TestDryRun(Base):
    @classmethod
    def setUpClass(cls):
        for s in SCEN:
            fst = os.path.join(DEMO, "out", s, f"{s}.fst")
            if not os.path.isfile(fst):
                raise AssertionError(f"missing {fst}: run make -C"
                                     f" examples/fe_demo scenarios first")

    def check_stage(self, m, tag, commit):
        self.assertEqual(list(m)[:4], OLD_KEYS)
        self.assertEqual(m["scenarios"], SCEN)
        self.assertEqual(m["pacino_commit"], commit)
        self.assertRegex(m["build_date"],
                         r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
        self.assertEqual(m["tag"], tag)
        self.assertEqual(m["tag_commit"], commit)
        self.assertEqual(m["digest_version"], pw.DIGEST_VERSION)
        self.assertEqual(sorted(m["digests"]), sorted(SCEN))
        for d in m["digests"].values():
            self.assertRegex(d, r"^[0-9a-f]{64}$")
        want = sorted([f"{s}.fst" for s in SCEN] + [f"{s}.sucl" for s in SCEN])
        self.assertEqual(sorted(m["files"]), want)
        for name, size in m["files"].items():
            self.assertEqual(os.path.getsize(os.path.join(self.out, name)),
                             size, name)
        staged = sorted(os.listdir(self.out))
        self.assertEqual(staged, sorted(want + [".nojekyll", "README.md",
                                                "manifest.json"]))
        with open(os.path.join(self.out, "README.md")) as f:
            self.assertIn(f"Release `{tag}`, built from pacino commit"
                          f" `{commit}`", f.read())

    def test_args_no_git_and_background_fixture(self):
        # Tag and commit as arguments: no git call. Against a published
        # manifest in the Background's format every scenario is without a
        # published digest.
        pub = os.path.join(self.tmp, "published.json")
        with open(pub, "w") as f:
            json.dump(background_manifest(), f)
        r = self.run_pw(["--tag", "fe-1.0.0", "--commit", SHA, "--dry-run",
                         "--no-build", "--out", self.out, "--published", pub])
        self.assertEqual(r.rc, 0, r.out + r.err)
        self.assertEqual(r.git, [])
        self.check_stage(self.manifest(), "fe-1.0.0", SHA)
        for s in SCEN:
            self.assertRegex(r.out, rf"\n  no published digest +{s}\n")
        self.assertIn(f"[staleness]  {len(SCEN)} no published digest", r.out)
        self.assertIn("[dry run]", r.out)

        # The manifest just staged, with one digest changed, one scenario
        # dropped, and one listed without its digest: changed warns and
        # does not stop the run.
        m = self.manifest()
        m["digests"][SCEN[0]] = "0" * 64
        m["scenarios"].remove(SCEN[1])
        del m["digests"][SCEN[1]]
        del m["digests"][SCEN[2]]
        m["scenarios"].append("fd99_gone")
        with open(pub, "w") as f:
            json.dump(m, f)
        r = self.run_pw(["--tag", "fe-1.0.1", "--commit", SHA, "--dry-run",
                         "--no-build", "--out", self.out, "--published", pub])
        self.assertEqual(r.rc, 0, r.out + r.err)
        self.assertEqual(r.git, [])
        self.assertRegex(r.out, rf"\n  changed +{SCEN[0]}\n")
        self.assertIn(f"[warning]    {SCEN[0]}: its waveform differs", r.out)
        self.assertRegex(r.out, rf"\n  new +{SCEN[1]}\n")
        self.assertRegex(r.out, rf"\n  no published digest +{SCEN[2]}\n")
        self.assertRegex(r.out, r"\n  removed +fd99_gone\n")
        for s in SCEN[3:]:
            self.assertRegex(r.out, rf"\n  unchanged +{s}\n")
        self.assertIn("[dry run]", r.out)
        self.check_stage(self.manifest(), "fe-1.0.1", SHA)

    def test_override_untagged(self):
        r = self.run_pw(["--untagged", "--commit", SHA, "--dry-run",
                         "--no-build", "--out", self.out])
        self.assertEqual(r.rc, 0, r.out + r.err)
        self.assertEqual(r.git, [])
        self.check_stage(self.manifest(), "untagged", SHA)

    def test_lookup_takes_latest_annotated(self):
        # The default lookup, answered by the stand-in: two annotated
        # release tags and a lightweight one at HEAD.
        r = self.run_pw(["--dry-run", "--no-build", "--out", self.out],
                        {"rev-parse": SHA + "\n", "status": "",
                         "for-each-ref": "tag fe-1.9.3\ntag fe-1.10.0\n"
                                         "commit fe-2.0.0\n"})
        self.assertEqual(r.rc, 0, r.out + r.err)
        self.assertFalse(r.pushed())
        self.assertEqual([c[2] for c in r.git],
                         ["rev-parse", "for-each-ref", "status"])
        self.check_stage(self.manifest(), "fe-1.10.0", SHA)

    def test_dirty_tree_warns(self):
        # SR-9a: a dry run with rtl/ and examples/fe_demo/ dirty warns,
        # reading git status --porcelain as before DOC-010, and completes.
        r = self.run_pw(["--tag", "fe-1.0.0", "--dry-run", "--no-build",
                         "--out", self.out],
                        {"cat-file": "tag\n", "rev-parse": SHA + "\n",
                         "status": " M rtl/x.sv\n?? examples/fe_demo/y\n"})
        self.assertEqual(r.rc, 0, r.out + r.err)
        self.assertIn("[warning]    the pacino tree has uncommitted changes",
                      r.out)
        self.assertEqual(r.git[-1], ["-C", ROOT, "status", "--porcelain"])
        self.assertFalse(r.pushed())
        self.check_stage(self.manifest(), "fe-1.0.0", SHA)


# ---------------------------------------------------------------------
# A publish: the tag check (SR-10) and the dirty-tree refusal (SR-9a)
# ---------------------------------------------------------------------
HEAD_CALL = "rev-parse --verify HEAD^{commit}"
STATUS_CALL = ["-C", ROOT, *pw.STATUS]


def tag_call(tag):
    return f"rev-parse --verify refs/tags/{tag}^{{commit}}"


def porcelain(*entries):
    """git status --porcelain=v1 -z output of entries ("XY path")."""
    return "".join(e + "\0" for e in entries)


class TestPublishGate(Base):
    def answers(self, head=SHA, tag_commit=SHA, typ="tag", status=""):
        """HEAD at head, fe-1.0.0 a tag of type typ naming tag_commit,
        status the status output."""
        return {HEAD_CALL: head + "\n", tag_call("fe-1.0.0"): tag_commit + "\n",
                "cat-file": typ + "\n", "status": status}

    def publish(self, args, answers=None):
        return Run(self.tmp, args, answers, {"RVA_ROOT": self.tmp})

    def passed(self, r, tag, commit):
        """Past the gate, with the clean-tree check made; stopped at the
        RVA_ROOT check before anything is built or pushed."""
        self.assertIn(f"[release]    {tag} at {commit}\n", r.out, r.err)
        self.assertIn("RVA_ROOT is", r.err)
        self.assertNotEqual(r.rc, 0)
        self.assertNotIn("[building]", r.out)
        self.assertFalse(r.pushed())
        self.assertIn(STATUS_CALL, r.git)

    def refused_publish(self, r, text):
        self.refused(r, text)
        self.assertNotIn("[release]", r.out)

    # The tag check (SR-10)
    def test_tag_and_commit_checked(self):
        r = self.publish(["--tag", "fe-1.0.0", "--commit", SHA],
                         self.answers())
        self.passed(r, "fe-1.0.0", SHA)
        self.assertEqual(r.git, [["-C", ROOT, "cat-file", "-t",
                                  "refs/tags/fe-1.0.0"],
                                 ["-C", ROOT] + tag_call("fe-1.0.0").split(),
                                 ["-C", ROOT] + HEAD_CALL.split(),
                                 STATUS_CALL])

    def test_given_commit_not_head_refused(self):
        r = self.publish(["--tag", "fe-1.0.0", "--commit", SHA2],
                         self.answers(tag_commit=SHA2))
        self.refused_publish(r, f"--commit {SHA2} is not HEAD {SHA}")

    def test_lightweight_tag_with_commit_refused(self):
        r = self.publish(["--tag", "fe-1.0.0", "--commit", SHA],
                         self.answers(typ="commit"))
        self.refused_publish(r, "fe-1.0.0 is a lightweight tag")

    def test_tag_not_at_head_with_commit_refused(self):
        r = self.publish(["--tag", "fe-1.0.0", "--commit", SHA],
                         self.answers(tag_commit=SHA2))
        self.refused_publish(r, f"fe-1.0.0 names {SHA2[:12]}, but HEAD is"
                                f" {SHA[:12]}")

    def test_tag_alone_checked(self):
        self.passed(self.publish(["--tag", "fe-1.0.0"], self.answers()),
                    "fe-1.0.0", SHA)

    def test_no_args_checked(self):
        r = self.publish([], {"rev-parse": SHA + "\n", "status": "",
                              "for-each-ref": "tag fe-1.0.0\n"})
        self.passed(r, "fe-1.0.0", SHA)

    def test_git_failing_refused(self):
        # Tag and commit given, git failing every call: refused.
        r = self.publish(["--tag", "fe-1.0.0", "--commit", SHA])
        self.refused_publish(r, "failed")
        self.assertEqual(r.git[0][2:4], ["cat-file", "-t"])

    def test_commit_without_tag_refused(self):
        r = self.publish(["--commit", SHA], self.answers())
        self.refused_publish(r, "without --tag")
        self.assertEqual(r.git, [])

    def test_untagged_records_head(self):
        r = self.publish(["--untagged"], self.answers())
        self.passed(r, "untagged", SHA)
        self.assertEqual(r.git, [["-C", ROOT] + HEAD_CALL.split(),
                                 STATUS_CALL])

    def test_untagged_commit_at_head(self):
        self.passed(self.publish(["--untagged", "--commit", SHA],
                                 self.answers()), "untagged", SHA)

    def test_untagged_commit_not_head_refused(self):
        r = self.publish(["--untagged", "--commit", SHA2], self.answers())
        self.refused_publish(r, f"--commit {SHA2} is not HEAD {SHA}")

    # The dirty-tree refusal (SR-9a)
    def test_tracked_change_refused(self):
        st = porcelain(" M rtl/frontend/a.sv", "M  rtl/b.sv",
                       "D  examples/fe_demo/waves/fd01_x.sucl",
                       "MM examples/fe_demo/Makefile")
        for args in (["--tag", "fe-1.0.0", "--commit", SHA],
                     ["--tag", "fe-1.0.0"], ["--untagged"]):
            r = self.publish(args, self.answers(status=st))
            self.refused_publish(r, "4 file(s) under rtl/ or examples/fe_demo/")
            for line in (" M rtl/frontend/a.sv", "M  rtl/b.sv",
                         "D  examples/fe_demo/waves/fd01_x.sucl",
                         "MM examples/fe_demo/Makefile"):
                self.assertIn(f"\n    {line}", r.err, args)
            self.assertEqual(r.git[-1], STATUS_CALL)

    def test_untracked_file_refused(self):
        st = porcelain("?? examples/fe_demo/programs/new prog.S",
                       "?? rtl/frontend/tmp.sv")
        r = self.publish(["--tag", "fe-1.0.0"], self.answers(status=st))
        self.refused_publish(r, "2 file(s) under rtl/ or examples/fe_demo/")
        self.assertIn("\n    ?? examples/fe_demo/programs/new prog.S", r.err)
        self.assertIn("\n    ?? rtl/frontend/tmp.sv", r.err)

    def test_outside_changes_warn(self):
        st = porcelain(" M tools/x.py", "?? notes/a.md", "?? rtl_old/b.sv",
                       "?? examples/fe_demo_old/c", " M examples/README.md")
        r = self.publish(["--tag", "fe-1.0.0"], self.answers(status=st))
        self.passed(r, "fe-1.0.0", SHA)
        self.assertIn("[warning]    5 uncommitted change(s) outside rtl/ and"
                      " examples/fe_demo/", r.out)
        for line in (" M tools/x.py", "?? notes/a.md", "?? rtl_old/b.sv",
                     "?? examples/fe_demo_old/c", " M examples/README.md"):
            self.assertIn(f"\n    {line}\n", r.out)

    def test_outside_warning_capped(self):
        st = porcelain(*[f"?? notes/n{i:02}.md" for i in range(12)])
        r = self.publish(["--untagged"], self.answers(status=st))
        self.passed(r, "untagged", SHA)
        self.assertIn("    ?? notes/n09.md\n    ... and 2 more\n", r.out)
        self.assertNotIn("n10.md", r.out)

    def test_mixed_refused_names_inside(self):
        st = porcelain(" M tools/x.py", "?? rtl/c.sv")
        r = self.publish(["--untagged"], self.answers(status=st))
        self.refused_publish(r, "1 file(s) under rtl/ or examples/fe_demo/")
        self.assertIn("\n    ?? rtl/c.sv", r.err)
        self.assertNotIn("tools/x.py", r.err)

    def test_dry_run_unchanged(self):
        # The same dirty tree and a given commit that is not HEAD: a dry
        # run with --tag and --commit makes no git call and completes the
        # gate; with --tag alone it warns and does not refuse.
        st = porcelain(" M rtl/frontend/a.sv")
        r = Run(self.tmp, ["--tag", "fe-1.0.0", "--commit", SHA2, "--dry-run",
                           "--out", self.out], self.answers(status=st),
                {"RVA_ROOT": self.tmp})
        self.assertIn(f"[release]    fe-1.0.0 at {SHA2}\n", r.out)
        self.assertEqual(r.git, [])
        r = Run(self.tmp, ["--tag", "fe-1.0.0", "--dry-run", "--out",
                           self.out], self.answers(status=st),
                {"RVA_ROOT": self.tmp})
        self.assertIn(f"[release]    fe-1.0.0 at {SHA}\n", r.out)
        self.assertIn("[warning]    the pacino tree has uncommitted changes",
                      r.out)
        self.assertNotIn(STATUS_CALL, r.git)

    def test_status_entries(self):
        out = porcelain(" M rtl/a b.sv", "?? x", "R  rtl/new.sv") \
            + "examples/fe_demo/old.sv\0"
        self.assertEqual(pw.status_entries(out),
                         [(" M", "rtl/a b.sv"), ("??", "x"),
                          ("R ", "rtl/new.sv"),
                          ("R ", "examples/fe_demo/old.sv")])
        self.assertEqual(pw.status_entries(""), [])


# ---------------------------------------------------------------------
# The digest (SR-11), on decoded data
# ---------------------------------------------------------------------
class TestDigest(unittest.TestCase):
    def data(self):
        return {"tb.clk": [(0, 0), (5, 1), (10, 0), (15, 1)],
                "tb.dut.a": [(0, None), (5, 3), (15, 7)],
                "tb.dut.b": [(0, 0), (10, 1)],
                "tb.dut.unlisted": [(0, 0), (5, 9)]}

    LISTED = ["tb.clk", "tb.dut.a", "tb.dut.b"]

    def test_listed_value_changes_digest(self):
        base = pw.digest(self.data(), self.LISTED)
        d = self.data()
        d["tb.dut.a"][2] = (15, 6)
        self.assertNotEqual(pw.digest(d, self.LISTED), base)
        d = self.data()
        d["tb.dut.b"][1] = (11, 1)
        self.assertNotEqual(pw.digest(d, self.LISTED), base)
        d = self.data()
        d["tb.dut.a"][0] = (0, 0)
        self.assertNotEqual(pw.digest(d, self.LISTED), base)

    def test_unlisted_signal_does_not(self):
        base = pw.digest(self.data(), self.LISTED)
        d = self.data()
        d["tb.dut.unlisted"][1] = (5, 8)
        d["tb.dut.other"] = [(0, 1)]
        self.assertEqual(pw.digest(d, self.LISTED), base)

    def test_canonical_form(self):
        base = pw.digest(self.data(), self.LISTED)
        d = self.data()
        d["tb.dut.b"] = [(0, 0), (5, 0), (10, 1), (10, 1)]
        self.assertEqual(pw.digest(d, self.LISTED), base)
        d = self.data()
        d["tb.dut.a"] = [(0, None), (5, 1), (5, 3), (15, 7)]
        self.assertEqual(pw.digest(d, self.LISTED), base)
        self.assertEqual(pw.digest(self.data(), list(reversed(self.LISTED))),
                         base)

    def test_sucl_signals(self):
        with tempfile.NamedTemporaryFile("w", suffix=".sucl",
                                         delete=False) as f:
            f.write("# variable_add tb.no\nvariable_add tb.clk\nitem_focus a\n"
                    "variable_add tb.dut.x.[0].y\nitem_set_format Bit\n")
        try:
            self.assertEqual(pw.sucl_signals(f.name),
                             ["tb.clk", "tb.dut.x.[0].y"])
        finally:
            os.remove(f.name)


# ---------------------------------------------------------------------
# The staleness report (SR-12), on manifests
# ---------------------------------------------------------------------
class TestStaleness(unittest.TestCase):
    def test_statuses(self):
        pub = {"scenarios": ["s1", "s2", "s3"], "digest_version": 1,
               "digests": {"s1": "a", "s2": "b"}}
        got = pw.staleness({"s1": "a", "s2": "x", "s3": "c", "s4": "d"}, pub)
        self.assertEqual(got, {"s1": "unchanged", "s2": "changed",
                               "s3": "no published digest", "s4": "new"})

    def test_background_format(self):
        digests = {s: "0" * 64 for s in SCEN}
        got = pw.staleness(digests, background_manifest())
        self.assertEqual(set(got.values()), {"no published digest"})
        self.assertEqual(len(got), 24)

    def test_other_digest_version_not_compared(self):
        pub = {"scenarios": ["s1"], "digest_version": 2,
               "digests": {"s1": "a"}}
        self.assertEqual(pw.staleness({"s1": "a"}, pub),
                         {"s1": "no published digest"})


# ---------------------------------------------------------------------
# Two runs of one scenario on one build give one digest (SR-11)
# ---------------------------------------------------------------------
class TestTwoRuns(unittest.TestCase):
    SCEN = "fd02_steady"

    def test_two_runs(self):
        fst = os.path.join(DEMO, "out", self.SCEN, f"{self.SCEN}.fst")
        sucl = os.path.join(DEMO, "waves", f"{self.SCEN}.sucl")
        env = dict(os.environ, RVA_ROOT=ROOT)
        tmp = tempfile.mkdtemp(prefix="test_two_runs.")
        try:
            subprocess.run(["make", "-C", DEMO, self.SCEN], env=env,
                           check=True, stdout=subprocess.DEVNULL)
            first = os.path.join(tmp, "first.fst")
            shutil.copyfile(fst, first)
            subprocess.run(["make", "-C", DEMO, self.SCEN], env=env,
                           check=True, stdout=subprocess.DEVNULL)
            d1 = pw.scenario_digest(first, sucl)
            d2 = pw.scenario_digest(fst, sucl)
            self.assertEqual(d1, d2)
            with open(first, "rb") as a, open(fst, "rb") as b:
                same = a.read() == b.read()
            print(f"\n  {self.SCEN}: digest {d1[:16]}, FST bytes of the two"
                  f" runs {'identical' if same else 'differ'}")
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main()
