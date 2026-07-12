```
 FILE:    fe.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-07-08
 CONTACT: Jeff Nye
```

# Intro

This is the central planning document for the frontend once complete this will
be distilled to produce planning documents for rtl and testbench generation.

# Front-End FTQ <-> BPU Interface (XiangShan Kunminghu)

This document captures the structures used to communicate between the
Fetch Target Queue (FTQ) and the Branch Prediction Unit (BPU) in the
XiangShan Kunminghu (third generation) front end, followed by
SystemVerilog `typedef struct packed` translations of each structure.

Source of truth (local copies):
- Scala/Chisel: `./ia_xiangshan/scala/src/main/scala/xiangshan/`
  - `frontend/FrontendBundle.scala`  - prediction/update bundles
  - `frontend/NewFtq.scala`          - FTQ IO, FTQ-stored entries
  - `frontend/BPU.scala`             - BpuToFtqIO, constants
  - `frontend/FTB.scala`             - FTB entry and slots
  - `Bundle.scala`                   - Redirect, CfiUpdateInfo
- RTL (Verilator SystemVerilog): `./ia_xiangshan/rtl/Predictor.sv`,
  `./ia_xiangshan/rtl/Ftq.sv`

Note on the RTL: the Chisel bundles do NOT survive as SystemVerilog
structs. FIRRTL/Verilator flatten every field into a scalar port named
by its dotted path, joined with underscores, e.g.
`io_bpu_to_ftq_resp_bits_s2_full_pred_3_targets_0`. So the "Verilog
names" in the emitted RTL are the Scala field paths flattened. The
optimizer also prunes unused duplicate lanes, so only `full_pred_3` /
`pc_3` survive in the emitted RTL even though the source declares a
4-wide duplication vector. The `typedef struct packed` versions below
are a faithful, re-structured translation, not a copy of the flattened
emission.

---

## Top-level interface

The two directions are two Chisel IO bundles. In `Predictor`
(`rtl/Predictor.sv`) the FTQ side is `io.bpu_to_ftq` (output) and
`io.ftq_to_bpu` (input, `Flipped`).

```
BpuToFtqIO { resp : Decoupled(BpuToFtqBundle) }         // BPU -> FTQ
FtqToBpuIO { redirect, update, enq_ptr, redirctFromIFU} // FTQ -> BPU
```

---

## Parameters (default XiangShan config)

These size every structure below.

| Parameter        | Default | Meaning                               |
|------------------|---------|---------------------------------------|
| VAddrBits        | 39      | Virtual address width (Sv39, no H)    |
| FetchWidth       | 8       | Instructions fetched per cycle        |
| PredictWidth     | 16      | FetchWidth * 2 (with C extension)     |
| FtqSize          | 64      | FTQ entries                           |
| numBr            | 2       | Conditional branches per fetch block  |
| numBrSlot        | 1       | numBr - 1 (dedicated br slots)        |
| totalSlot        | 2       | numBrSlot + 1 (br slots + tail slot)  |
| numDup           | 4       | Prediction duplication (fanout/timing)|
| RasSize          | 16      | Return address stack depth            |
| RasCtrSize       | 3       | RAS repeat-return counter width       |
| RasSpecSize      | 32      | RAS speculative queue depth           |
| UbtbGHRLength    | 4       | uBTB global-history length            |
| HistoryLength    | ~256    | Global history length (config-derived)|
| MaxMetaLength    | 512/256 | Predictor meta blob (sim / FPGA)      |
| BR_OFFSET_LEN    | 12      | Branch-slot target low-bit width      |
| JMP_OFFSET_LEN   | 20      | Jump-slot target low-bit width        |
| TAR_STAT_SZ      | 2       | Target hi-bit status (FIT/OVF/UDF)    |

---

## Direction 1 - BPU -> FTQ: `BpuToFtqBundle` (= `BranchPredictionResp`)

Wrapped in `Decoupled` (`resp_valid` / `resp_ready` / `resp_bits_*`).
This is the 3-stage pipelined prediction. `s1/s2/s3` are three copies
of the same `BranchPredictionBundle`, one per predictor pipeline stage.

### BranchPredictionResp
```
| Field                  | Type                     | Description                                                                 |
|------------------------|--------------------------|-----------------------------------------------------------------------------|
| s1 / s2 / s3           | BranchPredictionBundle   | Prediction produced at pipeline stage 1 / 2 / 3 (later stages override)      |
| s1_uftbHit             | Bool                     | uFTB (FauFTB) hit in stage 1                                                 |
| s1_uftbHasIndirect     | Bool                     | Stage-1 block contains an indirect branch                                   |
| s1_ftbCloseReq         | Bool                     | Request to close/bypass main FTB lookup (timing/power)                       |
| last_stage_meta        | UInt(MaxMetaLength)      | Opaque predictor metadata, stored in FTQ, replayed on update to train       |
| last_stage_spec_info   | Ftq_Redirect_SRAMEntry   | Speculative history/RAS snapshot for recovery on redirect                    |
| last_stage_ftb_entry   | FTBEntry                 | The FTB entry hit (or synthesized) for this block                           |
| topdown_info           | FrontendTopDownBundle    | Top-down perf stall-reason counters                                         |

### BranchPredictionBundle (each of s1 / s2 / s3)

| Field        | Type                        | Description                                            |
|--------------|-----------------------------|--------------------------------------------------------|
| pc           | Vec(numDup, VAddr)          | Start PC of the predicted fetch block (duplicated)     |
| valid        | Vec(numDup, Bool)           | This stage produced a valid prediction                 |
| hasRedirect  | Vec(numDup, Bool)           | This stage disagrees with the prior stage -> redirect  |
| ftq_idx      | FtqPtr                      | FTQ slot this prediction will occupy                   |
| full_pred    | Vec(numDup, FullBranchPred) | The actual decoded prediction (below)                  |

### FullBranchPrediction (the core payload)

| Field                | Type                  | Description                                            |
|----------------------|-----------------------|--------------------------------------------------------|
| br_taken_mask        | Vec(numBr, Bool)      | Per-conditional-branch taken decision                  |
| slot_valids          | Vec(totalSlot, Bool)  | Which FTB slots (br slots + tail slot) are valid       |
| targets              | Vec(totalSlot, VAddr) | Target address per slot                                |
| jalr_target          | VAddr                 | Dedicated indirect (JALR) target path, for timing      |
| offsets              | Vec(totalSlot, UInt)  | In-block instruction offset of each slot's branch      |
| fallThroughAddr      | VAddr                 | Fall-through address (end of block if not taken)       |
| fallThroughErr       | Bool                  | Fall-through computation was invalid                   |
| multiHit             | Bool                  | More than one FTB way hit (error condition)            |
| is_jal / is_jalr     | Bool                  | Tail-slot jump type                                    |
| is_call / is_ret     | Bool                  | Tail-slot jump type                                    |
| last_may_be_rvi_call | Bool                  | Last slot may be a 32-bit (RVI) call spanning block end |
| is_br_sharing        | Bool                  | Tail slot is shared by a conditional branch            |
| hit                  | Bool                  | FTB hit for this block                                 |
| predCycle            | Option(UInt64)        | Debug: cycle prediction was made (non-FPGA only)       |

---

## Direction 2 - FTQ -> BPU

### 2a. enq_ptr : FtqPtr
Output-only. Current FTQ enqueue pointer so the BPU knows the next free
FTQ slot / can apply backpressure. `FtqPtr` is a `CircularQueuePtr` =
`{ flag: Bool, value: UInt(log2(FtqSize)) }`.

### 2b. redirctFromIFU : Bool
Flags that the pending redirect originated in the IFU predecode stage
(versus the backend).

### 2c. redirect : Valid(BranchPredictionRedirect)
Squash + steer the BPU after a mispredict. `BranchPredictionRedirect
extends Redirect`, so it carries the full backend redirect plus BPU
bubble-classification helpers.

#### Redirect (base)

| Field                    | Type            | Description                                     |
|--------------------------|-----------------|-------------------------------------------------|
| isRVC                    | Bool            | Redirecting instruction is compressed           |
| robIdx                   | RobPtr          | ROB entry of the redirecting instruction        |
| ftqIdx                   | FtqPtr          | FTQ block to redirect to                        |
| ftqOffset                | UInt            | Instruction offset within that block            |
| level                    | RedirectLevel   | Flush-itself vs flush-after semantics           |
| interrupt                | Bool            | Redirect caused by interrupt                    |
| cfiUpdate                | CfiUpdateInfo   | Control-flow info to restore predictor state    |
| stFtqIdx / stFtqOffset   | FtqPtr / UInt   | Store position, for load/store violation redirect |
| debugIsCtrl              | Bool            | Debug: redirect from a control (branch) mispred |
| debugIsMemVio            | Bool            | Debug: redirect from a memory-order violation   |

Plus (in BranchPredictionRedirect): `BTBMissBubble : Bool`, and derived
bubble-classification methods (ControlBTBMissBubble, TAGEMissBubble,
SCMissBubble, ITTAGEMissBubble, RASMissBubble, ...).

#### CfiUpdateInfo (carried inside redirect to rewind predictor state)

| Field         | Type                            | Description                                            |
|---------------|---------------------------------|--------------------------------------------------------|
| pc            | VAddr                           | PC of the control-flow instruction                     |
| pd            | PreDecodeInfo                   | Predecode info (br/jal/jalr/call/ret, rvc)             |
| ssp           | UInt(log2 RasSize)              | RAS speculative stack pointer to restore               |
| sctr          | UInt(RasCtrSize)                | RAS speculative counter (repeated-return compression)  |
| TOSW / TOSR   | RASPtr                          | RAS top-of-stack write / read pointers                 |
| NOS           | RASPtr                          | RAS next-on-stack pointer                              |
| topAddr       | VAddr                           | RAS top-of-stack return address                        |
| folded_hist   | AllFoldedHistories              | Folded global-history set to restore                   |
| afhob         | AllAheadFoldedHistoryOldestBits | Ahead-pipelined oldest history bits                    |
| lastBrNumOH   | UInt(numBr+1)                   | One-hot count of branches in last block (history shift)|
| ghr           | UInt(UbtbGHRLength)             | Global history register snapshot (uBTB)                |
| histPtr       | CGHPtr                          | Circular global-history pointer to restore             |
| specCnt       | Vec(numBr, UInt10)              | Speculative branch counters                            |
| br_hit        | Bool                            | Mispredicted branch was in the FTB entry               |
| jr_hit        | Bool                            | Indirect jump was in the FTB entry                     |
| sc_hit        | Bool                            | SC was consulted for this branch (valid if br_hit)     |
| predTaken     | Bool                            | Original predicted-taken value                         |
| target        | VAddr                           | Corrected target                                       |
| taken         | Bool                            | Actual taken outcome                                    |
| isMisPred     | Bool                            | This CFI was mispredicted                              |
| shift         | UInt(log2(numBr)+1)             | History shift amount for this block                    |
| addIntoHist   | Bool                            | Whether this branch updates global history             |

### 2d. update : Valid(BranchPredictionUpdate)
Non-speculative training, sent at commit/retire to update FTB, TAGE,
SC, ITTAGE, RAS.

#### BranchPredictionUpdate

| Field             | Type                | Description                                            |
|-------------------|---------------------|--------------------------------------------------------|
| pc                | VAddr               | Start PC of the block being trained                    |
| spec_info         | SpeculativeInfo     | Recovered speculative history/RAS state at pred time   |
| ftb_entry         | FTBEntry            | The (possibly newly generated) FTB entry to write      |
| cfi_idx           | Valid(UInt)         | Offset of the actual taken CFI (invalid if none)       |
| br_taken_mask     | Vec(numBr, Bool)    | Actual taken outcomes per conditional branch           |
| br_committed      | Vec(numBr, Bool)    | Branch slot valid AND committed                        |
| jmp_taken         | Bool                | Tail-slot jump was taken                                |
| mispred_mask      | Vec(numBr+1, Bool)  | Per-slot (+jmp) mispredict flags                       |
| pred_hit          | Bool                | Original prediction hit the FTB                        |
| false_hit         | Bool                | FTB hit but entry was stale/wrong                      |
| new_br_insert_pos | Vec(numBr, Bool)    | Slot position to insert a newly discovered branch      |
| old_entry         | Bool                | Update reuses an existing FTB entry (vs new)           |
| meta              | UInt(MaxMetaLength) | Predictor metadata replayed for training               |
| full_target       | VAddr               | Full (un-truncated) correct target                     |
| from_stage        | UInt(2)             | Which BPU stage originally produced the prediction     |
| ghist             | UInt(HistoryLength) | Global history at prediction time                      |

---

## Supporting structures

### FTBEntry (the FTB record - heart of the target payload)

| Field                | Type                     | Description                                     |
|----------------------|--------------------------|-------------------------------------------------|
| valid                | Bool                     | Entry valid                                     |
| brSlots              | Vec(numBrSlot, FtbSlot)  | Conditional-branch slots (BR_OFFSET_LEN = 12)   |
| tailSlot             | FtbSlot (JMP=20, sub=12) | Last slot - jump or shared last conditional br  |
| pftAddr              | UInt(log2 PredictWidth)  | Partial fall-through address (block end offset)  |
| carry                | Bool                     | Carry bit for fall-through hi-bit reconstruction |
| isCall / isRet       | Bool                     | Tail-slot jump type                             |
| isJalr               | Bool                     | Tail-slot jump type (isJal = !isJalr)           |
| last_may_be_rvi_call | Bool                     | Last instr may be a 32-bit call crossing end     |
| always_taken         | Vec(numBr, Bool)         | Per-branch "always taken" hint                  |

### FtbSlot (FtbSlot_FtqMem is the compact FTQ-stored subset)

| Field   | Type                   | Description                                     |
|---------|------------------------|-------------------------------------------------|
| offset  | UInt(log2 PredictWidth)| Branch instruction offset in block              |
| sharing | Bool                   | Tail slot shared by a conditional branch        |
| valid   | Bool                   | Slot valid                                      |
| lower   | UInt(offsetLen)        | Low bits of target address (12b br / 20b jmp)   |
| tarStat | UInt(2)                | Target hi-bit status: FIT / OVF / UDF           |

FtbSlot_FtqMem holds only offset/sharing/valid; lower/tarStat are
reconstructed, saving FTQ SRAM.

### SpeculativeInfo / Ftq_Redirect_SRAMEntry (history + RAS snapshot)

| Field              | Type                 | Description                                     |
|--------------------|----------------------|-------------------------------------------------|
| histPtr            | CGHPtr               | Circular global-history pointer                 |
| ssp                | UInt(log2 RasSize)   | RAS speculative stack pointer                   |
| sctr               | UInt(RasCtrSize)     | RAS speculative repeat counter                  |
| TOSW / TOSR / NOS  | RASPtr               | RAS top-write / top-read / next-on-stack ptrs   |
| topAddr            | VAddr                | RAS top return address                          |
| sc_disagree (SRAM) | Vec(numBr, Bool)     | SC disagreed with TAGE (non-FPGA, debug/train)  |

### PreDecodeInfo (8 bits)

| Field  | Type    | Description                                     |
|--------|---------|-------------------------------------------------|
| valid  | Bool    | Predecode valid                                 |
| isRVC  | Bool    | Compressed instruction                          |
| brType | UInt(2) | notCFI / branch / jal / jalr                    |
| isCall | Bool    | Call                                            |
| isRet  | Bool    | Return                                          |

### Circular queue pointers

All are `{ flag, value }` where value width = log2(depth):
- FtqPtr : value = log2(FtqSize)      = 6 bits
- RASPtr : value = log2(RasSpecSize)  = 5 bits
- CGHPtr : value = log2(HistoryLength)

---

## FTB (Fetch Target Buffer)

The FTB is the structure that lets the BPU predict a fetch block it has
never decoded. It is a set-associative, PC-indexed memory: given only
the block start PC, it returns where the branches are (as in-block
offsets), where they go (as compressed target low-bits), and the block
boundary (fall-through). The BPU never sees instruction bytes - the FTB
is trained after the fact from IFU predecode (see the update path in
`ifu_ftq.md` and `BranchPredictionUpdate` above).

Defined in `frontend/FTB.scala`. RTL: `rtl/FTB.sv`, `rtl/FTBBank.sv`,
`rtl/FauFTB.sv` (the stage-1 micro-FTB), `rtl/FTBEntryGen.sv` (build a
new entry from predecode).

### Organization (default config)

| Parameter  | Default | Meaning                                        |
|------------|---------|------------------------------------------------|
| FtbSize    | 2048    | Total FTB entries                              |
| FtbWays    | 4       | Associativity                                  |
| numSets    | 512     | FtbSize / FtbWays                              |
| tagSize    | 20      | Tag bits per entry                             |
| numBr      | 2       | Branches represented per entry (block)         |

- Index/tag are derived from the block PC (see `TableAddr` in
  `FrontendBundle.scala`): low bits pick the set, high bits form the
  tag. A hit requires a way whose tag matches.
- The FauFTB (micro-FTB, `FauFTB.sv`) is a small fully-associative
  stage-1 predictor that produces an early s1 prediction; the main FTB
  refines it at s2. `s1_uftbHit` / `s1_ftbCloseReq` in
  BranchPredictionResp come from here.

### How a branch PC is reconstructed

An FTB entry stores each branch as an in-block `offset`, not a full PC.
The full branch PC is rebuilt as `block_start + offset*2` (offset is a
log2(PredictWidth)=4-bit slot index; the *2 is instOffsetBits=1, since
RVC makes 2 bytes the minimum instruction stride). Target addresses are
stored as `lower` bits plus a 2-bit `tarStat` (FIT/OVF/UDF) that says
whether the high bits equal, exceed, or fall short of the block PC's
high bits; the full target is reassembled from the block PC high bits
+/- 1. This is why the entry is compact: it never stores full 39-bit
branch or target PCs.

Key helper methods on FTBEntry (`FTB.scala`):
- `getOffsetVec` -> Vec of each slot's in-block offset
- `getTargetVec(pc)` -> Vec of full targets (reassembled from lower +
  tarStat + block PC high bits)
- `getFallThrough(pc)` -> block fall-through address from `pftAddr` +
  `carry`
- `brValids` / `hasBr(offset)` / `brIsSaved(offset)` -> per-slot valid
  and lookup-by-offset queries
- `newBrCanNotInsert(offset)` / `noEmptySlotForNewBr` -> allocation
  checks used when predecode discovers a new branch

### FTBEntry (repeated here for completeness)

Full entry stored in the FTB SRAM. See also the `FTBEntry` table under
"Supporting structures" and the SystemVerilog `ftb_entry_t`.

| Field                | Type                     | Description                                     |
|----------------------|--------------------------|-------------------------------------------------|
| valid                | Bool                     | Entry valid                                     |
| brSlots              | Vec(numBrSlot, FtbSlot)  | Conditional-branch slots (BR_OFFSET_LEN = 12)   |
| tailSlot             | FtbSlot (JMP=20, sub=12) | Last slot - jump or shared last conditional br  |
| pftAddr              | UInt(log2 PredictWidth)  | Partial fall-through address (block end offset)  |
| carry                | Bool                     | Carry bit for fall-through hi-bit reconstruction |
| isCall / isRet       | Bool                     | Tail-slot jump type                             |
| isJalr               | Bool                     | Tail-slot jump type (isJal = !isJalr)           |
| last_may_be_rvi_call | Bool                     | Last instr may be a 32-bit call crossing end     |
| always_taken         | Vec(numBr, Bool)         | Per-branch "always taken" hint                  |

### FtbSlot (one branch within an entry)

| Field   | Type                   | Description                                     |
|---------|------------------------|-------------------------------------------------|
| offset  | UInt(log2 PredictWidth)| Branch instruction offset in block              |
| sharing | Bool                   | Tail slot shared by a conditional branch        |
| valid   | Bool                   | Slot valid                                      |
| lower   | UInt(offsetLen)        | Low bits of target address (12b br / 20b jmp)   |
| tarStat | UInt(2)                | Target hi-bit status: FIT / OVF / UDF           |

`FtbSlot_FtqMem` is the compact FTQ-stored subset (offset/sharing/valid
only); `lower`/`tarStat` are reconstructed to save FTQ SRAM.

### FTBEntryWithTag (what the SRAM actually holds)

| Field | Type       | Description                          |
|-------|------------|--------------------------------------|
| entry | FTBEntry   | The FTB entry payload                |
| tag   | UInt(20)   | Tag matched against the block PC     |

### FTBMeta (per-lookup metadata, carried in last_stage_meta)

| Field      | Type                 | Description                                     |
|------------|----------------------|-------------------------------------------------|
| writeWay   | UInt(log2 numWays)   | Way to write on update (hit way, or alloc way)  |
| hit        | Bool                 | Lookup hit the FTB                              |
| pred_cycle | Option(UInt64)       | Debug: cycle of prediction (non-FPGA only)      |

### FTB module ports (read + update)

The FTB module (`FTB.scala:455`) has a read path (prediction) and a
separate update path (training):

| Port                 | Dir | Description                                     |
|----------------------|-----|-------------------------------------------------|
| req_pc               | in  | Decoupled block PC to look up (read path)       |
| read_resp            | out | FTBEntry read out on hit                        |
| read_hits            | out | Valid + hit way (or alloc way if miss)          |
| u_req_pc             | in  | Decoupled block PC for the update path          |
| update_write_data    | in  | Valid(FTBEntryWithTag) to write                 |
| update_write_way     | in  | Way to write                                    |
| update_write_alloc   | in  | Write is an allocation (miss) vs a hit-update   |

The update path is fed by `FTBEntryGen` (`NewFtq.scala:232`), which
turns an old entry plus the IFU predecode result (`Ftq_pd_Entry`,
cfiIndex, target, mispredict_vec) into a new/updated FTBEntry and the
slot-insertion position for a newly discovered branch.

### Cold start: what happens on an FTB miss

Walk through what the front end does right after reset, when the FTB is
empty. This is the "warm-up" behavior, and it explains why an FTB miss
is not an error - it is the normal first-touch case.

1. Reset. `s0_pc` is set to the reset vector - the fixed address where
   the CPU starts fetching after reset (e.g. 0x80000000, driven by
   `io.reset_vector`). Note: it is the reset vector, not 0.

2. The BPU looks that PC up in the FTB. The FTB is empty, so the lookup
   returns `hit = false`. The BPU has no record of any branch in this
   block - it cannot invent a branch it has never seen.

3. On a miss the BPU makes the safe default prediction: no taken
   branch, run straight through.
   - `br_taken_mask` = all zeros
   - predicted next PC = fall-through = `pc + FetchWidth*4`
     (`FullBranchPrediction.allTarget`, the not-hit case)
   - `cfiIndex.valid` = false (nothing taken)

4. The BPU keeps walking forward: next `s0_pc` = fall-through address,
   look up, miss again, predict fall-through again. Right after reset it
   marches sequentially through memory, guessing "no branches," because
   everything misses in the cold FTB. These guesses stream into the FTQ
   and on to the IFU.

5. The truth arrives from the IFU. The IFU fetches the real bytes and
   predecodes them (the first stage that actually decodes). If a block
   really did contain a taken branch:
   - Correction: the BPU guessed fall-through but the branch was taken
     -> misprediction. The front end flushes the wrong-path fetches and
     snaps `s0_pc` to the correct target via `redirect`. This costs a
     few cycles - the warm-up penalty.
   - Learning: the predecode result (`pdWb`) goes to the FTQ, which
     builds an FTB entry ("branch at offset K, target = X") via
     `FTBEntryGen` and writes it into the FTB through `update`.

6. Next time the BPU predicts that PC, the FTB hits. It now predicts the
   branch taken/target directly - no misprediction, no redirect, full
   speed.

Summary: an FTB miss defaults to a plain sequential (fall-through)
prediction. If that guess is wrong once the bytes are decoded, the front
end pays a redirect to correct course and updates the FTB so the same
miss does not recur. This is the fast loop (make the guess) being taught
by the slow loop (predecode / commit) - see "Dataflow: the two loops".

---

## SystemVerilog structures

Faithful, re-structured translation of the bundles above. Field order
is illustrative (grouped for readability); it is not bit-exact to the
FIRRTL emission. Complex nested history state in CfiUpdateInfo
(folded_hist, afhob) is not expanded here - it is opaque predictor
internal state; see note at the end.

```systemverilog
package fe_pkg;

  // --------------------------------------------------------------------
  // Parameters (default XiangShan config). Override for wider machines.
  // --------------------------------------------------------------------
  localparam int VADDR_W          = 39;
  localparam int PREDICT_WIDTH    = 16;
  localparam int OFFSET_W         = $clog2(PREDICT_WIDTH);   // 4
  localparam int FTQ_SIZE         = 64;
  localparam int FTQ_IDX_W        = $clog2(FTQ_SIZE);        // 6
  localparam int NUM_BR           = 2;
  localparam int NUM_BR_SLOT      = NUM_BR - 1;              // 1
  localparam int TOTAL_SLOT       = NUM_BR_SLOT + 1;         // 2
  localparam int NUM_DUP          = 4;
  localparam int RAS_SIZE         = 16;
  localparam int RAS_SSP_W        = $clog2(RAS_SIZE);        // 4
  localparam int RAS_CTR_W        = 3;
  localparam int RAS_SPEC_SIZE    = 32;
  localparam int RAS_PTR_W        = $clog2(RAS_SPEC_SIZE);   // 5
  localparam int HISTORY_LENGTH   = 256;
  localparam int CGH_PTR_W        = $clog2(HISTORY_LENGTH);  // 8
  localparam int UBTB_GHR_LEN     = 4;
  localparam int MAX_META_LEN     = 512;
  localparam int BR_OFFSET_LEN    = 12;
  localparam int JMP_OFFSET_LEN   = 20;
  localparam int TAR_STAT_SZ      = 2;
  localparam int ROB_IDX_W        = 8;   // ROB pointer value width
  localparam int NUM_STALL_REASON = 16;  // TopDownCounters.NumStallReasons
  localparam int FTB_SIZE         = 2048;
  localparam int FTB_WAYS         = 4;
  localparam int FTB_WAY_W        = $clog2(FTB_WAYS);       // 2
  localparam int FTB_TAG_W        = 20;

  // --------------------------------------------------------------------
  // Circular queue pointers: { flag, value }
  // --------------------------------------------------------------------
  typedef struct packed {
    logic                    flag;
    logic [FTQ_IDX_W-1:0]    value;
  } ftq_ptr_t;

  typedef struct packed {
    logic                    flag;
    logic [RAS_PTR_W-1:0]    value;
  } ras_ptr_t;

  typedef struct packed {
    logic                    flag;
    logic [CGH_PTR_W-1:0]    value;
  } cgh_ptr_t;

  typedef struct packed {
    logic                    flag;
    logic [ROB_IDX_W-1:0]    value;
  } rob_ptr_t;

  // ValidUndirectioned(UInt) : a valid bit plus an in-block offset
  typedef struct packed {
    logic                    valid;
    logic [OFFSET_W-1:0]     bits;
  } valid_offset_t;

  // --------------------------------------------------------------------
  // PreDecodeInfo (8 bit)
  // --------------------------------------------------------------------
  typedef struct packed {
    logic                    valid;
    logic                    is_rvc;
    logic [1:0]              br_type;   // notCFI/branch/jal/jalr
    logic                    is_call;
    logic                    is_ret;
  } predecode_info_t;

  // --------------------------------------------------------------------
  // FTB slots. Br slots use BR_OFFSET_LEN lower bits; the tail slot
  // uses JMP_OFFSET_LEN, so they are distinct packed types.
  // --------------------------------------------------------------------
  typedef struct packed {
    logic [OFFSET_W-1:0]        offset;   // in-block branch offset
    logic                       sharing;  // shared by a cond branch
    logic                       valid;    // slot valid
  } ftb_slot_ftqmem_t;                     // compact FTQ-stored subset

  typedef struct packed {
    logic [OFFSET_W-1:0]        offset;
    logic                       sharing;
    logic                       valid;
    logic [BR_OFFSET_LEN-1:0]   lower;    // target low bits
    logic [TAR_STAT_SZ-1:0]     tar_stat; // FIT/OVF/UDF
  } ftb_br_slot_t;

  typedef struct packed {
    logic [OFFSET_W-1:0]        offset;
    logic                       sharing;
    logic                       valid;
    logic [JMP_OFFSET_LEN-1:0]  lower;    // wider target low bits
    logic [TAR_STAT_SZ-1:0]     tar_stat;
  } ftb_tail_slot_t;

  // --------------------------------------------------------------------
  // FTBEntry
  // --------------------------------------------------------------------
  typedef struct packed {
    logic                              valid;
    ftb_br_slot_t [NUM_BR_SLOT-1:0]    br_slots;
    ftb_tail_slot_t                    tail_slot;
    logic [OFFSET_W-1:0]               pft_addr;  // fall-through offset
    logic                              carry;
    logic                              is_call;
    logic                              is_ret;
    logic                              is_jalr;   // is_jal = !is_jalr
    logic                              last_may_be_rvi_call;
    logic [NUM_BR-1:0]                 always_taken;
  } ftb_entry_t;

  // Compact FTQ-stored FTB entry (FTBEntry_FtqMem)
  typedef struct packed {
    ftb_slot_ftqmem_t [NUM_BR_SLOT-1:0] br_slots;
    ftb_slot_ftqmem_t                   tail_slot;
    logic                               is_call;
    logic                               is_ret;
    logic                               is_jalr;
  } ftb_entry_ftqmem_t;

  // What the FTB SRAM actually holds: entry + tag
  typedef struct packed {
    ftb_entry_t              entry;
    logic [FTB_TAG_W-1:0]    tag;      // matched against block PC
  } ftb_entry_with_tag_t;

  // Per-lookup FTB metadata (carried inside last_stage_meta)
  typedef struct packed {
    logic [FTB_WAY_W-1:0]    write_way; // hit way, or alloc way on miss
    logic                    hit;       // lookup hit the FTB
    // pred_cycle (UInt64) omitted - non-FPGA debug only
  } ftb_meta_t;

  // --------------------------------------------------------------------
  // SpeculativeInfo and its FTQ SRAM entry variant
  // --------------------------------------------------------------------
  typedef struct packed {
    cgh_ptr_t                hist_ptr; // circular global-history ptr
    logic [RAS_SSP_W-1:0]    ssp;      // RAS spec stack pointer
    logic [RAS_CTR_W-1:0]    sctr;     // RAS spec repeat counter
    ras_ptr_t                tosw;     // RAS top-of-stack write ptr
    ras_ptr_t                tosr;     // RAS top-of-stack read ptr
    ras_ptr_t                nos;      // RAS next-on-stack ptr
    logic [VADDR_W-1:0]      top_addr; // RAS top return address
  } spec_info_t;

  typedef struct packed {
    cgh_ptr_t                hist_ptr;
    logic [RAS_SSP_W-1:0]    ssp;
    logic [RAS_CTR_W-1:0]    sctr;
    ras_ptr_t                tosw;
    ras_ptr_t                tosr;
    ras_ptr_t                nos;
    logic [VADDR_W-1:0]      top_addr;
    logic [NUM_BR-1:0]       sc_disagree; // sim/debug only
  } ftq_redirect_sram_entry_t;

  // --------------------------------------------------------------------
  // Top-down perf counters
  // --------------------------------------------------------------------
  typedef struct packed {
    logic [NUM_STALL_REASON-1:0] reasons;
    logic [OFFSET_W-1:0]         stall_width;
  } frontend_topdown_bundle_t;

  // --------------------------------------------------------------------
  // Direction 1: BPU -> FTQ prediction payload
  // --------------------------------------------------------------------
  typedef struct packed {
    logic [NUM_BR-1:0]                    br_taken_mask;
    logic [TOTAL_SLOT-1:0]                slot_valids;
    logic [TOTAL_SLOT-1:0][VADDR_W-1:0]   targets;
    logic [VADDR_W-1:0]                   jalr_target;
    logic [TOTAL_SLOT-1:0][OFFSET_W-1:0]  offsets;
    logic [VADDR_W-1:0]                   fall_through_addr;
    logic                                 fall_through_err;
    logic                                 multi_hit;
    logic                                 is_jal;
    logic                                 is_jalr;
    logic                                 is_call;
    logic                                 is_ret;
    logic                                 last_may_be_rvi_call;
    logic                                 is_br_sharing;
    logic                                 hit;
    // predCycle (UInt64) omitted - non-FPGA debug only
  } full_branch_prediction_t;

  typedef struct packed {
    logic [NUM_DUP-1:0][VADDR_W-1:0]        pc;
    logic [NUM_DUP-1:0]                     valid;
    logic [NUM_DUP-1:0]                     has_redirect;
    ftq_ptr_t                               ftq_idx;
    full_branch_prediction_t [NUM_DUP-1:0]  full_pred;
  } branch_prediction_bundle_t;

  // BpuToFtqBundle == BranchPredictionResp
  typedef struct packed {
    branch_prediction_bundle_t  s1;
    branch_prediction_bundle_t  s2;
    branch_prediction_bundle_t  s3;
    logic                       s1_uftb_hit;
    logic                       s1_uftb_has_indirect;
    logic                       s1_ftb_close_req;
    logic [MAX_META_LEN-1:0]    last_stage_meta;
    ftq_redirect_sram_entry_t   last_stage_spec_info;
    ftb_entry_t                 last_stage_ftb_entry;
    frontend_topdown_bundle_t   topdown_info;
  } branch_prediction_resp_t;

  // --------------------------------------------------------------------
  // Direction 2: FTQ -> BPU control-flow update info
  // --------------------------------------------------------------------
  typedef struct packed {
    logic [VADDR_W-1:0]      pc;
    predecode_info_t         pd;
    logic [RAS_SSP_W-1:0]    ssp;
    logic [RAS_CTR_W-1:0]    sctr;
    ras_ptr_t                tosw;
    ras_ptr_t                tosr;
    ras_ptr_t                nos;
    logic [VADDR_W-1:0]      top_addr;
    // folded_hist / afhob omitted - nested folded-history state.
    // Represent as opaque bit vectors if a flat port is required.
    logic [NUM_BR:0]         last_br_num_oh;  // numBr+1
    logic [UBTB_GHR_LEN-1:0] ghr;
    cgh_ptr_t                hist_ptr;
    logic [NUM_BR-1:0][9:0]  spec_cnt;        // Vec(numBr, UInt(10))
    logic                    br_hit;
    logic                    jr_hit;
    logic                    sc_hit;
    logic                    pred_taken;
    logic [VADDR_W-1:0]      target;
    logic                    taken;
    logic                    is_mispred;
    logic [$clog2(NUM_BR):0] shift;           // log2Ceil(numBr)+1
    logic                    add_into_hist;
  } cfi_update_info_t;

  typedef struct packed {
    logic                    is_rvc;
    rob_ptr_t                rob_idx;
    ftq_ptr_t                ftq_idx;
    logic [OFFSET_W-1:0]     ftq_offset;
    logic                    level;         // RedirectLevel
    logic                    interrupt;
    cfi_update_info_t        cfi_update;
    ftq_ptr_t                st_ftq_idx;
    logic [OFFSET_W-1:0]     st_ftq_offset;
    logic                    debug_is_ctrl;
    logic                    debug_is_mem_vio;
  } redirect_t;

  // BranchPredictionRedirect: Redirect + BPU bubble bit
  typedef struct packed {
    redirect_t               redirect;
    logic                    btb_miss_bubble;
  } branch_prediction_redirect_t;

  typedef struct packed {
    logic [VADDR_W-1:0]        pc;
    spec_info_t                spec_info;
    ftb_entry_t                ftb_entry;
    valid_offset_t             cfi_idx;
    logic [NUM_BR-1:0]         br_taken_mask;
    logic [NUM_BR-1:0]         br_committed;
    logic                      jmp_taken;
    logic [NUM_BR:0]           mispred_mask;  // numBr+1
    logic                      pred_hit;
    logic                      false_hit;
    logic [NUM_BR-1:0]         new_br_insert_pos;
    logic                      old_entry;
    logic [MAX_META_LEN-1:0]   meta;
    logic [VADDR_W-1:0]        full_target;
    logic [1:0]                from_stage;
    logic [HISTORY_LENGTH-1:0] ghist;
  } branch_prediction_update_t;

  // --------------------------------------------------------------------
  // Top-level IO payloads. Decoupled/Valid wrappers shown explicitly.
  // --------------------------------------------------------------------
  // BpuToFtqIO: resp = Decoupled(BpuToFtqBundle)
  typedef struct packed {
    logic                       valid;   // resp_valid  (BPU -> FTQ)
    branch_prediction_resp_t    bits;    // resp_bits
    // ready flows FTQ -> BPU as a separate scalar port
  } bpu_to_ftq_resp_t;

  // FtqToBpuIO
  typedef struct packed {
    logic                          redirect_valid;
    branch_prediction_redirect_t   redirect_bits;
    logic                          update_valid;
    branch_prediction_update_t     update_bits;
    ftq_ptr_t                      enq_ptr;
    logic                          redirct_from_ifu;
  } ftq_to_bpu_io_t;

endpackage : fe_pkg
```

---

## Notes for an 8-wide (Pacino) port

- XiangShan predicts 2 branches per fetch block (`numBr = 2`: one
  dedicated br slot plus one shared tail slot). For an 8-wide machine
  you will likely raise `numBr` / `totalSlot` and widen the FTB slot
  vectors; this ripples through nearly every structure above
  (full_branch_prediction_t, ftb_entry_t, cfi_update_info_t masks,
  branch_prediction_update_t masks).
- The `numDup` fanout duplication is a physical-design timing artifact.
  The optimizer prunes it in RTL, so `full_pred_3` is not semantically
  special - it is just the surviving copy. A fresh design can set
  `NUM_DUP = 1` and add duplication later only where timing needs it.
- `folded_hist` and `afhob` in CfiUpdateInfo are nested folded-history
  bundles (per-table compressed history plus ahead-pipelined oldest
  bits). They are opaque predictor-internal state; size them from the
  final TAGE/SC/ITTAGE table geometry, or carry them as flat bit
  vectors between FTQ and BPU.
- `RedirectLevel` is modeled as a single bit here (flush-itself vs
  flush-after). Confirm against the backend redirect encoding when the
  backend interface is defined.

---

## Control model - who initiates a prediction

There is NO FTQ -> BPU structure that requests a prediction. This is
the single most important architectural fact about this front end, and
it is easy to miss when reading the bundle tables above in isolation.

The BPU is free-running and self-steering. It holds its own next-PC
register and launches a fresh prediction essentially every cycle on its
own initiative. The FTQ never asks for a prediction - it only throttles
the BPU (backpressure) and corrects it (redirect). None of the four
FtqToBpuIO members (enq_ptr, redirect, update, redirctFromIFU) is a
prediction request.

This is the decoupled front end: BPU leads, FTQ buffers, IFU follows.
The BPU runs ahead of the IFU, emitting a stream of predicted fetch
blocks into the FTQ, which is the elastic buffer between them.

### Dataflow: the two loops

There are two loops, not one ring. The FTB is a table read INSIDE the
BPU (not a stage between IFU and BPU), and the IFU is downstream of the
BPU (not upstream).

Loop 1 - prediction (fast, every cycle, BPU-internal):

```
  +-------------------------------------------------+
  |                 BPU (Predictor)                 |
  |                                                 |
  |   s0_pc --> [ FTB, uFTB, TAGE, SC, ITTAGE,      |
  |     ^          RAS ] --> prediction             |
  |     |                        |                  |
  |     +----- npcGen (s1 target) <-----------------+   self-feeds
  +-------------------------------------------------+    next PC
                    |
                    | resp (BranchPredictionResp)
                    | gated by resp.ready  (backpressure, FTQ -> BPU)
                    v
                 [  FTQ  ]   elastic buffer (BPU runs ahead)
                    |
                    | FetchRequest (start PC, ftqIdx, ftqOffset)
                    v
                 [  IFU  ] -> ICache -> IBuffer -> backend
```

The steady-state loop is BPU -> BPU: the predicted target becomes the
next block's start PC. The IFU never reads the BPU or FTB here.

Loop 2 - training / correction (slow, on new branch or mispredict):

```
  [ IFU predecode ]   first stage that truly decodes the bytes
        |
        | pdWb (PredecodeWritebackBundle: real branch layout)
        v
  [  FTQ  ] --FTBEntryGen--> build / update an FTBEntry
        |
        +-- update   (BranchPredictionUpdate.ftb_entry) --> FTB write
        +-- redirect (on mispredict) --------------------> resteer s0_pc
        |
        v
  [  BPU  ]  FTB + directional predictors trained; s0_pc snapped
```

This is the only path where information flows from the IFU back toward
the FTB, and it happens at predecode / commit time, not per prediction.
Backend commit does the final training of the FTB and the directional
predictors.

One-line summary of the full ring:

```
  forward (predict): BPU (reads FTB) -> FTQ -> IFU
  backward (train):  IFU -> FTQ -> BPU.update / redirect -> FTB
```

### What initiates a prediction: s0_pc + s0_fire

The BPU keeps its own PC (`BPU.scala:290`, s0_pc_dup / s0_pc_reg_dup).
Each cycle it can fire a fresh lookup at that PC:

```
predictors.io.in.valid      := s0_fire_dup(0)   // launch a prediction
predictors.io.in.bits.s0_pc := s0_pc_dup        // at the BPU's own PC
```
(`BPU.scala:362-363`)

The next PC is selected by a priority mux, npcGen (`BPU.scala:323`,
`:913`), whose inputs are effectively all internal:

| Source          | Meaning                                   | Ref        |
|-----------------|-------------------------------------------|------------|
| stallPC         | Hold current PC when stalled              | BPU.sv:487 |
| s1_target       | BPU's own stage-1 predicted target        | BPU.sv:544 |
| s2_target       | BPU's own stage-2 self-redirect target    | BPU.sv:647 |
| s3_target       | BPU's own stage-3 self-redirect target    | BPU.sv:733 |
| redirect_target | FTQ redirect cfiUpdate.target (correction)| BPU.sv:892 |
| reset_vector    | Startup PC                                | BPU.sv:293 |

In steady state the BPU feeds its own predicted target (s1_target) back
into its own PC and walks forward autonomously.

### What the FTQ actually sends back: backpressure, not a request

The signal that most resembles a request is the resp.ready bit of the
BPU -> FTQ Decoupled channel - and it flows FTQ -> BPU. The BPU only
advances when the FTQ can accept the result:

```
s1_fire := s1_valid && s2_components_ready && s2_ready &&
           io.bpu_to_ftq.resp.ready
```
(`BPU.scala:401`)

When the FTQ fills (its bpuPtr catches the commit pointer) it deasserts
resp.ready, s0_fire / s1_fire drop, and the BPU stalls by re-selecting
stallPC. The control model is credit/ready backpressure, not
request/grant. The FTQ says "I have room" (ready), never "predict
address X".

### The only time the FTQ steers the BPU

Two events, both corrections rather than requests:

- redirect (`BPU.scala:376`, do_redirect): on a mispredict/flush the
  FTQ hands the BPU the corrected cfiUpdate.target, which wins the
  npcGen mux because the redirect also asserts s1_flush / s2_flush /
  s3_flush (`BPU.scala:383`) to invalidate the in-flight speculative
  stages. This resets the free-running PC onto the correct path.
- update: commit-time training of FTB/TAGE/SC/ITTAGE/RAS. No effect on
  when predictions happen.

### Implication for an 8-wide (Pacino) port

Do not expect (or design) a valid/address "predict-request" bundle -
that is the in-order, IFU-leads-BPU shape and Kunminghu deliberately
inverts it. Keep the BPU self-clocked: it generates fetch-block targets
at its own rate, gated only by FTQ resp.ready, and is resteered only by
redirect. A request-driven BPU serializes prediction behind fetch and
loses the run-ahead that the decoupled front end exists to provide.
