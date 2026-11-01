<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd05_p3_override: p3 Override
```
 FILE:    fd05_p3_override.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd05_p3_override` is the FD-5 demonstration scenario. It is a demo, not
a verification test. It runs a loop around two conditional branches
whose outcomes follow short periodic patterns. While TAGE is learning
them, the statistical corrector (SC) at p3 disagrees with the direction
published at p2, the slot's successor changes, and the cluster raises a
p3 redirect with the slot's `pred_src` set to `PRED_SC`. The run passes
if the FTQ accepts at least one such redirect.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).
FD-22 (`docs/fd22_sc_slot1.md`) shows SC reversing the second slot of a
block on the two-slot model.

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                            |
  |--------------------|-------------------------------------------------|
  | This file          | $DEMO/docs/fd05_p3_override.md                  |
  | Program (stimulus) | $DEMO/programs/fd05_p3_override.svh             |
  | Surfer sucl        | $DEMO/waves/fd05_p3_override.sucl               |
  | Log                | $DEMO/out/fd05_p3_override/fd05_p3_override.log |
  | Waveform           | $DEMO/out/fd05_p3_override/fd05_p3_override.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd05_p3_override.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd05_p3_override.sucl) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd05_p3_override
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd05_p3_override
```

Console output:
```
-I: fd05_p3_override : PASS : cyc = 975
```

Log file output:
```
-I: fd05_p3_override: PASS, p3 redirects 33, SC reversals among them 33,
    events checked 8 of 8, cyc 975
```

### 2.1 What the monitor counts

The counts come from `tb/fe_demo_mon.svh:424-438`, taken inside the
`meas` window.

```
n_redir_p3      u_ftq.w_ok_redir_p3 && any bpu_redir_p3[s].valid
                a cycle in which the FTQ accepted a p3 redirect
n_redir_p3_sc   the same, with a redirecting slot s for which
                bpu_slot_val_p3, bpu_slot_idx_p3 == bpu_redir_idx_p3
                and bpu_slot_p3[s].pred_src == PRED_SC
```

The proof (`tb/fe_demo_proofs.svh:64-68`) is `n_redir_p3_sc > 0`.
`tb_fe_demo.sv` also requires the whole stream to retire with no errors
before it accepts the proof.

### 2.2 Reading the numbers

- `p3 redirects 33, SC reversals among them 33`: every accepted p3
  redirect in this run had an SC-decided slot. The p3 direction differs
  from the p2 one only through SC (section 4.1, item 2), which is why
  the two figures agree here.
- Both are counts of cycles, not slots.
- The p2 direction that SC reversed was TAGE's in all 33 (from the FST).
  The monitor does not check that; it checks only `pred_src ==
  PRED_SC` on the p3 slot.
- `n_tage_prov` is not in this scenario's result line. DOC-002 changed
  it to sum the slots of a cycle; on this model a cycle has one slot.
- Departure from `planning/showcase/fe_demo_scenarios.md` FD-5: its
  program is "a branch TAGE predicts weakly and SC corrects". As built,
  two history-dependent conditionals (periods 2 and 3) are run; whether
  TAGE's prediction was weak is not checked by the proof or recorded
  here. The proof is FD-5's.

---

## 3. The program

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
  `cskip(tk, 2)` (`fe_tb_writer.svh:502-519`) writes the skipped
  `mixed(2)` in dry mode when taken, so the code is fixed and only the
  expected stream changes.
- A has period 2, B period 3. Outcomes come from the writer (`bcc`,
  `fe_tb_writer.svh:412-419`), not from x6.
- Lookup blocks that hold A or B, and the position (halfwords from the
  lookup PC) of each: `top` (0x80000008), A at 3; `top+10`
  (0x80000012, after A falls through on a redirect), B at 4; `top+16`
  (0x80000018, A's target), B at 1; `top+18` (0x8000001A), B at 0. On
  this model an FTB entry holds one branch. The entry for `top` holds
  A. Its end is B's PC, top+18 (the split at update,
  `planning/arch/ftb_decisions.md` section 3). B is predicted in the
  block that starts there.

---

## 4. Walkthrough

### 4.1 Why the program produces SC reversals

1. SC answers at p3. `rtl/core/frontend/bpu/rtl/bp_cluster.sv:1296-
   1297`: `w_sc_hit_p3[s]` is the SC response for slot s
   (`w_sc_pred_rdy_p3`), with `sc_enable` (`fe_cfg.sc_enable`,
   `fe_top.sv:486`) and a `branch_id` matching the entry at p3.
2. The direction. Lines 1301-1304: for a conditional slot with an SC
   hit, and no loop-predictor direction at p2 (`~r_lp_use_p3`), the p3
   direction is `sc_pred_tkn`; otherwise the p2 direction.
3. The redirect. Lines 1307-1325: the p3 successors are chained from
   the highest slot down, as at p2, and slot s redirects when it is
   reachable and its p3 successor differs from its p2 successor. A
   p3 redirect therefore fires only where SC changed a direction, or
   where a later slot's change moves an earlier not-taken slot's
   successor.
4. The slot record. Lines 1340-1352 (`p3_slot_comb`): the p3 slot takes
   `sc_pred_tkn`, and `pred_src` becomes `PRED_SC` when that differs
   from the p2 `taken`.
5. FTQ acceptance and the new request: `ok_redir_p3`
   (`rtl/core/frontend/ftq/rtl/ftq_shadow.sv:220-221`); `ftq_npc.sv:
   338-348` (arm 3) takes the p3 PC, ahead of any p2 redirect.

From the FST, the 33 accepted p3 redirects, by the slot SC reversed
(slot 0 in every one):

```
block        branch  pos  p2 pred_src   p3 taken   target       count
0x80000008   A       3    PRED_TAGE     0          0x8000001A      17
0x80000008   A       3    PRED_TAGE     0          0x80000028       2
0x80000008   A       3    PRED_TAGE     1          0x80000018       2
0x80000012   B       4    PRED_TAGE     1          0x80000024       2
0x80000018   B       1    PRED_TAGE     1          0x80000024       7
0x8000001A   B       0    PRED_TAGE     1          0x80000024       3
```

In every one the p2 direction came from TAGE (`r_slot_p3[0].pred_src`
PRED_TAGE). A reversed to not taken redirects to the end of the block
at `top`. Once the FTB entry has been split, that end is B's PC,
0x8000001A; the split is an update for B at position 9 from `top`, at
cyc 261. In the two cases before it the end is `top` + 0x20,
0x80000028. The redirects fall
between cyc 47 and 822 of the 975-cycle run.

### 4.2 Reading the waveform

The saved view is `waves/fd05_p3_override.sucl`, which `make view
S=fd05_p3_override` opens in Surfer. Look at:

- group `tage_p2`: `w_tage_pred_rdy_p2` and `tage_pred_meta_p2.[0]`
  (`tage_prm_comp`, `tage_prm_ctr`, `tage_pred_tkn`) for the block.
- group `bp_cluster_p2`: the p2 slot with `pred_src` PRED_TAGE and its
  `taken`.
- group `sc_p3`: `w_sc_pred_rdy_p3`, `w_sc_hit_p3` and `w_taken_p3`
  opposite to the p2 slot's `taken`.
- group `bp_cluster_p3`: `bpu_slot_p3.[0].pred_src` `PRED_SC` and
  `bpu_redir_p3.[0].valid` with its `target_pc`.
- group `ftq`: `w_ok_redir_p3` accepting it.

---

## 5. Events

| # | cyc | Event                                                                                               | Other                      |
|---|-----|-----------------------------------------------------------------------------------------------------|----------------------------|
| 0 | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                             | fast init                  |
| 1 | 47  | first p3 redirect from an SC reversal: B reversed to taken; redirect to 0x8000_0024, its target     | slot 0, `pred_src` PRED_SC |
| 2 | 178 | A reversed to not taken before the split; redirect to 0x8000_0028, the end of the block at top then | slot 0, PRED_SC            |
| 3 | 261 | the split: the FTB update for B at position 9 from top ends the entry for top at B's PC             | `upd_split`                |
| 4 | 292 | A reversed to not taken after the split; redirect to 0x8000_001A, B's PC                            | slot 0, PRED_SC            |
| 5 | 822 | last p3 redirect from an SC reversal                                                                | the 33rd                   |
| 6 | 965 | back edge falls through, a misprediction; redirect to 0x8000_002A                                   | pass 95, backend           |
| 7 | 975 | the run ends                                                                                        |                            |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd05_p3_override` opens
`waves/fd05_p3_override.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group         | signal                                                               | description                                  |
|---------------|----------------------------------------------------------------------|----------------------------------------------|
| clock         | `tb.clk`                                                             | clock                                        |
|               | `tb.rstn`                                                            | active low reset                             |
|               | `tb.cyc`                                                             | cycle number                                 |
| tage_p2       | `u_bpu.w_tage_pred_rdy_p2`                                           | TAGE response at p2                          |
|               | `u_bpu.u_tage.u_tage_cntrl.tage_pred_meta_p2.[0].tage_prm_comp`      | slot 0 provider table, 0 is T0               |
|               | `u_bpu.u_tage.u_tage_cntrl.tage_pred_meta_p2.[0].tage_alt_comp`      | slot 0 alternate table, 0 is T0              |
|               | `u_bpu.u_tage.u_tage_cntrl.tage_pred_meta_p2.[0].tage_using_primary` | slot 0 is 0 when the alternate provides      |
|               | `u_bpu.u_tage.u_tage_cntrl.tage_pred_meta_p2.[0].tage_prm_ctr`       | slot 0 provider CTR                          |
|               | `u_bpu.u_tage.u_tage_cntrl.tage_pred_meta_p2.[0].tage_pred_tkn`      | slot 0 TAGE direction                        |
| bp_cluster_p2 | `u_bpu.r_val_p2`                                                     | p2 valid                                     |
|               | `bpu_slot_val_p2`                                                    | slot valid mask                              |
|               | `bpu_slot_idx_p2`                                                    | FTQ index of the p2 group                    |
|               | `u_bpu.w_ftb_valid_p2`                                               | FTB hit at p2                                |
|               | `bpu_slot_p2.[0].slot_valid`                                         | slot 0 holds a branch                        |
|               | `bpu_slot_p2.[0].br_type`                                            | slot 0 branch type                           |
|               | `bpu_slot_p2.[0].pos`                                                | slot 0 halfword position in the fetch block  |
|               | `bpu_slot_p2.[0].taken`                                              | slot 0 predicted direction                   |
|               | `bpu_slot_p2.[0].target`                                             | slot 0 predicted target                      |
|               | `bpu_slot_p2.[0].pred_src`                                           | slot 0 predictor that supplied the direction |
|               | `bpu_redir_p2.[0].valid`                                             | p2 redirect from slot 0                      |
|               | `bpu_redir_p2.[0].target_pc`                                         | p2 redirect target from slot 0               |
|               | `bpu_redir_idx_p2`                                                   | FTQ index of the p2 redirect                 |
| sc_p3         | `u_bpu.w_sc_pred_rdy_p3`                                             | SC response at p3                            |
|               | `u_bpu.w_sc_hit_p3.[0]`                                              | SC response for slot 0                       |
|               | `u_bpu.w_taken_p3.[0]`                                               | slot 0 direction at p3                       |
| bp_cluster_p3 | `u_bpu.r_val_p3`                                                     | p3 valid                                     |
|               | `bpu_slot_val_p3`                                                    | slot valid mask                              |
|               | `bpu_slot_idx_p3`                                                    | FTQ index of the p3 group                    |
|               | `bpu_slot_p3.[0].slot_valid`                                         | slot 0 holds a branch                        |
|               | `bpu_slot_p3.[0].br_type`                                            | slot 0 branch type                           |
|               | `bpu_slot_p3.[0].pos`                                                | slot 0 halfword position in the fetch block  |
|               | `bpu_slot_p3.[0].taken`                                              | slot 0 predicted direction                   |
|               | `bpu_slot_p3.[0].target`                                             | slot 0 predicted target                      |
|               | `bpu_slot_p3.[0].pred_src`                                           | slot 0 predictor that supplied the direction |
|               | `bpu_redir_p3.[0].valid`                                             | p3 redirect from slot 0                      |
|               | `bpu_redir_p3.[0].target_pc`                                         | p3 redirect target from slot 0               |
|               | `bpu_redir_idx_p3`                                                   | FTQ index of the p3 redirect                 |
| ftq           | `u_ftq.w_ok_pred_p1`                                                 | the FTQ accepts the p1 prediction            |
|               | `u_ftq.w_ok_slot_p2`                                                 | the FTQ accepts the p2 group                 |
|               | `u_ftq.w_ok_slot_p3`                                                 | the FTQ accepts the p3 group                 |
|               | `u_ftq.w_ok_redir_p2`                                                | the FTQ accepts the p2 redirect              |
|               | `u_ftq.w_ok_redir_p3`                                                | the FTQ accepts the p3 redirect              |
|               | `u_ftq.w_redir_val`                                                  | a redirect the FTQ takes                     |
|               | `u_ftq.w_redir_idx`                                                  | FTQ index of the redirect                    |
|               | `u_ftq.w_commit_ptr`                                                 | FTQ commit pointer                           |
|               | `ftq_full`                                                           | FTQ full                                     |
|               | `ftq_empty`                                                          | FTQ empty                                    |
