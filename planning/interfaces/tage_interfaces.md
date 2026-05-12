# TAGE Interface Specification
```
 FILE:    tage_interfaces.md
 SOURCE:  various
 STATUS:  NEEDS RE-VERIFICATION
 UPDATED: 2026-04-27
 CONTACT: Jeff Nye
```

---

## Overview

TAGE is a tagged geometric history length branch predictor
providing direction prediction for conditional branches. It
fires at p2 alongside FTB and overrides FTB direction when
TAGE disagrees. s2_redirect fires on override.

Five tables: T0 is the base table (no tag, no useful bit,
2b CTR). T1-T4 are tagged tables (valid=1b, tag=8b, ctr=3b,
useful=2b), each with 2 banks x 2048 entries and increasing
history lengths (8b, 13b, 32b, 119b).

Pipeline: p0 index calculation, p1 SRAM read and tag match,
p2 final prediction output.

All types defined in bp_defines_pkg.sv and bp_structs_pkg.sv.
This document describes port semantics, timing contracts, and
consumer/producer obligations. It does not restate struct
field layouts -- see bp_structs_pkg.sv.

---

## Port Naming Convention

Signal names follow the pattern:
`<signal>_<pipestage>`

- `pipestage` : p0, p1, p2 for prediction path.
                u0, u1 for update path.
                px for flush-related signals (not yet defined).

Slot dimension uses vector index [0:NUM_PRED_SLOTS-1].
clk and rstn carry no pipe stage suffix.

---

## Module Parameters

Paramters for TAGE are found in section :TAGE parameters:
of rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv

---

## Port List

```
// clock and reset
input  logic                                  clk
input  logic                                  rstn

// prediction interface
input  logic             [NUM_PRED_SLOTS-1:0] tage_pred_val_p0
input  tage_pred_inp_t   tage_pred_inp_p0[0:NUM_PRED_SLOTS-1]
output logic             [NUM_PRED_SLOTS-1:0] tage_pred_rdy_p2
output tage_pred_meta_t  tage_pred_meta_p2[0:NUM_PRED_SLOTS-1]

// update interface
input  logic             [NUM_PRED_SLOTS-1:0] tage_upd_val_u0
input  tage_upd_inp_t    tage_upd_inp_u0[0:NUM_PRED_SLOTS-1]
output logic             [NUM_PRED_SLOTS-1:0] tage_upd_rdy_u1

// aging control -- shared across both slots
input  logic                                  tage_enable_aging
input  logic             [31:0]               tage_aging_interval

input  bp_folded_hist_t   folded_hist,

// ram init interface
output logic  tage_rdy
```

---

## Struct Definitions

All structs defined in bp_structs_pkg.sv.

### tage_pred_inp_t

Input bundle presented with each prediction request.
Carries branch PC and branch_id for the slot.
See bp_structs_pkg.sv for the authoritative definition.

### tage_pred_meta_t

Prediction output and metadata. Carries primary and alternate
component indices, confidence counters, useful bits, allocation
target, predicted results for primary and alternative, UAON 
flag, hit status, and branch_id.
See bp_structs_pkg.sv for the authoritative definition.

### tage_upd_inp_t

Update input bundle. Contains the prediction metadata
captured at predict time plus resolution fields supplied
by the top level.
See bp_structs_pkg.sv for the authoritative definition.

---

## Prediction Interface

### Producer: tage
### Consumer: BP cluster (override control, p2 mux, FTQ write)

### Timing

```
tage_pred_inp_p0[s] is presented at p0. folded_hist
(bp_folded_hist_t from bp_history) is also presented at p0.
Index and tag hash logic is combinational within each
tage_table instance at p0.
p1: SRAM read completes. Tag match and hit processing
    execute in p1.
p2: Final prediction flopped out. tage_pred_meta_p2[s]
    and tage_pred_rdy_p2[s] are valid at p2.
```

### Folded History Input

`folded_hist` is the `bp_folded_hist_t` output of
bp_history. It is shared across both prediction slots
and passed directly to each tage_table instance.
Each tage_table instance selects its table-specific
fields and derives index_hash and tag_hash locally.
TAGE consumes the following fields for index and tag
computation:

```
tage_t1_idx_fh, tage_t1_tag_fh1, tage_t1_tag_fh2
tage_t2_idx_fh, tage_t2_tag_fh1, tage_t2_tag_fh2
tage_t3_idx_fh, tage_t3_tag_fh1, tage_t3_tag_fh2
tage_t4_idx_fh, tage_t4_tag_fh1, tage_t4_tag_fh2
```

PHR contribution to index and tag hashing is TBD.
All current folds are GHR-derived only.

### Semantics

```
tage_pred_val_p0[s] = 1  -- valid prediction request for
                            slot s. TAGE will process and
                            produce tage_pred_meta_p2[s]
                            two cycles later.
tage_pred_val_p0[s] = 0  -- no request for slot s.
                            tage_pred_rdy_p2[s] will be
                            0 at p2.
tage_pred_rdy_p2[s] = 1  -- tage_pred_meta_p2[s] is valid.
```

Both slots may have tage_pred_val_p0 asserted in the same
cycle. Slots operate independently with no cross-slot
interaction.

T0 always produces a prediction.
T1-T4 produce a prediction only on tag match.
tage_pred_rdy_p2[s] is asserted on completion of the
prediction indicating the predict meta data should be
sampled by the consumer.

#### Selection of primary or alternative:

tage_pred_meta_p2[s].tage_pred_tkn carries the predicted direction.

The provider is either a) primary component b) alternative component
c) or table 0, T0, aka BIM

All tables are accessed in parallel. Each table returns a hit value,
if those hit values are organized as a vector with the table with
the longest history in the MSB then the primary and alternative
components are the left most hit (primary) and next left most hit
(alternative).

In tage there is always at least 1 hit. When there are
no hits in the tagged tables the provider component is 0 (T0).

Normally the primary component is selected since by design it
has the longest history length, but this selection is modified
by the primary component's CTR and the current value of the
UAON for that prediction slot.

When the primary component is T0 there is no modification.
Otherwise when the primary component's CTR is weak
(3'b011 or 3'b100) and the UAON counter is >= TAGE_UAON_THRES
the alternative component becomes the provider.

Operation of the UAON is described in tage_cntrl_uaon_update_rules.md.

TAGE processes up to two conditional branches, one for each
prediction slot.

### Hash Functions

Each tage_table instance generates index_hash and tag_hash
locally. These hashes are used to access the RAMS in p0.

The hash operations are defined in tage_table_hash_rules.md

### Consumer obligations

- Must not consume tage_pred_tkn when tage_pred_rdy_p2[s]=0.
- Must write tage_pred_meta_p2[s] into FTQ meta path when
  tage_pred_val_p0[s] was asserted, regardless of
  tage_pred_rdy_p2[s]. The update path requires these
  fields unconditionally.
- Must set pred_src in bp_ftq_entry_t to PRED_TAGE when
  TAGE overrides FTB direction.
- Must assert s2_redirect when tage_pred_rdy_p2[s]=1 and
  tage_pred_tkn disagrees with FTB direction.
- Must gate TAGE override on br_type==COND only.

### TAGE simulation support
- TAGE_FAST_INIT: runtime plusarg (+TAGE_FAST_INIT=1).
  Read in tage.sv, tage_bim.sv, tage_table.sv.
  When set: tage_bim and tage_table initial blocks
  write bw_ram mem arrays via hierarchical reference
  at time zero. tage.sv straps all tbl_ri_* to zero
  and drives tage_rdy=1 immediately. sram_init
  elaborates but is fully bypassed.
  When not set: sram_init sequences all entries,
  tage_rdy follows tbl_ri_rdy from sram_init.
  Simulation-only mechanism. No synthesis impact.
  bw_ram.sv is not modified.
- TAGE_SRAM_INIT_VALUE: localparam int in
  bp_defines_pkg.sv, default 0. Used by sram_init
  (.INIT_VAL) and tage_bim/tage_table initial blocks.

---

## Update Interface

### Producer: post-execute resolution path (BP cluster)
### Consumer: tage

### Timing

tage_upd_inp_u0[s] is presented at u0. Sampled on rising
clk edge.  tage_upd_rdy_u1[s] is asserted at u1 when the
update has been applied. Update completes in one cycle.
tage_upd_val_u0[s] may be asserted in any cycle.  No ordering
constraint between update channels when NUM_PRED_SLOTS=2.
Both channels processed independently in the same cycle.

## RAM Init Interface

Output tage_rdy indicates that the RAM initialization cycles
have completed. This would tied to the .ready output of
the sram_init module. 

No prediction or update cycles should begin before tage_rdy has
been asserted. TAGE should ignore prediction and update requests
when tage_rdy is not asserted. It is the resonsiblity of
up stream logic to comprehend this condition.

---

### Semantics

```
tage_upd_val_u0[s] = 0  -- no update this cycle for slot s.
                           tage_upd_inp_u0[s] ignored.
tage_upd_val_u0[s] = 1  -- resolved update for slot s.
                           All tage_upd_inp_u0[s] fields
                           valid.
tage_upd_rdy_u1[s] = 1  -- update applied for slot s.
```

### Update behavior

CTR is a direction strength counter. It tracks 
the confidence in the prediction for the provider entry.

tage_pred_strong reflects NOT WEAK on the final provider
CTR after UAON mux selection. It is not strictly the
primary provider CTR. See tage_pred_meta_t in
bp_structs_pkg.sv.

The definitive operation of CTR updates is found in
tage_cntrl_ctr_update_rules.md.

The definitive operation of update time allocations is found in
tage_cntrl_alloc_rules.md.

### Read-during-write contract

Prediction and update paths are mutually exclusive by
design. The prediction path is read-only. The update
path is write-only. No read-modify-write cycles are
required or permitted.

### Producer obligations

- Must provide resolved_taken from execute, not speculative.
- Must pass tage_pred_meta_p2[s] captured at predict time
  unmodified into tage_upd_inp_u0[s]. No recomputation at update.
- Must not assert upd_val on the same branch_id via
  both channels in the same cycle (undefined update order).

---

## SC Consumer Contract

The SC = Statistical Corrector.

SC reads tage_pred_ctr from tage_pred_meta captured in
the FTQ meta path at p2. TAGE must be valid before SC
can finalize. SC does not read TAGE ports directly at
runtime.

The SC is only mentioned here for reference in the 
override chain position. 

---

## Override Chain Position

TAGE sits between FTB and SC in the override chain:

```
SC > TAGE > FTB > uBTB
```

TAGE sits at s2 alongside FTB and ITTAGE.

```
s1: uBTB + Loop
s2: FTB + TAGE + ITTAGE + RAS
s3: SC
```

TAGE overrides FTB direction at p2 for COND branches only.
SC overrides TAGE direction at p3. TAGE does not participate
in target selection -- FTB provides the target for
conditional branches.

---

## Known Gaps and Deferred Items

| ID  | Item                                   | Status             |
|-----|----------------------------------------|--------------------|
| TI1 | PHR contribution to index/tag hashing  | TBD at impl.       |
|     | All current folds are GHR-derived only |                    |
| TI2 | USE_ALT_ON_NA counter width and        | Closed             |
|     | update policy                          |                    |
| TI3 | Slot 1 PC derivation. pred_pc+32 was   | Closed -- retracted|
|     | in error and has been removed. Slot 1  |                    |
|     | PC is supplied by fetch unit via       |                    |
|     | tage_pred_inp_p0[1].pc. No offset      |                    |
|     | derivation in tage_cntrl.              |                    |
| TI4 | Update channel arbitration when both   | G9 in              |
|     | channels write same entry same cycle   | bp_cluster.md      |
| TI5 | TAGE/ITTAGE ftq_meta_t overload scheme | G10 in             |
|     | for shared index fields at update      | bp_cluster.md      |
| TI6 | Bank selection policy within each      | Closed             |
|     | table. Banks are per-slot RAMs, not    |                    |
|     | address-banked. Slot 0 uses RAM0,      |                    |
|     | slot 1 uses RAM1. Selection is         |                    |
|     | structural, not runtime. Unrelated to  |                    |
|     | sram_init/bw_ram bank scheme.          |                    |
| TI7 | bp_tage_meta_t migration to            | Cleanup task.      |
|     | tage_pred_meta_t -- both retained      | Post BP-010.       |
|     | during transition                      |                    |
| TI8 | Flush port definitions (_px signals)   | TBD. Not yet       |
|     | not yet defined                        | defined.           |

