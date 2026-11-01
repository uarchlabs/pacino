<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd08_indirect: Indirect Jump
```
 FILE:    fd08_indirect.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd08_indirect` is the FD-8 demonstration scenario. It is a demo, not a
verification test. Each of 40 passes runs an indirect jump and an
indirect call whose targets alternate between two addresses from pass
to pass. Each is preceded by a conditional whose direction alternates
with it, so global history tells the two cases apart. The FTB holds one
target per jump; ITTAGE learns both targets under their histories and
supplies the right one at p2. The run passes if at least one retired
indirect took its correct target from ITTAGE.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                      |
  |--------------------|-------------------------------------------|
  | This file          | $DEMO/docs/fd08_indirect.md               |
  | Program (stimulus) | $DEMO/programs/fd08_indirect.svh          |
  | Surfer sucl        | $DEMO/waves/fd08_indirect.sucl            |
  | Log                | $DEMO/out/fd08_indirect/fd08_indirect.log |
  | Waveform           | $DEMO/out/fd08_indirect/fd08_indirect.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd08_indirect.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd08_indirect.sucl) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd08_indirect
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd08_indirect
```

Console output:
```
-I: fd08_indirect : PASS : cyc = 1147
```

Log file output:
```
-I: fd08_indirect: PASS, indirect targets predicted by ITTAGE 50,
    events checked 7 of 7, cyc 1147
```

### 2.1 What the monitor counts

At retirement (`tb/fe_demo_mon.svh:311-316`):

```
n_itt_ok   a retired INDIRECT_NONRET or INDIRECT_CALL whose FTQ entry's
           final slot at its position is valid, has
           pred_src == PRED_ITTAGE, is taken, and has the expected
           target
```

The final slot is the last group the FTQ accepted for the entry, p1 then
p2 then p3 (`fin_log`, `tb/fe_demo_mon.svh:270-279`).

The proof (`tb/fe_demo_proofs.svh:83`) is `n_itt_ok > 0`.
`tb_fe_demo.sv:160` also requires the whole stream to retire with no
errors.

### 2.2 Reading the numbers

- 50 of the 80 retired indirects had their right target from ITTAGE.
  The other 30 include the first executions of each, before ITTAGE has
  allocated; their sources were not traced one by one. On the two-slot
  model the same program gives 58 (DOC-007 run).
- A target from ITTAGE that is wrong is not counted, and neither is one
  that reached the entry's final slot from another predictor.
- Departure from FD-8 in `planning/showcase/fe_demo_scenarios.md`: the
  spec's program is "an indirect jump through a table with a repeating
  target pattern". The build has no table: an indirect jump and an
  indirect call whose targets alternate, each after a conditional that
  alternates with it (tb_fe_top `indir`). The proof matches the spec.

---

## 3. The program

Source: `programs/fd08_indirect.svh`, task `prog_fd08` (line 19).
Addresses derived from the source (`RESET_VECTOR` 0x8000_0000); `odd` is
pass number mod 2:

```
top = 0x8000_0008   c.addi
top+2       A:      bne x6,x0,top+8    taken when odd; skips one c.addi
top+8       J:      jalr x0,0(x7)      to ta (odd) or tb (even)
ta = 0x8000_0400    mixed(2); jal x0,jn
tb = 0x8000_0480    mixed(1); jal x0,jn
jn = 0x8000_0500    c.addi
jn+2        C:      bne x6,x0,jn+8     taken when even
jn+8        K:      jalr x1,0(x28)     call fa (odd) or fb (even)
fa = 0x8000_0600    mixed(2); ret
fb = 0x8000_0680    mixed(1); ret
jn+12               c.addi
jn+14               bne x6,x0,jn+22    taken on the last pass (exit)
jn+18               jal x0,top         back to top on passes 0..38
```

- The writer decides every outcome and target (`bcc`, `jalr_to`,
  `rtl/core/frontend/fe_top/tb/models/fe_tb_writer.svh:412` and
  `:389`). `jalr_to` writes `jalr rd, 0(rs1)`, the same encoding every
  pass (`enc_jalr`, line 345); the backend retires against the expected
  stream, so x7 and x28 are never read.
- J is `INDIRECT_NONRET` (neither register a link) and K is
  `INDIRECT_CALL` (rd x1), by the type rule of `jalr_to`
  (`fe_tb_writer.svh:396-401`). The `ret` in fa and fb is a RETURN,
  predicted by the RAS.
- `exit_or_jal` (`fe_tb_writer.svh:615`) writes the loop exit.
- 40 passes give 80 retired indirects: J and K retire 40 times each,
  20 times to each of their two targets (derived from the source).

---

## 4. Walkthrough

### 4.1 Why the program produces the behavior

1. The FTB jump slot holds one target per jump (`jmp.tgt`, written from
   `ftb_upd_jmp_target_u0`,
   `rtl/core/frontend/bpu/rtl/ftb_cntrl.sv:553-554`). A target that changes
   every pass is wrong at p2 whenever the FTB target is the one used.
2. ITTAGE takes the folded global history (`folded_hist`,
   `rtl/core/frontend/bpu/rtl/ittage.sv:53-54`). A and C alternate
   in step with the targets, so the history at J and at K differs
   between odd and even passes and the two targets fall in different
   entries.
3. Allocation. A target mispredict allocates when the provider is not
   the last table and a candidate exists (`alc_upd`,
   `rtl/core/frontend/bpu/rtl/ittage_cntrl.sv:832-850`); the new entry
   holds the resolved target.
4. Selection at p2. For an `INDIRECT_NONRET` or `INDIRECT_CALL` slot the
   cluster takes the ITTAGE target when ITTAGE answered for this entry
   with a tagged hit (`it_hit`,
   `rtl/core/frontend/bpu/rtl/bp_cluster.sv:1148-1150`), primary or
   alternate target by `ittage_using_primary` (lines 1151-1153), and
   records `pred_src = PRED_ITTAGE`; otherwise the FTB jump target and
   `PRED_FTB` (lines 1171-1174). `ittage_hit` is the primary-table hit
   (`ittage_cntrl.sv:557`).

### 4.2 Reading the waveform

The saved view is `waves/fd08_indirect.sucl`, which `make view
S=fd08_indirect` opens in Surfer. Look at:

- `w_ittage_pred_rdy_p2` with `w_ittage_pred_meta_p2.[0].ittage_hit`
  set and `ittage_prm_tgt` (VA[40:1]) alternating between the two
  targets of the slot.
- `bpu_slot_p2.[0]`: on the jump's slot, `pred_src` `PRED_ITTAGE` and
  `target` 0x8000_0400 / 0x8000_0480 for J, 0x8000_0600 / 0x8000_0680
  for K.
- `bpu_redir_p2.[0]` with `w_ok_redir_p2`: a p2 redirect, the p2
  target differing from the block's p1 prediction.

---

## 5. Events

| # | cyc  | Event                                                                                                 | Other               |
|---|------|-------------------------------------------------------------------------------------------------------|---------------------|
| 0 | 0    | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                               | fast init           |
| 1 | 20   | first misprediction of J; redirect to tb, 0x8000_0480                                                 | pass 0, backend     |
| 2 | 260  | first ITTAGE tagged hit at p2 (`ittage_hit`)                                                          | slot 0              |
| 3 | 260  | first target of K from ITTAGE: the call's slot at p2 has `pred_src` PRED_ITTAGE                       | accepted by the FTQ |
| 4 | 267  | first target of J from ITTAGE: the jump's slot at p2 has `pred_src` PRED_ITTAGE                       | accepted by the FTQ |
| 5 | 1138 | the loop exits: its last conditional taken on the last pass, a misprediction; redirect to 0x8000_0516 | pass 39, backend    |
| 6 | 1147 | the run ends                                                                                          |                     |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd08_indirect` opens
`waves/fd08_indirect.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group         | signal                                            | description                                  |
|---------------|---------------------------------------------------|----------------------------------------------|
| clock         | `tb.clk`                                          | clock                                        |
|               | `tb.rstn`                                         | active low reset                             |
|               | `tb.cyc`                                          | cycle number                                 |
| ittage_p2     | `u_bpu.w_ittage_pred_rdy_p2`                      | ITTAGE response at p2                        |
|               | `u_bpu.w_ittage_pred_meta_p2.[0].ittage_hit`      | slot 0 ITTAGE primary table hit              |
|               | `u_bpu.w_ittage_pred_meta_p2.[0].ittage_prm_comp` | slot 0 ITTAGE primary table                  |
|               | `u_bpu.w_ittage_pred_meta_p2.[0].ittage_prm_tgt`  | slot 0 ITTAGE primary target, VA[40:1]       |
| bp_cluster_p2 | `u_bpu.r_val_p2`                                  | p2 valid                                     |
|               | `bpu_slot_val_p2`                                 | slot valid mask                              |
|               | `bpu_slot_idx_p2`                                 | FTQ index of the p2 group                    |
|               | `u_bpu.w_ftb_valid_p2`                            | FTB hit at p2                                |
|               | `bpu_slot_p2.[0].slot_valid`                      | slot 0 holds a branch                        |
|               | `bpu_slot_p2.[0].br_type`                         | slot 0 branch type                           |
|               | `bpu_slot_p2.[0].pos`                             | slot 0 halfword position in the fetch block  |
|               | `bpu_slot_p2.[0].taken`                           | slot 0 predicted direction                   |
|               | `bpu_slot_p2.[0].target`                          | slot 0 predicted target                      |
|               | `bpu_slot_p2.[0].pred_src`                        | slot 0 predictor that supplied the direction |
|               | `bpu_redir_p2.[0].valid`                          | p2 redirect from slot 0                      |
|               | `bpu_redir_p2.[0].target_pc`                      | p2 redirect target from slot 0               |
|               | `bpu_redir_idx_p2`                                | FTQ index of the p2 redirect                 |
| ftq           | `u_ftq.w_ok_pred_p1`                              | the FTQ accepts the p1 prediction            |
|               | `u_ftq.w_ok_slot_p2`                              | the FTQ accepts the p2 group                 |
|               | `u_ftq.w_ok_slot_p3`                              | the FTQ accepts the p3 group                 |
|               | `u_ftq.w_ok_redir_p2`                             | the FTQ accepts the p2 redirect              |
|               | `u_ftq.w_ok_redir_p3`                             | the FTQ accepts the p3 redirect              |
|               | `u_ftq.w_redir_val`                               | a redirect the FTQ takes                     |
|               | `u_ftq.w_redir_idx`                               | FTQ index of the redirect                    |
|               | `u_ftq.w_commit_ptr`                              | FTQ commit pointer                           |
|               | `ftq_full`                                        | FTQ full                                     |
|               | `ftq_empty`                                       | FTQ empty                                    |
