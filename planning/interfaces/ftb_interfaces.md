<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTB Interface Contracts
```
 FILE:    planning/interfaces/ftb_interfaces.md
 SOURCE:  ftb_decisions.md (canonical), session-051/052/053
 STATUS:  DRAFT
 UPDATED: 2026-09-22
 CONTACT: Jeff Nye
```

Interface contract for the FTB module. Derived from ftb_decisions.md,
which is the canonical authority. Where this file and ftb_decisions.md
disagree, ftb_decisions.md wins and this file is wrong.

Conventions:
  - Stage notation: p0/p1/p2/p3 for prediction and u0/u1 for update,
    in every document and in the RTL (PROJECT_CORE.md,
    fe_decisions.md 12). This read that planning narrative uses
    s-stage; PROJECT_CORE supersedes that. Session-072.
  - FTB is a SINGLE data array, one lookup per cycle, one entry per
    block. There are NO per-slot RAMs and NO NUM_PRED_SLOTS unpacking
    on FTB ports. The cluster's two branches per cycle are br0 and br1
    of the one indexed entry (ftb_decisions.md 2.1).
  - TI6 per-slot RAMs is a TAGE/ITTAGE convention and does NOT
    apply to FTB. The G8/G17 pred_pc+32 bundle split does not apply
    either, AND NO LONGER EXISTS ANYWHERE: tage_interfaces.md TI3
    has slot 1's PC supplied on tage_pred_inp_p0[1].pc and records
    pred_pc+32 as an error that was removed. An earlier revision
    called it a TAGE/ITTAGE convention, which pointed the reader at
    something TAGE disowns. Corrected session-070; the FTB
    conclusion is unchanged.
  - Active-low reset: rstn. Rising-edge clock: clk. Storage-module
    enables are active low (IC-FTB-13).
  - VA_WIDTH = 41. All full-width addresses are [VA_WIDTH-1:0].
    41 because H is mandatory through Sha and a V=1 vsatp.MODE=Bare
    fetch PC is a 41-bit guest physical address (fe_decisions.md
    FE-19). Was 40; TD#122 tracks the RTL.
  - conf is a bimodal DIRECTION counter; its MSB is FTB's predicted
    direction. There is no always_taken bit (removed session-053).

---

## 1. Module Hierarchy

ftb (top, structural only)
  ftb_array (single 1R1W DATA array; one instance; pure RAM)
  ftb_plru  (entry-valid bits + tree-PLRU state; flops; resettable)
  ftb_cntrl (read, branch-type classify, way-match using ftb_plru
             valid AND ftb_array tag, block-boundary and fallthrough
             compute, allocate/evict incl. PLRU victim and next-state,
             valid set/clear, update field writes, conf bimodal
             direction + fast-path)

See ftb_decisions.md section 2.4. The top is structural only. The two
storage modules are discrete so a 1R1W SRAM macro can replace ftb_array
without touching ftb_cntrl, and so all resettable state (valid, PLRU)
lives in flops in ftb_plru. ftb_cntrl is the only logic. PLRU victim
selection, next-state compute, and way-match live in ftb_cntrl, not in
the storage modules (IC-FTB-12).

---

## 2. ftb Top Ports

### 2.1 Clock and reset

  clk               -- rising-edge clock
  rstn              -- active-low synchronous reset (to ftb_plru and
                       ftb_cntrl; ftb_array has no reset)

### 2.2 Prediction request (p0 in, registered p1)

  input  logic                  pred_valid_p0
                        -- 1 = prediction request valid this cycle.
  input  logic [VA_WIDTH-1:0]   pred_pc_p0
                        -- block start PC. One PC. The single entry
                           covers the 32-byte block from this PC. No
                           slot-1 PC; FTB is not slot-split.

bp_cluster owns pipeline advance (p0 -> p1 -> p2). FTB registers the
request internally; outputs in 2.3 are valid at p2.

### 2.3 Prediction outputs (to bp_cluster override logic, at p2)

One entry's worth of outputs. br0 and br1 are the two conditional
fields of the one indexed entry, not two slots.

  output logic                  ftb_valid_p2
                        -- 1 = FTB tag hit for this block.

  -- carried for update (writeWay scheme, IC-FTB-10)
  output logic                  ftb_hit_p2
                        -- 1 = tag hit, 0 = miss. Carried through the
                           FTQ to the update port as ftb_upd_hit_u0.
  output logic [FTB_WAY_BITS-1:0] ftb_way_p2
                        -- predicted writeWay: the hit way on a hit,
                           or the tree-PLRU victim way on a miss.
                           Carried through the FTQ as ftb_upd_way_u0.

  -- conditional branch 0
  output logic                  ftb_br0_valid_p2
                        -- 1 = conditional field 0 is occupied.
  output logic [FTB_BR_POS_BITS-1:0] ftb_br0_pos_p2
                        -- br0 in-block position: which 2-BYTE SLOT
                           (0..15) within the 32-byte block this
                           branch occupies, counted from the BLOCK
                           START. ftb_cntrl stores it region-relative
                           and converts at the read, suppressing a
                           field outside this block's window
                           (ftb_decisions.md 4.6, session-071).
                           Used by the cluster/FTQ
                           to locate the taken branch in the bundle.
                           NOT to order br0 against br1 -- br0 is
                           always the earlier branch by fill order
                           (IC-FTB-16, ftb_decisions.md 4).
                           Written at allocate/free-field from
                           ftb_upd_pos_u0 (2.5); static for the life
                           of the field.
                           This entry read "which expanded-
                           instruction slot" and "order br0 vs br1".
                           BP-099 took positions to 2-byte
                           granularity and retired the
                           expanded-instruction model
                           (ftb_decisions.md 4.4 and 11).
                           Session-070.
  output logic                  ftb_br0_taken_p2
                        -- FTB direction for br0 = conf MSB, qualified
                           by valid: ftb_br0_taken_p2 =
                           ftb_br0_valid_p2 & conf_br0[MSB]. 1 = taken.
  output logic [FTB_CONF_WIDTH-1:0] ftb_br0_conf_p2
                        -- br0 bimodal direction counter value (MSB =
                           direction). Exposed for the cluster and for
                           observability.
  output logic [VA_WIDTH-1:0]   ftb_br0_target_p2
                        -- br0 taken target, reconstructed full width
                           by ftb_cntrl from the stored displacement
                           (4.2). Valid only when br0 taken.

  -- conditional branch 1 (same fields as br0)
  output logic                  ftb_br1_valid_p2
  output logic [FTB_BR_POS_BITS-1:0] ftb_br1_pos_p2
  output logic                  ftb_br1_taken_p2
  output logic [FTB_CONF_WIDTH-1:0] ftb_br1_conf_p2
  output logic [VA_WIDTH-1:0]   ftb_br1_target_p2

  (No ftb_brI_always_taken_p2 -- the always_taken bit was removed,
   session-053; conf is the sole per-branch direction state.)

  -- jump field (terminal: uncond jump / call / return)
  output logic                  ftb_jmp_valid_p2
                        -- 1 = jump field occupied.
  output logic [FTB_BR_POS_BITS-1:0] ftb_jmp_pos_p2
                        -- jump in-block position (0..15), same meaning
                           as the conditional positions. Written at
                           allocate from ftb_upd_pos_u0 (2.5).
  output logic [VA_WIDTH-1:0]   ftb_jmp_target_p2
                        -- jump target, reconstructed full width by
                           ftb_cntrl from the stored 21-bit
                           displacement + status (FTB_JMP_TGT_BITS).
                           Architectural fallback for ITTAGE miss (no
                           IT0 base table) and RAS empty. Always
                           current regardless of whether ITTAGE or RAS
                           normally supplies the runtime target
                           (IC-FTB-01).
  output logic                  ftb_is_call_p2
  output logic                  ftb_is_ret_p2
  output logic                  ftb_is_jalr_p2
                        -- jump type for this block. Gates JALR
                           ownership, RAS or ITTAGE, resolved by FTB
                           before p2 (ftb_decisions.md section 1).
                           The FTB is not a third arm: its target is
                           the ITTAGE-miss fallback, section 4.2.
                           An earlier revision said "three-way JALR
                           split (FTB / RAS / ITTAGE)".

  -- fallthrough (block end)
  output logic [VA_WIDTH-1:0]   ftb_pft_addr_p2
                        -- predicted fallthrough address, full width,
                           reconstructed by ftb_cntrl from the stored
                           partial pftAddr -- six bits from the
                           aligned region base, NO CARRY BIT
                           (ftb_decisions.md 5.5, ruled session-070,
                           BUILT by BP-110). Bounds checked per
                           ftb_decisions.md 4.5: an end not above
                           the start (FTB-G1), or beyond start +
                           FTB_BLOCK_BYTES + 2 (FTB-G3, ruled
                           session-073), is replaced by start +
                           FTB_BLOCK_BYTES. BOTH CHECKS ARE BUILT
                           by BP-110; before it ftb_cntrl
                           reconstructed unconditionally, so this
                           entry's earlier "AS BUILT" note was
                           correct and the restoration recorded in
                           session-069 had never reached the RTL.
                           The uBTB does NOT have this check; see
                           ubtb_interfaces.md.
                           Authoritative for the cluster; RAS push
                           uses this value (IC-FTB-03).

### 2.4 Fast-path (direction bypass) (to override logic, p2)

  input  logic                  ftb_fastpath_en
                        -- 1 = fast-path enabled; a saturated conf may
                           bypass the TAGE/SC direction wait/override.
                           0 = disabled, FTB is always overridable
                           (ordinary BTB). Source TBD at bp_cluster
                           (confidence doc section 10). Renamed from the
                           former chicken_bit_enable (inverse sense:
                           1 enables the optimization).
  output logic [1:0]            ftb_fastpath_p2
                        -- bit 0 = br0, bit 1 = br1.
                           1 = FTB commits its direction for that branch
                           and the cluster must NOT apply a TAGE/SC
                           DIRECTION override and must not stall for SC
                           (saves the p3 SC cycle). Asserted when
                           ftb_fastpath_en AND conf saturated (111 or
                           000) AND ftb_valid_p2 AND the matching
                           ftb_brI_valid_p2 (IC-FTB-02). Target
                           overrides (ITTAGE/RAS) are never affected.
                           Full policy in
                           ftb_confidence_override_rules.md. (Renamed
                           from ftb_suppress_dir_p2.)

### 2.5 Update port (from FTQ, post-execute)

ONE update port. FTB does not arbitrate or serialize multi-branch
updates; the FTQ routes and serializes onto this single port (F20,
IC-FTB-05).

  input  logic                  ftb_upd_valid_u0
                        -- 1 = update active this cycle.
  input  logic [VA_WIDTH-1:0]   ftb_upd_pc_u0
                        -- block start PC of the entry being updated.
  input  logic                  ftb_upd_hit_u0
                        -- carried from the prediction read: 1 = this
                           block hit in FTB at predict time. Guides
                           the write: overwrite the carried way on a
                           hit, allocate the carried victim on a miss.
  input  logic [FTB_WAY_BITS-1:0] ftb_upd_way_u0
                        -- carried writeWay from the prediction read.
                           ftb_cntrl does NOT re-look-up the tag
                           (IC-FTB-10).

  -- conditional-branch resolve
  input  logic                  ftb_upd_is_br_u0
                        -- 1 = this resolve is a conditional branch.
  input  logic                  ftb_upd_br_idx_u0
                        -- which conditional PORT SLOT, 0 or 1, as
                           the update's own block start saw it.
                           RATIFIED session-073: it names a slot,
                           not a storage field. Under the O-3b read
                           compaction the FTQ only ever sees port
                           slots, so this is the only reading under
                           which the producer needs no knowledge of
                           the region window. ftb_cntrl maps the
                           slot back to a storage field through the
                           same window: a slot mapping to a visible
                           field is an in-place update; otherwise
                           the branch fills an empty field, else a
                           field hidden from this start. For an
                           aligned start with nothing hidden the
                           mapping is the identity. Built by
                           BP-110.
  input  logic                  ftb_upd_taken_u0
                        -- resolved direction. 1 = taken. Drives the
                           bimodal conf step (increment toward 111 on
                           taken, decrement toward 000 on not-taken,
                           saturating) and, at allocate, the weak conf
                           init direction (ftb_decisions.md 5.4/5.5).
  input  logic [VA_WIDTH-1:0]   ftb_upd_target_u0
                        -- resolved taken target, full width.
                           ftb_cntrl converts to the stored
                           displacement form for conditional storage
                           (4.2).
  input  logic [FTB_BR_POS_BITS-1:0] ftb_upd_pos_u0
                        -- in-block position of the resolving branch
                           (0..15), = (branch_pc - block_start) >>
                           POS_OFFSET_BITS, supplied by the FTQ/resolve
                           side. START-relative; ftb_cntrl adds the
                           update PC's region offset before storing
                           it (ftb_decisions.md 4.6 R-2). Written to
                           the selected field's pos at
                           allocate / free-field fill (the conditional
                           chosen by ftb_upd_br_idx_u0, or the jump when
                           ftb_upd_is_jmp_u0). Static for the life of a
                           filled field; not rewritten on an in-place
                           conf/target update (ftb_decisions.md 5.4/5.5).

  (No ftb_upd_ftb_dir_u0 -- conf trains bimodally on the resolved
   OUTCOME, not on FTB-prediction correctness, so FTB's original
   direction is not needed on the update port. Removed session-053.)

  -- jump resolve
  input  logic                  ftb_upd_is_jmp_u0
                        -- 1 = this resolve is a jump (call/ret/jalr).
  input  logic [VA_WIDTH-1:0]   ftb_upd_jmp_target_u0
                        -- resolved jump target, full width. Written
                           to the jump field unconditionally on every
                           jump resolve (IC-FTB-01).
  input  logic                  ftb_upd_is_call_u0
  input  logic                  ftb_upd_is_ret_u0
  input  logic                  ftb_upd_is_jalr_u0

  -- block boundary
  input  logic [VA_WIDTH-1:0]   ftb_upd_pft_addr_u0
                        -- resolved block end (fallthrough), full
                           width. ftb_cntrl reduces it to the stored
                           partial pftAddr at the write -- relative
                           to the ALIGNED REGION BASE, not the block
                           start, six bits, no carry
                           (ftb_decisions.md 5.4/5.5, TD#124).

There is no last_may_be_rvi_call port. The bit was eliminated
(ftb_decisions.md section 6).

### 2.6 Flush input

  input  logic                  ftb_flush_px
                        -- flush. REDUNDANT, and retained rather
                           than removed. A flush is a redirect
                           (fe_decisions.md FE-14); the FTB is
                           cleared by withholding its stage valid,
                           which bp_cluster already does. The port
                           is not driven. ftb_cntrl.sv gates the
                           combinational prediction outputs while
                           it is asserted; that behaviour is
                           RATIFIED as harmless and is not a flush
                           protocol. Update-queue drain is owned by
                           the FTQ and is not a flush question.

---

## 3. ftb_array Module Ports

One instance. Single 1R1W DATA array. Read port for prediction, write
port for update, independent read and write addresses usable in the
same cycle. ftb_array holds NO entry-valid bit and NO PLRU state --
those live in ftb_plru. It is pure data RAM so a 1R1W SRAM macro can
substitute it directly. Enables are ACTIVE LOW (IC-FTB-13).

  clk               -- rising-edge clock

  -- read port (prediction)
  rd_en_n           -- active low; 0 = read this cycle
  rd_addr           -- [FTB_IDX_BITS-1:0]    set index
  rd_data           -- [FTB_RAM_SET_WIDTH-1:0] all ways of the set
                       (data only, no valid); way match and select in
                       ftb_cntrl, qualified by ftb_plru valid

  -- write port (update / allocate)
  wr_en_n           -- active low; 0 = write this cycle
  wr_addr           -- [FTB_IDX_BITS-1:0]    set index
  wr_way            -- [FTB_WAYS-1:0]        one-hot way select
  wr_data           -- [FTB_RAM_ENTRY_WIDTH-1:0] one way's entry data
                       (no entry-valid; that is set in ftb_plru)

There is NO clk reset of the data array (pure SRAM-style storage). Cold
validity is owned entirely by ftb_plru (IC-FTB-12). Do not rely on
array power-up contents.

  FTB_RAM_SET_WIDTH   = FTB_WAYS * FTB_RAM_ENTRY_WIDTH
  FTB_RAM_ENTRY_WIDTH = FTB_ENTRY_WIDTH - 1 (the relocated entry-valid
                        lives in ftb_plru)

THE ARITHMETIC IS NOT RESTATED HERE. ftb_decisions.md 8 is its sole
home and says so. This block carried a full field-by-field sum with
FTB_RAM_ENTRY_WIDTH = 105, a 106-bit logical entry,
FTB_RAM_SET_WIDTH = 420, FTB_BR_POS_BITS = 3 and PFTADDR_BITS = 4
plus a carry bit. Every one of those was stale: BP-099 took
FTB_BR_POS_BITS to 4 and the entry to 110 / 109 / 440 / 436, and
session-070 took PFTADDR_BITS to 6 and deleted the carry (TD#124).
Restating it here is how it went stale, so it is now a pointer.
Removed session-070.

Way-slice packing: way w occupies rd_data/wr_data
[w*FTB_RAM_ENTRY_WIDTH +: FTB_RAM_ENTRY_WIDTH]; wr_way[w] selects
way w. ftb_cntrl uses the same convention.

Same-cycle read and write to the same set/way: the read returns the
OLD value (F19, IC-FTB-14). Substitution invariant: any 1R1W array
primitive (register file or SRAM macro) may replace ftb_array without
changing ftb_cntrl port connections.

---

## 3a. ftb_plru Module Ports

One instance. Flop storage, parallel to ftb_array. Holds, per set, the
FTB_WAYS entry-valid bits and the PLRU_BITS tree-PLRU state. Storage
only: ftb_plru does NOT compute the victim, the next PLRU state, or the
way-match -- those are in ftb_cntrl (IC-FTB-12). Enables ACTIVE LOW
(IC-FTB-13). Reset clears all entry-valid bits; this is the FTB cold
init -- there is no sram_init for the FTB.

  clk               -- rising-edge clock
  rstn              -- active-low reset; clears all entry-valid bits to
                       0 and resets all PLRU state to 0

  -- read port (prediction; combinational)
  rd_en_n           -- active low; 0 = read this cycle
  rd_addr           -- [FTB_IDX_BITS-1:0]    set index
  rd_valid          -- [FTB_WAYS-1:0]        per-way entry-valid for the
                       set (ftb_cntrl ANDs with tag-match for the hit)
  rd_plru           -- [PLRU_BITS-1:0]       tree-PLRU state for the set

  -- valid write port (synchronous): set or clear one way's valid
  val_we_n          -- active low; 0 = valid write this cycle
  val_addr          -- [FTB_IDX_BITS-1:0]    set index
  val_way           -- [FTB_WAYS-1:0]        one-hot way (mirrors
                       ftb_array wr_way)
  val_set           -- 1 = set the selected way's valid (allocate);
                       0 = clear it. Reserved. NOT a flush
                       mechanism: there is no flush event
                       (fe_decisions.md FE-14, IC-FTB-07 closed).
                       Retained for invalidate-on-allocate use.

  -- PLRU write port (synchronous): replace a set's tree-PLRU state
  plru_we_n         -- active low; 0 = PLRU write this cycle
  plru_addr         -- [FTB_IDX_BITS-1:0]    set index
  plru_wdata        -- [PLRU_BITS-1:0]       next PLRU state, computed
                       by ftb_cntrl

Same-cycle read vs same-set valid/PLRU write returns the OLD value, so
the prediction read of ftb_array and ftb_plru together yields a
coherent pre-update snapshot of the set (IC-FTB-14).

  Per-set storage: FTB_WAYS valid bits + PLRU_BITS = (4 + 3) = 7 bits.
  Total flops: FTB_SETS * 7 = 512 * 7 = 3584.

---

## 4. Interface Invariants

IC-FTB-01:
  ftb_jmp_target_p2 reflects the most recently resolved target for the
  jump in this block, regardless of whether ITTAGE or RAS normally
  owns that branch type. The update write is unconditional on every
  jump resolve; it is NOT gated on an ITTAGE miss (ftb_decisions.md
  4.2 / 5.5). This is the override-chain "...else FTB jump target"
  floor.

IC-FTB-02:
  ftb_fastpath_p2[i] is valid only when ftb_valid_p2 is asserted and
  the matching ftb_brI_valid_p2 is asserted. Do not sample the
  fast-path on an FTB miss or an empty conditional field.

IC-FTB-03:
  ftb_pft_addr_p2 is the authoritative fallthrough for the cluster.
  RAS uses this value as the pushed return address (ras_fall_through).
  No straddle correction is applied. The value is BOUNDS CHECKED
  (ftb_decisions.md 4.5, FTB-G1, FTB-G2), as ubtb_interfaces.md
  applies to blk_p1. As built, ftb_cntrl.sv line 500 reconstructs
  unconditionally, TD#124. This entry recorded the check as "A
  CONFLICT, NOT A SETTLED ABSENCE" (session-070); 4.5 is the
  authority, so it is the specification and the RTL is the
  divergence. Session-071.

IC-FTB-04:
  br0 and br1 are the two conditional fields of one entry from one
  lookup. FTB does not produce a second, separately-indexed
  prediction. There is no slot-1 lookup and no slot-1 output.

IC-FTB-05:
  The FTQ owns update scheduling. FTB exposes one update port and does
  not serialize or arbitrate multi-branch updates internally (F20).

IC-FTB-06 (session-053):
  conf allocate-init invariant. FTB_CONF_INIT_TKN and FTB_CONF_INIT_NTK
  must both be UNSATURATED (TKN != all-ones, NTK != all-zeros) with the
  MSB matching their direction (TKN MSB=1, NTK MSB=0), so a freshly
  allocated entry cannot fast-path on first use. Assert in ftb_cntrl
  and tb_ftb. (Replaces the former INIT < SUPPRESS_THRESH invariant;
  there is no threshold.)

IC-FTB-07 (CLOSED, BP-105):
  Flush protocol (ftb_flush_px). CLOSED BY DECISION, not by writing a
  protocol: there is no flush event to define. A flush is a redirect
  (fe_decisions.md FE-14). The port is redundant and retained.

  This item previously read "Do not implement flush logic until
  specified" while ftb_cntrl.sv already gated prediction outputs on
  ftb_flush_px. The document and the tree disagreed. Resolved by
  RATIFYING the existing gate: it is harmless, the port is never
  driven, and removing it would touch a green module for no gain.

IC-FTB-08 (resolved, session-052; reconciled session-053):
  Field widths are ruled in ftb_decisions.md 8 and are NOT restated
  here. This block gave FTB_BR_POS_BITS = 3, FTB_RAM_ENTRY_WIDTH =
  105 and FTB_RAM_SET_WIDTH = 420, all stale since BP-099. The
  current values are in ftb_decisions.md 8 only. Corrected
  session-070 by removing the copy; session-071 removed the "110 /
  109 / 440 / 436" this entry still restated, stale once the
  stored positions widened.

IC-FTB-09 (resolved, 2026-08-19):
  G9 update channel arbitration. Multi-branch update scheduling onto
  the single FTB update port is an FTQ concern and is
  ftq_decisions.md 5.7. This item was OPEN, not decided: the single
  port was never analysed against a target update rate.

  The analysis: at the 8-issue target, with 15 to 20 percent branch
  density, 1.2 to 1.6 branches resolve per cycle in steady state and
  every one writes the FTB (5.5 steps conf on every resolve). One
  write per cycle is below the target rate, and under FE-5 as
  originally written the deficit backpressured resolution and stalled
  the backend -- a training limit becoming a throughput limit.

  The resolution: the FTQ schedules onto the port with a one-deep
  skid and MAY DROP an update, but only a LOW-value one, meaning the
  FTB hit at predict and the branch was predicted correctly. An
  update that allocates an entry (predict-time miss) or corrects a
  mispredict is never dropped; if accepting one would force such a
  drop the FTQ backpressures instead. FE-5 is amended to match, and
  only for this path.

  The FTB itself is UNCHANGED. No second write port, no banking, no
  wider payload. Two escalations are recorded in ftq_decisions.md
  5.7.5 should measurement ever show the drop rate matters: merging
  two same-entry updates into one ftb_array write, which needs no
  extra port, and banking ftb_array by index.

  (This item also covered the prediction-vs-update read port sharing
  surfaced in BP-066; that half is unaffected.)

IC-FTB-10 (resolved, session-052):
  Update-side way selection. ftb_cntrl does NOT re-look-up the tag on
  update. The predicted way (writeWay) and the hit result are
  determined at the prediction read (ftb_way_p2 / ftb_hit_p2) and
  carried through the FTQ on ftb_upd_way_u0 / ftb_upd_hit_u0. On a
  carried hit, overwrite the carried way; on a carried miss, allocate
  the carried tree-PLRU victim. A carried victim may go stale if
  another write hits the same set between read and update; tolerated
  (prediction accuracy, never correctness). A direct carried-way READ
  of the entry for the conf/target read-modify-write is still required
  and permitted -- IC-FTB-10 forbids the associative re-lookup, not the
  carried-way read.

IC-FTB-11 (resolved session-052, REOPENED session-070):
  Fallthrough reconstruction error. Ruled OUT in session-052 because
  the full 26-bit tag made wrong-entry hits unreachable. TWO THINGS
  HAVE CHANGED. ftb_decisions.md 4.5 restored a bounds check in
  session-069 (FTB-G1, FTB-G2) because blocks are unaligned and two
  lookup PCs in one 32-byte region share an entry, which is not a
  wrong-entry hit. And the tag is now PINNED at 26 over a 41-bit VA
  (4.1, TD#122), so it no longer covers the whole upper VA.
  RESOLVED AS SPECIFIED session-071: the reconstruction is bounds
  checked per ftb_decisions.md 4.5 (FTB-G1, FTB-G2), with the
  start + FTB_BLOCK_BYTES fallback. As built there is still no
  fallback mux and ftb_cntrl.sv line 500 reconstructs
  unconditionally; TD#124 tracks the divergence. An upper bound
  is open, ftb_decisions.md 4.6 O-2.

IC-FTB-12 (session-053):
  Storage split. ftb_array is pure 1R1W DATA RAM: no entry-valid, no
  PLRU state, no compute. The entry-valid bits and the tree-PLRU state
  live in ftb_plru, in resettable flops. Reset clears the valid bits;
  this is the FTB cold init -- the FTB has NO sram_init mechanism.
  Way-match, PLRU victim selection, PLRU next-state, and valid set/clear
  are all computed in ftb_cntrl, which drives both storage modules. The
  logical entry is partitioned: 1 valid bit/way in ftb_plru, the
  FTB_RAM_ENTRY_WIDTH bits in ftb_array. This carried the number,
  which read 105 until session-070 and 109 until session-071;
  ftb_decisions.md 8 is the authority and is no longer copied here.
  Session-072.

IC-FTB-13 (session-053):
  Active-low controls. All enables on ftb_array and ftb_plru are active
  low (rd_en_n, wr_en_n, val_we_n, plru_we_n), matching the BPU array
  convention. Reset is rstn (active low). ftb_array has no reset (pure
  RAM); ftb_plru reset clears valid + PLRU state.

IC-FTB-14 (session-053):
  Coherent snapshot on collision. Both storage modules return the OLD
  contents on a same-cycle read vs same-set write (F19 extended to
  ftb_plru). A prediction that reads a set in the same cycle an update
  writes that set sees a coherent pre-update view of both the data
  (ftb_array) and the validity/replacement state (ftb_plru).

IC-FTB-15 (session-053, FTB-4 resolved):
  In-block position is sourced and sunk. Each stored position field
  (br0, br1, jump; FTB_BR_RPOS_BITS each, stored region-relative,
  ftb_decisions.md 4.6) has a producer and a consumer:
  written from ftb_upd_pos_u0 (2.5) at allocate / free-field fill,
  routed to the field selected by ftb_upd_br_idx_u0 or ftb_upd_is_jmp_u0;
  read out on ftb_br0_pos_p2 / ftb_br1_pos_p2 / ftb_jmp_pos_p2 (2.3).
  Position is static for the life of a filled field -- not rewritten on
  an in-place conf/target update; reset only by reallocation. No stored
  field may be left write-only (0-stuffed) or read-only: a field is not
  "settled" until it has a named producer and consumer.

IC-FTB-16 (2026-08-19, amended session-073):
  br0 holds the earlier branch. STORAGE IS IN ASCENDING REGION
  POSITION (ftb_decisions.md 4.6 O-3a): br0 holds the lower stored
  position and br1 the higher, whatever start wrote them. A start
  that fills one conditional into an empty entry fills br0.

  THE FTB REORDERS AND CHECKS. This invariant previously made the
  FTQ responsible and said the FTB did neither; O-3 moved both
  inside ftb_cntrl, which swaps storage into ascending order at the
  write and compacts the window-surviving fields onto the ports at
  the read (O-3b). Built by BP-110.

  ON THE PORTS, program order is per START. Under the read window of
  ftb_decisions.md 4.6 br0 can be suppressed while br1 is visible;
  compaction then reports br1 on PORT SLOT 0, so slot 0 is always
  the first branch at or after the looked-up start. "br0 maps to
  slot 0" holds only when br0 is visible. In storage program order
  is per REGION.

  ftb_upd_br_idx_u0 (2.5) names a port slot in the same terms.

  Two consequences follow.

  The prediction slot array becomes program-ordered. br0 maps to slot
  0 and br1 to slot 1 (ftq_bpu_interfaces.md 5.1), so slot 0 is the
  first branch of the block and slot 1 the second. fe_decisions.md
  FE-10 already states that the slot is the array index and carries no
  identifier; it is now an ORDERED index.

  The jump field's lowest-free-slot placement is program order in
  every case, not merely the common one. A jump terminates the block,
  so no conditional follows it; and because conditionals fill from br0
  upward, the free slot the jump takes is always above every filled
  conditional slot. Without this invariant a block whose only
  conditional sat in br1 would place the jump in slot 0, ahead of an
  earlier branch.

  Position is still required. It locates the branch in the fetch
  bundle (IC-FTB-15), forms the branch PC reported to bp_history
  (BP-092a), and is the key the backend returns at resolution
  (ftq_backend_interfaces.md 4). This invariant removes its ORDERING
  role, not the field.

---

## 5. Parameters

All from bp_defines_pkg.sv. THE VALUES ARE NOT RESTATED HERE:
ftb_decisions.md 8 and 8.1 are their sole home, as section 3's
arithmetic-not-restated block and IC-FTB-08 in section 4 both say. The names this interface uses:

  VA_WIDTH, FTB_WAYS, FTB_ENTRIES, FTB_SETS, FTB_IDX_BITS,
  FTB_WAY_BITS, FTB_BLOCK_BYTES, FTB_OFFSET_BITS, FTB_TAG_BITS,
  PLRU_BITS, PFTADDR_BITS, TAR_STAT_BITS, FTB_BR_POS_BITS
  (the width of every position PORT, start-relative),
  FTB_BR_RPOS_BITS (the STORED position, region-relative),
  FTB_BR_TGT_BITS, FTB_JMP_TGT_BITS, FTB_CONF_WIDTH,
  FTB_CONF_INIT_TKN, FTB_CONF_INIT_NTK, and the entry arithmetic
  FTB_ENTRY_WIDTH / FTB_SET_WIDTH (logical, including the valid bit)
  and FTB_RAM_ENTRY_WIDTH / FTB_RAM_SET_WIDTH (the ftb_array data).

  Invariant: both conf init values unsaturated, MSB matches
  direction (IC-FTB-06). There is no FTB_CONF_SUPPRESS_THRESH.

This section carried every value and the entry arithmetic, against
the rule the file states about itself twice. The copies agreed with
ftb_decisions.md 8 at the time they were removed, having been stale
at 105 / 420 until session-070 and at 109 / 436 until session-071 --
which is the argument for not keeping them. Session-072.

ftb_array uses the FTB_RAM_* widths; ftb_plru holds the valid bit per
way and the PLRU state. All FTB field widths are settled.
IC-FTB-07, the flush protocol, is CLOSED by decision -- no flush
event exists, FE-14. IC-FTB-09, update-channel arbitration, is
resolved by ftq_decisions.md 5.7 and built as ftq_ftb_sched
(BP-100).

FETCH_BLOCK_BYTES = 64 is a global / fetch-unit parameter, already in
the package. It is NOT an FTB parameter. The FTB prediction block is
FTB_BLOCK_BYTES (32), decoupled from the fetch block, the 64-byte
L1I line the IFU reads, by the FTQ. Do not collapse the two
(ftb_decisions.md 2.3; this read "fetch width", session-071).

---

## 6. Interactions With Other Planning Documents

  ftb_decisions.md    -- canonical FTB authority. This file is
                         subordinate to it.
  ftb_confidence_override_rules.md
                      -- conf as a bimodal direction counter, bimodal
                         training, the saturated-endpoint fast-path,
                         ftb_fastpath_en, init/self-correction.
  bp_cluster.md       -- pipeline staging, override chain, FTQ entry
                         contents, decoupled frontend, pipeline advance,
                         update-channel arbitration, keeping TAGE/SC
                         trained under the FTB fast-path (FTB-2).
  ras_decisions.md    -- RAS consumes ftb_pft_addr_p2 as the pushed
                         return address; ftb_jmp_target_p2 is the
                         RAS-empty fallback.
  ittage              -- ftb_jmp_target_p2 is the ITTAGE-miss fallback
                         (ITTAGE has no IT0 base table).
  bp_defines_pkg.sv   -- all FTB parameters in section 5.

---

## 7. Document History

  2026-06-24  session-052. Regenerated from ftb_decisions.md (single
              array, single update port, VA_WIDTH=40, FTB_TAG_BITS=26,
              expanded-instruction granularity, partial pftAddr).

  2026-06-24  session-052 (later/widths passes). IC-FTB-10 (writeWay
              carry) and IC-FTB-11 (fallThroughErr out) resolved.
              IC-FTB-08 widths ruled; ENTRY_WIDTH 108 / SET_WIDTH 432.

  2026-06-25  session-053 (storage split). Hierarchy to three modules
              (ftb_array data RAM, ftb_plru valid+PLRU flops, ftb_cntrl
              logic). Section 3 ftb_array reduced to pure data RAM with
              active-low enables; section 3a ftb_plru added. IC-FTB-12/
              13/14 added. Storage-module enables active low. Stale
              "FTB_WAYS currently 8" annotation removed.

  2026-06-25  session-053 (confidence redefine). conf is a bimodal
              DIRECTION counter (MSB = direction); ftb_brI_taken_p2 =
              valid & conf MSB. always_taken removed: conditional field
              22 bits, FTB_RAM_ENTRY_WIDTH 107 -> 105, FTB_RAM_SET_WIDTH
              428 -> 420, logical entry 108 -> 106; IC-FTB-08 reconciled.
              ftb_brI_always_taken_p2 output removed. Suppression-
              threshold mechanism replaced by the saturated-endpoint
              fast-path: ftb_suppress_dir_p2 renamed ftb_fastpath_p2;
              chicken_bit_enable input renamed ftb_fastpath_en (now a
              listed top input). ftb_upd_ftb_dir_u0 update input removed
              (conf trains bimodally on ftb_upd_taken_u0). IC-FTB-06
              repurposed to the conf init-unsaturated invariant
              (FTB_CONF_INIT_TKN/NTK; FTB_CONF_SUPPRESS_THRESH removed).
              IC-FTB-10 clarified: carried-way read for the conf/target
              RMW is permitted (only the associative re-lookup is
              barred). IC-FTB-09 extended to cover the pred-vs-update
              read-port sharing surfaced in BP-066.

  2026-06-25  session-053 (position fix, FTB-4). The in-block position
              field (FTB_BR_POS_BITS per branch) was stored but had no
              producer or consumer (BP-066 stored it as 0). Added
              ftb_upd_pos_u0 (2.5) as the producer and ftb_br0_pos_p2 /
              ftb_br1_pos_p2 / ftb_jmp_pos_p2 (2.3) as the consumers;
              IC-FTB-15 added (every stored field must have a named
              producer and consumer). No width change -- pos already
              occupied bits in the 105-bit entry. RTL wired in BP-066b.

  2026-09-19  session-071. Positions on every port are
              start-relative; ftb_cntrl stores them region-relative
              at FTB_BR_RPOS_BITS = 5 and applies a read window
              (ftb_decisions.md 4.6, ruled, option R). IC-FTB-15
              and IC-FTB-16 note the stored form and the open slot
              mapping question. Section 5: FTB_BR_RPOS_BITS added,
              entry 110 -> 113. TD#125 tracks the RTL.

  2026-09-20  session-072. D5: the local stage-notation rule replaced
              by PROJECT_CORE's.

  2026-09-20  session-072. D5: the s-stage section heads and timing
              text swept to p-stage.

  2026-09-20  session-072. D13: section 5 and IC-FTB-12 no longer
              restate the field widths or the entry arithmetic;
              ftb_decisions.md 8 is the sole home, as section 3's
              arithmetic-not-restated block and IC-FTB-08 already
              said. Both citations read "3.4", a section this file
              does not have; session-072.

  2026-09-20  session-072. E4: UPDATED brought to the session date.
