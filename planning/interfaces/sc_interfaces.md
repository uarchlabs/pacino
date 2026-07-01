<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# SC Interface Specification
```
 FILE:    sc_interfaces.md
 SOURCE:  various
 STATUS:  Draft -- session-058
 UPDATED: 2026-06-30
 CONTACT: Jeff Nye
```

---

## Overview

SC is the Seznec-style Statistical Corrector. It refines the TAGE
direction prediction for conditional branches by summing signed
confidence counters read from five tables and comparing the sum
magnitude against a dynamically adapted threshold. SC fires at p3,
one stage after TAGE p2, and overrides TAGE direction when the
override-corner logic selects the SC result.

Five tables ST0-ST4. ST0-ST3 hold confidence counters. ST4 is the
BrIMLI table. ST0 is indexed by a PC slice with no hash. ST1-ST3 are
indexed by PC hashed with a per-table folded history. ST4 is indexed
by the BrIMLI index function. Each table contains two RAMs, one per
prediction slot (TI6 convention).

Pipeline: p2 is the start of the SC prediction path (TAGE p2 output
and staged p0 inputs presented), p3 is the SC result. Update path is
u0/u1.

All types defined in bp_defines_pkg.sv and bp_structs_pkg.sv. This
document describes port semantics, timing contracts, and
consumer/producer obligations. It does not restate struct field
layouts -- see bp_structs_pkg.sv. It does not restate parameter
values -- see bp_defines_pkg.sv.

---

## Port Naming Convention

Signal names follow the pattern:
`<signal>_<pipestage>`

- `pipestage` : p2, p3 for the prediction path.
                u0, u1 for the update path.
                px for flush-related signals (not yet defined).

Planning documents use s0/s1/s2/s3 and u0/u1. RTL uses
p0/p1/p2/p3 and u0/u1. This document uses the RTL p-naming for
port names and the s-naming only where it quotes another planning
document. See sc_decisions.md section 3.

Slot dimension uses vector index [0:NUM_PRED_SLOTS-1].
clk and rstn carry no pipe stage suffix.

---

## Module Parameters

Parameters for SC are found in section :SC parameters: of
rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv. Arbitration parameters
(SC_UQ_DEPTH, SC_UQ_WR_PORTS, SC_RESP_BUF_DEPTH, SC_PRED_CREDITS,
SC_UPD_CREDITS, SC_STARVE_THRESH) are in the same file. Do not copy
values into this document.

---

## Port List

```
// clock and reset
input  logic                                  clk
input  logic                                  rstn

// prediction interface -- TAGE response (p2 in)
input  logic             [NUM_PRED_SLOTS-1:0] tage_pred_rdy_p2
input  tage_pred_meta_t  tage_pred_meta_p2[0:NUM_PRED_SLOTS-1]

// prediction interface -- staged p0 inputs presented at p2
input  logic [VA_WIDTH-1:1] inp_pc_p2[0:NUM_PRED_SLOTS-1]
input  logic [9:0]          sc_phr_p2
input  logic [SC_MAX_FH-1:0] sc_t1_idx_fh_p2
input  logic [SC_MAX_FH-1:0] sc_t2_idx_fh_p2
input  logic [SC_MAX_FH-1:0] sc_t3_idx_fh_p2

// prediction interface -- SC result (p3 out)
output logic             [NUM_PRED_SLOTS-1:0] sc_pred_rdy_p3
output sc_pred_meta_t    sc_pred_meta_p3[0:NUM_PRED_SLOTS-1]

// update interface
input  logic             [NUM_PRED_SLOTS-1:0] sc_upd_val_u0
input  sc_upd_inp_t      sc_upd_inp_u0[0:NUM_PRED_SLOTS-1]
output logic             [NUM_PRED_SLOTS-1:0] sc_upd_rdy_u1

// arbitration status outputs
output logic                      sc_uq_not_full
output logic [NUM_PRED_SLOTS-1:0] sc_upd_rdy

// CSR enable
input  logic                                  sc_enable

// ram init interface
output logic  sc_ready
```

---

## Struct Definitions

All structs defined in bp_structs_pkg.sv.

### tage_pred_meta_t

TAGE prediction output. SC consumes the fields tage_pred_strong,
tage_pred_medium, tage_pred_tkn, tage_extd_ctr (sc_decisions.md
section 9). SC does not consume the remaining fields.
See bp_structs_pkg.sv for the authoritative definition.

### sc_pred_meta_t

SC prediction output and metadata. Carries the SC sum and its
magnitude, the SC-local and final directions, the TAGE direction
copy, the override flag, the chooser corner, and the per-table index
and counter snapshots consumed by the update path.
See bp_structs_pkg.sv for the authoritative definition.

### sc_upd_inp_t

Update input bundle. Carries the sc_pred_meta_t captured at predict
time, the resolved direction, the mispredict flag, and the FTB-
supplied backwards_branch flag and branch_range PC slice used for
BrIMLI maintenance.
See bp_structs_pkg.sv for the authoritative definition.

---

## Prediction Interface

### Producer: TAGE response buffer (meta), fetch staging (pc/phr/folds)
### Consumer: BP cluster (override control, p3 redirect, FTQ write)

### Timing

```
p2: TAGE prediction meta is presented on tage_pred_meta_p2[s] with
    tage_pred_rdy_p2[s]. The staged p0 inputs inp_pc_p2[s],
    sc_phr_p2, sc_t1_idx_fh_p2, sc_t2_idx_fh_p2, sc_t3_idx_fh_p2
    are presented at p2. SC table index hashes are computed at p2.
    SC table RAM reads issue at p2.
p3: sc_pred_meta_p3[s] and sc_pred_rdy_p3[s] are valid.
```

SC begins at p2. The one-cycle SC operation produces the result at
p3 (sc_decisions.md section 2).

### Staged input derivation

The staged p2 inputs are derived from p0/p1 signals and held two
cycles (bp_arb_spec.md section 6.1):

```
inp_pc_p2[s]        <- tage_pred_inp_p0[s].pc          (p0 -> p2)
sc_phr_p2           <- folded_hist.tage_phr[9:0]        (p0 -> p2)
sc_t1_idx_fh_p2     <- folded_hist.sc_t1_idx_fh         (p0 -> p2)
sc_t2_idx_fh_p2     <- folded_hist.sc_t2_idx_fh         (p0 -> p2)
sc_t3_idx_fh_p2     <- folded_hist.sc_t3_idx_fh         (p0 -> p2)
```

The staging logic lives in the BP cluster, not in SC. SC receives
the p2 versions as ports.

### Table index inputs

```
ST0 index: sc_idx_hash(inp_pc_p2, SC_TBL_FH[0], 0)
           SC_TBL_FH[0] = 0. ST0 is a PC slice, no fold.
ST1 index: sc_idx_hash(inp_pc_p2, SC_TBL_FH[1], sc_t1_idx_fh_p2)
ST2 index: sc_idx_hash(inp_pc_p2, SC_TBL_FH[2], sc_t2_idx_fh_p2)
ST3 index: sc_idx_hash(inp_pc_p2, SC_TBL_FH[3], sc_t3_idx_fh_p2)
ST4 index: get_br_imli_idx(inp_pc_p2[15:6], sc_phr_p2, br_imli)
```

sc_idx_hash and get_br_imli_idx are defined in
sc_table_hash_rules.md (not yet written). ST4 takes PC[15:6]
(inp_pc_p2[15:6]).

### Semantics

```
tage_pred_rdy_p2[s] = 1  -- tage_pred_meta_p2[s] valid. SC processes
                            slot s and produces sc_pred_meta_p3[s].
tage_pred_rdy_p2[s] = 0  -- no TAGE result for slot s.
                            sc_pred_rdy_p3[s] = 0.
sc_pred_rdy_p3[s]   = 1  -- sc_pred_meta_p3[s] valid.
```

Both slots may be valid in the same cycle. Slots operate in parallel
with no cross-slot interaction (sc_decisions.md section 2).

SC prediction requires TAGE output. SC updates proceed without TAGE
input (sc_decisions.md section 2).

### Override

The final direction sc_pred_meta_p3[s].sc_pred_tkn is the post-
override result. sc_pred_meta_p3[s].sc_override indicates SC reversed
the TAGE direction. The chooser corner is sc_pred_meta_p3[s].
sc_chooser. Override selection logic is in sc_decisions.md section 9.

### CSR enable

sc_enable gates SC participation (bp_arb_spec.md section 0). When
deasserted, the BP cluster does not wait for SC responses and issues
no SC updates. FTB buffering of SC-related signals continues. The
enable is a cluster-level gate on SC consumption; the SC module
itself is not required to internally qualify on sc_enable unless the
implementing task specifies it. Marked IC-SC-05.

### Consumer obligations

- Must not consume sc_pred_meta_p3[s] when sc_pred_rdy_p3[s]=0.
- Must set pred_src in bp_ftq_entry_t to PRED_SC when SC overrides
  TAGE direction (sc_pred_meta_p3[s].sc_override=1).
- Must assert p3 redirect when sc_pred_rdy_p3[s]=1 and
  sc_pred_meta_p3[s].sc_pred_tkn disagrees with the FTQ-held
  direction for that fetch block (bp_arb_spec.md section 3.4).
- Must write sc_pred_meta_p3[s] into the FTQ meta path; the update
  path requires the captured indices and counters unconditionally.

### SC simulation support

- SC_FAST_INIT: runtime plusarg (+SC_FAST_INIT=1). Fast init block in
  sc_table.sv writes bw_ram mem arrays via hierarchical reference at
  time zero, both banks, both slot RAMs. When set, sram_init is
  bypassed and sc_ready asserts immediately. When not set, sram_init
  sequences all entries and sc_ready follows its ready output.
  Simulation-only. See sc_decisions.md section 13.
- SC_SRAM_INIT_VALUE: localparam int in bp_defines_pkg.sv, default 0.

---

## Update Interface

### Producer: post-execute resolution path (BP cluster)
### Consumer: SC

### Timing

```
u0: sc_upd_inp_u0[s] presented with sc_upd_val_u0[s]. Sampled on
    rising clk edge.
u1: sc_upd_rdy_u1[s] asserted when the update has been applied.
```

Update completes in one cycle. Both slot channels process
independently in the same cycle.

### Semantics

```
sc_upd_val_u0[s] = 0  -- no update this cycle for slot s.
                         sc_upd_inp_u0[s] ignored.
sc_upd_val_u0[s] = 1  -- resolved update for slot s. All
                         sc_upd_inp_u0[s] fields valid.
sc_upd_rdy_u1[s] = 1  -- update applied for slot s.

sc_uq_not_full        -- asserted when the SC update queue has room.
                         Consumer must gate sc_upd_val_u0 on this
                         signal.
```

### Update behavior

The update path reads the captured sc_pred_meta from sc_upd_inp,
applies the counter-update gate (SC-wrong OR sum below threshold),
steps the consulted counters toward the resolved direction, adapts
the threshold via the TC counter, and trains the chooser corners.
The definitive operation is in sc_decisions.md section 10.

BrIMLI register maintenance (br_imli, bb_hist, last_back_pc) uses
sc_upd_inp.branch_range and sc_upd_inp.backwards_branch. See
sc_decisions.md section 12.

### Read-during-write contract

Prediction and update paths are mutually exclusive by design.
Prediction is RAM read only. Update is RAM write only. No read-
modify-write is required (sc_decisions.md section 4). The
prediction-phase counter snapshots captured in sc_pred_meta supply
the update path; the update does not re-read the tables.

### Producer obligations

- Must provide resolved_taken from execute, not speculative.
- Must pass the sc_pred_meta_t captured at predict time unmodified
  into sc_upd_inp_u0[s].
- Must supply branch_range and backwards_branch from FTB (or other
  external logic) per sc_upd_inp_t.

---

## Arbitration Model

SC tables are single-port RAMs. SC prediction (read, p2->p3) and SC
update (write, u0/u1) compete for the one RAM port. The bp_arb_spec.md
section 4.5 credit arbiter governs that contention.

SC has no independent prediction FIFO. The TAGE response buffer
(TAGE_RESP_BUF_DEPTH) is SC's prediction-side storage and acts as
SC's PQ for arbitration (bp_arb_spec.md sections 5.5, 6). SC's
prediction rate is gated by TAGE's.

SC has a separate update queue, entry type sc_upd_inp_t. TAGE and SC
UQs are separate. A single conditional-branch commit enqueues one
TAGE UQ entry and one SC UQ entry; each entry covers both slots
(bp_arb_spec.md section 6.2).

When the SC arbiter grants an update and stalls a prediction, the
TAGE response buffer head is held, backpressuring TAGE
(bp_arb_spec.md section 11 item C).

---

## RAM Init Interface

Output sc_ready indicates the RAM initialization cycles have
completed. It ties to the ready output of the sram_init module.

No prediction or update cycles begin before sc_ready is asserted. SC
ignores prediction and update requests when sc_ready is deasserted.
Upstream logic must comprehend this condition. See sc_decisions.md
section 13.

---

## SC Table Interface

The SC-to-sc_table port list and per-table semantics are in
sc_table_interfaces.md (not yet written).

---

## Override Chain Position

SC sits at the top of the conditional-direction override chain:

```
SC > TAGE > FTB > uBTB
```

Stage assignment:

```
s1: uBTB + Loop
s2: FTB + TAGE + ITTAGE + RAS
s3: SC
```

SC overrides TAGE direction at p3 for conditional branches. SC does
not participate in target selection; FTB provides the target for
conditional branches.

---

## Known Gaps and Deferred Items

| ID       | Item                                      | Status          |
|----------|-------------------------------------------|-----------------|
| IC-SC-01 | `sc_idx_hash` not yet defined. Referenced | TBD.            |
|          | by ST0-ST3 index. Definition in           | `sc_table_`     |
|          | `sc_table_hash_rules.md`.                 | `hash_rules.md` |
| IC-SC-02 | `get_br_imli_idx` not yet defined.        | TBD.            |
|          | Referenced by ST4 index. Definition in    | `sc_table_`     |
|          | `sc_table_hash_rules.md`.                 | `hash_rules`.md |
| IC-SC-03 | ST4 PC width. `get_br_imli_idx` pc input  | RESOLVED        |
|          | is `inp_pc_p2[15:6]` (PC[15:6]), the      | session-058.    |
|          | BrIMLI region. Confirm in                 |                 |
|          | `sc_table_hash_rules.md` when written.    |                 |
| IC-SC-04 | `sc_table` port list and per-table        | TBD.            |
|          | semantics.                                | `sc_table_`     |
|          |                                           | interfaces.md   |
| IC-SC-05 | `sc_enable` qualification point. Cluster- | TBD at impl.    |
|          | level gate defined (`bp_arb_spec.md`      |                 |
|          | section 0). Whether the SC module         |                 |
|          | internally qualifies on `sc_enable` is    |                 |
|          | left to the implementing task.            |                 |
| IC-SC-06 | Flush port definitions (`_px signals`)    | TBD. TD #96.    |
|          | not yet defined.                          |                 |

