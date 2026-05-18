# Session Handoff 041
Written by Claude.ai at end of session-040.
Date: 2026-05-17

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Session Summary

Session-040 completed ittage_cntrl.sv in three prompts
(BP-034, BP-035, BP-036) plus one inline fix. The
prediction path, update path, and testbench are all
complete. 76 checks pass, lint clean.

---

## What This Session Accomplished

### BP-034 (complete)

ittage_cntrl.sv prediction path. Provider scan,
alternate provider scan, allocation candidate selection,
UAON mux, ittage_pred_meta_t assembly, p2 flop,
ittage_pred_rdy_p2. Update path fully stubbed.

Key decisions:
  - CNTRL_BITS_WIDTH=46, IT_MAX_ALLOC_DATA_WIDTH=57
    declared as localparams in #() block following
    ittage_table.sv pattern.
  - CB_* field position localparams match ittage_table.sv
    exactly.
  - prm_tbl_sel_u0 and alt_tbl_sel_u0 were incorrectly
    driven from prediction scan intermediates (prm_comp,
    alt_comp). This was identified as a defect and fixed
    in BP-036.
  - Lint clean with -Wno-VARHIDDEN (NUM_PRED_SLOTS
    shadowing from ittage_table.sv inclusion).

### BP-035 (complete)

ittage_cntrl.sv update path added. CTR update, USE
update, EPC update, TGT update, allocation write data
assembly, UAON counter update, aging interval and epoch
logic, u_eff computation replacing raw USE in prediction
path, ittage_upd_rdy_u1.

Key decisions:
  - upd_index_u0[s] carries provider index (prm_idx
    when using_primary=1, alt_idx when using_primary=0).
  - alc_index_u0[s] = upd_index_u0[s]. Over-design kept
    until performance analysis.
  - UAON update gated on ittage_hit from update meta.
  - u_eff replaces raw USE in allocation scan and meta
    fields ittage_prm_useful and ittage_alt_useful.

### BP-036 (complete)

prm_tbl_sel_u0 / alt_tbl_sel_u0 fix plus
tb_ittage_cntrl.sv. 76 PASS, 0 FAIL.

RTL defects found and fixed by testbench:
  1. prm_tbl_sel_u0 and alt_tbl_sel_u0 driven from
     prediction scan intermediates instead of update
     input meta. Fixed: now driven from
     ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_comp
     and .ittage_alt_comp.
  2. prv_alt_scan always_comb landed in Verilator
     stl_sequent (evaluated once at sim start) because
     all reads were module inputs. Fixed by gating on
     pred_val_p1[s] (a FF output) to force nba_sequent.
  3. meta_p1 intermediate wire caused scheduling
     inversion. Fixed by eliminating meta_p1; meta_p2_reg
     now reads scan outputs directly.

Verilator stl_sequent rule added to CLAUDE.md:
  always_comb blocks that must re-evaluate after FF
  updates must read at least one FF output. Pure
  module-input-only always_comb blocks are classified
  stl_sequent and will not re-evaluate after sim start.
  Gate prediction scan blocks on a registered valid
  signal to force nba_sequent classification.

---

## Methodology Updates This Session

  1. Update-path signals sourced from captured meta.
     prm_tbl_sel_u0, alt_tbl_sel_u0, upd_index_u0 and
     all update-time table selectors must be driven from
     ittage_upd_inp_u0[s].ittage_pred_meta, not from
     live prediction scan intermediates. Predict-time
     meta is captured into the FTQ and returned at
     update time. This is the fundamental meta-at-predict
     / consume-at-update microarchitectural pattern.
     Violation introduced in BP-034 Step 12 by driving
     from prediction scan signals as placeholders while
     the update path was stubbed.

  2. Verilator stl_sequent rule -- see CLAUDE.md.

---

## Open Items Carried Forward

  - TD #43: ittage_pred_strong definition in
    ittage_cntrl_decisions.md incorrect. Needs update
    to CTR > 0 (not NULL). Deferred.
  - TD #44: ittage_cntrl_decisions.md decoration flags
    section needs correction when TD #43 is implemented.
  - TD #45: TAGE T0 index handling needs revisit.
    Recorded this session during upd_index_u0 discussion.
  - alc_index_u0 over-design: currently = upd_index_u0.
    Correct value is alc_idx from meta. Deferred until
    performance analysis.
  - CTR width: IT_TBL_CTR currently 3b. 2b may be
    sufficient. Multi-file change deferred (TD #43
    scope). Impacts bp_defines_pkg.sv, bp_structs_pkg.sv,
    ittage_table.sv, ittage_cntrl.sv, tb_ittage_table.sv,
    tb_ittage_cntrl.sv.

---

## Next Session (041)

ittage_cntrl.sv is complete. Next module is ittage.sv.

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-041.md (this file)
  CLAUDE.md

### Planned prompts

**BP-037 -- ittage.sv without arbitration**
  Instantiates ittage_cntrl and five ittage_table
  instances (IT1-IT5) with correct per-table parameter
  assignments. Handles sram_init, ittage_rdy, signal
  fanout between controller and tables. Prediction and
  update paths wired. No arbitration logic.

  Key wiring note: alc_wd_u0 is driven by ittage_cntrl
  at IT_MAX_ALLOC_DATA_WIDTH=57. Each ittage_table
  instance declares its own ALLOC_DATA_WIDTH from
  CNTRL_BITS_WIDTH+THIS_TAG_BITS (54, 54, 55, 55, 57
  for IT1-IT5). ittage.sv connects the lower
  THIS_ALLOC_DATA_WIDTH bits of the ittage_cntrl output
  to each table port. IT_MAX_ALLOC_DATA_WIDTH covers
  this by design.

  Files needed:
    ittage_interfaces.md
    ittage_table_interfaces.md
    ittage_cntrl_decisions.md
    bp_defines_pkg.sv
    bp_structs_pkg.sv
    ittage_table.sv
    ittage_cntrl.sv

**BP-038 -- ittage.sv arbitration logic**
  Adds arbitration logic to ittage.sv following the
  TAGE arbitration pattern in the project. Review
  tage_cntrl.sv arbitration before writing this prompt.

  Files needed: same as BP-037 plus tage_cntrl.sv for
  arbitration pattern reference.

**BP-039 -- tb_ittage.sv**
  Full testbench with pre-computed test vectors.
  Instantiates ittage.sv with actual ittage_table
  instances in the loop. Per BP-033-FIX-1 and BP-036
  methodology: Test Vector Table with all expected
  values pre-computed in prompt. Separate from
  implementation prompts to reduce context pressure
  and correlated-bug risk.

  Apply Verilator stl_sequent rule from CLAUDE.md when
  writing testbench stimulus tasks.

  Files needed: ittage.sv, ittage_cntrl.sv,
  ittage_table.sv, bp_defines_pkg.sv, bp_structs_pkg.sv.

