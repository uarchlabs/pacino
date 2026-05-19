# Branch Predictor Arbitration and Prediction Pipeline Specification
```
 FILE:    bp_arb_spec.md
 SOURCE:  various
 STATUS:  Draft -- session-025
 UPDATED: 2026-05-18
 CONTACT: Jeff Nye
```

## Status
Draft -- session-025.  Supersedes tage_pred_upd_arb_spec.md.
Resolves debt #33.

## 1. Problem Statement

The branch predictor complex contains multiple synchronous RAM-based
predictors.  Each predictor has a prediction path (read) and an
update path (write) that compete for the same RAM access stage.  No
protocol exists in the current design to manage that competition or
to define how multiple predictors interact to produce a final
prediction.

This spec defines:

  a. The per-predictor buffering and arbitration mechanism that
     allows prediction and update requests to overlap safely.

  b. The pipeline stage model for all predictors and how later
     stages override earlier ones via a redirect mechanism.

  c. The update synchronization constraints between predictors
     that share a commit event (SC and TAGE).

  d. The RAS snapshot model, which does not fit the RAM
     arbitration pattern.


## 2. Predictor Inventory

  Predictor   RAM-based   Pred stage   Override stage   Update timing
  ---------   ---------   ----------   --------------   -------------
  uFTB        No          s0           s0               Immediate
  RAS         No          s0           s0               Speculative push /
                                                        snapshot restore
  FTB         Yes         s1/s2        s1/s2            u0/u1
  LP          Yes         s1/s2        s1/s2            u0/u1
  TAGE        Yes         s2           s2               u0/u1
  SC          Yes         s3           s3               u0/u1 lockstep
                                                        with TAGE
  ITTAGE      Yes         s2           s2               u0/u1

SC does not have an independent prediction request path.  Its p0
is fed from the TAGE s2 response, not from fetch directly.  See
section 6.

The indirect predictor chain (RAS + ITTAGE) shares the stage timing
of its direct counterparts but has different update and correction
semantics.  It is deferred to a later spec.  Placeholders are
included here where the indirect chain interacts with the direct
chain.


## 3. Pipeline Stage Model and Override Chain

### 3.1  Stage definitions

  s0   Inputs presented to RAMs (flopped).  PC hash, folded
       history available.
  s1   RAM outputs available.  Tag match, hit processing.
  s2   Result formation.  Provider selection, meta capture.
  s3   Statistical corrector threshold decision.

  u0   Update address and write data presented to RAMs.
  u1   RAM write completes.

### 3.2  Predictor stage assignments

  s0:     uFTB, RAS
  s1/s2:  FTB, LP
  s2:     TAGE, ITTAGE
  s3:     SC (chained from TAGE s2 output)

### 3.3  Override chain

A later stage overrides a previous stage if its prediction
differs.  Override is implemented as a redirect: the overriding
predictor compares its result against what the FTQ currently
holds for that fetch block.  If they differ it asserts a redirect
with the corrected target PC and the FTQ index of the fetch being
corrected.

The FTQ acts on the earliest available prediction (uFTB/RAS at s0)
and issues a fetch immediately.  It does not wait for later
predictors.  Later predictors issue redirects independently when
their results are ready.

Override priority (highest to lowest):
  SC (s3) > TAGE (s2) > FTB/LP (s1/s2) > uFTB/RAS (s0)

For indirect branches:
  ITTAGE (s2) > RAS (s0)  [indirect chain, deferred]

A redirect from a later stage supersedes any earlier redirect
for the same FTQ entry.  The FTQ must track which redirects are
stale.  This is a FTQ design responsibility, not a predictor
responsibility.

### 3.4  Redirect interface (per predictor, per stage)

Each RAM-based predictor that can redirect exposes:

  output logic                    <pred>_redir_val_<sN>
  output logic [VA_WIDTH-1:0]     <pred>_redir_tgt_<sN>
  output logic [FTQ_IDX_BITS-1:0] <pred>_redir_ftq_idx_<sN>

uFTB and RAS drive the FTQ directly at s0 without a redirect
interface -- they are the initial prediction, not a correction.

Redirect signal naming examples:
  ftb_redir_val_s2
  lp_redir_val_s2
  tage_redir_val_s2
  itage_redir_val_s2
  sc_redir_val_s3


## 4. RAM Arbitration Model

### 4.1  Competing stage

Each RAM-based predictor has one cycle in which prediction and
update compete for the RAM inputs.  This is the competing stage:

  Prediction:  p0 presents RAM read address (flopped input).
  Update:      u0 presents RAM write address and data (flopped).

Only one transaction may own the competing stage per cycle.  A
credit-based arbiter selects from a Prediction Queue (PQ) and an
Update Queue (UQ) placed in front of each predictor.

### 4.2  Common arbitration parameters (per predictor)

Each RAM-based predictor has its own parameter set.  Names are
prefixed with the predictor identifier.  TAGE is shown as the
reference instance.

  // Queue depths
  localparam int TAGE_PQ_DEPTH        = 8;
  localparam int TAGE_UQ_DEPTH        = 8;

  // UQ write port width
  // 4-at-once commit causes 2-cycle backpressure to commit.
  localparam int TAGE_UQ_WR_PORTS     = 2;

  // Response buffer depth
  localparam int TAGE_RESP_BUF_DEPTH  = 2;

  // Credit arbiter
  localparam int TAGE_PRED_CREDITS    = 4;
  localparam int TAGE_UPD_CREDITS     = 1;
  localparam int TAGE_STARVE_THRESH   = 8;

FTB, LP, and ITTAGE have analogous parameter sets with their own
prefix and independently chosen values.  SC shares TAGE's UQ
(see section 6).

### 4.3  Prediction Queue (PQ)

Structure:
  - FIFO.  Depth <PRED>_PQ_DEPTH.
  - Entry type: prediction input struct for that predictor.
  - Binary counter head/tail, registered full/empty flags.
  - Bypass: if PQ is empty and arbiter grants prediction this
    cycle, incoming request bypasses FIFO and drives the
    competing stage directly.

Handshake (producer side):
  - Producer presents val and inp signals.
  - PQ asserts not_full.
  - Producer may issue only when not_full.
  - Full: backpressure to fetch.  No drop.

Handshake (arbiter side):
  - Arbiter asserts pq_rd_en on grant.
  - PQ presents head entry.
  - PQ advances pointers on pq_rd_en.

### 4.4  Update Queue (UQ)

Structure:
  - FIFO.  Depth <PRED>_UQ_DEPTH.
  - Entry type: update input struct for that predictor.
  - Two write ports (<PRED>_UQ_WR_PORTS=2).  Up to 2 updates
    may be enqueued per cycle.
  - Bypass: if UQ empty and arbiter grants update, incoming
    entry bypasses FIFO.

Handshake (producer side):
  - Commit presents upd_val[s] and upd_inp[s] per slot.
  - UQ asserts upd_rdy[s] per slot when accepted.
  - When UQ full, upd_rdy deasserts.  Commit holds valid
    until accepted.

Handshake (arbiter side):
  - Arbiter asserts uq_rd_en on grant.
  - UQ presents head entry.

Updates are program-order.  FIFO must not be reordered.

### 4.5  Credit Arbiter

Initialization:
  pred_credits = <PRED>_PRED_CREDITS
  upd_credits  = <PRED>_UPD_CREDITS
  starve_ctr   = 0

Per-cycle grant logic (priority order):

  1. resp_buf_full asserted: no grant.  (Prediction path
     blocked; no point issuing a new prediction.)
     Note: rule 1 does not block update grants.

  2. Starvation override: UQ non-empty AND
     starve_ctr >= <PRED>_STARVE_THRESH:
       Grant update.  Reset starve_ctr.
       Reload upd_credits = <PRED>_UPD_CREDITS.

  3. Both queues non-empty, pred_credits > 0:
       Grant prediction.
       Decrement pred_credits.
       Increment starve_ctr.

  4. Both queues non-empty, pred_credits == 0:
       Grant update.
       Reload pred_credits = <PRED>_PRED_CREDITS.
       Reload upd_credits  = <PRED>_UPD_CREDITS.
       Reset starve_ctr.

  5. PQ non-empty only:
       Grant prediction unconditionally.
       Do not consume prediction credits.

  6. UQ non-empty only:
       Grant update unconditionally.

  7. Both empty: no grant.

### 4.6  Competing stage register

The arbiter output is captured in a transaction register that
travels with the pipeline from p0/u0 to p1/u1:

  typedef struct packed {
    logic                              trx_type; // 0=PRED 1=UPD
    logic [$clog2(NUM_PRED_SLOTS)-1:0] trx_slot;
  } bp_arb_trx_t;

The full input data (pred_inp or upd_inp) is held stable at the
queue head until the grant is de-asserted.  The transaction
register carries only type and slot.  This avoids a wide
registered copy of the full input struct.

At p1/u1:
  - trx_type==PRED: RAM read result flows to result formation.
  - trx_type==UPD:  RAM write completes.  No result routing.

### 4.7  Prediction Response Buffer

Structure:
  - <PRED>_RESP_BUF_DEPTH entries (default 2).
  - Bypass when empty and consumer ready.
  - Entry: prediction metadata struct + valid flag.

Handshake:
  - s2 result formation asserts s2_valid.  Result enters buffer.
  - Consumer (FTQ or SC for TAGE) presents consumer_ready.
  - Buffer asserts pred_rdy when head is valid.
  - When buffer full and consumer not ready, resp_buf_full
    asserted to arbiter (blocks new prediction grants, rule 1).

### 4.8  Same-entry conflict resolution

When a prediction and an update targeting the same RAM entry
are both pending, prediction is granted first per the credit
rules (section 4.5, rule 3).  The prediction reads pre-update
state.  The update is granted in a subsequent cycle.

This is defined behavior.  No address comparison is performed
at the arbiter.  The prediction was originally issued before
the branch resolved; it would have seen pre-update state in a
non-buffered design as well.  The buffering does not change
the fundamental ordering.


## 5. Per-Predictor Arbitration Instances

### 5.1  FTB

  Parameters:  FTB_PQ_DEPTH, FTB_UQ_DEPTH, FTB_UQ_WR_PORTS,
               FTB_RESP_BUF_DEPTH, FTB_PRED_CREDITS,
               FTB_UPD_CREDITS, FTB_STARVE_THRESH.
  Values:      TBD.  Independent of TAGE sizing.
  Pred input:  ftb_pred_inp_t  (PC + branch_id + fetch block
               boundary fields -- wider than tage_pred_inp_t)
  Upd input:   ftb_upd_inp_t   (resolved fetch block metadata)
  Pred output: ftb_pred_meta_t (branch targets, block end PC,
               taken map)
  Override:    s1/s2.  ftb_redir_val_s2.
  Notes:       FTB updates on every resolved fetch block, not
               only on mispredictions.  UQ drain rate may be
               higher than TAGE.  Size UQ_DEPTH accordingly.

### 5.2  Loop Predictor (LP)

  Parameters:  LP_PQ_DEPTH, LP_UQ_DEPTH, LP_UQ_WR_PORTS,
               LP_RESP_BUF_DEPTH, LP_PRED_CREDITS,
               LP_UPD_CREDITS, LP_STARVE_THRESH.
  Values:      TBD.  LP metadata is small; shallower queues
               may be sufficient.
  Pred input:  lp_pred_inp_t  (PC + branch_id -- narrow)
  Upd input:   lp_upd_inp_t
  Pred output: lp_pred_meta_t
  Override:    s1/s2.  lp_redir_val_s2.
  Request:     Fetch presents prediction request to LP PQ
               independently (Option B).  Same PC as TAGE
               but separate queue instance.  No shared
               upstream PQ at this time.
  Notes:       LP planned to complete at p2.  If LP tables
               are small enough to complete at p1, the
               response stage is s1 and the override fires
               one cycle earlier.  Decision deferred until
               LP is sized.

### 5.3  TAGE

  Parameters:  TAGE_PQ_DEPTH=8, TAGE_UQ_DEPTH=8,
               TAGE_UQ_WR_PORTS=2, TAGE_RESP_BUF_DEPTH=2,
               TAGE_PRED_CREDITS=4, TAGE_UPD_CREDITS=1,
               TAGE_STARVE_THRESH=8.
  Pred input:  tage_pred_inp_t
  Upd input:   cond_pred_upd_inp_t  (contains tage and sc
               sub-structs as fields -- see section 6.2)
  Pred output: cond_pred_meta_t     (contains tage and sc
               sub-structs as fields -- see section 6.1)
  Override:    s2.  tage_redir_val_s2.
  Notes:       TAGE response buffer holds cond_pred_meta_t.
               SC prediction chains from that buffer (section 6).
               Single UQ entry covers both TAGE and SC update
               (section 6.2).  Full arbitration spec in section
               4 was developed with TAGE as the reference instance.

### 5.4  ITTAGE

  Parameters:  ITTAGE_PQ_DEPTH=4, ITTAGE_UQ_DEPTH=2,
               ITTAGE_UQ_WR_PORTS=2, ITTAGE_RESP_BUF_DEPTH=2,
               ITTAGE_PRED_CREDITS=2, ITTAGE_UPD_CREDITS=1,
               ITTAGE_STARVE_THRESH=2.
  Pred input:  ittage_pred_inp_t
  Upd input:   ittage_upd_inp_t
  Pred output: ittage_pred_meta_t
  Override:    s2.  ittage_redir_val_s2.  Indirect chain only.


## 6. Statistical Corrector (SC) -- Chained Predictor

SC is a Seznec-style statistical corrector.  It has its own RAM
tables of signed counters and a thresholding process.  It adds
one pipeline stage (s3) after TAGE s2.

### 6.1  Merged metadata structs

TAGE and SC metadata are merged into two top-level structs that
carry per-predictor sub-structs as named fields.  This unifies
the prediction response and the update request into a single
object per branch, eliminating any cross-module synchronization
requirement.

Prediction metadata (captured at predict time, carried in FTQ):

  typedef struct packed {
    tage_pred_meta_t  tage;       // TAGE provider, CTR, etc.
    sc_pred_meta_t    sc;         // SC counter indices, sum
    logic             sc_valid;   // sc field populated this branch
  } cond_pred_meta_t;

Update input (presented at commit, enqueued in single UQ):

  typedef struct packed {
    tage_upd_inp_t  tage;         // tage_pred_meta_t + resolution
    sc_upd_inp_t    sc;           // sc_pred_meta_t + resolution
    logic           sc_valid;     // sc field valid for this update
    logic           resolved_taken;
    logic           cond_mispredict;
  } cond_pred_upd_inp_t;

sc_valid is a runtime bit.  It is asserted when SC participated
in the prediction for this branch (SC RAM was accessed and
counters were read).  A CSR-based enable mechanism may gate SC
participation; sc_valid reflects the actual runtime state
regardless of how it is driven.  The CSR mechanism is not
defined in this spec.

Both tage_upd_inp_t and sc_upd_inp_t retain their existing
definitions as sub-struct types.  cond_pred_meta_t and
cond_pred_upd_inp_t are new top-level wrappers.

### 6.2  Prediction path

SC does not have an independent fetch-facing PQ.  Its prediction
input is the TAGE response buffer output, which now carries
cond_pred_meta_t.  When the TAGE response buffer presents a
valid entry, SC begins its own RAM access at p0 (which is s3
from the fetch perspective).

  TAGE resp buffer output (s2)  -->  SC p0 (RAM addr, using
                                      tage sub-field as index)
                                 -->  SC p1 (RAM out, counter read)
                                 -->  SC s3 (threshold decision,
                                      updates sc sub-field)
                                 -->  sc_redir_val_s3 if result
                                      differs from tage.tage_pred_tkn

The TAGE response buffer entry (cond_pred_meta_t) is held stable
while SC processes it.  SC writes its results into the sc field
of the same struct before passing it downstream.  The final
cond_pred_meta_t with both fields populated exits SC's response
buffer at s3.

SC has its own response buffer (SC_RESP_BUF_DEPTH) after s3.
Backpressure from the SC response buffer propagates to the TAGE
response buffer consumer_ready input -- if SC cannot accept a
new entry, TAGE's response buffer stalls.

SC has no independent credit arbiter for prediction.  Its
prediction rate is gated entirely by TAGE's prediction rate.

### 6.3  Update path

TAGE and SC share a single UQ.  The UQ entry type is
cond_pred_upd_inp_t.  A single commit event enqueues one entry
covering both TAGE and SC.  A single arbiter grant drains one
entry per cycle.  At u0 the entry fans internally:
  - tage sub-field drives TAGE RAM update logic
  - sc sub-field drives SC RAM update logic (gated on sc_valid)

Both TAGE and SC RAM writes complete at u1 from the same grant.
No cross-module grant synchronization is required.  The lockstep
constraint is structurally enforced by the shared queue.

### 6.4  SC parameters

  SC_RESP_BUF_DEPTH.  Values: TBD.
  No separate UQ parameters -- SC shares the TAGE UQ.
  UQ sizing is driven by TAGE parameters (section 4.2).


## 7. Non-RAM Predictors

### 7.1  uFTB

uFTB is fully combinational.  No internal SRAMs.  No PQ, UQ,
or arbiter required.  Output is presented directly to the FTQ
at s0.  uFTB result is the initial prediction that fetch acts
on; it is not a redirect.

If the FTQ cannot accept the uFTB output (FTQ full), uFTB
holds its output stable.  No response buffer needed.

### 7.2  RAS

RAS is a register-file-based stack.  It does not have
synchronous SRAMs in the TAGE sense.  No PQ, UQ, or credit
arbiter required.

#### Prediction

RAS prediction is a read of the top-of-stack (TOS) register,
which is combinational.  A return instruction detected at s0
causes the RAS to present the TOS value as the predicted
target.  This is the initial s0 prediction, not a redirect.

#### Push (call)

A call instruction is detected at predecode/decode before
commit.  The return address is pushed onto the RAS
speculatively at that point.  Because predecode is speculative,
the push may be on a mispredicted path.

#### Snapshot and restore

RAS state (TOSR, TOSW, BOS -- defined in bp_ras_snapshot_t in
bp_structs_pkg.sv) must be checkpointed into the FTQ entry at
the time of the prediction that consumed or produced the RAS
state.  On mispredict or flush the RAS is restored from the
FTQ snapshot of the last known-good entry.

The bp_ftq_entry_t struct must include a bp_ras_snapshot_t
field.  This is the RAS update mechanism -- not a RAM write
but snapshot retirement.

#### Commit

On commit the FTQ snapshot for the retiring entry is released.
No RAM write occurs.  The RAS stack pointer advances as
speculative state is confirmed.

#### Open items

  RAS-1: Push timing.  Confirm whether push occurs at
         predecode or decode.  This affects how many cycles
         the return address is available before the
         corresponding fetch.
  RAS-2: Stack depth and register file size.  Not yet
         defined in bp_defines_pkg.sv.
  RAS-3: Recovery on flush.  Flush (_px signals) is not
         yet defined.  RAS restore on flush must be
         revisited when flush is specified.


## 8. Prediction Request Distribution

### 8.1  Current approach (Option B)

Fetch presents prediction requests independently to each
predictor's PQ.  The same PC fans out to FTB PQ, LP PQ,
and TAGE PQ simultaneously.  Each predictor has a separate
not_full backpressure signal to fetch.  Fetch stalls if any
predictor's PQ is full.

This is simpler than a shared upstream PQ and is appropriate
given the small metadata size of LP and the independent
sizing of each predictor.

### 8.2  Future: shared upstream PQ

A shared upstream PQ broadcasting to all predictor PQs may
be introduced later if the independent PQ approach creates
fan-out or timing problems.  This is deferred.  The per-
predictor PQ interfaces defined here are compatible with
being driven from either a shared or independent source.


## 9. RTL Change Summary

### 9.1  tage.sv
  - Add PQ, UQ instances.
  - UQ entry type: cond_pred_upd_inp_t (not tage_upd_inp_t).
  - Add credit arbiter.
  - Add competing-stage mux and bp_arb_trx_t register.
  - Add prediction response buffer.
  - Response buffer entry type: cond_pred_meta_t.
  - Re-route existing port connections through queue inputs.
  - tage_pred_rdy_p2 driven from response buffer head valid.
  - tage_upd_rdy_u1 driven from UQ not_full.
  - At u0: fan cond_pred_upd_inp_t.tage to TAGE update logic,
    cond_pred_upd_inp_t.sc to SC update logic (gated sc_valid).

### 9.2  tage_cntrl.sv
  - Add trx_type input from competing-stage register.
  - Gate RAM write enables on trx_type==UPD at u1.
  - Gate RAM read result routing on trx_type==PRED at p1.
  - No change to prediction or update logic.

### 9.3  sc.sv  (new module)
  - SC RAM tables, counter read/write logic.
  - Prediction input: cond_pred_meta_t from TAGE response
    buffer.  SC reads tage sub-field for indexing; writes
    sc sub-field with counter results.
  - No independent UQ.  Update input is sc sub-field of
    cond_pred_upd_inp_t, gated on sc_valid, driven from
    tage.sv at u0.
  - Thresholding logic at s3.
  - sc_redir_val_s3 output.
  - SC response buffer (SC_RESP_BUF_DEPTH).
  - Backpressure output to TAGE response buffer
    consumer_ready.

### 9.4  ftb.sv  (arbitration additions)
  - Add PQ, UQ, credit arbiter, response buffer.
  - Same pattern as TAGE.  Own parameter set.

### 9.5  loop_pred.sv  (arbitration additions)
  - Add PQ, UQ, credit arbiter, response buffer.
  - Same pattern as TAGE.  Own parameter set.
  - Prediction request input from fetch (Option B, not
    from shared upstream PQ).

### 9.6  bp_structs_pkg.sv
  - Add bp_arb_trx_t (section 4.6).
  - Add cond_pred_meta_t (section 6.1).  Contains
    tage_pred_meta_t and sc_pred_meta_t as fields plus
    sc_valid.
  - Add cond_pred_upd_inp_t (section 6.1).  Contains
    tage_upd_inp_t and sc_upd_inp_t as fields plus
    sc_valid, resolved_taken, cond_mispredict.
  - Add sc_pred_meta_t stub when SC is implemented.
  - Add sc_upd_inp_t stub when SC is implemented.
  - Confirm bp_ras_snapshot_t is present (session-003
    records it as defined -- verify fields match section 7.2).
  - tage_upd_inp_t and tage_pred_meta_t are retained as
    sub-struct definitions.  They are no longer used as
    top-level port types on tage.sv.

### 9.7  bp_defines_pkg.sv
  - Add TAGE arbitration parameters (section 4.2).
  - Add FTB, LP, SC, ITTAGE parameter stubs with TBD values.
  - Add RAS stack depth parameters when RAS is specced.

### 9.8  tage_interfaces.md
  - Add section: same-entry conflict resolution (section 4.8).
  - Add section: SC chaining -- TAGE response buffer output
    feeds SC p0.  cond_pred_meta_t replaces tage_pred_meta_t
    as the response buffer entry type.
  - Update tage_upd_rdy_u1 semantics (section 5.3 / 9.1).
  - Update UQ entry type to cond_pred_upd_inp_t.
  - Note: tage_upd_inp_t is now a sub-struct field, not the
    top-level update port type.


## 10. Testbench Requirements

### 10.1  TAGE arbitration tests (tb_tage.sv)

  TB-ARB-01: Prediction only, no updates in flight.
    Verify: prediction completes in p0+p1+p2, pred_rdy asserts.

  TB-ARB-02: Update only, no predictions in flight.
    Verify: update completes in u0+u1, upd_rdy asserts.

  TB-ARB-03: Simultaneous prediction and update, different
    entries.
    Verify: both complete.  Prediction wins arbitration first.
    Update completes next cycle.  No data corruption.

  TB-ARB-04: Simultaneous prediction and update, same entry.
    Verify: prediction granted first, reads pre-update state.
    Update writes next cycle.  Both complete successfully.
    Defined behavior per section 4.8.

  TB-ARB-05: Update burst of 4 in one cycle.
    Verify: first 2 accepted immediately, second 2 accepted
    after 2 cycles.  Backpressure asserted for 2 cycles.

  TB-ARB-06: PQ fills to TAGE_PQ_DEPTH.
    Verify: not_full deasserts.  All predictions eventually
    complete after queue drains.  No drops.

  TB-ARB-07: Response buffer full.
    Verify: arbiter does not issue new prediction.  Update
    may still issue during this window.

  TB-ARB-08: Starvation prevention.
    Issue TAGE_PRED_CREDITS predictions with updates pending.
    Verify: after TAGE_STARVE_THRESH starvation cycles, one
    update is granted.  starve_ctr resets.

### 10.2  SC/TAGE merged update tests  (tb_tage_sc.sv -- future)

  TB-SC-01: Update with sc_valid asserted.
    Verify: single UQ entry enqueued.  Single grant drains it.
    Both TAGE and SC RAM writes complete at u1.

  TB-SC-02: Update with sc_valid deasserted.
    Verify: single UQ entry enqueued.  SC update logic gated.
    Only TAGE RAM write completes at u1.  SC tables unchanged.

  TB-SC-03: SC response buffer full, TAGE producing results.
    Verify: TAGE response buffer stalls (consumer_ready low).
    TAGE arbiter does not issue new predictions.  System
    resumes when SC response buffer drains.

### 10.3  Per-predictor arbitration tests

  FTB, LP, ITTAGE each require TB-ARB-01 through TB-ARB-08
  equivalents in their own testbenches.  Naming convention:
    TB-FTB-ARB-01 through TB-FTB-ARB-08
    TB-LP-ARB-01  through TB-LP-ARB-08
  Test logic is structurally identical to the TAGE set.


## 11. Open Items

  A. Same-entry conflict ordering.  CLOSED 2026-04-09.
     Prediction goes first.  Reads pre-update state.  No
     address comparison at arbiter.  See section 4.8.

  B. bp_arb_trx_t width.
     The transaction register carries only trx_type and
     trx_slot (section 4.6).  Queue head data held stable.
     Evaluate whether hold-stable is synthesizable cleanly
     in the target flow before committing to RTL.

  C. SC response buffer placement and backpressure chain.
     SC response buffer sits after s3.  SC backpressures
     TAGE response buffer consumer_ready when full.  The
     TAGE response buffer then backpressures the TAGE
     arbiter (resp_buf_full, rule 1).  This is a two-deep
     stall chain.  Confirm worst-case SC drain rate does not
     create unacceptable prediction stalls.

  D. Shared upstream PQ.
     Deferred.  Option B (independent PQs) used initially.
     Revisit before LP integration if timing or fan-out
     is a problem.

  E. Flush protocol interaction.
     _px signals not yet defined.  On flush:
       PQ entries: discardable (speculative).
       UQ entries: must not be discarded (post-commit).
       In-flight competing-stage transaction: if PRED,
         discard result.  If UPD, must complete.
     Revisit when flush is specified.

  F. LP response stage.
     LP planned at p2.  If LP tables are small enough to
     complete at p1, override fires one cycle earlier.
     Confirm when LP is sized.

  G. RAS open items RAS-1, RAS-2, RAS-3.
     See section 7.2.

  H. FTB, LP, SC, ITTAGE parameter values.
     All marked TBD.  Assign before each module's
     arbitration RTL is written.

  I. ITTAGE arbitration spec.
     Deferred until TAGE is fully validated.
     Placeholder in section 5.4.


## 12. Document History

  2026-04-09  Session-025.  Initial draft.  Supersedes
              tage_pred_upd_arb_spec.md.  Resolves debt #33.
              Open item A closed same session.
              Rev 2 same session: SC/TAGE merged metadata
              structs (cond_pred_meta_t, cond_pred_upd_inp_t).
              SC lockstep constraint eliminated by design.
              Covers all predictors: uFTB, RAS, FTB, LP,
              TAGE, SC, ITTAGE.
              Status: draft, open items B-I remain.
              TAGE section ready for RTL planning.
              Other predictors: architecture settled,
              parameters TBD.

