<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTB Interface Contracts
```
 FILE:    planning/interfaces/ftb_interfaces.md
 SOURCE:  ftb_decisions.md (canonical), ftb_decision_record.md
          (session-051/052, frozen history)
 STATUS:  DRAFT
 UPDATED: 2026-06-24
 CONTACT: Jeff Nye
```

Interface contract for the FTB module. Derived from ftb_decisions.md,
which is the canonical authority. Where this file and ftb_decisions.md
disagree, ftb_decisions.md wins and this file is wrong.

Conventions:
  - Stage notation: planning narrative uses s-stage (s0/s1/s2/s3).
    Port names use p-stage (p0/p1/p2) for prediction, u0 for update,
    px for flush. s-stage and p-stage are equivalent.
  - FTB is a SINGLE array, one lookup per cycle, one entry per block.
    There are NO per-slot RAMs and NO NUM_PRED_SLOTS unpacking on FTB
    ports. The cluster's two branches per cycle are br0 and br1 of the
    one indexed entry (ftb_decisions.md 2.1).
  - The G8/G17 pred_pc+32 bundle split and TI6 per-slot RAMs are
    TAGE/ITTAGE conventions. They do NOT apply to FTB.
  - Active-low reset: rstn. Rising-edge clock: clk.
  - VA_WIDTH = 40. All full-width addresses are [VA_WIDTH-1:0].

---

## 1. Module Hierarchy

ftb (top, structural only)
  ftb_array (single 1R1W array; one instance)
  ftb_cntrl (read, branch-type classify, block-boundary and
             fallthrough compute, allocate/evict, update field
             writes, confidence training and suppression)

See ftb_decisions.md section 2.4. The top is structural only. The
array is a discrete module so a register file or a 1R1W SRAM can be
substituted without touching ftb_cntrl (ftb_decisions.md 2.4).

---

## 2. ftb Top Ports

### 2.1 Clock and reset

  clk               -- rising-edge clock
  rstn              -- active-low synchronous reset

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
                           Determined at the prediction read so update
                           need not re-look-up (ftb_decisions.md 5.3).

  -- conditional branch 0
  output logic                  ftb_br0_valid_p2
                        -- 1 = conditional field 0 is occupied.
  output logic                  ftb_br0_taken_p2
                        -- FTB direction for br0. 1 = taken.
                           Qualified by ftb_br0_valid_p2.
  output logic                  ftb_br0_always_taken_p2
                        -- 1 = br0 always_taken set. Direction
                           predictor bypassed; confidence suppression
                           not consulted for this branch (C5).
  output logic [FTB_CONF_WIDTH-1:0] ftb_br0_conf_p2
                        -- br0 confidence counter value, exposed for
                           the cluster and for observability.
  output logic [VA_WIDTH-1:0]   ftb_br0_target_p2
                        -- br0 taken target, reconstructed full width
                           by ftb_cntrl from the stored displacement
                           (4.2). Valid only when br0 taken.

  -- conditional branch 1 (same fields as br0)
  output logic                  ftb_br1_valid_p2
  output logic                  ftb_br1_taken_p2
  output logic                  ftb_br1_always_taken_p2
  output logic [FTB_CONF_WIDTH-1:0] ftb_br1_conf_p2
  output logic [VA_WIDTH-1:0]   ftb_br1_target_p2

  -- jump field (terminal: uncond jump / call / return)
  output logic                  ftb_jmp_valid_p2
                        -- 1 = jump field occupied.
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

### 2.4 Confidence suppression output (to override logic, s2)

  output logic [1:0]            ftb_suppress_dir_p2
                        -- bit 0 = br0, bit 1 = br1.
                           1 = suppress a TAGE/SC DIRECTION override
                           for that branch (conf >= threshold and
                           chicken bit enabled). Target overrides
                           (ITTAGE/RAS) are never suppressed.
                           Qualified by ftb_valid_p2 and the matching
                           br_valid bit (IC-FTB-02).
                           Full policy in
                           ftb_confidence_override_rules.md.

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
                           On hit, the way to overwrite; on miss, the
                           tree-PLRU victim way to allocate. ftb_cntrl
                           does NOT re-look-up the tag (IC-FTB-10).

  -- conditional-branch resolve
  input  logic                  ftb_upd_is_br_u0
                        -- 1 = this resolve is a conditional branch.
  input  logic                  ftb_upd_br_idx_u0
                        -- which conditional field, 0 or 1.
  input  logic                  ftb_upd_taken_u0
                        -- resolved direction. 1 = taken.
  input  logic [VA_WIDTH-1:0]   ftb_upd_target_u0
                        -- resolved taken target, full width.
                           ftb_cntrl converts to the stored
                           displacement form for conditional storage
                           (4.2).
  input  logic                  ftb_upd_ftb_dir_u0
                        -- FTB's ORIGINAL direction prediction for
                           this branch, carried in the FTQ entry.
                           Required for confidence training: compared
                           against ftb_upd_taken_u0 to inc/dec conf
                           (C2). Not derivable at update without it.

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
                           (ftb_decisions.md 5.4/5.5). Written at
                           allocate and recomputed on any update that
                           moves the block boundary (branch added to a
                           free field, terminating branch changes, or
                           block truncation moves the end).

There is no last_may_be_rvi_call port. The bit was eliminated; no
instruction straddles a block boundary in this design
(ftb_decisions.md section 6).

### 2.6 Flush input

  input  logic                  ftb_flush_px
                        -- flush. Protocol TBD at bp_cluster
                           integration (IC-FTB-07). On flush,
                           prediction outputs clear. Update-queue
                           drain behavior is owned by the FTQ.

---

## 3. ftb_array Module Ports

One instance. Single 1R1W array. Read port for prediction, write port
for update, independent read and write addresses usable in the same
cycle.

  clk               -- rising-edge clock
  rstn              -- active-low synchronous reset

  -- read port (prediction)
  rd_en             -- 1 = read this cycle
  rd_addr           -- [FTB_IDX_BITS-1:0]   set index
  rd_data           -- [SET_WIDTH-1:0]      all ways of the set;
                       way match and select in ftb_cntrl

  -- write port (update / allocate)
  wr_en             -- 1 = write this cycle
  wr_addr           -- [FTB_IDX_BITS-1:0]   set index
  wr_way            -- [FTB_WAYS-1:0]       one-hot way select
                       (ftb_cntrl decodes the carried encoded way,
                        ftb_upd_way_u0, to one-hot here)
  wr_data           -- [ENTRY_WIDTH-1:0]    one way's entry

  -- tree-PLRU state, per set (read-modify-write in ftb_cntrl)
  plru_rd_addr      -- [FTB_IDX_BITS-1:0]
  plru_rd_data      -- [PLRU_BITS-1:0]
  plru_wr_en        -- write enable
  plru_wr_addr      -- [FTB_IDX_BITS-1:0]
  plru_wr_data      -- [PLRU_BITS-1:0]

PLRU updates on two events (ftb_decisions.md 5.3): prediction hit
(mark the hit way used) and update/allocate write (mark the written
way used). The victim way is selected at the prediction read and
carried to update (IC-FTB-10).

  SET_WIDTH   = FTB_WAYS * ENTRY_WIDTH

  ENTRY_WIDTH per way = 108 bits (all widths ruled, session-052):
                  1                       valid
                + FTB_TAG_BITS            tag                  (26)
                + 2 * (                   br0 + br1 = 46:
                        1                   field valid
                      + FTB_BR_POS_BITS     in-block position    (3)
                      + FTB_BR_TGT_BITS     target displacement  (13)
                      + TAR_STAT_BITS       fit/ovf/udf          (2)
                      + 1                   always_taken
                      + FTB_CONF_WIDTH )    conf                 (3)
                + 1                       jump valid
                + FTB_BR_POS_BITS         jump in-block position (3)
                + FTB_JMP_TGT_BITS        jump target displ.     (21)
                + TAR_STAT_BITS           jump fit/ovf/udf       (2)
                + 3                       isCall / isRet / isJalr
                + PFTADDR_BITS            partial fallthrough    (4)
                + 1                       carry

  SET_WIDTH = FTB_WAYS * ENTRY_WIDTH = 4 * 108 = 432 bits.

All field widths are settled (ftb_decisions.md 8). Jump target is
stored as a 21-bit displacement + status (was full-width in an earlier
draft), reconstructed to full VA at read.

Same-cycle read and write to the same set/way: the read returns the
OLD value (F19). Substitution invariant: any 1R1W array primitive may
replace ftb_array without changing ftb_cntrl port connections.

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
  ftb_suppress_dir_p2[i] is valid only when ftb_valid_p2 is asserted
  and the matching ftb_brI_valid_p2 is asserted. Do not sample
  suppression on an FTB miss or an empty conditional field.

IC-FTB-03:
  ftb_pft_addr_p2 is the authoritative fallthrough for the cluster.
  RAS uses this value as the pushed return address (ras_fall_through).
  No straddle correction is applied; the straddle bit was eliminated.
  No fallthrough error check is applied; the value is trusted
  (IC-FTB-11, ftb_decisions.md 4.5).

IC-FTB-04:
  br0 and br1 are the two conditional fields of one entry from one
  lookup. FTB does not produce a second, separately-indexed
  prediction. There is no slot-1 lookup and no slot-1 output to
  discard.

IC-FTB-05:
  The FTQ owns update scheduling. FTB exposes one update port and does
  not serialize or arbitrate multi-branch updates internally (F20).

IC-FTB-06:
  FTB_CONF_INIT < FTB_CONF_SUPPRESS_THRESH must hold for all parameter
  sets, so a freshly allocated entry cannot suppress on first use.
  Assert in ftb_cntrl and in tb_ftb (C8).

IC-FTB-07 (open):
  Flush protocol (ftb_flush_px). Port reserved; behavior TBD at
  bp_cluster integration. Do not implement flush logic until the
  protocol is specified.

IC-FTB-08 (resolved, session-052):
  Field widths ruled (ftb_decisions.md 8, FTB-1 closed).
  FTB_BR_POS_BITS = 3 (in-block position, expanded granularity).
  FTB_BR_TGT_BITS = 13 and FTB_JMP_TGT_BITS = 21 (target displacements
  from ISA B-type/J-type reach in the expanded address space, +1 over
  Xiangshan's 12/20 for original-space). TAR_STAT_BITS = 2 on both.
  ENTRY_WIDTH = 108 bits/way, SET_WIDTH = 432. The position/pftAddr
  widths do NOT follow Xiangshan (granularity-dependent); the target
  widths DO derive from the same ISA reach Xiangshan's BR/JMP_OFFSET
  encode.

IC-FTB-09 (open):
  G9 update channel arbitration. Multi-branch update scheduling onto
  the single FTB update port is an FTQ/cluster concern, resolved at
  bp_cluster integration.

IC-FTB-10 (resolved, session-052):
  Update-side way selection. ftb_cntrl does NOT re-look-up the tag on
  update. The predicted way (writeWay) and the hit result are
  determined at the prediction read (ftb_way_p2 / ftb_hit_p2) and
  carried through the FTQ on ftb_upd_way_u0 / ftb_upd_hit_u0. On a
  carried hit, overwrite the carried way; on a carried miss, allocate
  the carried tree-PLRU victim. Matches Xiangshan. A carried victim
  may go stale if another write hits the same set between read and
  update; tolerated (prediction accuracy, never correctness). See
  ftb_decisions.md 5.1 / 5.3.

IC-FTB-11 (resolved, session-052):
  Fallthrough reconstruction error. Ruled OUT. The full 26-bit tag
  (ftb_decisions.md 4.1) makes wrong-entry hits unreachable, which is
  the only condition Xiangshan's fallThroughErr guards against under
  its truncated tag. ftb_pft_addr_p2 is reconstructed and used
  unconditionally; there is no fallthrough-error output and no
  fallback mux. FTB is not defensive against its own corrupt state.
  See ftb_decisions.md 4.5 for the divergence record and the restore
  guard (any reinstated fallback is start + FTB_BLOCK_BYTES, never
  start + FetchWidth*4).

---

## 5. Parameters

All from bp_defines_pkg.sv. Settled values (ftb_decisions.md 8 / 8.1):

  VA_WIDTH          = 40
  FTB_WAYS          = 4        PACKAGE CURRENTLY 8 -- must be fixed.
  FTB_ENTRIES       = 2048
  FTB_SETS          = 512
  FTB_IDX_BITS      = 9
  FTB_WAY_BITS      = 2        $clog2(FTB_WAYS), carried writeWay
  FTB_BLOCK_BYTES   = 32
  FTB_OFFSET_BITS   = 5        $clog2(FTB_BLOCK_BYTES), byte offset
  FTB_TAG_BITS      = 26       VA_WIDTH - FTB_IDX_BITS - FTB_OFFSET_BITS
  PLRU_BITS         = 3        FTB_WAYS - 1, tree-PLRU
  PFTADDR_BITS      = 4        $clog2(FTB_BLOCK_BYTES/4) + 1
  TAR_STAT_BITS     = 2        fit / overflow / underflow
  FTB_BR_POS_BITS   = 3        $clog2(FTB_BLOCK_BYTES/4), in-block pos
  FTB_BR_TGT_BITS   = 13       conditional target displacement
  FTB_JMP_TGT_BITS  = 21       jump target displacement
  FTB_CONF_WIDTH    = 3
  FTB_CONF_SUPPRESS_THRESH = 6
  FTB_CONF_INIT     = 3'b011
  Invariant: FTB_CONF_INIT < FTB_CONF_SUPPRESS_THRESH (IC-FTB-06).

  ENTRY_WIDTH = 108 bits/way, SET_WIDTH = 432 (section 3). All FTB
  field widths are now settled; nothing remains derived-at-RTL except
  the flush protocol (IC-FTB-07), which is deferred to bp_cluster.

FETCH_BLOCK_BYTES = 64 is a global / fetch-unit parameter, already in
the package. It is NOT an FTB parameter. The FTB prediction block is
FTB_BLOCK_BYTES (32), decoupled from fetch width by the FTQ. Do not
collapse the two (ftb_decisions.md 2.3).

---

## 6. Interactions With Other Planning Documents

  ftb_decisions.md    -- canonical FTB authority. This file is
                         subordinate to it.
  ftb_confidence_override_rules.md
                      -- the 3-bit confidence counter: training,
                         suppression, chicken bit, thresholds.
  bp_cluster.md       -- pipeline staging, override chain, FTQ entry
                         contents, decoupled frontend, pipeline
                         advance control.
  ras_decisions.md    -- RAS consumes ftb_pft_addr_p2 as the pushed
                         return address; ftb_jmp_target_p2 is the
                         RAS-empty fallback.
  ittage              -- ftb_jmp_target_p2 is the ITTAGE-miss fallback
                         (ITTAGE has no IT0 base table).
  bp_defines_pkg.sv   -- all FTB parameters in section 5.

---

## 7. Document History

  2026-06-24  session-052. Regenerated from ftb_decisions.md after the
              prior interface draft was found built on the rejected
              two-array / per-slot-RAM model. Corrections from that
              draft: single array and single update port (per-slot
              duplication removed); VA_WIDTH=40 throughout (was 64);
              FTB_TAG_BITS=26 (was 49); expanded-instruction
              granularity, 3-bit position kept open not 4-bit
              (was Xiangshan's 16-position/2-byte layout); partial
              pftAddr + carry stored (was full-width); slot-1 PC +32
              split removed (does not apply to FTB);
              last_may_be_rvi_call removed (bit eliminated);
              override-rules filename corrected to
              ftb_confidence_override_rules.md; IC-FTB-08 reopened
              (was wrongly marked closed with wrong widths).

  2026-06-24  session-052 (later pass). IC-FTB-10 resolved: writeWay
              and hit carried from the prediction read (ftb_way_p2 /
              ftb_hit_p2) through the FTQ; update-side re-lookup
              removed; ftb_upd_hit_u0 and ftb_upd_way_u0 added to 2.5;
              FTB_WAY_BITS added. IC-FTB-11 resolved: fallThroughErr
              ruled out (full tag), no error output, ftb_pft_addr_p2
              used unconditionally. Both rulings are authored in
              ftb_decisions.md (5.1/5.3, 4.5); this file points back to
              that authority.

  2026-06-24  session-052 (widths pass). IC-FTB-08 resolved: all field
              widths ruled in ftb_decisions.md section 8.
              FTB_BR_POS_BITS=3, FTB_BR_TGT_BITS=13, FTB_JMP_TGT_BITS=21,
              TAR_STAT_BITS=2. ENTRY_WIDTH resolved to 108 bits/way,
              SET_WIDTH 432; section 3 no longer symbolic. Jump target
              output reconstructed from a 21-bit displacement+status
              (was full-width). Only IC-FTB-07 (flush) remains open,
              deferred to bp_cluster.

