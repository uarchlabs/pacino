<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Project Status -- RISC-V RVA23 Processor Co-Design
```
 FILE:    PROJECT_STATUS.md
 SOURCE:  various
 STATUS:  WORKING
 UPDATED: 2026-08-19 (during ia interactive sessions)
 CONTACT: Jeff Nye
```

Updated every session. Paste into Claude.ai at session start,
along with the latest session_handoff-NNN.md and CLAUDE.md.

Paste PROJECT_CORE.md only when methodology is under discussion.

---

## IA interactive sessions: FTQ definition. Two RTL tasks, four interfaces.

The FTQ is specified end to end. Three of its four interfaces are
written; the fourth is deliberately not.

```
  BP-098  INST_OFFSET split -> PC_HASH_SHIFT + POS_OFFSET_BITS
  BP-099  FTB_BR_POS_BITS 3 -> 4, closing an RVA23 C-extension gap
  BP-100  FTB update scheduler. SPEC ONLY, no RTL written
  BP-101  pft_addr, the TD-FE-6 slot groups, RESET_VECTOR
```

New: ftq_decisions.md, ftq_entry_formats.md, ftq_ifu_interfaces.md,
ftq_backend_interfaces.md. The FTQ entry had been described in three
places and edited in lockstep; fe_decisions sections 4, 5 and 6 moved
out and are RETIRED, not reused, so cross-references still resolve.

Two defects, both found by writing down what the FTQ would have to
drive:

```
  TD-FE-6  CLOSED. The FTB classification and in-block positions
           reached no FTQ-facing port, so update fan-out read
           NO_BRANCH for any block the uBTB missed -- the case
           where training matters most.
  TD-FE-7  OPEN. bp_cluster has no rollback TRIGGER input. The
           checkpoints are all inside bp_history; only the index
           is missing on a backend redirect. Seven bits.
```

RULE: a predictor training path must not be able to stall the
machine. FE-5 promised updates like architectural state; FE-5a
narrows it to permit dropping low-value FTB updates (G9,
IC-FTB-09, ftq_decisions.md 5.7).

Counts, 47 of 47 green throughout:

```
  sim_bp_cluster   973 -> 997 (BP-101) -> 1765 (BP-099)
  sim               28 ->  29 (BP-101)
  all others            unchanged
```

Two deferrals, NOT the same kind. ftq_icache is physical and the PD
phase can undo it. Instruction prefetch is functional and PD cannot:
it needs the FTQ run-ahead, which the IFU is behind by construction
(ftq_decisions.md 6.1).

CLOSED: TD-FE-1, TD-FE-2, TD-FE-6, FE-U2, FE-U7, G9, G23,
IC-FTB-09, RESETVEC.
NEW: TD-FE-7, FE-5a, FE-13, IC-FTB-16, PREFETCH.

Next free BP number is BP-102. Next free INFRA number is INFRA-013.

---

## Session-066: BP-097. Record repair, watchdog class reopened.

One task: BP-097. No RTL changed. 47 of 47 bpu targets green in
baseline and final, both from this session.

Two defects, both counted-or-armed but inert:

1. tb_bp_cluster D2 checked !$isunknown of three queue-status bits.
   Two-state model, so the condition was constant and the check
   could not fail. Same defect BP-094 removed from A3. All 450
   check sites enumerated; this was the only survivor. Replaced
   with the required value, sampled every cycle. Count unchanged
   at 973, proven to fail when mutated.

2. TD#111 was closed on the four files it named. A sweep of all 18
   found three with no watchdog (tb_tage, tb_loop_pred,
   tb_bp_history) and one, tb_bp_cluster, whose watchdog could not
   fire: repeat (200000) @(posedge clk). Measured -- clock frozen,
   run hung, make never returned. Four repaired time-based, each
   proven both directions.

RULE: a watchdog is a TIME delay, never a cycle count.

Record corrections: `all` names 38 of 47, not 37; TD#100 figures
re-measured; TD#109 second paragraph (tage_assert_inhibit WAS
declared -- the fault was bind scope resolution); TD#109 and TD#110
recorded closed by BP-096; CLI-011 confirmed; sim_tage_manual "3/3"
withdrawn.

Negative results: no planning document carries 407; no document
describes the tree as containing bp_loop_meta_t; BP-094.md already
accounted for the 278-check growth in groups A-F, per group.

CLOSED this session: TD#111. TD#109 and TD#110 closed BP-096.

Next free BP number is BP-098. Next free INFRA number is INFRA-012.

---

## Session-065: BP-096. Bind sweep, 407 vs 973.

Not recorded at the time. Summarised from handoff-066 and verified
against the tree by BP-097.

One task: BP-096. Swept every bind in the unit -- five across 46
files, four already correct -- and repaired tb_tage.sv (TD#109). The
dead-bind class is BOUNDED at two instances, that one and
tb_tage_manual.sv (BP-095). Added four watchdogs (TD#111,
incompletely -- see session-066), added tage_assert.sv to the
cov_tage compile, fixed a concealed stimulus defect in tb_tage.sv
sub-test C, and deleted ittage_assert_bind.sv (TD#110; the deletion
was ordered by the prompt and never authorised by Jeff). Settled 407
vs 973: one run of one binary, 407 printed PASS lines, 973 checks.
All 47 targets green.

---

## Session-064: bp_cluster simulated. Three defects found by running.

tb_bp_cluster.sv exists. 973 self-checking assertions, groups A
through H. bp_cluster.sv is at 258/258 line coverage. All 47 bpu
Makefile targets are green: 18 lint, 22 sim, 7 cov.

Three defects were found by running things that had never been run.

1. tage_cntrl.sv read branch_id LIVE off its p0 input while building
   p1 metadata, so the branch_id arriving at p2 named the request one
   cycle later than the rest of the metadata described. At the cluster
   boundary this defeated the branch_id qualification: in an unstalled
   stream the TAGE direction and the SC correction never reached the
   FTQ at all; in a stalled stream the guard matched the WRONG entry.
   FIXED BP-094. Invisible to every unit suite because none varied
   branch_id across requests.

2. SEVEN TESTBENCHES COULD NOT FAIL. $finish and $finish(1) both
   produce exit 0 under Verilator v5.048, so a failing run reported a
   passing target. BP-086 found this in tb_ubtb, BP-094 in tb_tage,
   BP-095 swept the remaining five. Every count turned out correct --
   none changed -- but none had ever been ENFORCED. All fixed to
   $fatal(1) and proven in both directions by measurement.

3. tb_tage.sv binds tage_assert to an INSTANCE name (bind u_dut)
   rather than a module name. Verilator accepts it, instantiates
   nothing, warns about nothing under -Wall. tage_assert is not
   evaluated in sim_tage, sim_tage_fast, lint_tage or cov_tage. The
   identical defect in tb_tage_manual.sv was fixed by BP-095. THIS ONE
   IS OPEN and is the first item of session-065.

Tasks run: BP-091 (loop_pred dual-slot retrofit), BP-092 (retire
bp_loop_meta_t, add p1 fall-through), BP-092a (per-slot branch PC
fix), BP-093 (tb_bp_cluster, groups A-F), BP-094 (branch_id staging
fix, groups G and H), BP-095 (failure-exit sweep).

Four planning documents were corrected directly by the PA and pasted
by Jeff rather than through an IA task: bp_history_interfaces.md,
ftq_bpu_interfaces.md, fe_decisions.md, bp_arb_spec.md.

CLOSED this session: TD#105, TD#106, TD#107, TD#108.
NEW: TD#109 (dead assertion bind), TD#110 (ittage_assert_bind.sv
compiled by no target), TD#111 (four testbenches have no watchdog).

---

## Session-063: bp_cluster built. BPU green, cluster unverified.

bp_cluster.sv now instantiates all eight modules (seven predictors
plus bp_history), wires p0 through p3, and carries the full
prediction and update behaviour. All 45 bpu Makefile targets pass:
18 lint, 21 sim, 6 cov.

NOTHING IN bp_cluster HAS EVER BEEN SIMULATED at the time this
section was written. Superseded by session-064: it is simulated now.

Tasks run: INFRA-011 (port inventory), BP-082 (package dual-slot
entry, found already applied), BP-083 (tb_bp_pkg retrofit), BP-084
(cluster structural top), BP-085 (cluster behavioural), BP-086 (uBTB
block-descriptor rewrite), BP-090 (cluster rewire + metadata ports +
tb and comment closure).

BP-087, BP-088 and BP-089 were ABANDONED, all three for incomplete
specification by the PA. None of their RTL reached the tree. BP-090
was written against the tree state and closed the work in one run.
See session_handoff-064.md postmortem.

New planning documents:
  planning/interfaces/bpu_port_inventory.md   (INFRA-011)
  planning/interfaces/ftq_bpu_interfaces.md   FTQ/BPU port spec
  planning/interfaces/ubtb_interfaces.md      rewritten

New TDs: #105 (loop_pred dual-slot retrofit).
CLOSED: #91, #92 (SC PC and phr staged p0->p2 in bp_cluster).

---

## Session-061: Planning Document Audit (INFRA-008/009/010)

Before starting bp_cluster top-level design, three read-only IA
audits checked the FTB, TAGE/SC, and ITTAGE/RAS planning documents
against the shipped RTL/tb/Makefile for each group:

  INFRA-008 (ftb):        clean, no issues found.
  INFRA-009 (tage, sc):   12 findings, all doc drift, all fixed.
  INFRA-010 (ittage, ras): 10 findings -- 8 doc drift (fixed) plus
                            2 real design/RTL gaps, each resolved by
                            a Jeff ruling (doc fixed this session,
                            RTL-side gap opened as a new TD):
    - Indirect-CALL ownership: ITTAGE predicts the target, RAS
      separately pushes the return address. Both are in scope for
      indirect CALL, each for a different job. ittage_interfaces.md
      corrected (previously said RAS "exclusively").
    - ITTAGE IT5: NOT a BrIMLI table. The "BrIMLI, no folds" framing
      in bp_history_decisions.md and bp_cluster.md was a copy-paste
      artifact from SC's real BrIMLI table (ST4). IT5 has real
      folded history (FH=9b, FH1=9b, FH2=8b, hist=32b, per
      bp_defines_pkg.sv, which was already correct). Docs corrected.
      RTL gap (bp_history.sv never generates the IT5 folds it's
      wired to) opened as TD #102.

New TDs opened session-061: #101 (ras.sv ras_pc_p2 dead/undocumented
port), #102 (bp_history.sv missing IT5 fold generation), #104 (two
stale RTL comments found during INFRA-008, see Technical Debt table).

CONFLICT TO RESOLVE: TD#103 (added by Jeff, tage T0 init value) states
T0 should initialize to weakly-taken (2'b10) and that the current
00 (strongly-not-taken) init is a bug. INFRA-009 that same session
corrected tage_cntrl_decisions.md's T0 init description FROM "10" TO
"00" -- that correction was made to match CURRENT RTL/package behavior
(TAGE_SRAM_INIT_VALUE=0 in bp_defines_pkg.sv), not to assert 00 is the
intended value. The doc now accurately describes what the RTL does
today, which TD#103 says is wrong. When TD#103 is resolved (RTL and/or
TAGE_SRAM_INIT_VALUE changed to 2), tage_cntrl_decisions.md's T0 init
line must be updated again to match. Do not treat the session-061 doc
correction as having settled the "what should T0 init to" question --
it only documented current behavior.

---

## Module Status

| Module                  | Status      | Tests             | Notes                            |
|-------------------------|-------------|-------------------|----------------------------------|
| predecode.sv            | Complete    | tb_predecode      | clk/rstn unused (debt #4)        |
| instr_decoder.sv        | Complete    | tb_instr_decoder  | 1043 passing                     |
| rvc_expander.sv         | Complete    | tb_rvc_expander   |                                  |
| decode_pkg.sv           | Complete    | --                | All decode structs               |
| bp_defines_pkg.sv       | Complete    | tb_bp_pkg         | TAGE and ITTAGE parameters       |
|                         |             |                   | complete. IT_TBL_TGT_WIDTH added.|
|                         |             |                   | RAS params added BP-062:         |
|                         |             |                   | RAS_SPEC_ENTRIES=16,             |
|                         |             |                   | RAS_COMMIT_ENTRIES=32,           |
|                         |             |                   | RAS_RCTR_WIDTH=4, RAS_PTR_BITS=4,|
|                         |             |                   | RAS_COMMIT_PTR_BITS=5.           |
|                         |             |                   | FTB params added/fixed BP-065/   |
|                         |             |                   | 065a/066a (FTB_WAYS=4, widths,   |
|                         |             |                   | conf init, FTB_RAM_*).           |
|                         |             |                   | SC params session-056:           |
|                         |             |                   | SC_NUM_TABLES=5 (SC_NUM_ALL_TBLS |
|                         |             |                   | removed); dynamic threshold      |
|                         |             |                   | SC_THRSH_BITS/MIN/MID/MAX,        |
|                         |             |                   | SC_TC_BITS, SC_LSUM_BITS,         |
|                         |             |                   | SC_CHOOSER_*; SC_LO/HI_THRESHOLD  |
|                         |             |                   | removed (now dynamic).           |
|                         |             |                   | Threshold values corrected       |
|                         |             |                   | session-057: SC_THRSH_BITS=10,   |
|                         |             |                   | SC_THRSH_MID=10, SC_THRSH_MAX=   |
|                         |             |                   | 512, SC_TC_BITS=7 (O-GEHL).      |
|                         |             |                   | SC arb params: SC_UQ_DEPTH,      |
|                         |             |                   | SC_UQ_WR_PORTS, SC_RESP_BUF_     |
|                         |             |                   | DEPTH, SC_PRED_CREDITS, SC_UPD_  |
|                         |             |                   | CREDITS, SC_STARVE_THRESH; no    |
|                         |             |                   | SC_PQ_DEPTH.                     |
|                         |             |                   | SESSION-063: uBTB block params   |
|                         |             |                   | added and MOVED below the FTB    |
|                         |             |                   | section (they derive from the    |
|                         |             |                   | FTB values): UBTB_BLOCK_BYTES,   |
|                         |             |                   | UBTB_OFFSET_BITS,                |
|                         |             |                   | UBTB_BR_POS_BITS,                |
|                         |             |                   | UBTB_PFTADDR_BITS,               |
|                         |             |                   | UBTB_BR_TGT_BITS,                |
|                         |             |                   | UBTB_JMP_TGT_BITS,               |
|                         |             |                   | UBTB_CONF_WIDTH, INIT_TKN/NTK,   |
|                         |             |                   | UBTB_ENTRY_WIDTH=100,            |
|                         |             |                   | UBTB_SET_WIDTH=400. Index/tag    |
|                         |             |                   | comment corrected off PC[26:7]   |
|                         |             |                   | to block granularity (BP-090).   |
|                         |             |                   | SESSION-064: FTB_BR_POS_BITS =   |
|                         |             |                   | $clog2(FTB_BLOCK_BYTES/4), i.e.  |
|                         |             |                   | positions are 4-byte expanded-   |
|                         |             |                   | instruction slots, 8 per block.  |
|                         |             |                   | Confirmed BP-092a, not changed.  |
| bp_structs_pkg.sv       | Complete    | tb_bp_pkg         | TAGE and ITTAGE structs complete.|
|                         |             |                   | IT5 fold fields present in       |
|                         |             |                   | struct (II1); generation gap in  |
|                         |             |                   | bp_history.sv tracked TD#102.    |
|                         |             |                   | SC structs session-056/057/058.  |
|                         |             |                   | Session-060 BP-081: tage_pred_   |
|                         |             |                   | weak re-added; tage_high_conf/   |
|                         |             |                   | tage_provider_ctr absent.        |
|                         |             |                   | SESSION-063:                     |
|                         |             |                   | bp_ftq_entry_t split into block- |
|                         |             |                   | scalar fields plus a per-slot    |
|                         |             |                   | bp_ftq_slot_t[NUM_PRED_SLOTS-1:0]|
|                         |             |                   | array (BP-082, commit 2b60115).  |
|                         |             |                   | bp_ftq_slot_t gains pos          |
|                         |             |                   | (FTB_BR_POS_BITS) for the        |
|                         |             |                   | in-block branch position.        |
|                         |             |                   | ftb_pred_meta_t added (hit, way, |
|                         |             |                   | jmp_pos); bp_ftq_meta_t gains an |
|                         |             |                   | ftb member so the FTB carried    |
|                         |             |                   | writeWay travels in the struct.  |
|                         |             |                   | bp_redirect_t: ftq_idx removed   |
|                         |             |                   | (scalar at the port beside the   |
|                         |             |                   | per-slot array); s2/s3 comments  |
|                         |             |                   | to p2/p3.                        |
|                         |             |                   | uBTB types reshaped to the FTB   |
|                         |             |                   | entry form: ubtb_cond_t (22b),   |
|                         |             |                   | ubtb_jmp_t (30b), ubtb_entry_t   |
|                         |             |                   | (100b), ubtb_blk_t new,          |
|                         |             |                   | ubtb_pred_t gains pos and conf,  |
|                         |             |                   | ubtb_upd_t reshaped to mirror    |
|                         |             |                   | the FTB update port (13 fields;  |
|                         |             |                   | br_type and carry REMOVED).      |
|                         |             |                   | branch_id comments corrected to  |
|                         |             |                   | "FTQ entry index" (TD-FE-5);     |
|                         |             |                   | bp_pred_src_e stage labels to    |
|                         |             |                   | p1/p2/p3.                        |
|                         |             |                   | SESSION-064 BP-092: TD#106       |
|                         |             |                   | closed. bp_loop_meta_t DELETED;  |
|                         |             |                   | bp_ftq_meta_t's lp member is now |
|                         |             |                   | lp_pred_t. Both types were 80    |
|                         |             |                   | bits, 13 fields, identical       |
|                         |             |                   | widths -- the map was pure       |
|                         |             |                   | reorder and rename. lp_pred_t's  |
|                         |             |                   | typedef MOVED up the file (SV    |
|                         |             |                   | declare-before-use); fields      |
|                         |             |                   | unchanged.                       |
| bp_pkg.sv               | Deprecated  | --                | Deleted.                         |
| bp_history.sv           | Complete    | tb_bp_history     | Module-owned pointer (BP-069).   |
|                         |             |                   | Fold geometry corrected (BP-071);|
|                         |             |                   | increment-oriented walk +        |
|                         |             |                   | post-advance ckpt (BP-072).      |
|                         |             |                   | Dual-slot fold equivalence proven|
|                         |             |                   | in-sim (TD #74, BP-072): 16 TCs, |
|                         |             |                   | 19224 golden comparisons.        |
|                         |             |                   | External fold anchor TC14-16     |
|                         |             |                   | (BP-073). Canonical fold def in  |
|                         |             |                   | decisions.md s6; doc-RTL         |
|                         |             |                   | verified (BP-074).               |
|                         |             |                   | See BUG-004 / BUG-005.           |
|                         |             |                   | Session-061 (INFRA-010): IT5     |
|                         |             |                   | fold generation MISSING. TD#102. |
|                         |             |                   | Session-063: driven from the     |
|                         |             |                   | cluster's formed p1 prediction;  |
|                         |             |                   | pred_taken/pred_pc compacted by  |
|                         |             |                   | branch number, not slot number.  |
|                         |             |                   | SESSION-064: pred_pc is the      |
|                         |             |                   | BRANCH PC (block base + pos*4),  |
|                         |             |                   | not the fetch block PC -- BP-092a|
|                         |             |                   | fixed the cluster side, proven   |
|                         |             |                   | BP-093 TC-A..TC-G. A block-      |
|                         |             |                   | aligned PC would make the PHR    |
|                         |             |                   | path bit a constant.             |
|                         |             |                   | Watchdog added BP-097.           |
| bp_history_decisions.md | Draft       | --                | Created session-054. Resolves    |
|                         |             |                   | G20/G21/G22. s6 canonical Fold   |
|                         |             |                   | Definition (session-055). s7     |
|                         |             |                   | checkpoint POST-advance.         |
|                         |             |                   | Session-061: IT5 BrIMLI/no-folds |
|                         |             |                   | claim removed. Header still      |
|                         |             |                   | DRAFT pending s6.6 sha + HI2/HI5.|
| bp_history_interfaces.md| Draft       | --                | Rewritten session-054. Checkpoint|
|                         |             |                   | Timing consistent with s7        |
|                         |             |                   | (BP-074). SESSION-064: pred_pc   |
|                         |             |                   | producer obligation CORRECTED to |
|                         |             |                   | branch PC; ports restated per    |
|                         |             |                   | BRANCH not per slot; bp_pkg.sv   |
|                         |             |                   | refs fixed; caller-owned-pointer |
|                         |             |                   | target-state note retired; IT5   |
|                         |             |                   | "no folds" claim replaced with   |
|                         |             |                   | real geometry + TD#102. HI6, HI7 |
|                         |             |                   | opened.                          |
| ubtb.sv                 | Complete    | tb_ubtb           | SESSION-063 BP-086: REWRITTEN to |
|                         |             | sim_ubtb          | the single-lookup block          |
|                         |             |                   | descriptor model. One index, one |
|                         |             |                   | tag, one way search from         |
|                         |             |                   | pred_pc_p0; the matched entry    |
|                         |             |                   | supplies every slot. The         |
|                         |             |                   | pred_pc_p0 + 32 slot-1 lookup is |
|                         |             |                   | GONE. New blk_p1 output          |
|                         |             |                   | (ubtb_blk_t): entry hit and      |
|                         |             |                   | reconstructed fall-through.      |
|                         |             |                   | Target encode/reconstruct,       |
|                         |             |                   | fall-through reduce/reconstruct  |
|                         |             |                   | and the bimodal step ported from |
|                         |             |                   | ftb_cntrl against UBTB widths.   |
|                         |             |                   | Round-robin replacement and the  |
|                         |             |                   | single array retained.           |
|                         |             |                   | sim_ubtb 259/0, cov_ubtb 98.6%.  |
|                         |             |                   | Mutation tested, 5 injected      |
|                         |             |                   | defects, all caught.             |
|                         |             |                   | CLI-012 port naming retrofit now |
|                         |             |                   | reflected in the doc.            |
| ubtb_interfaces.md      | Draft       | --                | SESSION-063: REWRITTEN for the   |
|                         |             |                   | single-lookup model. UI1 closed  |
|                         |             |                   | (pred_pc+32 retired). UI4 closed |
|                         |             |                   | (a hit with no valid slot is the |
|                         |             |                   | no-branch state; successor is    |
|                         |             |                   | blk_p1.pft_addr; no sentinel).   |
|                         |             |                   | Port names carry stage suffixes. |
|                         |             |                   | UI2 (carry consumer) and UI3     |
|                         |             |                   | (both channels one entry) remain.|
| loop_pred.sv            | Complete    | tb_loop_pred      | BP-004c-f complete.              |
|                         |             |                   | SESSION-064 BP-091: TD#105       |
|                         |             |                   | CLOSED. Per-slot on pred_pc_p0,  |
|                         |             |                   | pred_valid_p0, pred_p1, upd_p0   |
|                         |             |                   | and upd_valid_p0; tables are     |
|                         |             |                   | per-slot banks (TI6) in one      |
|                         |             |                   | one-level generate loop; pred_p0 |
|                         |             |                   | RENAMED pred_p1. Algorithm and   |
|                         |             |                   | lp_pred_t unchanged. Elaborates  |
|                         |             |                   | at NUM_PRED_SLOTS 1 and 2.       |
|                         |             |                   | sim_loop_pred 9342/0 (TC1-TC18); |
|                         |             |                   | 8 mutants, all caught after two  |
|                         |             |                   | coverage holes were closed.      |
|                         |             |                   | CLI-011 CONFIRMED SATISFIED      |
|                         |             |                   | BP-097 against loop_pred.sv      |
|                         |             |                   | 51-57: every port carries a      |
|                         |             |                   | _<pipestage> suffix and no       |
|                         |             |                   | pred_p0 remains in the bpu RTL.  |
|                         |             |                   | CLOSED_TECH_DEBT row 12 credits  |
|                         |             |                   | BP-018, not BP-091. Nothing      |
|                         |             |                   | pending. Watchdog added BP-097.  |
| loop_pred_interfaces.md | Draft       | --                | SESSION-064 BP-091: corrected to |
|                         |             |                   | the delivered ports. 17 doc-vs-  |
|                         |             |                   | RTL findings recorded before any |
|                         |             |                   | change. LI1, LI2, LI3 CLOSED.    |
|                         |             |                   | Reset State and Victim Selection |
|                         |             |                   | sections added (neither existed).|
|                         |             |                   | LI6 opened then CLOSED BP-092.   |
|                         |             |                   | The retired pred_pc+32 model was |
|                         |             |                   | still described here -- the third|
|                         |             |                   | document found carrying it.      |
| tage_interfaces.md      | Complete    | --                | session-036: 6 corrections.      |
|                         |             |                   | Session-061 (INFRA-009): strong/ |
|                         |             |                   | medium/weak and extd_ctr         |
|                         |             |                   | corrections. SESSION-064 BP-094: |
|                         |             |                   | Metadata timing section ADDED -- |
|                         |             |                   | every tage_pred_meta_t member,   |
|                         |             |                   | branch_id included, describes the|
|                         |             |                   | request that produced it and is  |
|                         |             |                   | staged to p2 together.           |
| tage_table_interfaces.md| Draft       | --                | Created session-016.             |
|                         |             |                   | Updates pending.                 |
| tage_cntrl_use          | Complete    | --                | session-037/045.                 |
| _update_rules.md        |             |                   |                                  |
| tage_cntrl_uaon         | Complete    | --                | Session-060: reconciled to TD#87 |
| _update_rules.md        |             |                   | (UAON gate on tage_pred_weak).   |
| tage_cntrl              | Complete    | --                | session-044/045.                 |
| _ctr_update_rules.md    |             |                   |                                  |
| tage_cntrl_decisions.md | Complete    | --                | Session-061 (INFRA-009): T0 RAM  |
|                         |             |                   | index pc[11:1] -> pc[12:2]; T0   |
|                         |             |                   | init corrected to 00 to MATCH    |
|                         |             |                   | CURRENT RTL (see TD#103 conflict,|
|                         |             |                   | top of file).                    |
| bw_ram / sat_alu        | Complete    | tb_components     | COMP-001 PASS                    |
| dual_lm1                | Complete    | tb_components     | COMP-002 now uses generate       |
| sram_init               | Complete    | tb_components     | COMP-003                         |
| tage_hash.sv            | Complete    | tb_tage_hash      | BP-006 abandoned.                |
| tage_table.sv           | Complete    | tb_tage_table     | BP-007 through BP-012 complete.  |
|                         |             |                   | Signal naming debt #17 pending.  |
| tage_bim.sv             | Complete    | --                | BP-009b complete.                |
| tage_cntrl.sv           | Complete    | --                | BP-008a/b, BP-012, BP-045.       |
|                         |             |                   | BUG-003 fixed BP-057.            |
|                         |             |                   | Session-060 BP-081: TD#87 decode |
|                         |             |                   | + TD#88 extd_ctr generated.      |
|                         |             |                   | TD#103 OPEN: T0 init value.      |
|                         |             |                   | SESSION-064 BP-094: branch_id    |
|                         |             |                   | now STAGED p0->p1 into           |
|                         |             |                   | branch_id_r1[] alongside the     |
|                         |             |                   | index/tag hashes. It was the ONLY|
|                         |             |                   | meta_p1 member read live off p0. |
|                         |             |                   | No port, struct or other member  |
|                         |             |                   | timing changed.                  |
| tage.sv                 | Complete    | tb_tage           | BP-056 through BP-061 complete.  |
|                         |             |                   | Session-060 BP-081: FIFOs retyped|
|                         |             |                   | off cond_pred_*.                 |
|                         |             |                   | SESSION-064: sim_tage 106/0,     |
|                         |             |                   | sim_tage_fast 106/0, from a      |
|                         |             |                   | harness that can now fail.       |
| tage_assert.sv          | Complete    | sim_tage          | ADR-001 and row 18 assertions.   |
|                         | BOUND, LIVE | sim_tage_fast     | TD#109 CLOSED BP-096: the bind   |
|                         |             | sim_tage_tasks    | named an INSTANCE (bind u_dut)   |
|                         |             | sim_tage_manual   | and instantiated nothing. Now    |
|                         |             |                   | "bind tage", with                |
|                         |             |                   | tb.tage_assert_inhibit on the    |
|                         |             |                   | port. BP-096 also added the file |
|                         |             |                   | to the cov_tage compile.         |
|                         |             |                   | BP-097: 10/10 lines in cov_tage; |
|                         |             |                   | a firing assert...else $error    |
|                         |             |                   | exits non-zero, measured.        |
| ittage_assert.sv        | Complete    | sim_ittage        | New session-045. Bound inline in |
|                         |             |                   | tb_ittage.sv and LIVE. The       |
|                         |             |                   | separate ittage_assert_bind.sv   |
|                         |             |                   | (TD#110) was deleted BP-096.     |
| tb_tage.sv              | Complete    | sim_tage          | SESSION-064 BP-094: failure exits|
|                         |             | sim_tage_fast     | $finish(1) -> $fatal(1). Before  |
|                         |             |                   | that the whole file was ungated. |
|                         |             |                   | Varying-branch_id test added,    |
|                         |             |                   | proven to fail against unfixed   |
|                         |             |                   | RTL. TD#109 CLOSED BP-096: the   |
|                         |             |                   | bind now names the MODULE. The   |
|                         |             |                   | claim that tage_assert_inhibit   |
|                         |             |                   | was undeclared is FALSE -- it is |
|                         |             |                   | at line 259 and predates BP-096  |
|                         |             |                   | (BP-097, verified to ea6e917).   |
|                         |             |                   | Watchdog added BP-097.           |
| tb_tage_manual.sv       | Complete    | sim_tage_manual   | ctr rows 1-17, use rows 1-6.     |
|                         |             |                   | SESSION-064 BP-095: printed NO   |
|                         |             |                   | verdict at all before this task; |
|                         |             |                   | one was added and it now gates.  |
|                         |             |                   | Assert bind repaired to the      |
|                         |             |                   | module name and proven live.     |
|                         |             |                   | The prior "3/3" is WITHDRAWN --  |
|                         |             |                   | never produced by the harness.   |
|                         |             |                   | MEASURED BP-097: the only figure |
|                         |             |                   | it reports is "RESULTS: 0        |
|                         |             |                   | error(s)". It counts errors, not |
|                         |             |                   | checks. Watchdog #5000 BP-096.   |
| ittage_interfaces.md    | Draft       | --                | Session-061 (INFRA-010):         |
|                         |             |                   | indirect-CALL ownership and IT5  |
|                         |             |                   | corrections. SESSION-064 BP-094: |
|                         |             |                   | Metadata timing section added;   |
|                         |             |                   | ITTAGE was INSPECTED for the     |
|                         |             |                   | branch_id defect and does not    |
|                         |             |                   | have it -- the property is now   |
|                         |             |                   | specified rather than accidental.|
| ittage_table_interfaces.md| Draft     | --                | Session-061 (INFRA-010): "4 total|
|                         |             |                   | writes" and tgt_wr_u0 split      |
|                         |             |                   | corrections.                     |
| ittage_cntrl_alloc_rules.md| Complete | --                | Session-061: write-data field    |
|                         |             |                   | order corrected.                 |
| ittage_cntrl_ctr_update_rules.md| Complete| --           | session-045: 33-row table.       |
| ittage_cntrl_decisions.md| Complete   | --                | session-036/037/038.             |
| ittage_cntrl_uaon_update_rules.md| Complete| --          | Promoted Complete BP-051.        |
| ittage_cntrl_use_update_rules.md| Complete| --           | session-045 corrections.         |
| ittage_table_hash_rules.md| Complete  | --                | Fold CONSUMPTION only.           |
| ittage_table_entry_formats.md| Complete| --               | Session-061: TAG width param     |
|                         |             |                   | corrected.                       |
| ittage_table.sv         | Complete    | tb_ittage_table   | BP-033/033-FIX-1 complete.       |
|                         |             |                   | sim_ittage_table 32/0, ENFORCED  |
|                         |             |                   | from BP-095 (harness fixed and   |
|                         |             |                   | watchdog now fatal).             |
| ittage_cntrl.sv         | Complete    | tb_ittage_cntrl   | BP-034/035/036/044/048/051-053.  |
|                         |             |                   | 147 tests passing, ENFORCED from |
|                         |             |                   | BP-095. Confirmed BP-094 to      |
|                         |             |                   | already stage branch_id p0->p1;  |
|                         |             |                   | it does NOT have the tage defect.|
| ittage.sv               | Complete    | tb_ittage         | sim_ittage 211/0, ENFORCED from  |
|                         |             |                   | BP-095. Two wait-loop timeouts   |
|                         |             |                   | converted from WARN-and-continue |
|                         |             |                   | to counted failures.             |
|                         |             |                   | Session-061: IT5 fold ports wired|
|                         |             |                   | to bp_history outputs never      |
|                         |             |                   | driven (permanently 0). TD#102.  |
| ras_decisions.md        | Draft       | --                | Created session-050. G5/G6/G8/G17|
|                         |             |                   | recorded. Session-061:           |
|                         |             |                   | RAS_COMMIT_PTR_BITS correction.  |
| ras_interfaces.md       | Draft       | --                | Created session-050. Session-061:|
|                         |             |                   | ras_pc_p2 documented (TD#101).   |
| ras.sv                  | Complete    | tb_ras            | RTL BP-062, tb BP-063.           |
|                         |             |                   | sim_ras 87/0.                    |
|                         |             |                   | TD #78 pinned, TD #79 deferred.  |
|                         |             |                   | TD#101 OPEN: ras_pc_p2 declared, |
|                         |             |                   | unread. Session-063: the cluster |
|                         |             |                   | now DRIVES it from the staged p2 |
|                         |             |                   | PC; still unread inside ras.sv.  |
|                         |             |                   | SESSION-064: FE-11 proven end to |
|                         |             |                   | end in tb_bp_cluster E4 -- the p1|
|                         |             |                   | snapshot IS the p2 start state,  |
|                         |             |                   | checked one cycle apart against  |
|                         |             |                   | the RAS pointer registers.       |
| ftb_decisions.md        | Complete    | --                | Created session-051. Promoted    |
|                         |             |                   | Complete session-053.            |
| ftb_interfaces.md       | Complete    | --                | Created session-052. IC-FTB-12..15|
| ftb_confidence          | Complete    | --                | conf = bimodal direction,        |
| _override_rules.md      |             |                   | fast-path (session-053).         |
| ftb_array.sv            | Complete    | sim_ftb           | 1R1W data RAM, no reset.         |
| ftb_plru.sv             | Complete    | sim_ftb           | entry-valid + tree-PLRU flops.   |
| ftb_cntrl.sv            | Complete    | sim_ftb           | All FTB logic. Stale "107 bits/  |
|                         |             |                   | way" header comment, TD#104.     |
| ftb.sv                  | Complete    | tb_ftb            | Structural top. sim_ftb 99/0.    |
|                         |             | sim_ftb           | Stale fastpath_en comment, TD#104|
| sc_decisions.md         | Draft       | --                | Created session-056. Corrected   |
|                         |             |                   | 057. s12 br_imli_mode parameter  |
|                         |             |                   | (059).                           |
| sc_table.sv             | Complete    | tb_sc_table       | ST0-ST3. sim_sc_table 6/0.       |
| sc_brimli.sv            | Complete    | tb_sc_brimli      | ST4 BrIMLI. sim_sc_brimli 7/0.   |
| sc_cntrl.sv             | Complete    | tb_sc_cntrl       | sim_sc_cntrl 98/0. SESSION-064:  |
|                         |             |                   | READ and CONFIRMED (BP-094) that |
|                         |             |                   | sc_pred_meta_p3.branch_id is     |
|                         |             |                   | copied from the staged TAGE meta,|
|                         |             |                   | so fixing TAGE fixed SC. No SC   |
|                         |             |                   | change was needed.               |
| sc.sv                   | Complete    | tb_sc             | sim_sc 55/0, sim_sc_fast 52/0.   |
|                         |             |                   | Arb ports stubbed at unit level; |
|                         |             |                   | the real credit arbiter now lives|
|                         |             |                   | in bp_cluster (session-063) and  |
|                         |             |                   | is TESTED as of BP-094 group H.  |
|                         |             |                   | sc_ready is strapped constant    |
|                         |             |                   | under +SC_FAST_INIT -- see the   |
|                         |             |                   | Open Items note.                 |
| sc_interfaces.md        | Complete    | --                | Written session-058. Session-061:|
|                         |             |                   | Arbitration Model corrected.     |
| sc_table_interfaces.md  | Complete    | --                | Written session-058.             |
| sc_table_hash_rules.md  | Complete    | --                | Written session-058.             |
| sc_tb_decisions.md      | Complete    | --                | Session-061: ST0 tb coverage gap |
|                         |             |                   | noted.                           |
| SC (unit)               | Complete    | --                | Remaining unit item:             |
|                         |             |                   | sc_coverage_plan.md. Cluster     |
|                         |             |                   | prereqs: #89/#90 open; #87/#88   |
|                         |             |                   | CLOSED BP-081; #91/#92 CLOSED    |
|                         |             |                   | session-063.                     |
| tb_bp_pkg.sv            | Complete    | sim               | BP-083: retrofitted to the       |
|                         |             |                   | dual-slot entry, 16 -> 23 checks,|
|                         |             |                   | mutation tested (4 defects).     |
|                         |             |                   | BP-090: SLOT_BITS gains the pos  |
|                         |             |                   | term; width checks added for     |
|                         |             |                   | ftb_pred_meta_t and              |
|                         |             |                   | bp_ftq_meta_t (neither had one); |
|                         |             |                   | pos driven, read back and        |
|                         |             |                   | rewritten on both slots; packing |
|                         |             |                   | tests added for ftb_pred_meta_t  |
|                         |             |                   | and the bp_ftq_meta_t ftb member.|
|                         |             |                   | 28 checks. 13 mutations, all     |
|                         |             |                   | fired. BP-092: lp checks         |
|                         |             |                   | retargeted onto lp_pred_t, count |
|                         |             |                   | unchanged at 28. No watchdog     |
|                         |             |                   | needed: no clock, cannot hang.   |
| bp_cluster.sv           | Complete    | tb_bp_cluster     | SESSION-063. BP-084 structural,  |
|                         | SIMULATED   | sim_bp_cluster    | BP-085 behavioural, BP-090       |
|                         |             | cov_bp_cluster    | rewire + metadata + closure.     |
|                         |             |                   | SESSION-064: BP-091 loop_pred    |
|                         |             |                   | rewire (the slot-0 exception in  |
|                         |             |                   | the p1 mux and the zero-driven   |
|                         |             |                   | loop metadata above slot 0 are   |
|                         |             |                   | GONE); BP-092 lp_pred_t retype + |
|                         |             |                   | bpu_pred_pft_p1 added + TD#107   |
|                         |             |                   | comments; BP-092a per-slot branch|
|                         |             |                   | PC derived from in-block pos     |
|                         |             |                   | instead of a block stride.       |
|                         |             |                   | FIRST SIMULATED BP-093.          |
|                         |             |                   | sim_bp_cluster 973/0 after       |
|                         |             |                   | BP-094 groups G and H.           |
|                         |             |                   | LINE COVERAGE 258/258. 20        |
|                         |             |                   | mutants, all died. NO DEFECT WAS |
|                         |             |                   | FOUND IN bp_cluster itself.      |
|                         |             |                   | SESSION-066 BP-097: D2's         |
|                         |             |                   | $isunknown check could not fail  |
|                         |             |                   | and was replaced; the watchdog   |
|                         |             |                   | was cycle-based and could not    |
|                         |             |                   | fire, now #200000. Count         |
|                         |             |                   | unchanged at 973.                |
| bpu_port_inventory.md   | Working     | --                | INFRA-011. 140 ports across the  |
|                         |             |                   | eight top-level modules, read    |
|                         |             |                   | from RTL and compared to the     |
|                         |             |                   | eight interface docs. 4 findings,|
|                         |             |                   | all in ubtb and bp_history.      |
|                         |             |                   | STALE on loop_pred after BP-091. |
| ftq_bpu_interfaces.md   | Draft       | --                | SESSION-063. FTQ/BPU port        |
|                         |             |                   | specification: request, p1       |
|                         |             |                   | prediction, late predictions,    |
|                         |             |                   | redirects, prediction metadata,  |
|                         |             |                   | updates, history checkpoint.     |
|                         |             |                   | SESSION-064: section 4 gains     |
|                         |             |                   | bpu_pred_pft_p1; section 9       |
|                         |             |                   | pred_pc corrected to per-BRANCH  |
|                         |             |                   | and to the branch PC; section 10 |
|                         |             |                   | items 6, 7, 8, 9, 12 CLOSED;     |
|                         |             |                   | item 14 opened for TD#102.       |
| fe_decisions.md         | Draft       | --                | Created session-062. Front-end   |
|                         |             |                   | theory of operation. SESSION-064:|
|                         |             |                   | RAS top of stack corrected to p0 |
|                         |             |                   | (2.2, 9, and the section 1 stage |
|                         |             |                   | list); section 3.1 rewritten to  |
|                         |             |                   | the cluster-derived, stage-named |
|                         |             |                   | redirect groups; bp_loop_meta_t  |
|                         |             |                   | replaced by lp_pred_t in 4.2;    |
|                         |             |                   | FE-12 added.                     |
| fetch                   | Not started | --                | After BP cluster                 |

---

## Technical Debt

| # | Item                                   | Resolution path                 |
|---|----------------------------------------|---------------------------------|
| 1  | NUM_PRED_SLOTS=1 reduction.           | Cleanup session after TAGE      |
|    | Generate removal and NUM_PRED_SLOTS=1 | complete. Dual-slot *testing*   |
|    | tests pending.                        | tracked separately in #74.      |
|    | SESSION-064: NEW BLOCKER.             | tb_bp_cluster indexes generate  |
|    |                                       | blocks by literal and $fatal(1)s|
|    |                                       | at elaboration if the package   |
|    |                                       | value is not 2. Reduction now   |
|    |                                       | requires reworking that tb.     |
|    |                                       | loop_pred and tb_loop_pred DO   |
|    |                                       | elaborate at 1 (BP-091).        |
| 2  | Instruction fusion                    | Deferred to rename/dispatch     |
| 3  | UOP expansion for RVV segments        | Policy TBD at vector execution  |
| 4  | predecode.sv clk/rstn unused          | Resolve at pipeline stage assign|
| 5  | ENUM hole at 7'd2 (VALU_FP)           | Minor, acceptable for now       |
| 6  | vtype_hazard intra-bundle policy      | TBD at rename/dispatch          |
| 7  | curs/curs_v rollback undefined.       | Resolve at bp_cluster impl or   |
|    | Seznec uses SLIM structure. Inline    | migrate to SLIM-style external  |
|    | fields have no defined                | structure. See rollback test    |
|    | checkpoint/rollback path.             | items #69/#70.                  |
| 16 | ALLOC_DATA_WIDTH padding when         | Resolve at T0 implementation    |
|    | THIS_ < MAX_ -- unused bits between   |                                 |
|    | EPC and TAG fields.                   |                                 |
| 17 | BP-007b signal naming nonconforming.  | BP-007c scope expanded to       |
|    | _s0/_s1 suffixes used instead of      | include alc_index_u0 width fix  |
|    | array indexing per                    |(MAX_IDX_WIDTH->THIS_INDEX_BITS) |
|    | tage_table_interfaces.md.             | T0 tag hash compute-and-discard |
|    | Prompt author error.                  | cleanup.                        |
| 18 | Definition of T0 fields/behavior      | Prediction side closed          |
|    |                                       | Update side pending T0          |
|    |                                       | implementation                  |
| 37 | trx_type forwarded combinationally    | Investigate before closing.     |
|    | from arb_grant_upd instead of from    | When concurrent pred+upd tests  |
|    | registered arb_trx_r.trx_type.        | are added (arb item #73),       |
|    | Verify grant signal stability through | verify grant stability through  |
|    | tage_cntrl pipeline under concurrent  | the pipeline. If unstable,      |
|    | pred+upd.                             | promote arb_trx_r.trx_type and  |
|    |                                       | adjust write-enable timing.     |
| 38 | Verilator 5.048 covergroup #7099      | Re-check #7099 status in 5.048  |
|    | status not yet verified.              | release notes before closing.   |
| 39 | Rule 2 starvation override            | ANSWERED BP-094, needs a        |
|    | reachability.                         | DECISION. Measured: SC_PRED_    |
|    | SC_PRED_CREDITS=4 <                   | CREDITS=4 and rule 4 resets the |
|    | SC_STARVE_THRESH=8.                   | starve counter after 4 grants,  |
|    |                                       | so starve_ctr tops out at 4 and |
|    |                                       | NEVER reaches 8. The override is|
|    |                                       | unreachable in traffic. Group H |
|    |                                       | test H6 seeds the counter and   |
|    |                                       | proves the implemented arm obeys|
|    |                                       | 4.5 rule 2; it does not prove   |
|    |                                       | reachability, and says so.      |
|    |                                       | Either raise PRED_CREDITS above |
|    |                                       | STARVE_THRESH, lower the        |
|    |                                       | threshold, or record the arm as |
|    |                                       | dead code kept for parameter    |
|    |                                       | flexibility. Parameter choice,  |
|    |                                       | not a testbench problem.        |
| 40 | TB-ARB-05 spec discrepancy.           | bp_arb_spec.md testbench section|
|    | Old "backpressure 2 cycles" note did  | (was 10.1) removed session-057; |
|    | not match TAGE_UQ_DEPTH=8.            | tb requirements now live in the |
|    | No RTL risk.                          | implementing task file.         |
| 42 | Pipeline diagram shows ITTAGE at s3,  | Revisit after SC definition.    |
|    | should be s2 (alongside FTB, TAGE).   | Update diagram and discussions. |
|    |                                       | #65 is CLOSED, BP-054           |
| 43 | Reduce ITTAGE CTR width 3b -> 2b.     | Impacts bp_defines_pkg.sv,      |
|    |                                       | ittage_table_interfaces.md, RTL |
|    |                                       | and testbenches.                |
| 49 | Arb queue status pin renaming.         | pq_not_full/upd_rdy ->          |
|    |                                        | tage_pq_not_full/tage_uq_not_   |
|    |                                        | full and ittage_ equivalents.   |
|    |                                        | Scope: RTL, tb, bp_arb_spec.md, |
|    |                                        | tage_interfaces.md,             |
|    |                                        | ittage_interfaces.md.           |
|    |                                        | Session-063: bp_cluster ALREADY |
|    |                                        | prefixes these at its boundary, |
|    |                                        | so the rename inside tage.sv and|
|    |                                        | ittage.sv is cosmetic alignment,|
|    |                                        | not a blocker.                  |
| 52 | Move arb logic into submodule out of   | Top modules should be           |
|    | top in tage and ittage.                | structural only. New arb module |
|    | (Refactor; pairs with #73 test.)       | for tage and ittage. Co-        |
|    |                                        | sequence with arb test #73.     |
| 67 | tage sram_init non-fast path.          | All tests used +FAST_INIT,      |
|    | Untested here; confirm not elsewhere.  | bypassing real sram_init        |
|    | SESSION-064: now extends to the        | cycling. Confirm the COMP tests |
|    | CLUSTER -- sim_bp_cluster and          | cover the non-fast path; do not |
|    | cov_bp_cluster pass all three          | assume. A plusarg running a     |
|    | fast-init plusargs.                    | SHORT init walk rather than none|
|    |                                        | would also make the SC arbiter  |
|    |                                        | rule-1 guard reachable from the |
|    |                                        | ports (see BP-094 H2b).         |
| 68 | ittage sram_init non-fast path.        | Same as #67.                    |
| 69 | tage rollback / history recompute.     | G20/G21/G22 RESOLVED            |
|    | Dark; tracks arch TBDs.                | session-054. Fold recompute     |
|    |                                        | proven in-sim BP-072. Rollback  |
|    |                                        | STIMULUS now exists AND is      |
|    |                                        | exercised: tb_bp_cluster E1/E2  |
|    |                                        | drive checkpoint and rollback   |
|    |                                        | through the cluster. The tage-  |
|    |                                        | side recompute is still not     |
|    |                                        | checked end to end. See TD #7.  |
| 70 | ittage rollback / history recompute.   | Same as #69 for ittage.         |
| 73 | Arbitration layer behavioral test.     | CLOSED BP-094 group H. All      |
|    | Pairs with refactor #52.               | seven bp_arb_spec 4.5 grant     |
|    |                                        | rules plus tage consumer_ready  |
|    |                                        | tested, hierarchically. Folds in|
|    |                                        | #37, #39, #40. Residual: #39 is |
|    |                                        | a parameter decision, and       |
|    |                                        | concurrent pred+upd for TAGE and|
|    |                                        | ITTAGE (not SC) is untouched.   |
| 74 | Dual-slot (NUM_PRED_SLOTS=2) test.     | bp_history part CLOSED          |
|    | bp_history dual-slot fold equivalence  | (BP-072), externally anchored   |
|    | proven; broader cluster dual-slot      | BP-073. SESSION-064: both slots |
|    | still partly deferred.                 | are now exercised together in   |
|    |                                        | tb_bp_cluster groups B, E, F and|
|    |                                        | G. The slot-1 UPDATE path across|
|    |                                        | TAGE/ITTAGE is covered by group |
|    |                                        | G only for the loop it drives.  |
|    |                                        | Reduction work in #1.           |
| 75 | ittage has no fast versions of the     | The equivalent TAGE target is   |
|    | ittage sim targets.                    | sim_tage_fast. Create           |
|    |                                        | sim_ittage_fast.                |
| 77 | scrub prompts and redact any absolute  | Not a design TD; tools and infra|
|    | path not using the RVA_ROOT env var    | task, possibly manual.          |
| 78 | RAS p3 undo-pop does not reverse a   | LEAVE AS-IS. BP-064 pins the   |
|    | recursion pop.                       | current non-reversing behavior. |
|    |                                      | Revisit at bp_cluster           |
|    |                                      | integration if a p2/p3 repair   |
|    |                                      | over a recursion pop is ever    |
|    |                                      | required. Related: #79.         |
| 79 | RAS commit-stack recursion depth not | DEFER. The field is write-only  |
|    | preserved.                           | and never read by any output    |
|    |                                      | path, so a wrong value degrades |
|    |                                      | the fallback prediction only.   |
|    |                                      | Real fix needs a recursion-count|
|    |                                      | source on the commit interface. |
|    |                                      | Decide at FTQ integration.      |
| 80 | FTB confidence hysteresis tuning.    | FTB_CONF_WIDTH is the knob.     |
|    |                                      | Revisit at bp_cluster SPEC      |
|    |                                      | numbers.                        |
| 81 | tb_ftb coverage skews to br0.        | Optional symmetric br1 augment. |
|    |                                      | Not a blocker; sim_ftb 99/0.    |
| 82 | bp_history if/else-if slot cleanup.  | decisions.md 3.5. Fold into the |
|    |                                      | next bp_history RTL touch. No   |
|    |                                      | behavior change.                |
| 83 | bp_history decisions.md s6.6 origin  | Fill the Xiangshan commit sha / |
|    | citation placeholders.               | date. Manual, low priority.     |
| 84 | Producer/consumer end-to-end fold    | BP-073 proved the fold VALUE    |
|    | check.                               | against the canonical           |
|    |                                      | definition; it did NOT run that |
|    |                                      | fold through the TAGE/ITTAGE    |
|    |                                      | table index hash. Cluster       |
|    |                                      | stimulus now exists and         |
|    |                                      | tb_bp_cluster group G drives a  |
|    |                                      | closed loop, but the FOLD is    |
|    |                                      | still not traced through the    |
|    |                                      | hash. SC ST1-ST3 additional.    |
| 85 | bp_structs_pkg.sv                    | Review BPU structures for       |
|    |                                      | field sharing and storage/flop  |
|    |                                      | opportunities.                  |
| 86 | sc_cntrl 8x-weighted TAGE term.      | The current sum includes        |
|    |                                      | tage_extd_ctr at weight 1. The  |
|    |                                      | 8x variant is deferred to PD /  |
|    |                                      | perf. Related: #93.             |
| 87 | tage strong/medium/weak decode       | CLOSED BP-081 (session-060).    |
| 88 | tage_extd_ctr generation             | CLOSED BP-081 (session-060).    |
| 89 | ftb       | Change the FTB definition to store 20 additional bits.   |
|    |           | These are PC bits [15:6] of branch location              |
|    |           | These will be supplied to sc_upd_inp.branch_range        |
| 90 | ftb       | Change the FTB to store 2 additional bits. The signs of  |
|    |           | the branch targets for conditional branch 0/1 should be  |
|    |           | stored as backwards_branch0/1.                           |
|    |           | These will be supplied to sc_upd_inp.backwards_branch.   |
|    |           | Two bits, one per prediction slot.                       |
| 91 | bpc       | CLOSED session-063.                                      |
| 92 | bpc/sc    | CLOSED session-063 for the PC and phr; the three SC      |
|    |           | index folds were staged BP-090 and bp_arb_spec.md 6.1    |
|    |           | now names them (session-064). FULLY CLOSED.              |
| 93 | sc        | SC efficacy and threshold/band tuning -- deferred        |
|    |           | investigation. Open questions at PD/perf: does SC earn   |
|    |           | its area/power; the SC_THRSH_MID=10 / SC_THRSH_MAX=512   |
|    |           | seeds vs achievable |sum|~322; the vlo/vvlo band split   |
|    |           | (local, not O-GEHL); the 8x TAGE term (#86) interaction. |
|    |           | Refs: O-GEHL ISCA 2005; Storage-Free Confidence HPCA     |
|    |           | 2011; TAGE-LSC MICRO 2011. Gate any SC die-area          |
|    |           | commitment on this.                                      |
| 94 | bp_arb_spec | CLOSED BP-081. Session-064: 6.1 now names the SC       |
|    |           | index folds; 3.4 and 5.x annotated so the                |
|    |           | <pred>_redir_* names are not read as ports. Sections     |
|    |           | 9/10 remain stubs.                                       |
| 95 | tage      | CLOSED BP-081 (session-060).                             |
| 96 | bpc       | Flush operation has scattered mention across documents.  |
|    |           | Define flush behavior, implement it, and update all      |
|    |           | references. bp_cluster passes ftb_flush_px and the RAS   |
|    |           | flush group straight through with no flush behaviour of  |
|    |           | its own. G24 is the FTB half. NOT exercised by           |
|    |           | tb_bp_cluster.                                           |
| 97 | bp_arb    | To determine whether a shared upstream PQ broadcasting   |
|    |           | to all predictor PQs is implemented. Deferred.           |
| 98 | sc_cntrl  | sc_cntrl shared scalar state under dual-slot update.     |
|    |           | TEMPORARY (BP-077): lowest-indexed valid update slot     |
|    |           | drives the shared threshold/TC/chooser/BrIMLI            |
|    |           | adaptation. Evaluate at PD/perf. Related: #93, #86.      |
| 99 | bpu       | Create a PR/CI/CD process. Motivating evidence           |
|    |           | (session-060): `make all` silently omits targets.        |
|    |           | `all` names 38 of 47, enumerated from the Makefile       |
|    |           | BP-097. The 37 recorded through session-064 was wrong.   |
|    |           | Omitted: sim_ittage, sim_tage_manual, the seven cov      |
|    |           | targets. CI must run all 47, not `make all`.             |
|    |           | SESSION-064 SECOND MOTIVE: seven testbenches reported    |
|    |           | green regardless of what they found. CI must verify      |
|    |           | that each suite CAN fail, not merely that it passes.     |
|    |           | Scope note: the validator checks that a manifest path    |
|    |           | exists TODAY. 60 of 184 prompt files fail that on        |
|    |           | historical manifests. CI must validate only the file     |
|    |           | being run, not the prompts tree.                         |
| 100 | tage     | tage line coverage below the previously-stated >90%.     |
|     |          | MEASURED BP-097: cov_tage 73.8% (6418/8700),             |
|     |          | cov_tage_table 79.5% (399/502), cov_bpu 79.1%            |
|     |          | (9032/11419). The cov_tage denominator moved 8468 ->     |
|     |          | 8700 when BP-096 added tage_assert.sv to that compile,   |
|     |          | so 73.7 -> 73.8 is a new baseline, not a coverage        |
|     |          | change. The prior 6242/8468 predates that.               |
|     |          | The TD#109 caveat is retired: the assertions ARE bound   |
|     |          | in cov_tage and tage_assert.sv is 10/10 there.           |
|     |          | STILL UNRESOLVED: genuine under-coverage or accounting   |
|     |          | artifact. Data, not a resolution: 8043 of cov_tage's     |
|     |          | 8700 lines are tb_tage.sv, so the headline is dominated  |
|     |          | by testbench lines; DUT-only is near 90%. In             |
|     |          | cov_tage_table, tage_table.sv alone is 155/172 = 90.1%,  |
|     |          | so the 90.1% in TAGE_DECOMP_LOG.md and                   |
|     |          | tage_coverage_plan.md is the DUT-only figure, not a      |
|     |          | stale one. Any conclusion must state its denominator.    |
|     |          | CAUTION: BP-097's per-file table does not sum to 8700    |
|     |          | and its RTL-only subtotal excludes a file it lists.      |
|     |          | Re-derive per-file numbers before using them.            |
| 101 | ras.sv   | Declares input ras_pc_p2, unread in the module.          |
|     |          | bp_cluster drives it from the staged p2 PC. Confirm      |
|     |          | needed or remove from ras.sv and tb_ras.sv.              |
| 102 | bp_history.sv | Does not generate IT5 folds. ittage.sv wires        |
|     |          | it_t5_idx_fh/tag_fh1/tag_fh2 to bp_history outputs that  |
|     |          | are never driven -- permanently 0. IT5 has real history  |
|     |          | (IT_TBL_HIST[5]=32, FH=9, FH1=9, FH2=8). Consequence:    |
|     |          | IT5 indexes on PC alone, so the longest-history ITTAGE   |
|     |          | table contributes no history and duplicates a short-     |
|     |          | history table. Prediction accuracy loss, not a           |
|     |          | correctness break. Add IT5 fold generation (same pattern |
|     |          | as IT1-IT4). Recorded in bp_history_interfaces.md as HI6 |
|     |          | and ftq_bpu_interfaces.md section 10 item 14.            |
| 103 | tage     | tage initializes T0 to 00 (strongly not taken). Intended |
|     |          | is weakly taken, b10. Impacts TAGE_SRAM_INIT_VALUE use   |
|     |          | with sram_init. When this closes, update                 |
|     |          | tage_cntrl_decisions.md's T0 init line again (see the    |
|     |          | conflict note at the top of this file).                  |
| 104 | ftb      | Two stale RTL header comments (INFRA-008). Comment-only: |
|     |          |   - ftb_cntrl.sv: "107 bits/way", actual 105.            |
|     |          |   - ftb.sv: ftb_fastpath_en "beyond the interface draft",|
|     |          |     it is a documented top input.                        |
|     |          | Fold into the first FTB-touching RTL task.               |
| 105 | loop_pred| CLOSED BP-091 (session-064). Dual-slot retrofit,         |
|     |          | per-slot banks, pred_p0 -> pred_p1 rename, bp_cluster    |
|     |          | rewired. The cluster boundary ports lp_upd_valid_p0 and  |
|     |          | lp_upd_p0 gained the slot dimension in the same task.    |
| 106 | bp_structs_pkg | CLOSED BP-092 (session-064). bp_loop_meta_t        |
|     |          | deleted; lp_pred_t survives; lp_to_meta() deleted rather |
|     |          | than rewritten -- it did nothing but reorder and rename. |
| 107 | bp_cluster | CLOSED BP-092 (session-064). Both stale comments      |
|     |          | corrected. BP-092a found and corrected two more of the   |
|     |          | same class (stale interfaces section numbers) plus a     |
|     |          | fourth BP-092 missed because it read "(interfaces 8)".   |
| 108 | bp_cluster | CLOSED BP-092 (session-064). bpu_pred_pft_p1 added   |
|     |          | to the p1 output group: the block fall-through, one      |
|     |          | value per prediction, qualified by bpu_pred_val_p1,      |
|     |          | driven from the existing p1 not-taken term. Also closes  |
|     |          | the observability hole handoff-064 Part 3 item 4.        |
| 109 | tb_tage  | CLOSED BP-096. The bind read "bind u_dut tage_assert",   |
|     |          | an INSTANCE name. v5.048 accepts it, instantiates        |
|     |          | nothing and warns about nothing under -Wall, so          |
|     |          | tage_assert was NOT evaluated in sim_tage,               |
|     |          | sim_tage_fast, lint_tage or cov_tage. Repaired to        |
|     |          | "bind tage tage_assert".                                 |
|     |          | CORRECTED BP-097. The claim that tage_assert_inhibit     |
|     |          | "is not declared anywhere in tb_tage.sv" is FALSE. It is |
|     |          | declared at :259, initialised at :260, driven at         |
|     |          | :7669/:7671, and was present before BP-096 (verified     |
|     |          | against ea6e917). The compile failure was SCOPE          |
|     |          | RESOLUTION: a bind naming a MODULE resolves its port     |
|     |          | expressions in the bound-into module's scope, where      |
|     |          | that tb signal does not exist. Fix was the hierarchical  |
|     |          | reference tb.tage_assert_inhibit, not a declaration.     |
|     |          | Same defect in tb_tage_manual.sv fixed BP-095. BP-096    |
|     |          | swept all five binds across 46 files; class BOUNDED at   |
|     |          | these two, both repaired and proven live.                |
| 110 | tb       | CLOSED BP-096 by deletion. ittage_assert_bind.sv was     |
|     |          | compiled by no target; tb_ittage.sv's inline bind works, |
|     |          | so sim_ittage was always correct. The deletion was       |
|     |          | ordered by the BP-096 prompt and never authorised by     |
|     |          | Jeff -- recorded as a fact of the tree, not a precedent. |
|     |          | It left BP-096.md's manifest naming a missing path,      |
|     |          | corrected BP-097.                                        |
| 111 | tb       | CLOSED BP-097. Was: no watchdog in tb_ittage_cntrl,      |
|     |          | tb_ittage, tb_tage_tasks or tb_tage_manual. BP-096       |
|     |          | added those four. BP-097 swept all 18 testbenches:       |
|     |          |   - tb_tage, tb_loop_pred and tb_bp_history had none.    |
|     |          |     Added, time-based, proven both directions.           |
|     |          |   - tb_bp_cluster had one that could not fire:           |
|     |          |     repeat (200000) @(posedge clk). Clock frozen -> run  |
|     |          |     hung, make never returned. Converted to #200000.     |
|     |          |   - tb_bp_pkg needs none: no clock, cannot hang.         |
|     |          | RULE: a watchdog must be a TIME delay (#N), never a      |
|     |          | cycle count -- the hang it catches can stop the clock.   |
|     |          | 17 watchdogs now; tb_bp_cluster was the only cycle-based |
|     |          | one.                                                     |
|     |          | Residual, reported not fixed: magnitudes are not         |
|     |          | uniform. BP-096's four sit at 4.3x-6.1x of measured      |
|     |          | completion, the ten older ones at 20x-439x. No rule      |
|     |          | specifies a ratio and a late watchdog still fails        |
|     |          | correctly, so the older limits were left. The            |
|     |          | completion figures behind those ratios are coarse and    |
|     |          | strap-dependent; re-measure before setting a ratio rule. |

---

## Open Items

| Priority | Item                                    | Status              |
|----------|-----------------------------------------|---------------------|
| 1        | TOOLS-002 spike ISA string              | Deferred            |
| 2        | DECODE-012 pre-decode restructure       | Defer to fetch unit |
| 3        | Whisper ISS lock-step validation        | Post-pipeline       |
| 4        | Cleanup CLI-001,002,004,008,011,012,TI7 | Complete.           |
|          |                                         | CLI-011 confirmed   |
|          |                                         | BP-097; closed by   |
|          |                                         | BP-018, not BP-091. |
|          |                                         | Nothing pending.    |
| 5        | TAGE full validation plan               | Complete            |
| 6        | BP code coverage plan: CE-01            | Complete            |
|          | through CE-06 all closed                |                     |
| 7        | Verilator upgrade to post-covergroup    | Upgraded to 5.048.  |
|          | release                                 | Covergroup #7099    |
|          |                                         | re-check pending.   |
| 8        | Investigate mutation testing            | STANDING PRACTICE.  |
|          |                                         | BP-083, BP-086,     |
|          |                                         | BP-090, BP-091,     |
|          |                                         | BP-093 and BP-094   |
|          |                                         | all mutation-tested |
|          |                                         | their testbenches.  |
|          |                                         | BP-094 ran 20       |
|          |                                         | mutants, all died.  |
|          |                                         | Survivors were      |
|          |                                         | genuine coverage    |
|          |                                         | holes each time and |
|          |                                         | were closed. Make it|
|          |                                         | a written testbench |
|          |                                         | requirement.        |
| 9        | Research verible-verilog-format for SV  | Planned             |
|          | formatting.                             |                     |
| 10       | README update: document tools/bin       | Pending             |
|          | layout and build instructions for       |                     |
|          | Verilator and Spike.                    |                     |
| 11       | tb_bp_cluster and its tests             | DONE session-064.   |
|          |                                         | 973 checks, groups  |
|          |                                         | A-H, 258/258 lines. |
| 12       | Every new testbench must demonstrate    | session-064, plus   |
|          | a NON-ZERO EXIT on a deliberately       | the watchdog half   |
|          | broken check, AND carry a TIME-BASED    | BP-097.             |
|          | watchdog exiting $fatal(1). A cycle-    | $finish and         |
|          | count watchdog does NOT satisfy this.   | $finish(1) both     |
|          | Prove a watchdog by STOPPING THE CLOCK, | exit 0 under        |
|          | not by shortening the limit.            | v5.048. See TD#111. |
| 13       | sc_ready is strapped constant under     | NEW session-064.    |
|          | +SC_FAST_INIT, so the SC arbiter        | A plusarg running a |
|          | rule-1 guard is unreachable from the    | SHORT init walk     |
|          | ports. BP-094 H2b clears the strap      | would fix this and  |
|          | for one case.                           | help TD#67/#68.     |
| 14       | terminate() in tb/utils.svh is a bare   | NEW session-066.    |
|          | $finish, reached only on the clean      | Not a false green   |
|          | path of tb_tage_manual.sv. Invisible    | today. Any new      |
|          | to a per-file grep for exit primitives. | caller must         |
|          |                                         | preserve the split. |
| 15       | tb_pf() in tb/utils.svh prints a        | NEW session-066.    |
|          | PASS/FAIL string and does not gate.     | No testbench relies |
|          |                                         | on it for a verdict.|
| 16       | +ITTAGE_FAST_INIT is INERT for          | NEW session-066.    |
|          | sim_ittage_table: that target compiles  | Harmless; the       |
|          | ittage_table.sv without sram_init.sv.   | Makefile line       |
|          | Completion 266 units with and without.  | implies otherwise.  |

---

## BP Cluster Open TBDs

| ID  | Item                                  | Status                 |
|-----|---------------------------------------|------------------------|
| G5  | RAS commit stack entry count          | RESOLVED session-050.  |
|     |                                       | 16 spec + 32 commit.   |
| G6  | RAS recursion counter width           | RESOLVED session-050.  |
|     |                                       | 4b per entry.          |
| G7  | SC threshold value                    | REFRAMED session-056,  |
|     |                                       | values corrected 057.  |
|     |                                       | Threshold is DYNAMIC   |
|     |                                       | (O-GEHL). Tuning       |
|     |                                       | deferred TD#93.        |
| G8  | Dual pred bundle split point          | SUPERSEDED session-063.|
|     |                                       | The pred_pc+0:31 /     |
|     |                                       | +32:63 split is the    |
|     |                                       | TAGE/ITTAGE bundle     |
|     |                                       | convention and does    |
|     |                                       | NOT govern block       |
|     |                                       | prediction. ubtb.sv    |
|     |                                       | rewritten to match     |
|     |                                       | (BP-086).              |
| G9  | Update channel arbitration            | RESOLVED session-067.  |
|     |                                       | SC credit arbiter done |
|     |                                       | and tested BP-094 grp  |
|     |                                       | H. The FTB single      |
|     |                                       | update port scheduler  |
|     |                                       | is ftq_decisions.md    |
|     |                                       | 5.7: slot 0 first into |
|     |                                       | a one-deep skid, with  |
|     |                                       | resolution backpressure|
|     |                                       | bounding it.           |
| G10 | TAGE/ITTAGE meta overload scheme      | TBD at implementation. |
|     |                                       | The metadata write path|
|     |                                       | exists and is verified |
|     |                                       | field by field (BP-093 |
|     |                                       | group F), so the       |
|     |                                       | overload scheme is the |
|     |                                       | remaining half.        |
|     |                                       | See TD-FE-2.           |
| G14 | Confidence counter purpose            | Reserved, 4b. Driven   |
|     |                                       | to zero by the cluster;|
|     |                                       | nothing reads it       |
|     |                                       | (FE-U3).               |
| G15 | Fold recompute timing concern         | REFRAMED session-054.  |
|     |                                       | Perf measurement, not  |
|     |                                       | a correctness gate.    |
| G16 | ignored labeling gap                  |                        |
| G17 | Slot 1 PC derivation (pred_pc+32)     | SUPERSEDED session-063.|
|     |                                       | Same as G8. There is   |
|     |                                       | no slot-1 PC in the    |
|     |                                       | uBTB or the FTB.       |
|     |                                       | SESSION-064: the       |
|     |                                       | cluster's own residual |
|     |                                       | block stride on        |
|     |                                       | w_slot_pc_p1 was found |
|     |                                       | and fixed (BP-092a).   |
| G18 | carry field consumer in cluster       | STILL TBD. ubtb_pred_t |
|     |                                       | .carry has no consumer.|
|     |                                       | It is the entry fall-  |
|     |                                       | through carry, not a   |
|     |                                       | property of the slot   |
|     |                                       | target. (= UI2)        |
| G19 | NO_BRANCH target on hit               | RESOLVED session-063.  |
|     |                                       | Verified BP-093 B2:    |
|     |                                       | a hit with no valid    |
|     |                                       | slot is legal and the  |
|     |                                       | successor is           |
|     |                                       | blk_p1.pft_addr.       |
| G20 | bp_history dual slot update path      | RESOLVED session-054.  |
| G21 | rollback_en + pred_valid same-cycle   | RESOLVED session-054.  |
|     | priority undefined                    | Rollback wins.         |
| G22 | One-cycle folded output invalid       | RESOLVED session-054.  |
|     | window after rollback                 | Folds STALE not        |
|     |                                       | invalid.               |
| G23 | Checkpoint slot reclaim protocol      | TBD at FTQ impl.       |
|     |                                       | (= bp_history HI5)     |
| G24 | FTB flush protocol (ftb_flush_px)     | TBD. The port passes   |
|     |                                       | straight to ftb.sv; no |
|     |                                       | flush behaviour at the |
|     |                                       | cluster and none       |
|     |                                       | exercised by           |
|     |                                       | tb_bp_cluster. TD#96.  |
| G25 | FTB fast-path enable source           | TBD. ftb_fastpath_en   |
|     | (ftb_fastpath_en: CSR / tie /         | is a cluster input and |
|     | runtime)                              | passes through.        |
|     |                                       | ftb_fastpath_p2 has no |
|     |                                       | consumer -- the bypass |
|     |                                       | is not built.          |

---

## Package Split Convention (settled session-008)

bp_pkg.sv has been split into:
  bp_defines_pkg.sv  -- bp_defines_pkg  -- parameters only
  bp_structs_pkg.sv  -- bp_structs_pkg  -- structs, enums, typedefs

Import order is mandatory in every file:
  import bp_defines_pkg::*;
  import bp_structs_pkg::*;

---

## BP Cluster Key Parameters
See bp_defines_pkg.sv. Do not duplicate here.
num_branches valid range: 0-2. Value 3 is undefined.

---

## Prompt Generation Guide

See PROJECT_CORE.md §Prompt generation rules.
For known failure modes see ANTIPATTERNS.md.

---

## Architectural Decisions

### Decoder track

Full detail: planning/arch/decode.md (file currently absent).

Key decisions for quick reference:
- Illegal instruction: ILLEGAL flag in decode packet,
  ROB entry allocated, commit flushes to mtvec
- vtype: decoder stateless, rename resolves dependency
- Dual decode packet: decode_pkt_t[7:0] scalar,
  vec_decode_pkt_t[7:0] vector, predecode_pkt_t[7:0]
- OPMVX: pkt.vs1=0, GPR in scalar pkt.rs1
- Extension enable: ext_enable_t static from misa/CSR
- Vector memory disambiguation: opcodes 0x07/0x27

### BP cluster track

Full detail: planning/arch/bp_cluster.md (LOCKED),
planning/arch/fe_decisions.md (theory of operation),
planning/interfaces/ftq_bpu_interfaces.md (port specification).

Key decisions for quick reference:
- Seven predictors: uBTB, Loop, FTB, TAGE, SC, ITTAGE, RAS
- Pipeline: p0 index + RAS TOS read, p1 uBTB+Loop,
  p2 FTB+TAGE+ITTAGE+RAS push/pop, p3 SC
- ITTAGE overrides FTB target at p2 for indirect branches
  (including indirect CALL). RAS overrides FTB target at p2
  for returns and separately pushes the return address on
  indirect/direct CALL.
- Loop overrides uBTB at p1 when trusted, PER SLOT. There is
  no slot-0 exception (BP-091).
- Update policy: post-execute, not retire
- RAS: dual-stack, static partition, 16 speculative +
  32 commit entries. Pointer-only snapshot recovery. The top
  of stack is read at p0 (ras_tos_addr_p0).
- FTB: single set-associative array (4-way / 2048 / 512
  sets), 26-bit full tag, tree-PLRU, 2 conditional + 1 jump
  per entry. Storage split ftb_array / ftb_plru / ftb_cntrl.
  conf is a bimodal DIRECTION counter; saturated-endpoint
  fast-path (ftb_fastpath_en). FTB target is the ITTAGE-miss
  / RAS-empty fallback.
- uBTB: ONE lookup per cycle. The entry mirrors the FTB
  entry. One entry describes one 32-byte block and supplies
  both prediction slots. The pred_pc+32 slot-1 lookup is
  retired (session-063, BP-086). Entry hit is reported once
  per lookup on blk_p1.hit; a slot valid bit means only that
  the slot carries a branch.
- In-block position: FTB_BR_POS_BITS = $clog2(BLOCK/4), so a
  position is a 4-byte expanded-instruction slot, 8 per
  block. The branch PC is block base + pos*4.
- BPU is decoupled frontend. The FTQ is the REQUESTER and owns
  next-PC selection: bp_cluster takes ftq_pred_pc_p0 as an input
  and does not self-steer. Corrected session-067; the previous
  wording, "self-generates next PC", described the XiangShan model
  rather than this one. Selection is ftq_decisions.md 4.
- FTQ depth 64, split fast/slow SRAMs
- History: GHR 256b, PHR 32b, folds recomputed on rollback.
  Pointer module-owned. pred_pc into bp_history is the BRANCH
  PC, indexed by BRANCH NUMBER after compaction. Fold
  geometry canonical in bp_history_decisions.md s6. ITTAGE
  IT5 has real folded history but bp_history does not
  generate it -- TD#102 open.
- TAGE entry: T0 2b CTR only, T1-T4 valid+tag+CTR+useful.
  T0 init value under review, TD#103 open.
- Predictor metadata: every member of tage_pred_meta_t,
  branch_id included, describes the request that produced it
  and is staged to p2 together (BP-094). ITTAGE was inspected
  and already correct.
- ITTAGE entry: IT1-IT5 valid+tag+EPC+USE+CTR(3b)+TGT(38b).
  No IT0 base table.
- SC index: uniform 5-entry arrays. No tag bits. ST4 is
  BrIMLI, SC only. Dynamic threshold (O-GEHL), two-corner
  chooser. br_imli_mode is a compile-time parameter.
- SC arbitration: the section 4.5 credit arbiter is
  IMPLEMENTED IN bp_cluster and TESTED (BP-094 group H). CSR
  sc_enable gates SC participation and the cluster does not
  wait on SC when it is disabled.
- NUM_PRED_SLOTS=2 is the default. Reduction to 1 deferred
  (debt #1).
- Port naming convention: <signal>_<pipestage>. The eight
  modules do NOT all follow it; variance recorded in
  bpu_port_inventory.md and ftq_bpu_interfaces.md section 2.
- TI6: banks are per-slot RAMs. TAGE/ITTAGE/SC/loop_pred
  convention; does NOT apply to FTB or the uBTB.

### bp_cluster boundary decisions (session-063, verified 064)

Every item below was verified in simulation by tb_bp_cluster
unless noted.

- Predictors declare NO redirect ports. The cluster derives
  the redirect by comparing a predictor's stage output
  against the prediction it formed at p1. The groups are
  named by STAGE: bpu_redir_p2 and bpu_redir_p3.
- The redirect comparison reduces both views to ONE quantity,
  the address fetched after that slot. Two not-taken views
  compare equal (BP-093 C2). The p1 operand is formed from
  the p1 view only, so a stale uBTB block boundary redirects
  at p2 (BP-093 C3).
- The p3 comparison is against the p2-corrected value, so a
  p3 redirect fires only when SC changes what was published
  at p2 (BP-093 D1a/D1b).
- Every p2 and p3 comparison is qualified by branch_id equal
  to the FTQ index in the matching stage register. This
  DEPENDS on the predictor staging branch_id with the rest of
  its metadata -- tage_cntrl did not, and the guard was
  defeated until BP-094.
- The FTQ slow path is written by TWO groups with disjoint
  members, shown constructively in BP-093 group F.
- The uBTB update branch type is REDERIVED from the payload's
  own is_br / is_jmp / is_call / is_ret / is_jalr bits.
  Verified BP-094 G0 across all seven encodings, including
  the three fe_decisions 7.2 does not tabulate.
- The jump field is reported in the lowest prediction slot
  carrying no valid conditional field.
- RAS p2 operations are gated by reachability across slots
  (FE-11), and the p1 snapshot IS the p2 start state
  (BP-094 E4).
- The SC prediction PC, phr[9:0] and the three SC index folds
  are all staged p0 to p2 by the cluster.
- The p1 output group carries the block fall-through on
  bpu_pred_pft_p1 (TD#108, BP-092).

### Shared planning documents
    - planning/arch/bp_arb_spec.md                    In progress
        - RECONCILED session-057. Session-064: 6.1 names the SC
          index folds; a caveat at section 0 and a rewritten
          3.4 status note record that no <pred>_redir_* port
          exists; Override lines in 5.x retargeted to the
          stage-named groups; open item J added for TD#39.
    - planning/arch/bp_cluster.md                     In progress
        - Branch prediction cluster summary data. The
          session-063 decisions still are NOT promoted here;
          they live in handoff-064 and ftq_bpu_interfaces.md.
    - planning/arch/fe_decisions.md                   Draft
        - Front-end FTQ<->BPU theory of operation. Session-064
          corrections applied; see Module Status.
    - planning/interfaces/ftq_bpu_interfaces.md       Draft
        - FTQ/BPU port specification. Section 10 items 6, 7, 8,
          9 and 12 CLOSED session-064; item 14 opened. Session-067
          added section 4a, the slot correction groups, and closed
          items 15 and 16.
    - planning/arch/ftq_decisions.md                  Draft
        - FTQ-owned behaviour, session-067. Entry storage,
          lifetime, checkpoint, and the open-policy list.
    - planning/arch/ftq_entry_formats.md              Draft
        - SOLE prose home for bp_ftq_entry_t / bp_ftq_meta_t,
          session-067. bp_cluster.md and fe_decisions.md each
          carried a copy until then.
    - planning/interfaces/ftq_ifu_interfaces.md       Draft
        - FTQ/IFU port specification, session-067. Closes TD-FE-1.
    - planning/interfaces/ftq_backend_interfaces.md   Draft
        - Backend/FTQ resolution, redirect and commit,
          session-067. Closes FE-U2 for the FTQ side; opens
          TD-FE-7. Six backend assumptions recorded, none
          verifiable -- the backend does not exist.
    - planning/interfaces/bpu_port_inventory.md       Working
        - 140-port inventory. STALE on loop_pred after BP-091.
    - planning/interfaces/loop_pred_interfaces.md     Draft
        - Corrected to the delivered ports BP-091.
    - planning/arch/ras_decisions.md                  Draft
    - planning/arch/sram_init.md                      Complete
    - planning/testbenches/manual_tb_decisions.md     Complete

### bp_cluster decomposition (sessions 063-066)

- RTL COMPLETE AND SIMULATED.
    - rtl/core/frontend/bpu/rtl/bp_cluster.sv
    - rtl/core/frontend/bpu/tb/tb_bp_cluster.sv
    - lint_bp_cluster, sim_bp_cluster, cov_bp_cluster.
    - sim_bp_cluster 973/0, cov_bp_cluster 973/0, measured
      BP-097. bp_cluster.sv line coverage 258/258. The whole-
      compile figure for cov_bp_cluster is 85.1% (4501/5289
      after BP-097); it includes every leaf predictor, covered
      separately by the per-predictor suites.
    - Of the 973, 407 print as PASS: lines and 566 are quiet
      sweep checks. One run of one binary. 973 is the
      authoritative count; 407 is a grep artifact and is not a
      group subtotal (settled BP-096, re-measured BP-097).
- Built session-063 in three tasks (BP-084 structural, BP-085
  behavioural, BP-090 rewire and metadata), then corrected and
  verified session-064:
    - BP-091 loop_pred rewire: per-slot p1 mux with no slot-0
      exception, real per-slot p2 loop metadata.
    - BP-092 lp_pred_t retype, bpu_pred_pft_p1, TD#107.
    - BP-092a per-slot branch PC from in-block position.
    - BP-093 first simulation, groups A-F, 530 checks.
    - BP-094 groups G and H, 973 checks, 100% lines.
- Session-066 BP-097: D2 $isunknown check replaced, watchdog
  converted from cycle-based to time-based. Count unchanged.
- Test groups in tb_bp_cluster:
    A bring-up (reset-value conformance, non-zero exit proof)
    B p1 prediction        C p2 redirect
    D p3 and supersession  E history (incl. BP-092a TC-A..TC-G)
    F metadata             G closed predict-then-update loop,
                             all seven predictors
    H SC credit arbiter, all seven grant rules
  Cumulative subtotals measured BP-097: A 55, B 98, C 321,
  D 403, E 763, F 808, G 893, H 973. BP-093's A-F figure of
  530 is the pre-BP-094 state; BP-094.md accounts for the
  +278 per group.
- Known state at the boundary:
    - The nine metadata outputs have no consumer in this
      repository: the FTQ is not built.
    - ftb_fastpath_p2 has no consumer (G25).
    - ubtb_pred_t.carry and .conf have no consumer (G18, FE-U3).
    - ftb_flush_px and the RAS flush group pass through
      untested (G24, TD#96).

### TAGE decomposition
- Session-060 (BP-081): tage RECONCILED and GREEN.
- Session-064 (BP-094): branch_id staging defect FIXED. This
  was a real functional defect that no unit suite could see.
- RTL available; unit and manual testbenches written.
    - Line coverage MEASURED BP-097: cov_tage 73.8%
      (6418/8700), cov_tage_table 79.5% (399/502). TD#100.
      The cov_tage denominator moved when BP-096 added
      tage_assert.sv to that compile: new baseline, not a
      coverage change. The assertions ARE bound in cov_tage
      now and tage_assert.sv is 10/10 there.
    - Directed validation complete. sim_tage 106/0.
    - Remaining deferred: #69 rollback, #67 sram_init non-fast,
      #74 dual-slot, #100 coverage, #103 T0 init.
    - Formal validation not started.
- Tage planning documents all Complete; tage_interfaces.md
  gained a Metadata timing section session-064.

### ITTAGE decomposition
- RTL available; unit testbenches written; directed validation
  complete; formal validation not started.
- Session-064: all three ITTAGE suites were confirmed
  UNENFORCED and then enforced (BP-095). No count changed --
  147, 211 and 32 reproduce exactly. ittage_cntrl was
  inspected for the tage branch_id defect and does NOT have
  it.
- Remaining deferred: #69/#70 rollback, #43 CTR width, #75
  sim_ittage_fast, #68 sram_init non-fast, #102 IT5 fold
  generation.

### RAS decomposition
- RTL: ras.sv complete (BP-062), tb_ras.sv complete (BP-063),
  sim_ras 87/0.
- TD #78 pinned, TD #79 deferred, TD #101 open.
- Session-064: FE-11 proven end to end in tb_bp_cluster E4.
  The p1 snapshot is the state that block starts from at p2,
  checked one cycle apart against the RAS pointer registers.
  The closed commit-update loop is BP-094 G7.

### FTB decomposition
- RTL available and verified (session-053). sim_ftb 99/0.
- Deferred to bp_cluster: flush (IC-FTB-07 / G24, still not
  exercised), conf x TAGE meta (FTB-2 / G10), update
  arbitration (FTB-3 / IC-FTB-09 / G9), ftb_fastpath_en
  source (G25).
- SC-facing additions deferred: TD#89 branch PC[15:6], TD#90
  per-slot backwards-branch sign.
- Session-064: the carried writeWay path (IC-FTB-10) is
  verified end to end -- BP-093 F1 checks hit, way and
  jmp_pos in the p2 metadata, and BP-094 G5 drives a closed
  install-then-hit loop through the FTB update channel.

### SC decomposition
- Planning COMPLETE and RTL COMPLETE at unit level. Remaining
  unit item: sc_coverage_plan.md.
- Prerequisites for cluster integration:
    - #87 / #88 CLOSED BP-081.
    - #91 / #92 CLOSED (PC, phr and the three index folds all
      staged p0->p2).
    - #89 / #90 still open.
    - #84 end-to-end fold check still open -- group G drives a
      closed SC loop but does not trace a fold through the
      index hash.
- Session-064: the SC credit arbiter is tested (group H), the
  SC closed update loop is tested (G3), and sc_cntrl was
  confirmed to inherit its branch_id from the staged TAGE
  metadata rather than reading p0 itself.

### bp_history decomposition
- COMPLETE at unit level (session-055).
- Session-064: pred_pc is the BRANCH PC and is indexed by
  BRANCH NUMBER; bp_history_interfaces.md corrected on both
  points and on three stale claims besides. The cluster side
  was fixed by BP-092a and proven by BP-093 TC-A..TC-G,
  including a 64-pair position sweep and the identity
  path_bit = pos[1] ^ pos[0].
- Open / deferred: HI2, HI5 (= G23), HI6 (= TD#102), HI7,
  #82, #83, #84, #69/#70.

### Shared components track
- components/rtl  components/tb

