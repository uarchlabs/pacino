# Note to the PA: two BPU defects found by a 1-slot fe_demo trial

From:   IA, interactive session 2026-10-17
Source: tree at ab80cfe (rtl/ and examples/fe_demo/ clean), copied to a
        scratch area and built twice: NUM_PRED_SLOTS = 2 (default) and
        NUM_PRED_SLOTS = 1 (+define+BP_NUM_PRED_SLOTS=1
        +define+BP_EXPECT_PRED_SLOTS=1). No project file was changed.
Ask:    craft the task(s) to fix the design. Two independent defects;
        D2 is present in the default 2-slot build.

---

## Background

The trial ran all 21 fe_demo scenarios in both builds. 2-slot: 21/21
PASS, figures identical to the project's. 1-slot: 19 PASS, 2 FAIL:
fd03_two_branch (expected, needs two slots) and fd07_calls_returns. The
fd07 investigation found D1 (the cause of the fd07 failure) and D2
(present in both builds).

All signal values below were read from the FSTs with
waves/fe_demo_sigs.fst_values, sampled once per tb.cyc.

---

## D1. An FTB entry's jump is dropped when no slot is free for it

### Mechanism

bp_cluster.sv p2_class_comb (lines 965-1032) gives slot s the FTB
conditional field s (br0 for slot 0, br1 for higher slots) when it is
valid, and places the block's single jump field (ftb jmp) in "the
lowest slot that carries no conditional branch" (jmp_placed). When every
slot holds a conditional, the jump is not placed: w_br_type_p2 never
carries it and w_ras_pred_val_p2 never qualifies it, so the RAS sees no
push or pop for it.

p2_succ_comb (lines 1074-1079) still sets the block fall-through to the
jump's end whenever the FTB jump field is valid:
  else if (w_ftb_jmp_valid_p2) w_pft_p2 = w_jmp_ft_p2;
So when the conditional(s) are predicted not taken, the predicted
successor is the address after the jump, as if the jump were not in the
block. The prediction is wrong every time the path reaches the jump.

### Where it occurs

- NUM_PRED_SLOTS = 1: any block with a conditional before its jump.
- NUM_PRED_SLOTS = 2: any block with two conditionals before its jump
  (br0, br1 and jmp all valid). Inferred from the code; no fe_demo
  scenario has this pattern, so it was not observed.

### Evidence (fd07, block f = 0x8000_0800)

Block f: beq at f+6 (br0, pos 3), jal x1,f at f+10 (jmp, pos 5); in some
cycles the FTB entry's jmp field holds a return at pos 8 instead.

p2 cycles with r_pc_p2 = f and an FTB hit:

                           2 slots              1 slot
  cycles                   58                   46
  jmp field valid          57                   45
  slot 0                   COND                 COND
  slot 1                   jump: DIRECT_CALL    (none)
                           36, RETURN 21
  jump presented to RAS    46 cycles            never
  successor, call entry,   0x8000_0800 (f,      0x8000_080e (f+14,
  cond not taken           the call target)     after the call)
  successor, return entry, 0x8000_0018 (RAS)    0x8000_0814 (after
  cond not taken                                the return)

1-slot consequence: fetch runs sequentially from f+0x14 for about 8
cycles until a predecode redirect to f with ifu_ftq_mis_pos 5 (the jal).
Example: p2 at f in cyc 292, predecode redirect in cyc 300, fetch
restarts at f. Predecode redirects with target f: 24 (2 slots) vs 42
(1 slot); the 18 extra equal the 10 + 8 call-entry cycles above.

Effect on fd07: the recursive call is never pushed at p2, so no
repeated push of the same return address occurs, spec_rctr never rises
above 0 (max_rctr 0 vs 8), and the proof (max_rctr > 1,
fe_demo_proofs.svh:79) fails. p2 pushes 45 vs 76.

### For the task

The design question is what a block whose branches exceed the slot
count should predict. Options the PA may weigh (no recommendation
made here):
- reserve a slot for the jump (place the jump in the last slot when
  every slot is taken, dropping the youngest conditional);
- end the predicted block at the last placed branch, so the
  fall-through does not skip an unplaced jump (w_pft_p2 must not be
  w_jmp_ft_p2 when the jump was not placed);
- constrain FTB allocation so an entry never holds more branches than
  slots.
The w_pft_p2 / jmp_placed mismatch is the defect in any of these.
NUM_PRED_SLOTS = 1 is a ruled value (BP-128, session-078), so the
1-slot case is in scope, not only the 2-slot three-branch case.

Suggested checks for the fix: a directed bp_cluster test with a block
of {cond, jump} at 1 slot and {cond, cond, jump} at 2 slots, cond not
taken, expecting the jump's target as successor (and the RAS push for
a call); fd07 passing in a 1-slot fe_demo build.

---

## D2. RAS pops a stale entry as valid after BOS passes an empty TOSR

### Mechanism (as observed)

ras_decisions.md: "Empty condition: TOSR == BOS. On pop when empty, fall
through to commit stack top as prediction result." In both builds the
speculative stack became empty (TOSR == BOS), then a commit advanced
BOS by one while TOSR stayed. From then on TOSR != BOS, so the stack is
treated as non-empty, and p2 pops return entries below BOS with
ras_pop_valid_p2 = 1. One such entry, spec_ret_addr[0], is never written
in the run and holds its reset value 0x0.

The RTL path is ras.sv lines 604-611: the empty test (~w.valid) is
false, so ras_pop_addr_p2 = w.top_addr and ras_pop_valid_p2 = 1. The
commit-stack fallback (commit_top_valid 1, commit_top_addr 0x8000_0012)
is not used.

### Evidence

2-slot fd07 (default build):
  cyc 583-584  tosr 5 bos 5            empty
  cyc 585      tosr 5 bos 6            BOS advanced, TOSR did not
  cyc 587-589  p2 RETURN at 0x8000_080e pops: tosr 5 -> 3 -> 1 -> 0
               via spec_nos; cyc 589 pops entry 0:
               ras_pop_valid_p2[0] 1, ras_pop_addr_p2[0] 0x0,
               pred_src PRED_RAS, bpu_redir_p2[0] to 0x0
  cyc 590-595  fetch at 0x0 and 0x500 (a uBTB entry matching at 0x0,
               DIRECT_CALL target 0x500)
  backend redirect corrects to 0x8000_050a a few cycles later.
Valid p2 pops with an address below 0x8000_0000: 4 in the 2-slot run
(cyc 589, 754, 919, 1083), 7 in the 1-slot run (cyc 259, 450, 632, 814,
996, 1178, 1360), about once per program loop iteration. 1-slot cyc 257-258 tosr 0 bos 0 (empty), cyc 259 bos 1, pop of
entry 0 returns 0x0 valid.

The program still retires correctly (fd07 passes at 2 slots); the
defect costs a wrong-path fetch to an address outside the program,
each time ending in a backend redirect. It is a prediction defect
with a functional symptom: ras_pop_valid_p2 = 1 for an entry that holds
no return address, contrary to IC-RAS-07 / ras_interfaces.md.

### For the task

Root cause not established beyond the observation above: whether BOS
should not advance past TOSR on commit, whether TOSR should move with
it, or whether the empty test must cover TOSR behind BOS in circular
order. This matches the circular-stack empty/full ambiguity pattern
the RAS has had before. A directed tb_ras test: empty the speculative
stack with pops, then commit a call so BOS advances, then pop; expect
the commit-stack fallback, not a speculative entry.

---

## Reproduction

  make -C examples/fe_demo build scenarios           # 2-slot, D2
  make -C examples/fe_demo ... VER_FLAGS="<as Makefile> \
    +define+BP_NUM_PRED_SLOTS=1 +define+BP_EXPECT_PRED_SLOTS=1"
                                                     # 1-slot, D1, D2
Use a scratch copy or a separate obj dir for the 1-slot build; FDT-5
says the demonstration has no 1-slot build. Probe scripts (scratch):
fd07_probe.py, fd07_probe2.py ... fd07_probe6.py.
