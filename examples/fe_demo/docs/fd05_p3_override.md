<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd05_p3_override: p3 Override
```
 FILE:    fd05_p3_override.md
 SOURCE:  DOC-002
 STATUS:  WORKING
 UPDATED: 2026-10-15
 CONTACT: Jeff Nye
```

`fd05_p3_override` is the FD-5 demonstration scenario. It is a demo, not
a verification test. It runs a loop around two conditional branches
whose outcomes follow short periodic patterns. While TAGE is learning
them, the statistical corrector (SC) at p3 disagrees with the direction
published at p2, the slot's successor changes, and the cluster raises a
p3 redirect with the slot's `pred_src` set to `PRED_SC`. The run passes
if the FTQ accepts at least one such redirect.

A recorded run (DOC-002):

```
DEMO PASS fd05_p3_override: p3 redirects 49, of them SC reversals 49
(cycles 968)
```

---

## 1. The program

Source: `programs/fd05_p3_override.svh`, task `prog_fd05` (tb_fe_top's
hist). `top = RESET_VECTOR + 8` (0x80000008).

```
RESET_VECTOR+0   mixed(3)                                  8 bytes
top              c.addi, addi                              6 bytes
top+6    A       bne x6,x0,top+16     taken on odd passes
top+10           c.addi, addi         skipped when A is taken
top+16           c.addi
top+18   B       bne x6,x0,top+28     taken when pass % 3 == 2
top+22           c.addi, addi         skipped when B is taken
top+28           c.addi
top+30           bne x6,x0,top        back edge: taken on passes 0..94
top+34           mixed(3)
top+42           jal x0,0             halt (demo_go -> W.halt)
```

- 96 passes. Each pass resets `W.wp = top` and writes the same bytes;
  `cskip(tk, 2)` (`fe_tb_writer.svh:502-521`) writes the skipped
  `mixed(2)` in dry mode when taken, so the code is fixed and only the
  expected stream changes.
- A has period 2, B period 3. Outcomes come from the writer (`bcc`,
  `fe_tb_writer.svh:412-421`), not from x6.
- Lookup blocks that hold A or B, and the position (halfwords from the
  lookup PC) of each: `top` (0x80000008), A at 3 and B at 9;
  `top+10` (0x80000012, after A falls through on a redirect), B at 4;
  `top+16` (0x80000018, A's target), B at 1.

---

## 2. Why the program produces SC reversals

1. SC answers at p3. `rtl/core/frontend/bpu/rtl/bp_cluster.sv:1235-
   1236`: `w_sc_hit_p3[s]` is the SC response for slot s
   (`w_sc_pred_rdy_p3`), with `sc_enable` (`fe_cfg.sc_enable`,
   `fe_top.sv:486`) and a `branch_id` matching the entry at p3.
2. The direction. Lines 1240-1243: for a conditional slot with an SC
   hit, and no loop-predictor direction at p2 (`~r_lp_use_p3`), the p3
   direction is `sc_pred_tkn`; otherwise the p2 direction.
3. The redirect. Lines 1247-1263: the p3 successors are chained from
   the highest slot down, as at p2, and slot s redirects when it is
   reachable and its p3 successor differs from its p2 successor. A
   p3 redirect therefore fires only where SC changed a direction, or
   where a later slot's change moves an earlier not-taken slot's
   successor.
4. The slot record. Lines 1279-1292 (`p3_slot_comb`): the p3 slot takes
   `sc_pred_tkn`, and `pred_src` becomes `PRED_SC` when that differs
   from the p2 `taken`.
5. FTQ acceptance and the new request: `ok_redir_p3`
   (`rtl/core/frontend/ftq/rtl/ftq_shadow.sv:220-221`); `ftq_npc.sv:
   338-348` (arm 3) takes the p3 PC, ahead of any p2 redirect.

From the FST, the 49 accepted p3 redirects, by the slot SC reversed:

```
block        branch  pos  p2 pred_src   p3 taken   count
0x80000008   A       3    PRED_TAGE     0          29
0x80000008   B       9    PRED_TAGE     0 or 1      4
0x80000012   B       4    PRED_TAGE     1           2
0x80000018   B       1    PRED_TAGE     1          14
```

In every one the p2 direction came from TAGE (`r_slot_p3[s].pred_src`
3). In the four B cycles of block 0x80000008 both slots redirect: SC
reverses B in slot 1, and slot 0 (A, not taken) redirects as well
because its successor is slot 1's. The redirects fall between cycles 46
and 723 of the 968-cycle run.

---

## 3. What the monitor counts

The counts come from `tb/fe_demo_mon.svh:386-400`, taken inside the
`meas` window.

```
n_redir_p3      u_ftq.w_ok_redir_p3 && any bpu_redir_p3[s].valid
                a cycle in which the FTQ accepted a p3 redirect
n_redir_p3_sc   the same, with a redirecting slot s for which
                bpu_slot_val_p3, bpu_slot_idx_p3 == bpu_redir_idx_p3
                and bpu_slot_p3[s].pred_src == PRED_SC
```

The proof (`tb/fe_demo_proofs.svh:53-57`) is `n_redir_p3_sc > 0`.
`tb_fe_demo.sv` also requires the whole stream to retire with no errors
before it accepts the proof.

---

## 4. Reading the numbers

- `p3 redirects 49, of them SC reversals 49`: every accepted p3
  redirect in this run had an SC-decided slot. The p3 direction differs
  from the p2 one only through SC (section 2, item 2), which is why
  the two figures agree here.
- Both are counts of cycles, not slots.
- The p2 direction that SC reversed was TAGE's in all 49 (from the FST).
  The monitor does not check that; it checks only `pred_src ==
  PRED_SC` on the p3 slot.
- `n_tage_prov` is not in this scenario's DEMO line. It is the one
  counter the DOC-002 monitor fix changes in this run: 25 cycles had
  both slots with a tagged provider, so it read 60 before the fix and
  reads 85 now.
- Departure from `planning/showcase/fe_demo_scenarios.md` FD-5: its
  program is "a branch TAGE predicts weakly and SC corrects". As built,
  two history-dependent conditionals (periods 2 and 3) are run; whether
  TAGE's prediction was weak is not checked by the proof or recorded
  here. The proof is FD-5's.

---

## 5. Waveform

The saved view is `waves/fd05_p3_override.sucl`, which `make view
S=fd05_p3_override` opens in Surfer. Look at:

- group `tage_p2`: `w_tage_pred_rdy_p2` and `tage_pred_meta_p2.[s]`
  (`tage_prm_comp`, `tage_prm_ctr`, `tage_pred_tkn`) for the block.
- group `bp_cluster_p2`: the p2 slot with `pred_src` 3 and its `taken`.
- group `sc_p3`: `w_sc_pred_rdy_p3`, `w_sc_hit_p3` and `w_taken_p3`
  opposite to the p2 slot's `taken`.
- group `bp_cluster_p3`: `bpu_slot_p3.[s].pred_src` 4 (`PRED_SC`) and
  `bpu_redir_p3.[s].valid` with its `target_pc`.
- group `ftq`: `w_ok_redir_p3` accepting it.
