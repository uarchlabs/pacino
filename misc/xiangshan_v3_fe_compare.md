# XiangShan Kunminghu V3 vs Pacino - Frontend Comparison

Date: 2026-11-14

kumminghu-v3 branch vs Pacino HEAD.

## Sources and caveats

- XiangShan: branch `kunminghu-v3` (the repo default branch) of
  https://github.com/OpenXiangShan/XiangShan, path
  src/main/scala/xiangshan/frontend/. Values are case-class defaults;
  DefaultConfig overrides none of the frontend parameters. The repo
  README describes kunminghu-v3 as still evolving rapidly. No V3 design
  document was found, so source only.
- The local xiangshan/ checkout is a Kunminghu V2 layout (FauFTB, FTB,
  NewFtq, WayLookup) and was NOT used.
- XiangShan facts were read through WebFetch summaries. Parameter lines
  came back verbatim; behavioral descriptions are summaries, not a
  line-by-line read.
- Pacino: rtl/core/frontend/, bp_defines_pkg.sv, bp_structs_pkg.sv,
  decode_pkg.sv, planning/arch/*_decisions.md, docs/frontend/.
- The regression was not run for this comparison.

## Headline differences

1. Fetch bandwidth.
   - XiangShan predicts one 64 B block per cycle (two 32 B BTB align
     halves). The FTQ can issue two fetch blocks per cycle to the
     ICache and IFU (`FetchPorts = 2`). The second must be past the
     point of no return (`pnrPtr`), and it is dropped on a bank
     conflict, MMIO, or an ITLB exception.
   - Pacino predicts and fetches one 32 B block per cycle, which is
     8 RVI or 16 RVC instructions. 8 per cycle needs all-RVI code with
     no taken branch before the block end.
2. Instruction prefetch.
   - XiangShan: FTQ-directed prefetch (FDIP). A separate prefetch pipe
     runs up to `PrefetchDepth = 32` blocks ahead, with 10 prefetch
     MSHRs and 4 fetch MSHRs.
   - Pacino: none. `ifu_l1i_req_prefetch` is tied 0. The MSHR reserve
     for prefetches is built, but nothing uses it.
3. BTB organization.
   - XiangShan dropped the FTB for per-branch BTBs: a uBTB (32, fully
     associative), an ahead BTB (1K), and a main BTB (8K) with a
     32-entry victim BTB. Up to 10 branch hits per block.
   - Pacino keeps a block-based FTB: 2K entries, each with 2
     conditional slots, 1 jump slot and a pftAddr, behind a 256-entry
     uBTB.
4. History.
   - XiangShan: TAGE and ITTAGE hash path history (PHR). Each taken
     branch writes a 15-bit hash of (branch PC, target). Length is
     about 530 bits (derived, see Open points). A separate CommonHR
     (GHR 16, backward 8, IMLI) serves the SC only.
   - Pacino: a 256-bit direction GHR feeds TAGE and ITTAGE. The 32-bit
     PHR is used only by SC ST4. PHR in TAGE/ITTAGE is open item HI2.
5. TAGE capacity and history length.
   - XiangShan: 8 tables x 4096 entries, 2-way, 13-bit tags, history up
     to 397 bits.
   - Pacino: T0 base + 4 tagged tables x 2048 entries, 8-bit tags,
     history up to 119 bits.

## Detailed comparison

| Area | XiangShan V3 | Pacino |
|---|---|---|
| Prediction block | 64 B, half-aligned (2 x 32 B BTB align banks), 32 halfword slots | 32 B, any 2 B start, 16 halfword positions; IFU reads 34 B |
| Predictions / cycle | 1 block (2-taken off: `EnableTwoTaken = false`) | 1 block, up to 2 branch slots (`NUM_PRED_SLOTS`) |
| Fetch blocks / cycle | up to 2 | 1 |
| Decode width | 8 | 8 |
| Stage 1 | fall-through predictor, uBTB 32 FA, ahead BTB 1K (4-way, 4 banks), uTAGE (2 x 512), MicroRas | uBTB 256 (4-way), loop predictor 256 x slot |
| Stage 2 | main BTB 8K (4-way, 2 align x 4 internal banks) + victim BTB 32; TAGE fast direction | FTB 2K (4-way, 512 sets), TAGE, ITTAGE, RAS push/pop, LP re-read |
| Stage 3 | full TAGE, SC, ITTAGE, RAS | SC |
| Override compare | s2 compares taken/position/type, not target (protects uRAS target); s3 also compares target | successor PC compared per stage; p2 only on an FTB hit, p3 only when SC changes the result |
| Override cost | s2 1 bubble, s3 2 bubbles (from the flush chain) | p2/p3: 1 cycle to the first new translation request |
| TAGE | 8 x 4096, 2-way, 4 banks, tag 13, ctr 3, u 2; history 4/9/17/29/56/109/211/397 | T0 + T1-T4 x 2048, tag 8, ctr 3, u 2, epoch aging; history 8/13/32/119; one RAM copy per slot |
| SC | 8 tables x 128 sets x 8 ways (path x2, global x2, backward x2, IMLI, bias); ctr 6; 13-bit threshold, init 1130 | 5 untagged tables (512/512/512/512/1024), ctr 6; ST4 IMLI-style; 10-bit threshold, init 10; overrides only in two chooser corners |
| ITTAGE | 256/256/512/512/512, history 4/8/13/16/32, tag 9; 20-bit target + 16-entry region table | same sizes and history lengths; tags 8/8/9/9/11; full VA[58:1] target; falls back to the FTB target on a miss |
| RAS | commit stack 16 + speculative queue 32, 3-bit recursion counter; MicroRas covers s1-s3 | speculative 16 (circular, nos link) + commit 32, 4-bit rctr; TOS read at p0 |
| Loop predictor | none (IMLI in SC instead) | yes, p1 + p2, per-FTQ-entry checkpoint |
| History repair | per-entry meta {phrPtr, low bits, folded history}; folds fully recomputed on redirect | per-entry checkpoint {ghist_ptr, phist_ptr, ckpt_nb}; corrected bundle of up to 2 bits; folds registered (1 cycle stale) |
| FTQ | 64 entries; bpu/pf/fetch/commit/pnr pointers; resolve queue 16 | 64 entries; alloc/xlate/fetch/commit pointers; ~304 b fast entry + ~461 b/slot meta |
| Training | at resolve + s3 fast-train (uBTB, ahead BTB); commit carries RAS/PHR only | at resolve, out of order, per-type predictor set; commit trains the RAS commit stack |
| Resolve ports | `BrhCnt` (likely 3, BJU0-2) + 1 from the IFU | 2, capped by the 2-write-port update queues |
| SRAM port conflicts | per-table write buffers (4), banked single-port SRAMs | arbiters: prediction never delayed; update queues; FTQ hold on starvation; FTB update takes a prediction cycle |
| ICache | 64 KB, 4-way x 256 sets, VIPT (2 alias bits), 8 x 8 B data banks, 2 ports, cross-line fetch, parity on meta and data | 64 KiB, 8-way x 128 sets, PIPT, 2 banks on PA[6], full 512 b line response, 2-cycle hit, no ECC (TD-L1I-5) |
| MSHRs | 4 fetch + 10 prefetch | 16 x 4 targets, non-blocking, out-of-order return by ID |
| Way lookup | prefetch pipe writes WayLookup; main pipe reads data only | tag + data in the main access |
| ITLB | 48 entries, 1 port, no cross-page fetch; misses go through PTW filter/repeater to an L2 TLB | 64 FA, 1-cycle hit, 4K-256T + NAPOT, H-ext, PMP/PMA in the response, second lookup on a page crossing; no L2 TLB, `WALK_DEPTH = 1` |
| Translation | merged into the ICache prefetch pipe | separate IFU pipeline on `xlate_ptr`, 4-deep queue |
| IFU | s0 boundaries -> s1 half-RVI join, predecode -> s2 RVC expand, check -> wb | F0 request -> F1 block queue -> F2 line select -> F3 RVC expand, predecode, check -> WB; 16-entry line buffer reorders L1I returns |
| Predecode redirect | PredChecker (5 fault types); IFU `wbRedirect` port to the FTQ | IFU reports M1-M4, FTQ derives the redirect (no IFU redirect port); 2 cycles |
| IBuffer | 48 entries, 4 write / 8 read banks, enqueue up to 36, bypass up to 12 | 64 entries flat, 16 in (only when 16 free), 8 out all-or-nothing, bypass when empty |
| Backend redirect | `ftqIdxAhead` sent a cycle early hides the FTQ read | 2 cycles; cause and `_self` carried |

## Where Pacino matches or goes beyond XiangShan

- ITTAGE: the same table sizes and history lengths. Pacino stores full
  targets instead of using a region table.
- Shared choices: training at resolve, a 64-entry FTQ with per-entry
  history checkpoints, and 8-wide decode.
- Loop predictor: Pacino has one; XiangShan V3 does not.
- Translation: Pacino runs a separate translation pipeline ahead of
  fetch.
- Page crossing: Pacino handles a page crossing inside one fetch block.
  XiangShan V3 does not support cross-page fetch.
- ITLB: Pacino covers 512G/256T pages and H-extension two-stage entries.

## Doc vs RTL mismatch found

- rtl/core/frontend/ftq/rtl/ftq_npc.sv:400 computes
  `rollback_idx = redir_self ? (redir_idx - 1'b1) : redir_idx`.
- planning/arch/ftq_decisions.md:183-197 (session-071 ruling) rejects
  that K-1 form.
- On a `_self` redirect the RTL can restore history and the RAS
  snapshot from an entry that is already committed and freed.

## Open points (XiangShan values not confirmed)

- 32 halfword slots per block assumes `instBytes = 2`.
- The PHR length of about 530 bits assumes `MaxTableHistoryLength` is
  the TAGE maximum (397): 397 + 2*64 + 4, rounded up to a multiple of
  4, gives 532.
- The ahead BTB prediction stage and its indexing PC: the source
  comments conflict.
- `BrhCnt = 3` is inferred from the BJU0-2 config; `numRedirect` was
  not determined.
- End-to-end redirect-to-fetch cycle counts were not determined.
