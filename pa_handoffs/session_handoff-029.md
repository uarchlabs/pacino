# Session Handoff 029
Written by Claude.ai at end of session-028.
Date: 2026-04-13

This session executed BP-022c, triaged debt #36,
and executed BP-023a and BP-023b. Read PROJECT_STATUS.md,
then this file, then CLAUDE.md to restore full context.

---

## What This Session Covered

Session context restored from session_handoff-028.

- BP-022c executed: minor housekeeping in bp_defines_pkg.sv.
  SC_TBL_INDEX_BITS localparam removed (no active consumers
  confirmed by grep). Commented-out alias block (lines
  165-170) removed. Lint exit 0, zero warnings. Both deferred
  items from BP-022b closed. BP-022 cleanup series complete.

- Debt #36 triaged: sim_tage_table TC6 USE field update
  not reflected in cntrl_bits_p1. Full trace through
  tage_table.sv write path, bw_ram read-address flop
  timing, and testbench stimulus confirmed the defect was
  already fixed by HAND-FIX-001 (session-022). TC6 passes
  with cntrl=39 as expected. Debt #36 marked closed.
  No RTL change required.

- NUM_PRED_SLOTS changed from 1 to 2 in bp_defines_pkg.sv
  before running BP-023a. This is the architectural default
  per debt #1. TRX_SLOT_BITS fix applied in BP-023a is
  valid for both values but no longer needed at value 2.

- BP-023a executed: added TAGE arbitration parameters to
  bp_defines_pkg.sv and arbitration structs to
  bp_structs_pkg.sv.
  bp_defines_pkg.sv: TAGE arbitration parameters (7,
  exact values from bp_arb_spec.md section 4.2). Stub
  sections for LP, FTB, SC, ITTAGE (all 0, TBD).
  TRX_SLOT_BITS localparam added near NUM_PRED_SLOTS to
  avoid ASCRANGE when NUM_PRED_SLOTS=1 ($clog2(1)=0).
  bp_structs_pkg.sv: bp_arb_trx_t, sc_pred_meta_t stub
  (8b reserved), sc_upd_inp_t stub (8b reserved),
  cond_pred_meta_t, cond_pred_upd_inp_t added.
  bp_ras_snapshot_t confirmed present: fields tosr, tosw,
  bos (all RAS_PTR_BITS=6b). No change made.
  Lint exit 0. All 12 targets green. 46/46 PASS.

- BP-023b executed: added PQ, UQ, credit arbiter,
  competing-stage mux, bp_arb_trx_t register, and
  prediction response buffer to tage.sv. Added trx_type
  gating to tage_cntrl.sv.
  All 46 existing tests pass. Lint exit 0. All 12 green.
  Two key decisions documented below.

---

## Decisions Made This Session

### NUM_PRED_SLOTS set to 2

Changed from 1 to 2 in bp_defines_pkg.sv before BP-023a.
This is the architectural default. Debt #1 cleanup
(generate removal and single-slot tests) remains deferred.

### TRX_SLOT_BITS localparam

Added to bp_defines_pkg.sv. Value:
  (NUM_PRED_SLOTS > 1) ? $clog2(NUM_PRED_SLOTS) : 1
Used in bp_arb_trx_t.trx_slot field width. Prevents
ASCRANGE at NUM_PRED_SLOTS=1. Semantically identical
for NUM_PRED_SLOTS >= 2.

### consumer_ready tied internally (D1)

consumer_ready not added as a port to tage.sv. Tied to
1'b1 internally. Reason: tb_tage.sv cannot be modified
and Verilator drives unconnected inputs to 0, which would
stall the response buffer and break all 46 prediction
tests. SC->TAGE response buffer backpressure deferred to
SC integration task. This decision blocks TB-ARB-07
(response buffer full test) until consumer_ready is
promoted to a port.

### trx_type forwarded combinationally (D2)

trx_type forwarded to tage_cntrl as arb_grant_upd
(combinational) not as registered arb_trx_r.trx_type.
Reason: registered value lags by 1 cycle. Write enables
in tage_cntrl must be gated in the same cycle as the UPD
grant. Using registered value would cause writes to fire
one cycle late, failing all 46 update tests.
The arb_trx_r register exists for pipeline tracking only.
Risk: when concurrent pred+upd tests (TB-ARB-03,
TB-ARB-04) are added in BP-023c, this combinational
path may not hold stable through the pipeline if the
grant signal changes while tage_cntrl is mid-pipeline.
Assigned new debt -- see below.

### Bypass path only exercised

All 46 existing tests hit the arbiter bypass path (rule 5
or rule 6 -- one queue active at a time). FIFO storage
arrays and credit registers are architecturally correct
but never written or read in current test patterns.
BP-023c TB-ARB-06 will be the first test to exercise
actual FIFO reads and writes.

---

## Technical Debt Status After This Session

Closed this session:
  #36 -- sim_tage_table TC6 USE field update (verified
         fixed by HAND-FIX-001, no RTL change needed)

New debt assigned this session:
  #37 -- trx_type forwarded combinationally from
         arb_grant_upd instead of from registered
         arb_trx_r.trx_type. When concurrent pred+upd
         tests are added (TB-ARB-03, TB-ARB-04), verify
         that grant signal stability through tage_cntrl
         pipeline is maintained. If not, promote
         arb_trx_r.trx_type to the gating signal and
         adjust write-enable timing accordingly.
         Investigate in BP-023c before closing.

Still open:
  #7  -- curs/curs_v rollback undefined

---

## Files Modified This Session

  frontend/branch_predictor/rtl/bp_defines_pkg.sv
    -- BP-022c: SC_TBL_INDEX_BITS removed.
                Commented-out alias block removed.
    -- BP-023a: TAGE arbitration parameters added.
                LP/FTB/SC/ITTAGE stub sections added.
                TRX_SLOT_BITS localparam added.
                NUM_PRED_SLOTS changed from 1 to 2.

  frontend/branch_predictor/rtl/bp_structs_pkg.sv
    -- BP-023a: bp_arb_trx_t added.
                sc_pred_meta_t stub added.
                sc_upd_inp_t stub added.
                cond_pred_meta_t added.
                cond_pred_upd_inp_t added.

  frontend/branch_predictor/rtl/tage.sv
    -- BP-023b: PQ FIFO added (depth 8, tage_pred_inp_t).
                UQ FIFO added (depth 8,
                cond_pred_upd_inp_t, 2 write ports).
                Credit arbiter added (rules 1-7).
                Competing-stage mux added.
                bp_arb_trx_t pipeline register added.
                Response buffer added (depth 2,
                cond_pred_meta_t).
                New ports: pq_not_full, upd_rdy[1:0],
                tage_pred_rdy_p2.
                consumer_ready tied to 1'b1 internally.

  frontend/branch_predictor/rtl/tage_cntrl.sv
    -- BP-023b: trx_type input port added.
                Write enables gated on trx_type==1.
                Prediction result routing gated on
                trx_type==0.

  Makefile (frontend/branch_predictor/)
    -- BP-023b: -Wno-PINMISSING added to sim_tage,
                sim_tage_fast, lint_tage targets.
                Required because new output ports
                (pq_not_full, upd_rdy) are unconnected
                in tb_tage.sv.

---

## Next Session (029)

### Step 1: BP-023c decision -- consumer_ready port

Three options, decision required before prompt is written:

  Option A: Add consumer_ready as a port in BP-023c.
    Requires one-line change to tage.sv (port declaration),
    Makefile suppression update, and tb_tage.sv wired.
    Enables TB-ARB-07 as specified. Recommended.

  Option B: Skip TB-ARB-07 in BP-023c. Defer to SC
    integration task. Write TB-ARB-01 through TB-ARB-06
    and TB-ARB-08 only (7 of 8 tests).

  Option C: Promote consumer_ready to port in a small
    BP-023b-fix pass before BP-023c. Then write full
    BP-023c with all 8 tests.

  Claude.ai recommendation: Option A. Fold the port
  promotion into BP-023c as a prerequisite step.
  One-line tage.sv change, one Makefile suppression
  removed, tb_tage.sv wired. All 8 ARB tests then
  implementable as specified.

### Step 2: BP-023c -- tb_tage.sv ARB tests

Per bp_arb_spec.md section 10.1:
  TB-ARB-01 through TB-ARB-08.
  Test count grows from 46 to 54.
  Debt #37 must be investigated during TB-ARB-03
  and TB-ARB-04 (concurrent pred+upd tests).

### Step 3: Coverage planning

Scope the formal coverage approach before bp_cluster:
  - Coverage matrix structure
  - Per-predictor coverage tracking
  - Verilator code coverage integration
  - Tooling and Makefile targets
  This step was deferred from session-028.

### Step 4: bp_cluster integration

Begins after Steps 2 and 3 complete.

---

## Prompt Files Created This Session

  prompts/BP-022c.md  -- PASS, lint only, both items removed
  prompts/BP-023a.md  -- PASS, all 12 targets green
  prompts/BP-023b.md  -- PASS, 46/46, lint green
