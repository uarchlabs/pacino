<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTQ to BPU Interface
```
 FILE:    ftq_bpu_interfaces.md
 SOURCE:  fe_decisions.md, bpu_port_inventory.md (INFRA-011),
          bp_structs_pkg.sv, bp_cluster.sv
 STATUS:  DRAFT
 UPDATED: 2026-08-09
 CONTACT: Jeff Nye
```

Specifies the signals crossing the FTQ/BPU boundary and the routing
from that boundary to the ports each predictor declares.

fe_decisions.md is the theory of operation. This file is the port
specification. The RTL port declaration is the reference for every
port named here. Where fe_decisions.md or bp_structs_pkg.sv
disagrees with the RTL, section 10 states the correction the other
file needs.

---

## 1. Scope

Covered:
- prediction request from FTQ into the cluster
- prediction results out of the cluster
- redirects, derived at the cluster boundary
- prediction metadata out of the cluster
- updates from FTQ into each predictor
- history checkpoint and rollback
- configuration and status sidebands

Not covered:
- IFU to FTQ (TD-FE-1, unspecified)
- EXE to FTQ resolution
- predictor internals
- RAM arbitration (bp_arb_spec.md)

---

## 2. Conventions

Predictor ports are named as declared in the RTL. The eight modules
do not share one naming convention. This file uses each module's
actual port names and does not propose renaming.

Naming variance present in the shipped RTL, recorded so a reader is
not surprised by it:

```
  tage, ittage, sc     <pred>_<signal>_<stage>, slot as unpacked
                       [0:NUM_PRED_SLOTS-1] after the port name
  ras                  same form, no queue-status ports
  ubtb                 slot as packed [NUM_PRED_SLOTS-1:0] on the
                       type
  loop_pred            per-slot since BP-091; prediction output
                       named pred_p1, update ports keep a p0 suffix
  ftb                  flat ports, no structs, no slot dimension
  bp_history           no stage suffixes, literal [1:0] and [2]
                       dimensions
```

Cluster-boundary signals defined in this file and not present in any
shipped RTL are marked NEW. Everything else names a declared port.

Array direction follows the package convention: packed-struct
dimensions descend, `[NUM_PRED_SLOTS-1:0]`; port dimensions ascend,
`[0:NUM_PRED_SLOTS-1]`.

Internal cluster nets carry a `w_` prefix. Stage registers carry an
`r_` prefix with the stage in the suffix.

Stage labels are p0/p1/p2/p3 for prediction and u0/u1 for update.

---

## 3. Prediction request: FTQ to BPU

The FTQ drives one prediction request per cycle into the cluster.

```
  ftq_pred_val_p0                          request valid
  ftq_pred_pc_p0    [VA_WIDTH-1:0]         fetch block start PC
  ftq_pred_idx_p0   [FTQ_IDX_BITS-1:0]     allocated FTQ index
```

The FTQ index is presented at p0 so the cluster can carry it into
the predictor input structs, which hold it as `branch_id`.

The cluster qualifies the request with the prediction-queue status
of the queued predictors before presenting it to any of them, so all
eight stay in lockstep and no prediction is dropped. The FTQ must
not present a request while a `pq_not_full` output is low; the
cluster has no request-ready output.

Cluster routing of the request:

| Destination      | Port                | Notes                    |
|------------------|---------------------|--------------------------|
| ubtb             | pred_pc_p0          | scalar PC                |
| loop_pred        | pred_pc_p0          | per slot                 |
| loop_pred        | pred_valid_p0       | per slot                 |
| ftb              | pred_pc_p0          | scalar PC                |
| ftb              | pred_valid_p0       | request valid            |
| tage             | tage_pred_val_p0    | per-slot bit vector      |
| tage             | tage_pred_inp_p0    | tage_pred_inp_t per slot |
| ittage           | ittage_pred_val_p0  | per-slot bit vector      |
| ittage           | ittage_pred_inp_p0  | ittage_pred_inp_t/slot   |

`tage_pred_inp_t` and `ittage_pred_inp_t` each carry `pc` and
`branch_id`. The cluster builds one per slot from the request.

Every slot of `loop_pred.pred_pc_p0` is driven from the one request
PC. There is no slot-1 PC at p0; the per-slot dimension is a shape,
the same way the cluster drives `sc.inp_pc_p2` per slot from a single
staged p2 copy.

ubtb has no request-valid port. It presents an output every cycle.

sc takes no p0 request. It is driven from the TAGE p2 result
(section 5.3).

RAS presents its top of stack at p0; see section 5.4.

---

## 4. Initial prediction: p1

ubtb and loop_pred produce the p1 prediction. Neither is a redirect
source.

```
  ubtb.pred_p1       ubtb_pred_t [NUM_PRED_SLOTS-1:0]   out
  ubtb.blk_p1        ubtb_blk_t                         out
  loop_pred.pred_p1  lp_pred_t   per slot               out
```

`ubtb_blk_t` carries the entry hit and the reconstructed
fall-through address. The hit is reported once per lookup; a slot's
own valid bit says only whether that slot carries a branch.

`lp_pred_t` carries the loop table snapshot, including lp_hit,
lp_pred_is_loop, and lp_pred_taken. It carries no target: the loop
predictor supplies a direction only, and the target comes from the
uBTB entry when the loop predictor wins.

loop_pred is per-slot as of BP-091 and its prediction output is named
`pred_p1`. TD#105 is closed.

The p1 selection mux is cluster logic, per slot:

```
  lp_pred_is_loop set   ->  loop_pred supplies the direction
  else ubtb slot valid  ->  ubtb supplies the slot
  else                  ->  slot carries no prediction
```

There is no slot-0 exception to this rule.

A uBTB RETURN takes its target from the registered RAS top of stack
rather than from the uBTB entry.

Producer alignment. `ubtb.pred_p1` is combinational from
`pred_pc_p0` and is therefore valid in the p0 cycle; loop_pred's
output is registered and is valid in the p1 cycle. The cluster
registers the uBTB result once so both describe the same request
when the selection mux reads them.

Cluster output to the FTQ at p1:

```
  bpu_pred_val_p1                                 NEW
  bpu_pred_idx_p1  [FTQ_IDX_BITS-1:0]             NEW
  bpu_pred_slot_p1 bp_ftq_slot_t
                     [0:NUM_PRED_SLOTS-1]         NEW
  bpu_pred_ras_p1  bp_ras_snapshot_t              NEW
  bpu_pred_pft_p1  [VA_WIDTH-1:0]                 NEW
```

The FTQ writes these into the entry it allocates at p1. Allocation
is unconditional: an entry is allocated for every prediction block,
including one the p1 predictors miss, so a later stage has an entry
to correct.

`bpu_pred_pft_p1` is the block fall-through: the address the front
end fetches after this block when no slot in the block is taken.
One value per prediction, not one per slot, and qualified by
`bpu_pred_val_p1` -- it carries no valid of its own. TD#108.

It is the p1 view of the fall-through and is exactly the not-taken
term the cluster already uses when it forms each slot's p1
successor for the section 6 redirect comparison: `blk_p1.pft_addr`
on a uBTB hit, and the block-aligned request PC plus
FTB_BLOCK_BYTES on a miss, where `blk_p1.pft_addr` reads zero. It
is not the FTB `pftAddr` of section 5.1, which arrives at p2.

The FTQ writes it into the allocated entry as
`bp_ftq_entry_t.pft_addr`. The port is present only in the p1 cycle
and the FTQ re-evaluates the block successor on every redirect
(fe_decisions.md 2.4), so the not-taken arm is read back from the
entry rather than resampled from the cluster.

---

## 4a. Slot correction: p2 and p3

The p1 group of section 4 is the uBTB and loop-predictor view. The
FTB classifies the block at p2 and supplies each branch field's
in-block position. The cluster republishes its view of every slot at
p2, and again at p3 with the SC direction applied.

```
  bpu_slot_val_p2                                 NEW
  bpu_slot_idx_p2  [FTQ_IDX_BITS-1:0]             NEW
  bpu_slot_p2      bp_ftq_slot_t
                     [0:NUM_PRED_SLOTS-1]         NEW
  bpu_slot_val_p3                                 NEW
  bpu_slot_idx_p3  [FTQ_IDX_BITS-1:0]             NEW
  bpu_slot_p3      bp_ftq_slot_t
                     [0:NUM_PRED_SLOTS-1]         NEW
```

Same type as `bpu_pred_slot_p1`. The FTQ overwrites the slot
description of the named entry with the latest group received.

`bpu_slot_val_p2` is `r_val_p2 & ftb_valid_p2`: the cluster has a
corrected view only when the FTB answered. `bpu_slot_val_p3` is
`r_val_p3`.

THIS IS NOT A REDIRECT AND IS NOT GATED ON ONE. A redirect fires only
when the p2 successor differs from the p1 successor. The case that
matters most does not qualify: a conditional the uBTB missed and the
FTB found, predicted not taken. Both views end the block at the same
address, no redirect fires, and the entry would otherwise keep
`br_type` NO_BRANCH and `pos` zero -- so section 7.2 would form no
update and no predictor would ever be trained on that branch.
TD-FE-6, FE-13.

Field sources at p2:

| Field        | Source                                          |
|--------------|-------------------------------------------------|
| `slot_valid` | FTB conditional field valid, or jump placement  |
| `br_type`    | FTB classification, `w_br_type_p2`              |
| `taken`      | TAGE when its branch_id matches, else FTB       |
| `target`     | section 3.3 target table by branch type         |
| `pos`        | `ftb_br0_pos_p2` / `ftb_br1_pos_p2`, or         |
|              | `ftb_jmp_pos_p2` for the jump slot              |
| `pred_src`   | the arm that supplied the target                |
| `confidence` | zero, FE-U3                                     |

p3 changes `taken`, and `pred_src` to PRED_SC when SC actually moved
the direction. SC corrects direction, not branch type, so `br_type`,
`pos` and `target` pass through the p2 to p3 register unchanged.

---

## 5. Late predictions: p2 and p3

### 5.1 FTB

ftb declares 42 flat ports. The p2 outputs the cluster consumes:

```
  ftb_valid_p2       ftb_hit_p2        ftb_way_p2
  ftb_br0_valid_p2   ftb_br0_pos_p2    ftb_br0_taken_p2
  ftb_br0_conf_p2    ftb_br0_target_p2
  ftb_br1_valid_p2   ftb_br1_pos_p2    ftb_br1_taken_p2
  ftb_br1_conf_p2    ftb_br1_target_p2
  ftb_jmp_valid_p2   ftb_jmp_pos_p2    ftb_jmp_target_p2
  ftb_is_call_p2     ftb_is_ret_p2     ftb_is_jalr_p2
  ftb_pft_addr_p2    ftb_fastpath_p2 [1:0]
```

br0 maps to slot 0 and br1 to slot 1 at the cluster boundary. That
mapping is PROGRAM ORDERED as of IC-FTB-16: the update path fills br0
with the earlier branch, so slot 0 is the block's first branch and
slot 1 its second. The
FTB is not internally slot-split: one lookup supplies both branch
fields of one 32-byte block (ftb_decisions.md 2.1, 2.3).
`ftb_fastpath_p2` is already a per-slot vector, bit 0 for br0 and
bit 1 for br1.

`ftb_pft_addr_p2` is the fall-through address used when a slot's
direction resolves not-taken.

The block's single jump field is placed in the lowest prediction
slot carrying no valid conditional field. The jump is the
block-terminating branch, so lowest-free-slot placement is program
order.

ftb declares no FTQ index port. The cluster tracks the index
positionally through the p0 to p2 pipeline.

`ftb_hit_p2` and `ftb_way_p2` are the carried writeWay scheme
(IC-FTB-10): they are captured at predict and returned to the FTB on
the update port as `ftb_upd_hit_u0` and `ftb_upd_way_u0`, so the FTB
does not re-look-up the tag. They travel through the FTQ; see
section 7.

### 5.2 TAGE and ITTAGE

```
  tage_pred_rdy_p2    [NUM_PRED_SLOTS-1:0]        out
  tage_pred_meta_p2   tage_pred_meta_t per slot   out
  ittage_pred_rdy_p2  [NUM_PRED_SLOTS-1:0]        out
  ittage_pred_meta_p2 ittage_pred_meta_t per slot out
```

TAGE supplies direction: `tage_pred_meta_t.tage_pred_tkn`. ITTAGE
supplies a target: `ittage_pred_meta_t.ittage_prm_tgt` or
`ittage_alt_tgt`, selected by `ittage_using_primary`.
`ittage_hit` clear means the FTB target stands.

The ITTAGE target field holds the upper bits of an Sv39 VA with bit
0 not stored. The cluster reconstructs the full width by appending
the zero bit and sign-extending.

Both metadata structs carry `branch_id`. Every p2 and p3 comparison
is qualified by `branch_id` equal to the FTQ index held in the
matching stage register, so a queued or back-pressured response
cannot be compared against the wrong entry. The redirect logic
therefore assumes no fixed predictor latency.

### 5.3 SC

sc consumes the TAGE p2 result directly:

```
  tage_pred_rdy_p2   in   from tage
  tage_pred_meta_p2  in   from tage
```

The TAGE p2 result fans out to both the FTQ boundary comparison and
the sc input.

sc history and PC inputs, driven by the cluster:

```
  inp_pc_p2        [VA_WIDTH-1:1]     per slot   TD#91
  sc_phr_p2        [9:0]              scalar     TD#92
  sc_t1_idx_fh_p2  [SC_MAX_FH-1:0]    scalar
  sc_t2_idx_fh_p2  [SC_MAX_FH-1:0]    scalar
  sc_t3_idx_fh_p2  [SC_MAX_FH-1:0]    scalar
```

sc does not take `bp_folded_hist_t`. The cluster slices the three SC
folds and the low 10 bits of `tage_phr` out of the struct and drives
them as separate ports.

ALL FIVE are staged p0 to p2 by the cluster. The three folds were
connected live to bp_history until BP-090; because bp_history
advances whenever a branch is predicted, the live folds at p2
described history newer than the block SC was indexing. Same class of
signal as the PC and the phr, same staging. TAGE and ITTAGE take
`bp_folded_hist_t` whole at their own p0 request and stage
internally; only SC takes sliced folds.

sc p3 output:

```
  sc_pred_rdy_p3   [NUM_PRED_SLOTS-1:0]     out
  sc_pred_meta_p3  sc_pred_meta_t per slot  out
```

`sc_pred_meta_t.sc_pred_tkn` is the final direction for the slot;
`sc_override` records whether SC changed the TAGE direction.

### 5.4 RAS

```
  ras_tos_addr_p0     [VA_WIDTH-1:0]    per slot  out
  ras_tos_valid_p0    logic             per slot  out
  ras_pred_val_p2     logic             per slot  in
  ras_br_type_p2      bp_br_type_e      per slot  in
  ras_pc_p2           [VA_WIDTH-1:0]    per slot  in   TD#101
  ras_fall_through_p2 [VA_WIDTH-1:0]    per slot  in
  ras_pop_addr_p2     [VA_WIDTH-1:0]    per slot  out
  ras_pop_valid_p2    logic             per slot  out
  ras_snapshot_p2     bp_ras_snapshot_t per slot  out
  ras_pred_val_p3     logic             per slot  in
  ras_br_type_p3      bp_br_type_e      per slot  in
```

The top of stack is presented at p0. The push or pop executes at p2
once `ras_br_type_p2` carries the FTB classification. The p3 pair
takes the registered p2 classification.

`ras_pc_p2` is declared and unread (TD#101). The cluster drives it
from the staged p2 PC.

RAS p2 operations are qualified by reachability across slots: a
taken branch ends the block, so a later slot is off the predicted
path and must not push or pop (FE-11). One snapshot per entry is
therefore sufficient.

Restore and commit ports, section 8.

---

## 6. Redirects

No predictor declares a redirect port. The inventory confirms this
across all 140 ports of all eight modules.

A redirect is derived at the cluster boundary by comparing a
predictor's stage output against the prediction the cluster formed
at p1 and carried forward in its own stage registers (FE-4). The
cluster does not read the FTQ.

```
  bpu_redir_p2      bp_redirect_t [0:NUM_PRED_SLOTS-1]   NEW
  bpu_redir_idx_p2  [FTQ_IDX_BITS-1:0]                   NEW
  bpu_redir_p3      bp_redirect_t [0:NUM_PRED_SLOTS-1]   NEW
  bpu_redir_idx_p3  [FTQ_IDX_BITS-1:0]                   NEW
```

`bp_redirect_t` is the per-slot payload and carries `target_pc` and
`valid`. The index is scalar and sits alongside the array, since
both slots occupy one FTQ entry.

The group is named by STAGE, not by predictor. p2 carries the FTB,
TAGE, ITTAGE, and RAS corrections; p3 carries the SC correction.

The comparison is expressed as one quantity, the slot successor
address, rather than as a taken/target pair. Both the p1 and the p2
view are reduced to the address fetched after that slot, so two
not-taken views compare equal and raise no redirect.

The p1 operand is formed at p1 from the p1 view only: the slot
target when taken, the uBTB fall-through on a hit, the
block-aligned PC plus FTB_BLOCK_BYTES on a miss. A stale uBTB block
boundary therefore redirects at p2 rather than letting the front end
fetch past a boundary the FTB had already contradicted.

The p3 comparison is against the p2-corrected value, not the raw p1
prediction, so a p3 redirect fires only when SC changes the value
the cluster published at p2.

A redirect from a later stage supersedes an earlier redirect for the
same entry index and slot. Supersession does not cross slots.

---

## 7. Prediction metadata: BPU to FTQ

The FTQ slow path (`bp_ftq_meta_t`) holds the state each predictor
needs to train and cannot recompute at resolution. It is written at
prediction time and read once at resolution to form the updates of
section 8.

Without this group the update path cannot work at all:
`tage_upd_inp_t` embeds `tage_pred_meta_t`, `ittage_upd_inp_t`
embeds `ittage_pred_meta_t`, and `sc_upd_inp_t` embeds
`sc_pred_meta_t`. Those values exist only at predict time.

The metadata finalizes at two stages, so there are two write groups.
Each writes a disjoint set of `bp_ftq_meta_t` members, so the FTQ
never has to merge.

### 7.1 p2 write

```
  bpu_meta_val_p2                                      NEW
  bpu_meta_idx_p2     [FTQ_IDX_BITS-1:0]               NEW
  bpu_meta_tage_p2    tage_pred_meta_t
                        [0:NUM_PRED_SLOTS-1]           NEW
  bpu_meta_ittage_p2  ittage_pred_meta_t
                        [0:NUM_PRED_SLOTS-1]           NEW
  bpu_meta_lp_p2      lp_pred_t
                        [0:NUM_PRED_SLOTS-1]           NEW
  bpu_meta_ftb_p2     ftb_pred_meta_t
                        [0:NUM_PRED_SLOTS-1]           NEW
```

The FTB classification is NOT carried here. It travels on the slot
correction group of section 4a, which writes it into the fast-path
entry where section 7.2 reads it.

Writes the `tage`, `ittage`, `lp` and `ftb` members of
`bp_ftq_meta_t` for the entry named by `bpu_meta_idx_p2`.

The TAGE and ITTAGE metadata are the predictor outputs passed
through unchanged.

The loop predictor finalizes at p1, not p2. The cluster registers
its p1 result and presents it in the p2 group so the FTQ performs
one slow-path write per entry rather than two. The `lp` member of
`bp_ftq_meta_t` is `lp_pred_t`, the same type loop_pred outputs, so
the cluster passes the registered result through unchanged. TD#106
retired `bp_loop_meta_t`, which carried the same thirteen fields in
a different order; the cluster's field-by-field map went with it.
See section 10, item 9.

Every slot carries its own loop snapshot. The zero drive that
covered slots above 0 before the loop predictor was per-slot is gone
(BP-091).

### 7.2 p3 write

```
  bpu_meta_val_p3                                      NEW
  bpu_meta_idx_p3     [FTQ_IDX_BITS-1:0]               NEW
  bpu_meta_sc_p3      sc_pred_meta_t
                        [0:NUM_PRED_SLOTS-1]           NEW
```

Writes the `sc` member of `bp_ftq_meta_t` for the entry named by
`bpu_meta_idx_p3`. This is the SC predictor output passed through
unchanged.

`bpu_meta_val_p3` is asserted whether or not SC is enabled, so the
entry's slow path is always complete. When SC is disabled the
written value carries no prediction and the FTQ forms no SC update.

### 7.3 FTB metadata

`bp_ftq_meta_t` carries an `ftb` member of type `ftb_pred_meta_t`,
holding the FTB state the update path needs:

```
  hit                              tag hit at predict
  way   [FTB_WAY_BITS-1:0]         hit way, or the PLRU victim
  jmp_pos [FTB_BR_POS_BITS-1:0]    jump field in-block position
```

The FTB determines the hit result and the write way at the
prediction read and does not re-look-up the tag at update
(IC-FTB-10). The FTQ returns them on `ftb_upd_hit_u0` and
`ftb_upd_way_u0`.

These are scalar within the entry, not per slot: the FTB indexes one
entry per lookup and both slots come from it. `bp_ftq_meta_t` is
carried per slot, so the cluster writes the same values to every
slot's copy.

### 7.4 In-block positions

The per-branch in-block position lives in `bp_ftq_slot_t.pos`, in
the fast-path entry, sourced from `ftb_br0_pos_p2` and
`ftb_br1_pos_p2` and delivered on the section 4a slot correction
group. Until that group existed no port carried either signal out of
the cluster and this paragraph described something unbuildable
(TD-FE-6). The FTQ uses it to order br0 against br1 and to
locate the taken branch in the fetch bundle (IC-FTB-15), and returns
the resolving branch's position on `ftb_upd_pos_u0`.

Locating a branch in the fetch bundle is every-cycle work, so the
position belongs on the fast path rather than in the update-only
metadata. The jump field's position travels in the metadata group
(7.3), since it is one value per entry rather than one per slot.

The uBTB also produces a position on `ubtb_pred_t.pos`, so the p1
prediction can fill `bp_ftq_slot_t.pos` before the FTB result
arrives.

The position addresses two-byte slots: FTB_BR_POS_BITS is
`$clog2(FTB_BLOCK_BYTES/2)`, so a 32-byte block has sixteen
positions. RVA23 mandates the C extension, so a branch may begin at
any 2-byte boundary and the position must resolve that. The cluster
also uses the position to form the branch PC it reports to
bp_history, block base plus position times two (BP-092a, section 9).

### 7.5 Fields with no consumer

`ftb_br0_conf_p2`, `ftb_br1_conf_p2` and `ftb_fastpath_p2` are FTB
outputs that no port in this specification carries. The confidence
values are exposed for observability, and the fast-path bypass is
not yet built at the cluster. They are recorded here so a reader
does not mistake their absence for an omission.

---

## 8. Updates: FTQ to BPU

One update channel per prediction slot. The FTQ reads
`bp_ftq_meta_t` at resolution and forms the per-predictor update
payloads from `bp_update_t`, the resolved-branch record.

| Predictor | Valid port        | Payload port    | Ready port      |
|-----------|-------------------|-----------------|-----------------|
| ubtb      | in ubtb_upd_t     | upd_u0          | none            |
| loop_pred | upd_valid_p0      | upd_p0          | none            |
| ftb       | ftb_upd_valid_u0  | 14 flat ports   | none            |
| tage      | tage_upd_val_u0   | tage_upd_inp_u0 | tage_upd_rdy_u1 |
| ittage    | ittage_upd_val_u0 | ittage_upd_inp  | ittage_upd_rdy  |
| sc        | sc_upd_val_u0     | sc_upd_inp_u0   | sc_upd_rdy_u1   |
| ras       | ras_commit_val    | 3 commit ports  | none            |

Notes:
- ubtb carries the valid inside `ubtb_upd_t.valid`; it has no
  separate valid port.
- loop_pred update ports carry a p0 suffix, not u0. They are
  per-slot as of BP-091, at both the module and the cluster
  boundary (`lp_upd_valid_p0`, `lp_upd_p0`).
- ftb update is 14 flat ports: ftb_upd_pc_u0, ftb_upd_hit_u0,
  ftb_upd_way_u0, ftb_upd_is_br_u0, ftb_upd_br_idx_u0,
  ftb_upd_taken_u0, ftb_upd_target_u0, ftb_upd_pos_u0,
  ftb_upd_is_jmp_u0, ftb_upd_jmp_target_u0, ftb_upd_is_call_u0,
  ftb_upd_is_ret_u0, ftb_upd_is_jalr_u0, ftb_upd_pft_addr_u0.
- ras update is the commit group: ras_commit_val,
  ras_commit_br_type, ras_commit_ret_addr, ras_commit_snapshot.
- ftb and ras have no slot dimension on their update ports.

The uBTB and FTB update field sets mirror each other, so one set of
resolved facts forms both.

`ubtb_upd_t` carries no `br_type` field. The cluster rederives the
resolved type from the payload's own is_br / is_jmp / is_call /
is_ret / is_jalr bits, in the same arm order as ubtb.sv and the FTB
classification, with is_br outranking is_jmp. A missing br_type read
resolves to zero, which decodes as COND, so restoring the field
instead of rederiving the type would silently classify every update
as conditional and stop ITTAGE ever being updated.

Update fan-out by resolved br_type is fe_decisions.md 7.2. The three
encodings that table does not list follow from what each predictor
does: NO_BRANCH forms no update; DIRECT_CALL pushes RAS and updates
uBTB and FTB; INDIRECT_CALL updates ITTAGE for the target and RAS
for the return address.

Each queued predictor's update valid is additionally qualified by
its own queue ready, so no update is presented to a full queue. The
FTQ holds the update until it is accepted.

Queue status ports, driven out of the cluster:

```
  tage    tage_pq_not_full, tage_upd_rdy, tage_upd_rdy_u1
  ittage  ittage_pq_not_full, ittage_upd_rdy, ittage_upd_rdy_u1
  sc      sc_uq_not_full, sc_upd_rdy, sc_upd_rdy_u1
```

tage and ittage declare `pq_not_full` and `upd_rdy` with no
predictor prefix (TD#49). The cluster boundary adds the prefix so
the two groups are distinguishable.

RAS restore, driven on redirect from the snapshot in the entry being
corrected:

```
  ras_restore_val
  ras_restore_snapshot  bp_ras_snapshot_t
```

RAS flush ports `ras_flush_val` and `ras_flush_snapshot` are
declared. Flush behavior is TD#96.

---

## 9. History checkpoint and rollback

The checkpoint is the GHR and PHR circular-buffer pointer pair, one
per FTQ entry, held in the FTQ entry (FE-7). bp_history advances the
pointers and rolls back by index.

bp_history carries no stage suffix on any port.

Driven by the cluster at p1, from the formed prediction:

```
  pred_taken    [1:0]              bit n = branch n
  pred_pc       [VA_WIDTH-1:0] [2] one per branch, after compaction
  num_branches  [1:0]              count, 0 to 2
```

bp_history indexes these by BRANCH NUMBER, not by slot number, so
the cluster compacts the valid slots down before presenting them. A
bundle whose only branch sits in slot 1 presents that branch at
index 0.

`pred_pc` is the BRANCH PC, not the fetch block PC: the block base
plus that branch's in-block position, four bytes per position
(section 7.4). bp_history folds bits [3] and [2] of it into the PHR
path bit, and a block-aligned PC has those bits hard zero, so the
block PC would make the path bit a constant. See
bp_history_interfaces.md, Producer obligations, and BP-092a.

Checkpoint write, at allocation:

```
  ckpt_wr_en                          driven at p1 allocation
  ckpt_wr_idx  [FTQ_IDX_BITS-1:0]     FTQ index
```

Rollback, on redirect:

```
  rollback_valid
  rollback_ckpt_idx  [FTQ_IDX_BITS-1:0]
```

Driven from the derived redirect. When both stages redirect in the
same cycle the p3 index wins, matching the supersession rule.

Outputs:

```
  ghist_ptr       [GHIST_PTR_BITS-1:0]   current pointer
  phist_ptr       [PHIST_PTR_BITS-1:0]   current pointer
  ckpt_ghist_ptr  [GHIST_PTR_BITS-1:0]   checkpoint read
  ckpt_phist_ptr  [PHIST_PTR_BITS-1:0]   checkpoint read
  ghr_buf         [GHR_WIDTH-1:0]
  phr_buf         [PHR_WIDTH-1:0]
  folded          bp_folded_hist_t
```

`ckpt_ghist_ptr` and `ckpt_phist_ptr` are the pointer pair the FTQ
writes into the allocated entry as that entry's checkpoint.

`folded` drives `tage.folded_hist` and `ittage.folded_hist` whole.
sc takes sliced fields instead (section 5.3).

---

## 10. Package and document corrections required

The RTL is the reference. These are the changes other files need to
match it and to match this specification.

### bp_structs_pkg.sv

1. `bp_ftq_meta_t` is carried per slot. The array is declared at the
   port, not inside the struct, per the `bp_update_t` convention.

2. `bp_redirect_t` comments use s2/s3 stage labels. Change to p2/p3.

3. `branch_id` is commented "FTQ slot index" in `bp_ftq_entry_t`,
   `tage_pred_meta_t`, `sc_pred_meta_t`, and `ittage_pred_meta_t`.
   It is the FTQ entry index (TD-FE-5).

4. The uBTB index and tag comments read PC[26:7], which describes
   the retired instruction-granularity indexing. The uBTB now
   indexes at block granularity.

5. `ubtb_pred_t.carry` is commented as a property of the slot
   target. The implemented and specified behaviour is the entry
   fall-through carry.

### fe_decisions.md

6. CLOSED, INFRA-012, session-064. Section 2.2 and section 9 placed
   the RAS top of stack at p1. ras.sv declares `ras_tos_addr_p0` and
   `ras_tos_valid_p0`, at p0. Both corrected, and the section 1
   stage list updated to match.

7. CLOSED, INFRA-012, session-064. Section 3.1 named redirect
   signals `<pred>_redir_val_<pN>` and `<pred>_redir_tgt_<pN>`,
   reading as a per-predictor port group. No predictor declares a
   redirect port. Rewritten to the cluster-derived, stage-named
   group of section 6, with FE-4 restated and FE-12 added.

### Open items

8. CLOSED, TD#92, BP-090. SC index fold staging. `inp_pc_p2` and
   `sc_phr_p2` were staged p0 to p2 while the three SC index folds
   were connected live to bp_history, which advances whenever a
   branch is predicted, so at p2 the live folds described a later
   block than the one SC was indexing. All three folds are now
   staged the same way as the PC and the phr. Section 5.3 records
   it; bp_arb_spec.md 6.1 names them among the staged inputs.

9. CLOSED, TD#106, BP-092. `lp_pred_t` and `bp_loop_meta_t` carried
   the same field set under two spellings (`lp_past_itr` against
   `lp_pst_itr`, `lp_curr_itr` against `lp_cur_itr`) and the cluster
   mapped between them for the section 7.1 write. `lp_pred_t`
   survives, for consistency with the other predictor prediction
   types. `bp_loop_meta_t` is deleted from bp_structs_pkg.sv, the
   `lp` member of `bp_ftq_meta_t` is `lp_pred_t`, and the cluster's
   `lp_to_meta()` is deleted rather than rewritten. The two retired
   spellings disappear with the type.

10. `bp_ftq_meta_t` gains an `ftb` member of a new type
    `ftb_pred_meta_t` (hit, way, jmp_pos), so the FTB carried
    writeWay state travels inside the struct like every other
    predictor's state (section 7.3).

11. `bp_ftq_slot_t` gains a `pos` field of FTB_BR_POS_BITS, the
    in-block instruction position of that slot's branch
    (section 7.4).

15. CLOSED, 2026-08-19. `bp_ftq_entry_t` gains a `pft_addr` field of
    VA_WIDTH, block scalar, holding the value delivered on
    `bpu_pred_pft_p1`. Applied to bp_structs_pkg.sv and checked in
    tb_bp_pkg.sv. Entry width 182b -> 222b.

16. CLOSED, 2026-08-19. bp_cluster.sv gains the section 4a slot
    correction group, six ports, driven from the p2 classification,
    the FTB positions and the p2 target selection, plus a p3 stage
    register carrying the slot with the SC direction applied.
    tb_bp_cluster group I, 24 checks. sim_bp_cluster 973 -> 997, all
    47 targets green. An earlier draft of this item proposed a
    narrower `bpu_meta_brtype_p2`; it carried the type but not the
    position, and left section 7.4 unbuildable.

17. DEFERRED, not blocking. `bp_ftq_meta_t` becomes the two-arm
    packed union of ftq_entry_formats.md 3.1. It is a storage
    optimization only, 420b -> 277b per slot. tb_bp_cluster group F3
    proves that the p2 and p3 write groups touch DISJOINT members of
    the struct; under the union that holds only within `u.cond`,
    since `sc` and `ittage` alias, so F3 must be restated per arm
    when the union lands.

### loop_pred

12. CLOSED, TD#105, BP-091. loop_pred.sv was single-slot; no port
    carried a slot dimension. It is now per-slot on
    `pred_pc_p0`, `pred_valid_p0`, `pred_p1`, `upd_p0` and
    `upd_valid_p0`, with per-slot table banks (TI6), and the
    `pred_p0` to `pred_p1` rename is applied. loop_pred.sv,
    tb_loop_pred.sv, loop_pred_interfaces.md and the bp_cluster
    instantiation were all updated. The cluster boundary ports
    `lp_upd_valid_p0` and `lp_upd_p0` gained the slot dimension in
    the same task.

### bp_history

13. bp_history uses literal `[1:0]` and `[2]` where other modules
    use NUM_PRED_SLOTS. Deferred. Recorded INFRA-011.

14. bp_history does not generate the ITTAGE IT5 folds. ittage.sv
    wires `it_t5_idx_fh`, `tag_fh1` and `tag_fh2` to outputs that
    are never driven, so IT5 indexes on PC alone. TD#102.

---

## 11. Document history

```
  2026-08-02  Created, session-063. Written from fe_decisions.md,
              bpu_port_inventory.md (INFRA-011), and
              bp_structs_pkg.sv. Predictor ports named as declared;
              no renaming proposed. Redirect group named by stage,
              since no predictor declares a redirect port. RAS top
              of stack at p0 per ras.sv. Checkpoint held in the FTQ
              entry; bp_history rolls back by index. loop_pred
              described dual-slot per TD#105. bp_redirect_t arrayed
              per slot with ftq_idx removed. bp_ftq_slot_t defined.

  2026-08-02  Section 7 added: the prediction metadata write groups
              at p2 and p3, the FTB carried hit and way, and the
              in-block positions. Sections 8 through 11 renumbered.
              Section 4 updated for the reshaped uBTB interface
              (blk_p1, entry-scoped hit). Section 5 updated with the
              branch_id match rule, the jump slot placement rule and
              the RAS reachability rule. Section 6 updated with the
              successor-address comparison and the p3 comparison
              basis. Corrections 8 through 11 opened.

  2026-08-19  Section 4a added: the p2 and p3 slot correction
              groups, delivered in bp_cluster.sv. They carry the FTB
              classification and the in-block positions into the
              fast-path entry on every prediction, not only when a
              redirect fires. Section 7.4 was describing a path no
              port provided; it is now buildable. Item 16 closed,
              item 17 opened and deferred (TD-FE-6, TD-FE-2).

  2026-08-19  Section 4 records that the FTQ stores the p1
              fall-through in bp_ftq_entry_t.pft_addr; section 10
              item 15 opened and closed for the field addition.

  2026-08-09  INFRA-012 / session-064. Section 9 pred_pc corrected:
              it is one value per BRANCH after compaction, not one
              per slot, and it is the branch PC rather than the
              fetch block PC (BP-092a). Section 10 items 6, 7, 8 and
              12 closed: the fe_decisions.md RAS-stage and
              redirect-port corrections were applied by this task,
              the SC index folds were staged by BP-090, and the
              loop_pred dual-slot retrofit landed in BP-091. Item 14
              opened for the IT5 fold gap (TD#102). Section 2, 3, 4,
              5.3, 7.1, 7.4 and 8 updated to the post-BP-091,
              post-BP-092 RTL: loop_pred per-slot throughout, the
              slot-0 exception removed from the p1 mux, the SC folds
              described as staged, the uBTB update br_type rederived
              rather than carried, and the position granularity
              stated.
```

