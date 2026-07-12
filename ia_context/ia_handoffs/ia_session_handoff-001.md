# Session resume: XiangShan Kunminghu front-end interface study

Purpose: capture context so this work can be resumed in a later session.

## Goal

Understand and document the XiangShan Kunminghu (3rd gen) front-end
interfaces, as reference for the Pacino 8-wide OoO RISC-V RVA23 design.
Focus so far: FTQ <-> BPU and FTQ <-> IFU communication structures, the
FTB, and the prediction/training control flow.

## Source material (local copies)

- Scala/Chisel: `./ia_xiangshan/scala/src/main/scala/xiangshan/`
  - `frontend/FrontendBundle.scala` - prediction/update bundles
  - `frontend/NewFtq.scala`         - FTQ IO, FTQ-stored entries
  - `frontend/BPU.scala`            - Predictor, BpuToFtqIO, s0_pc/npcGen
  - `frontend/FTB.scala`            - FTB entry, slots, FTB module
  - `frontend/IFU.scala`            - IfuToFtqIO, IFU top IO
  - `frontend/PreDecode.scala`      - PreDecodeInfo, PredChecker
  - `Bundle.scala`                  - Redirect, CfiUpdateInfo
  - `backend/fu/Branch.scala`       - BranchModule (taken/mispredict)
  - `backend/fu/wrapper/BranchUnit.scala` - fills cfiUpdate on redirect
- RTL (Verilator SystemVerilog): `./ia_xiangshan/rtl/`
  (`Predictor.sv`, `Ftq.sv`, `FTB.sv`, `FTBBank.sv`, `FauFTB.sv`,
  `FTBEntryGen.sv`, etc.)

## Deliverables produced this session

- `fe.md`  - FTQ <-> BPU interface. Field tables for all bundles,
  parameterized SystemVerilog `typedef struct packed` package
  (`fe_pkg`), FTB section, control-model section (who initiates a
  prediction), and a two-loops dataflow diagram. NOTE: some tables in
  this file were wrapped in ``` fences by the user/linter; leave as is.
- `ifu_ftq.md` - FTQ <-> IFU interface. Reuses `fe_pkg` types, defines
  `ifu_ftq_pkg` for the IFU/FTQ-specific structs. Adjacent structures
  (FTQ->ICache, FetchToIBuffer) noted but not fully expanded.
- `cold_start.md` - FTB-miss (cold start) behavior, scoped to
  conditional branches. Rewritten in plain engineering phrasing.

## Key facts established (verified against source)

Control model:
- There is NO FTQ->BPU structure that requests a prediction. The BPU is
  free-running: it holds its own `s0_pc` and launches a prediction each
  cycle (`BPU.scala` s0_pc / s0_fire / npcGen priority mux).
- The FTQ throttles the BPU via `resp.ready` (Decoupled backpressure on
  the BPU->FTQ resp channel), and steers it only via `redirect`
  (correction) and `update` (training). `enq_ptr` is bookkeeping.
- Dataflow is two loops: fast prediction loop (BPU -> FTQ -> IFU, FTB
  read internally) and slow training loop (IFU predecode -> FTQ ->
  BPU.update / redirect -> FTB).

FTB:
- FTB lives inside the BPU (a PC-indexed set-assoc table), not a stage
  between IFU and BPU. Default: FtbSize 2048, 4-way, 512 sets, 20b tag.
- An FTB entry stores each branch as an in-block `offset`, not a full
  PC. Branch PC = block_start + offset*2 (instOffsetBits=1, RVC).
  Targets stored as `lower` bits + 2b `tarStat` (FIT/OVF/UDF).
- FTB is trained from IFU predecode via pdWb -> FTBEntryGen -> update.

Cold start / mispredict (conditional branches):
- Not-taken is the default. On FTB miss the block is predicted
  fall-through; nothing is marked taken; per-instruction
  `pred_taken` = `ftqOffset(i).valid` = 0 (`IBuffer.scala:75`).
- Identifying an instruction as a branch is a (pre)decode function,
  independent of the BPU. Predecode sets `PreDecodeInfo.brType` in the
  frontend; the FTB miss does not stop branch identification.
- A conditional branch's direction is resolved at execute in the branch
  functional unit: `taken` from operands, `mispredict = pred_taken ^
  taken` (`Branch.scala:50`). Redirect carries `taken`, `predTaken`,
  `isMisPred`, `target` in cfiUpdate (`BranchUnit.scala:50-52`).
- Redirect is gated on `isMisPred` (`CtrlBlock.scala:194`): a correctly
  predicted branch produces no flush.

## Terminology note (user correction, apply going forward)

Do not use "backend" loosely to mean "the decoder." Decode is a
distinct step from execution. Use explicit stage names:
- predecode (IFU, frontend) and decode - identify the instruction /
  branch type
- execute (branch functional unit) - resolve direction and mispredict
XiangShan's repo places DecodeStage under the `backend/` package tree;
that is repo layout, not the architectural frontend/backend boundary.

## Style / working preferences observed this session

- Engineering phrasing only. No asides, no intensifiers, no rhetorical
  framing (e.g. avoid "it cannot invent a branch it has never seen" or
  "this explains why ..."). State facts and signal values.
- Be precise about pipeline stages; do not conflate them.
- Cite `file:line` for claims where practical; verify against source
  rather than assert from memory.
- Project doc style (from CLAUDE.md): 80-col max, 2-space indent, ASCII
  only, use `->` not arrows, `-` for bullets.

## Open / possible next steps (not yet done)

- FTQ <-> backend interface (`FtqToCtrlIO`) writeup, if wanted.
- Fold the two cold-start writeups into one source of truth: a shorter
  cold-start section currently also exists inside `fe.md`; `cold_start.md`
  is the fuller conditional-branch version. Decide which is canonical.
- Optionally merge fe.md + ifu_ftq.md into one front-end spec with a
  single shared SV package.
- Widen structures from XiangShan numBr=2 to the Pacino 8-wide target
  (numBr/totalSlot, FTB slot vectors, PredictWidth) - noted in each
  file's "8-wide port" notes but not implemented.
- Expand adjacent structures in ifu_ftq.md (FTQ->ICache, FetchToIBuffer)
  to full field tables + SV if needed.

## Not addressed this session

- Directional predictors internals (TAGE/SC/ITTAGE/RAS) beyond their
  role in the interface. RAS bug patterns are in prior memory
  (feedback_ras_bugs). ITTAGE project context in memory
  (project_ittage).

## Context to load

Load this context and review in detail. Each file has an intro section
which summarizes the contents and/or purpose

@ia_context/c.md
@ia_context/cold_start.md
@ia_context/fe.md
@ia_context/fe_qaa.md
@ia_context/ifu_ftq.md

