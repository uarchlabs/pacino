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

`fd06_loop_pred` is the FD-6 demonstration scenario. It is a demo, not a
verification test. It runs a counted inner loop of 10 iterations inside
an outer loop of 16 passes. The loop predictor (LP) learns the inner
loop's trip count, reaches full confidence, and from then on supplies
the inner loop branch's direction, including the not-taken exit. The run
passes if at least one retired exit was predicted not taken by the LP.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).
A recorded run:

```
-I: fd06_loop_pred: PASS, loop exits predicted by the loop predictor 8, cyc 439
```

---

## 1. The program

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

## 2. Why the program produces the behavior

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

---

## 3. What the monitor counts

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

---

## 4. Reading the numbers

- 8 of the 16 inner exits were predicted not taken by the LP. Of the
  other 8, four were mispredicted (the backend redirects of section
  2); for the other four, the slot that predicted them was not traced.
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

## 5. Waveform

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
