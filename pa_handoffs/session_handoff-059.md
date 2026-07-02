<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 059
Written by Claude.ai at end of session-058.
Date: 2026-07-01

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

Session-058 took SC from PLANNING into RTL. It wrote the three
remaining SC interface/hash planning docs and the SC tb-decisions
doc, then generated and landed four IA tasks: the two SC table
modules, the SC control layer, and their unit testbenches. All SC
unit-level RTL below sc.sv is now written and green. The next step is
sc.sv (structural top), its testbench, and tests.

The SC authority doc:
  planning/arch/sc_decisions.md (Draft, session-057)
The arbitration authority doc:
  planning/arch/bp_arb_spec.md (Draft, session-057)

---

## Read This First

The SC table and control layers are written and green at the unit
level (session-058). sc.sv, which wraps them, is NOT written. sc.sv is
the next task.

sc_decisions.md and bp_arb_spec.md were NOT edited this session. They
remain at rest and consistent with the packages as of session-057.
The session-057 source-verified facts still hold and were not
re-litigated: SC counter-update gate = sc_wrong || sc_lo_upd; sum
includes tage_extd_ctr at weight 1 (8x term deferred TD#86); dynamic
threshold seed SC_THRSH_MID, TC 7b; BrIMLI from cookbook predictor.h.

One package syntax fix landed this session (see item 2 below):
sc_pred_meta_t.sc_upd_idx and sc_upd_ctr were unpacked arrays inside a
packed struct; converted to packed 2D arrays. Per-element index access
unchanged.

---

## Session Summary

1. SC planning docs written (the session-057 "next writes" set):
   - planning/interfaces/sc_interfaces.md. SC top-level ports.
     Prediction side takes tage_pred_meta_p2 + tage_pred_rdy_p2 and
     the staged p2 inputs (inp_pc_p2, sc_phr_p2, sc_t1/2/3_idx_fh_p2);
     result sc_pred_meta_p3 / sc_pred_rdy_p3. Update side sc_upd_inp_u0
     / sc_upd_rdy_u1. Arb-status sc_uq_not_full. CSR sc_enable. RAM
     init sc_ready. IC-SC gaps recorded; ST4 PC width resolved to
     inp_pc_p2[15:6] (IC-SC-03).
   - planning/interfaces/sc_table_interfaces.md. Two module types:
     sc_table (ST0-ST3), sc_brimli (ST4). Counter-only entry (no tag/
     USE/EPC/valid/alloc). ctr_p3 out (p2 index, p3 read), idx_hash_p2
     out, upd_index_u0 in, tbl_ri_* init. sc_table takes idx_fh_p2
     (ST0 ties zero); sc_brimli takes sc_phr_p2/br_imli/br_imli_mode.
   - planning/arch/sc_table_hash_rules.md. sc_idx_hash for ST0-ST3
     ((pc>>INST_OFFSET) ^ fh, cast to THIS_INDEX_BITS; fh by
     THIS_TABLE) and get_br_imli_idx for ST4 (pc[15:6], mode-selected
     f_idx, pc^f_idx^(pc>>4)). Update path takes the captured index,
     no re-hash.
   - planning/testbenches/sc_tb_decisions.md. Unit-tb conventions for
     sc_table: DUT direct (u_dut), SC_FAST_INIT plusarg, hierarchical
     mem[b][i] paths, per-test enable, the six-test plan.

2. Package fix (bp_structs_pkg.sv). sc_pred_meta_t.sc_upd_idx and
   sc_upd_ctr were declared with a trailing unpacked dimension
   ([0:SC_NUM_TABLES-1]) inside a packed struct; Verilator rejected
   it. Converted to packed 2D:
     logic [SC_NUM_TABLES-1:0][SC_MAX_IDX_WIDTH-1:0]  sc_upd_idx;
     logic [SC_NUM_TABLES-1:0][SC_MAX_DATA_WIDTH-1:0] sc_upd_ctr;
   sc_upd_idx[0] still maps to table 0; prediction/update assignments
   unchanged.

3. IA tasks generated and landed (all green this session):
   - BP-075: sc_table.sv (ST0-ST3). lint 0/0.
   - BP-075a: tb_sc_table.sv, sim_sc_table / sim_sc_table_fast.
     6 PASS 0 FAIL both targets. (tb was omitted from BP-075 in
     error; BP-075a added it.)
   - BP-076: sc_brimli.sv (ST4) + tb_sc_brimli.sv, combined RTL+tb.
     lint 0/0; sim_sc_brimli / sim_sc_brimli_fast 7 PASS 0 FAIL.
   - BP-077: sc_cntrl.sv + tb_sc_cntrl.sv. lint 0/0; sim_sc_cntrl
     98 PASS 0 FAIL. Table-facing t_* port set; tables not
     instantiated (logic-only unit test).

4. TD#98 opened (dual-slot shared scalar state). See Decisions.

---

## What Was Accomplished

  - sc_interfaces.md, sc_table_interfaces.md, sc_table_hash_rules.md,
    sc_tb_decisions.md written. At rest.
  - bp_structs_pkg.sv: sc_upd_idx / sc_upd_ctr packed-array fix.
  - sc_table.sv, sc_brimli.sv, sc_cntrl.sv and their testbenches
    written and green. Makefile targets added: lint_sc_table,
    sim_sc_table, sim_sc_table_fast, lint_sc_brimli, sim_sc_brimli,
    sim_sc_brimli_fast, lint_sc_cntrl, sim_sc_cntrl.
  - TD#98 drafted for PROJECT_STATUS.

---

## Decisions (session-058)

### SC module decomposition (below sc.sv)

  - Two SC table module types: sc_table (ST0-ST3) and sc_brimli
    (ST4). Separate modules to simplify ST4 specialization; may be
    combined later.
  - SC table entry is a single signed counter. No tag, USE, EPC,
    valid bit, or allocation. ALLOC_DATA_WIDTH == counter width.
  - Tables compute their own index internally and expose idx_hash_p2;
    sc_cntrl captures it into sc_upd_idx. The update path takes the
    captured index; no re-hash.
  - ST4 index PC input is inp_pc_p2[15:6].
  - sc_cntrl holds all SC control state (threshold, TC, chooser,
    BrIMLI registers); tables are pure RAM. br_imli is an sc_brimli
    input driven by sc_cntrl.
  - sc_cntrl exposes a table-facing t_* port set so it is unit-
    testable without the tables. sc.sv fans t_* to the five table
    instances.
  - sc_pred_val_p2 is unconnected in the tables (bw_ram has no read
    enable). Retained for interface completeness.

### TD#98 -- dual-slot shared scalar state (TEMPORARY)

sc_decisions.md s8 declares threshold/TC/chooser/BrIMLI as scalar
(one copy). It does not define adaptation when both slots carry a
valid update the same cycle. Two contention scopes: threshold/TC/
chooser contend whenever both slots update (do_update, s10); BrIMLI
registers contend only when both slots are resolved-taken backward
branches (backwards_branch=1 in both sc_upd_inp, s12).

TEMPORARY resolution (BP-077, in the sc_cntrl header): the lowest-
indexed valid update slot drives the shared threshold/TC/chooser/
BrIMLI adaptation; per-slot counter writes proceed independently for
every valid slot (each slot owns its per-slot table RAM, no write
conflict). Recorded as TD#98; the perf question (duplicate vs share
vs merge) is deferred to PD/perf. Not a correctness gate at the unit
level.

---

## Open Work

### SC -- next writes (sc.sv layer)

  - rtl/core/frontend/bpu/rtl/sc.sv. Structural top. Instantiate
    sc_cntrl, the five tables (sc_table ST0-ST3 via a generate loop,
    sc_brimli ST4), and one sram_init. Fan sc_cntrl t_* to the table
    ports. Tie ST0 idx_fh_p2 to zero; drive ST1-ST3 idx_fh_p2 from
    the staged folds. Drive sc_brimli PC[15:6]/sc_phr_p2/br_imli/
    br_imli_mode. Parent-module sram_init tie-offs and SC_FAST_INIT
    bypass per sram_init.md (parent muxes tbl_ri_*, asserts sc_ready
    immediately in fast mode). sc_ready gating on pred/update.
  - tb_sc.sv + sim_sc / sim_sc_fast. Full SC integration: drive a
    prediction through the real tables into sc_cntrl and back;
    drive an update; exercise sram_init (slow) and SC_FAST_INIT
    (fast); the sc_ready gate; both slots.
  - sc_cntrl_ctr_update_rules.md -- write at tb time, cite
    sc_decisions section 10 (still deferred; optional for sc.sv).
  - sc_coverage_plan.md -- not written.

### SC -- prerequisites (TD, other units; gate cluster integration
    not sc.sv unit work)

  - #87/#88 TAGE emits tage_pred_medium / tage_extd_ctr. Struct
    fields present; generation not written. sc_cntrl consumes driven
    values at unit level; real values needed at cluster integration.
  - #89/#90 FTB supplies branch_range[15:6] and per-slot backwards
    sign to sc_upd_inp.
  - #91/#92 bpc routes PC p0->p2 (inp_pc_p2) and phr[9:0]
    (sc_phr_p2) to SC.
  - #84 end-to-end fold check extends to SC ST1-ST3.
  - br_imli_mode source (CSR/tie/register) is a bp_cluster decision.

### PROJECT_STATUS bookkeeping

  - Add TD#98 (drafted this session).
  - Update SC decomposition section: sc_table / sc_brimli / sc_cntrl
    RTL + tb Complete at unit level; sc.sv Not started.
  - Module Status table: add sc_table, sc_brimli, sc_cntrl rows
    (Complete, unit tb green). sc.sv Not started.
  - Header checkboxes on BP-075/075a/076/077 task files are unticked
    in the IA output (outside the RESULTS markers); set them manually.
  - sc_interfaces.md / sc_table_interfaces.md / sc_table_hash_rules.md
    / sc_tb_decisions.md move to their planning/ paths.

### Carried infra (unchanged from handoff-058, Jeff's priority call)

  - bp_history close-out: s6.6 sha (#83); BP-072/073 status
    checkboxes; retire versions/bp_history.sv.
  - #43 ITTAGE CTR 3b->2b, #75 sim_ittage_fast, #77 path scrub,
    #67/#68 sram_init non-fast, #38 covergroup #7099 re-check.

---

## SC State: RTL IN PROGRESS (tables + control done; sc.sv next)

sc_table (ST0-ST3), sc_brimli (ST4), and sc_cntrl are written and
green at the unit level. sc.sv (structural top) is the next write,
with its integration testbench, followed by sc_coverage_plan.md. The
TAGE/FTB/bpc prerequisites (#87-#92) remain open and gate cluster
integration, not the sc.sv unit task (which drives them as stimulus).

---

## Next Session (059)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-059.md (this file)
  CLAUDE.md
  planning/arch/sc_decisions.md
  planning/interfaces/sc_interfaces.md
  planning/interfaces/sc_table_interfaces.md
  planning/arch/sram_init.md
  rtl/.../sc_table.sv
  rtl/.../sc_brimli.sv
  rtl/.../sc_cntrl.sv
  rtl/.../bp_defines_pkg.sv
  rtl/.../bp_structs_pkg.sv
  rtl/.../tage.sv            (parent-module structural reference)
  rtl/lib/rtl/sram_init.sv

Start by generating the sc.sv task (structural top: sc_cntrl + five
tables + sram_init, t_* fan-out, ST0 fold tie-off, sc_brimli index
inputs, parent-module fast-init bypass, sc_ready gating), then the
sc.sv integration testbench and tests. tage.sv is the parent-module
pattern for the sram_init tie-offs and the SC_FAST_INIT mux.

When generating the sc.sv task: the tables and sc_cntrl are fixed
interfaces now -- transcribe the t_* fan-out from the sc_cntrl port
set and the table port lists, do not re-derive the control logic.
Resolve nothing already settled in the unit modules.

---

## Postmortem Record -- PA performance (session-058)

Continuing the trend log (052/053 unchecked claims; 054 over-asking;
055 one under-audited line; 056 late-source/imported framing; 057
unsourced number, volume, manufactured hazards). 058 ran the SC RTL
generation. The dominant failure this session was over-asking:
repeatedly emitting confirmation requests for items already settled
in-session or answered in the immediately preceding preface, and
listing verified non-issues as open points.

1. Confirmation of already-answered items. Multiple turns asked the
   user to confirm a fact the same response had just stated, or that
   an earlier turn had settled (module count after it was given, the
   plusarg name present in context, bank decomposition deducible from
   the package). The user called this repeatedly. A hard rule was
   added mid-session: do not ask for confirmation of anything decided
   in-session or written in the artifact; if it seems open, cite the
   specific unresolved token or drop it.

2. Re-listing verified findings as open points. "What is left" lists
   included items that were verified consistent, not remaining work.
   Same class as the 057 review-noise.

3. Restating the answer then asking it. On the index-ownership point
   the PA quoted the resolved answer and then asked the user to
   confirm the original answer. Called directly.

4. Research ineffectiveness. On the SC index-hash request the PA
   could not retrieve the two external sources (Xiangshan SC.scala
   getIdx, cookbook predictor.h) because the search engine did not
   surface those blobs; time was spent before establishing the
   functions were already specified in sc_decisions.md and the
   validated hash form. The retrieval that mattered (Xiangshan
   ITTAGE.scala idx construction, Parameters.scala SC params) was
   correct; the framing wrongly treated the documented in-repo forms
   as blocked on the un-fetched sources.

What held: the RTL tasks were source-scoped and landed green on the
first IA run in each case (BP-075/075a/076/077). The package
packed-array fix was correct SV. TD#98 was surfaced by pushing on the
IA's buried dual-slot assumption -- the one review catch that earned
its place -- though the initial framing of it (restating the IA's
"lowest-indexed slot" wording without testing it against the two-RAM
structure) was itself an under-analysis the user corrected.

Pattern to carry into 059:
  - Do not ask for confirmation of anything settled in-session or
    written in the artifact. Cite the specific open token or say
    nothing.
  - A verified-consistent finding is not an open point. Keep it out
    of "what is left."
  - Before flagging an IA assumption, test it against the module
    structure already in context, not just the spec prose.
  - When a function is already specified in-repo, do not frame the
    task as blocked on an external source; use the in-repo form and
    cite origin without reproducing it.

