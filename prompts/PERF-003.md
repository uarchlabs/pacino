<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header 
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | PERF-003                |                          |
| Date         | 2026.11.18              |                          |
| Module       | perf                    | PF-11, PF-18, PF-22      |
| Run time     | 1h.25m.33s              |                          |
| Ctx %        | 82%                     |                          |
| Model        | claude-opus-5-5 low     |                          |
| Resume sha   | 482ebc09-d160-4ec5-9cc6-f6ae1dc48fc1 |             |
| PA session   | 086                     |                          |

Task:   [x] experiment  [x] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [x] verification
Mode:   [x] automated   [ ] manual          [ ] interactive
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview
Make the perf harness a measuring instrument (perf_decisions.md PF-11,
PF-18, PF-22). In order, each step accepted before the next starts:
1. The CPU cap: 75% of the hardware threads by default.
2. A conditional's resolution carries its taken target, not pc + 8.
3. The fetch rule, observed: computed beside the stream rule, it agrees
   on every branch outside the cases written here.
4. The fetch rule, driving: it decides mispredicts at resolve; pred_src
   from its record; the err_predict disagreements explained.
5. The FTB-slot oracle (PF-11).
6. The backend stages (decode, rename, dispatch, execute) and the sweep
   that sets the near-perfect default.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion 

## Claude.code Console Output

PERF-003 is done through Problem 8, with two items left for your ruling. Problems 0
  to 5 met their acceptance. Problem 6 ended the way the task provides: only (8, 8)
  meets the near-perfect default's rule, so no default was changed and the sweep table
  is the deliverable. tools/regress.sh passed: 287 targets, RESULT: PASS, 281 s.

  Problem: 0 baseline
  Result: Two Background facts are wrong: p4_params.sets uses --resolve-lat in 8
    sets, not 7, and the scan_traces comment is on line 128, not 127. The rebuilt
    baseline equals BP-150's after-fix rows exactly.
  ────────────────────────────────────────
  Problem: 1 CPU cap
  Result: The three tools, veneer and the perf Makefile default to 24 of 32 threads,
    and each prints the count it uses.
  ────────────────────────────────────────
  Problem: 2 resolution target
  Result: A conditional now resolves with its encoded taken target. err_cond_target
    is 0. Predecode redirects fall by up to 99.5%, which confirms the
    false-FTB-target hypothesis. err_predict fell to 0.
  ────────────────────────────────────────
  Problem: 3 fetch rule, observed
  Result: fr_disagree is 0 in all 35 runs. No case was added. Before the formal runs
    I fixed one harness defect: the verdict had been read at the take instead of the
    resolve cycle.
  ────────────────────────────────────────
  Problem: 4 fetch rule, driving
  Result: Now the default. Every hard check is 0. Under the old pc + 8 target, every
    err_predict disagreement had one cause: a predecode correction reaching the entry
    in or after the take cycle. So the hypothesis was wrong as worded. The take-time
    reading and err_predict are removed.
  ────────────────────────────────────────
  Problem: 5 oracle
  Result: Built by SV force with no RTL change; perf.vlt keeps six predictor modules
    out of inlining. In all 18 oracle runs every slot-held branch has 0 mispredicts,
    apart from the trap-after-branch cases you told me to count apart (0 to 8 per
    run). The oracle-off cycles minus the oracle cycles are reported per trace (what
    prediction costs).
  ────────────────────────────────────────
  Problem: 6 stages and sweep
  Result: The four stage parameters are built and accepted, and --resolve-lat is
    removed. In the 486-run sweep, return mispredicts do not settle on 5 of 6 traces.
    The default stays immediate.

  Rulings needed:
  1. The near-perfect default. media_2's return mispredicts drop to about 90–140 in the
     middle of the grid, then climb back to about 600 at execute latency 7–8.
     compress_1, infra_1 and int_6 rise with resolve-to-commit. web_11 moves by about
     3,000 with no trend. So TD#207 is not just a "commit too fast" effect.
  2. A trap right after a branch. Under both rules it still counts as that branch's
     mispredict. The other option is to judge the branch on its own outcome and treat
     the trap as a separate RC_TRAP redirect, as for non-branches.

  Where I departed from the task:
  - I fixed one more harness defect: the path's last branch had been judged, adding one
    mispredict on compress_1.
  - I deleted the first Problem 4 CSV and reran it on the final build.
  - I wrote the Problem 6 code before Problem 5 was finished. Problem 5's final runs
    used that build, and the oracle-off counts are unchanged by it.
  - The Grep tool wasn't available, so I searched with grep -n and also used
    tail/awk/head on scratch logs, against CLAUDE.md.
  - I grepped bp_structs_pkg.sv, bp_defines_pkg.sv and rtl/Vars.mk, which are outside
    the manifest, and read extra parts of PERF-002.md.

  Results Capture in prompts/PERF-003.md also proposes the text for PF-11, PF-18, PF-21
  and PF-22. I also saved a memory note on the Verilator force behaviors found here.

## My Assessment

Rulings:

1: Keep the immediate backend as the default for now, and look into TD#207 first.
2: The other option is to judge the branch on its own outcome and treat
   the trap as a separate RC_TRAP redirect, as for non-branches.

## Claude.ai Assessment

## Verdict

**Accept.** Problems 0 to 5 meet their acceptance as written. Problem 6
stopped the way the task provides: the stages are built and checked,
the sweep ran, and no point but (8, 8) meets the default rule, so no
default was set. The regression passed: 287 targets, RESULT: PASS,
281 s.

The harness is now a measuring instrument:

- the fetch rule is the default;
- the stream is kept as a check;
- the oracle gives a cycle ceiling;
- every hard check is 0 in every run.

I checked the arithmetic I could check from the tables:

- the oracle sums: mispredicts equal misses plus traps for compress_1,
  infra_1 and web_11 immediate;
- the Problem 2 percentages: pd_redirects -99.5% on fp_1, cycles -6.98%
  on int_6, MPKI -1.07% on web_11;
- the IPCs;
- the C3 arithmetic (6913 to 6912, which equals 3.4560 x 2000).

All of them hold.

Two rulings are already in My Assessment:

1. Keep the immediate backend as the default, and look into TD#207
   first.
2. Judge a branch followed by a trap on its own outcome, with the trap
   as a separate RC_TRAP redirect.

Both need recording. Ruling 2 also needs building.

**Before pushing:** the regress pass was NOT recorded ("tracked changes
... push will be refused"), because the run was on a dirty tree. After
you commit, run tools/regress.sh once more on the clean tree, or the
push will be refused.

## What the results establish

**The pc + 8 target was a real training defect, and a large one.**

- Predecode redirects fall from 120,121 to 598 on fp_1 and from 103,730
  to 1,658 on int_6.
- Cycles fall by up to 7.0%.
- MPKI hardly moves (at most 1.1%). The false targets were mostly
  repaired by predecode (M3) before the backend saw them, so they cost
  cycles, not mispredicts.
- p2_overrides rose on fp_1 (28,266 to 42,394, immediate). The FTB now
  holds correct targets that the uBTB at p1 disagrees with. This is not
  a defect, but it is worth knowing when reading p2 numbers from before
  and after the fix.

**err_predict is explained, and it was a side effect of the same
defect.**

- Every disagreement in PERF-002's counts was a predecode correction
  landing on the entry in or after the take cycle.
- The IA showed this on a temporary pc + 8 build. Its err_predict equals
  Problem 0's in all 12 runs, every case is classed as "pd", and none
  are left over.
- With the target fixed, the remaining corrections are M1 JAL
  corrections, which give the same verdict. That is why err_predict is
  0.
- My hypothesis said the slots change between request and take. They
  change between take and correction. It was wrong as worded, and the IA
  said so.

**The fetch rule agrees with the stream exactly.**

- fr_disagree is 0 in 35 runs (12 p5 and 23 p4_params), with no case
  added. Even the C1 (slot-decided) branches agree, 0 disagreements.
- The IA found one defect in its own build before the formal runs: the
  verdict was read at the take, not at resolve. That was a departure
  from the ruling, which says resolve cycle. It was fixed before the
  observe runs, and no case was added to hide it.
- Four hard checks the task didn't ask for are welcome: err_fetch_port,
  err_record_moved, the correction-without-record part of err_no_record,
  and fr_beyond_taken.

**Dropping the stream rule's wait saves 2,612 to 150,154 cycles in 10
of 12 runs.** That is roughly 7% on web_11 immediate. The stream rule's
own measurement was inflating cycles. The two runs where the fetch rule
is longer (int_6 latency +688, media_2 latency +221) come from
different redirect timing, so the predictors see different streams.
That is not a defect.

**The oracle works, and it puts a number on what prediction costs.**

- Slot-held branches have 0 mispredicts, apart from the trap cases.
- Direct misses are 0 (predecode corrects every JAL).
- Every missed return mispredicts.
- The largest cost is fp_1 latency: 503,021 cycles (IPC 1.70 against
  2.97).
- The oracle's ceiling still includes two things, by the ruling that
  slot presence stays the predictors' own:
  - FTB misses (web_11: 67,057 conditional misses);
  - p2 overrides from uBTB slot-presence differences (infra_1: 110,310).
- The ceiling is a "perfect direction and target" ceiling, not a
  perfect front end. PF-11 should say this in so many words.

## The sweep: TD#207 is probably an RTL defect, not a backend effect

This is the most important finding of the task. The near-perfect
default rested on the idea that return mispredicts settle once the
backend is slow enough to avoid a race. The sweep says they don't:

- **media_2:** returns go from 4,815 at (0, 0) to 84 at (5, 5), then
  back up to about 600 on the S = 7 and 8 rows. That is a 57x swing in
  return mispredicts from backend timing alone.
- **compress_1, infra_1, int_6:** returns rise steadily with
  resolve-to-commit C at fixed S (infra_1 at S 0: 14,707 to 20,044).
- **Against the oracle:** infra_1 has 2,533 return misses under the
  oracle, so roughly 12,000 of its returns at immediate are slot-held
  returns that the RAS mispredicts. Its RAS MPKI is 5.99 at immediate.

A correct RAS on CBP-style code mispredicts returns mostly on overflow
and on deep recursion. It does not vary by 57x with commit latency.
There seem to be two mechanisms:

- (a) **Returns get worse as commit lags.** This fits a recovery that
  restores from, or is limited by, committed-stack state that trails
  speculation.
- (b) **media_2's dip and rise depend on the order of resolve, redirect
  and commit within a few cycles.** This fits a same-cycle ordering
  defect in the speculative RAS repair (the snapshot restore against the
  commit pop or push).

Neither is the harness's: the oracle forced the RAS and returns went to
misses-only.

**Recommendation.** BP-151, a debug task on TD#207:

- **The traces.** media_2 at (0, 0) and at (5, 5), and infra_1 at C 0
  and C 8.
- **What to log.** Per return PC: mispredict count, the RAS top at
  predict, the repair source on each redirect, and the commit stack at
  repair.
- **The cause.** Locate it and reproduce it in a tb_fe_top program.
  The program must fail on the current RTL, as BP-150 did with
  sc_nored.
- **The fix, if it keeps the rules.** Then rerun the sweep. The
  near-perfect default question is only meaningful after that.

Until then, every MPKI the harness reports carries an RAS term that
depends on timing. Studies should name their backend, and results
should not be compared across backends.

## Process notes on the IA

None of these block acceptance. I'll note them in the recording.

- **THE ORDER.** The IA wrote Problem 6's stage code while still
  debugging Problem 5. The task says "No later step is built ahead". It
  disclosed this and showed the oracle-off counts unchanged, so the
  effect is nil, but it is a departure.
- **Tool and file rules.** The IA used tail, awk, head and cut on
  scratch logs, and mv, rm, mkdir and rsync for files. All of it was
  disclosed. It deleted an acceptance CSV (perf003_p4_fetch.csv) after
  the C3 fix and reran it. That is disclosed, but a replaced result
  should be kept beside its rerun, not deleted.
- **The effort level.** The run used opus-5-5 at low effort and reached
  82% of context. It did not compact, but there is little room left for
  a bigger task at that setting.
- **The memory note.** The Verilator force findings went into the IA's
  memory file:
  - forces through inlined ports are circular;
  - a released variable keeps its forced value;
  - force inside always_comb does nothing;
  - only one member force per struct element applies;
  - a comment starting with that word is read as a pragma.

  Anyone who touches perf_top.sv needs them, so they belong in the repo
  as well. I'll put them in PF-11, and the README should carry them.

## PA errors

Two Background facts were wrong:

- p4_params.sets uses --resolve-lat in eight sets, not seven;
- the scan_traces.py comment is on line 128, not 127.

Both are small, and both are mine. I'll record them.

## Defect found in the review: the build's sha can be stale

The IA found that head_s2 carried sha 2fe4b61 at 7c61093. make saw the
binary as newer than its sources and did nothing.

perf/Makefile:104-116 compiles the sha in with -DPERF_SRC_SHA, but the
binary does not depend on it. So:

- a commit that changes no source leaves the old sha on every new row;
- a dirty tree is not marked.

The CSV's sha column is the measurement's provenance (PF-9), so this
matters. Proposed TD#210:

- the build writes the sha, with a "-dirty" mark, to a stamp file;
- the binary depends on the stamp, and the stamp is rewritten only when
  the value changes.

## Recording (PA, next)

**perf_decisions.md:**

- **PF-11, PF-18, PF-21 and PF-22:** the IA's proposed text, with these
  changes:
  - PF-11 adds what the ceiling includes (FTB misses, p2 slot-presence
    overrides) and the Verilator findings.
  - PF-11 and PF-18 change the trap-after-branch text from OPEN to
    RULED: "judge the branch on its own outcome; the trap is a separate
    RC_TRAP redirect, as for a non-branch". It is to be built by
    PERF-004. orc_slot_trap goes when it is built.
  - PF-18's near-perfect default becomes: "RULED session-086 (Jeff):
    the default stays immediate; TD#207 is investigated first", with the
    sweep's result.
- **History:** a 2026-11-18 entry.

**PROJECT_STATUS.md:**

- A PERF-003 recorded entry, with the two PA errors and the process
  notes.
- **TD#207:** updated with the sweep, reclassified as a likely RTL
  defect in the RAS repair, with BP-151 as the next task.
- **TD#208:** stays open. mis_sc moves both ways after the target fix
  (infra_1 +147, fp_1 -254). Look at it after TD#207, because an RAS
  defect changes the global history that SC and TAGE see.
- **TD#210:** opened, the stale build sha.
- **Module Status:** the perf harness row gets the fetch rule as the
  default, the oracle, the stages, the cap, and the immediate default.
- **Next free numbers:** PERF-004 stays the next PERF number, and
  BP-151 is to be written.

**PERF-004 scope** (after BP-151):

- the trap-after-branch ruling;
- TD#210;
- the no_inline speed measured on an idle machine;
- the full CBP rerun under the fetch rule (perf_rerun.py --plan full);
- the TD#202 study.

**Order:** record PERF-003, then BP-151 (TD#207), then the sweep again,
then PERF-004.

## Follow-on Actions
Nothing required

## CLAUDE.md Updates
Nothing required

## Other Planning File Updates
Nothing required

:: DISCUSSION:END ::

=============================================================
:: PROMPT:START ::
=============================================================

## Task ID
PERF-003

## Context Loaded
@planning/perf/perf_decisions.md
@rtl/CLAUDE.md
@perf/src/harness/perf_fe.cc
@perf/src/harness/supply.h
@perf/src/harness/supply.cc
@perf/sv/perf_top.sv
@rtl/core/frontend/ftq/rtl/ftq_ifu.sv
@planning/interfaces/ftq_backend_interfaces.md

## Context Comments
perf_decisions.md is the specification, as of session-086 after
PERF-002 (PF-11 the FTB-slot oracle, PF-18 the rulings for PERF-003,
PF-22 the CPU cap). perf_fe.cc, supply.* and perf_top.sv are the
harness PERF-002 built. ftq_ifu.sv forms the fetch request the fetch
rule records (267-288) and writes the predecode correction (about
466-512). ftq_backend_interfaces.md section 4 is the resolution the
harness sends.

The IA may read, read only, the parts the work needs of:
- every other file under perf/, and tools/perf_study.py,
  tools/perf_rerun.py, tools/perf_traces.py, tools/scan_traces.py;
- README.md, section Performance analysis (it changes, Problem 7);
- rtl/core/frontend/bpu/rtl/bp_cluster.sv, for the oracle's force
  points (p1_form_comb at about 791, p2_succ_comb about 1129,
  p2_slot_comb about 1264, p3_redir_comb about 1312, p3_slot_comb
  about 1364) and the predictor outputs they read;
- the RTL under rtl/core/frontend/ftq/rtl, rtl/core/frontend/ifu/rtl
  and rtl/core/frontend/fe_top/rtl, for the signals the wrapper brings
  out;
- rtl/core/frontend/fe_top/tb/models/fe_tb_backend.svh (br_target,
  36-58);
- planning/arch/ftb_decisions.md section 5.5,
  planning/interfaces/ftq_ifu_interfaces.md sections 4 and 7, and
  planning/interfaces/ftq_bpu_interfaces.md section 6;
- prompts/PERF-002.md's Results Capture (Deferred Work 7, Other
  Notes 2) and prompts/BP-150.md's Results Capture;
- the changed traces under CBP_TRACES_RV (PF-15).

## Hypothesis
The pc + 8 target trains false FTB targets, and fixing it changes
the MPKI. A record of the prediction fetch used, taken at each
accepted fetch request and at each predecode correction, gives the
same mispredict verdict as the fetched stream on every branch the
stream decides, outside the cases written here. err_predict is the
take-time slot reading disagreeing with that record, because the
entry's slots change between the request and the take. The oracle can
be forced inside bp_cluster by hierarchical reference, with no RTL
file changed. Return mispredicts stop changing at small backend
latencies.

## Background
Checked by the PA against the tree at 7c61093. The IA confirms each
fact it uses.
- THE NOT-TAKEN TARGET. perf_fe.cc:631-634 sends a conditional's
  resolution target as its traced target when taken and pc + 8 when
  not taken. ftb_decisions.md 5.5 (about line 868) and
  fe_tb_backend.svh:44-58 (BP-121): a conditional's resolution
  carries its RESOLVED TAKEN TARGET whatever its direction.
  ftq_resolve.sv:617 writes the resolution's target into the FTB
  update. supply.cc:61 encodes a conditional never seen taken with
  target pc + 8 (pc + 4 is not allowed, PF-15), and supply.h:37 gives
  Inst.target as pc + 4 when not taken. So pc + 8 is right only for a
  conditional never taken in the trace prefix loaded.
- THE STREAM RULE (perf_fe.cc:28-39, 532-554, 832-878). A branch
  mispredicts when the next slot fetch delivers is not the trace's
  next PC: the next slot of its bundle, or, when the branch ended its
  bundle, the next slot taken, which it waits for (pend, decide()).
  With the FTQ full or the ibuf empty for EAGER_IDLE (32) cycles, the
  slot reading decides a waiting branch (596-604, decided_by_slot).
  A path mismatch after a branch not yet resolved flips it to
  mispredicted (751-759).
- THE SLOT READING (err_predict). perf_top.sv:339-349 reads pq_* from
  dut.u_ftq.u_entry.r_arr at the entry named by each ibuf slot, in the
  take cycle: the entry as it is then, not the prediction fetch used.
  perf_fe.cc:836-860 makes r.recon from it, and pred_src (r.src) comes
  from the same read. err_predict counts r.recon against the stream
  verdict (538, 752, 873): 202 to 9,463 per 2e6 run (PERF-002).
  perf_fe.cc:854-855 makes a direct jump or call never mispredicted by
  the reading.
- THE FETCH REQUEST (ftq_ifu.sv:267-288): ftq_ifu_req_val, _req_rdy,
  ftq_ifu_idx, _start_pc, _next_pc, _taken_val, _taken_pos, from
  fetch_entry; taken_val and taken_pos name the lowest valid taken
  slot, next_pc its target, else pft_addr. fe_top.sv:326-332 declares
  them. ftq_entry.sv:239-242: the fetch read port writes through the
  same-cycle p3 slot write (BP-150).
- THE PREDECODE CORRECTION: ifu_ftq_pdwb_val, _pdwb_idx,
  ifu_ftq_mis_val, _mis_pos, ifu_ftq_target (fe_top.sv:337-346);
  ftq_ifu.sv about 466-512 forms the corrected slot (w_new_slot), the
  entry's corrected slots (w_corr_slot) and successor (w_corr_succ).
- PERF-002 DEFERRED WORK 7, STEP 0 (b) IS ANSWERED BY BP-150: in 12
  runs of 2e6 instructions no p2 or p3 redirect found its entry
  already fetched (p2redir_iss, p3redir_iss 0), and no p2 slot write
  reached an entry already fetched; a p3 correction without a redirect
  reaches the request of its own cycle. Step 0 (a), when the
  predecode correction's fields are valid and what ifu_ftq_target
  means, is not answered.
- THE BACKEND (perf_fe.cc:124-140, 354-364, 824-829): --resolve-lat,
  --resolve-commit, --take-rate, --window; one random stream per
  parameter, seeded from --seed. A branch resolves at take + drawn
  latency.
- THE STUDY SETS. perf/studies/p5.sets: immediate, and latency
  (--resolve-lat uniform:4:12 --resolve-commit uniform:2:8 --seed 1),
  2e6 instructions. perf/studies/p4_params.sets uses --resolve-lat in
  seven sets.
- THE BUILD. perf/build/head_s2 was built at 2fe4b61, before BP-150.
- -j. tools/perf_study.py:63, tools/perf_rerun.py:125 and
  tools/perf_traces.py:66 default -j to os.cpu_count();
  perf_traces.py:77 passes it to a subcommand.
- tools/scan_traces.py:127, a comment: "The translation modes PF-16
  checks". PF-16 is removed; the counts are in PF-15.
- TD#207: return mispredicts depend on how soon the backend commits
  (media_2, 723 at immediate, 21 at resolve to commit 8). TD#208: MPKI
  and mis_sc rise on some traces after BP-150, to be looked at after
  the not-taken target is fixed.

## Binding Previous Decisions
Jeff, session-084 to session-086, as recorded in perf_decisions.md and
in this task.

- THE SPECIFICATION is perf_decisions.md. Where this task and the
  document differ, the document wins and the IA reports the
  difference.
- NO TOLERANCE (Jeff, session-086). Every comparison here is exact. No
  acceptance uses a percentage, a band or "within noise". A difference
  is a case written here, or a defect to explain.
- THE ORDER. Problems 1 to 6 run in order. A step that fails its
  acceptance stops the task there: the IA reports what failed, its
  evidence and the change it would need, and does not start the later
  steps. No later step is built ahead to work around an earlier one.
- THE RESOLUTION TARGET (ftb_decisions.md 5.5). A conditional's
  resolution carries its taken target, whatever its direction: the
  target encoded in the code image's B-type word at its PC (the
  stub's address for a veneered branch, PF-15), decoded as
  fe_tb_backend.svh's br_target does. Every other type keeps its
  traced target.
- THE FETCH RULE (PF-18), as ruled:
  - THE RECORD. A table by FTQ index, written at each accepted fetch
    request (ftq_ifu_req_val and ftq_ifu_req_rdy): start_pc,
    taken_val, taken_pos, next_pc, and the entry's slots as the fetch
    read port gives them in that cycle (slot_valid, pos, br_type,
    taken, target, pred_src). A later request for the same index
    overwrites it. A predecode correction of that entry updates it as
    the FTQ updates the entry (ftq_ifu.sv w_corr_slot, w_corr_succ).
  - THE VERDICT. A branch at position p of entry E predicts:
    taken to E.next_pc when E.taken_val and E.taken_pos is p; not
    taken (pc + 4) when p is below E.taken_pos or E.taken_val is
    clear and the branch is not the block's last instruction; E.next_pc
    when it is the block's last instruction. It mispredicts when that
    differs from the trace's next PC. The verdict is decided in the
    branch's resolve cycle, with no wait.
  - pred_src is the pred_src of the record's slot at p; PRED_NONE when
    no slot of the record is at p.
  - THE TWO STEPS. (1) Observe: the stream rule drives the redirects,
    and the fetch rule's verdict, computed beside it, agrees on every
    branch the stream decides (THE CASES below). (2) Drive: the fetch
    rule drives the redirects and its MPKI is the measurement. It is
    not compared with the stream rule's MPKI.
  - A run parameter --mispredict-rule stream|fetch selects the rule;
    after Problem 4 is accepted the default is fetch. The CSV gains a
    mispredict_rule column.
- THE CASES. The fetch and stream verdicts may differ only where the
  stream rule has no stream verdict of its own, or the trace and the
  code image disagree:
  C1  a branch decided by the slot reading (decided_by_slot): the
      stream rule's verdict there is the reading, not the stream.
      Counted, agree and disagree, apart; not in the exact comparison.
  C2  a branch at a class-conflict PC, or the branch before one
      (supply.h conflict()): the image holds another class (PF-15).
      Counted apart.
  C3  the path's last branch, with no next instruction. Excluded.
  Before the observe runs (Problem 3, step 3a) the IA reads the RTL
  and the harness and adds any further case in which the two verdicts
  may differ for a stated reason, each with its rule. A case is not
  added after the runs. Every other disagreement is a harness or RTL
  defect: located, and fixed if within AUTHORITY, otherwise reported.
- THE ORACLE (PF-11). The wrapper forces, by SV force by hierarchical
  reference inside bp_cluster, each slot's direction and target to the
  trace's, at the predictor outputs the stage logic reads, so that the
  successors and the p2 and p3 redirects bp_cluster computes come from
  the forced values. Slot presence stays the predictors' own: a
  branch with no slot is a miss, counted on its own by class. The
  values come from the C++, which follows the predicted path from the
  trace: an entry allocated on the path is forced; an entry allocated
  off it is not, and is counted. No file under rtl/ changes. A run
  parameter --oracle selects it; the CSV gains an oracle column.
- THE BACKEND STAGES (PF-18). Resolve latency is the sum of four
  parameters, --decode-lat, --rename-lat, --dispatch-lat and
  --execute-lat, each a distribution as now, each its own random
  stream from the seed; --resolve-commit stays. --resolve-lat is
  removed, and the study sets that use it move to --execute-lat with
  the same distribution. The CSV's resolve_lat column becomes the
  four.
- THE NEAR-PERFECT DEFAULT (PF-18): the smallest stage and commit
  values beyond which return mispredicts stop changing, found by the
  sweep of Problem 6. "Stop changing" is exact: mispred_return equal at
  every larger grid point. With fixed values only the stage sum
  matters, so the sweep varies execute and the default puts the sum in
  --execute-lat, the other three 0.
- THE CPU CAP (PF-22): the perf tools default -j to 75% of the
  hardware threads, rounded down, at least 1; -j sets fewer or more.
- MEASUREMENT AND RESULTS (PF-6, PF-9) as PERF-002 built them. A
  performance run gates no push: nothing joins tools/regress.sh.
- AUTHORITY. The IA may change and create files under perf/, change
  tools/perf_study.py, tools/perf_rerun.py and tools/perf_traces.py,
  change the comment at tools/scan_traces.py:127, and change the
  README.md Performance analysis section. It changes no file under
  rtl/, examples/ or planning/, and nothing in tools/cbp2025. It does
  not stop to ask permission for a change within this authority.

## Specific Requirements

Problem 0: the baseline
- Report each Background fact found false, with what the files say.
- Rebuild perf/build/head_s2 at the current tree. Rerun
  perf/studies/p5.sets on its six traces (12 runs) as they are: the
  stream rule, pc + 8. This is the baseline for Problem 2. Report it
  beside PERF-002's p5_checks.csv and BP-150's after-fix runs.
- Do not run a baseline regress.sh: BP-150's run (287 targets, RESULT:
  PASS) is the baseline.

Problem 1: the CPU cap
Apply THE CPU CAP to the three tools. perf_traces.py's subcommand gets
the same default.
Acceptance: each tool's --help shows the default; a run without -j
reports the worker count it uses; -j N uses N.

Problem 2: the resolution target
Apply THE RESOLUTION TARGET.
- A hard check: for a TAKEN conditional, the decoded image target
  equals the trace's target, except at a class-conflict PC; a
  difference is counted (err_cond_target) and fails the run.
Acceptance:
- p5.sets rerun (12 runs): status ok, every hard err_* 0,
  err_cond_target 0.
- Before (Problem 0) and after, per run: MPKI, mispred_cond, mis_sc,
  mis_tage, mis_ftb, pd_redirects, p2_overrides, p3_overrides, cycles.
  No expected value; the numbers are reported.
- tb_fe_top is not run: no RTL changes.

Problem 3: the fetch rule, observed
3a. Before any run:
- Settle PERF-002 Deferred Work 7 Step 0 (a) from the RTL, and from a
  --log run if needed: when ifu_ftq_mis_val, _mis_pos and
  ifu_ftq_target are valid relative to ifu_ftq_pdwb_val, and what the
  record must take from the correction.
- Write the added cases (THE CASES), each with its reason and rule,
  in Results Capture, or state that there are none.
3b. Build THE RECORD and THE VERDICT beside the stream rule. The
wrapper brings out the request, the fetch read port's slots in the
request cycle, and the predecode correction, by hierarchical
reference, as the existing obs_* and pq_* ports are. Hard checks:
- a slot taken whose FTQ index has no record, or whose PC is not in
  the record's block (from start_pc), is counted (err_no_record) and
  fails the run;
- a p2 or p3 slot write to an entry after its request was accepted,
  other than the same-cycle p3 write the fetch port carries (BP-150),
  is counted (err_late_write) and fails the run.
New columns: the fetch verdict's mispredict count, and the agree and
disagree counts per case and for the rest (fr_disagree, which must be
0).
Acceptance:
- p5.sets (12 runs) and p4_params.sets on the traces PERF-002 ran it
  on: status ok; every hard err_* 0; fr_disagree 0 in every run.
- The counts per case, per run.
- Under the stream rule the redirects and every count are as Problem 2
  gave them: the record observes only. Show it for the 12 p5 runs.
If fr_disagree is not 0 in a run, the task stops here (THE ORDER),
with each disagreement located.

Problem 4: the fetch rule, driving
- --mispredict-rule fetch: the verdict decides at resolve and drives
  the redirect; the pend and decided_by_slot fallback are not used.
- pred_src from the record.
- The fetched stream stays a check: a path instruction that is not the
  trace's next PC after a branch the fetch rule judged correct is
  err_stream, a hard check under fetch. A branch the fetch rule judged
  mispredicted whose next slot fetch delivered before the redirect and
  equals the trace's next PC is err_fetch_rule, a hard check.
- err_predict: for each disagreement of the take-time slot reading
  with the record, its cause, from comparing the slot as read at take
  with the record; counted by cause. A disagreement without a cause is
  a defect. Then the take-time reading (pq_*) is removed from the
  harness and from the CSV, and err_predict with it.
- Default --mispredict-rule fetch.
Acceptance:
- p5.sets (12 runs) under fetch: status ok; every hard err_* 0;
  resolve_wait_sum 0; decided_by_slot 0; Instr and NumBr equal the
  reader's prefix counts.
- MPKI, per-predictor MPKI and cycles per run, under fetch; cycles
  beside the observe run's (the wait the stream rule added).
- err_predict's causes and counts, per run, from the observe runs.
- p4_params.sets under fetch: every parameter still moves its count;
  min = max gives the same row on two seeds; 0/0 resolves in the take
  cycle.

Problem 5: the oracle
Apply THE ORACLE. Before building, name the force points in
bp_cluster and the signals forced, with lines, in Results Capture. If
the oracle cannot be built by force without an RTL change, say what it
needs and stop (THE ORDER); do not report it passed.
New columns: the oracle's forced entries, entries off the path (not
forced), and the misses by class (conditional, direct, indirect,
return) with the mispredicts among them.
Acceptance, on the six p5 traces, 2e6 instructions, under fetch:
- immediate and latency (12 runs): status ok; every hard err_* 0;
  ZERO mispredicts on branches the record held in a slot; the misses
  and their mispredicts reported, expected non-zero; p2_overrides and
  p3_overrides reported.
- the cycles of each oracle run beside the same run without the
  oracle (Problem 4): the difference is what prediction costs.
- immediate with --icache perfect, with and without the oracle (12
  runs): the ceiling without I-cache misses.

Problem 6: the backend stages and the near-perfect default
- Apply THE BACKEND STAGES. Move the study sets.
Acceptance, the stages: each of the four parameters at two values
moves resolve_lat_sum by the expected amount (one run each); fixed
values in two stages give the same row as their sum in one;
min = max is seed independent; all four 0 resolves in the take cycle.
- THE SWEEP: fixed execute latency S in 0..8 and resolve to commit C
  in 0..8, the other stages 0, take rate fixed:8, no window, real
  I-cache, under fetch, the six p5 traces, 2e6 instructions: 486 runs.
  Report mispred_return, and MPKI, per trace at every (S, C), as a
  table per trace, in a CSV in perf/studies/.
- THE DEFAULT: the grid point with the smallest S + C (then the
  smaller S) at which every trace's mispred_return equals its value at
  every grid point with S' >= S and C' >= C. Set it as the harness
  default and in the README.
- If no point other than (8, 8) meets that rule, or return mispredicts
  do not settle, change no default: report the table and stop, for a
  ruling. The table is the deliverable then.
- Report what the sweep shows of TD#207 (return mispredicts against
  C at S fixed, and against S at C fixed). TD#207 is not fixed here.

Problem 7: what is found
- README.md, Performance analysis: the CPU cap, --mispredict-rule,
  --oracle, the four stage parameters (and --resolve-lat removed), the
  new columns and the removed ones, the default backend.
- tools/scan_traces.py:127 names PF-15, not PF-16.
- Any other defect found: fixed if within AUTHORITY, otherwise
  reported with the change it needs.

Problem 8: the regression
- tools/regress.sh runs once at the end, in the background. Report its
  summary whole and its time.

## Constraints
- The planning files are read only. Results Capture proposes the exact
  text, but only for the planning files in Context Loaded. The PA
  updates the others.
- The IA runs no git command. Running tools/regress.sh, which makes git
  calls of its own, is permitted; that grant is to run the script, not
  any command it contains. The same holds for the perf build's own
  read-only git call that records a revision's sha.
- tools/regress.sh runs once, at the end, in the background. The IA
  waits for it to finish, and no file changes while it runs. Its
  summary goes into Results Capture whole, sha line included, not cut
  by a pipe.
- tools/regress_demo.sh is not run (fe_demo_tb_decisions.md FDT-2a).
- COMMANDS (CLAUDE.md Commands, Experiment File Rules):
  - A Bash command names its files by literal paths. It uses no shell
    variable (no S=..., no $S, no $? and no ${PIPESTATUS[...]}), no
    $(...) or backticks, no loop and no xargs. The one exception is an
    environment setting on the command itself, such as
    CBP_TRACES_RV=...
  - No `&` and no `wait`: a long run uses the Bash tool's background
    mode and is waited for through it. No `echo` of a status and no
    `date` for timing: the tools report both.
  - Files are read and searched with the Read, Grep and Glob tools.
    If the Grep tool is not available in the session, `grep -n` with
    literal paths through Bash is allowed; say so in Results Capture.
    No sed, cat, head or tail to read files.
  - Files are created and changed with the Write and Edit tools. No
    sed -i, no heredoc, no redirect, except that a build or run log
    may be redirected to a file in the scratchpad.
  - Every command runs from the repo root: no cd, except a subshell
    ( cd <dir> && ... ) where a tool must run in another directory.
  - A scratch build of the tree sets RVA_ROOT to the copy, and copies
    sources only, not build output.
- Studies use the tools' default -j once Problem 1 is built, and at
  most 24 before it. Long runs run in the background and are waited
  for. No file a run reads changes while it runs.
- Every result row records the sha the build reports. The tree has
  uncommitted perf/ changes while the task runs; Results Capture says
  so beside the sha.
- The training traces under CBP_TRACES and the changed traces under
  CBP_TRACES_RV are not written.

## Deliverables
Note: If a new module is to be created ensure that claude.code is allowed
or told to modify the Makefile for lint checking at the minimum.

Files the IA may change:
- files under perf/ (the wrapper, the C++, the Makefile, perf.vlt,
  study sets and CSVs);
- tools/perf_study.py, tools/perf_rerun.py, tools/perf_traces.py;
- tools/scan_traces.py, the comment at line 127 only;
- README.md, section Performance analysis;
- prompts/PERF-003.md, Results Capture filled in below.

Results Capture reports:
- Problem 0: the false facts; the baseline runs beside PERF-002's and
  BP-150's.
- Problem 1: the tools' defaults and the demonstration.
- Problem 2: the change by file and line; before and after per run.
- Problem 3: Step 0 (a); the added cases; the signals brought out and
  from where; the counts per case per run; fr_disagree.
- Problem 4: the drive runs; err_predict's causes and counts; the
  p4_params checks.
- Problem 5: the force points; the oracle runs, the misses, and the
  cycles against the design's.
- Problem 6: the stage checks; the sweep table and CSV; the default
  set, or the stop and the table.
- Problem 7: every change by file and line.
- Problem 8: the regress.sh summary, whole, and its time.
- The text proposed for perf_decisions.md: PF-11 (the oracle as
  built), PF-18 (the stages, the default, the fetch rule as built),
  PF-21 (what PERF-003 built) and PF-22 (built).

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary
Problems 0 to 8 ran in order. Problems 0 to 5 met their acceptance.
Problem 6 stopped as the task provides: the stages are built and
accepted, the sweep ran (486 runs), and ONLY (8, 8) meets THE DEFAULT's
rule, so no default was changed. The table is the deliverable, and the
default awaits a ruling. The regression passed (287 targets, RESULT:
PASS, 281 s). Status for the PA: the task's own outcome for Problem 6
is "report the table and stop, for a ruling", and that is where it
stands.
1. CPU cap (PF-22): perf_study.py, perf_rerun.py, perf_traces.py (and
   its veneer), and the perf Makefile default to 24 of 32 hardware
   threads.
2. Resolution target: a conditional resolves with the taken target its
   B-type word encodes. err_cond_target is 0. Predecode redirects fall
   by up to 99.5% (fp_1 120,121 -> 598), and err_predict falls to 0 in
   all 12 runs.
3. Fetch rule, observed: fr_disagree is 0 in all 12 p5 and all 23
   p4_params runs, with no case added, and the stream rule's counts are
   unchanged.
4. Fetch rule, driving, now the default: every hard check is 0,
   resolve_wait_sum 0, decided_by_slot 0. err_predict's cause: every
   disagreement (202 to 9,456 per run under PERF-002's pc + 8 target) is
   a predecode correction that reaches the entry in or after the take
   cycle; none come from a resolution write, and none are left without a
   cause. pq_* and err_predict are removed.
5. Oracle (PF-11), built by force with no RTL change (perf.vlt keeps six
   predictor modules out of inlining). In all 18 oracle runs every
   slot-held branch has 0 mispredicts, apart from 0 to 8 per run whose
   next trace record is an exception entry. Jeff ruled in the session to
   count those apart (orc_slot_trap) and accept.
6. Stages built and accepted. In the sweep, return mispredicts do not
   settle on five of six traces; the default stays immediate.
SHA: every result row records 7c6109310fe4eafa202f51d4e4fe47488fb09e8d
(ftb512 rows: unversioned). While the runs ran, the tree had this task's
uncommitted perf/, tools/ and README.md changes.

## Test Matrix (testbench sessions only, omit otherwise)
Not a testbench session.

## What was delivered
- perf/src/harness/perf_fe.cc: the resolution target and
  err_cond_target; THE RECORD (FRec) and THE VERDICT (fr_verdict); the
  record's hard checks; --mispredict-rule fetch|stream (default fetch);
  err_stream and err_fetch_rule as hard checks under fetch; pred_src from
  the record; the take-time reading and err_predict removed; --oracle
  (OEnt alignment, o_succ, o_slot, the forced values, the miss counts);
  the four backend stages (--resolve-lat removed); the C3 fix.
- perf/sv/perf_top.sv: fr_*, pc_*, ew_* (the record), os_* and orc_*
  with the forces (the oracle); pq_* removed.
- perf/sv/perf.vlt: no_inline for loop_pred, ftb, tage, ittage, sc, ras.
- perf/src/harness/rv_encode.h: is_b_type, br_target.
- perf/src/harness/supply.h, supply.cc: set_keep (retired records kept
  readable).
- perf/src/perf_util.h, perf/src/veneer.cc, perf/Makefile, tools/
  perf_study.py, perf_rerun.py, perf_traces.py: the CPU cap;
  perf_traces.py --dry-run.
- perf/studies: p5.sets and p4_params.sets moved to --execute-lat; new
  perf003_*.sets and their CSVs; perf003_p6_sweep_table.csv.
- tools/scan_traces.py:128 PF-16 -> PF-15. README.md Performance
  analysis.

## Test Case Results

### Problem 0: the baseline

Background facts found false:
1. "perf/studies/p4_params.sets uses --resolve-lat in seven sets": it is
   eight (rlat_fixed8, rlat_unif, rlat_geom, rlat_table, unif_seed1,
   unif_seed2, fixed4_seed1, fixed4_seed2).
2. "tools/scan_traces.py:127, a comment": the comment is on line 128;
   line 127 is blank. It was changed at 128 (Problem 7).
Every other fact I used was confirmed against the files: perf_fe.cc
631-634, 28-39, 532-554, 596-604, 751-759, 836-860, 854-855, 124-140,
354-364, 824-829; perf_top.sv 339-349; supply.cc 61; supply.h 37;
fe_tb_backend.svh 36-58; ftb_decisions.md 5.5 (line 868);
ftq_resolve.sv 617; fe_top.sv 326-332 and 337-346; ftq_entry.sv
239-242; ftq_ifu.sv 267-288 and 412-525; the three tools' -j lines;
p5.sets.
THE BUILD: the binary carried sha 2fe4b61, as stated. But make -C perf
harness at 7c61093 found it newer than its sources and did nothing: it
had been built from the BP-150 tree before the commit. make -B rebuilt
it at 7c61093.

The baseline (perf/studies/perf003_p0_baseline.csv: 12 runs, status ok,
every hard err_* 0) equals BP-150's after-fix rows in every column
BP-150 reported:

| set | trace | mpki P002 | mpki BP-150 | mpki P0 | mis_sc P002 | mis_sc BP-150 | mis_sc P0 | cycles P002 | cycles BP-150 | cycles P0 | err_predict P0 | decided_by_slot P0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| immediate | compress_1 | 3.4960 | 3.4840 | 3.4840 | 515 | 506 | 506 | 697255 | 697206 | 697206 | 1734 | 275 |
| immediate | fp_1 | 16.5395 | 15.9660 | 15.9660 | 7059 | 5962 | 5962 | 994691 | 970578 | 970578 | 7512 | 3 |
| immediate | infra_1 | 17.0185 | 16.9755 | 16.9755 | 1915 | 1844 | 1844 | 1486871 | 1486304 | 1486304 | 6874 | 1870 |
| immediate | int_6 | 5.1660 | 5.1690 | 5.1690 | 393 | 394 | 394 | 694215 | 694048 | 694048 | 9456 | 8 |
| immediate | media_2 | 3.7850 | 3.7860 | 3.7860 | 130 | 133 | 133 | 506186 | 506286 | 506286 | 202 | 31 |
| immediate | web_11 | 29.3220 | 29.6925 | 29.6925 | 4891 | 4928 | 4928 | 2109737 | 2110328 | 2110328 | 1865 | 7269 |
| latency | compress_1 | 3.7760 | 3.8120 | 3.8120 | 504 | 549 | 549 | 747403 | 748235 | 748235 | 1490 | 196 |
| latency | fp_1 | 16.7945 | 16.6345 | 16.6345 | 6974 | 6325 | 6325 | 1239797 | 1236150 | 1236150 | 8038 | 2 |
| latency | infra_1 | 18.2470 | 18.2450 | 18.2450 | 2002 | 2030 | 2030 | 1725600 | 1726331 | 1726331 | 6045 | 1635 |
| latency | int_6 | 5.2230 | 5.2305 | 5.2305 | 433 | 454 | 454 | 748282 | 748343 | 748343 | 8021 | 6 |
| latency | media_2 | 1.7240 | 1.7220 | 1.7220 | 132 | 134 | 134 | 488265 | 488177 | 488177 | 198 | 25 |
| latency | web_11 | 29.2850 | 29.4630 | 29.4630 | 4909 | 5075 | 5075 | 2459418 | 2465290 | 2465290 | 1837 | 6745 |

### Problem 1: the CPU cap

The default is max(1, floor(0.75 x hardware threads)), which is 24 on
this 32-thread machine.
- tools/perf_study.py:57-72, perf_rerun.py:124-135 and
  perf_traces.py:67-79 each gain default_jobs(). Their --help reads
  "worker processes (default 24: 75% of the 32 hardware threads,
  PF-22)", and each prints the worker count it uses (perf_study.py "N
  processes (-j M)", perf_rerun.py:193, perf_traces.py:86).
- perf_traces.py passes the same N to its subcommand, perf/build/veneer
  -j N. veneer's own default (perf/src/perf_util.h:59-70 default_jobs,
  shared with trace_count) is the same, and veneer.cc:612 prints
  "veneer: N threads".
- perf/Makefile:39-41: JOBS (the Verilator build's -j) is 24.
- perf_traces.py gains --dry-run, which prints the worker count and the
  veneer command and writes nothing, so that the default could be shown
  without writing CBP_TRACES_RV.
Demonstration:
- perf_study.py without -j (3 runs, perf003_p1_demo.sets): "3 traces x
  1 sets = 3 runs, 3 processes (-j 24)"; with -j 2: "2 processes
  (-j 2)".
- perf_rerun.py --dry-run: "24 worker processes"; with -j 5: "5 worker
  processes".
- perf_traces.py --dry-run: "24 worker processes", and "would run:
  .../perf/build/veneer -j 24"; with -j 5: 5 and "-j 5".
- perf/build/veneer --only none/none_trace: "veneer: 24 threads"; with
  -j 3: "veneer: 3 threads". It then stops (no trace selected) and
  writes nothing.
- make -C perf --eval 'showjobs: ; @echo JOBS=$(JOBS)' showjobs prints
  JOBS=24; with JOBS=5 it prints 5.

### Problem 2: the resolution target

The change:
- rv_encode.h: is_b_type(w) and br_target(pc, w), which decode the
  B-type immediate as fe_tb_backend.svh's br_target does.
- perf_fe.cc, at the take: a conditional's resolution target (Ro
  rsv_tgt) is br_target(pc, the image word at pc), whatever its
  direction; for a veneered branch that is the stub. Every other class
  keeps its traced target. At a class-conflict PC the traced target is
  sent. The resolution port (it was lines 631-634) sends rsv_tgt.
- err_cond_target, a hard check: counts a taken conditional whose
  decoded target is not its traced target, and a conditional whose image
  word is not B-type, outside a class-conflict PC.
p5.sets rerun (perf003_p2_target.csv): 12 runs, status ok, every hard
err_* 0, err_cond_target 0, err_stream 0. err_predict, still built then,
is 0 in all 12.

Before (Problem 0) and after:

| set | trace | mpki | mispred_cond | mis_sc | mis_tage | mis_ftb | pd_redirects | p2_overrides | p3_overrides | cycles |
|---|---|---|---|---|---|---|---|---|---|---|
| immediate | compress_1 | 3.4840 -> 3.5125 | 4072 -> 4101 | 506 -> 529 | 629 -> 690 | 1835 -> 1776 | 51909 -> 31200 | 27063 -> 27380 | 1510 -> 1439 | 697206 -> 683700 |
| immediate | fp_1 | 15.9660 -> 15.9535 | 31904 -> 31879 | 5962 -> 5708 | 14782 -> 15318 | 9773 -> 9075 | 120121 -> 598 | 28266 -> 42394 | 9726 -> 11226 | 970578 -> 905596 |
| immediate | infra_1 | 16.9755 -> 17.0910 | 16637 -> 16598 | 1844 -> 1991 | 2288 -> 2464 | 8355 -> 8392 | 235599 -> 138307 | 187238 -> 180308 | 5053 -> 5557 | 1486304 -> 1436730 |
| immediate | int_6 | 5.1690 -> 5.1625 | 10248 -> 10230 | 394 -> 404 | 1065 -> 1071 | 8711 -> 8676 | 103730 -> 1658 | 4568 -> 3645 | 3914 -> 1457 | 694048 -> 645580 |
| immediate | media_2 | 3.7860 -> 3.7880 | 2711 -> 2715 | 133 -> 132 | 148 -> 152 | 2286 -> 2286 | 5677 -> 3283 | 3923 -> 3709 | 359 -> 233 | 506286 -> 504108 |
| immediate | web_11 | 29.6925 -> 29.3755 | 30275 -> 30299 | 4928 -> 4876 | 5166 -> 5260 | 9910 -> 9703 | 510198 -> 476042 | 97607 -> 98781 | 11725 -> 11958 | 2110328 -> 2086174 |
| latency | compress_1 | 3.8120 -> 3.8045 | 4333 -> 4248 | 549 -> 568 | 808 -> 823 | 1723 -> 1607 | 76245 -> 53590 | 31200 -> 31720 | 1806 -> 1730 | 748235 -> 739111 |
| latency | fp_1 | 16.6345 -> 16.7175 | 33241 -> 33407 | 6325 -> 6402 | 15112 -> 15929 | 10470 -> 9524 | 221707 -> 943 | 38476 -> 60171 | 11847 -> 17958 | 1236150 -> 1181631 |
| latency | infra_1 | 18.2450 -> 18.1470 | 17323 -> 17097 | 2030 -> 2077 | 2659 -> 2833 | 8619 -> 8159 | 339042 -> 240664 | 207058 -> 206555 | 6689 -> 7486 | 1726331 -> 1677851 |
| latency | int_6 | 5.2305 -> 5.2190 | 10314 -> 10287 | 454 -> 510 | 1119 -> 1222 | 8658 -> 8472 | 97417 -> 3967 | 5750 -> 4902 | 4842 -> 2004 | 748343 -> 698861 |
| latency | media_2 | 1.7220 -> 1.7225 | 2801 -> 2797 | 134 -> 130 | 223 -> 225 | 2268 -> 2268 | 8512 -> 5892 | 8367 -> 8412 | 271 -> 276 | 488177 -> 486739 |
| latency | web_11 | 29.4630 -> 29.4630 | 31098 -> 31106 | 5075 -> 5013 | 5580 -> 5695 | 8785 -> 8633 | 847447 -> 806109 | 122681 -> 123828 | 15477 -> 15906 | 2465290 -> 2448186 |

The hypothesis holds for the targets. With pc + 8, a not-taken
conditional wrote pc + 8 into its FTB entry. The next taken prediction of
that branch then went to pc + 8, and predecode (M3) corrected it. With
the fix, predecode redirects fall by up to 99.5% and cycles by up to 7.0%
(int_6 immediate). MPKI moves both ways, by up to 1.1% (web_11
immediate). TD#208: mis_sc moves both ways again (compress_1 +23 and
+19, infra_1 +147 and +47, int_6 +10 and +56; fp_1 -254, web_11 -52 and
-62). Not investigated here. tb_fe_top was not run.

### Problem 3: the fetch rule, observed

3a. STEP 0 (a), settled from the RTL (ifu_f3.sv 401-432, ifu_wb.sv
63-95, ftq_ifu.sv 412-557, ftq.sv 594-598):
- ifu_ftq_pdwb_val is high for one cycle: the cycle after the block's F3
  transfer to the ibuf.
- ifu_ftq_mis_val, _mis_pos and ifu_ftq_target are registered with it:
  ifu_wb loads them on wb_load and not flush. They are meaningful only in
  a cycle with pdwb_val; otherwise they hold the last writeback's values.
- ifu_ftq_target is the predecode target at mis_pos when mis_val, else
  at cfi_pos. The FTQ reads it only for a direct branch or a JAL
  (w_pd_has_target), never for a JALR.
- ifu_ftq_target is not the entry's corrected next PC. That is
  w_corr_succ, re-derived over the corrected slots.
- The FTQ applies the correction on pd_wr_val, which is pd_redir_val:
  wb_accept (the generation test), and mis_val, and not wb_rcvd (R3).
  pd_wr is not gated by the redirect arbitration (ftq.sv 594-598).
- What the record takes, on pd_wr_val for pd_wr_idx: the slots
  w_corr_slot; taken_val and taken_pos re-derived over them; and next_pc
  = w_corr_succ. These are brought out from ftq_ifu directly.
- A request presented in a flush cycle is discarded (ftq_ifu.sv
  341-348). The record is therefore written only on req_val and req_rdy
  and not flush_val.

THE CASES, written before the observe runs: none was added. The record
follows every write the FTQ makes to the slots fetch uses: the request
with the p3 write-through (BP-150) and the predecode correction. The IFU
truncates on the same taken_val/taken_pos and continues at the same
next_pc. M1 to M4 all correct through pd_wr. A trap after a branch makes
both rules compare against the same next record. So the two give the
same next PC, except in C1, C2 and C3.

THE VERDICT IS READ IN THE RESOLVE CYCLE. A short development run before
the observe runs (media_2, 2e5) gave 20 disagreements. All were direct
jumps and calls whose entry's M1 correction had not yet been applied.
The cause: the ibuf hands a block to the backend in its F3 transfer
cycle, and the writeback lands the cycle after, which is the resolve
cycle at latency 0. That build read the verdict at the take. Fixed as
the ruling says: a cycle's correction is applied to the record at the
start of that cycle (pd_wr_val and the corrected slots are formed from
registered state), and the verdict is read when the branch joins the
resolution queue. No case was added for this; the observe runs ran on
the fixed build.

3b. Signals brought out (perf_top.sv): fr_req_val/_rdy, fr_flush_val,
fr_idx, fr_start_pc, fr_next_pc, fr_taken_val, fr_taken_pos
(dut.ftq_ifu_*); fr_rd_idx (u_ftq.u_entry.fetch_rd_idx);
fr_s_val/_taken/_pos/_type/_src/_tgt (u_ftq.u_entry.fetch_rd_entry.slot);
pc_val, pc_idx, pc_succ, pc_s_* (u_ftq.u_ifu pd_wr_val, pd_wr_idx,
w_corr_succ, w_corr_slot); ew_alloc_val/_idx/_pc, ew_p2_val/_idx,
ew_p3_val/_idx (u_ftq.u_entry ports).
Hard checks:
- err_no_record: a slot taken whose entry has no record, or whose PC is
  not start_pc + 2 x pos; also a correction of an entry with no record.
- err_late_write: a p2 or p3 slot write to an entry whose request was
  accepted in an earlier cycle, or a p2 write in the request's own
  cycle.
- err_fetch_port: the fetch read port names a different entry from the
  request.
- err_record_moved: a new request for a branch's entry between its take
  and its resolve.
- fr_disagree.
New columns: fr_mispred, fr_agree, fr_disagree, fr_c1_agree,
fr_c1_disagree, fr_c2_agree, fr_c2_disagree, fr_c3_excluded,
fr_corr_after_take, fr_beyond_taken, fr_requests, fr_corrections, and
the four err_ checks above.

p5 observe (perf003_p3_observe.csv): status ok in all 12, every hard
err_* 0, fr_beyond_taken 0.

| set | trace | fr_agree | fr_disagree | C1 agree | C1 disagree | C2 agree | C2 disagree | C3 excluded | fr_mispred | mispred |
|---|---|---|---|---|---|---|---|---|---|---|
| immediate | compress_1 | 267715 | 0 | 267 | 0 | 0 | 0 | 1 | 7026 | 7025 |
| immediate | fp_1 | 411616 | 0 | 3 | 0 | 0 | 0 | 0 | 31907 | 31907 |
| immediate | infra_1 | 428088 | 0 | 1878 | 0 | 0 | 0 | 0 | 34182 | 34182 |
| immediate | int_6 | 243161 | 0 | 8 | 0 | 0 | 0 | 0 | 10325 | 10325 |
| immediate | media_2 | 128087 | 0 | 31 | 0 | 0 | 0 | 0 | 7576 | 7576 |
| immediate | web_11 | 416678 | 0 | 7233 | 0 | 0 | 0 | 0 | 58751 | 58751 |
| latency | compress_1 | 267774 | 0 | 208 | 0 | 0 | 0 | 1 | 7610 | 7609 |
| latency | fp_1 | 411617 | 0 | 2 | 0 | 0 | 0 | 0 | 33435 | 33435 |
| latency | infra_1 | 428282 | 0 | 1684 | 0 | 0 | 0 | 0 | 36294 | 36294 |
| latency | int_6 | 243163 | 0 | 6 | 0 | 0 | 0 | 0 | 10438 | 10438 |
| latency | media_2 | 128093 | 0 | 25 | 0 | 0 | 0 | 0 | 3445 | 3445 |
| latency | web_11 | 417154 | 0 | 6757 | 0 | 0 | 0 | 0 | 58926 | 58926 |

C2 is 0 because no class-conflict PC is reached in these prefixes.
compress_1's fr_mispred exceeds mispred by its C3 branch (Problem 4, the
C3 fix).
p4_params observe (media_2, perf003_p3_params.csv): status ok in all 23,
every hard err_* 0, fr_disagree 0. The first run of rev_ftb512 used
PERF-002's ftb512 binary, which has no record columns. I rebuilt
ftb512_s2 from a source-only scratch copy (RVA_ROOT and SRC_ROOT set to
the copy, FTB_ENTRIES 512) and reran.
The record observes only: in all 12 p5 runs, every column shared by
perf003_p2_target.csv and perf003_p3_observe.csv is equal (timing
columns aside).

### Problem 4: the fetch rule, driving

Built:
- --mispredict-rule fetch|stream, with fetch the default.
- Under fetch, a branch's verdict is read from its record in its resolve
  cycle: the resolution queue is formed before the cycle's redirect, and
  a mispredict redirects then. There is no pend and no decided_by_slot.
- The next path slot after each branch is recorded (nxt_seen/nxt_ok).
  - err_stream: fetch leaves the path after a branch the record judged
    correct; repaired by RC_REPLAY naming the branch.
  - err_fetch_rule: fetch delivers the trace's next PC after a branch
    judged mispredicted.
  - Both are hard checks under fetch.
- pred_src comes from the record under either rule.
- New column: mispredict_rule.
THE C3 FIX, found during Problem 5: the path's last branch has no next
record. The verdict compared it with a pc + 4 stand-in, so a taken last
branch counted as mispredicted. It is not judged now, as C3 excludes it
and the stream rule never judged it. This moves compress_1 by one (6913
-> 6912 immediate, 7584 -> 7583 latency; a direct call at k 1999999) and
changes no other row.

err_predict's causes, from observe runs with the take-time reading still
built (perf003_p4_causes.csv). For each branch, the reading's verdict is
compared with the record's. A disagreement is classed by comparing the
slot read at the take with the record's slot at the same position:
- rsv: a resolution slot write to the entry between its request and the
  take;
- pd: a predecode correction that reaches the entry in or after the take
  cycle;
- other: any other slot difference;
- jal: the reading's direct-jump rule;
- rule: the slots are equal and the reading's rule differs.
To show the source of PERF-002's counts, the same runs were made on a
temporary build with PERF-002's pc + 8 target: one line, built as
perf/build/pc8_s2, reverted and deleted after.

| build | set | trace | err_predict (vs stream) | reading vs record | rsv | pd | other | jal | rule | slot differs, same verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| head | immediate | compress_1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1472 |
| head | immediate | fp_1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 25 |
| head | immediate | infra_1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6067 |
| head | immediate | int_6 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 76 |
| head | immediate | media_2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 146 |
| head | immediate | web_11 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 20488 |
| head | latency | compress_1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1527 |
| head | latency | fp_1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 25 |
| head | latency | infra_1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6239 |
| head | latency | int_6 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 89 |
| head | latency | media_2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 155 |
| head | latency | web_11 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 20662 |
| pc8 | immediate | compress_1 | 1734 | 1735 | 0 | 1735 | 0 | 0 | 0 | 3379 |
| pc8 | immediate | fp_1 | 7512 | 7512 | 0 | 7512 | 0 | 0 | 0 | 11301 |
| pc8 | immediate | infra_1 | 6874 | 6887 | 0 | 6887 | 0 | 0 | 0 | 13534 |
| pc8 | immediate | int_6 | 9456 | 9456 | 0 | 9456 | 0 | 0 | 0 | 9876 |
| pc8 | immediate | media_2 | 202 | 202 | 0 | 202 | 0 | 0 | 0 | 382 |
| pc8 | immediate | web_11 | 1865 | 1881 | 0 | 1881 | 0 | 0 | 0 | 23243 |
| pc8 | latency | compress_1 | 1490 | 1491 | 0 | 1491 | 0 | 0 | 0 | 3227 |
| pc8 | latency | fp_1 | 8038 | 8038 | 0 | 8038 | 0 | 0 | 0 | 13033 |
| pc8 | latency | infra_1 | 6045 | 6070 | 0 | 6070 | 0 | 0 | 0 | 13013 |
| pc8 | latency | int_6 | 8021 | 8021 | 0 | 8021 | 0 | 0 | 0 | 8454 |
| pc8 | latency | media_2 | 198 | 198 | 0 | 198 | 0 | 0 | 0 | 396 |
| pc8 | latency | web_11 | 1837 | 1854 | 0 | 1854 | 0 | 0 | 0 | 23622 |

The pc8 err_predict equals Problem 0's in all 12 runs, and every
disagreement has one cause: a predecode correction that reaches the
entry in or after the take cycle. The take reads r_arr, and the
correction is written the cycle after the F3 transfer, which can be the
take cycle. With pc + 8 these were M3 corrections of false FTB targets;
with the fix they are M1 JAL corrections, where the reading's jump rule
gives the same verdict. None comes from a resolution write. The
hypothesis ("because the entry's slots change between the request and
the take") is therefore wrong as worded: the slots change between the
take and the correction landing.
A first classification left 3 pc8 disagreements as "other" (infra_1
latency 1, web_11 latency 2). They were corrections in the take cycle
itself, which the record already held; with these classed as pd,
"other" is 0.
Then pq_* were removed from perf_top.sv, and err_predict and its cause
columns from perf_fe.cc and the CSV. The stream rule's decided_by_slot
fallback now uses the record's verdict. On the final build the stream
rule's counts equal the observe runs' except pred_src attribution on
infra_1, web_11 and int_6 latency: mis_/pred_ tage and sc move to none,
with totals equal. This is because a predecode-corrected slot carries
PRED_NONE (ftq_ifu.sv W1).

Fetch rule, final build (perf003_p5_oracle.csv rows immediate and
latency, oracle off; also perf003_p4_rules.csv fetch_*): 12 runs, status
ok, every hard err_* 0, err_stream 0, err_fetch_rule 0, resolve_wait_sum
0, decided_by_slot 0. Instr is 2,000,000, and NumBr (224630, 396994,
248445, 199857, 67352, 285258) is the reader's prefix count, as in
PERF-002's p5_checks.csv.

| set | trace | mpki | mpki_cond | ubtb | loop | ftb | tage | sc | ittage | ras | none | cycles fetch | cycles stream | stream - fetch |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| immediate | compress_1 | 3.4560 | 2.0715 | 0.0000 | 0.0005 | 0.8190 | 0.3455 | 0.2720 | 0.0140 | 0.9925 | 1.0125 | 674230 | 683700 | 9470 |
| immediate | fp_1 | 16.4320 | 16.4180 | 0.0000 | 0.8550 | 4.1965 | 8.0685 | 3.2825 | 0.0000 | 0.0000 | 0.0295 | 888716 | 905596 | 16880 |
| immediate | infra_1 | 17.0105 | 8.3585 | 0.0000 | 0.0015 | 3.7890 | 1.2585 | 0.9895 | 0.1035 | 5.9875 | 4.8810 | 1358583 | 1436730 | 78147 |
| immediate | int_6 | 5.1665 | 5.1205 | 0.0000 | 0.0015 | 4.3395 | 0.5085 | 0.2310 | 0.0000 | 0.0195 | 0.0665 | 634720 | 645580 | 10860 |
| immediate | media_2 | 3.7905 | 1.3610 | 0.0000 | 0.0000 | 1.1405 | 0.0820 | 0.0645 | 0.0000 | 2.3770 | 0.1265 | 490672 | 504108 | 13436 |
| immediate | web_11 | 28.1675 | 15.0760 | 0.0010 | 0.0180 | 3.8570 | 2.5975 | 2.4110 | 0.2520 | 2.9045 | 16.1265 | 1936020 | 2086174 | 150154 |
| latency | compress_1 | 3.7915 | 2.1085 | 0.0005 | 0.0010 | 0.8065 | 0.4110 | 0.2690 | 0.0145 | 1.2580 | 1.0310 | 736499 | 739111 | 2612 |
| latency | fp_1 | 16.7375 | 16.7235 | 0.0000 | 0.7760 | 4.8170 | 7.8980 | 3.2175 | 0.0000 | 0.0000 | 0.0290 | 1176921 | 1181631 | 4710 |
| latency | infra_1 | 18.1845 | 8.5330 | 0.0005 | 0.0120 | 4.0685 | 1.4050 | 1.0475 | 0.0940 | 6.6190 | 4.9380 | 1646885 | 1677851 | 30966 |
| latency | int_6 | 5.2250 | 5.1490 | 0.0000 | 0.0005 | 4.2410 | 0.6010 | 0.2585 | 0.0000 | 0.0490 | 0.0750 | 699549 | 698861 | -688 |
| latency | media_2 | 1.7205 | 1.3970 | 0.0000 | 0.0120 | 1.1340 | 0.1135 | 0.0615 | 0.0000 | 0.2695 | 0.1300 | 486960 | 486739 | -221 |
| latency | web_11 | 29.4080 | 15.5125 | 0.0015 | 0.0135 | 4.2690 | 2.8160 | 2.4645 | 0.2470 | 3.2990 | 16.2975 | 2356496 | 2448186 | 91690 |

The stream rule's extra cycles, the wait it added (its resolve_wait_sum
is 2,202 to 826,413), are 2,612 to 150,154 in 10 of 12 runs. In int_6
and media_2 latency the fetch rule is longer, by 688 and 221 cycles:
the two rules redirect at different cycles, so the predictors see
different streams. The MPKI is not compared (ruled).
p4_params under fetch (perf003_p4_params.csv, media_2, 3e5): status ok
in all 23, and every parameter moves its count. Base: 74,437 cycles.
- execute fixed:8: resolve_lat_sum 2,400,000, cycles 73,658.
- execute uniform, geometric, table: resolve_lat_sum 2,098,831,
  1,796,787 and 1,499,184.
- resolve-commit fixed:8: commit_delay_sum 2,400,000.
- take 2: taken_per_cycle 1.9473, ftq_full_cycles 79,799.
- window 16 with r2c 8: 174,319 cycles.
- preload and perfect: l1i_gets 88 and 20.
- sc_off: pred_sc 0.
- fe_cfg_seen: enf/1024/1024 and en3/... as set.
- limit_100k: instr 100,000.
- mem-lat 30: 75,042 cycles.
- ftb512: sha unversioned, 74,442 cycles.
min = max (fixed4_seed1 and _seed2): every column but seed is equal.
uniform:2:12 on seeds 1 and 2: 49 columns differ.
0/0: in a --log run (media_2), the return k 7 is taken in cycle 348;
its take cycle is 349; its verdict and resolution fall in 349; it
commits in 350, after the FTQ accepts the resolution (A7).
The moved sets (--resolve-lat -> --execute-lat) give the same rows as
before.

### Problem 5: the oracle

FORCE POINTS (bp_cluster.sv), named before the build:
- p1, p1_form_comb (791):
  - r_ubtb_pred_p1: decl 473, load 711; read 843 .br_taken, 827 and 858
    .target. Forced whole.
  - w_lp_pred_p1[s]: decl 368, port 1895; read 817-820 .lp_pred_taken.
  - r_ras_tos_val_p1[s] and r_ras_tos_addr_p1[s]: decl 475-476, load
    717-718; read 851-856.
- p2, p2_class_comb (997):
  - w_lp_pred_p2[s]: decl 372, port 1896; read 1052-1055.
  - w_tage_pred_meta_p2[s]: decl 434, port 1970; read 1057
    .tage_pred_tkn.
  - w_ftb_br_taken_p2[s]: decl 425, assign 1710; read 1058.
- p2, p2_succ_comb (1129):
  - w_ftb_br_target_p2[s]: decl 426, assign 1712; read 1182.
  - w_ras_pop_addr_p2[s]: decl 459, port 2050; read 1188.
  - w_ittage_pred_meta_p2[s]: port 1993; read 1173-1175 .ittage_prm_tgt
    and .ittage_alt_tgt.
  - w_ftb_jmp_target_p2: decl 407, port 1934; read 1190, 1195, 1199.
- p3, p3_redir_comb (1312) and p3_slot_comb (1364):
  - w_sc_pred_meta_p3[s]: decl 449, port 2025; read 1327 and 1371
    .sc_pred_tkn.
Not forced: slot presence, type and position, the stage valids, and the
fast-path and LP-use selects.
Each forced value is a mux: the trace's value where the gasket enables
it, else the predictor's own. The predictor's own value comes from
places the force does not reach:
- the p0 -> p1 registers: wrapper shadows loaded every clock from
  w_ubtb_pred_p1 and w_ras_tos_*_p0, with the same synchronous reset
  (stage_ff 657-719);
- the p2 and p3 outputs: the predictor module's own output port.

BUILT WITHOUT AN RTL CHANGE. Three Verilator 5.048 behaviors decided the
form; each was found in a scratch test or in the harness:
- With a predictor module inlined, its port and bp_cluster's net are one
  variable, so the mux is circular: UNOPTFLAT, and "Unsupported: Cannot
  detect changes on expression of complex type 'VlForceVec'". perf.vlt
  now has no_inline for loop_pred, ftb, tage, ittage, sc and ras. The
  logic is unchanged; only the hierarchy is kept.
- force/release per entry does not work in place of the mux. A released
  variable keeps its forced value until its driver re-evaluates (a cycle
  or more), and force inside always_comb does nothing.
- Two member forces on one struct element: only one is applied, with no
  warning (ITTAGE: alt_tgt took, prm_tgt did not). Every force is
  therefore of a whole variable or element, built from the predictor's
  value with the trace's fields put in.
With the oracle off, the forced build gives the same counts as without
the forces: the oracle-off immediate and latency runs equal Problem 4's
build in every column in 11 of 12 runs, and compress_1 differs only by
the C3 fix. Speed on one run alone (media_2, 3e5): 22,827 cycles per
second. Under the 24-process study load, the forced build ran at 15,113
to 21,443 and the observe build at 22,924 to 25,727; the loads differed,
so these are not a measured slowdown.

THE PATH (perf_fe.cc OEnt, o_succ, o_slot). An entry allocated at p1 is
on the path at trace index k in either of two cases:
- its PC is where a backend redirect sent fetch (k from the redirect);
- its PC is where the trace goes after its predecessor (the entry before
  it), when the predecessor is on the path: the trace runs sequentially
  from the predecessor's k to the predecessor's predicted end (its
  lowest taken slot, else its fall-through) and continues at the PC.
The predecessor's prediction comes from its fetch record once it has
been fetched (resolutions can rewrite its slots afterwards), and from its
FTQ entry (os_pr_*) before that. The p2 and p3 blocks are aligned again
each cycle, oldest first, because a p2 or p3 write can move the
predecessor's end without changing its successor (BP-150). An entry not
aligned is off the path and is not forced. The supplier keeps 4,096
retired records readable (set_keep).
Defects of my own, found and fixed before the acceptance runs:
- the supplier dropped retired records;
- a loop inside a block: the first sequential arrival at the successor
  PC was taken as the block's end;
- a predecessor's entry already rewritten by its resolutions;
- a branch taken to its own pc + 4 was treated as leaving the block;
- the two-member force;
- the C3 verdict.
New columns: oracle, orc_forced_entries, orc_offpath_entries,
orc_path_unforced, orc_realigned, err_orc_slot_mispred (hard under
--oracle), orc_slot_trap, mispred_trap_after, miss_cond, _cond_mis,
miss_direct, _direct_mis, miss_indirect, _indirect_mis, miss_return,
_return_mis.

Oracle runs (perf003_p5_oracle.csv; 2e6, fetch): all 18 status ok,
every hard err_* 0, err_orc_slot_mispred 0, orc_path_unforced 0.

| set | trace | forced entries | off-path entries | slot-held mispred | trap after branch | cond miss / mis | direct miss / mis | indirect miss / mis | return miss / mis | mispred | p2_overrides | p3_overrides |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| oracle_immediate | compress_1 | 315766 | 57133 | 0 | 1 | 2715 / 1246 | 0 / 0 | 158 / 158 | 506 / 506 | 1911 | 17831 | 113 |
| oracle_immediate | fp_1 | 316875 | 1317 | 0 | 0 | 57 / 29 | 0 / 0 | 11 / 11 | 17 / 17 | 57 | 4 | 4 |
| oracle_immediate | infra_1 | 414774 | 295656 | 0 | 8 | 11348 / 5416 | 0 / 0 | 1045 / 1043 | 2533 / 2533 | 9000 | 110310 | 801 |
| oracle_immediate | int_6 | 333803 | 2434 | 0 | 0 | 158 / 75 | 0 / 0 | 20 / 20 | 23 / 23 | 118 | 410 | 5 |
| oracle_immediate | media_2 | 302607 | 6523 | 0 | 0 | 260 / 124 | 0 / 0 | 37 / 37 | 60 / 60 | 221 | 1887 | 5 |
| oracle_immediate | web_11 | 367216 | 862546 | 0 | 1 | 67049 / 16916 | 0 / 0 | 6392 / 6382 | 7880 / 7880 | 31179 | 43479 | 1763 |
| oracle_latency | compress_1 | 315744 | 68009 | 0 | 1 | 2720 / 1248 | 0 / 0 | 157 / 157 | 506 / 506 | 1912 | 18232 | 167 |
| oracle_latency | fp_1 | 316875 | 1700 | 0 | 0 | 57 / 29 | 0 / 0 | 11 / 11 | 17 / 17 | 57 | 3 | 4 |
| oracle_latency | infra_1 | 413503 | 348943 | 0 | 8 | 11343 / 5413 | 0 / 0 | 1042 / 1040 | 2515 / 2515 | 8976 | 112768 | 1157 |
| oracle_latency | int_6 | 333764 | 3202 | 0 | 0 | 158 / 75 | 0 / 0 | 20 / 20 | 23 / 23 | 118 | 420 | 7 |
| oracle_latency | media_2 | 302891 | 7942 | 0 | 0 | 262 / 124 | 0 / 0 | 37 / 37 | 60 / 60 | 221 | 1897 | 7 |
| oracle_latency | web_11 | 367128 | 1047922 | 0 | 1 | 67345 / 16931 | 0 / 0 | 6370 / 6360 | 7881 / 7881 | 31173 | 48607 | 2880 |
| perfect_oracle | compress_1 | 315765 | 50380 | 0 | 1 | 2710 / 1245 | 0 / 0 | 159 / 159 | 504 / 504 | 1909 | 17722 | 93 |
| perfect_oracle | fp_1 | 316875 | 1068 | 0 | 0 | 57 / 29 | 0 / 0 | 11 / 11 | 17 / 17 | 57 | 4 | 1 |
| perfect_oracle | infra_1 | 414778 | 256295 | 0 | 8 | 11338 / 5405 | 0 / 0 | 1044 / 1042 | 2539 / 2539 | 8994 | 109257 | 636 |
| perfect_oracle | int_6 | 333803 | 2079 | 0 | 0 | 158 / 75 | 0 / 0 | 20 / 20 | 23 / 23 | 118 | 410 | 5 |
| perfect_oracle | media_2 | 302606 | 5690 | 0 | 0 | 260 / 124 | 0 / 0 | 37 / 37 | 60 / 60 | 221 | 1886 | 5 |
| perfect_oracle | web_11 | 367144 | 726277 | 0 | 1 | 67057 / 16930 | 0 / 0 | 6390 / 6380 | 7866 / 7866 | 31177 | 42078 | 1493 |

Every mispredict is a miss or a trap after a branch (compress_1
immediate: 1246 + 158 + 506 + 1 = 1911). Direct misses are 0, because
predecode corrects every JAL. A missed return always mispredicts. A
missed conditional mispredicts only on its taken instances.
THE TRAP CASES. Example: compress_1 k 10542, a direct call at
0xffffdfe2bac8 to 0xffffdfe36988, predicted to 0xffffdfe36988. The next
trace record is 0xfffffbfffdbfc400, an exception entry, where the
harness also takes RC_TRAP redirects. THE VERDICT compares with the
trace's next PC, so these count as mispredicts with or without the
oracle: mispred_trap_after is 1, 9 and 4 on compress_1, infra_1 and
web_11 in every set; 1, 8 and 1 of them are slot-held. Jeff, in the
session, answering the IA's question: count them apart (orc_slot_trap),
accept Problem 5, continue.

Cycles of the design against the oracle (the difference is what
prediction costs):

| backend | trace | cycles | cycles oracle | difference | IPC | IPC oracle |
|---|---|---|---|---|---|---|
| immediate | compress_1 | 674230 | 632999 | 41231 | 2.9663 | 3.1596 |
| immediate | fp_1 | 888716 | 621847 | 266869 | 2.2504 | 3.2162 |
| immediate | infra_1 | 1358583 | 1132607 | 225976 | 1.4721 | 1.7658 |
| immediate | int_6 | 634720 | 573727 | 60993 | 3.1510 | 3.4860 |
| immediate | media_2 | 490672 | 434350 | 56322 | 4.0760 | 4.6046 |
| immediate | web_11 | 1936020 | 1660150 | 275870 | 1.0330 | 1.2047 |
| latency | compress_1 | 736499 | 647971 | 88528 | 2.7156 | 3.0866 |
| latency | fp_1 | 1176921 | 673900 | 503021 | 1.6993 | 2.9678 |
| latency | infra_1 | 1646885 | 1196627 | 450258 | 1.2144 | 1.6714 |
| latency | int_6 | 699549 | 576656 | 122893 | 2.8590 | 3.4683 |
| latency | media_2 | 486960 | 438210 | 48750 | 4.1071 | 4.5640 |
| latency | web_11 | 2356496 | 1867777 | 488719 | 0.8487 | 1.0708 |
| perfect I-cache | compress_1 | 667367 | 626159 | 41208 | 2.9969 | 3.1941 |
| perfect I-cache | fp_1 | 888480 | 621598 | 266882 | 2.2510 | 3.2175 |
| perfect I-cache | infra_1 | 1315034 | 1090710 | 224324 | 1.5209 | 1.8337 |
| perfect I-cache | int_6 | 634477 | 573371 | 61106 | 3.1522 | 3.4881 |
| perfect I-cache | media_2 | 489823 | 433496 | 56327 | 4.0831 | 4.6137 |
| perfect I-cache | web_11 | 1789764 | 1515218 | 274546 | 1.1175 | 1.3199 |

The ceiling without I-cache misses (perfect I-cache with the oracle) is
IPC 1.3199 (web_11) to 4.6137 (media_2). It still includes the FTB's
misses (web_11: 67,057 conditional misses).

### Problem 6: the backend stages and the near-perfect default

THE STAGES:
- --decode-lat, --rename-lat, --dispatch-lat and --execute-lat, each a
  distribution with its own random stream. Execute keeps the stream
  --resolve-lat had (seed x 3 + 1); the three new stages add 2^40,
  2 x 2^40 and 3 x 2^40.
- Resolve latency is their sum.
- --resolve-lat is removed and now stops the run with a message.
- The CSV's resolve_lat becomes decode_lat, rename_lat, dispatch_lat and
  execute_lat.
- Moved to --execute-lat with the same distribution: p5.sets latency
  (immediate now names fixed:0 explicitly), the 8 p4_params sets, and
  perf003_p4.sets, perf003_p4_causes.sets and perf003_p5.sets.
Stage checks (perf003_p6_stages.csv; media_2, 3e5, all ok):

| set | resolve_lat_sum | expected | cycles | mispred |
|---|---|---|---|---|
| st_zero (all 0) | 0 | 0 | 74437 | 1219 |
| st_dec2 / st_ren2 / st_dis2 / st_exe2 | 600000 each | 2 x 300000 | 76124 | 1220 |
| st_dec5 / st_ren5 / st_dis5 / st_exe5 | 1500000 each | 5 x 300000 | 78633 | 1132 |
| st_split_2_3 (decode 2 + execute 3) | 1500000 | 5 x 300000 | 78633 | 1132 |
| st_split_1_4 (rename 1 + dispatch 4) | 1500000 | 5 x 300000 | 78633 | 1132 |
| st_minmax_s1 / _s2 (uniform 1:1, 2:2, 1:1, 3:3; commit 2:2) | 2100000 | 7 x 300000 | 72773 | 606 |
| st_sum7_c2 (execute 7, commit 2) | 2100000 | 7 x 300000 | 72773 | 606 |

Rows compared column by column (seed and the stage columns aside):
- the two splits, decode 5, rename 5 and dispatch 5 all equal execute 5;
- decode 2 equals execute 2;
- minmax on seeds 1 and 2 are equal;
- minmax equals the fixed sum in one stage (0 differing columns each).
All four 0: the --log run with every stage named fixed:0 shows the
return k 7 taken in 348, verdict and resolution in its take cycle 349,
commit in 350.

THE SWEEP (perf003_p6_sweep.sets): execute S 0..8 by resolve to commit C
0..8, the other stages 0, take fixed:8, no window, the real I-cache,
fetch, the six p5 traces at 2e6: 486 runs, all ok, wall 1357 s.
perf/studies/perf003_p6_sweep_table.csv holds trace, S, C,
mispred_return, mpki, mispred, cycles, status and sha for every point
(the per-trace MPKI tables are there); perf003_p6_sweep.csv holds the
full rows.

mispred_return, rows S, columns C:

compress_1
| S \ C | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 2486 | 2486 | 2557 | 2710 | 2981 | 2939 | 3161 | 3033 | 3159 |
| 1 | 2445 | 2445 | 2667 | 2710 | 3037 | 2964 | 3174 | 3201 | 3216 |
| 2 | 2417 | 2425 | 2607 | 2733 | 2999 | 3020 | 3241 | 3288 | 3342 |
| 3 | 2473 | 2470 | 2645 | 2622 | 2944 | 2980 | 3244 | 3222 | 3332 |
| 4 | 2519 | 2488 | 2599 | 2711 | 3015 | 3034 | 3275 | 3273 | 3280 |
| 5 | 2458 | 2458 | 2603 | 2658 | 2972 | 2923 | 3101 | 3115 | 3136 |
| 6 | 2361 | 2364 | 2474 | 2506 | 2854 | 2821 | 3080 | 3064 | 3107 |
| 7 | 2382 | 2383 | 2493 | 2536 | 2832 | 2785 | 3012 | 3034 | 3077 |
| 8 | 2382 | 2382 | 2501 | 2523 | 2829 | 2791 | 3043 | 3034 | 3080 |

fp_1: 17 at every point.

infra_1
| S \ C | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 14707 | 14707 | 15148 | 18251 | 18311 | 18994 | 19881 | 20159 | 20044 |
| 1 | 14836 | 14833 | 15109 | 16839 | 17573 | 19715 | 19714 | 19146 | 19660 |
| 2 | 13978 | 13925 | 14398 | 16373 | 16352 | 18436 | 18486 | 18746 | 18653 |
| 3 | 14338 | 14420 | 15210 | 17112 | 17280 | 18036 | 18015 | 18789 | 18296 |
| 4 | 14093 | 14115 | 14471 | 16333 | 17176 | 18516 | 18192 | 18035 | 17927 |
| 5 | 13731 | 13747 | 14150 | 16302 | 17453 | 17283 | 17770 | 18294 | 17387 |
| 6 | 13191 | 13194 | 13918 | 15268 | 15462 | 16320 | 17036 | 16691 | 17378 |
| 7 | 13466 | 13471 | 13654 | 15012 | 14664 | 15708 | 16359 | 16256 | 16115 |
| 8 | 13440 | 13416 | 13337 | 14300 | 14510 | 15205 | 16230 | 16013 | 16111 |

int_6
| S \ C | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 63 | 63 | 63 | 88 | 92 | 106 | 107 | 116 | 116 |
| 1 | 62 | 62 | 64 | 88 | 91 | 104 | 105 | 121 | 123 |
| 2 | 73 | 74 | 74 | 99 | 101 | 108 | 109 | 108 | 110 |
| 3 | 71 | 71 | 67 | 96 | 99 | 108 | 109 | 111 | 111 |
| 4 | 67 | 67 | 69 | 95 | 97 | 104 | 105 | 109 | 124 |
| 5 | 64 | 64 | 64 | 88 | 91 | 105 | 107 | 123 | 123 |
| 6 | 75 | 75 | 75 | 101 | 103 | 107 | 108 | 124 | 126 |
| 7 | 77 | 77 | 77 | 103 | 105 | 106 | 107 | 109 | 125 |
| 8 | 76 | 76 | 76 | 101 | 103 | 105 | 112 | 111 | 123 |

media_2
| S \ C | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 4815 | 4815 | 4815 | 4820 | 4816 | 4745 | 4752 | 1128 | 141 |
| 1 | 4813 | 4813 | 4815 | 4814 | 4751 | 1315 | 1321 | 141 | 140 |
| 2 | 4818 | 4817 | 4812 | 4749 | 3782 | 133 | 140 | 143 | 141 |
| 3 | 4811 | 4811 | 4744 | 4191 | 134 | 130 | 136 | 140 | 92 |
| 4 | 4744 | 4744 | 4167 | 783 | 133 | 133 | 140 | 143 | 139 |
| 5 | 4220 | 4220 | 1665 | 190 | 132 | 84 | 90 | 92 | 93 |
| 6 | 1798 | 1798 | 330 | 204 | 131 | 87 | 92 | 604 | 603 |
| 7 | 979 | 979 | 780 | 641 | 639 | 593 | 598 | 603 | 603 |
| 8 | 850 | 850 | 717 | 640 | 594 | 593 | 600 | 604 | 604 |

web_11
| S \ C | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 14064 | 14064 | 14232 | 14695 | 15508 | 16302 | 16230 | 14781 | 15449 |
| 1 | 15523 | 15739 | 15735 | 15620 | 14580 | 14651 | 14718 | 14795 | 14614 |
| 2 | 16098 | 16150 | 16493 | 16747 | 16937 | 16084 | 16411 | 14798 | 14778 |
| 3 | 14913 | 14887 | 15014 | 15542 | 15878 | 15669 | 15550 | 14693 | 14254 |
| 4 | 15307 | 15637 | 14897 | 15957 | 16626 | 17007 | 16782 | 15048 | 15198 |
| 5 | 14540 | 14328 | 15067 | 15090 | 16900 | 16669 | 16912 | 14561 | 14742 |
| 6 | 15032 | 15029 | 14928 | 16366 | 16151 | 15864 | 15727 | 14314 | 15907 |
| 7 | 15792 | 15510 | 15010 | 16386 | 16147 | 15287 | 15255 | 14409 | 15749 |
| 8 | 15643 | 15672 | 15825 | 14837 | 14836 | 14542 | 14523 | 16255 | 16666 |

THE DEFAULT: the only point at which every trace's mispred_return equals
its value at every point with S' >= S and C' >= C is (8, 8). Each
trace's smallest such point is (8, 8), except fp_1 (0, 0) and media_2
(8, 7). By the task's rule no default was changed: the harness default
stays immediate (every stage and resolve to commit fixed:0). The README
says so. A ruling is needed.

TD#207, from the sweep (not fixed):
- media_2 is the commit race PERF-002 saw. At S = 0, returns stay
  4,745-4,820 for C 0..6, then fall to 1,128 at C 7 and 141 at C 8. At
  C = 0 they fall with S: 4,815 at S 0, 4,220 at S 5, 1,798 at S 6, 850
  at S 8. The fall comes at about S + C = 7 to 8 and also starts
  earlier, from about S + C = 5 (for example (3, 4) 134, (5, 2) 1,665).
  But media_2 does not settle: at S >= 6 with C >= 7, and on the whole
  S 7 and 8 rows, returns rise again, to about 600. Return mispredicts
  depend on the resolve and commit timing in both directions.
- compress_1, infra_1 and int_6 rise with C at fixed S (compress_1 S 0:
  2,486 -> 3,159; infra_1 S 0: 14,707 -> 20,044; int_6 S 0: 63 -> 116).
  infra_1 falls with S at fixed C (C 0: 14,707 -> 13,440).
- web_11 varies by 14,064-17,007 with no monotone trend.
- fp_1 is unchanged (17).
So the claim "return mispredicts stop changing at small backend
latencies" is not supported on 5 of 6 traces.

### Problem 7: what is found
README.md, Performance analysis:
- Running the harness: the run parameters rewritten as a list. It
  covers the four stages and their streams, --resolve-lat removed, THE
  DEFAULT BACKEND (immediate; the near-perfect default not set, awaiting
  a ruling), --mispredict-rule, --oracle, and the CPU cap for the tools
  and the build (JOBS).
- Running a study:
  - the example sets use --execute-lat and add an oracle set;
  - -j defaults to 75% of the hardware threads;
  - the hard checks are listed by rule;
  - err_predict is removed;
  - the columns table gains fr_*, mispred_trap_after, orc_*,
    orc_slot_trap and miss_*, and names the four stage columns;
  - the PERF-003 studies are listed.
tools/scan_traces.py:128: PF-16 -> PF-15 (the comment is at 128, not
127).
Other defects found and fixed, all in perf/:
- the verdict read at the take (Problem 3);
- the C3 verdict (Problem 4);
- the oracle's alignment defects (Problem 5).
Defect found and not changed (a ruling, not a fix): a trap after a
branch counts as that branch's mispredict under both rules
(mispred_trap_after 1, 9 and 4 per 2e6 run on compress_1, infra_1 and
web_11).

### Problem 8: the regression
tools/regress.sh, run once at the end in the background. Time 281 s.
The summary, whole:

```
==================================================================
REGRESSION SUMMARY  git 7c61093 (dirty)
root /home/jeff/Development/jeffnye-gh/pacino
jobs 15 (default: 32 threads / 2, 31 GB / 2); priority: nice -n 10, ionice -c 3
==================================================================
== rtl/core/csr
  PASS       lint_csr_pkg           rc=0   warn=0  err=0  -              0s
  PASS       lint_csr_tb_pkg        rc=0   warn=0  err=0  -              0s
  PASS       sim_csr_tb_pkg         rc=0   warn=0  err=0  200/0          1s
  time 1s
== rtl/core/frontend/bpu
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       lint_loop_pred         rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_table        rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_table          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_brimli         rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_cntrl          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc                rc=0   warn=0  err=0  -              1s
  PASS       lint_ittage_table      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_cntrl      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_arb        rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage            rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_cntrl        rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_arb          rc=0   warn=0  err=0  -              0s
  PASS       lint_tage              rc=0   warn=0  err=0  -              1s
  PASS       lint_ras               rc=0   warn=0  err=0  -              1s
  PASS       lint_ftb_array         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru          rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb               rc=0   warn=0  err=0  -              0s
  PASS       lint_bp_cluster        rc=0   warn=0  err=0  -              2s
  PASS       sim                    rc=0   warn=0  err=0  31/0           0s
  PASS       sim_history            rc=0   warn=0  err=0  45442/0        9s
  PASS       sim_ubtb               rc=0   warn=0  err=0  341/0          7s
  PASS       sim_loop_pred          rc=0   warn=0  err=0  11548/0        4s
  PASS       sim_tage_table         rc=0   warn=0  err=0  15/0           0s
  PASS       sim_sc_table           rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_table_fast      rc=0   warn=0  err=0  7/0            0s
  PASS       sim_sc_brimli          rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_brimli_fast     rc=0   warn=0  err=0  7/0            0s
  PASS       sim_sc_cntrl           rc=0   warn=0  err=0  98/0           4s
  PASS       sim_sc                 rc=0   warn=0  err=0  144/0          2s
  PASS       sim_sc_fast            rc=0   warn=0  err=0  140/0          3s
  PASS       sim_ittage_table       rc=0   warn=0  err=0  32/0           0s
  PASS       sim_ittage_cntrl       rc=0   warn=0  err=0  147/0          3s
  PASS       sim_ittage             rc=0   warn=0  err=0  389/0          4s
  PASS       sim_ittage_fast        rc=0   warn=0  err=0  389/0          3s
  PASS       sim_bp_cluster         rc=0   warn=0  err=0  2112/0         6s
  PASS       sim_bp_cluster_init    rc=0   warn=0  err=0  2112/0        45s
  PASS       sim_ras                rc=0   warn=0  err=0  602/0          3s
  PASS       sim_ftb                rc=0   warn=0  err=0  239/0          3s
  PASS       sim_tage               rc=0   warn=0  err=0  109/0          3s
  PASS       sim_tage_fast          rc=0   warn=0  err=0  109/0          2s
  PASS       sim_tage_tasks         rc=0   warn=0  err=0  1/0            3s
  PASS       sim_tage_manual        rc=0   warn=0  err=0  1267/0         3s
  PASS       cov_history            rc=0   warn=0  err=0  45442/0        8s
  PASS       cov_ubtb               rc=0   warn=0  err=0  341/0          7s
  PASS       cov_loop_pred          rc=0   warn=0  err=0  11548/0        6s
  PASS       cov_tage_table         rc=0   warn=0  err=0  15/0           1s
  PASS       cov_tage               rc=0   warn=0  err=0  218/0          8s
  PASS       cov_bp_cluster         rc=0   warn=0  err=0  2112/0        23s
  PASS       cov_bpu                rc=0   warn=0  err=0  57564/0       33s
             sum of sub-runs:tage=218/0 tage_table=15/0 loop_pred=11548/0 bp_history=45442/0 ubtb=341/0
  PASS       lint_1slot             rc=0   warn=0  err=0  -              0s
  PASS       lint_loop_pred_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_table_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_table_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_brimli_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_cntrl_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_1slot          rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_table_1slot rc=0   warn=0  err=0  -              1s
  PASS       lint_ittage_cntrl_1slot rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_arb_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_1slot      rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_cntrl_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_arb_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_1slot        rc=0   warn=0  err=0  -              0s
  PASS       lint_ras_1slot         rc=0   warn=0  err=0  -              1s
  PASS       lint_ftb_array_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_1slot         rc=0   warn=0  err=0  -              0s
  PASS       lint_bp_cluster_1slot  rc=0   warn=0  err=0  -              1s
  PASS       sim_1slot              rc=0   warn=0  err=0  27/0           0s
  PASS       sim_history_1slot      rc=0   warn=0  err=0  26590/0        3s
  PASS       sim_ubtb_1slot         rc=0   warn=0  err=0  341/0          2s
  PASS       sim_loop_pred_1slot    rc=0   warn=0  err=0  5765/0         3s
  PASS       sim_tage_table_1slot   rc=0   warn=0  err=0  11/0           0s
  PASS       sim_sc_table_1slot     rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_table_fast_1slot rc=0   warn=0  err=0  6/0            1s
  PASS       sim_sc_brimli_1slot    rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_brimli_fast_1slot rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_cntrl_1slot     rc=0   warn=0  err=0  98/0           2s
  PASS       sim_sc_1slot           rc=0   warn=0  err=0  108/0          1s
  PASS       sim_sc_fast_1slot      rc=0   warn=0  err=0  104/0          0s
  PASS       sim_ittage_table_1slot rc=0   warn=0  err=0  26/0           0s
  PASS       sim_ittage_cntrl_1slot rc=0   warn=0  err=0  138/0          3s
  PASS       sim_ittage_1slot       rc=0   warn=0  err=0  258/0          3s
  PASS       sim_ittage_fast_1slot  rc=0   warn=0  err=0  258/0          3s
  PASS       sim_bp_cluster_1slot   rc=0   warn=0  err=0  1534/0         5s
  PASS       sim_bp_cluster_init_1slot rc=0   warn=0  err=0  1534/0        26s
  PASS       sim_ras_1slot          rc=0   warn=0  err=0  502/0          4s
  PASS       sim_ftb_1slot          rc=0   warn=0  err=0  186/0          2s
  PASS       sim_tage_1slot         rc=0   warn=0  err=0  105/0          3s
  PASS       sim_tage_fast_1slot    rc=0   warn=0  err=0  105/0          2s
  PASS       sim_tage_tasks_1slot   rc=0   warn=0  err=0  1/0            1s
  PASS       sim_tage_manual_1slot  rc=0   warn=0  err=0  534/0          2s
  time 273s
== rtl/core/frontend/decode
  PASS       lint_dec               rc=0   warn=0  err=0  -              0s
  PASS       sim_dec                rc=0   warn=0  err=0  1355/0        13s
  PASS       coverage               rc=0   warn=0  err=0  -             10s
  PASS       sim_dec_sweep          rc=0   warn=0  err=0  458752/0      39s
  PASS       oracle_dec_sweep       rc=0   warn=0  err=0  -              3s
  PASS       asm_dec_words          rc=0   warn=0  err=0  492/0          0s
  time 65s
== rtl/core/frontend/fe_top
  PASS       lint_fe_top            rc=0   warn=0  err=0  -              4s
  PASS       sim_fe_top             rc=0   warn=0  err=0  849/0         17s
  PASS       assert_labels          rc=0   warn=0  err=0  169/0          2s
  PASS       sim_fe_top_bare        rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_sv39        rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_loops       rc=0   warn=0  err=0  26/0           0s
  PASS       sim_fe_top_coro        rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_calls       rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_lp          rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_hist        rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_twocond     rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_ftbonly     rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_nest        rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_recur       rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_t0_uaon     rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_deep        rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_indir       rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_region      rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_multistart  rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_cross       rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_rvc         rc=0   warn=0  err=0  18/0           1s
  PASS       sim_fe_top_misp_call   rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_sc_nored    rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_jals        rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_fencei      rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_cboinval    rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_uc_nc       rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_uc_io       rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_faults_s rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_pt_faults_h rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_napot_s  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_napot_h  rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_pt_rsv_s    rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_rsv_h    rc=0   warn=0  err=0  20/0           2s
  PASS       sim_fe_top_pt_ad_s     rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_pt_ad_h     rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_pt_inv      rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_zstar       rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_gonly    rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_vsonly   rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_upriv    rc=0   warn=0  err=0  25/0           0s
  PASS       sim_fe_top_sv48        rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_sv57        rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_h57         rc=0   warn=0  err=0  24/0           1s
  PASS       sim_fe_top_pt_gonly_x4 rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_init_walk   rc=0   warn=0  err=0  34/0           0s
  time 32s
== rtl/core/frontend/fe_top/slot1
  PASS       lint_fe_top_1slot      rc=0   warn=0  err=0  -              3s
  PASS       sim_fe_top_1slot       rc=0   warn=0  err=0  847/0         17s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  161/0          1s
  PASS       sim_fe_top_bare_1slot  rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_sv39_1slot  rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_loops_1slot rc=0   warn=0  err=0  24/0           0s
  PASS       sim_fe_top_coro_1slot  rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_calls_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_lp_1slot    rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_hist_1slot  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_twocond_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_ftbonly_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_nest_1slot  rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_recur_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_t0_uaon_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_deep_1slot  rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_indir_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_region_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_multistart_1slot rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_cross_1slot rc=0   warn=0  err=0  18/0           1s
  PASS       sim_fe_top_rvc_1slot   rc=0   warn=0  err=0  18/0           0s
  PASS       sim_fe_top_misp_call_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_sc_nored_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_jals_1slot  rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_fencei_1slot rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_cboinval_1slot rc=0   warn=0  err=0  22/0           0s
  PASS       sim_fe_top_uc_nc_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_uc_io_1slot rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_pt_faults_s_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_faults_h_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_napot_s_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_napot_h_1slot rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_pt_rsv_s_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_rsv_h_1slot rc=0   warn=0  err=0  20/0           1s
  PASS       sim_fe_top_pt_ad_s_1slot rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_pt_ad_h_1slot rc=0   warn=0  err=0  23/0           1s
  PASS       sim_fe_top_pt_inv_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_zstar_1slot rc=0   warn=0  err=0  20/0           0s
  PASS       sim_fe_top_pt_gonly_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_vsonly_1slot rc=0   warn=0  err=0  19/0           0s
  PASS       sim_fe_top_pt_upriv_1slot rc=0   warn=0  err=0  25/0           0s
  PASS       sim_fe_top_sv48_1slot  rc=0   warn=0  err=0  23/0           1s
  PASS       sim_fe_top_sv57_1slot  rc=0   warn=0  err=0  23/0           0s
  PASS       sim_fe_top_h57_1slot   rc=0   warn=0  err=0  24/0           0s
  PASS       sim_fe_top_pt_gonly_x4_1slot rc=0   warn=0  err=0  21/0           0s
  PASS       sim_fe_top_init_walk_1slot rc=0   warn=0  err=0  32/0           0s
  time 30s
== rtl/core/frontend/ftq
  PASS       lint_ftq_ftb_sched     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ftb_sched      rc=0   warn=0  err=0  67/0           1s
  PASS       lint_ftq_ptr           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ptr            rc=0   warn=0  err=0  207/0         12s
  PASS       lint_ftq_commit        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_commit         rc=0   warn=0  err=0  72/0           1s
  PASS       lint_ftq_entry         rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_entry          rc=0   warn=0  err=0  72/0           7s
  PASS       lint_ftq_meta          rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta           rc=0   warn=0  err=0  26/0           0s
  PASS       lint_ftq_status        rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_status         rc=0   warn=0  err=0  45/0           0s
  PASS       lint_ftq_shadow        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_shadow         rc=0   warn=0  err=0  53/0           1s
  PASS       lint_ftq_npc           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_npc            rc=0   warn=0  err=0  84/0           0s
  PASS       lint_ftq_ifu           rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_ifu            rc=0   warn=0  err=0  237/0          3s
  PASS       lint_ftq_resolve       rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_resolve        rc=0   warn=0  err=0  146/0          5s
  PASS       lint_ftq_upd_conv      rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_upd_conv       rc=0   warn=0  err=0  192/0          3s
  PASS       lint_ftq               rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq                rc=0   warn=0  err=0  158/0          2s
  PASS       assert_labels          rc=0   warn=0  err=0  226/0          1s
  PASS       lint_ftq_ftb_sched_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ftb_sched_1slot rc=0   warn=0  err=0  67/0           1s
  PASS       lint_ftq_ptr_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ptr_1slot      rc=0   warn=0  err=0  207/0          2s
  PASS       lint_ftq_commit_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_commit_1slot   rc=0   warn=0  err=0  72/0           1s
  PASS       lint_ftq_entry_1slot   rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_entry_1slot    rc=0   warn=0  err=0  61/0           2s
  PASS       lint_ftq_meta_1slot    rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta_1slot     rc=0   warn=0  err=0  19/0           1s
  PASS       lint_ftq_status_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_status_1slot   rc=0   warn=0  err=0  45/0           0s
  PASS       lint_ftq_shadow_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_shadow_1slot   rc=0   warn=0  err=0  53/0           1s
  PASS       lint_ftq_npc_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_npc_1slot      rc=0   warn=0  err=0  80/0           0s
  PASS       lint_ftq_ifu_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ifu_1slot      rc=0   warn=0  err=0  222/0          3s
  PASS       lint_ftq_resolve_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_resolve_1slot  rc=0   warn=0  err=0  105/0          3s
  PASS       lint_ftq_upd_conv_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_upd_conv_1slot rc=0   warn=0  err=0  106/0          3s
  PASS       lint_ftq_1slot         rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_1slot          rc=0   warn=0  err=0  158/0          3s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  205/0          2s
  time 62s
== rtl/core/frontend/ibuf
  PASS       lint_ibuf              rc=0   warn=0  err=0  -              0s
  PASS       sim_ibuf               rc=0   warn=0  err=0  52/0          10s
  PASS       assert_labels          rc=0   warn=0  err=0  3/0            1s
  time 11s
== rtl/core/frontend/icache
  PASS       lint_l1i               rc=0   warn=0  err=0  -              1s
  PASS       sim_l1i_emitted        rc=0   warn=0  err=0  67/0          11s
  PASS       sim_l1i                rc=0   warn=0  err=0  296/0          7s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0            5s
  time 24s
== rtl/core/frontend/ifu
  PASS       lint_ifu_rvc_exp       rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_predecode     rc=0   warn=0  err=0  -              1s
  PASS       lint_ifu_xlate         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_lbuf          rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_fetch         rc=0   warn=0  err=0  -              1s
  PASS       lint_ifu_f3            rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_wb            rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_maint         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu               rc=0   warn=0  err=0  -              1s
  PASS       sim_ifu_rvc_exp        rc=0   warn=0  err=0  2457618/0     12s
  PASS       sim_ifu_predecode      rc=0   warn=0  err=0  63/0           6s
  PASS       sim_ifu                rc=0   warn=0  err=0  738/0         10s
  PASS       assert_labels          rc=0   warn=0  err=0  16/0           0s
  PASS       oracle_ifu_rvc_exp     rc=0   warn=0  err=0  -              1s
  time 33s
== rtl/core/frontend/l1i_param_chk
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       lint_neg               rc=0   warn=0  err=0  -              0s
  time 0s
== rtl/lib
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       sim                    rc=0   warn=0  err=0  34/0           1s
  time 1s
== rtl
  time 0s
== rtl/mmu/itlb
  PASS       lint_itlb              rc=0   warn=0  err=0  -              1s
  PASS       sim_itlb               rc=0   warn=0  err=0  228/0         13s
  PASS       sim_itlb_d2            rc=0   warn=0  err=0  231/0          7s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0            0s
  time 21s
== rtl/mmu/pmp
  PASS       lint_pmp_pma_chk       rc=0   warn=0  err=0  -              0s
  PASS       sim_pmp_pma_chk        rc=0   warn=0  err=0  73/0          11s
  PASS       lint_neg_pma           rc=0   warn=0  err=0  -              0s
  PASS       lint_neg_pma_dflt      rc=0   warn=0  err=0  -              1s
  time 12s
== rtl/mmu/ptw
  PASS       lint_ptw               rc=0   warn=0  err=0  -              0s
  PASS       lint_pt_build_pkg      rc=0   warn=0  err=0  -              1s
  PASS       sim_ptw                rc=0   warn=0  err=0  1564/0        13s
  PASS       assert_labels          rc=0   warn=0  err=0  13/0          10s
  PASS       sim_pt_gen             rc=0   warn=0  err=0  -              0s
  PASS       sim_ptw_img            rc=0   warn=0  err=0  5465/0         6s
  PASS       sim_pt_gen_noncanon    rc=0   warn=0  err=0  -              0s
  PASS       sim_pt_gen_mem_top     rc=0   warn=0  err=0  -              1s
  time 31s
------------------------------------------------------------------
targets run: 287   total time: 281s
new failures: 0   known failures: 0   now passing: 0   stale entries: 0   malformed entries: 0   set errors: 0
logs: /tmp/regress.rxXfzT
pass NOT recorded: tracked changes or untracked rtl/ files, or HEAD moved during the run (push will be refused)
RESULT: PASS
```

### Text proposed for perf_decisions.md

PF-11, to replace "Not built by PERF-002 (it stated the gap); built by
PERF-003.":
  BUILT BY PERF-003 (--oracle). Each FTQ entry allocated at p1 is
  aligned with the trace. It is on the path when its PC is where a
  backend redirect sent fetch, or where the trace goes after its
  predecessor's predicted block (the fetch record once fetched, the
  entry before that; realigned at p2 and p3). For an entry on the path,
  perf_top forces bp_cluster's predictor outputs at p1 (r_ubtb_pred_p1,
  the loop predictor, the RAS top of stack), p2 (loop, TAGE, the FTB
  direction, conditional and jump targets, the RAS pop, ITTAGE's targets)
  and p3 (SC) to the trace's direction and target, each as a mux with
  the predictor's own value. perf.vlt keeps loop_pred, ftb, tage,
  ittage, sc and ras out of inlining, so that their ports read unforced.
  No file under rtl/ changes. Measured on six traces at 2e6: 0
  mispredicts on slot-held branches, except a branch followed in the
  trace by an exception entry, which THE VERDICT counts and which is
  counted apart (orc_slot_trap, 0 to 8 per run; Jeff, session-086).
  Misses: conditional, indirect and return; direct 0.

PF-18, replacing "RULED session-086 (Jeff), to be built by PERF-003:"
with "RULED session-086 (Jeff), BUILT by PERF-003:", and adding:
  - THE STAGES ARE BUILT: --decode-lat, --rename-lat, --dispatch-lat
    and --execute-lat, each its own random stream (execute keeps
    --resolve-lat's); --resolve-lat is removed.
  - THE FETCH RULE IS BUILT AND IS THE DEFAULT (--mispredict-rule
    fetch). The record is written at each accepted request (not in a
    flush cycle) and at each predecode correction. The verdict is read
    in the branch's resolve cycle, with that cycle's correction applied.
    The fetched stream is a check (err_stream, err_fetch_rule).
    Observed: no disagreement with the stream rule outside C1 to C3 in
    35 runs. The path's last branch is not judged.
  - THE NEAR-PERFECT DEFAULT IS NOT SET. In the sweep (S 0..8 by C
    0..8, six traces, 2e6) only (8, 8) meets the rule; return
    mispredicts do not settle on five traces (media_2 non-monotone;
    compress_1, infra_1 and int_6 rise with C). The default stays
    immediate. TD#207 stands.
  - A TRAP AFTER A BRANCH (the trace's next record an exception entry)
    counts as the branch's mispredict. OPEN: whether the branch should
    be judged on its own outcome, with the trap a separate RC_TRAP
    redirect as for non-branches.

PF-21, add: "WHAT PERF-003 BUILT: the CPU cap (PF-22); the resolution
target (a conditional resolves with its encoded taken target); the fetch
record and the fetch rule (PF-18); the oracle (PF-11); the backend
stages (PF-18); the sweep table perf/studies/perf003_p6_sweep_table.csv.
The take-time slot reading and err_predict are removed: err_predict was
predecode corrections reaching the entry after the take."

PF-22, replace "Built by PERF-003." with: "BUILT by PERF-003:
perf_study.py, perf_rerun.py, perf_traces.py (and veneer, which it runs,
and trace_count) and the perf Makefile's JOBS default to
max(1, floor(0.75 x hardware threads)); -j N (JOBS=N) sets N; each
prints the count it uses."

DIFFERENCES BETWEEN THE TASK AND THE DOCUMENT: none found that changed
the build.

## Assumptions made not explicit in the prompt
1. An accepted fetch request is ftq_ifu_req_val and _rdy in a cycle
   without ftq_ifu_flush_val, because ftq_ptr discards the handshake of
   a request presented with a flush (ftq_ifu.sv 341-348).
2. "The block's last instruction" (THE VERDICT) is the branch at pc + 4
   == next_pc when the record has no taken slot. A branch past its
   record's taken position or block end is counted (fr_beyond_taken; 0
   in every run).
3. A slot taken whose record PC is not start_pc + 2 x pos counts toward
   err_no_record.
4. "Hardware threads" is os.cpu_count() in Python, and
   std::thread::hardware_concurrency() and nproc elsewhere.
5. The oracle forces only the slots of entries on the path, and only at
   positions the trace reaches within the block. A slot at a position
   the trace does not reach keeps the predictor's value.

## Decisions made not explicit in the prompt
1. I applied the CPU cap to the perf Makefile's JOBS and to veneer and
   trace_count (perf_util.h) too, and added perf_traces.py --dry-run to
   demonstrate it without writing traces.
2. Every oracle force is of a whole variable or element (two member
   forces on one element do not both apply in this Verilator).
3. perf.vlt keeps six predictor modules out of inlining. This applies
   to every harness run, not only --oracle; the counts are unchanged.
4. TraceSupply keeps 4,096 retired records readable.
5. The stream rule's decided_by_slot fallback uses the record's verdict
   now that the take-time reading is removed.
6. The cause count for err_predict was made on a temporary pc8 build
   (one line of perf_fe.cc), deleted after.
7. Execute keeps --resolve-lat's random stream, so the moved sets
   reproduce their rows; the new stages take new streams.
8. p5.sets immediate names fixed:0 explicitly, so that it stays
   immediate whatever the default.
9. perf003_p4_fetch.csv, the first Problem 4 acceptance run, was deleted
   after the C3 fix. Its rows are rerun in perf003_p5_oracle.csv
   (immediate, latency) and perf003_p4_rules.csv. perf003_p4_rules.csv
   and perf003_p4_params.csv are reruns on the final build.
10. Problem 6's stage parameters were written while Problem 5 was being
    debugged. They are not a workaround for it. Problem 5's final runs
    used that build, and every oracle-off column equals Problem 4's
    except the C3 fix.

## RVA23 compliance risks and gaps noticed
None. The harness only.

## Deferred Work
1. A ruling on the near-perfect default (Problem 6): no point other than
   (8, 8) meets the rule.
2. A ruling on a trap after a branch: judge the branch on its own
   outcome, or keep counting the trap as its mispredict.
3. TD#207: the return mispredicts' timing dependence (media_2
   non-monotone, others rising with C), for the PA.
4. TD#208: mis_sc moves both ways after the target fix. Not
   investigated.
5. tools/known_failures.txt: nothing to propose; nothing failed.
6. The speed cost of no_inline was not measured on an idle machine.

## Other Notes
TOOL USE, against CLAUDE.md:
- The Grep tool was not available. Files were searched with grep -n
  through Bash, with literal paths.
- On scratch logs and CSVs I also used tail, awk, head, cut, wc, ls and
  grep -c through Bash (CLAUDE.md asks for Read). One awk read of
  regress output is covered by the summary reproduced above.
- Shell file operations: mv of the baseline CSV to perf003_ names; rm of
  perf/build/pc8_s2 and of perf003_p4_fetch.csv and its work directory;
  mkdir and rsync for the scratch RTL copy (source files only, *.sv
  *.svh *.mk *.vlt *.vh, into the scratchpad).
READS BEYOND THE LISTED CONTEXT:
- rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv and bp_defines_pkg.sv
  (grep for the predictor struct fields and widths the forces need);
- rtl/Vars.mk (grep for the Verilator path);
- prompts/PERF-002.md lines 1500-1540 and 1600-1720 (Problem 4 and
  speed text) besides Deferred Work 7 and Other Notes;
- the scratch copy read all of rtl/ (rsync).
No git command was run. regress.sh and the build's rev-parse ran their
own.
VERILATOR FINDINGS (for the oracle; recorded above): circular forces
through inlined ports, release keeping the forced value, force in
always_comb ignored, one member force per element, and a comment line
starting with that word read as a pragma (hit in perf.vlt and in a
scratch test).
The scratch ftb512 tree sets FTB_ENTRIES 512 in
bp_defines_pkg.sv:172 of the copy only.

## Files Modified
- perf/Makefile
- perf/sv/perf_top.sv
- perf/sv/perf.vlt
- perf/src/perf_util.h
- perf/src/veneer.cc
- perf/src/harness/perf_fe.cc
- perf/src/harness/supply.h
- perf/src/harness/supply.cc
- perf/src/harness/rv_encode.h
- perf/studies/p4_params.sets
- perf/studies/p5.sets
- perf/studies/perf003_p1_demo.sets
- perf/studies/perf003_p4.sets
- perf/studies/perf003_p4_causes.sets
- perf/studies/perf003_p5.sets
- perf/studies/perf003_p6_stages.sets
- perf/studies/perf003_p6_sweep.sets
- perf/studies/perf003_p0_baseline.csv
- perf/studies/perf003_p2_target.csv
- perf/studies/perf003_p3_observe.csv
- perf/studies/perf003_p3_params.csv
- perf/studies/perf003_p4_causes.csv
- perf/studies/perf003_p4_rules.csv
- perf/studies/perf003_p4_params.csv
- perf/studies/perf003_p5_oracle.csv
- perf/studies/perf003_p6_stages.csv
- perf/studies/perf003_p6_sweep.csv
- perf/studies/perf003_p6_sweep_table.csv
- perf/studies/perf003_*_work/
- perf/build/head_s2/
- perf/build/ftb512_s2/
- perf/build/veneer
- perf/build/trace_count
- tools/perf_study.py
- tools/perf_rerun.py
- tools/perf_traces.py
- tools/scan_traces.py
- README.md
- prompts/PERF-003.md

:: RESULTS:END ::

:: CONTEXT:START ::
# Context Usage
Compactions: 0
Run time: 1h.25m.33s active, 2h.35m.52s wall (2026-11-18T17:31:37Z -> 2026-11-18T20:07:30Z, /run PERF-003)

**Model:** claude-opus-5-5
**Tokens:** 823k / 1m (82%)

### Estimated usage by category

| Category | Tokens | Percentage |
|----------|--------|------------|
| System prompt | 3k | 0.3% |
| System tools | 21.1k | 2.1% |
| MCP server instructions | 39 | 0.0% |
| MCP tools (deferred) | 1.2k | 0.1% |
| System tools (deferred) | 30.3k | 3.0% |
| Memory files | 6.6k | 0.7% |
| Skills | 6k | 0.6% |
| Messages | 786.3k | 78.6% |
| Free space | 144k | 14.4% |
| Autocompact buffer | 33k | 3.3% |

### Other MCP tools, by server

| Server | Tools | Tokens if all were loaded |
|--------|-------|---------------------------|
| easel | 1 | 1.2k |

### Memory Files

| Type | Path | Tokens |
|------|------|--------|
| Project | /home/jeff/Development/jeffnye-gh/pacino/CLAUDE.md | 4.7k |
| AutoMem | /home/jeff/.claude/projects/-home-jeff-Development-jeffnye-gh-pacino/memory/MEMORY.md | 1.9k |

### Skills

| Skill | Source | Tokens |
|-------|--------|--------|
| dataviz | Built-in | ~480 |
| code-review | Built-in | ~400 |
| claude-api | Built-in | ~390 |
| docs | claude.ai sync | ~340 |
| pptx | claude.ai sync | ~330 |
| google-workspace | claude.ai sync | ~330 |
| xlsx | claude.ai sync | ~320 |
| computer-use | claude.ai sync | ~320 |
| docx | claude.ai sync | ~320 |
| built-in-browser | claude.ai sync | ~290 |
| and 22 more |  | ~2.4k |
:: CONTEXT:END ::
