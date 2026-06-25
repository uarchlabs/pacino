<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTB Micro-Architectural Decisions
```
 FILE:    ftb_decisions.md
 SOURCE:  session-051 / session-052 / session-053
 STATUS:  DRAFT
 UPDATED: 2026-06-25
 CONTACT: Jeff Nye
```

Canonical decision record for the Fetch Target Buffer (FTB), also
called the BTB. Companion to ftb_interfaces.md (interface contract)
and ftb_confidence_override_rules.md (confidence-override policy).
Those documents reference this file for FTB-specific decisions.
Claude Code loads this file when working on ftb.sv or related
testbenches.

Note on stage notation: planning documents use s-stage notation
(s0/s1/s2/s3). RTL and port names use p-stage notation (p0/p1/p2/p3).
They are equivalent. Port names use p-stage; narrative uses s-stage.

---

## 1. Role and Pipeline Position

FTB provides the authoritative branch target for direct conditional
and unconditional branches, and classifies branch type for the whole
prediction cluster.

Pipeline stage: s2 output. s0 send, s1 registered, s2 valid.

Override chain: SC > TAGE > FTB > uBTB. FTB overrides uBTB. TAGE and
SC override FTB on direction. ITTAGE and RAS override FTB on target.

FTB classifies branch type per block, which gates who supplies the
target at s2:
  return       -> RAS provides target
  indirect     -> ITTAGE provides target
  conditional  -> TAGE provides direction, FTB provides target
  direct uncond -> FTB provides target

Branch type classification is FTB's responsibility. The three-way
JALR split (FTB / RAS / ITTAGE) is resolved by FTB structural
prediction before s2. RAS, ITTAGE, and TAGE depend on FTB's branch
type and fallthrough outputs.

### 1.1  Timing

uBTB is the zero-bubble s1 predictor that supplies the fast next-PC.
FTB at s2 is therefore not on the critical first-cycle path, which
gives FTB a larger, slower read budget. FTB overrides uBTB at s2 on
the presumption that the larger, slower structure is more accurate.
That override is an s2 redirect and costs a bubble. The bubble is the
accepted cost of the timing latitude; it is what allows FTB to be
sized and clocked as a second-level structure rather than a
zero-bubble one.

---

## 2. Structure

### 2.1  Single array

ONE FTB data array. One PC indexes one entry per cycle. That entry
describes the whole prediction block: its start, its end
(fallthrough), its branches, their types, and their basic directions.
One read port for prediction; one write port for update (see
ftb_interfaces.md section 3).

The entry-level valid bits and the tree-PLRU replacement state do NOT
live in the data array. They are held in a parallel flop module,
ftb_plru (section 2.4, 5.3). The data array (ftb_array) is therefore
pure RAM: a single PC lookup returns one data entry per way of the
indexed set, and ftb_cntrl qualifies each way with the matching valid
bit read from ftb_plru.

The cluster predicts two branches per cycle. Both branches come from
the one indexed entry (two conditional fields, section 4). FTB does
NOT use per-slot RAMs. TI6 (per-slot RAMs) and the G8/G17 pred_pc+32
bundle split are TAGE/ITTAGE conventions and do not apply to FTB
structure. A single FTB lookup supplies both predictions.

### 2.2  Associativity and capacity

  FTB_WAYS    = 4       set-associative, parameterized.
  FTB_ENTRIES = 2048    total, single array.
  FTB_SETS    = 512     FTB_ENTRIES / FTB_WAYS.

4-way is the Xiangshan choice at the same 2048-entry capacity. 8-way
was an unmeasured belief; FTB_WAYS is parameterized so 8-way is a
synthesis experiment, not a redesign. Revisit with SPEC numbers if
time allows.

2048 entries is in the proven range for a fast single-level BTB
(Apple M2 ~2048; Xiangshan 2048; Zen 2/3/4 fast tier 512/1536). We
are not building a 4096-entry FTB at this time. Relief lever if
capacity or timing is tight: 1024 entries (256 sets x 4-way).

Growth path if 2048 proves short under SPEC: a second FTB level (L2
FTB, victim style), consistent with the decoupled frontend. NOT a
larger flat L1. Bigger commercial designs go multi-level, not
fatter-flat.

### 2.3  Block width vs fetch width

FTB prediction block = 32 bytes (FTB_BLOCK_BYTES), 8 expanded
instructions, matched to 8-wide issue and to the two-branch-per-cycle
budget. FTB predicts one 32-byte block per cycle.

Fetch delivers 64 bytes (FETCH_BLOCK_BYTES, a fetch-unit / global
parameter, not an FTB parameter) into the FTQ per cycle, decoupled
from FTB by the queue. The wider fetch gives decode and fusion a
larger window. It does NOT raise the prediction rate. Prediction rate
is two branches per cycle.

These two widths are independent and must not be collapsed. Treating
the 64-byte fetch as a 64-byte prediction reintroduces a
two-block-per-cycle structure, which is wrong (it would demand four
conditional-branch predictions per cycle against a two-prediction
budget).

### 2.4  Module boundary

FTB is a structural top module (ftb) containing THREE submodules:

  - ftb_array  -- the single 1R1W FTB DATA array. Pure RAM: data only,
                  no entry-valid bit, no PLRU state, no compute. It has
                  no reset (a real SRAM cannot be reset). Sized at
                  FTB_RAM_ENTRY_WIDTH per way (section 8).
  - ftb_plru   -- entry-valid bits and tree-PLRU replacement state for
                  every set, held in resettable flops. Storage only --
                  it does not compute the victim, the next PLRU state,
                  or the way-match. Reset clears all entry-valid bits;
                  this is the FTB cold init.
  - ftb_cntrl  -- all FTB logic: read, branch-type classification,
                  way-match (ftb_array tag qualified by ftb_plru
                  valid), block-boundary and fallthrough computation,
                  allocate/evict including PLRU victim and next-state
                  compute, valid set/clear, update field writes,
                  confidence training and suppression.

The top is structural only, matching the convention of keeping arb
logic out of the TAGE/ITTAGE tops. ftb_array and ftb_plru are storage
peers; ftb_cntrl is the only logic and drives both.

This split exists to support eventual SRAM migration. By keeping the
data array pure (no per-entry resettable state, no decode) it can be
replaced by a 1R1W SRAM macro without touching ftb_cntrl. The
resettable state that a real SRAM cannot hold -- the entry-valid bits
-- lives in ftb_plru flops, so the FTB needs NO sram_init mechanism,
unlike the TAGE/ITTAGE tables. The tree-PLRU state lives there too,
co-located with validity since both are small per-set flop state that
ftb_cntrl maintains.

Storage-module enables are ACTIVE LOW, matching the BPU array
convention (ftb_interfaces.md IC-FTB-13). ftb_array has clk only and
no reset; ftb_plru reset (rstn) clears its valid and PLRU state. Both
storage modules return the OLD contents on a same-cycle read vs
same-set write, so a prediction sees a coherent pre-update snapshot of
data and validity/replacement together (IC-FTB-14).

Outside FTB: FTQ-level update scheduling, and cluster-wide override
resolution at s2.

---

## 3. Block Model

One FTB entry describes one prediction block. The block runs from the
lookup PC to the fallthrough address.

Intra-block branching (a taken branch targeting an address inside the
same block) is handled by the next cycle's lookup re-indexing at the
branch target. It is NOT handled by predicting two blocks in one
cycle. Each cycle is one block prediction from one entry.

A block can contain more branches than the entry can hold (section 4:
two conditional + one jump). When a block has a third conditional
branch with no field for it, the block ENDS at the second conditional.
The fallthrough points just after that second branch. The third
branch becomes the first branch of the next fetch block and gets its
own entry on a separate lookup. Branches are never dropped; the block
is split.

Cost of the split: that block becomes two fetch blocks, two lookups
instead of one, on that path. This only happens with three or more
conditional branches in one 32-byte block, which is rare.

---

## 4. Entry Format

Each entry holds two conditional branch fields and one jump field
(2+1). No Xiangshan-style field sharing. Two conditional branches with
no jump fill both conditional fields directly.

Entry fields (logical entry, FTB_ENTRY_WIDTH = 108 bits/way):

  valid                  -- entry valid. Held in ftb_plru (flops),
                            NOT in ftb_array (section 2.4, 8).
  tag                    -- FTB_TAG_BITS, full upper-VA tag (2.x)
  conditional branch 0   -- valid, offset, target, always_taken,
                            conf[2:0]
  conditional branch 1   -- valid, offset, target, always_taken,
                            conf[2:0]
  jump field             -- valid, offset, target (reconstructed full
                            VA_WIDTH from a stored displacement, 4.2),
                            isCall, isRet, isJalr
  fallthrough            -- pftAddr + carry

Storage partition. The entry-level valid bit (1 per way) is the only
field physically relocated to ftb_plru. The remaining 107 bits -- tag,
both conditional fields, the jump field, and the fallthrough -- are
stored in ftb_array (FTB_RAM_ENTRY_WIDTH, section 8). The per-field
valid bits of br0/br1/jump stay in the RAM entry; they are don't-care
while the entry-valid (in ftb_plru) is 0, so they need no reset. The
entry-valid gates the whole entry.

NOTE: this bit has been removed. This reference kept for documentation
of the decision
  last_may_be_rvi_call   -- 1 bit (section 6)

The 2+1 structure costs the area of two full conditional fields plus a
jump field even in the common one-branch block. This is a chosen
tradeoff: simpler format, simpler update, no field-sharing decode.
Project stance is to trade area for performance; do not optimize the
entry toward minimum area at the expense of capability.

### 4.1  Tag

  FTB_TAG_BITS = 26   = VA_WIDTH - FTB_IDX_BITS - FTB_OFFSET_BITS
                      = 40 - 9 - 5.

Full upper-VA tag. Chosen so two different PCs can never alias to one
entry. No partial-tag aliasing.

### 4.2  Targets

Conditional branch targets are stored as an offset from the block
start, with a fit/overflow/underflow status field. Offset storage is
lossless -- the target reconstructs exactly -- so it is an area win,
not an accuracy tradeoff. The cost is a reconstruct-and-bounds-check
step in logic.

The jump field target is stored as a 21-bit displacement
(FTB_JMP_TGT_BITS) plus a fit/overflow/underflow status, the same
lossless offset-from-block-start encoding as the conditional targets
(4.2 above), reconstructed to full width at read. It is load-bearing
for the cluster:

ITTAGE has no IT0 base table. An ITTAGE miss therefore produces no
ITTAGE target. The FTB jump target is the architectural fallback for
the terminal control instruction:
  - direct jump (JAL, fixed target): the FTB jump target IS the
    answer.
  - indirect (JALR): ITTAGE overrides on hit; on ITTAGE MISS, the
    target falls back to the FTB jump target.
  - return: RAS overrides; the FTB jump target is the fallback when
    RAS is empty (connects to the RAS commit-stack fallback).

The override chain therefore has an implied "...else FTB jump target"
floor. FTB must keep the jump target current even for branches that
ITTAGE or RAS normally own. See section 5 (update) -- the jump target
is rewritten on every resolve of that jump, not gated on an ITTAGE
miss.

Target widths (session-052, ruled): the stored displacement widths are
set by ISA branch/jump reach in the EXPANDED address space, not by
in-block granularity. A conditional B-type reaches +/-4 KB in original
code; in the worst all-RVC-expanded case that span doubles to +/-8 KB,
so FTB_BR_TGT_BITS = 13. A J-type reaches +/-1 MB original, +/-2 MB
expanded, so FTB_JMP_TGT_BITS = 21. Both pair with TAR_STAT_BITS = 2.
The position field (which instruction in the block) is separate and is
FTB_BR_POS_BITS = 3 ($clog2(8)), in-block granularity.

### 4.3  always_taken

One bit per conditional branch. Meaning: this branch has been taken
every time, so the direction predictor can be skipped. Subsequent
predictors may adopt the FTB direction directly. always_taken has
priority over the confidence counter (see
ftb_confidence_override_rules.md). Init and clear rules in section 5.

### 4.4  Offset and fallthrough widths

pacino expands RVC instructions to 32b before the FTB. The FTB
addresses instructions at the expanded granularity, NOT 2-byte RVC
granularity.

Two different quantities must not be conflated here:

  - IN-BLOCK quantities (position offset, pftAddr) ARE granularity-
    dependent. Do NOT inherit Xiangshan's log2(PredictWidth)=4 position
    or its pftAddr sizing -- those address 16 RVC instructions at
    2-byte granularity. This design has 8 expanded instructions per
    32-byte block: FTB_BR_POS_BITS = 3, PFTADDR_BITS per 8.1.

  - TARGET DISPLACEMENT widths are set by ISA branch/jump REACH, not by
    in-block granularity. Xiangshan's BR_OFFSET_LEN=12 / JMP_OFFSET_LEN
    =20 encode the B-type/J-type immediate reaches and DO transfer,
    adjusted for the expanded address space: FTB_BR_TGT_BITS = 13,
    FTB_JMP_TGT_BITS = 21 (see 4.2). The earlier blanket "do not
    inherit BR_OFFSET_LEN/JMP_OFFSET_LEN" was too broad; it correctly
    excluded the position/pftAddr widths and wrongly swept in the
    target widths. Corrected here.

All widths are now ruled. None remain derived-at-RTL.

### 4.5  Fallthrough reconstruction: no error check (Xiangshan divergence)

pftAddr is stored partial (8.1). The full fallthrough is reconstructed
as block-start-high ++ pftAddr (+ carry). The reconstruction is used
UNCONDITIONALLY. There is no fallthrough error check.

Xiangshan carries a fallThroughErr signal: it compares the
reconstructed end against the block start and, if the end is not above
the start, discards pftAddr and substitutes start + one prediction
block. That guard exists because Xiangshan uses a truncated tag
(tagSize 20), so two PCs can alias to one entry, a wrong-entry hit is
possible, and the aliased entry's pftAddr is garbage relative to the
looked-up start.

This design uses a full tag (4.1, FTB_TAG_BITS = 26, no aliasing). A
hit is always the correct entry for the looked-up PC, so the
wrong-entry source of a bad pftAddr cannot occur. The only remaining
source is a corrupt or malformed entry, which is an upstream state
defect, not a designed-for event. FTB is NOT made defensive against
its own corrupt state; the reconstructed pftAddr is trusted. The error
comparator, the fallback mux, and any fallthrough-error output are
removed.

Restore guard: if this check is ever reintroduced, the fallback value
is start + FTB_BLOCK_BYTES (one prediction block, 32 bytes), NOT
Xiangshan's start + FetchWidth*4. In this design the fetch width maps
to FETCH_BLOCK_BYTES (64), so copying the Xiangshan literal would
substitute a fetch-width fallthrough and re-commit the block-vs-fetch
collapse banned by 2.3. Adopt the semantics (start + one prediction
block), never the literal.

---

## 5. Allocation and Update

Update happens post-execute, not at retire.

### 5.1  Hit updates, miss allocates

When a branch resolves at execute:
  - Tag hit (entry for this block already in the set): update in
    place. Write the resolved branch's target, always_taken, and conf
    to ftb_array.
  - Tag hit, this branch not yet stored, a branch field free: write it
    into the free field. conf for that field starts at FTB_CONF_INIT.
  - Tag miss (no entry for this block): allocate a new entry. The
    evicted way is chosen by the replacement policy (5.3). ftb_cntrl
    writes the entry data to ftb_array and sets the entry-valid for the
    allocated way in ftb_plru in the same cycle.

The whole block's branches live in one entry, because the entry sets
the block boundary and fallthrough. One branch per entry would not
work.

Way selection on update is carried, not recomputed. The predicted way
(writeWay) and the hit/miss result are determined by ftb_cntrl at the
prediction READ -- way-match over the ftb_array tags qualified by the
ftb_plru valid bits gives the hit way on a tag hit, or the tree-PLRU
victim way from ftb_plru on a miss (5.3) -- and travel with the
prediction through the FTQ. At update, ftb_cntrl writes the carried way
directly; it does NOT re-look-up the tag. On a carried hit, the carried
way is overwritten; on a carried miss, the carried victim way is
allocated (data to ftb_array, valid set in ftb_plru). This matches
Xiangshan (writeWay/hit carried in the prediction meta) and removes a
second tag lookup on the update path. See ftb_interfaces.md IC-FTB-10.

### 5.2  Track every branch, not just taken ones

FTB allocates and tracks any conditional branch or jump that resolves
in a fetched block, taken or not. A taken-only FTB does not work here:
a not-taken conditional that FTB did not store would give TAGE nothing
to override at s2, put the block boundary in the wrong place, and give
RAS the wrong fallthrough.

Cost: more entries than a taken-only BTB, so more pressure on the
2048-entry capacity. If capacity runs short under SPEC, this is the
first thing to revisit, alongside the capacity relief lever (2.2).

### 5.3  Replacement: tree-PLRU

On a tag-miss allocate, the evicted way is chosen by tree-PLRU,
PLRU_BITS = 3 per set for the 4-way. The tree-PLRU state AND the
entry-valid bits live in ftb_plru (resettable flops), not in ftb_array
(section 2.4). ftb_cntrl reads the set's PLRU state from ftb_plru at
the prediction read and selects the victim from it; on a tag hit the
carried way is the hit way, on a miss it is the PLRU victim. That way
is carried through the FTQ to the update (5.1).

ftb_cntrl computes the next PLRU state and writes it back to ftb_plru
on two events:
  - prediction hit: mark the hit way used.
  - update or allocate write: mark the written way used.
ftb_plru exposes separate valid and PLRU write ports, so an allocate
(set valid + mark used) does both in one cycle. The two PLRU-touch
events above are funneled by ftb_cntrl onto the single PLRU write
port; if both target the same set in one cycle, the update/allocate
write wins and the prediction-hit touch is dropped -- a dropped touch
costs prediction accuracy, never correctness.

A carried victim can go stale if another write lands in the same set
between the prediction read and the update. This is tolerated: an
occasional suboptimal eviction costs prediction accuracy, never
correctness. Same stance as Xiangshan.

The victim is the tree-PLRU choice. Allocation does not preferentially
fill an invalid way first; an invalid way is simply a low-value
eviction candidate the PLRU may or may not pick. (If invalid-first
allocation is ever wanted, ftb_cntrl already has the per-way valid
vector from ftb_plru to implement it; it is not specified now.)

### 5.4  Field values at allocate

  entry valid:  set to 1 in ftb_plru for the allocated way (5.1).
  field valid:  1 for a filled branch field, 0 for an unused one
                (stored in the ftb_array entry).
  tag:          the block tag.
  conf:         FTB_CONF_INIT (each conditional).
  always_taken: the branch's resolved direction at allocate -- 1 if
                allocated taken, 0 if not-taken. Cleared later by 5.5.
  target (cond): the resolved taken target, as an offset with
                fit/overflow/underflow status.
  target (jump): the resolved jump target, as a 21-bit displacement
                (FTB_JMP_TGT_BITS) with fit/overflow/underflow status.
  isCall / isRet / isJalr: from the resolved jump's type.
  fallthrough (pftAddr + carry): reduced by ftb_cntrl from the
                resolved block end address relative to block start.

### 5.5  Field writes when an existing branch resolves

  conf:         per ftb_confidence_override_rules.md (up if FTB would
                have been correct, down if wrong).
  always_taken: the first time the branch resolves not-taken, set it
                to 0. Once 0, it stays 0 for the life of the entry. It
                is set to 1 again only if the entry is evicted and
                reallocated to a taken branch.
                Reason: always_taken=1 means the branch has been taken
                every time. One not-taken outcome makes that false. It
                is not set back to 1 on the next taken, because an
                alternating branch would otherwise flip the bit back
                and forth and the claim would be wrong. One not-taken
                ends it.
  conditional target: rewrite if the resolved taken target differs
                from the stored offset.
  jump target:  rewrite on EVERY resolve of that jump, including when
                ITTAGE or RAS normally supplies the runtime target.
                ITTAGE has no base table, so an ITTAGE miss falls back
                to this stored target; RAS falls back here when empty.
                The stored target must stay current. Do NOT gate this
                write on "ITTAGE missed" -- write it whenever the jump
                resolves. See 4.2.
  fallthrough (pftAddr + carry): recomputed on any update that MOVES
                the block boundary -- a branch added to a free field,
                the terminating branch changing, or block truncation
                (section 3) moving the end. Computed from the resolved
                block end relative to block start, at the same write as
                the other fields. Not rewritten when the boundary is
                unchanged.

All of the above are writes into the ftb_array entry (the carried way).
The entry-valid in ftb_plru is unchanged on an in-place update -- it
was set at allocate and is only set/cleared there (and on flush, when
that protocol exists).

Full-to-partial reduction (ftb_cntrl): the update port delivers the
resolved block end as a full VA (ftb_upd_pft_addr_u0). ftb_cntrl
reduces it to the stored partial form:
  pftAddr = end[FTB_OFFSET_BITS-1 : 2]   -- the in-block instruction
            index of the end, expanded-instruction granularity
            (FTB_BLOCK_BYTES/4 = 8 positions, 3 bits) extended by one
            to represent the full-block end point (PFTADDR_BITS = 4,
            8.1).
  carry   = 1 when the end lies in the next block (end crosses the
            FTB_BLOCK_BYTES boundary above block start), else 0.
The reconstruction at read inverts this: block-start-high ++ pftAddr,
plus carry into the next block. No error check on reconstruction
(4.5).

---

## 6. last_may_be_rvi_call

THIS BIT HAS BEEN ELIMINATED. THIS DISCUSSION KEPT INCASE THE 
DECISION NEEDS TO BE REVISITED IN THE FUTURE.

A 1-bit field. It flags the case where the last instruction in a block
is a call whose second half spills into the next block. The RAS return
address depends on where the call actually ends, so the bit signals
that a straddle correction applies.

The bit is kept because an instruction straddling a block boundary
cannot be guaranteed not to happen. The straddle correction itself is
part of the fallthrough / pftAddr arithmetic (section 4.4), computed at
RTL/doc time -- it is not a separate stored width. The bit is the only
added storage.

---

## 7. Confidence Override

FTB carries a 3-bit saturating confidence counter per conditional
branch that can suppress a TAGE/SC direction override when FTB has
been reliably correct for that branch. This is a multi-predictor
interaction and is specified separately in
ftb_confidence_override_rules.md. Summary:

- Trains at execute on FTB direction correctness, unconditionally.
- Acts at s2 to suppress a TAGE/SC DIRECTION override only, when the
  counter is at or above FTB_CONF_SUPPRESS_THRESH.
- Target overrides (ITTAGE/RAS) are never suppressed.
- A chicken bit disables suppression while training continues.

See ftb_confidence_override_rules.md for the full policy.

---

## 8. Parameters

Defined in bp_defines_pkg.sv. Do not use numeric literals for these.

  VA_WIDTH          = 40      already in package.
  FTB_WAYS          = 4       set-associative (package fixed to 4 in
                              BP-065; an earlier draft annotation read
                              "currently 8" -- stale, struck).
  FTB_ENTRIES       = 2048    total, single array.
  FTB_SETS          = 512     FTB_ENTRIES / FTB_WAYS.
  FTB_IDX_BITS      = 9       $clog2(FTB_SETS).
  FTB_WAY_BITS      = 2       $clog2(FTB_WAYS). Encoded carried
                              writeWay (5.1).
  FTB_BLOCK_BYTES   = 32      FTB prediction block (8 expanded instr).
  FTB_OFFSET_BITS   = 5       $clog2(FTB_BLOCK_BYTES).
  FTB_TAG_BITS      = 26      VA_WIDTH - FTB_IDX_BITS - FTB_OFFSET_BITS.
  PLRU_BITS         = 3       FTB_WAYS - 1 (tree-PLRU). Stored in
                              ftb_plru.
  FTB_BR_POS_BITS   = 3       $clog2(FTB_BLOCK_BYTES/4). In-block
                              instruction position (8 expanded instr).
  FTB_BR_TGT_BITS   = 13      conditional target displacement. B-type
                              +/-4 KB original -> +/-8 KB expanded.
  FTB_JMP_TGT_BITS  = 21      jump target displacement. J-type
                              +/-1 MB original -> +/-2 MB expanded.
  TAR_STAT_BITS     = 2       fit / overflow / underflow status,
                              shared by conditional and jump targets.

Logical entry width (the full per-way entry, including the entry-valid
held in ftb_plru):

  FTB_ENTRY_WIDTH (logical, per way) = 108 bits:
    1   valid          -- held in ftb_plru (flops), not ftb_array
  + 26  tag
  + 2 * (1 + 3 + 13 + 2 + 1 + 3)   = 46   br0 + br1
  + (1 + 3 + 21 + 2 + 3)           = 30   jump (valid,pos,tgt,stat,type)
  + (4 + 1)                        =  5   pftAddr + carry
    FTB_SET_WIDTH = FTB_WAYS * FTB_ENTRY_WIDTH = 432 bits (logical).

RAM entry width (what ftb_array actually stores -- the logical entry
minus the relocated entry-valid):

  FTB_RAM_ENTRY_WIDTH = FTB_ENTRY_WIDTH - 1 = 107 bits/way.
    The br0/br1/jump FIELD-valid bits remain in the RAM entry; only the
    ENTRY-level valid moves to ftb_plru.
  FTB_RAM_SET_WIDTH = FTB_WAYS * FTB_RAM_ENTRY_WIDTH = 428 bits.

ftb_array is sized at FTB_RAM_* (data only). ftb_plru holds, per set,
FTB_WAYS entry-valid bits + PLRU_BITS tree-PLRU bits = 7 bits
(512 sets x 7 = 3584 flops). FTB_ENTRY_WIDTH / FTB_SET_WIDTH remain the
LOGICAL widths; FTB-1 / IC-FTB-08 stay closed -- the logical width is
unchanged, only its physical partition across the two storage modules.

Confidence parameters (see ftb_confidence_override_rules.md):

  FTB_CONF_WIDTH           = 3
  FTB_CONF_SUPPRESS_THRESH = 6
  FTB_CONF_INIT            = 3'b011
  Invariant: FTB_CONF_INIT < FTB_CONF_SUPPRESS_THRESH.

FETCH_BLOCK_BYTES = 64 is a global / fetch-unit parameter, already in
bp_defines_pkg.sv. It is NOT an FTB parameter; it is the fetch width,
decoupled from the FTB block width by the FTQ.

Control polarity: ftb_array and ftb_plru enables are active low
(rd_en_n, wr_en_n, val_we_n, plru_we_n), per the BPU array convention
(IC-FTB-13). ftb_array has no reset; ftb_plru rstn clears valid + PLRU.

## 8.1 Partial fall-through address derivation

pftAddr = partial fall-through address. It's the block's end address stored as
a short offset from the block start instead of a full VA, with carry as the
overflow bit when the end crosses a boundary. The full fall-through
reconstructs from block-start + pftAddr + carry. No fallthrough error check is
applied on reconstruction; see 4.5.

  PFTADDR_BITS      = $clog2(FTB_BLOCK_BYTES / 4) + 1

---

## 9. Open Items

  FTB-1: CLOSED (session-052). All offset, target, pftAddr, and carry
         widths ruled and listed in section 8. Position FTB_BR_POS_BITS
         =3; conditional FTB_BR_TGT_BITS=13; jump FTB_JMP_TGT_BITS=21;
         TAR_STAT_BITS=2; PFTADDR_BITS=4; carry=1. ENTRY_WIDTH=108.
         The session-053 storage split (8) does not reopen this: the
         logical entry is unchanged, only partitioned into
         FTB_RAM_ENTRY_WIDTH=107 (ftb_array) + 1 valid (ftb_plru).
         (Historical: last_may_be_rvi_call was eliminated; no straddle
         correction exists.)

  FTB-2: Confidence-override interaction with the TAGE update/meta
         path. Flagged, not yet analyzed. Resolve at bp_cluster
         integration.

  FTB-3: Update channel arbitration (G9). FTB exposes one update
         port; how multiple resolved branches are scheduled onto it is
         a cluster/FTQ concern, resolved at bp_cluster integration.

---

## 10. Interactions With Other Planning Documents

  ftb_interfaces.md   -- FTB module interface contract. Port list,
                         timing, producer/consumer obligations.
                         Sections 3 (ftb_array) and 3a (ftb_plru) carry
                         the storage-module ports; IC-FTB-12/13/14 carry
                         the storage-split invariants.

  ftb_confidence_override_rules.md
                      -- the 3-bit confidence counter, training and
                         suppression policy, chicken bit.

  bp_cluster.md       -- pipeline staging, override chain, FTQ entry
                         contents, decoupled frontend.

  ras_decisions.md    -- RAS consumes the FTB fallthrough as
                         ras_fall_through; FTB jump target is the RAS
                         fallback when RAS is empty.

  ittage              -- FTB jump target is the ITTAGE-miss fallback
                         (no IT0 base table).

  bp_defines_pkg.sv   -- FTB_WAYS, FTB_ENTRIES, FTB_SETS, FTB_IDX_BITS,
                         FTB_WAY_BITS, FTB_BLOCK_BYTES, FTB_OFFSET_BITS,
                         FTB_TAG_BITS, PLRU_BITS, FTB_ENTRY_WIDTH and
                         FTB_SET_WIDTH (logical), FTB_RAM_ENTRY_WIDTH
                         and FTB_RAM_SET_WIDTH (ftb_array),
                         FTB_CONF_SUPPRESS_THRESH, FTB_CONF_INIT.

---

## 11. Document History

  2026-06-24  session-051/052. Initial draft, expanded from
              ftb_decision_record.md. Single-array structure
              (one lookup per cycle, one entry per block, 2+1 fields).
              4-way / 2048 entries / 32-byte block / 26-bit full tag /
              tree-PLRU. Confidence override split to its own document.
              Jump target full width as the ITTAGE-miss / RAS-empty
              fallback. 

              Decision changed: this
                                    last_may_be_rvi_call kept.
                                is now this:
                                    last_may_be_rvi_call eliminated.

  2026-06-24  session-052 (later pass). Update-side way selection
              ruled: writeWay and hit carried from the prediction read
              through the FTQ, no update-side re-lookup (5.1, 5.3),
              matching Xiangshan. FTB_WAY_BITS added. Fallthrough
              reconstruction error check (Xiangshan fallThroughErr)
              ruled OUT: the full tag makes wrong-entry hits
              unreachable, and FTB is not made defensive against its
              own corrupt state (4.5). Restore guard recorded: any
              reinstated fallback is start + FTB_BLOCK_BYTES, never
              start + FetchWidth*4. pftAddr/carry write rule added to
              5.4 (allocate) and 5.5 (boundary-move recompute).

  2026-06-24  session-052 (widths pass). Entry widths ruled and FTB-1
              closed. FTB_BR_POS_BITS=3 (in-block position, expanded
              granularity). FTB_BR_TGT_BITS=13 and FTB_JMP_TGT_BITS=21
              (target displacements from ISA reach in the expanded
              address space; jump moved from full-width to 21+status).
              TAR_STAT_BITS=2 shared by conditional and jump targets.
              4.4 corrected: the blanket "do not inherit Xiangshan
              BR_OFFSET_LEN/JMP_OFFSET_LEN" was too broad -- it
              excludes in-block position/pftAddr (granularity) but the
              target displacement widths derive from ISA reach and do
              transfer. Full-to-partial fallthrough reduction
              arithmetic added to 5.5. ENTRY_WIDTH = 108 bits/way,
              SET_WIDTH = 432, fully determined.

  2026-06-25  session-053. Storage split for SRAM migration. Entry-
              valid and tree-PLRU state moved out of the data array
              into a new ftb_plru flop module (2.4); ftb_array reduced
              to pure 1R1W data RAM, no reset, FTB_RAM_ENTRY_WIDTH=107 /
              FTB_RAM_SET_WIDTH=428 (8). ftb_plru reset clears the
              entry-valid bits -- the FTB cold init, no sram_init
              (unlike TAGE/ITTAGE). PLRU victim/next-state compute and
              way-match stay in ftb_cntrl; ftb_plru and ftb_array are
              storage only. Storage-module enables made active low
              (BPU convention). Both storage modules read-old-on-
              collision for a coherent prediction snapshot. Edits in
              2.1, 2.4, 4 (storage partition note), 5.1, 5.3, 5.4, 8,
              10. Logical entry unchanged at 108; FTB-1 stays closed.
              Stale "FTB_WAYS currently 8" annotation struck (package
              confirmed 4 in BP-065). Companion: ftb_interfaces.md
              sections 3/3a and IC-FTB-12/13/14. RTL finalized in
              BP-065a.

