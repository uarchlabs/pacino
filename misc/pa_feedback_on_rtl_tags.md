# IA notes on the PA brief: frontend tags and the scenario regression

Review of `pa_brief_fe_tags_and_scenario_regression.md`, for the PA
session that plans the task file. Written by the IA at Jeff's request,
2026-10-28. Figures below were measured in this session; nothing was
changed.

---

## 1. Summary

The core of the brief is worth doing: the demo pages do drift from the
RTL (DOC-007 checked about 1570 line citations and found 188 wrong), and
putting the scenarios in the regression is cheap. Two parts cost more
than they return as written: the separate JSON expectations file (Level
1 as specified) and the warn-only fingerprint in the regression (Level
2). The brief also reverses a recorded decision without naming it, and
the tags, not the RTL, create a two-views risk.

## 2. Cost of each part

| Part | Cost | Notes |
|------|------|-------|
| Scenarios in regress.sh (decision 3) | Low | See 2.1. |
| Tags and the publish gate (decision 1) | Low | publish_waves.py already writes the pacino commit to manifest.json; it adds the tag and the gate. |
| Level 1 as JSON + FST checker + page cross-check | High | A third description of each scenario beside the page and the testbench proof: a format, a checker and a sync check. The cross-check exists only because the JSON duplicates the page. |
| Level 2 as a regression warning | Medium | regress.sh has PASS and FAIL only, and the pre-push hook reads only that. A warn level is new behavior that nothing acts on. |

### 2.1 The scenarios in the regression

- fe_demo builds from rtl/ (no copy of the RTL). Its outputs,
  examples/fe_demo/out/ and obj_fe_demo*/, are in .gitignore, so a
  regression run leaves the tree clean and the pass record
  (new_user_decisions.md NU-19) still works.
- The 24 scenarios share obj_fe_demo/ and obj_fe_demo_2slot/.
  regress.sh runs the targets of one Makefile in one job (NU-22), so
  they never run against each other. Scanning examples/ must keep that
  rule.
- Measured run time under regress.sh's `make -B` (32 threads, ccache
  warm, 2026-10-28): one scenario target 7 to 15 s, because -B
  recompiles its model (fd02_steady 7.4 s, fd22_sc_slot1 13.6 s,
  fd09_tage 15.2 s). The 24 runs alone, with both models built, take
  7.4 s.
  - 24 targets: about 4 to 5 minutes in one job, inside the 561 s that
    fe_top's job takes at the default jobs, so the regression is not
    longer; at -j 1 it is 4 to 5 minutes longer.
  - One target, `scenarios`: under a minute (two model builds, then
    the runs), at the cost of one summary line for all 24.
- The demo Makefile must define regress_list and classify every
  target: help, build, clean and view in REGRESS_EXCLUDE with reasons;
  scenarios, or the 24 scenario targets, in REGRESS_TARGETS.
- The brief's 33 s for `make -k scenarios` (section 1) includes the
  model builds once; it is not the cost under regress.sh, which section
  4 asks for. Use the figures above.

## 3. Value of each part

- **Level 1: high value.** DOC-007's 188 wrong citations show the cost
  of drift. A simpler form than the brief's: write the documented events
  as cycle checks in the testbench, in each programs/fdNN_<name>.svh
  beside the existing end-of-run proof (tb/fe_demo_proofs.svh).
  - A broken event fails the scenario's own FDT-10 result line, so
    regress.sh needs no new mechanism.
  - A renamed signal fails the compile instead of a lookup.
  - No FST reader and no JSON format to maintain.
  - The page cross-check, if kept, reads the cycles from the .svh
    files. mk_sucl.py already parses each page's event table into
    cycles (FDT-12c), so reading the page side is solved.
- **Level 2: low value in the regression.** A stale waveform matters
  only at publish time. publish_waves.py can compute the digest and
  compare it with the published manifest.json: "the published copy is
  stale" when it matters, with no change to regress.sh.
- **Tags: moderate value, low cost.** They name the state the showcase
  documents. The manifest's commit already identifies it; the tag adds
  a readable name and the publish gate.
- **Exact cycles against windows (open question 2) decides the noise.**
  With exact cycles, every harmless timing change in the frontend fails
  the regression and forces a page edit and a new tag; with MMU and PTW
  still active, that will happen. Exact cycles only where the page's
  point is the cycle; ordering and windows elsewhere.

## 4. Two views of the RTL

- **Not of the RTL itself.** fe_demo compiles the same rtl/ sources as
  fe_top. Two weak points remain:
  - Its source list is kept in step with
    rtl/core/frontend/fe_top/Makefile by hand (its Makefile says so). A
    missing file fails loudly; a differing flag or define would not.
    The regression helps: a broken list then fails before a push.
  - Two testbenches for one DUT: tb_fe_top (84 programs, properties
    bound) and tb_fe_demo (24 scenarios, no properties). Acceptable if
    the task states the demo checks documented behavior and is not a
    second verification suite.
- **The tags create the two-views risk.** The docs site builds the
  Showcase pages from examples/fe_demo/docs on the branch (the
  docs/showcase symlink); the waveforms in pacino-waves come from the
  tagged commit. Between a page change and the next tag and publish,
  the site describes one state and its "Open waveform" links show
  another. The task should require one of:
  - the Showcase pages built from the same tag as the waveforms, or
  - a publish whenever a scenario page changes.
  With either, Level 1 keeps the branch's RTL matching its pages.

## 5. Gaps in the brief

1. **It reverses FDT-2 without naming it.** fe_demo_tb_decisions.md
   FDT-2: "examples/ is not scanned by tools/regress.sh and has no
   regression target"; the demo Makefile's header repeats it ("NOT A
   REGRESSION (FDT-2)"). FDT-2 needs amending, and
   planning/testbenches/fe_demo_tb_decisions.md belongs in section 6.
2. **It does not mention NU-22.** The scenarios are safe in the
   regression only because targets of one Makefile run in one job; the
   scan of examples/ must keep that (section 2.1).
3. **Run-time cost.** Section 1's 33 s is not the cost under
   regress.sh; section 2.1 gives the measured figures.
4. **Open question 1, the FST reader.** tools/bin/fst2vcd is now built
   per clone (NU-16) and is already the demo's FST reader
   (fe_demo_sigs.py); it is the reference option if an FST checker is
   kept. pylibfst would be a new dependency.
5. **Open question 5, the publish gate.** A tag gate alone does not
   keep the site and the waveforms on one state; pair it with the rule
   of section 4.

## 6. Suggested split

- **Task 1, small.** Tags `fe-<major>.<minor>`; publish_waves.py
  publishes only from a tag (or with an override), records the tag in
  manifest.json, and computes the Level 2 digest, comparing it with the
  published one as a publish-time staleness check. The rule of section
  4 for keeping the site and the waveforms on one state.
- **Task 2.** The scenarios in the regression (regress.sh scans
  examples/*/Makefile, one job per Makefile; the demo Makefile's
  regress_list) and Level 1 as testbench checks, ordering and windows by
  default, exact cycles where the page needs them. FDT-2 amended. Start
  with one `scenarios` regression target, or the 24 targets if a summary
  line per scenario is wanted.
- **Drop** the JSON expectations file and the page cross-check it
  requires.

## 7. Evidence

- Measured 2026-10-28 in a scratch copy of examples/fe_demo with
  RVA_ROOT at the working tree: `make -B fd09_tage` 15.22 s,
  `make -B fd02_steady` 7.40 s, `make -B fd22_sc_slot1` 13.63 s, then
  `make -k scenarios` with both models built 7.42 s; every scenario
  PASS.
- regress.sh timing at the default 15 jobs: 274 targets PASS in 569 s;
  fe_top's job 561 s (new_user_decisions.md NU-22).
- `git check-ignore`: examples/fe_demo/out/ and
  examples/fe_demo/obj_fe_demo/ are ignored (.gitignore lines 229 and
  230).
- FDT-2: planning/testbenches/fe_demo_tb_decisions.md line 50.
- DOC-007's citation figures: planning/PROJECT_STATUS.md, the
  session-081 entry after DOC-007.
