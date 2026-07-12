```
 FILE:    ifu_ftq.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-07-08
 CONTACT: Jeff Nye
```

# Intro/Front-End FTQ <-> IFU Interface (XiangShan Kunminghu)

This document captures the structures used to communicate between the
Fetch Target Queue (FTQ) and the Instruction Fetch Unit (IFU) in the
XiangShan Kunminghu (third generation) front end, followed by
SystemVerilog `typedef struct packed` translations.

It is a companion to `fe.md` (the FTQ <-> BPU interface) and reuses the
types defined there (`fe_pkg`): `ftq_ptr_t`, `valid_offset_t`,
`predecode_info_t`, `frontend_topdown_bundle_t`, and
`branch_prediction_redirect_t`.

Source of truth (local copies):
- Scala/Chisel: `./ia_xiangshan/scala/src/main/scala/xiangshan/`
  - `frontend/IFU.scala`             - IfuToFtqIO, IFU top IO
  - `frontend/NewFtq.scala`          - FtqToIfuIO, BpuFlushInfo, FTQ IO
  - `frontend/FrontendBundle.scala`  - FetchRequestBundle,
                                       PredecodeWritebackBundle
  - `frontend/PreDecode.scala`       - PreDecodeInfo
- RTL (Verilator SystemVerilog): `./ia_xiangshan/rtl/Ftq.sv` (IFU RTL
  is emitted alongside; bundles are flattened as in fe.md)

Note on the RTL: as with the BPU interface, the Chisel bundles do NOT
survive as SystemVerilog structs. FIRRTL/Verilator flatten every field
into a scalar port named by its dotted path, e.g.
`io_toIfu_req_bits_nextStartAddr` or `io_fromIfu_pdWb_bits_misOffset_*`.
The `typedef struct packed` versions below are a faithful,
re-structured translation.

---

## Top-level interface

The IFU wraps both directions in a `FtqInterface`:

```
class FtqInterface {
  val fromFtq = Flipped(FtqToIfuIO)  // FTQ -> IFU
  val toFtq   = IfuToFtqIO           // IFU -> FTQ
}

FtqToIfuIO {                         // FTQ -> IFU
  req              : Decoupled(FetchRequestBundle)
  redirect         : Valid(BranchPredictionRedirect)
  topdown_redirect : Valid(BranchPredictionRedirect)
  flushFromBpu     : BpuFlushInfo
}

IfuToFtqIO {                         // IFU -> FTQ
  pdWb : Valid(PredecodeWritebackBundle)
}
```

The interface is deliberately asymmetric. The FTQ drives the IFU with
fetch requests, redirects, and BPU-flush hints. The IFU sends back a
single predecode writeback per fetch block; the FTQ derives any
IFU-originated redirect internally from that writeback (there is no
separate IFU->FTQ redirect port).

Adjacent (not FTQ<->IFU, but part of the same fetch handshake): the FTQ
also drives the ICache (`FtqToICacheIO`) and prefetcher
(`FtqToPrefetchIO`), and the IFU's `req.ready` is gated on
`icacheReady`. The IFU forwards decoded instructions to the IBuffer via
`FetchToIBuffer`. These are documented briefly at the end.

---

## Parameters

Same parameter set as `fe.md`. The ones used here:

| Parameter    | Default | Meaning                               |
|--------------|---------|---------------------------------------|
| VAddrBits    | 39      | Virtual address width (Sv39, no H)    |
| PredictWidth | 16      | Prediction/fetch-block width in slots |
| FtqSize      | 64      | FTQ entries (-> FtqPtr value = 6 b)   |
| instOffsetBits | 1     | Instruction offset LSBs (RVC = 16 b)  |

---

## Direction 1 - FTQ -> IFU: `FtqToIfuIO`

### req : Decoupled(FetchRequestBundle)

The fetch request handshake. `req.ready` is asserted by the IFU only
when its F1 stage is free AND the ICache is ready.

#### FetchRequestBundle

| Field         | Type                    | Description                                            |
|---------------|-------------------------|--------------------------------------------------------|
| startAddr     | VAddr                   | Start PC of the fetch block (fast/timing-critical path)|
| nextlineStart | VAddr                   | Start of the next cache line (for cross-line fetch)    |
| nextStartAddr | VAddr                   | Predicted next-block start (fall-through or target)    |
| ftqIdx        | FtqPtr                  | FTQ slot that owns this fetch block                    |
| ftqOffset     | Valid(UInt)             | Taken-branch offset in block; valid if a taken CFI     |
| topdown_info  | FrontendTopDownBundle   | Top-down perf stall-reason counters                    |

Helper: `crossCacheline = startAddr(blockOffBits-1) === 1` -> the block
spans two cache lines (drives double-line fetch).

### redirect : Valid(BranchPredictionRedirect)

Flush + resteer the IFU pipeline. Same `BranchPredictionRedirect`
structure documented in `fe.md` (Redirect + CfiUpdateInfo + BPU bubble
bits). The IFU uses `level` (RedirectLevel.flushItself) to decide
whether the redirecting block itself is flushed, and reads the
bubble-classification helpers (ControlBTBMissBubble, TAGEMissBubble,
SCMissBubble, ITTAGEMissBubble, RASMissBubble) via topdown_redirect.

### topdown_redirect : Valid(BranchPredictionRedirect)

A second copy of the redirect used purely to drive the IFU's top-down
performance-counter accounting (which stall-reason bucket to charge).
Structurally identical to `redirect`.

### flushFromBpu : BpuFlushInfo

Late-stage BPU redirect hints. When a later BPU stage (s2 or s3)
overturns an earlier prediction, the IFU must drop in-flight fetch
requests for FTQ entries at or after the flushing pointer.

#### BpuFlushInfo

| Field | Type            | Description                                            |
|-------|-----------------|--------------------------------------------------------|
| s2    | Valid(FtqPtr)   | BPU stage-2 redirect target FTQ pointer                |
| s3    | Valid(FtqPtr)   | BPU stage-3 redirect target FTQ pointer                |

Helper methods:
- `shouldFlushByStage2(idx)` = `s2.valid && !isAfter(s2.bits, idx)`
- `shouldFlushByStage3(idx)` = `s3.valid && !isAfter(s3.bits, idx)`

i.e. flush a fetch whose FTQ index is at or behind the redirecting
stage's pointer.

---

## Direction 2 - IFU -> FTQ: `IfuToFtqIO`

### pdWb : Valid(PredecodeWritebackBundle)

One predecode writeback per fetch block. After the IFU predecodes the
fetched bytes it reports back the actual branch layout and any
predecode-detected mispredict. The FTQ uses this to (a) build/repair
the FTB entry (`Ftq_pd_Entry.fromPdWb`) and (b) generate an
IFU-originated redirect when predecode disagrees with the prediction.

#### PredecodeWritebackBundle

| Field      | Type                       | Description                                            |
|------------|----------------------------|--------------------------------------------------------|
| pc         | Vec(PredictWidth, VAddr)   | PC of each instruction slot in the block               |
| pd         | Vec(PredictWidth, PreDecodeInfo) | Predecode info per slot (br/jal/jalr/call/ret, rvc) |
| ftqIdx     | FtqPtr                     | FTQ slot being written back                            |
| ftqOffset  | UInt(log2 PredictWidth)    | Offset of the predicted taken branch                   |
| misOffset  | Valid(UInt)                | Offset of a predecode-detected mispredict (if any)     |
| cfiOffset  | Valid(UInt)                | Offset of the actual control-flow instruction          |
| target     | VAddr                      | Corrected branch target from predecode                 |
| jalTarget  | VAddr                      | Directly-computed JAL target                           |
| instrRange | Vec(PredictWidth, Bool)    | Which slots hold valid in-range instructions           |

#### PreDecodeInfo (8 bits) - see fe.md

| Field  | Type    | Description                          |
|--------|---------|--------------------------------------|
| valid  | Bool    | Predecode valid                      |
| isRVC  | Bool    | Compressed instruction               |
| brType | UInt(2) | notCFI / branch / jal / jalr         |
| isCall | Bool    | Call                                 |
| isRet  | Bool    | Return                               |

---

## SystemVerilog structures

These reuse the package `fe_pkg` from `fe.md` for shared types. Only
the FTQ<->IFU-specific structures are defined here. Field order is
illustrative (grouped for readability), not bit-exact to the FIRRTL
emission.

```systemverilog
package ifu_ftq_pkg;

  import fe_pkg::*;   // ftq_ptr_t, valid_offset_t, predecode_info_t,
                      // frontend_topdown_bundle_t,
                      // branch_prediction_redirect_t, VADDR_W,
                      // PREDICT_WIDTH, OFFSET_W

  // --------------------------------------------------------------------
  // Valid(FtqPtr) helper for BpuFlushInfo
  // --------------------------------------------------------------------
  typedef struct packed {
    logic       valid;
    ftq_ptr_t   bits;
  } valid_ftq_ptr_t;

  // --------------------------------------------------------------------
  // Direction 1: FTQ -> IFU
  // --------------------------------------------------------------------

  // FetchRequestBundle (req.bits of FtqToIfuIO)
  typedef struct packed {
    logic [VADDR_W-1:0]        start_addr;      // fetch block start PC
    logic [VADDR_W-1:0]        nextline_start;  // next cache line start
    logic [VADDR_W-1:0]        next_start_addr; // predicted next block
    ftq_ptr_t                  ftq_idx;         // owning FTQ slot
    valid_offset_t             ftq_offset;      // taken-branch offset
    frontend_topdown_bundle_t  topdown_info;    // perf counters
  } fetch_request_bundle_t;

  // BpuFlushInfo (flushFromBpu)
  typedef struct packed {
    valid_ftq_ptr_t  s2;   // BPU stage-2 redirect pointer
    valid_ftq_ptr_t  s3;   // BPU stage-3 redirect pointer
  } bpu_flush_info_t;

  // FtqToIfuIO (IFU sees this Flipped as 'fromFtq').
  // req is Decoupled: req_valid / req_ready / req_bits. redirect and
  // topdown_redirect are Valid: <name>_valid / <name>_bits.
  typedef struct packed {
    logic                          req_valid;
    fetch_request_bundle_t         req_bits;
    // req_ready flows IFU -> FTQ as a separate scalar port
    logic                          redirect_valid;
    branch_prediction_redirect_t   redirect_bits;
    logic                          topdown_redirect_valid;
    branch_prediction_redirect_t   topdown_redirect_bits;
    bpu_flush_info_t               flush_from_bpu;
  } ftq_to_ifu_io_t;

  // --------------------------------------------------------------------
  // Direction 2: IFU -> FTQ
  // --------------------------------------------------------------------

  // PredecodeWritebackBundle (pdWb.bits of IfuToFtqIO)
  typedef struct packed {
    logic [PREDICT_WIDTH-1:0][VADDR_W-1:0]  pc;          // per-slot PC
    predecode_info_t [PREDICT_WIDTH-1:0]    pd;          // per-slot pd
    ftq_ptr_t                               ftq_idx;     // FTQ slot
    logic [OFFSET_W-1:0]                     ftq_offset;  // taken offset
    valid_offset_t                          mis_offset;  // mispred slot
    valid_offset_t                          cfi_offset;  // actual CFI
    logic [VADDR_W-1:0]                      target;      // corrected tgt
    logic [VADDR_W-1:0]                      jal_target;  // JAL target
    logic [PREDICT_WIDTH-1:0]                instr_range; // valid slots
  } predecode_writeback_bundle_t;

  // IfuToFtqIO ('toFtq'). pdWb is Valid: pdWb_valid / pdWb_bits.
  typedef struct packed {
    logic                          pd_wb_valid;
    predecode_writeback_bundle_t   pd_wb_bits;
  } ifu_to_ftq_io_t;

endpackage : ifu_ftq_pkg
```

---

## Adjacent fetch-datapath structures (not FTQ<->IFU)

Included for context, since the IFU fetch handshake depends on them.
Not expanded to SystemVerilog here.

### FtqToICacheIO / FtqToICacheRequestBundle (FTQ -> ICache)

| Field     | Type                    | Description                          |
|-----------|-------------------------|--------------------------------------|
| pcMemRead | Vec(5, FtqICacheInfo)   | Up to 5 fetch-block address requests |
| readValid | Vec(5, Bool)            | Per-port request valid               |

FtqICacheInfo: `{ startAddr, nextlineStart, ftqIdx }`.

### BpuFlushInfo (also used on FtqToPrefetchIO)

Same `BpuFlushInfo` as above; the prefetcher uses it to drop stale
prefetch requests on a late BPU redirect.

### FetchToIBuffer (IFU -> IBuffer)

The IFU's output of decoded instructions (not back to the FTQ):
`instrs`, `valid`, `enqEnable`, `pd`, `pc`, `foldpc`, `ftqPtr`,
`ftqOffset`, `exceptionType`, `crossPageIPFFix`, `triggered`,
`topdown_info` - all `PredictWidth`-wide.

---

## Notes for an 8-wide (Pacino) port

- The `PredictWidth`-wide vectors in `PredecodeWritebackBundle` (pc, pd,
  instr_range) and in `FetchToIBuffer` scale directly with fetch-block
  width. For sustained 8-wide dispatch, size `PredictWidth` to cover a
  full fetch block plus RVC expansion.
- `FetchRequestBundle` splits a fast path (startAddr / nextlineStart /
  nextStartAddr) from a slow path (ftqIdx / ftqOffset). Preserve that
  split when retiming - the address fields feed the ICache the cycle
  before `req.valid` rises.
- There is no dedicated IFU->FTQ redirect port. Predecode-detected
  mispredicts travel through `pdWb` (misOffset / cfiOffset / target);
  the FTQ synthesizes the redirect. Keep this single-writeback contract
  to avoid an extra IFU->FTQ redirect path.
- `redirect` and `topdown_redirect` are structurally identical copies;
  the second exists only for perf accounting. A cost-reduced design can
  drop `topdown_redirect` if top-down counters are not needed.
