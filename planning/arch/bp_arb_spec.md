<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Branch Predictor Arbitration and Prediction Pipeline Specification
```
 FILE:    bp_arb_spec.md
 SOURCE:  various
 STATUS:  STABLE (rev 1.0)
 UPDATED: 2026-08-09
 CONTACT: Jeff Nye
```
## 0. Caveat

- There is a plan for a SC csr bit which enables the SC. PA will help
  insert the right phrasing in the right locations. When the SC is
  disabled the FTB/control logic does not issue updates to the SC, it
  does not process the SC prediction response queue and otherwise does
  not wait for any responses from the SC. The FTB buffers and storage of
  SC related signals continues as normal. 

- Redirect naming. Sections 3.3, 3.4 and 5.x below use a
  `<pred>_redir_*` per-predictor naming that does not exist in any
  RTL. No predictor declares a redirect port; INFRA-011 confirmed
  this across all 140 ports of the eight top-level modules. The
  redirect is derived at the bp_cluster boundary and the groups are
  named by STAGE: `bpu_redir_p2` and `bpu_redir_p3`. The port
  specification is ftq_bpu_interfaces.md section 6, and the theory of
  operation is fe_decisions.md section 3.1. Read every
  `<pred>_redir_*` name below as "that predictor's contribution to
  the stage group", not as a port.

## 1. Problem Statement

The branch predictor cluster contains multiple synchronous RAM-based
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

  c. The RAS snapshot model, which does not fit the RAM
     arbitration pattern.


## 2. Predictor Inventory

|Predictor|RAM-based|Pred stage|Override stage|Update timing          |
|---------|---------|----------|--------------|-----------------------|
| uFTB    |No       |p0        |p0            |Immediate              |
| RAS     |No       |p0/p2     |p2            |Speculative push/snapshot restore. p0: TOS read for       initial prediction. p2: push/pop executes, redirect participation. See section 7.2 and ras_decisions.md p1.   |
| FTB     |Yes      |p1/p2     |p1/p2         |u0/u1                  |
| LP      |Yes      |p1/p2     |p1/p2         |u0/u1                  |
| TAGE    |Yes      |p2        |p2            |u0/u1                  |
| SC      |Yes      |p3        |p3            |u0/u1 (separate UQ)    |
| ITTAGE  |Yes      |p2        |p2            |u0/u1                  |

The indirect predictor chain (RAS + ITTAGE) shares the stage timing
of its direct counterparts but has different update and correction
semantics.  It is deferred to a later spec.  Placeholders are
included here where the indirect chain interacts with the direct
chain.

Note: fe_decisions.md section 12 records the departures from this
table that the front-end specification takes deliberately. The LP is
not a redirect source; the initial prediction is formed at p1.

## 3. Pipeline Stage Model and Override Chain

### 3.1  Stage definitions

  p0   Inputs presented to RAMs (flopped).  PC hash, folded
       history available.
  p1   RAM outputs available.  Tag match, hit processing.
  p2   Result formation.  Provider selection, meta capture.
  p3   Statistical corrector threshold decision.

  u0   Update address and write data presented to RAMs.
  u1   RAM write completes.

### 3.2  Predictor stage assignments

  p0:     uFTB, RAS (TOS read only)
  p1/p2:  FTB, LP
  p2:     TAGE, ITTAGE, RAS (push/pop, redirect participation)
  p3:     SC (chained from TAGE p2 output)

### 3.3  Override chain

A later stage overrides a previous stage if its prediction
differs.  Override is implemented as a redirect: the cluster
compares the predictor's result against the prediction it formed
at p1 and holds in its own stage registers.  If they differ it
asserts a redirect with the corrected target PC and the FTQ index
of the fetch being corrected.

The FTQ acts on the earliest available prediction (uFTB/RAS at p0)
and issues a fetch immediately.  It does not wait for later
predictors.  Later predictors issue redirects independently when
their results are ready.

Override priority (highest to lowest):
  SC (p3) > TAGE (p2) > FTB/LP (p1/p2) > uFTB/RAS (p0)

For indirect branches:
  ITTAGE (p2) > RAS (p0)  [indirect chain, deferred]

Note: fe_decisions.md section 12 rejects both priority chains. These
predictors do not produce the same quantity and do not contend;
redirects supersede by stage order (FE-3), and br_type selects the
RAS for a return and the ITTAGE for an indirect so the two are never
both consulted for one branch. The rows are retained here as the
original text; fe_decisions.md governs.

A redirect from a later stage supersedes any earlier redirect
for the same FTQ entry.  The FTQ must track which redirects are
stale.

### 3.4  Redirect interface (per predictor, per stage)

HISTORICAL. The signal names in this section were never implemented
and will not be. See the Caveat in section 0 and
ftq_bpu_interfaces.md section 6 for the real interface.

The original text described each RAM-based predictor that can
redirect as exposing:

```
  output logic                    <pred>_redir_val_<pN>
  output logic [VA_WIDTH-1:0]     <pred>_redir_tgt_<pN>
  output logic [FTQ_IDX_BITS-1:0] <pred>_redir_ftq_idx_<pN>
```

uFTB and RAS drive the FTQ directly at p0 without a redirect
interface. They are the initial prediction.  RAS push/pop 
and redirect participation occurs at p2; the p0 output is 
a TOS read only.

Redirect signal naming examples:
```
ftb_redir_val_p2
lp_redir_val_p2
tage_redir_val_p2
itage_redir_val_p2
sc_redir_val_p3
```

Status: NO SUCH PORT EXISTS, on any predictor or at the cluster
boundary. The session-060 audit (INFRA-009) found none on the
unit-level RTL, and INFRA-011 confirmed the same across all 140
ports of all eight modules once bp_cluster was built. The redirect
is cluster-derived logic, and the delivered groups are named by
stage rather than by predictor:

```
  bpu_redir_p2      bp_redirect_t [0:NUM_PRED_SLOTS-1]
  bpu_redir_idx_p2  [FTQ_IDX_BITS-1:0]
  bpu_redir_p3      bp_redirect_t [0:NUM_PRED_SLOTS-1]
  bpu_redir_idx_p3  [FTQ_IDX_BITS-1:0]
```

The comparison reduces both views of a slot to one quantity, the
address fetched after that slot, and every comparison is qualified by
branch_id equal to the FTQ index in the matching stage register. The
LP is not a redirect source at all: it is selected against the uBTB
by mux at p1.

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

```
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
```

FTB, LP, and ITTAGE have analogous parameter sets with their own
prefix and independently chosen values.

Note, TD#39: PRED_CREDITS = 4 is less than STARVE_THRESH = 8, so the
section 4.5 rule 2 starvation override may be unreachable at these
values -- rule 4 reloads the credits and resets the starve counter
before the counter can reach the threshold. Settle whether the
relationship is intentional before writing arbiter tests.

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

Note: fe_decisions.md section 12 corrects both statements above. The
producer is post-execute resolution, not commit, and this is an
out-of-order machine, so updates are enqueued and delivered in
resolution order (FE-6). The two write ports and the backpressure
behaviour are retained as written.

### 4.5  Credit Arbiter

Initialization:
  pred_credits = <PRED>_PRED_CREDITS
  upd_credits  = <PRED>_UPD_CREDITS
  starve_ctr   = 0

Per-cycle grant logic (priority order):

  1. resp_buf_full asserted: no grant.  Prediction path
     blocked; do not issue a new prediction.
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

These rules are IMPLEMENTED for SC inside bp_cluster (session-063).
They are untested; TD#73 folds the grant-rule tests into
tb_bp_cluster, with TD#39 (section 4.2) settled first.

### 4.6  Competing stage register

The arbiter output is captured in a transaction register that
travels with the pipeline from p0/u0 to p1/u1:

```
  typedef struct packed {
    logic                              trx_type; // 0=PRED 1=UPD
    logic [$clog2(NUM_PRED_SLOTS)-1:0] trx_slot;
  } bp_arb_trx_t;
```

The full input data (<PRED>_pred_inp or <PRED>_upd_inp) is held 
stable at the queue head until the grant is de-asserted.  The 
transaction register carries only type and slot.  This avoids a wide
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
  - p2 result formation asserts p2_valid.  Result enters buffer.
  - Consumer (FTQ or SC for TAGE) presents consumer_ready.
  - Buffer asserts pred_rdy when head is valid.
  - When buffer full and consumer not ready, resp_buf_full
    asserted to arbiter (blocks new prediction grants, rule 1).

### 4.8  Same-entry conflict resolution

When a prediction and an update targeting the same RAM entry
are both pending, prediction is granted first per the credit
rules (section 4.5, rule 3).  The prediction reads pre-update
state.  The update is granted in a subsequent cycle.


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
  Override:    p2, via the cluster-derived bpu_redir_p2 group.
               No ftb_redir_val_p2 port exists.
  Notes:       FTB updates on every resolved fetch block, not
               only on mispredictions.  UQ drain rate may be
               higher than TAGE.  Size UQ_DEPTH accordingly.
               As shipped, ftb.sv declares 42 flat ports and no
               PQ, UQ or arbiter; the parameters above are not
               instantiated.

### 5.2  Loop Predictor (LP)

  Parameters:  LP_PQ_DEPTH, LP_UQ_DEPTH, LP_UQ_WR_PORTS,
               LP_RESP_BUF_DEPTH, LP_PRED_CREDITS,
               LP_UPD_CREDITS, LP_STARVE_THRESH.
  Values:      TBD.  LP metadata is small; shallower queues
               may be sufficient.
  Pred input:  lp_pred_inp_t  (PC + branch_id -- narrow)
  Upd input:   lp_upd_inp_t
  Pred output: lp_pred_t
  Override:    NONE. The LP is not a redirect source. It is
               selected against the uBTB by mux at p1
               (fe_decisions.md 2.1). lp_redir_val_p2 does not
               exist.
  Request:     Fetch presents prediction request to LP PQ
               independently (Option B).  Same PC as TAGE
               but separate queue instance.  No shared
               upstream PQ at this time.
  Notes:       LP completes at p1, not p2. Its prediction output
               is pred_p1 and it is per-slot as of BP-091. As
               shipped it declares no PQ, UQ or arbiter.

### 5.3  TAGE

  Parameters:  TAGE_PQ_DEPTH=8, TAGE_UQ_DEPTH=8,
               TAGE_UQ_WR_PORTS=2, TAGE_RESP_BUF_DEPTH=2,
               TAGE_PRED_CREDITS=4, TAGE_UPD_CREDITS=1,
               TAGE_STARVE_THRESH=8.
  Pred input:  tage_pred_inp_t
  Upd input:   tage_upd_inp_t  
  Pred output: tage_pred_meta_t 
  Override:    p2, via the cluster-derived bpu_redir_p2 group.
               No tage_redir_val_p2 port exists.
  Notes:       TAGE response buffer holds tage_pred_meta_t.
               SC prediction chains from that buffer (section 6).
               TAGE and SC have separate UQ buffers. This is a change
               from the previous where the UQ entry was shared.

### 5.4  ITTAGE

  Parameters:  ITTAGE_PQ_DEPTH=4, ITTAGE_UQ_DEPTH=2,
               ITTAGE_UQ_WR_PORTS=2, ITTAGE_RESP_BUF_DEPTH=2,
               ITTAGE_PRED_CREDITS=2, ITTAGE_UPD_CREDITS=1,
               ITTAGE_STARVE_THRESH=2.
  Note: ITTAGE_RESP_BUF_DEPTH is vestigial -- the response buffer
  was removed (BP-038b, ittage.sv). ITTAGE has no independent
  prediction response FIFO at the unit level.
  Pred input:  ittage_pred_inp_t
  Upd input:   ittage_upd_inp_t
  Pred output: ittage_pred_meta_t
  Override:    p2, via the cluster-derived bpu_redir_p2 group. No
  dedicated redirect port on ittage.sv; the cluster derives the
  redirect by comparing ittage_pred_meta_p2 against the prediction
  it formed at p1, per section 3.4. Indirect chain only.

### 5.5  SC

  Parameters:  SC_UQ_DEPTH=8, SC_UQ_WR_PORTS=2,
               SC_RESP_BUF_DEPTH=2, SC_PRED_CREDITS=4,
               SC_UPD_CREDITS=1, SC_STARVE_THRESH=8.
  Pred input:  tage_pred_meta_t
               staged p0->p2 prediction inputs, see section 6.1
  Upd input:   sc_upd_inp_t  
  Pred output: sc_pred_meta_t
  Override:    p3, via the cluster-derived bpu_redir_p3 group.
               No sc_redir_val_p3 port exists.
  Notes:       SC has no SC_PQ_DEPTH. SC does not instantiate its
               own prediction FIFO; the TAGE response buffer
               (TAGE_RESP_BUF_DEPTH) is the prediction-side storage
               and acts as SC's PQ for arbitration (section 6.1).
               SC response buffer holds sc_pred_meta_t.
               TAGE and SC have separate update queues and 
               prediction response queues. This is a change
               from the previous version.
               The SC credit arbiter is IMPLEMENTED in bp_cluster
               (session-063), not stubbed at the unit level. It is
               untested; TD#73.

## 6. Statistical Corrector (SC) -- Chained Predictor

SC is a Seznec-style statistical corrector.  It has its own RAM
tables of signed counters and a thresholding process.  It adds
one pipeline stage (p3) after TAGE p2.

SC tables are single-port RAMs. SC prediction (read, p2->p3) and SC
update (write, u0/u1) compete for the one RAM port. The section 4.5
credit arbiter governs that contention unchanged. SC's prediction
transactions are drawn from the TAGE response buffer (acting as SC's
PQ); SC's update transactions are drawn from the SC UQ. SC does not
instantiate an independent prediction FIFO.

### 6.1  TAGE/SC Prediction Request Communication

TAGE prediction response meta data is used by the SC. The SC accepts the
tage_pred_meta_t and a staged version of the tage_pred_inp structures as
prediction request inputs but SC only queues a sub-set of the information 
provided. 

tage_pred_inp is staged from p0 to p2. P2 is the start of the SC
prediction pipeline.

The SC has discrete ports for the p2 versions of the prediction pc, a
snapshot of the lower 10 bits of the PHR, AND THE THREE SC INDEX
FOLDS.

These signals are captured at p0/p1
```
tage_pred_inp_p0[slot].pc[VA_WIDTH-1:1]
folded_hist.tage_phr[9:0]
folded_hist.sc_t1_idx_fh
folded_hist.sc_t2_idx_fh
folded_hist.sc_t3_idx_fh
```

They are staged to p2 and applied as inputs to SC

```
logic [VA_WIDTH-1:1] inp_pc_p2[0:NUM_PRED_SLOTS-1]; //tage_pred_inp_p0[s].pc
logic [9:0]          sc_phr_p2;        // folded_hist.tage_phr[9:0]
logic [SC_MAX_FH-1:0] sc_t1_idx_fh_p2; // folded_hist.sc_t1_idx_fh
logic [SC_MAX_FH-1:0] sc_t2_idx_fh_p2; // folded_hist.sc_t2_idx_fh
logic [SC_MAX_FH-1:0] sc_t3_idx_fh_p2; // folded_hist.sc_t3_idx_fh
```

ALL FIVE ARE STAGED. The three index folds were connected live to
bp_history until BP-090. bp_history advances whenever a branch is
predicted, so at p2 the live folds described a block LATER than the
one SC was indexing -- the same defect the PC and the phr staging
exists to prevent. They are the same class of signal and take the
same staging. TD#92; ftq_bpu_interfaces.md section 10 item 8 records
the closure.

TAGE and ITTAGE do not appear here because they take
bp_folded_hist_t whole at their own p0 request and stage internally.
SC is the only consumer that takes sliced folds.

The TAGE prediction response is a port on the SC along with the ready signal
indicating the prediction response is valid.

```
tage_pred_meta_p2[0:NUM_PRED_SLOTS-1];
tage_pred_rdy_p2
```

Of the tage_pred_meta_p2, these signals are used. These ports hold the
signals for the two prediction slots, indicated by (s).

```
tage_pred_meta_p2[s].tage_pred_strong
tage_pred_meta_p2[s].tage_pred_medium
tage_pred_meta_p2[s].tage_pred_tkn   
tage_pred_meta_p2[s].tage_extd_ctr   
```

These are p2 signals and do not require staging.

The SC prediction-side credit arbiter draws its prediction
transactions from the TAGE response buffer (which acts as SC's PQ)
and its update transactions from the SC UQ. Section 4.5 arbitration
applies unchanged. When the arbiter grants an SC update and stalls an
SC prediction, the TAGE response buffer head is held, which
backpressures TAGE (see section 11 item C).

### 6.2  SC Update Request Communication

SC has a separate UQ. The UQ entry type is sc_upd_inp_t.

Note: A single conditional branch commit event must enqueue one entry
in the TAGE UQ and one in the SC UQ. Each of these entries can contain
two branches, since Pacino BPC is dual prediction capable.

The SC and TAGE UQ's are separate.

## 7. Non-RAM Predictors

### 7.1  uFTB

uFTB is fully combinational.  No internal SRAMs.  No PQ, UQ,
or arbiter required.  Output is presented directly to the FTQ
at p0.  uFTB result is the initial prediction that fetch acts
on; it is not a redirect.

If the FTQ cannot accept the uFTB output (FTQ full), uFTB
holds its output stable.  No response buffer needed.

Note: fe_decisions.md places the initial prediction at p1, where the
FTQ allocates. The uBTB output is combinational from pred_pc_p0 and
the cluster registers it once so the p1 selection mux reads it
alongside the loop predictor's registered output. The predictor name
is uBTB; uFTB is retained here as the original text only.

### 7.2  RAS

RAS is a register-file-based stack.  It does not have
synchronous SRAMs in the TAGE sense.  No PQ, UQ, or credit
arbiter required.

#### Prediction

RAS prediction is a read of the top-of-stack (TOS) register,
which is combinational.  A return instruction detected at p0
causes the RAS to present the TOS value as the predicted
target.  This is the initial p0 prediction, not a redirect.
ras.sv declares ras_tos_addr_p0 and ras_tos_valid_p0.

#### Push (call)

A call instruction is detected via FTB structural prediction
at p2.  The return address is pushed onto the RAS speculatively
at p2.  Because the prediction is speculative, the push may be
on a mispredicted path.

#### Snapshot and restore

RAS state (TOSR, TOSW, BOS -- defined in bp_ras_snapshot_t in
bp_structs_pkg.sv, each RAS_PTR_BITS=4b wide) must be
checkpointed into the FTQ entry at the time of the prediction
that consumed or produced the RAS state.  On mispredict or
flush the RAS is restored from the FTQ snapshot of the last
known-good entry.

The bp_ftq_entry_t struct includes a bp_ras_snapshot_t field.
This is the RAS update mechanism -- not a RAM write but
snapshot retirement.  See ras_decisions.md section 4.

#### Commit

On commit the FTQ snapshot for the retiring entry is released.
No RAM write occurs.  The RAS stack pointer advances as
speculative state is confirmed.

#### Open items

  Flush behavior: the RAS half is CLOSED, ras_decisions.md 4.4.
  The flush EVENT is CLOSED too, BP-105: there is none. A flush is
  a redirect, fe_decisions.md FE-14. TD #96 is closed.

## 8. Prediction Request Distribution

### 8.1  Current approach 

Fetch presents prediction requests independently to each
predictor's PQ.  The same PC fans out to FTB PQ, LP PQ,
and TAGE PQ simultaneously.  Each predictor has a separate
not_full backpressure signal to fetch.  Fetch stalls if any
predictor's PQ is full.

This is simpler than a shared upstream PQ and is appropriate
given the small metadata size of LP and the independent
sizing of each predictor.

### 8.2  Future: shared upstream PQ

This is now recorded as TD #97.

## 9. RTL changes

Section removed.

## 10. Testbench Requirements

Section removed. Testbench requirements derive from the section 4.5
arbitration rules, section 4.8 same-entry ordering, and the section
11 item C backpressure chain. They are enumerated in the implementing
task file, not here.

## 11. Open Items

  B. bp_arb_trx_t width.
     The transaction register carries only trx_type and
     trx_slot (section 4.6).  Queue head data held stable.
     Evaluate whether hold-stable is synthesizable cleanly
     in the target flow before committing to RTL.

  C. CLOSED.  SC response buffer is a separate queue with
     it's own back pressure chain eventually tied into the TAGE
     p2 inputs, and ties into TAGE's response back pressure.

     OLD: SC response buffer placement and backpressure chain.
     SC response buffer sits after p3.  SC backpressures
     TAGE response buffer consumer_ready when full.  The
     TAGE response buffer then backpressures the TAGE
     arbiter (resp_buf_full, rule 1).  This is a two-deep
     stall chain.  Confirm worst-case SC drain rate does not
     create unacceptable prediction stalls.

  D. Shared upstream PQ.

     This is TD #97.

     OLD: Deferred.  Option B (independent PQs) used initially.
     Revisit before LP integration if timing or fan-out
     is a problem.

  E. Flush protocol interaction.

     CLOSED, BP-105. There is no flush event to interact with: a
     flush is a redirect (fe_decisions.md FE-14). The queues need
     no flush behaviour, and the OLD analysis below is CORRECT and
     is already how the design works without one -- a redirect
     clears stage valids, so PQ entries are naturally discarded,
     while the update path is not gated by the redirect at all and
     UQ entries simply proceed.

     Corroborated by XiangShan: its predictors take `update`
     independently of the redirect path and no queue is flushed,
     because nothing flushes them.

     OLD: _px signals not yet defined.  On flush:
       PQ entries: discardable (speculative).
       UQ entries: must not be discarded (post-commit).
       In-flight competing-stage transaction: if PRED,
         discard result.  If UPD, must complete.

  F. LP response stage.
     CLOSED. The LP completes at p1. Its output is pred_p1 and it
     is selected against the uBTB by mux at p1, so it is not a
     redirect source at any stage.

  G. RAS open items RAS-1, RAS-2, RAS-3.
     See section 7.2 and planning/arch/ras_decisions.md section 10.
     RAS-2 (stack depth): CLOSED session-050.
       16 speculative + 32 commit, static partition.
       See ras_decisions.md section 3.
     RAS-1 (push timing): PARTIALLY RESOLVED session-050.
       Push at p2 gated on FTB branch type.
       See ras_decisions.md section 7.
     RAS-3 (flush recovery): CLOSED 2026-08-20, and answered by
       ras_decisions.md 4.4 well before that date -- only the
       label said otherwise. The RAS response to a flush is the
       pointer restore of 4.3, built and tested as
       ras_restore_val. BP-105 then closed the flush EVENT as
       well: there is none (fe_decisions.md FE-14). Do not re-raise from the
       unread ras_flush_* ports (4.4.2).

  H. FTB, LP, SC, ITTAGE parameter values.
     All marked TBD.  Assign before each module's
     arbitration RTL is written.

  I. ITTAGE arbitration spec.

     CLOSED. Confirm with PA.

     OLD:
     Deferred until TAGE is fully validated.
     Placeholder in section 5.4.6

  J. TD#39. PRED_CREDITS < STARVE_THRESH, so the section 4.5
     rule 2 starvation override may be unreachable at the current
     parameter values and therefore untestable. Settle whether the
     relationship is intentional before the arbiter tests are
     written. See section 4.2.


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

  2026-06-23  Session-050. Consistency pass.
              Section 2 predictor inventory: RAS row updated
              to clarify p0=TOS read only, p2=push/pop and
              redirect participation. Override stage column
              updated to p2.
              Section 3.2 stage assignments: RAS entry
              expanded to note both p0 and p2 roles.
              Section 3.4: note added clarifying RAS p0
              output is TOS read; push/pop at p2.
              Section 7.2: push timing updated to p2 gated
              on FTB branch type (RAS-1 partially resolved).
              Snapshot field widths corrected to RAS_PTR_BITS
              = 4b (was unstated; old linked-array reference
              removed from struct comment in bp_structs_pkg).
              Open item G: RAS-1/RAS-2/RAS-3 status updated.
              References to ras_decisions.md added throughout.

  2026-06-28  Session-057. Manual edits
              SC semantics defined.
              PA consistency pass: section 2 SC update timing
              "lockstep w/ TAGE" replaced with "separate UQ";
              section 5.5 SC params reconciled (SC_PQ_DEPTH
              removed; TAGE response buffer is SC's PQ; six
              arbiter params retained for single-port RAM
              predict-vs-update contention); section 6 lead-in
              and 6.1 closing added to state the SC arbiter
              draws predictions from the TAGE response buffer
              and updates from the SC UQ. Typo fixes (responses,
              prediction, These signals). Section 6.1 cross-ref
              "section 61" corrected to 6.1.

  2026-08-09  INFRA-012 / session-064. Section 6.1 now names the
              three SC index folds among the p0-to-p2 staged
              inputs, alongside the prediction PC and the phr
              (TD#92, staged by BP-090), with the reason recorded:
              bp_history advances whenever a branch is predicted,
              so the live folds at p2 belonged to a later block.
              Redirect naming: a caveat added at section 0 and the
              status note in section 3.4 rewritten -- no predictor
              declares a redirect port and none is planned; the
              delivered groups are bpu_redir_p2 and bpu_redir_p3,
              derived at the cluster boundary and named by stage.
              The Override lines in 5.1 through 5.5 retargeted to
              those groups, and the LP's marked NONE since it is
              selected by mux at p1 rather than redirecting. Open
              item F closed on the same basis, open item J added
              for TD#39, and the TD#39 note added at section 4.2.
              Notes added where fe_decisions.md section 12 already
              records a deliberate departure (sections 2, 3.3, 4.4,
              7.1). Section 4.5 marked implemented-for-SC and
              untested (TD#73). RAS p0 port names stated.

