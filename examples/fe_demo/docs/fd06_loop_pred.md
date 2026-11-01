<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd06_loop_pred: Loop Predictor
```
 FILE:    fd06_loop_pred.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd06_loop_pred` is the FD-6 demonstration scenario. It is a demo, not a
verification test. It runs a counted inner loop of 10 iterations inside
an outer loop of 16 passes. The loop predictor (LP) learns the inner
loop's trip count, reaches full confidence, and from then on supplies
the inner loop branch's direction, including the not-taken exit. The run
passes if at least one retired exit was predicted not taken by the LP.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                        |
  |--------------------|---------------------------------------------|
  | This file          | $DEMO/docs/fd06_loop_pred.md                |
  | Program (stimulus) | $DEMO/programs/fd06_loop_pred.svh           |
  | Surfer sucl        | $DEMO/waves/fd06_loop_pred.sucl             |
  | Log                | $DEMO/out/fd06_loop_pred/fd06_loop_pred.log |
  | Waveform           | $DEMO/out/fd06_loop_pred/fd06_loop_pred.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd06_loop_pred.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd06_loop_pred.sucl) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd06_loop_pred
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd06_loop_pred
```

Console output:
```
-I: fd06_loop_pred : PASS : cyc = 439
```

Log file output:
```
-I: fd06_loop_pred: PASS, loop exits predicted by the loop predictor 8,
    events checked 9 of 9, cyc 439
```

### 2.1 What the monitor counts

The count is taken at retirement, in the backend's retire hook
(`tb/fe_demo_mon.svh:302-305`):

```
n_lp_exit_ok   a retired COND, not taken in the expected stream, whose
               FTQ entry's final slot at its position is valid, has
               pred_src == PRED_LOOP and taken == 0
```

The final slot is the last group the FTQ accepted for the entry, p1 then
p2 then p3 (`fin_log`, `tb/fe_demo_mon.svh:270-279`), found by position
(`slot_at`, line 282).

The proof (`tb/fe_demo_proofs.svh:72`) is `n_lp_exit_ok > 0`.
`tb_fe_demo.sv:160` also requires the whole stream to retire with no
errors before it accepts the proof.

### 2.2 Reading the numbers

- 8 of the 16 inner exits were predicted not taken by the LP. Of the
  other 8, four were mispredicted (the backend redirects of section
  4.1); for the other four, the slot that predicted them was not traced.
- The count is of retired exits, each counted once, so it cannot exceed
  16.
- Spec and build agree on program and proof. The FD-6 waveform entry
  names "loop predictor entry". The command file shows the loop
  predictor's per-slot answers in the group `loop_pred_p1_p2`, which
  stand in for the table entry. The p1 answer shows its hit and its
  direction. The p2 answer, which re-reads the same entry, also shows
  the speculative count `lp_curs` and the learned trip count
  `lp_past_itr` with its confidence `lp_conf` (DOC-006).

---

## 3. The program

Source: `programs/fd06_loop_pred.svh`, task `prog_fd06` (line 20).
Addresses from the source (`RESET_VECTOR` 0x8000_0000,
`rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv:40`):

```
0x8000_0000          mixed(3)           c.addi, addi, c.addi     8 bytes
otop = 0x8000_0008   mixed(2)           c.addi, addi             6 bytes
itop = 0x8000_000E   mixed(3)                                    8 bytes
0x8000_0016   I:     bne x6,x0,itop     taken on iterations 0..8
0x8000_001A          mixed(2)                                    6 bytes
0x8000_0020   O:     bne x6,x0,otop     taken on passes 0..14
0x8000_0024          mixed(3)
                     jal x0,0           halt (demo_go -> W.halt)
```

- Fixed code. Each outer pass resets `W.wp = otop` and each inner
  iteration `W.wp = itop`, so the same bytes are written again; only the
  expected stream grows.
- Outcomes come from the writer. `bcc` (`fe_tb_writer.svh:412`) emits
  `bne x6, x0` with the direction already decided; the backend retires
  against the writer's expected stream, so x6 is never read.
- I is taken 9 times and not taken once per outer pass: 16 exits in
  all, each with the same trip count. O is taken 15 times.

---

## 4. Walkthrough

### 4.1 Why the program produces the behavior

The loop predictor is `rtl/core/frontend/bpu/rtl/loop_pred.sv`, one
bank per slot.

1. Allocation. An update that misses allocates an entry on a taken
   backward branch (`u_alloc`, `loop_pred.sv:400`). I is taken backward
   (target 0x8000_000E below its PC), so its first taken resolution
   allocates. The speculative count is unknown at allocation; it
   becomes known at the entry's next exit (comment, lines 427-429).
2. Training. On a not-taken resolution (an exit) at a known count
   (`loop_pred.sv:411-423`): a count equal to the learned trip count
   (`past_itr`) raises `cnf` by one; any other count clears `cnf` and
   learns the count. A taken resolution at or past the learned count
   clears `cnf` (lines 404-410).
3. Trust. A prediction is made only at full confidence:
   `lp_pred_is_loop` needs a hit, a valid speculative count and
   `cnf == {LP_CNF_BITS{1'b1}}` (`loop_pred.sv:269-271`, p1;
   lines 305-306, the p2 re-read). `LP_CNF_BITS` is 2, so the level
   is 3 (`LP_CONF_LEVEL`, line 82). The direction is taken while the
   count is below the trip count (lines 272 and 273, lines 307 and
   308), so the exit is predicted not taken.
4. Override. At p1, a trusted LP overrides the direction of a slot the
   uBTB supplied and the slot carries `pred_src = PRED_LOOP`
   (`rtl/core/frontend/bpu/rtl/bp_cluster.sv:805-810`). At p2 the LP
   takes priority over TAGE for a conditional (`w_lp_use_p2`,
   `bp_cluster.sv:1031-1036`) and the slot again carries `PRED_LOOP`
   (lines 1161 and 1162).

From the run (out/fd06_loop_pred/fd06_loop_pred.fst, slot 0 of
`w_lp_pred_p2`): `lp_past_itr` first reads 8 at cycle 116, `lp_conf`
steps 1, 2, 3 and reaches 3 at cycle 248, and `lp_pred_is_loop` is
first set at cycle 257. Before that, the inner exit was mispredicted
four times: backend redirects to 0x8000_001A at cycles 49, 88, 112 and
140. The p2 answer describes the inner loop's branch only in the cycles
its block is at p2; in other cycles it reads 0.

### 4.2 Reading the waveform

The saved view is `waves/fd06_loop_pred.sucl`, which `make view
S=fd06_loop_pred` opens in Surfer. Look at:

- `bpu_pred_slot_p1.[0]` and `bpu_slot_p2.[0]`: `pred_src` `PRED_LOOP`
  on the slot of I from cyc 256 at p1 and 257 at p2, with `taken`
  dropping on the tenth iteration (first at cyc 259).
- `w_lp_pred_p2.[0]`: `lp_past_itr` 8 from cyc 116, `lp_conf` reaching
  3 at cyc 248, `lp_pred_is_loop` first set at cyc 257.
- `w_lp_upd_val_p0`: the LP updates as I resolves.
- `bkend_ftq_redir_val` is absent from this command file; the three
  early exit mispredicts show as `w_redir_val` in the ftq group.
- `pd_out.[0]`: the retirement stream at decode.

---

## 5. Events

| # | cyc | Event                                                                                       | Other              |
|---|-----|---------------------------------------------------------------------------------------------|--------------------|
| 0 | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                     | fast init          |
| 1 | 49  | first inner exit mispredicted; redirect to 0x8000_001A                                      | backend            |
| 2 | 116 | the loop predictor learns the trip count: `lp_past_itr` reads 8                             | `w_lp_pred_p2.[0]` |
| 3 | 248 | confidence reaches 3 (`lp_conf`), the level at which the loop predictor is trusted          |                    |
| 4 | 256 | first p1 slot from the loop predictor (`pred_src` PRED_LOOP), accepted by the FTQ           |                    |
| 5 | 257 | the loop predictor first trusted at p2 (`lp_pred_is_loop`); the slot is PRED_LOOP           |                    |
| 6 | 259 | first exit predicted not taken, by the loop predictor: I's slot at p2, PRED_LOOP, `taken` 0 | block 0x8000_000E  |
| 7 | 429 | outer loop falls through, a misprediction; redirect to 0x8000_0024                          | pass 15, backend   |
| 8 | 439 | the run ends                                                                                |                    |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd06_loop_pred` opens
`waves/fd06_loop_pred.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group            | signal                                   | description                                     |
|------------------|------------------------------------------|-------------------------------------------------|
| clock            | `tb.clk`                                 | clock                                           |
|                  | `tb.rstn`                                | active low reset                                |
|                  | `tb.cyc`                                 | cycle number                                    |
| bp_cluster_p1    | `bpu_pred_val_p1`                        | p1 prediction valid                             |
|                  | `bpu_pred_idx_p1`                        | FTQ index of the p1 prediction                  |
|                  | `u_bpu.r_ubtb_blk_p1.hit`                | uBTB hit at p1                                  |
|                  | `bpu_pred_pft_p1`                        | p1 fetch block end, the first halfword after it |
|                  | `bpu_pred_slot_p1.[0].slot_valid`        | slot 0 holds a branch                           |
|                  | `bpu_pred_slot_p1.[0].br_type`           | slot 0 branch type                              |
|                  | `bpu_pred_slot_p1.[0].pos`               | slot 0 halfword position in the fetch block     |
|                  | `bpu_pred_slot_p1.[0].taken`             | slot 0 predicted direction                      |
|                  | `bpu_pred_slot_p1.[0].target`            | slot 0 predicted target                         |
|                  | `bpu_pred_slot_p1.[0].pred_src`          | slot 0 predictor that supplied the direction    |
| loop_pred_p1_p2  | `u_bpu.w_lp_pred_p1.[0].lp_hit`          | loop predictor hit at p1, slot 0                |
|                  | `u_bpu.w_lp_pred_p1.[0].lp_pred_is_loop` | loop predictor trusted at p1, slot 0            |
|                  | `u_bpu.w_lp_pred_p1.[0].lp_pred_taken`   | loop predictor direction at p1, slot 0          |
|                  | `u_bpu.w_lp_pred_p2.[0].lp_hit`          | loop predictor hit at p2, slot 0                |
|                  | `u_bpu.w_lp_pred_p2.[0].lp_pred_is_loop` | loop predictor trusted at p2, slot 0            |
|                  | `u_bpu.w_lp_pred_p2.[0].lp_pred_taken`   | loop predictor direction at p2, slot 0          |
|                  | `u_bpu.w_lp_pred_p2.[0].lp_conf`         | loop predictor confidence, slot 0               |
|                  | `u_bpu.w_lp_pred_p2.[0].lp_past_itr`     | learned trip count, slot 0                      |
|                  | `u_bpu.w_lp_pred_p2.[0].lp_curs`         | speculative count, slot 0                       |
| bp_cluster_p2    | `u_bpu.r_val_p2`                         | p2 valid                                        |
|                  | `bpu_slot_val_p2`                        | slot valid mask                                 |
|                  | `bpu_slot_idx_p2`                        | FTQ index of the p2 group                       |
|                  | `u_bpu.w_ftb_valid_p2`                   | FTB hit at p2                                   |
|                  | `bpu_slot_p2.[0].slot_valid`             | slot 0 holds a branch                           |
|                  | `bpu_slot_p2.[0].br_type`                | slot 0 branch type                              |
|                  | `bpu_slot_p2.[0].pos`                    | slot 0 halfword position in the fetch block     |
|                  | `bpu_slot_p2.[0].taken`                  | slot 0 predicted direction                      |
|                  | `bpu_slot_p2.[0].target`                 | slot 0 predicted target                         |
|                  | `bpu_slot_p2.[0].pred_src`               | slot 0 predictor that supplied the direction    |
|                  | `bpu_redir_p2.[0].valid`                 | p2 redirect from slot 0                         |
|                  | `bpu_redir_p2.[0].target_pc`             | p2 redirect target from slot 0                  |
|                  | `bpu_redir_idx_p2`                       | FTQ index of the p2 redirect                    |
| ftq              | `u_ftq.w_ok_pred_p1`                     | the FTQ accepts the p1 prediction               |
|                  | `u_ftq.w_ok_slot_p2`                     | the FTQ accepts the p2 group                    |
|                  | `u_ftq.w_ok_slot_p3`                     | the FTQ accepts the p3 group                    |
|                  | `u_ftq.w_ok_redir_p2`                    | the FTQ accepts the p2 redirect                 |
|                  | `u_ftq.w_ok_redir_p3`                    | the FTQ accepts the p3 redirect                 |
|                  | `u_ftq.w_redir_val`                      | a redirect the FTQ takes                        |
|                  | `u_ftq.w_redir_idx`                      | FTQ index of the redirect                       |
|                  | `u_ftq.w_commit_ptr`                     | FTQ commit pointer                              |
|                  | `ftq_full`                               | FTQ full                                        |
|                  | `ftq_empty`                              | FTQ empty                                       |
| loop_pred_update | `u_bpu.w_lp_upd_val_p0`                  | loop predictor update valid, per slot           |
| decode           | `tb.dec_ibuf_rdy`                        | the backend model takes the bundle              |
|                  | `tb.pd_out.[0].valid`                    | lane 0 valid                                    |
|                  | `tb.pd_out.[0].start_pc`                 | lane 0 instruction address                      |
|                  | `tb.pd_out.[0].ftq_idx`                  | lane 0 FTQ index                                |
|                  | `tb.pd_out.[0].pos`                      | lane 0 halfword position in the fetch block     |
|                  | `tb.pd_out.[0].instr`                    | lane 0 instruction, expanded if compressed      |
|                  | `tb.pd_out.[0].is_rvc`                   | lane 0 instruction is 16-bit                    |
|                  | `tb.pd_out.[0].fault_cause`              | lane 0 fetch fault cause                        |
|                  | `tb.pd_out.[0].fault_va`                 | lane 0 fetch fault virtual address              |
