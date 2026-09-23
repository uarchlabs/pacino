<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# RAS Fixes -- Findings for a Repair Task
```
 FILE:    ras_fixes.md
 SOURCE:  IA read-only review of misc/ras_theory_of_operation.md
          against planning, ras.sv, tb_ras.sv, bp_cluster.sv
 STATUS:  DRAFT
 UPDATED: 2026-09-22
 CONTACT: Jeff Nye
```

Input for the PA to draft one or more repair tasks. This file reports
findings and evidence. It does not decide fixes; where a fix is
listed it is a candidate for the PA / Jeff to rule on.

Tree state at review: git sha b4d7fd1 (main), working tree as of
2026-09-22. No repo file was modified by the review.

Sources read in full:
- misc/ras_theory_of_operation.md (652 lines)
- planning/arch/ras_decisions.md (893 lines)
- planning/interfaces/ras_interfaces.md (sections 5-7, IC-RAS-01..12)
- rtl/core/frontend/bpu/rtl/ras.sv (456 lines)
- rtl/core/frontend/bpu/tb/tb_ras.sv (603 lines)
- rtl/core/frontend/bpu/rtl/bp_cluster.sv (RAS wiring and p2/p3 regs)
- bp_defines_pkg.sv / bp_structs_pkg.sv (RAS params, bp_br_type_e)

Simulator: tools/bin/verilator (v5.048). NOTE: `verilator` on PATH is
v5.020 and gives wrong results for ad hoc RAS testbenches (inputs
appear one cycle late). Use tools/bin/verilator for any reproduction.
Baseline: unmodified tb_ras under v5.048 -> PASS=87 FAIL=0.

---

## Summary

| ID  | Severity | Area        | One line                                     |
|-----|----------|-------------|----------------------------------------------|
| F1  | HIGH     | RTL+plan    | Pop after pop-then-push returns a dead frame |
| F2  | HIGH     | RTL+plan    | Wrap trigger is push count, not live depth   |
| F3  | LOW      | plan+doc    | Full condition off by one (14 live, not 15)  |
| F4  | MEDIUM   | RTL+plan    | p3 repair cannot fire in bp_cluster          |
| F5  | MEDIUM   | RTL+plan    | RETURN_CALL documented as added; not in RTL  |
| F6  | LOW      | tb          | No test covers F1 / F2 / wrap collapse       |
| D1  | --       | doc         | Theory doc stale against sessions 069-072    |

F1 and F2 need an RTL ruling before the theory doc can be rewritten;
the doc currently presents the cause of F1 as a design strength.

---

## F1. Pop after a pop-then-push returns a dead frame

### Defect

ras.sv allocates every push at TOSW (ras.sv:321-329), and TOSW does
not retreat on pop. A normal pop moves TOSR to TOSR-1
(ras.sv:354). After any pop followed by a push, the push lands above
the popped slot, so the new entry's TOSR-1 neighbour is the popped
(dead) frame, not the caller's frame. The next pop after that
returns the dead frame.

The TOSR/TOSW/BOS scheme is taken from XiangShan, where each entry
also stores a next-on-stack (nos) pointer and a pop follows nos.
ras.sv dropped the nos link (ras_decisions.md 3.2, "No linked-list
structure") but kept the separate monotonic write pointer. Without
the link the structure is not a stack.

### Reproduction (no commits, slot 0 only, p3 agrees with p2)

```
  call A   -> alloc idx1, tosr=1 tosw=2
  call C   -> alloc idx2, tosr=2 tosw=3
  ret      -> returns C (correct),   tosr=1
  call D   -> alloc idx3, tosr=3 tosw=4
  ret      -> returns D (correct),   tosr=2
  ret      -> returns C (WRONG, want A)
```

Observed (probe E4, v5.048):
```
  E4 ret1 -> 0000000000c (want c)
  E4 after call D: tosr=3 tosw=4
  E4 ret2 -> 0000000000d (want d)
  E4 ret3 -> 0000000000c v=1 (want a)
```

Probe E3 shows the same defect at larger scale: one live entry AAAA,
13 call/return pairs, call BBBB, two returns -> second return gives
0x10c (a popped frame), not AAAA.

### Why commit does not hide it

BOS only advances on commit. Prediction runs ahead of commit by up to
FTQ_DEPTH = 64 blocks, and every call and return ends a block, so the
dead-frame pop is predicted long before the relevant commits land.

### Documents that assert the opposite

- ras_theory_of_operation.md 3.2, 3.6: monotonic TOSW "is what makes
  pointer-only recovery correct".
- ras_theory_of_operation.md 4.1, 4.2, 4.3 table: monotonic TOSW gives
  the linked structure's benefit "at lower cost".
- ras_decisions.md 3.2: "simple circular buffer chosen over the
  Xiangshan Kunminghu linked circular array ... Complexity cost not
  justified." The rejected link is what the chosen pointer scheme
  depends on.
- ras_decisions.md 1 / IC-RAS-11 undo-pop: "TOSR moves back up one
  slot" also assumes live entries are contiguous.

### Candidate fixes (for ruling, not decided)

- A. Conventional circular stack: drop the separate TOSW; push writes
  at TOSR+1 (skipping the BOS sentinel), pop is TOSR-1. Snapshot
  shrinks to {tosr, bos}. Wrong-path pushes then overwrite resident
  data, so recovery is exact only if the snapshot also saves the top
  entry (Skadron et al. 1998 pointer + top-content repair) or the loss
  is accepted. Undo-pop and missed-push repair must be re-derived.
- B. Keep TOSR/TOSW/BOS and add a per-entry nos pointer
  (RAS_PTR_BITS per entry, XiangShan style). Push stores nos=TOSR;
  pop sets TOSR=entry.nos. Snapshot unchanged. Wrap / reuse of TOSW
  slots still live under a nos chain must be handled (see F2).
- Either option is a ras_decisions.md 3.2 reversal or amendment and
  touches IC-RAS-05/06/07/09/11 and the snapshot width if A.

---

## F2. Wrap trigger is push count since BOS, not live depth

### Defect

The sentinel skip (ras.sv:321-323) fires when TOSW reaches BOS.
Because TOSW advances on every push and never on pop, TOSW-BOS counts
pushes since BOS last moved, not live entries. A shallow stack loses
its bottom entry after enough call/return pairs without commit.

### Reproduction

Probe E2: one live entry AAAA, 14 call/return pairs (live depth never
above 2), no commit, then call BBBB and two returns.
```
  E2 after 14 pairs: tosr=14 tosw=0 bos=0
  E2 push B: tosr=1 tosw=2 spec[1]=0000000bbbb   <- AAAA overwritten
  E2 ret1 -> 0000000bbbb v=1 (want BBBB)
  E2 ret2 -> 00000000000 v=0 (want AAAA)
```

### Documents that describe it as a depth event

- ras_decisions.md 3.2 "Full condition ... 15 entries live" and
  "Overflow effect" paragraph.
- ras_interfaces.md IC-RAS-06.
- ras_theory_of_operation.md 3.2, 4.3 table ("Overflow" row).

### Note

Fix option A of F1 removes this (write position follows TOSR). Option
B keeps it unless allocation reuses slots freed by pops, which needs
a free-slot rule.

---

## F3. Full condition is off by one

ras_decisions.md 3.2, IC-RAS-06 and theory doc 3.2 say
"TOSW + 1 == BOS: 15 entries live, one push remaining". Probe E1
(pushes only, from reset, BOS=0):
```
  push 14: tosr=14 tosw=15  tosw+1==bos -> 14 live
  push 15: tosr=15 tosw=0   tosw==bos   -> 15 live (true full)
  push 16: tosr=1  tosw=2               -> collapse
```
At TOSW+1 == BOS there are 14 live entries and one push remaining;
15 live corresponds to TOSW == BOS with TOSR != BOS. Text-only fix,
but moot if F1 option A is taken.

---

## F4. p3 repair cannot fire in the integrated cluster

### Defect

bp_cluster.sv:610-611 registers the RAS p3 inputs from the RAS p2
inputs of the previous cycle:
```
  r_br_type_p3[s] <= w_br_type_p2[s];
  r_ras_val_p3[s] <= w_ras_pred_val_p2[s];
```
ras.sv:450 registers p3_op_q from the same p2 inputs. p3 therefore
always agrees with the p2 op and the repair table (ras.sv:224-292)
never fires in bp_cluster. It is exercised only in tb_ras by
force_p3 (TC-16, TC-17, TC-21).

### Documents

- ras_decisions.md 1 / 1.2 and IC-RAS-11 define p3 as "p2 registered"
  and in the same breath require a repair when p3 disagrees with p2.
  Both cannot hold unless some other source can change the type at
  p3.
- ras_theory_of_operation.md 3.8 motivates the repair with "the s2
  operation is initiated on a prediction that can change one cycle
  later".

### Needs a ruling

Either name the p3 source that can disagree with p2 (and wire it), or
record the repair as reserved / dead in the current integration.

### Latent hazard if a real p3 source is wired

ras.sv registers p3_op_q unconditionally, including in a cycle where
ras_restore_val blocks the p2 op (ras.sv:407-422, 449-452). If the p3
valid for that wrong-path op is later withheld, the next cycle
"repairs" (undoes) an op that was never applied, against the freshly
restored pointers. TC-12 does not look at the cycle after restore.
Candidate: clear p3_op_q when ras_restore_val is asserted.

---

## F5. RETURN_CALL is documented as added but is not in the RTL

ras_interfaces.md 5 says RETURN_CALL "was added to bp_br_type_e at
3'b111 in session-069"; IC-RAS-01/02/10 and ras_decisions.md 2, 3.3
and RAS-DS1 give its behaviour (pop first, then push; commit return
arm then call arm).

bp_structs_pkg.sv:84-92 has no RETURN_CALL (3'b111 unused), and
ras.sv has no pop-then-push path at p2 or at commit. The built RAS
cannot perform the operation, which answers TD-DCD-2 (dcd_decisions.md
158) in the negative.

Scope for the task: package addition (enum value), ras.sv p2 path
(pop supplies target, then push of fall-through), ras.sv commit path,
p3 repair table rows for RETURN_CALL (not defined in IC-RAS-11), and
tb cases. Sequence with F1 since both change the push/pop core.

---

## F6. Test gaps

tb_ras has no case that:
- pops twice after a pop-then-push (F1). TC-07 reaches the state
  (seed X, pop, push B) but never pops B and then pops again.
- runs call/return pairs past RAS_SPEC_ENTRIES pushes with a live
  bottom entry (F2).
- checks the depth collapse on wrap. TC-18 checks only that pointers
  are not X.
- checks the cycle after a restore that coincided with a p2 op (F4
  hazard).

Probe stimulus that exposes F1-F3 is in the Appendix; it drops into
tb_ras using the existing do_reset / push_one / drive / tick tasks.

---

## D1. Theory doc items stale against planning (no RTL change)

For the doc rewrite after F1-F5 are ruled. Each row: theory doc
section -> current planning text.

| Doc  | Doc says                          | Planning now                  |
|------|-----------------------------------|-------------------------------|
| 2    | RAS is "outside the override      | Wording withdrawn;            |
|      | chain SC > TAGE > FTB > uBTB"     | ras_decisions.md 1            |
| 2    | Three-way FTB/RAS/ITTAGE split    | Two-way RAS/ITTAGE; FTB target|
|      |                                   | is ITTAGE-miss fallback (2)   |
| 2    | Return rule; "C.JALR rs1=x5       | JALR hint table + RETURN_CALL |
|      | excluded"                         | (ras_decisions.md 2)          |
| 2    | s0 read is "initial prediction    | Input to the p1 prediction    |
|      | used by the FTQ"                  | (ras_decisions.md 1)          |
| 2    | s2 redirect when a predictor      | p2 successor vs cluster's own |
|      | "disagrees with the uBTB s1"      | p1 registers (1.2, FE-4)      |
| 3.4, | Fixed +32 slot split, five slot   | Superseded; at most one slot  |
| A.2, | combinations, same-cycle bypass   | has a RAS op (FE-11, 6.1-6.4);|
| 4.2  | as a live feature                 | bypass is dead logic          |
| 3.1  | VA_WIDTH = 40b                    | 41 (RTL and FE-19, TD#122)    |
| 3.6  | Snapshot written by predictions   | Every valid block, from       |
|      | "that affect the RAS"             | snapshot[NUM_PRED_SLOTS-1]    |
|      |                                   | (4.2, IC-RAS-08)              |
| 3.6  | Restore from "the mispredicted    | Entry the redirect names by   |
|      | entry"                            | index (4.3, D2)               |
| 3.7, | Commit wrap "candidate for a TD"  | TD #121                       |
| 5    |                                   |                               |
| 3.10 | "Three items" of known limitation | Add TD #121; F1-F5 once ruled |

Minor:
- Doc 3.3: "the cycle after the push commits" -- "commit" means
  retire elsewhere in the doc; use "takes effect".
- Doc 3.8 / 4.2 attribute a pointer-realignment result to Desmet et
  al. (2008); ras_decisions.md 3.2 attributes a different claim to
  the same paper. Check the paper before publication.
- Doc header disclaimer ("canonical records take precedence") does
  not carry into a blog; the text must be correct on its own.

---

## Suggested task split (for the PA)

1. Ruling (Jeff / PA): F1 fix option A or B; F4 p3 source or
   dead-marking. Planning updates to ras_decisions.md 3.2, 3.3, 1,
   IC-RAS-06/09/11 follow the ruling.
2. RTL task: ras.sv core rework per F1 ruling (covers F2, F3), with
   F4 p3_op_q clear-on-restore, tb_ras cases from F6.
3. RTL task: RETURN_CALL (F5) -- package addition plus ras.sv p2,
   commit and repair paths, tb cases. After task 2.
4. Doc task: rewrite ras_theory_of_operation.md against the ruled
   design and D1.

All RTL tasks: ./tools/regress.sh from repo root; package edit in
task 3 widens the run to every unit per CLAUDE.md.

---

## Appendix. Probe stimulus (drop-in for tb_ras initial block)

Built as: tb_ras.sv up to its `initial begin`, then the block below,
compiled with the sim_ras file list and flags using tools/bin/verilator.

```
  initial begin
    pass_cnt = 0; fail_cnt = 0;
    // E1: depth when tosw+1 == bos
    do_reset();
    for (int i = 1; i <= 16; i++) begin
      push_one(VA_WIDTH'('h1000) + VA_WIDTH'(i*16));
      $display("E1 push %0d: tosr=%0d tosw=%0d bos=%0d full=%0d",
               i, dut.tosr, dut.tosw, dut.bos,
               (dut.tosw + 4'd1) == dut.bos);
    end
    // E2: one live entry, 14 call/return pairs, no commit
    do_reset();
    push_one(VA_WIDTH'('hAAAA));
    for (int i = 0; i < 14; i++) begin
      push_one(VA_WIDTH'('h100) + VA_WIDTH'(i));
      drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); #1;
      tick();
    end
    push_one(VA_WIDTH'('hBBBB));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); #1;
    $display("E2 ret1 -> %h (want BBBB)", pop_addr_p2[0]);
    tick();
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); #1;
    $display("E2 ret2 -> %h v=%0d (want AAAA)",
             pop_addr_p2[0], pop_valid_p2[0]);
    tick();
    // E4: call A; call C; ret; call D; ret; ret. No commits.
    do_reset();
    push_one(VA_WIDTH'('hA));
    push_one(VA_WIDTH'('hC));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); #1;
    $display("E4 ret1 -> %h (want c)", pop_addr_p2[0]); tick();
    push_one(VA_WIDTH'('hD));
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); #1;
    $display("E4 ret2 -> %h (want d)", pop_addr_p2[0]); tick();
    drive(1'b1, RETURN, '0, 1'b0, NO_BRANCH, '0); #1;
    $display("E4 ret3 -> %h v=%0d (want a)",
             pop_addr_p2[0], pop_valid_p2[0]);
    tick();
    $finish;
  end
endmodule
```

As regression cases these become self-checking check() calls with the
"want" values as expected results; under the current RTL E2 ret2 and
E4 ret3 fail.
