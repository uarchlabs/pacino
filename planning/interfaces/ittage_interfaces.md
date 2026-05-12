# ITTAGE Interface Specification
```
 FILE:    ittage_interfaces.md
 SOURCE:  various
 STATUS:  DRAFT, modified by hand
 UPDATED: 2026-04-29
 CONTACT: Jeff Nye
```

---

## Overview

ITTAGE is an indirect target tagged geometric history length predictor
providing target address prediction for indirect branches. It fires
at p2 alongside FTB and TAGE and overrides FTB target when ITTAGE
has a matching entry. ITTAGE does not predict direction -- it predicts
a 38-bit target address (upper 38 bits of a Sv39 VA; bit 0 is always
zero for instruction alignment and is not stored).

Five active tables: IT1-IT5. No IT0 base table. IT0 index position
in parameter arrays is a placeholder only and is never instantiated.
When no IT1-IT5 entry matches, ittage_hit is de-asserted in the
response and the consumer falls through to the FTB target.

Branch type partitioning is resolved upstream by the decoder and
carried in the FTB entry. ITTAGE operates exclusively on indirect
branches that are neither CALL nor RETURN. RAS handles CALL and
RETURN. No dynamic arbitration between ITTAGE and RAS is required
at p2.

Alternate provider and USE_ALT_ON_NA (UAON) are implemented,
following the same principles as TAGE. IT_UAON_WIDTH=4,
IT_UAON_THRES=8.

Pipeline: p0 index and tag hash calculation, p1 SRAM read and tag
match, p2 final target output.

All types defined in bp_defines_pkg.sv and bp_structs_pkg.sv. This
document describes port semantics, timing contracts, and
consumer/producer obligations. It does not restate struct field
layouts -- see bp_structs_pkg.sv.

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

Parameters for ITTAGE are found in section :ITTAGE parameters:
of rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv

---

## Port List

```
// clock and reset
input  logic                                   clk
input  logic                                   rstn

// prediction interface
input  logic              [NUM_PRED_SLOTS-1:0] ittage_pred_val_p0
input  ittage_pred_inp_t  ittage_pred_inp_p0[0:NUM_PRED_SLOTS-1]
output logic              [NUM_PRED_SLOTS-1:0] ittage_pred_rdy_p2
output ittage_pred_meta_t ittage_pred_meta_p2[0:NUM_PRED_SLOTS-1]

// update interface
input  logic              [NUM_PRED_SLOTS-1:0] ittage_upd_val_u0
input  ittage_upd_inp_t   ittage_upd_inp_u0[0:NUM_PRED_SLOTS-1]
output logic              [NUM_PRED_SLOTS-1:0] ittage_upd_rdy_u1

// aging control -- shared across both slots
input  logic                                   ittage_enable_aging
input  logic              [31:0]               ittage_aging_interval

input  bp_folded_hist_t   folded_hist,

// ram init interface
output logic ittage_rdy
```

---

## Struct Definitions

All structs defined in bp_structs_pkg.sv.

### ittage_pred_inp_t

Input bundle presented with each prediction request.
Carries branch PC and branch_id for the slot.
See bp_structs_pkg.sv for the authoritative definition.

### ittage_pred_meta_t

Prediction output and metadata. Carries primary and alternate
component indices, confidence counters, useful bits, allocation
target, predicted targets for both primary and alternate, UAON
flag, ittage_hit, and branch_id.
See bp_structs_pkg.sv for the authoritative definition.

### ittage_upd_inp_t

Update input bundle. Contains prediction metadata captured at
predict time plus resolution fields supplied by the top level.
See bp_structs_pkg.sv for the authoritative definition.

---

## Prediction Interface

### Producer: ittage
### Consumer: BP cluster (p2 target mux, FTQ write)

### Timing

```
ittage_pred_inp_p0[s] is presented at p0. folded_hist
(bp_folded_hist_t from bp_history) is also presented at p0.
Index and tag hash logic is combinational within each
ittage_table instance at p0.
p1: SRAM read completes. Tag match and hit processing
    execute in p1.
p2: Final target flopped out. ittage_pred_meta_p2[s]
    and ittage_pred_rdy_p2[s] are valid at p2.
```

### Folded History Input

`folded_hist` is the `bp_folded_hist_t` output of
bp_history. It is shared across both prediction slots
and passed directly to each ittage_table instance.
Each ittage_table instance selects its table-specific
fields and derives index_hash and tag_hash locally.
ITTAGE consumes the following fields for index and tag
computation:

```
it_t1_idx_fh, it_t1_tag_fh1, it_t1_tag_fh2
it_t2_idx_fh, it_t2_tag_fh1, it_t2_tag_fh2
it_t3_idx_fh, it_t3_tag_fh1, it_t3_tag_fh2
it_t4_idx_fh, it_t4_tag_fh1, it_t4_tag_fh2
it_t5_idx_fh, it_t5_tag_fh1, it_t5_tag_fh2
```

PHR contribution to index and tag hashing is TBD. All current
folds are GHR-derived only.

### Semantics

```
ittage_pred_val_p0[s] = 1  -- valid prediction request for
                              slot s. ITTAGE will process and
                              produce ittage_pred_meta_p2[s]
                              two cycles later.
ittage_pred_val_p0[s] = 0  -- no request for slot s.
                              ittage_pred_rdy_p2[s] will be
                              0 at p2.
ittage_pred_rdy_p2[s] = 1  -- ittage_pred_meta_p2[s] is valid.
```

Both slots may have ittage_pred_val_p0 asserted in the same
cycle. Slots operate independently with no cross-slot
interaction.

ITTAGE has no base table (no IT0). When no IT1-IT5 table hits,
ittage_hit is de-asserted in ittage_pred_meta_p2[s] and the
consumer uses the FTB target. ittage_pred_rdy_p2[s] still
asserts -- the response is valid regardless of hit status.
ittage_pred_meta_p2[s].ittage_pred_tgt carries the predicted
target address when ittage_hit is asserted.

The primary component is the longest-history tagged table with
a matching entry. The alternate component is the next-longest
hitting table.

#### Selection of primary or alternative:

The provider is either a) primary component b) alternative
component c) none when no tagged table is hit.

All tables are accessed in parallel. It is possible for there
to be 0, 1, or many hits. When there are no hits ittage sets
ittage_hit=0. Else ittage_hit=1.

When the primary component's CTR is zero (null confidence) and
the UAON counter is >= IT_UAON_THRES the alternative component
becomes the provider.

For full provider selection scan logic see
ittage_cntrl_decisions.md §Prediction Phase.
Operation of the UAON is described in
ittage_cntrl_uaon_update_rules.md.

ITTAGE processes up to two indirect branches, one for each
prediction slot.

### Hash Functions

Each ittage_table instance generates index_hash and tag_hash
locally. These hashes are used to access the RAMs in p0.

The hash operations are defined in ittage_table_hash_rules.md.

### Consumer Obligations

- Must not consume ittage_pred_tgt when ittage_hit is not
  asserted.
- Must use FTB target when ittage_hit is not asserted.
- Must write ittage_pred_meta_p2[s] into FTQ meta path when
  ittage_pred_val_p0[s] was asserted, regardless of hit status.
  The update path requires these fields unconditionally.
- Must set pred_src in bp_ftq_entry_t to PRED_ITTAGE when
  ITTAGE overrides FTB target.
- Must assert s2_redirect when ittage_hit is asserted and
  ittage_pred_tgt disagrees with FTB target.
- Must gate ITTAGE prediction on indirect branch type only.
  CALL and RETURN are handled by RAS exclusively.

### ITTAGE Simulation Support
- ITTAGE_FAST_INIT: runtime plusarg (+ITTAGE_FAST_INIT=1).
  Read in ittage.sv and ittage_table.sv.
  When set: ittage_table initial blocks
  write bw_ram mem arrays via hierarchical reference
  at time zero. ittage.sv straps all tbl_ri_* to zero
  and drives ittage_rdy=1 immediately. sram_init
  elaborates but is fully bypassed.
  When not set: sram_init sequences all entries,
  ittage_rdy follows tbl_ri_rdy from sram_init.
  Simulation-only mechanism. No synthesis impact.
  bw_ram.sv is not modified.
- ITTAGE_SRAM_INIT_VALUE: localparam int in
  bp_defines_pkg.sv, default 0. Used by sram_init
  (.INIT_VAL) and ittage_table initial blocks.

---

## Update Interface

### Producer: post-execute resolution path (BP cluster)
### Consumer: ittage

### Timing

ittage_upd_inp_u0[s] is presented at u0. Sampled on rising
clk edge. ittage_upd_rdy_u1[s] is asserted at u1 when the
update has been applied. Update completes in one cycle.
ittage_upd_val_u0[s] may be asserted in any cycle. No ordering
constraint between update channels when NUM_PRED_SLOTS=2.
Both channels processed independently in the same cycle.

## RAM Init Interface

Output ittage_rdy indicates that the RAM initialization cycles
have completed. This would tied to the .ready output of
the sram_init module.

No prediction or update cycles should begin before ittage_rdy
has been asserted. ITTAGE should ignore prediction and update
requests when ittage_rdy is not asserted. It is the
responsibility of upstream logic to comprehend this condition.

---

### Semantics

```
ittage_upd_val_u0[s] = 0  -- no update this cycle for slot s.
                             ittage_upd_inp_u0[s] ignored.
ittage_upd_val_u0[s] = 1  -- resolved update for slot s.
                             All ittage_upd_inp_u0[s] fields
                             valid.
ittage_upd_rdy_u1[s] = 1  -- update applied for slot s.
```

### Update Behavior

CTR is a confidence counter, not a direction counter. It tracks
confidence in the stored target address for the provider entry.

The provider is determined by ittage_using_primary: when 1 the
primary table entry supplied the prediction; when 0 the alternate
supplied it. The corresponding CTR write port is asserted --
either prm_ctr_wr_u0 or alt_ctr_wr_u0, never both in the same
cycle. Both write ports are real and active. They are mutually
exclusive by design, not by omission.

The definitive operation of CTR updates is found in
ittage_cntrl_ctr_update_rules.md.

The definitive operation of update time allocations is found in
ittage_cntrl_alloc_rules.md.

### Target Write Gating (tgt_wr_u0)

The target field is written only when all three conditions hold:

```
  indir_mispredict == 1
  AND provider CTR from meta == 3'b000 (null confidence)
  AND THIS_TABLE matches the provider table selector
```

The provider table selector depends on which provider was used:

```
  ittage_using_primary == 1: match prm_tbl_sel_u0
  ittage_using_primary == 0: match alt_tbl_sel_u0
```

tgt_wr_u0 and the active CTR write port (prm_ctr_wr_u0 or
alt_ctr_wr_u0) are mutually exclusive. From Seznec: if CTR is
non-null on misprediction, decrement CTR -- no target write.
If CTR is null on misprediction, replace target -- CTR stays
at null, no CTR write. Both strobes are never asserted in the
same cycle for the same entry.

### Read-during-Write Contract

Prediction and update paths are mutually exclusive by design.
The prediction path is read-only. The update path is write-only.
No read-modify-write cycles are required or permitted.

### Producer Obligations

- Must provide resolved_target from execute, not speculative.
- Must pass ittage_pred_meta_p2[s] captured at predict time
  unmodified into ittage_upd_inp_u0[s]. No recomputation at
  update.
- Must not assert upd_val on the same branch_id via both
  channels in the same cycle (undefined update order).

---

## Bank Address Assignment

See ittage_table_interfaces.md §Bank Address Assignment.

---

## Override Chain Position

ITTAGE sits at s2 alongside FTB and TAGE. ITTAGE overrides FTB
target (not direction) when a hit occurs:

```
s1: uBTB + Loop
s2: FTB + TAGE + ITTAGE + RAS
s3: SC
```

Override priority at s2 for target selection:

```
ITTAGE > FTB (for indirect branches only)
RAS    > FTB (for RETURN branches only)
```

ITTAGE and RAS operate on mutually exclusive branch classes.
No dynamic arbitration between them is required.

SC at s3 overrides TAGE direction for conditional branches only.
SC does not interact with ITTAGE target prediction.

---

## Known Gaps and Deferred Items

| ID  | Item                                   | Status             |
|-----|----------------------------------------|--------------------|
| II1 | bp_folded_hist_t missing               | Complete           |
|     | it_t5_idx_fh, it_t5_tag_fh1,           |                    |
|     | it_t5_tag_fh2. Comment in              |                    |
|     | bp_structs_pkg.sv states "IT5 is       |                    |
|     | BrIMLI -- no folds" which is           |                    |
|     | incorrect.                             |                    |
| II2 | PHR contribution to index/tag hashing  | TBD at impl.       |
|     | All current folds are GHR-derived only.|                    |
| II3 | Flush port definitions (_px signals)   | TBD. Not yet       |
|     | not yet defined.                       | defined.           |
| II4 | FTQ meta overload scheme for ITTAGE    | G10 in             |
|     | and TAGE sharing index fields at       | bp_cluster.md.     |
|     | update.                                |                    |
| II5 | No-hit allocation scan direction.      | Complete           |
|     | Confirm scan from IT1 at impl.         |                    |
| II6 | tgt_wr_u0 gating definition.           | Complete           |
|     | Gating conditions and mutual           |                    |
|     | exclusion with CTR write defined in    |                    |
|     | Target Write Gating section above      |                    |
|     | and in ittage_cntrl_decisions.md.      |                    |

