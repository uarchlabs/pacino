<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 058
Written by Claude.ai at end of session-057.
Date: 2026-06-28

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

Session-057 was an SC document-consistency and arbitration session.
It took the session-056 sc_decisions.md draft and the two package
files through a fresh pass, closed the "items observed in 056" list,
fixed the SC prediction-phase counter handling, corrected the dynamic
threshold parameters against source, and rewrote bp_arb_spec.md to the
standalone-SC model (separate SC update queue, TAGE response buffer as
SC's prediction queue, CSR enable). No RTL. sc_interfaces.md is the
next write and is now unblocked.

The SC authority doc:
  planning/arch/sc_decisions.md (Draft, session-057)
The arbitration authority doc:
  planning/arch/bp_arb_spec.md (Draft, session-057)

---

## Read This First

Two documents were edited to a resting state this session:
sc_decisions.md and bp_arb_spec.md. Both are internally consistent
against bp_defines_pkg.sv and bp_structs_pkg.sv as of session-057.

Three source-verified facts from session-056 still hold and were not
re-litigated (SC counter-update gate = sc_wrong || sc_lo_upd; BrIMLI
from cookbook predictor.h; SC sum includes tage_extd_ctr at weight 1,
8x term deferred TD#86). Do not re-derive these.

Two facts were newly source-verified this session against the O-GEHL
paper (ISCA 2005, fetched):
  1. Dynamic-threshold seed = number of tables. SC has 5 tables;
     SC_THRSH_MID was 2048, corrected to 10 (2x table count for the
     2*ctr+1-weighted sum). SC_THRSH_MAX corrected 4096 -> 512 (the
     achievable |sum| is ~322, bounded by SC_LSUM_BITS=10). The
     vlo/vvlo band split (threshold>>1, >>2) is NOT from O-GEHL
     (single threshold there); it is a local construction, tuning
     deferred to TD#93.
  2. TC counter width. Seznec uses 7b; SC_TC_BITS was 10, corrected
     to 7.

The SC efficacy question is now TD#93: prior (non-reusable) analysis
showed marginal-to-no benefit from a baseline SC; the later-literature
mechanisms in this design (O-GEHL threshold, two-corner chooser,
BrIMLI) are there to test whether they recover gains. Threshold seed,
band geometry, and whether SC earns its area are settled at PD/perf,
not in the docs.

---

## Session Summary

1. sc_decisions.md fresh pass. The "items observed in 056" list was
   worked and closed:
   - Section numbering fixed (was four "## 8" and a duplicate "## 4";
     now sequential 9-14).
   - SC_CTR_MIN / SC_CTR_MAX added to bp_defines_pkg.sv; sat_sc
     resolves.
   - branch-range field tangle resolved by ELIMINATING
     sc_pred_meta.pc_range (see item 3 below).
   - sc_tage_pred_tkn capture qualified to
     tage_pred_meta.tage_pred_tkn.
   - enum compile blockers fixed (bp_sc_chooser_e trailing comma,
     br_imli_mode_e comma) in the package.
   - SC_IMLI_INDEX_BITS commented out in bp_defines_pkg.sv (leftover).

2. SC prediction-phase counter handling corrected in sc_decisions.md
   section 9. The capture was writing the doubled value (2*ctr+1) into
   sc_upd_ctr and re-feeding it through sat_sc on update, inflating the
   stored counter. Fixed: ctr* read SIGNED, value* = (ctr* <<< 1) + 1
   is LOCAL TO THE SUM only, raw ctr* captured into sc_upd_ctr. Signed
   reads added (counters are -32..31; unsigned reads mis-summed
   negatives). sc_override capture added (was computed, never stored).

3. pc_range eliminated (Q4 resolution). inp_pc is no longer captured
   into sc_pred_meta. BrIMLI update reads sc_upd_inp.branch_range and
   sc_upd_inp.backwards_branch (top-level sc_upd_inp_t fields, FTB-
   supplied). sc_pred_meta_t.pc_range removed from the struct. The
   section 12 BrIMLI double-assignment collapsed to one source.

4. TD#89 / TD#90 revised (FTB-side, per Jeff): FTB stores PC[15:6] of
   the branch (20 bits, both slots) supplied to sc_upd_inp.branch_range;
   FTB stores the branch-target sign for cond br0/br1 as
   backwards_branch0/1 (2 bits, one per slot) supplied to
   sc_upd_inp.backwards_branch. Per-slot update struct carries the
   single matching bit; backwards_branch stays single logic (the two
   bits are FTB-entry storage, not the per-slot update field).

5. Threshold parameters corrected against O-GEHL (see Read This First).
   SC_THRSH_BITS 12->10, SC_THRSH_MID 2048->10, SC_THRSH_MAX 4096->512,
   SC_TC_BITS 10->7. All in bp_defines_pkg.sv.

6. sc_decisions.md editorial: section 2 stale LO/HI threshold prose
   struck (SC_LO/HI_THRESHOLD deleted from package); section 7 reduced
   to a package reference (no restated values); IA notes added (sum
   width deliberate, value*-local, band-split-is-local); TD#93 recorded
   in section 0; sc_abs helper documented; em-dashes in section 12
   comments replaced with ASCII per CLAUDE.md.

7. SC planning file-set decided:
   - DROP sc_cntrl_decisions.md (no content independent of
     sc_decisions sections 8-10).
   - DROP sc_table_entry_formats.md (SC entry is a single signed
     counter; nothing to format).
   - KEEP sc_cntrl_ctr_update_rules.md but write at tb time (it is a
     verification rule table, mirroring tage_cntrl_ctr_update_rules.md;
     cite sc_decisions section 10 as source).
   - sram_init.md stays a shared standalone file (SC-specific fast init
     stays inline in sc_decisions section 13; section 1 context list
     NOT-WRITTEN tag on sram_init was a typo, fixed).
   - sc_decisions.md stays whole; it slims as the hash and interface
     docs are written and sections 9/12 shift to referencing them.

8. bp_arb_spec.md rewritten to the standalone-SC model. The uarch
   options were bounded to three (see Decisions), the merged-struct
   model (cond_pred_*) is retired, SC gets a separate UQ, and the CSR
   enable was added. See Decisions and the arb_spec section list below.

9. bp_arb_spec.md / ras_decisions.md cross-check. ras_decisions.md
   renamed to p-naming (Jeff). arb_spec section 11 item G corrected
   from "RAS items are closed" to the per-item status matching
   ras_decisions.md section 10 (RAS-2 closed, RAS-1 partial, RAS-3
   open). The section 0 ToS-at-p0 caveat is verified: ras_decisions
   s0 TOS-read maps to arb_spec p0; ToS is available at p0.

---

## What Was Accomplished

  - sc_decisions.md: "items observed in 056" list closed; prediction-
    phase counter capture/signedness/override fixed; pc_range removed;
    threshold prose and section-7 values de-duplicated; IA notes and
    TD#93 added. At rest.
  - bp_defines_pkg.sv: SC_CTR_MIN/MAX added; threshold params corrected
    (BITS=10, MID=10, MAX=512, TC_BITS=7); SC_IMLI_INDEX_BITS and
    SC_LO/HI_THRESHOLD out; SC arb params present (SC_UQ_DEPTH,
    SC_UQ_WR_PORTS, SC_RESP_BUF_DEPTH, SC_PRED_CREDITS, SC_UPD_CREDITS,
    SC_STARVE_THRESH; no SC_PQ_DEPTH).
  - bp_structs_pkg.sv: sc_pred_meta_t.pc_range removed; enum commas
    fixed; captured_phr commented out.
  - bp_arb_spec.md: standalone-SC model, separate SC UQ, TAGE response
    buffer as SC PQ, CSR enable caveat, section 2 / 5.5 / 6 made
    consistent, RAS item G corrected, sections 9/10 reduced to stubs.
    At rest.
  - SC planning file-set decided (drop two, defer one, keep the rest).
  - TD#93 recorded; TD#94/#96/#97 referenced from arb_spec (confirm in
    PROJECT_STATUS).

---

## Decisions (session-057)

### SC micro-architecture options (bounded)

Three configurations, not a spectrum:
  1. SC absent -- compile-time removal.
  2. SC present, fused -- FTB sees only the final post-SC direction;
     no TAGE-direct path to FTB.
  3. SC present, separate -- TAGE outputs to FTB at p2; SC refines via
     a separate p3 redirect, applied if SC is enabled.
Runtime sc_enable (CSR) applies to options 2 and 3: when disabled,
FTB/control does not wait for SC responses and issues no SC updates;
FTB buffering/storage of SC-related signals continues.

### SC arbitration model (bp_arb_spec.md)

  - SC tables are single-port RAMs. SC prediction (read, p2->p3) and SC
    update (write, u0/u1) compete for the one RAM port; the section 4.5
    credit arbiter governs that contention unchanged.
  - SC has NO independent prediction FIFO. The TAGE response buffer
    (TAGE_RESP_BUF_DEPTH) is SC's prediction-side storage and acts as
    SC's PQ for arbitration. SC prediction rate is gated by TAGE's.
  - SC has a SEPARATE update queue (sc_upd_inp_t entries). TAGE and SC
    UQs are separate; a single conditional-branch commit enqueues one
    TAGE UQ entry and one SC UQ entry (each entry covers both slots).
  - Backpressure: when SC's arbiter grants an update and stalls a
    prediction, the TAGE response buffer head is held, backpressuring
    TAGE (arb_spec section 11 item C).

### SC struct model

Standalone, not merged. cond_pred_meta_t / cond_pred_upd_inp_t stay
retired (commented out in the package). SC uses sc_pred_meta_t and
sc_upd_inp_t directly. This is the model sc_interfaces.md must target.

---

## Open Work

### SC -- next writes (blocks RTL)

  - planning/interfaces/sc_interfaces.md. NOW UNBLOCKED. The four
    decisions that blocked it in 057 are settled: standalone structs;
    separate SC UQ; TAGE-response-buffer-as-PQ; branch_range/
    backwards_branch/pc_range reconciliation (pc_range gone). The port
    list transcribes from bp_arb_spec.md sections 5.5 / 6.1 into the
    tage_interfaces.md shape. ONE open item to mark as an IC-SC gap,
    not guess: the ST4 PC width -- get_br_imli_idx takes a [9:0] PC
    while BrIMLI's region is PC[15:6]; which PC bits feed ST4 is
    unspecified.
  - planning/interfaces/sc_table_interfaces.md (sc_table ports).
  - planning/arch/sc_table_hash_rules.md (sc_idx_hash and
    get_br_imli_idx -- referenced by sc_decisions, not defined;
    includes the ST4 PC-width question above).
  - planning/arch/sc_cntrl_ctr_update_rules.md -- write at tb time,
    cite sc_decisions section 10.
  - sram_init (SC) reference confirm, sc_tb_decisions.md,
    sc_coverage_plan.md.
  - DROPPED (do not write): sc_cntrl_decisions.md,
    sc_table_entry_formats.md.

### SC -- prerequisites (TD, other units)

  - #87/#88 TAGE: SC prediction sum and chooser consume
    tage_pred_medium and tage_extd_ctr; TAGE must EMIT them. Struct
    fields present; generation logic not written; medium/weak (#87)
    not added.
  - #89/#90 FTB: branch_range[15:6] (20b, both slots) and per-slot
    backwards-branch sign (2b FTB storage; 1b per update struct).
    Revised this session.
  - #91/#92 bpc: route PC p0->p2 to SC (inp_pc_p2 per slot); capture
    phr[9:0] as sc_phr_p2.
  - #84 end-to-end fold check also covers SC ST1-ST3.

### bp_arb_spec.md -- residual

  - TD#94 (arb_spec reconciliation) is the tracked item for the §6
    rewrite; confirm it is marked done or note what remains. The
    standalone model is now IN arb_spec; verify nothing downstream
    still references cond_pred_* or a shared SC/TAGE UQ.
  - Section 0 ToS-at-p0 caveat may be struck (verified this session).
    Left in place; Jeff's call on a section-0 pass.
  - Sections 9 (RTL changes) and 10 (Testbench) are "Section removed"
    stubs; testbench requirements derive from arb_spec 4.5/4.8/11-C and
    belong in the implementing task file.
  - arb_spec item I "ITTAGE arbitration CLOSED. Confirm with PA" vs
    PROJECT_STATUS TD#73 (ITTAGE behavioral arb test deferred). The
    spec section may be closed while the test stays deferred; confirm
    the wording.

### PROJECT_STATUS bookkeeping

  - Confirm TD#93 placed (SC efficacy/threshold tuning).
  - Confirm TD#94 (arb_spec reconciliation), TD#96 (flush protocol,
    referenced arb_spec 7.2 / item E), TD#97 (shared upstream PQ,
    referenced arb_spec 8.2 / item D) all present.
  - TD#89 / TD#90 text updated to the revised FTB-storage wording.

### Carried infra (Jeff's priority call, independent of SC)

  - bp_history close-out bookkeeping (from handoff-057, confirm done):
    s6.6 sha (#83); BP-072/073 status checkboxes; retire
    versions/bp_history.sv.
  - #43 ITTAGE CTR 3b->2b, #75 sim_ittage_fast, #77 path scrub,
    #67/#68 sram_init non-fast, #38 covergroup #7099 re-check.

---

## SC State: PLANNING (decisions + arb settled; interfaces next)

sc_decisions.md and bp_arb_spec.md are at rest and consistent with the
packages. The SC struct and arbitration models are decided (standalone
structs, separate SC UQ, TAGE-buffer-as-PQ, CSR enable). RTL is not
started. sc_interfaces.md is unblocked and is the next write, followed
by sc_table_hash_rules.md, then IA task generation for SC RTL. The
TAGE/FTB/bpc prerequisites (#87-#92) remain open and gate the RTL.

---

## Next Session (058)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-058.md (this file)
  CLAUDE.md
  planning/arch/sc_decisions.md
  planning/arch/bp_arb_spec.md
  planning/interfaces/tage_interfaces.md   (format reference)
  rtl/.../bp_defines_pkg.sv
  rtl/.../bp_structs_pkg.sv

Start by writing planning/interfaces/sc_interfaces.md, matching the
tage_interfaces.md section structure and IC-numbering. Transcribe the
SC port list from bp_arb_spec.md sections 5.5 / 6.1; use the standalone
structs; mark the ST4 PC-width question as an IC-SC gap rather than
guessing it. Then sc_table_hash_rules.md (which resolves that PC-width
question), then IA task generation for SC RTL.

When reviewing or editing the SC docs: check each comment against the
doc/packages before emitting it, audit the whole touched section (not
just changed lines), report facts without rankings or significance
claims unless asked, verify against source before asserting OR
conceding, and do not import one unit's framing onto another (the 056
error was carrying TAGE's arbitration apparatus onto SC).

---

## Postmortem Record -- PA performance (session-057)

Continuing the trend log (052/053 unchecked claims; 054 over-asking;
055 one under-audited line; 056 late-source, imported framing, jargon,
50% review noise). 057 was a stronger session than 056; the recurring
failure modes appeared early and were corrected, several after direct
user calls.

1. Padding and an unsourced number. Early in the session the PA wrote
   "gets the determined 80%," a fabricated percentage with no basis,
   alongside decorative closers ("it tells you exactly," "the order
   that doesn't make either of us guess"). The user flagged all three.
   The 80% is the same class of error as the 056 unsourced assertions:
   a number stated as if measured. Corrected; the engineering-register
   instruction block was then written into the project settings to
   make the constraint durable.

2. Volume. Multiple responses ran long -- a ~200-word turn to ask a
   yes/no path-confirmation whose likely answer the PA already knew.
   The user called it directly ("reduce the volume"). Improved after
   the call but required the reminder.

3. Manufactured hazards. On the sc_interfaces Q1-Q4 questions the PA
   dressed a plain redundancy question ("is sc_phr_p2 a separate port
   or sliced internally") as a "trap from 056," and flagged a "real
   asymmetry" that was just two modules with different pipeline entry
   points. Both were filler elevating routine questions to hazards.
   The user called both. This is a softer form of the 056 imported-
   framing error: inventing significance rather than importing it.

4. Stale-timing copy. The first sc_interfaces Q-set attached "p0" to a
   folded-history input for a predictor that starts at p2, copied from
   TAGE's timing without reading SC's stage. Caught by the user in one
   line. Same stale-vs-authority pattern logged in 054/056.

What held: the source-pulled work was correct and was the work the
user kept. The O-GEHL threshold correction (seed = table count, MAX =
sum range, TC = 7b) came from the fetched paper, not recall, and set
four package parameters. The counter-capture/signedness bug in
sc_decisions section 9 was found by reading the widths against the
struct. The bp_arb_spec SC/TAGE inconsistencies (section 2 lockstep,
section 5.5 PQ params vs no-independent-PQ) were found by checking the
document against itself and the packages. The RAS item-G overstatement
was caught by cross-reading ras_decisions.md section 10. When the PA
resisted conceding a point until the source was checked (the ctr0
signed-declaration exchange), the correction stuck and was right.

Pattern to carry into 058:
  - No number without a source. A fabricated percentage is the same
    error as an unchecked assertion.
  - Shortest response that carries the facts and the question. Do not
    pad; do not restate for emphasis.
  - Do not manufacture significance (traps, asymmetries, hazards) for
    routine questions, the mirror of the 056 imported-framing error.
  - Read the unit's own timing/design before copying a sibling unit's
    port or stage.
  - The kept output is the source-checked output. Pull the source
    first, before asserting OR conceding.

