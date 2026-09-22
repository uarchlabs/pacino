<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header 
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | TOOLS-006               |                          |
| Date         | YYYY.MM.DD              |                          |
| Module       | tools/regress.sh, all rtl/ Makefiles |             |
| Run time     | 33m.22s + interactive   |                          |
| Ctx %        | 23%                     |                          |
| Model        | claude-opus-5[1m] normal |                         |
| Resume sha   | 6a0790aa-a3fd-4991-b57c-e19cac45361b |             |
| PA session   | 073                     |                          |

Task:   [ ] experiment  [x] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Mode:   [ ] automated   [ ] manual          [ ] interactive
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview

Build a single repo-level regression command that finds every Makefile
under rtl/, runs every test target in each, and reports per target. A
checked-in known-failures file separates open, TD-tracked failures from
new ones. A pre-push hook runs the command and refuses a red push.

This replaces rule-based checking (the "both units" package rule,
per-task waiver lists, the hand-kept make-target gap list) with a check
that runs the same way every time. The goal is that nothing checked in
is broken, and that a package change which breaks another unit is
caught at push time. This task builds the tool and records the
baseline. It does not fix pre-existing failures.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion 

## Claude.code Console Output
TOOLS-006 is complete. ./tools/regress.sh, run from the repo root with no
  arguments, ran all 78 test targets in the 5 rtl/ Makefiles: 78 passed, 0
  warnings, exit 0, 223 s. Each result matches the baseline I took before any
  edit. I filled in Results Capture and the Model field, and left the header
  Status box for you, since it sits outside the results markers.

  What I found
  - all gap (TD#99): confirmed in bpu. Its all leaves out sim_ittage,
    sim_tage_manual and all seven cov_* targets. The decode, ftq and lib all
    targets are complete.
  - Top-level Makefile: rtl/Makefile only hands off to the unit Makefiles and
    has no test targets of its own. Its all and clean skip the ftq unit
    entirely, and its cov only reaches bpu cov_bpu. regress.sh doesn't use these
    targets, so nothing runs twice.
  - Testbenches that exited 0 on failure: the lib testbench (tb_components) and
    all three decode testbenches printed a failed check but still exited 0, so a
    regression reading exit status reported them as passing. I proved this by
    breaking one check in each on a scratch copy. I changed only their
    end-of-run code, so a failed check now exits through $fatal(1), as the bpu
    and ftq testbenches already do. After the change, all four injected faults
    are reported as failures.
  - No existing failures: the baseline found no failing target, so
    tools/known_failures.proposed.txt contains only comments.

  What was delivered
  - tools/regress.sh: it compares each Makefile's regression list with the
    targets make itself defines. A target in neither the run list nor the
    exclude list fails the run and is named, whatever it is called, so the all
    gap can't come back under a new name.
  - Makefile changes: a short block appended to the end of each of the 5
    Makefiles, adding a run list, an exclude list with a reason for each
    exclusion, and a regress_list target. No existing line changed.
  - tools/hooks/pre-push: tested in two scratch git repos. It allowed the push
    when the only failure was listed as known and refused it otherwise. I did
    not install it.
  - Tests on scratch copies outside the repo: an unlisted target (Problem 2), a
    broken check and a lint warning in each unit (Problem 4), and the three
    known-failure cases (Problem 5). All behaved as specified. Those copies are
    deleted, and the repo never held an injected fault.

  For you to decide
  - Verilator version: decode and lib take Verilator from PATH (5.020 at
    /usr/local/bin), not the project's 5.048 in tools/bin. I left this alone
    because the task forbids changing existing recipes; it's a candidate TD.
  - Top-level Makefile: the ftq omission in rtl/Makefile is either a candidate
    TD or a reason to retire those targets in favour of regress.sh.
  - Files to create or install: create tools/known_failures.txt from the
    proposed file, and install the hook with ln -s ../../tools/hooks/pre-push 
    .git/hooks/pre-push.
  - Suggested CLAUDE.md change (I didn't make it): the "ALL TARGETS MUST RUN"
    and "run both units after a package edit" rules could point to
    tools/regress.sh instead of asking for targets to be listed by hand. TD#99
    could be closed against this task.
  - Naming mismatch: Deliverables says rtl/Var.mk but the file is rtl/Vars.mk.
    The changes don't need it and it is unchanged.

## My Assessment

I worked interactively with the IA. This is a summary of the changes
that occurred after the initial task was complete.

Summary of everything after TOOLS-006 was reported complete.

  1. Verilator version in lib and decode — fixed
  Both Makefiles found Verilator on PATH (5.020 at /usr/local/bin), and lib's
  recipes called plain verilator. Both now include $(RVA_ROOT)/rtl/Vars.mk and
  use $(VERILATOR), matching bpu and ftq. make -n confirms both invoke
  tools/bin/verilator 5.048. Their decode header comment was updated to say
  5.048. Side effect: lib and decode now require RVA_ROOT to be set, as bpu and
  ftq already did.

  2. ftq missing from rtl/Makefile — fixed
  Added to all and to clean, since clean skipped it too. cov is unchanged
  because ftq has no coverage target.

  3. Hook install instruction — rewritten
  The old note gave a symlink path relative to .git/hooks, which is why it read
  oddly. The hook header now says to run once from the repo root:
  git config core.hooksPath tools/hooks

  4. tools/known_failures.txt — you created it
  It holds comment lines only, so regress.sh reads it as an empty waiver list. I
  did not write that file.

  5. Regression rerun after those changes
  Full run from the repo root: 78 targets, 78 PASS, 0 warnings, exit 0, 152s.
  This was the first run of the decode and lib suites under 5.048, and it
  produced no warning and no failed check. Decode wall time dropped from 90s to
  29s with identical check counts; I did not investigate why.

  6. CLAUDE.md
  I gave suggested text for the regression rules, you applied it, and I reviewed
  it. I found a conflict between the old task-Constraints waiver bullet and the
  new known_failures.txt rule, a duplicated current-session rule, and an
  overlapping "non-green suite" bullet. I then gave a preferred replacement for
  the whole Verification Expectations section, which you applied. You decided a
  waived entry does not need a TD number, and I made that wording change. An
  editor buffer later overwrote it, so I reapplied it. The section is now
  correct, ASCII only, and within 80 columns. While reviewing I also noted a
  non-ASCII dash and a 165-character line elsewhere in the file, which are now
  gone.

  7. prompts/TOOLS-006.md
  I added a Follow-on section inside the results markers recording items 1-5,
  and updated the three Deferred Work entries and the Problem 7 text that the
  follow-on resolved. The file still passes validate_and_extract.py.

  Still open
  regress.sh prints the third word of each known_failures.txt line as the TD
  field without checking it. With the TD requirement dropped, an entry that
  omits that field still works as a waiver, but its first description word will
  appear where the TD normally prints. Say the word if you want the format or
  the report tightened.

## Claude.ai Assessment

Read the whole file, results and follow-on included. Short version: the task did what it was for, and the evidence is real rather than asserted. The injection work is the part that matters. Every detection path is demonstrated except one, which the IA says plainly.

The finding that matters most

The lib testbench and all three decode testbenches reported a failed check and exited 0. A regression reading exit status called them PASS. The IA found this only because it injected faults rather than trusting the suites, which is exactly the standing rule about green reports working as intended.

The scope of it is worth being precise about. Those testbenches printed their failure counts, so any past result a human read from printed counts still stands. What was never true is that those suites could be checked mechanically. Had you built the push gate without Problem 4, it would have been blind to every decode and lib check failure from the first day. That alone repaid the task.

Where the evidence is complete, and where it isn't

Proven by injection: unlisted target, sim check failure and lint warning in every unit, and the three known-failure cases. The extra failures in each lint injection are explained by which sources each target compiles, which is the right level of care.

Not proven: the stale-entry path, an entry naming a target that was never run. The IA says so rather than implying coverage. It's a small gap and can be tested whenever something else touches regress.sh.

Things to look at
Decode wall time dropped from 90 s to 29 s after the Verilator change, with identical check counts, and the cause was not investigated. Identical counts mean the same checks ran, so this is probably compile and simulation speed under 5.048 with a warm ccache. It's still an unexplained 3x. One make -n comparison would settle it, and I'd rather not leave an unexplained number attached to the first run of a suite under a new tool version.
Decode and lib results are now under a different Verilator. Every previously recorded decode result was 5.020. The current PASS is 5.048. That belongs in the PROJECT_STATUS entry, since it changes what older decode results mean.
The known-failures TD field. As the IA notes, regress.sh prints the third word of each line as the TD number without checking it. Now that a TD isn't required, an entry without one prints its first description word in the TD column. Either require a - placeholder or have the parser accept a field only if it starts with TD#.
The hook install method. git config core.hooksPath tools/hooks disables everything in .git/hooks. If you have any local hooks there, they stop running silently. The symlink approach doesn't have that property.
tools/handoff.sh was already modified in the working tree before the task and was left alone. That also answers the earlier question about why the IA was looking at it. That unrelated change will ride along in whatever commit you make next unless you separate it.
rtl/Makefile cov still reaches only cov_bpu, so cov_bp_cluster is unreachable from the top. The follow-on fixed all and clean only.
Process note

The follow-on changed existing recipes, which the task constraints forbade. It's recorded inside the results markers, marked as done on your direct instruction, and the rerun is included. That's the right way to handle it. Worth noting for the record that the first TOOLS-006 result and the final tree are not the same thing, so anyone reading later should read to the end of the results.

What I'd do next
Commit, separating the handoff.sh change if it's unrelated. Then let the hook run once for real, since every regress run so far has been by hand on a dirty tree.
TDs: close TD#99 against this task. Open TDs for the top-level cov gap, the six targets whose check counts don't parse, and the TD-field parsing item if you don't fix it now.
PROJECT_STATUS: a session-073 entry covering TOOLS-006 and the follow-on, with the Verilator change for decode and lib called out. The Session-070 and Session-072 entries are still missing.
Then TD#122, which still waits on values for the five MMU widths.

## Follow-on Actions
- [x] CLAUDE.md changes made interactively

## CLAUDE.md Updates
Nothing required

## Other Planning File Updates
Nothing required

:: DISCUSSION:END ::

=============================================================
:: PROMPT:START ::
=============================================================

## Task ID
TOOLS-006

## Context Loaded
@rtl/Makefile
@rtl/Vars.mk
@rtl/lib/Makefile
@rtl/core/frontend/decode/Makefile
@rtl/core/frontend/bpu/Makefile
@rtl/core/frontend/ftq/Makefile

## Context Comments
These are the RTL Makefiles known to the project record, plus the
shared variables file they include. The record may be incomplete. If a
search of rtl/ finds a Makefile not listed above, it is in scope: read
it, run it and add the regress plumbing to it, and name it in Results
Capture.

Running a target reads the RTL and testbench sources it compiles. That
is expected and does not widen the manifest. Opening a testbench to
edit it is limited to the end-of-run change allowed in Problem 4.

tools/cachegen/output/ and import/ are out of scope. They hold
generated or superseded output and are not searched.

## Hypothesis
One command, run from the repo root with no arguments, can run every
test target in every rtl/ Makefile, report each target's result, and
exit non-zero on any failure not recorded as known. Its detection of a
failure, a lint warning, and a test target missing from the regression
set can each be proven by injection.

## Background
TD#99: `make all` is not a complete run in at least the bpu Makefile,
which omits sim and coverage targets from `all`. The current rule asks
the IA to enumerate targets by hand. Confirm the gap against the
Makefiles; do not take it from this paragraph.

Whether a failing self-checking testbench exits non-zero is not
recorded anywhere. A regression that reads exit status is only as good
as that assumption, so it is tested here rather than assumed.

The rtl/Makefile top level may or may not recurse into the unit
Makefiles. Determine which, so no target is run twice or skipped.

## Binding Previous Decisions
- The IA never creates or edits tools/known_failures.txt. That file is
  Jeff's. This task writes tools/known_failures.proposed.txt, and Jeff
  creates the real file from it.
- The hook is written to tools/hooks/pre-push. It is not installed into
  .git/hooks. Installing it is Jeff's.
- A test target is every lint, sim and coverage target. Build helpers,
  clean and similar are not; each exclusion is named with its reason.

## Specific Requirements
Form: PROBLEMS. Method, ordering within a problem and decomposition are
yours. Each problem states what must be true at the end.

### Problem 0 -- tree state
Before writing anything, check whether any of tools/regress.sh,
tools/hooks/, tools/known_failures.txt, tools/known_failures.proposed.txt
or a regress target in any rtl/ Makefile already exists. If any does,
stop and report what exists. Do not overwrite a partial state.

### Problem 1 -- baseline, before any edit
Find every Makefile under rtl/. For each, determine its complete set of
test targets and run each one individually, as the Makefile stands,
recording pass/fail, lint warning count, and check counts where the
testbench prints them.

Done when: every target in every Makefile is either in the before table
with a result or listed as excluded with a reason, and the table records
which targets `all` omits.

### Problem 2 -- a regression set that cannot silently go stale
Each Makefile exposes its complete test target set to the regression.
A test target that exists in a Makefile but is not in its regression set
must make the regression fail, naming the target. The same `all` gap
must not be reproducible under a new name.

Done when: on a scratch copy of the tree outside the repo, adding a
dummy test target to one Makefile without adding it to the regression
set makes tools/regress.sh exit non-zero and name it. Revert.

### Problem 3 -- tools/regress.sh
Runs from the repo root with no arguments, and accepts an optional root
path so it can run against a scratch copy. It:
- finds every Makefile under that root's rtl/, and lists them
- runs every test target in each, continuing past failures
- prints one summary, headed by the git sha and whether the tree is
  dirty, grouped by Makefile, one line per target: result, lint warning
  count, check counts where available
- prints wall time per Makefile and in total
- compares results against tools/known_failures.txt (a missing file is
  treated as empty) and exits zero only if every failing target is
  listed there and every listed target still fails

A listed target that now passes is reported as "known failure now
passes" with its TD number, and makes the run exit non-zero, so the
file cannot go stale.

Done when: the per-target result under tools/regress.sh matches the
Problem 1 before table target for target. Any difference is explained.

### Problem 4 -- failure detection is proven, not assumed
For each Makefile, on a scratch copy outside the repo: break one check
in one sim target, and introduce one lint warning in one lint target.
Confirm tools/regress.sh reports each as a failure of that target and
exits non-zero. Revert.

If a testbench reports a failed check but exits zero, change its
end-of-run code so that any failed check produces a non-zero exit. Do
not change what it checks. List every testbench changed.

### Problem 5 -- known-failure comparison
On a scratch copy, prove the three cases: a failing target listed in
tools/known_failures.txt gives exit zero; a failing target not listed
gives non-zero and names it; a listed target that passes gives
non-zero with the "now passes" message.

### Problem 6 -- proposed known-failures file
From the baseline, write tools/known_failures.proposed.txt: one line per
failing target, format

  <makefile dir> <target> TD#? <one-line description of the failure>

with # comment lines allowed. Leave the TD field as TD#? unless the
failure output itself names a TD. Jeff assigns the numbers.

### Problem 7 -- pre-push hook
Write tools/hooks/pre-push: runs tools/regress.sh from the repo root and
refuses the push on a non-zero exit, printing the summary. Do not
install it.

## Constraints
- No edits to any RTL module. Testbench edits are limited to the
  end-of-run exit status of Problem 4. Makefile and Var.mk edits are
  limited to the regression plumbing; no existing target's recipe,
  flags or sources change.
- Failures in existing targets found by the baseline are RECORDED, NOT
  FIXED, and do not block Status: complete. They are this task's output
  and belong to TDs Jeff will assign. This is a deliberate, scoped
  exception to fix-what-you-find: it covers pre-existing RTL and
  testbench failures only. A defect in the regression tooling or
  plumbing found during this task IS fixed in this task.
- A target whose result differs between the Problem 1 before table and
  the Problem 3 run, and is not explained by a Problem 4 exit-status
  fix, blocks Status: complete.
- Injection work of Problems 2, 4 and 5 is done on scratch copies
  outside the repo. The repo is never left with an injected fault.

## Deliverables
- tools/regress.sh
- tools/hooks/pre-push
- tools/known_failures.proposed.txt
- the regression plumbing in each rtl/ Makefile, and rtl/Var.mk if used
- any testbench end-of-run change from Problem 4
- Results Capture filled in below, in prompts/TOOLS-006.md, containing:
  the Makefiles found and whether rtl/Makefile recurses; the before
  table; the tools/regress.sh summary from the final run; the targets
  `all` omits; excluded targets with reasons; the injection evidence
  for Problems 2, 4 and 5, showing each failure appearing and the
  revert; testbenches changed; run time per Makefile and in total

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary
Status: complete. The hypothesis holds. tools/regress.sh, run from the
repo root with no arguments, found 5 Makefiles, ran all 78 test targets
one make call each, and exited 0: 78 PASS, 0 warnings, 223 s. This
matches the Problem 1 baseline target for target (78 PASS, 0 warnings).
Injection on scratch copies proved each detection path: an unlisted
target (P2), a failed check and a lint warning in every unit (P4), and
all three known-failure cases (P5). The injections also showed that the
lib and the three decode testbenches exited 0 on a failed check.
Their end-of-run code now exits through $fatal(1). The baseline found
no failing target, so tools/known_failures.proposed.txt holds comments
only.

## Test Matrix (testbench sessions only, omit otherwise)
Not a testbench session. Omitted.

## What was delivered
- tools/regress.sh: the regression command. It takes an optional
  ROOT argument (default: the repo root). It sets RVA_ROOT=ROOT, finds
  every Makefile under ROOT/rtl, and checks each one's regression set
  against make's own rule database (make -pRrq). It then runs each
  REGRESS_TARGETS entry as `make -B -C <dir> <target>`, continuing past
  failures. The summary is headed by the git sha and the clean/dirty
  state and grouped by Makefile, one line per target: result, rc,
  %Warning count, %Error count, check counts (pass/fail) and seconds.
  It also prints wall time per Makefile and in total. A target fails
  on a non-zero exit OR on any %Warning line in its log. Exit is 0
  only when there are no regression-set errors, every failure is
  listed in tools/known_failures.txt, and every listed entry still
  fails.
- Regression plumbing, appended to the end of each rtl/ Makefile (no
  existing line changed): REGRESS_TARGETS, REGRESS_EXCLUDE (each
  exclusion commented with its reason), and a `regress_list` target
  that prints both lists.
- End-of-run exit status fix in four testbenches (Problem 4).
- tools/known_failures.proposed.txt (comments only; no failing target).
- tools/hooks/pre-push (not installed).

## Test Case Results

### Problem 0 -- tree state
None of these existed before the task: tools/regress.sh, tools/hooks/,
tools/known_failures.txt, tools/known_failures.proposed.txt, or a
regress target in any rtl/ Makefile (grep -i regress over every rtl/
Makefile and *.mk returned nothing). Work proceeded.

### Makefiles found, and whether rtl/Makefile recurses
find rtl -name Makefile (also checked: makefile, GNUmakefile):
- rtl/Makefile
- rtl/lib/Makefile
- rtl/core/frontend/decode/Makefile
- rtl/core/frontend/bpu/Makefile
- rtl/core/frontend/ftq/Makefile
No Makefile outside the Context Loaded list exists. The many
obj*/Vtb.mk and Vtb_classes.mk files are Verilator-generated build
files, not project Makefiles. rtl/Vars.mk is included by bpu and ftq
only; lib, decode and rtl/Makefile do not include it.

rtl/Makefile RECURSES. It defines no test target of its own:
- all   -> make -C lib all, make -C core/frontend/decode all,
           make -C core/frontend/bpu all. It does NOT reach ftq.
- cov   -> make -C core/frontend/bpu cov_bpu
- clean -> clean in lib, decode, bpu (not ftq)
regress.sh runs every unit Makefile directly, so rtl/Makefile's three
targets are excluded to avoid running unit targets twice. Its
REGRESS_TARGETS is empty.

### Targets `all` omits (TD#99, confirmed against the Makefiles)
- bpu: sim_ittage, sim_tage_manual, cov_history, cov_ubtb,
  cov_loop_pred, cov_tage_table, cov_tage, cov_bp_cluster, cov_bpu
  (9 test targets). TD#99 is confirmed.
- decode: none. all = lint sim sim_all, which covers all three lint_*,
  all three sim_* and coverage.
- ftq: none.
- lib: none.
- rtl/Makefile: its `all` omits the whole ftq unit (22 test targets),
  and its `cov` runs only bpu cov_bpu (cov_bp_cluster is not reached).

### Excluded targets, with reasons
Every target make defines in each Makefile is in REGRESS_TARGETS or in
REGRESS_EXCLUDE. regress.sh fails on any target in neither list.
- rtl/Makefile: all, cov, clean (recursion into unit Makefiles, see
  above); regress_list (the plumbing).
- lib: all (aggregate of lint + sim); obj_dir/Vtb (the build helper
  that sim depends on; runs inside sim); clean; regress_list.
- decode: all, lint, sim, sim_all (aggregates: their recipes only run
  lint_exp/lint_dec/lint_predecode, sim_exp/sim_dec, and
  sim_predecode/sim_dec/coverage); help (prints text); clean;
  regress_list.
- bpu: all (aggregate); clean, clean_cov, clean_cov_tage,
  clean_cov_tage_table, clean_cov_loop_pred, clean_cov_history,
  clean_cov_ubtb, clean_cov_bp_cluster, clean_cov_bpu (housekeeping);
  regress_list.
- ftq: all (aggregate); clean; regress_list.
cov_bpu is KEPT as a test target. It re-runs five cov_* targets and
then merges their data. The merge step belongs only to cov_bpu.

### Problem 1 -- before table (baseline, before any edit)
Every target was run individually with `make -B -C <dir> <target>`,
RVA_ROOT set to the repo, against the Makefiles and testbenches as they
stood. The four units ran in parallel with each other; targets within
a unit ran in sequence. rc = make exit status, warn = count of
%Warning lines, checks = pass/fail as printed by the testbench ("-"
where the testbench prints no parseable total). Result: 78 targets,
78 rc=0, 0 warnings, 0 failed checks.
The decode sim_exp/sim_dec/sim_predecode and lib sim results were
also read from the printed counts (FAIL=0 / 34/34), because Problem 4
later showed those four testbenches exit 0 on a failed check.
rtl/Makefile: no test target (see exclusions).

```
== rtl_core_frontend_bpu  rtl/core/frontend/bpu TOTAL sec=107
  lint                   rc=0   warn=0  -           sec=1
  lint_bp_cluster        rc=0   warn=0  -           sec=1
  lint_ftb               rc=0   warn=0  -           sec=0
  lint_ftb_array         rc=0   warn=0  -           sec=0
  lint_ftb_cntrl         rc=0   warn=0  -           sec=0
  lint_ftb_plru          rc=0   warn=0  -           sec=1
  lint_ittage            rc=0   warn=0  -           sec=0
  lint_ittage_cntrl      rc=0   warn=0  -           sec=0
  lint_ittage_table      rc=0   warn=0  -           sec=0
  lint_loop_pred         rc=0   warn=0  -           sec=1
  lint_ras               rc=0   warn=0  -           sec=0
  lint_sc                rc=0   warn=0  -           sec=0
  lint_sc_brimli         rc=0   warn=0  -           sec=0
  lint_sc_cntrl          rc=0   warn=0  -           sec=0
  lint_sc_table          rc=0   warn=0  -           sec=0
  lint_tage              rc=0   warn=0  -           sec=1
  lint_tage_cntrl        rc=0   warn=0  -           sec=1
  lint_tage_table        rc=0   warn=0  -           sec=0
  sim                    rc=0   warn=0  29/0        sec=0
  sim_bp_cluster         rc=0   warn=0  1795/0      sec=4
  sim_ftb                rc=0   warn=0  99/0        sec=2
  sim_history            rc=0   warn=0  -           sec=3
  sim_ittage             rc=0   warn=0  211/0       sec=3
  sim_ittage_cntrl       rc=0   warn=0  147/0       sec=2
  sim_ittage_table       rc=0   warn=0  32/0        sec=0
  sim_loop_pred          rc=0   warn=0  9342/0      sec=3
  sim_ras                rc=0   warn=0  87/0        sec=0
  sim_sc                 rc=0   warn=0  55/0        sec=2
  sim_sc_brimli          rc=0   warn=0  7/0         sec=0
  sim_sc_brimli_fast     rc=0   warn=0  7/0         sec=1
  sim_sc_cntrl           rc=0   warn=0  98/0        sec=2
  sim_sc_fast            rc=0   warn=0  52/0        sec=2
  sim_sc_table           rc=0   warn=0  6/0         sec=1
  sim_sc_table_fast      rc=0   warn=0  6/0         sec=0
  sim_tage               rc=0   warn=0  -           sec=2
  sim_tage_fast          rc=0   warn=0  -           sec=3
  sim_tage_manual        rc=0   warn=0  -/0         sec=2
  sim_tage_table         rc=0   warn=0  15/0        sec=1
  sim_tage_tasks         rc=0   warn=0  -           sec=2
  sim_ubtb               rc=0   warn=0  259/0       sec=2
  cov_bp_cluster         rc=0   warn=0  1795/0      sec=13
  cov_history            rc=0   warn=0  -           sec=6
  cov_loop_pred          rc=0   warn=0  9342/0      sec=5
  cov_tage               rc=0   warn=0  -           sec=6
  cov_tage_table         rc=0   warn=0  15/0        sec=1
  cov_ubtb               rc=0   warn=0  259/0       sec=8
  cov_bpu                rc=0   warn=0  259/0       sec=25
== rtl_core_frontend_decode  rtl/core/frontend/decode TOTAL sec=96
  lint_exp               rc=0   warn=0  -           sec=1
  lint_dec               rc=0   warn=0  -           sec=0
  lint_predecode         rc=0   warn=0  -           sec=0
  sim_exp                rc=0   warn=0  43/0        sec=21
  sim_dec                rc=0   warn=0  567/0       sec=44
  sim_predecode          rc=0   warn=0  476/0       sec=23
  coverage               rc=0   warn=0  -           sec=7
== rtl_core_frontend_ftq  rtl/core/frontend/ftq TOTAL sec=11
  lint_ftq_ftb_sched     rc=0   warn=0  -           sec=1
  sim_ftq_ftb_sched      rc=0   warn=0  67/0        sec=0
  lint_ftq_ptr           rc=0   warn=0  -           sec=0
  sim_ftq_ptr            rc=0   warn=0  102/0       sec=0
  lint_ftq_commit        rc=0   warn=0  -           sec=0
  sim_ftq_commit         rc=0   warn=0  72/0        sec=1
  lint_ftq_entry         rc=0   warn=0  -           sec=0
  sim_ftq_entry          rc=0   warn=0  48/0        sec=0
  lint_ftq_meta          rc=0   warn=0  -           sec=0
  sim_ftq_meta           rc=0   warn=0  26/0        sec=1
  lint_ftq_status        rc=0   warn=0  -           sec=0
  sim_ftq_status         rc=0   warn=0  40/0        sec=0
  lint_ftq_shadow        rc=0   warn=0  -           sec=0
  sim_ftq_shadow         rc=0   warn=0  44/0        sec=1
  lint_ftq_npc           rc=0   warn=0  -           sec=0
  sim_ftq_npc            rc=0   warn=0  66/0        sec=0
  lint_ftq_ifu           rc=0   warn=0  -           sec=0
  sim_ftq_ifu            rc=0   warn=0  67/0        sec=1
  lint_ftq_resolve       rc=0   warn=0  -           sec=0
  sim_ftq_resolve        rc=0   warn=0  82/0        sec=3
  lint_ftq               rc=0   warn=0  -           sec=0
  sim_ftq                rc=0   warn=0  56/0        sec=3
== rtl_lib  rtl/lib TOTAL sec=11
  lint                   rc=0   warn=0  -           sec=1
  sim                    rc=0   warn=0  34/0        sec=10
```

### Problem 2 -- the regression set cannot silently go stale
Mechanism: regress.sh reads the defined targets from make's rule
database, which is independent of any hand-kept list. It fails when a
defined target is in neither REGRESS_TARGETS nor REGRESS_EXCLUDE, when
a listed name is not defined, or when a name is in both lists. A hand
list that omits a target (the `all` gap) cannot pass under any name,
because the check is against what make defines, not against a
naming pattern.

Injection (scratch copy <scratchpad>/p2_dummy, outside the repo):
appended to rtl/core/frontend/ftq/Makefile:
```
sim_dummy_tools006:
	@echo dummy
```
regress.sh <scratchpad>/p2_dummy:
```
  REGRESS-SET ERROR  sim_dummy_tools006: defined, not in the regression set
new failures: 0   known failures: 0   now passing: 0   stale entries: 0   set errors: 1
REGRESS-SET ERROR: rtl/core/frontend/ftq: target 'sim_dummy_tools006' is in neither REGRESS_TARGETS nor REGRESS_EXCLUDE
RESULT: FAIL
exit=1
```
Revert: the fault existed only in the scratch copy, which has been
deleted. The repo ftq Makefile never contained it (grep for
sim_dummy over rtl/ returns nothing).

### Problem 3 -- tools/regress.sh final run (repo root, no arguments)
Per-target result is identical to the before table, target for target
(checked by diffing the two sorted "<dir> <target> <PASS|FAIL>" lists:
no difference). The four testbench exit-status changes do not change
any result, because no check fails in the unmodified tree.
Check-count notes: cov_bpu shows 259/0, which is the last summary in
its log (the cov_ubtb sub-run). "-" means the testbench prints no
total in any of the formats the parser recognizes (sim_history,
sim_tage, sim_tage_fast, sim_tage_tasks, cov_history, cov_tage); those
targets still print PASS/FAIL per test and exit non-zero on failure.

```
==================================================================
REGRESSION SUMMARY  git 3cf74e8 (dirty)
root /home/jeff/Development/jeffnye-gh/pacino
==================================================================
== rtl/core/frontend/bpu
  PASS       lint                   rc=0   warn=0  err=0  -              1s
  PASS       lint_loop_pred         rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_table        rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_table          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_brimli         rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_cntrl          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc                rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_table      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_cntrl      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage            rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_cntrl        rc=0   warn=0  err=0  -              0s
  PASS       lint_tage              rc=0   warn=0  err=0  -              1s
  PASS       lint_ras               rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_array         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru          rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl         rc=0   warn=0  err=0  -              1s
  PASS       lint_ftb               rc=0   warn=0  err=0  -              0s
  PASS       lint_bp_cluster        rc=0   warn=0  err=0  -              1s
  PASS       sim                    rc=0   warn=0  err=0  29/0           0s
  PASS       sim_history            rc=0   warn=0  err=0  -              3s
  PASS       sim_ubtb               rc=0   warn=0  err=0  259/0          3s
  PASS       sim_loop_pred          rc=0   warn=0  err=0  9342/0         2s
  PASS       sim_tage_table         rc=0   warn=0  err=0  15/0           1s
  PASS       sim_sc_table           rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_table_fast      rc=0   warn=0  err=0  6/0            1s
  PASS       sim_sc_brimli          rc=0   warn=0  err=0  7/0            0s
  PASS       sim_sc_brimli_fast     rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_cntrl           rc=0   warn=0  err=0  98/0           3s
  PASS       sim_sc                 rc=0   warn=0  err=0  55/0           2s
  PASS       sim_sc_fast            rc=0   warn=0  err=0  52/0           2s
  PASS       sim_ittage_table       rc=0   warn=0  err=0  32/0           1s
  PASS       sim_ittage_cntrl       rc=0   warn=0  err=0  147/0          2s
  PASS       sim_ittage             rc=0   warn=0  err=0  211/0          4s
  PASS       sim_bp_cluster         rc=0   warn=0  err=0  1795/0         4s
  PASS       sim_ras                rc=0   warn=0  err=0  87/0           0s
  PASS       sim_ftb                rc=0   warn=0  err=0  99/0           3s
  PASS       sim_tage               rc=0   warn=0  err=0  -              2s
  PASS       sim_tage_fast          rc=0   warn=0  err=0  -              3s
  PASS       sim_tage_tasks         rc=0   warn=0  err=0  -              2s
  PASS       sim_tage_manual        rc=0   warn=0  err=0  -/0            3s
  PASS       cov_history            rc=0   warn=0  err=0  -              7s
  PASS       cov_ubtb               rc=0   warn=0  err=0  259/0          6s
  PASS       cov_loop_pred          rc=0   warn=0  err=0  9342/0         5s
  PASS       cov_tage_table         rc=0   warn=0  err=0  15/0           1s
  PASS       cov_tage               rc=0   warn=0  err=0  -              6s
  PASS       cov_bp_cluster         rc=0   warn=0  err=0  1795/0        13s
  PASS       cov_bpu                rc=0   warn=0  err=0  259/0         26s
  time 112s
== rtl/core/frontend/decode
  PASS       lint_exp               rc=0   warn=0  err=0  -              0s
  PASS       lint_dec               rc=0   warn=0  err=0  -              1s
  PASS       lint_predecode         rc=0   warn=0  err=0  -              0s
  PASS       sim_exp                rc=0   warn=0  err=0  43/0          15s
  PASS       sim_dec                rc=0   warn=0  err=0  567/0         43s
  PASS       sim_predecode          rc=0   warn=0  err=0  476/0         23s
  PASS       coverage               rc=0   warn=0  err=0  -              8s
  time 90s
== rtl/core/frontend/ftq
  PASS       lint_ftq_ftb_sched     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ftb_sched      rc=0   warn=0  err=0  67/0           1s
  PASS       lint_ftq_ptr           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ptr            rc=0   warn=0  err=0  102/0          0s
  PASS       lint_ftq_commit        rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_commit         rc=0   warn=0  err=0  72/0           0s
  PASS       lint_ftq_entry         rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_entry          rc=0   warn=0  err=0  48/0           1s
  PASS       lint_ftq_meta          rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta           rc=0   warn=0  err=0  26/0           0s
  PASS       lint_ftq_status        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_status         rc=0   warn=0  err=0  40/0           1s
  PASS       lint_ftq_shadow        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_shadow         rc=0   warn=0  err=0  44/0           0s
  PASS       lint_ftq_npc           rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_npc            rc=0   warn=0  err=0  66/0           0s
  PASS       lint_ftq_ifu           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ifu            rc=0   warn=0  err=0  67/0           1s
  PASS       lint_ftq_resolve       rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_resolve        rc=0   warn=0  err=0  82/0           2s
  PASS       lint_ftq               rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq                rc=0   warn=0  err=0  56/0           2s
  time 11s
== rtl/lib
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       sim                    rc=0   warn=0  err=0  34/0          10s
  time 10s
== rtl
  time 0s
------------------------------------------------------------------
targets run: 78   total time: 223s
new failures: 0   known failures: 0   now passing: 0   stale entries: 0   set errors: 0
logs: <scratchpad>/regress.hV1K2M
RESULT: PASS
```

### Problem 4 -- failure detection proven by injection
Every injection was made in its own full scratch copy of the tree
(rtl/ copied, tools/ symlinked except regress.sh), outside the repo.
`diff -rq` against the repo rtl/ showed exactly the one injected file
changed in each copy. Each run was the full regress.sh over all 5
Makefiles. rtl/Makefile has no test target, so no injection applies
to it.

Injections (the line after injection):
- lib sim     tb_components.sv:412
    alu_check(4'hE, 4'h1, 1'b0, 4'h0, 1'b0, "E+1=F",      1);
- lib lint    sat_alu.sv, before endmodule (WIDTHTRUNC)
    logic [3:0] tools006_inj;  assign tools006_inj = 8'hA5;
- decode sim  tb_rvc_expander.sv:131
    check(0, 32'h02A10094, 1'b1, "T2_passthrough_ADDI");
- decode lint rvc_expander.sv, appended `module tools006_inj; endmodule`
    (DECLFILENAME + MULTITOP; the sim targets pass -Wno-DECLFILENAME
    and --top-module tb, so only the lint target sees it)
- bpu sim     tb_ras.sv:220
    check("TC-01 tosr==0", dut.tosr != '0);
- bpu lint    ras.sv, appended `module tools006_inj; endmodule`
- ftq sim     tb_ftq_ptr.sv:292
    chk("B9a alias-full asserted at 64 live", !ptr_alias_full);
- ftq lint    ftq_ptr.sv, appended `module tools006_inj; endmodule`

Results, BEFORE the testbench exit-status change:
```
lib_sim   PASS       sim        rc=0 warn=0 err=0 33/1      -> MISSED
          log: "tb_components: 33/34 PASSED" / "FAILURES: 1" / $finish
          new failures: 0 ... RESULT: PASS  exit=0
lib_lint  FAIL       lint       rc=2 warn=1 err=1
          FAIL       sim        rc=2 warn=1 err=1
          RESULT: FAIL  exit=1
dec_sim   PASS       sim_exp    rc=0 warn=0 err=0 42/1      -> MISSED
          log: "rvc_expander: PASS=42  FAIL=1" / "STATUS: FAIL"
          RESULT: PASS  exit=0
dec_lint  FAIL       lint_exp   rc=2 warn=2 err=1
          RESULT: FAIL  exit=1
bpu_sim   FAIL       sim_ras    rc=2 warn=0 err=1 86/1
          RESULT: FAIL  exit=1
bpu_lint  FAIL       lint_ras        rc=2 warn=2 err=1
          FAIL       lint_bp_cluster rc=2 warn=1 err=1
          RESULT: FAIL  exit=1
ftq_sim   FAIL       sim_ftq_ptr rc=2 warn=0 err=1 101/1
          RESULT: FAIL  exit=1
ftq_lint  FAIL       lint_ftq_ptr rc=2 warn=1 err=1
          FAIL       lint_ftq     rc=2 warn=1 err=1
          RESULT: FAIL  exit=1
```
In every run, all other targets passed (failures + passes = 78).
The extra failures are explained by what each target compiles:
- lib_lint: lib lint and sim compile the same sources with the same
  -Wall flags, so the warning is fatal to both.
- bpu_lint: lint_bp_cluster lints ras.sv too. It passes --top-module,
  so it shows DECLFILENAME only (1 warning); lint_ras shows
  DECLFILENAME and MULTITOP (2 warnings).
- ftq_lint: lint_ftq lints ftq_ptr.sv too.

The two decode testbenches that had not been injected yet
(tb_instr_decoder, tb_predecode) were injected with their HEAD
end-of-run code (scratch copy p4_pre_dec23):
- decode sim_dec  tb_instr_decoder.sv:791
    `CHECK_VEC(0, is_vsetvl,   1'b0,    "T24_vsetvli_e32m1ta")
- decode sim_predecode  tb_predecode.sv:252
    check_may_be_branch(8'b00000001, "TC01");
```
  PASS       sim_dec                rc=0   warn=0  err=0  566/1         42s
  PASS       sim_predecode          rc=0   warn=0  err=0  475/1         22s
RESULT: PASS  exit=0                                       -> MISSED
```
Conclusion: the lib testbench and all three decode testbenches reported
a failed check and exited 0.

Fix: changed only the end-of-run code of those four testbenches. A
failed run now ends with $fatal(1, ...) in a branch exclusive of
$finish, the pattern the bpu/ftq testbenches already use (BP-094,
BP-095). What each testbench checks is unchanged. The decode sims build
with a custom verilator/sim_main*.cpp (--cc --exe) under Verilator
5.020. In 5.020, $fatal reaches vl_fatal(), which calls std::abort(),
so the exit is non-zero without changing sim_main. The injection
below confirms this.

Results AFTER the change: all four sim faults in one scratch copy
(p4_post). Each fault is in a different testbench, so each can only
affect its own target:
```
== rtl/core/frontend/decode
  FAIL       sim_exp                rc=2   warn=0  err=1  42/1          16s
  FAIL       sim_dec                rc=2   warn=0  err=1  566/1         42s
  FAIL       sim_predecode          rc=2   warn=0  err=1  475/1         22s
== rtl/lib
  FAIL       sim                    rc=2   warn=0  err=1  33/1          11s
new failures: 4   known failures: 0   now passing: 0   stale entries: 0   set errors: 0
FAIL: rtl/core/frontend/decode sim_exp (exit 2, 0 warning(s)) ...
FAIL: rtl/core/frontend/decode sim_dec (exit 2, 0 warning(s)) ...
FAIL: rtl/core/frontend/decode sim_predecode (exit 2, 0 warning(s)) ...
FAIL: rtl/lib sim (exit 2, 0 warning(s)) ...
RESULT: FAIL
exit=1
```
All 74 other targets passed in that run.

Revert: every fault existed only in scratch copies, which have been
deleted. Before the final run, the repo was checked: git status lists
only the intended files, and grep for tools006 / sim_dummy over rtl/
returns nothing.

### Problem 5 -- known-failure comparison
All three cases used a scratch copy with its own tools/known_failures.txt.
The repo has no tools/known_failures.txt.
- Case a: sim_ftq_ptr injected (as in ftq_sim) and listed:
    rtl/core/frontend/ftq sim_ftq_ptr TD#? injected check B9a
  ```
    KNOWN-FAIL sim_ftq_ptr            rc=2   warn=0  err=1  101/1          1s
  new failures: 0   known failures: 1   now passing: 0   stale entries: 0   set errors: 0
  known failure: rtl/core/frontend/ftq sim_ftq_ptr TD#?
  RESULT: PASS
  exit=0
  ```
- Case b: sim_ftq_ptr injected; the file exists but holds only a comment:
  ```
    FAIL       sim_ftq_ptr            rc=2   warn=0  err=1  101/1          0s
  new failures: 1   known failures: 0   now passing: 0   stale entries: 0   set errors: 0
  FAIL: rtl/core/frontend/ftq sim_ftq_ptr (exit 2, 0 warning(s)) log ...
  RESULT: FAIL
  exit=1
  ```
- Case c: clean tree; sim_ftq_ptr listed:
    rtl/core/frontend/ftq sim_ftq_ptr TD#? listed but passes
  ```
    NOW-PASSES sim_ftq_ptr            rc=0   warn=0  err=0  102/0          1s
  new failures: 0   known failures: 0   now passing: 1   stale entries: 0   set errors: 0
  KNOWN FAILURE NOW PASSES: rtl/core/frontend/ftq sim_ftq_ptr TD#?: known failure now passes
  RESULT: FAIL
  exit=1
  ```
An entry naming a target that was not run is reported as a STALE
KNOWN-FAILURE ENTRY and also exits non-zero. This case was not
injected.

### Problem 6 -- tools/known_failures.proposed.txt
The baseline found no failing target, so the file holds only comment
lines. They state the format, the baseline it came from (78 run,
78 pass, 0 warnings), and that the lib/decode passes were confirmed
from printed counts.

### Problem 7 -- tools/hooks/pre-push
Runs ./tools/regress.sh from `git rev-parse --show-toplevel`. It
prints the summary block, or the whole output if regress.sh stopped
before printing a summary, and exits 1 (push refused) when regress.sh
exits non-zero. It is not installed; its header comment gives the
install command (see Follow-on). It was tested in two scratch git repos (git init in
the scratch copies):
- case-a tree (known failure only): "RESULT: PASS" /
  "pre-push: regression passed." / hook exit=0
- case-b tree (unlisted failure): "FAIL: rtl/core/frontend/ftq
  sim_ftq_ptr ..." / "pre-push: regression failed (exit 1). Push
  refused." / hook exit=1

### Testbenches changed
- rtl/lib/tb/tb_components.sv
- rtl/core/frontend/decode/tb/tb_rvc_expander.sv
- rtl/core/frontend/decode/tb/tb_instr_decoder.sv
- rtl/core/frontend/decode/tb/tb_predecode.sv
End-of-run exit status only.

### Run time per Makefile and in total (final regress.sh run, serial)
- rtl/core/frontend/bpu     112 s  (47 targets)
- rtl/core/frontend/decode   90 s  (7 targets)
- rtl/core/frontend/ftq      11 s  (22 targets)
- rtl/lib                    10 s  (2 targets)
- rtl                         0 s  (0 targets)
- total                     223 s  (78 targets)
Baseline, for comparison (units in parallel): bpu 107 s, decode 96 s,
ftq 11 s, lib 11 s. ccache is active (/usr/bin/ccache), so the C++
compile times are cache-warm figures.

## Assumptions made not explicit in the prompt
- The Deliverables line says rtl/Var.mk. The file is rtl/Vars.mk (as
  Context Loaded lists it). The plumbing does not use it and it is
  unchanged: lib and decode do not include it, and adding the include
  would make them depend on RVA_ROOT.
- "Test target" covers decode `coverage` (the RVA23 opcode coverage
  script) and bpu cov_bpu, since both are coverage targets.
- A target fails on a non-zero exit OR on any %Warning line in its
  log, even with exit 0. Under -Wall without -Wno-fatal these are the
  same today. The second test keeps a warning from passing if a target
  ever adds -Wno-fatal.
- regress.sh runs targets with make -B so every target rebuilds, and
  exports RVA_ROOT=<root> so a scratch copy uses its own Vars.mk and
  tools/bin. The baseline was run the same way.
- For the proposed file, "failing target" means failing in the
  Problem 1 baseline. There were none.

## Decisions made not explicit in the prompt
- Classification is complete, not pattern-based. Every target make
  defines must be listed in REGRESS_TARGETS or REGRESS_EXCLUDE. A new
  target with any name, not only lint*/sim*/cov*, fails the regression
  until it is classified.
- The plumbing is appended at the end of each Makefile, so no default
  goal changes (rtl/Makefile, lib and decode have no .DEFAULT_GOAL). It
  adds its own `.PHONY: regress_list` line instead of editing the
  existing .PHONY lines. No existing line of any Makefile changed
  (git diff: insertions only).
- regress.sh runs targets one at a time, in sequence, so the reported
  times are per-target wall times and the obj dirs cannot conflict.
  Logs go to a mktemp directory under $TMPDIR, whose path is printed,
  so a run adds no files to the repo.
- A known-failures entry whose target was not run is reported as stale
  and exits non-zero, for the same reason as the "now passes" case.
- The P4 injections used separate scratch copies so each failure can
  be traced to one fault. The post-fix check put all four sim faults
  in one copy, since each is in a different testbench.

## RVA23 compliance risks and gaps noticed
None from this task. It touches tooling and end-of-run code only.

## Deferred Work
- decode and lib Makefiles take verilator from PATH (`which verilator`
  resolves to /usr/local/bin/verilator, Verilator 5.020). bpu and ftq
  use $(RVA_ROOT)/tools/bin/verilator (5.048). CLAUDE.md requires
  5.048. This was not changed because the constraints forbid changing
  existing flags or recipes. It is a candidate TD.
  RESOLVED in the follow-on below.
- rtl/Makefile `all` and `clean` omit the ftq unit, and `cov` reaches
  only bpu cov_bpu. regress.sh does not use them. Candidate TD, or
  retire the top-level targets in favour of tools/regress.sh.
  ftq added to `all` and `clean` in the follow-on below.
- Check counts are best-effort parsing of the testbench summary lines.
  Six targets print no total the parser recognizes. cov_bpu shows the
  last sub-run's count. The pass/fail result does not depend on this
  parsing.
- tools/known_failures.txt is Jeff's to create from the proposed file
  (done by Jeff, see follow-on). tools/hooks/pre-push is Jeff's to
  install.

## Other Notes
- Suggested planning/CLAUDE.md update (not made; planning files are
  read-only): the "ALL TARGETS MUST RUN" and "PACKAGE EDIT WIDENS THE
  RUN TO BOTH UNITS" rules can point to `tools/regress.sh`. It runs
  every target of every unit and fails on an unclassified target, so
  the hand enumeration is no longer needed. TD#99 can be closed
  against this task: the bpu `all` gap is confirmed, and regress.sh
  covers all 9 omitted targets.
- tools/handoff.sh was already modified in the working tree before
  this task; it was not touched.
- The final run header reads "git 3cf74e8 (dirty)". The tree is dirty
  from this task's uncommitted changes and from pre-existing untracked
  files.

## Follow-on (interactive, after review, same session)
Changes Jeff asked for after reading the results above. They are made
on Jeff's direct instruction; they change existing recipes, which the
original task constraints did not allow.
- rtl/lib/Makefile and rtl/core/frontend/decode/Makefile: the
  `VERILATOR := $(shell which verilator)` block is replaced by
  `include $(RVA_ROOT)/rtl/Vars.mk`, as bpu and ftq already do. The
  two lib recipes that called plain `verilator` now call
  $(VERILATOR). The decode header comment now says 5.048. `make -n`
  confirms both units now invoke
  $(RVA_ROOT)/tools/bin/verilator (Verilator 5.048 rev v5.048). lib
  and decode now need RVA_ROOT set, like bpu and ftq.
- rtl/Makefile: `$(MAKE) -C core/frontend/ftq all` added to `all`,
  and the matching line added to `clean`. `cov` is unchanged; ftq has
  no coverage target. The TOOLS-006 plumbing (all/cov/clean excluded
  as recursion) still applies.
- tools/hooks/pre-push: the install note in the header now reads
  `git config core.hooksPath tools/hooks` (run once from the repo
  root) instead of a relative symlink into .git/hooks.
- tools/known_failures.txt: created by Jeff from the proposed file
  (comment lines only, so no entries). The IA did not write it.
- CLAUDE.md: Jeff applied the suggested regression rules under
  Verification Expectations. The IA did not edit CLAUDE.md.

Regression after the follow-on, run in this session from the repo root
with no arguments, reading the new tools/known_failures.txt:
```
REGRESSION SUMMARY  git 3cf74e8 (dirty)
== rtl/core/frontend/decode
  PASS       lint_exp               rc=0   warn=0  err=0  -              0s
  PASS       lint_dec               rc=0   warn=0  err=0  -              1s
  PASS       lint_predecode         rc=0   warn=0  err=0  -              0s
  PASS       sim_exp                rc=0   warn=0  err=0  43/0           6s
  PASS       sim_dec                rc=0   warn=0  err=0  567/0          8s
  PASS       sim_predecode          rc=0   warn=0  err=0  476/0          6s
  PASS       coverage               rc=0   warn=0  err=0  -              8s
  time 29s
== rtl/lib
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       sim                    rc=0   warn=0  err=0  34/0           4s
  time 4s
targets run: 78   total time: 152s
new failures: 0   known failures: 0   now passing: 0   stale entries: 0   set errors: 0
RESULT: PASS   exit=0
```
All 78 targets PASS with 0 warnings. bpu (47) and ftq (22) are
unchanged from the final run above. This is the first run of the
decode and lib suites under Verilator 5.048; it adds no warning and
no failed check. Decode wall time dropped from 90 s to 29 s with
identical check counts; the cause was not investigated.

## Files Modified
- tools/regress.sh
- tools/hooks/pre-push
- tools/known_failures.proposed.txt
- rtl/Makefile
- rtl/lib/Makefile
- rtl/core/frontend/decode/Makefile
- rtl/core/frontend/bpu/Makefile
- rtl/core/frontend/ftq/Makefile
- rtl/lib/tb/tb_components.sv
- rtl/core/frontend/decode/tb/tb_rvc_expander.sv
- rtl/core/frontend/decode/tb/tb_instr_decoder.sv
- rtl/core/frontend/decode/tb/tb_predecode.sv
- prompts/TOOLS-006.md


:: RESULTS:END ::

:: CONTEXT:START ::

# Context Usage

Context used: 23% (233.6k of 1m tokens)

Model: claude-opus-5[1m] (Opus 5, 1M context)
Auto-compact window: 1m tokens

## Estimated usage by category

| Category                 | Tokens | Percent |
|--------------------------|--------|---------|
| System prompt            | 2.3k   | 0.2%    |
| System tools             | 19.8k  | 2.0%    |
| System tools (deferred)  | 26k    | 2.6%    |
| MCP tools (deferred)     | 3.7k   | 0.4%    |
| Memory files             | 5.5k   | 0.5%    |
| Skills                   | 4.3k   | 0.4%    |
| Messages                 | 202.6k | 20.3%   |
| Free space               | 732.5k | 73.2%   |
| Autocompact buffer       | 33k    | 3.3%    |

## Memory files

| Type    | Path                                          | Tokens |
|---------|-----------------------------------------------|--------|
| Project | CLAUDE.md                                     | 4.6k   |
| AutoMem | ~/.claude/projects/-home-jeff-Development-jeffnye-gh-pacino/memory/MEMORY.md | 844 |

## Skills loaded

| Skill                          | Source         | Tokens |
|--------------------------------|----------------|--------|
| cntx                           | Project        | ~30    |
| run                            | Project        | ~20    |
| dataviz                        | Built-in       | ~480   |
| artifact-design                | Built-in       | ~70    |
| artifact-diagramming           | Built-in       | ~70    |
| artifact-capabilities          | Built-in       | ~220   |
| update-config                  | Built-in       | ~240   |
| keybindings-help               | Built-in       | ~80    |
| code-review                    | Built-in       | ~280   |
| simplify                       | Built-in       | ~60    |
| fewer-permission-prompts       | Built-in       | ~60    |
| loop                           | Built-in       | ~120   |
| schedule                       | Built-in       | ~130   |
| claude-api                     | Built-in       | ~360   |
| workflow-authoring             | Built-in       | ~80    |
| claude-in-chrome               | Built-in       | ~180   |
| init                           | Built-in       | ~20    |
| security-review                | Built-in       | ~30    |
| anthropic-skills:docs          | claude.ai sync | ~330   |
| anthropic-skills:docx          | claude.ai sync | ~350   |
| anthropic-skills:import-memory | claude.ai sync | ~60    |
| anthropic-skills:morning       | claude.ai sync | ~120   |
| anthropic-skills:pdf           | claude.ai sync | ~150   |
| anthropic-skills:pptx          | claude.ai sync | ~330   |
| anthropic-skills:skill-creator | claude.ai sync | ~120   |
| anthropic-skills:xlsx          | claude.ai sync | ~320   |

## MCP tools available (loaded on demand)

| Tool                                                    | Tokens |
|---------------------------------------------------------|--------|
| mcp__claude_ai_Claude_Docs__batch                       | 183    |
| mcp__claude_ai_Claude_Docs__create                      | 284    |
| mcp__claude_ai_Claude_Docs__delete                      | 381    |
| mcp__claude_ai_Claude_Docs__export                      | 360    |
| mcp__claude_ai_Claude_Docs__guide                       | 224    |
| mcp__claude_ai_Claude_Docs__query                       | 201    |
| mcp__claude_ai_Claude_Docs__read                        | 360    |
| mcp__claude_ai_Claude_Docs__update                      | 330    |
| mcp__claude_ai_Gmail__authenticate                      | 200    |
| mcp__claude_ai_Gmail__complete_authentication           | 263    |
| mcp__claude_ai_Google_Calendar__authenticate            | 209    |
| mcp__claude_ai_Google_Calendar__complete_authentication | 276    |
| mcp__claude_ai_Google_Drive__authenticate               | 205    |
| mcp__claude_ai_Google_Drive__complete_authentication    | 272    |
:: CONTEXT:END ::
