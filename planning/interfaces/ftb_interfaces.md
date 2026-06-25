<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTB Interface Contracts
```
 FILE:    planning/interfaces/ftb_interfaces.md
 SOURCE:  ftb_decisions.md (canonical), session-051/052/053
 STATUS:  DRAFT
 UPDATED: 2026-06-25
 CONTACT: Jeff Nye
```

Interface contract for the FTB module. Derived from ftb_decisions.md,
which is the canonical authority. Where this file and ftb_decisions.md
disagree, ftb_decisions.md wins and this file is wrong.

Conventions:
  - Stage notation: planning narrative uses s-stage (s0/s1/s2/s3).
    Port names use p-stage (p0/p1/p2) for prediction, u0 for update,
    px for flush. s-stage and p-stage are equivalent.
  - FTB is a SINGLE data array, one lookup per cycle, one entry per
    block. There are NO per-slot RAMs and NO NUM_PRED_SLOTS unpacking
    on FTB ports. The cluster's two branches per cycle are br0 and br1
    of the one indexed entry (ftb_decisions.md 2.1).
  - The G8/G17 pred_pc+32 bundle split and TI6 per-slot RAMs are
    TAGE/ITTAGE conventions. They do NOT apply to FTB.
  - Active-low reset: rstn. Rising-edge clock: clk. Storage-module
    enables are active low (IC-FTB-13).
  - VA_WIDTH = 40. All full-width addresses are [VA_WIDTH-1:0].
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

### 2.2 Prediction request (s0 in, registered s1)

  input  logic                  pred_valid_p0
                        -- 1 = prediction request valid this cycle.
  input  logic [VA_WIDTH-1:0]   pred_pc_p0
                        -- block start PC. One PC. The single entry
                           covers the 32-byte block from this PC. No
                           slot-1 PC; FTB is not slot-split.

bp_cluster owns pipeline advance (s0 -> s1 -> s2). FTB registers the
request internally; outputs in 2.3 are valid at s2.

### 2.3 Prediction outputs (to bp_cluster override logic, at s2)

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
                        -- br0 in-block position: which expanded-
                           instruction slot (0..7) within the 32-byte
                           block this branch occupies. Needed by the
                           cluster/FTQ to order br0 vs br1 and locate
                           the taken branch in the bundle. Written at
                           allocate/free-field from ftb_upd_pos_u0
                           (2.5); static for the life of the field.
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
                        -- jump in-block position (0..7), same meaning
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
                        -- jump type for this block. Gates the
                           three-way JALR split (FTB / RAS / ITTAGE)
                           resolved by FTB before s2 (ftb_decisions.md
                           section 1).

  -- fallthrough (block end)
  output logic [VA_WIDTH-1:0]   ftb_pft_addr_p2
                        -- predicted fallthrough address, full width,
                           reconstructed by ftb_cntrl from the stored
                           partial pftAddr + carry. Reconstructed
                           UNCONDITIONALLY; there is no fallthrough
                           error check (ftb_decisions.md 4.5).
                           Authoritative for the cluster; RAS push
                           uses this value (IC-FTB-03).

### 2.4 Fast-path (direction bypass) (to override logic, s2)

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
                           (saves the s3 SC cycle). Asserted when
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
                        -- which conditional field, 0 or 1.
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
                           (0..7), = (branch_pc - block_start) >>
                           INST_OFFSET, supplied by the FTQ/resolve
                           side. Written to the selected field's pos at
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
                           partial pftAddr + carry at the write
                           (ftb_decisions.md 5.4/5.5).

There is no last_may_be_rvi_call port. The bit was eliminated
(ftb_decisions.md section 6).

### 2.6 Flush input

  input  logic                  ftb_flush_px
                        -- flush. Protocol TBD at bp_cluster
                           integration (IC-FTB-07). On flush,
                           prediction outputs clear. Update-queue
                           drain behavior is owned by the FTQ.

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

  FTB_RAM_SET_WIDTH   = FTB_WAYS * FTB_RAM_ENTRY_WIDTH   (= 420)

  FTB_RAM_ENTRY_WIDTH per way = 105 bits (the 106-bit logical entry
  minus the relocated entry-valid):
                  FTB_TAG_BITS            tag                  (26)
                + 2 * (                   br0 + br1 = 44:
                        1                   field valid
                      + FTB_BR_POS_BITS     in-block position    (3)
                      + FTB_BR_TGT_BITS     target displacement  (13)
                      + TAR_STAT_BITS       fit/ovf/udf          (2)
                      + FTB_CONF_WIDTH )    conf (bimodal dir)   (3)
                + 1                       jump valid
                + FTB_BR_POS_BITS         jump in-block position (3)
                + FTB_JMP_TGT_BITS        jump target displ.     (21)
                + TAR_STAT_BITS           jump fit/ovf/udf       (2)
                + 3                       isCall / isRet / isJalr
                + PFTADDR_BITS            partial fallthrough    (4)
                + 1                       carry

  Each conditional field is 22 bits (no always_taken). 26 + 2*22 + 30 +
  4 + 1 = 105.

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
                       0 = clear it (reserved for flush, deferred,
                       IC-FTB-07)

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
  No straddle correction and no fallthrough error check are applied
  (IC-FTB-11, ftb_decisions.md 4.5).

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

IC-FTB-07 (open):
  Flush protocol (ftb_flush_px). Port reserved; behavior TBD at
  bp_cluster integration. Do not implement flush logic until specified.

IC-FTB-08 (resolved, session-052; reconciled session-053):
  Field widths ruled (ftb_decisions.md 8). FTB_BR_POS_BITS = 3,
  FTB_BR_TGT_BITS = 13, FTB_JMP_TGT_BITS = 21, TAR_STAT_BITS = 2.
  always_taken removed: each conditional field is 22 bits, so
  FTB_RAM_ENTRY_WIDTH = 105, FTB_RAM_SET_WIDTH = 420; logical
  FTB_ENTRY_WIDTH = 106 (1 valid in ftb_plru + 105 in ftb_array). The
  width is settled.

IC-FTB-09 (open):
  G9 update channel arbitration. Multi-branch update scheduling onto
  the single FTB update port is an FTQ/cluster concern, resolved at
  bp_cluster integration. (Also covers the prediction-vs-update read
  port sharing surfaced in BP-066.)

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

IC-FTB-11 (resolved, session-052):
  Fallthrough reconstruction error. Ruled OUT. The full 26-bit tag
  (ftb_decisions.md 4.1) makes wrong-entry hits unreachable.
  ftb_pft_addr_p2 is reconstructed and used unconditionally; there is
  no fallthrough-error output and no fallback mux. See ftb_decisions.md
  4.5 for the divergence record and the restore guard.

IC-FTB-12 (session-053):
  Storage split. ftb_array is pure 1R1W DATA RAM: no entry-valid, no
  PLRU state, no compute. The entry-valid bits and the tree-PLRU state
  live in ftb_plru, in resettable flops. Reset clears the valid bits;
  this is the FTB cold init -- the FTB has NO sram_init mechanism.
  Way-match, PLRU victim selection, PLRU next-state, and valid set/clear
  are all computed in ftb_cntrl, which drives both storage modules. The
  logical entry is partitioned: 1 valid bit/way in ftb_plru, 105 in
  ftb_array.

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
  (br0, br1, jump; FTB_BR_POS_BITS each) has a producer and a consumer:
  written from ftb_upd_pos_u0 (2.5) at allocate / free-field fill,
  routed to the field selected by ftb_upd_br_idx_u0 or ftb_upd_is_jmp_u0;
  read out on ftb_br0_pos_p2 / ftb_br1_pos_p2 / ftb_jmp_pos_p2 (2.3).
  Position is static for the life of a filled field -- not rewritten on
  an in-place conf/target update; reset only by reallocation. No stored
  field may be left write-only (0-stuffed) or read-only: a field is not
  "settled" until it has a named producer and consumer.

---

## 5. Parameters

All from bp_defines_pkg.sv. Settled values (ftb_decisions.md 8 / 8.1):

  VA_WIDTH          = 40
  FTB_WAYS          = 4
  FTB_ENTRIES       = 2048
  FTB_SETS          = 512
  FTB_IDX_BITS      = 9
  FTB_WAY_BITS      = 2        $clog2(FTB_WAYS), carried writeWay
  FTB_BLOCK_BYTES   = 32
  FTB_OFFSET_BITS   = 5        $clog2(FTB_BLOCK_BYTES), byte offset
  FTB_TAG_BITS      = 26       VA_WIDTH - FTB_IDX_BITS - FTB_OFFSET_BITS
  PLRU_BITS         = 3        FTB_WAYS - 1, tree-PLRU (in ftb_plru)
  PFTADDR_BITS      = 4        $clog2(FTB_BLOCK_BYTES/4) + 1
  TAR_STAT_BITS     = 2        fit / overflow / underflow
  FTB_BR_POS_BITS   = 3        $clog2(FTB_BLOCK_BYTES/4), in-block pos
  FTB_BR_TGT_BITS   = 13       conditional target displacement
  FTB_JMP_TGT_BITS  = 21       jump target displacement
  FTB_CONF_WIDTH    = 3        bimodal direction counter (MSB = dir)
  FTB_CONF_INIT_TKN = 3'b100   allocate weak-taken (MSB=1, unsaturated)
  FTB_CONF_INIT_NTK = 3'b011   allocate weak-not-taken (MSB=0, unsat.)
  Invariant: both init values unsaturated, MSB matches direction
  (IC-FTB-06). There is no FTB_CONF_SUPPRESS_THRESH.

  FTB_ENTRY_WIDTH = 106 / FTB_SET_WIDTH = 424   (logical, incl. valid)
  FTB_RAM_ENTRY_WIDTH = 105 / FTB_RAM_SET_WIDTH = 420   (ftb_array data)

ftb_array uses the FTB_RAM_* widths; ftb_plru holds the valid bit per
way and the PLRU state. All FTB field widths are settled; the only open
items are the flush protocol (IC-FTB-07) and the update-channel
arbitration / read-port sharing (IC-FTB-09), both deferred to
bp_cluster.

FETCH_BLOCK_BYTES = 64 is a global / fetch-unit parameter, already in
the package. It is NOT an FTB parameter. The FTB prediction block is
FTB_BLOCK_BYTES (32), decoupled from fetch width by the FTQ. Do not
collapse the two (ftb_decisions.md 2.3).

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

