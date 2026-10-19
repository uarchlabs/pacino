<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Front-End Demonstration Scenarios
```
 FILE:    fe_demo_scenarios.md
 SOURCE:  session-080
 STATUS:  DRAFT
 UPDATED: 2026-10-14
 CONTACT: Jeff Nye
```

Owns the FD-N and FD-UN registries.

The scenarios the front-end demonstration testbench runs. Each scenario
is one program that makes one behaviour of fe_top visible in the
waveform and the trace. The testbench is
planning/testbenches/fe_demo_tb_decisions.md; the trace is
planning/observ/fe_trace_decisions.md.

---

## 1. Common rules

FD-0a  Every scenario runs on fe_top with the walker beside it and
       the in-order backend of tb_fe_top, on the build its entry names
       (fe_demo_tb_decisions.md FDT-5): NUM_PRED_SLOTS = 1, or 2 where
       the entry says so. FD-3 and FD-22 to FD-24 run at 2; every
       other scenario at 1 (Jeff, session-081).
FD-0b  Each scenario has, in its program or its README entry:
         shows     the behaviour, in one sentence
         program   the code shape that produces it
         waveform  the units whose signals make up its saved group
         trace     the events it must produce
         proof     the condition that shows the behaviour occurred
       Each program file's header carries the entry; its trace line
       lists the events the proof counts.
FD-0c  A scenario's proof is checked at the end of its run. A run whose
       proof fails reports it; it is a broken demonstration, not a test
       failure.
FD-0d  CSR state is set through csr_tb_pkg. A scenario that needs a
       non-reset value names it.

---

## 2. Prediction

```
FD-1   Reset and SRAM initialization
  shows     the full init walk of the predictor tables, ending with
            every predictor ready
  program   a loop of 3000 passes over 7 instructions; reset without
            the fast-init options
  waveform  sram_init, TAGE, ITTAGE, SC readies, first p0 request
  proof     every ready rises; the first prediction the FTQ accepts
            follows the last ready

FD-2   Steady-state prediction and fetch
  shows     one block per cycle: p0 request, uBTB answer at p1, FTQ
            allocation, the next p0 the cycle after
  program   straight-line code with no branches, longer than one line
  waveform  bp_cluster p0/p1, FTQ pointers, IFU F0-F3, IBUF, decode
  proof     at least 4 consecutive allocations; at least 4
            consecutive cycles of 8 instructions decoded

FD-3   Two branches in one block
  build     NUM_PRED_SLOTS = 2
  shows     both prediction slots used by one block
  program   two blocks, each with two conditionals in one 32-byte
            region, in a loop of 24
  waveform  uBTB and FTB slot outputs, both slots
  proof     a block predicted with both slots valid

FD-4   p2 override
  shows     the FTB disagreeing with the uBTB and the p2 redirect
  program   eight blocks 0x800 apart chained by taken conditionals,
            sharing one 4-way uBTB set; the FTB holds all eight
  waveform  uBTB p1, FTB p2, bpu_redir_p2, FTQ rewrite
  proof     a p2 redirect

FD-5   p3 override
  shows     SC reversing the TAGE direction and the p3 redirect
  program   two conditionals whose outcomes depend on history
            (periods 2 and 3), 96 passes
  waveform  TAGE p2, SC p3, bpu_redir_p3
  proof     a p3 redirect from an SC reversal

FD-6   Loop predictor
  shows     the loop predictor taking over a loop and predicting its
            exit
  program   a counted inner loop with a fixed trip count, run enough
            times for the entry to become trusted
  waveform  loop predictor entry, p1 mux, loop exit
  proof     a loop exit predicted correctly by the loop predictor

FD-7   Calls and returns
  shows     RAS push and pop, a return predicted from the stack,
            recursion compression, a return-call
  program   nested calls, a recursive call four deep, two coroutines
            switching by return-call
  waveform  RAS pointers and top of stack, p2 operations, commit stack
  proof     returns predicted from the RAS; a recursion count above
            1; a p2 RETURN_CALL

FD-8   Indirect jump
  shows     ITTAGE predicting an indirect target
  program   an indirect jump and an indirect call whose targets
            alternate, each after an alternating conditional, 40 passes
  waveform  ITTAGE p2, FTB target, p2 target selection
  proof     an indirect target predicted by an ITTAGE hit

FD-9   TAGE provider, allocation and use_alt_on_na
  shows     a tagged provider hit, an allocation after a mispredict,
            use_alt_on_na choosing T0
  program   a loop around one conditional branch taken at random
            (1 in 8, from the program writer's LFSR), with a back edge;
            the t0_uaon program of tb_fe_top
  waveform  TAGE p2 provider, update path, allocation, uaon
  proof     an allocation; a prediction by T0 through use_alt_on_na
```

---

## 3. Recovery

```
FD-10  Predecode redirect
  shows     a JAL the predictors did not report, found at F3
  program   a JAL in code not yet seen by the uBTB or FTB
  waveform  IFU F3, predecode writeback, FTQ redirect, IFU flush
  proof     a predecode redirect

FD-11  Backend mispredict
  shows     the backend redirect: FTQ squash, IFU flush, history
            rollback and correction, RAS restore
  program   a conditional with a pseudo-random outcome (the program
            writer's LFSR), then a call and its return, 32 passes
  waveform  backend resolution, FTQ squash, bp_history, RAS restore
  proof     a backend redirect followed by fetch at the corrected PC

FD-12  Training
  shows     a resolution through ftq_upd_conv into the update queues,
            the FTB update and its p0 bubble, the uBTB fill
  program   nested counted loops with an always-taken conditional,
            an indirect jump and an indirect call
  waveform  ftq_resolve, ftq_upd_conv, the update queues, FTB update
  proof     an update reaches each predictor and the RAS commit; an
            FTB update bubble
```

---

## 4. Fetch and memory

```
FD-13  L1I hit and miss
  shows     a 2-cycle hit returning a full line; a miss with an MSHR
            fill; a second request merged onto the miss
  program   a loop within one line (hits); a call to the upper half
            of a line X whose JAL returns to X, trained, then run
            again after FENCE.I and one line of filler instructions:
            the block at X+0x30 requests X and X+1 (IFU-7) and the
            predicted block at X requests X while that miss is in
            flight. A second block on the same line never merges: the
            IFU reuses the previous request's line (TD-IFU-8). The
            filler keeps the fetch that runs past the FENCE.I from
            requesting X before the restart (DOC-007)
  waveform  L1I request and response, MSHR, fill
  proof     a hit, a miss, a merge

FD-14  Translation
  shows     an ITLB miss and an Sv39 walk; a nested Sv39x4 walk; a
            Svadu A-bit update by compare-and-swap
  program   fetch at S-mode under Sv39; fetch at VS-mode under
            two-stage translation; a leaf with A clear and ADUE set.
            The change to VS-mode rides on the trap of an ecall: the
            testbench applies V=1 and the VS CSRs as it retires
  waveform  ITLB, walker, walker memory port
  proof     a walk of each kind with G-stage PTE evaluations; one
            compare-and-swap

FD-15  Faults
  shows     a page fault, a guest-page fault and an access fault
            carried into ifu_pd_pkt_t
  program   fetch from an unmapped page, a G-stage miss, a PMP-denied
            region
  waveform  ITLB response, IFU fault path, IBUF packet
  proof     each cause reaches decode on its packet

FD-16  Page-crossing block
  shows     a block crossing a page, with two translations
  program   a block that starts within 32 bytes of a page end
  waveform  IFU translation queue, two ITLB lookups
  proof     one block with two translations

FD-17  Compressed and unaligned code
  shows     a 34-byte block, and a 32-bit instruction straddling two
            blocks
  program   mixed 16- and 32-bit instructions, unaligned block starts
  waveform  IFU expansion, predecode, IBUF slots
  proof     a straddling instruction delivered whole

FD-18  Uncached fetch
  shows     fetch from an NC page and from an IO page, one instruction
            per FTQ entry
  program   a short sequence on a page whose PTE PBMT is NC, then one
            on a page whose PTE PBMT is IO
  waveform  IFU uncached path, L1I uncached request, commit gate
  proof     uncached requests from each page, counted separately; no
            L1I allocation

FD-19  FENCE.I and cbo.inval
  shows     the drain, the invalidate and the restart
  program   code modified then FENCE.I; a cbo.inval of a code line
  waveform  IFU maintenance, L1I invalidate, done, restart
  proof     the invalidate completes and fetch restarts
```

---

## 5. Flow control

```
FD-20  Backpressure
  shows     IBUF full, FTQ full and a stalled decode, and where each
            stall starts
  program   a long run with the backend accepting slowly
  waveform  IBUF occupancy, FTQ pointers, p0 request ready
  proof     each stall occurs

FD-21  Commit
  shows     the commit pointer advancing and the RAS commit stack
  program   calls and returns retiring in order
  waveform  FTQ commit pointer, RAS commit stack
  proof     commits advance; the commit stack changes
```

---

## 6. Dual slot

```
FD-22  SC reversing slot 1
  build     NUM_PRED_SLOTS = 2
  shows     two conditionals in one block, slot 0 predicted by TAGE
            and slot 1 reversed by SC at p3
  program   a loop of 48 passes; its first block holds A, never taken,
            and B, taken on odd passes, whose target lies inside the
            block; the back edge in the next block
  waveform  TAGE p2, SC p3, p3 slots and redirect
  proof     a p3 redirect from slot 1, SC-decided (PRED_SC), behind a
            TAGE-predicted conditional in slot 0

FD-23  A jump behind two conditionals
  build     NUM_PRED_SLOTS = 2
  shows     a block {conditional, conditional, jump} with both
            conditionals not taken: the FTB entry holds the two
            conditionals and ends at the jump PC (the split at update,
            ftb_decisions.md 3, BP-140), and the next block predicts
            the jump. Re-pointed from the BP-138/BP-139 cut by DOC-007
  program   a loop of 24 passes over two never-taken conditionals and
            a jal to the block holding the back edge; the program
            records the jal's PC for the proof
  waveform  FTB p2 fields, p2 slots, the cut, the block end, the FTB
            update that splits the entry
  proof     a p2 group with two not-taken conditionals ending at the
            jump PC by the FTB's end (bpu_blk_pft_p2 at the jump PC,
            the cut clear); the next group at that PC with the jump in
            slot 0, taken

FD-24  A call in slot 1
  build     NUM_PRED_SLOTS = 2
  shows     a call in slot 1 behind a not-taken conditional in slot 0,
            the RAS push made from slot 1
  program   a loop of 24 passes; a never-taken conditional, then a call
            to a function that returns to the back edge's block
  waveform  p2 slots, RAS p2 operation and pointers, commit stack
  proof     a p2 group with a not-taken conditional in slot 0 and a
            call in slot 1 presented to the RAS; a return predicted by
            the RAS
```

---

## 7. Open

FD-U1  CLOSED, DOC-001: one program per scenario, none combined,
       presented in FD order.
FD-U2  CLOSED, DOC-001: the shared backend's be_rdy_pat; decode accepts
       one cycle in N (0 = every cycle, the reset value); FD-20 uses
       N = 4.

---

## 8. Document History

```
  2026-10-14  session-080. Created.
  2026-10-14  session-080, after DOC-001. FD-1 status, FD-13 program,
              FD-14 note, FD-0b trace entries; FD-U1, FD-U2 closed.
  2026-10-15  session-080, after BP-137. FD-1 met; its status line
              removed.
  2026-10-15  session-080. FD-9 program as built (docs/fd09_tage.md).
  2026-10-15  session-080, after DOC-002. FD-1, 3, 4, 5, 7, 8, 11, 12
              programs and FD-2, 7, 12, 14 proofs as built. FD-18
              covers IO as well as NC (Jeff).
  2026-10-15  session-080, after DOC-003. FD-18 proof as built.
  2026-10-18  session-081, after DOC-006. FD-0a builds (Jeff); FD-3
              build; section 6, FD-22 to FD-24 (Jeff); Open and
              History renumbered 7 and 8.
  2026-10-19  session-081, after DOC-007. FD-13 program re-timed (the
              filler after FENCE.I); FD-23 re-pointed at the split.
```
