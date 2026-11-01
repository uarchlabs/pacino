<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd04_p2_override: p2 Override
```
 FILE:    fd04_p2_override.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd04_p2_override` is the FD-4 demonstration scenario. It is a demo, not
a verification test. It runs a chain of eight blocks that all index one
uBTB set, which has four ways, while each has its own FTB set. The uBTB
cannot hold the chain, so at p1 most blocks miss and are predicted to
fall through; at p2 the FTB knows the taken branch, the successors
differ, and the cluster raises a p2 redirect. The run passes if the FTQ
accepts at least one p2 redirect.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                            |
  |--------------------|-------------------------------------------------|
  | This file          | $DEMO/docs/fd04_p2_override.md                  |
  | Program (stimulus) | $DEMO/programs/fd04_p2_override.svh             |
  | Surfer sucl        | $DEMO/waves/fd04_p2_override.sucl               |
  | Log                | $DEMO/out/fd04_p2_override/fd04_p2_override.log |
  | Waveform           | $DEMO/out/fd04_p2_override/fd04_p2_override.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd04_p2_override.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd04_p2_override.sucl) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd04_p2_override
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd04_p2_override
```

Console output:
```
-I: fd04_p2_override : PASS : cyc = 522
```

Log file output:
```
-I: fd04_p2_override: PASS, p2 redirects 49, events checked 6 of 6, cyc 522
```

### 2.1 What the monitor counts

The count comes from `tb/fe_demo_mon.svh:424-435`, taken inside the
`meas` window.

```
n_redir_p2   u_ftq.w_ok_redir_p2 && (bpu_redir_p2[0].valid
             || bpu_redir_p2[1].valid)
             a cycle in which the FTQ accepted a p2 redirect
```

The proof (`tb/fe_demo_proofs.svh:60-63`) is `n_redir_p2 > 0`.
`tb_fe_demo.sv` also requires the whole stream to retire with no errors
before it accepts the proof.

### 2.2 Reading the numbers

- `p2 redirects 49` counts cycles in which the FTQ accepted a p2
  redirect. On the two-slot model a cycle with both slots redirecting
  counts once; on this model a cycle has one slot.
- The miss counts are uneven across the chain (2, 3, 3, 14 and 12 for
  b[0] to b[4], none for b[5] and b[6]): which four blocks the set holds
  at a given time depends on the round-robin pointer and the order of
  updates. The figures are from this run.
- Departure from `planning/showcase/fe_demo_scenarios.md` FD-4: its
  program is "a branch whose uBTB entry is stale while its FTB entry is
  current". As built, the mechanism is uBTB capacity: eight blocks in
  one four-way set, so most redirects follow a uBTB miss, not a stale
  hit. 15 of the 49 do follow a hit, all of them b[7]'s, whose uBTB
  entry keeps an end the FTB entry has split. The proof is FD-4's.

---

## 3. The program

Source: `programs/fd04_p2_override.svh`, task `prog_fd04` (tb_fe_top's
ftbonly). `b[k] = RESET_VECTOR + 0x1000 + k * 0x800`, k = 0..7, so b[0]
is 0x80001000 and b[7] is 0x80004800.

```
RESET_VECTOR+0   mixed(3)                                  8 bytes
RESET_VECTOR+8   jal x0,b[0]

b[k], k < 7      c.addi, addi                              6 bytes
b[k]+6           bne x6,x0,b[k+1]     always taken        pos 3

b[7]             c.addi
b[7]+2           bne x6,x0,b[7]+10    taken on the last pass only
b[7]+6           jal x0,b[0]          passes 0..14 (written dry on
                                      the last pass)
b[7]+10          mixed(3)
b[7]+18          jal x0,0             halt (demo_go -> W.halt)
```

- 16 passes over the chain. The code is the same every pass; on the
  last, b[7]'s conditional exits and `d_jal_fill`
  (`fe_tb_writer.svh:530-541`) writes the back-edge JAL in dry mode so
  the bytes stay the same but it is not in the expected stream.
- Outcomes come from the writer (`bcc`, `fe_tb_writer.svh:412-419`).

---

## 4. Walkthrough

### 4.1 Why the program produces p2 redirects

1. One uBTB set. The uBTB index is `pc[10:5]` XOR (`pc[4:1]` << 2),
   the block start's halfword offset folded into the top index bits
   (`get_idx`, `rtl/core/frontend/bpu/rtl/ubtb.sv:135-140`;
   `UBTB_IDX_BITS = 6`, `UBTB_OFFSET_BITS = 5`,
   `bp_defines_pkg.sv:322, 323`). Every b[k] is a multiple of 0x800, so
   its offset is 0 and all eight map to set 0, which has
   `UBTB_WAYS = 4` (`bp_defines_pkg.sv:315`). An update that misses
   takes the way named by the set's round-robin `wr_ptr`
   (`ubtb.sv:478-481`), so at most four of the eight blocks are held
   at a time.
2. Eight FTB sets. The FTB set index is `pc[13:5]` XOR (`pc[4:1]` << 5)
   (`ftb_idx`, `ftb_cntrl.sv:327-331`; `FTB_IDX_BITS = 9`,
   `bp_defines_pkg.sv:176`). With offset 0 the eight blocks fall in
   sets 0x080, 0x0C0, 0x100, 0x140, 0x180, 0x1C0, 0x000 and 0x040
   (derived from the addresses), so the FTB holds all of them.
3. p1 on a uBTB miss predicts fall-through: `w_pft_p1` is the lookup PC
   plus 32 (`bp_cluster.sv:876-878`).
4. p2 comparison. `bp_cluster.sv:1213-1217`: a reachable slot s
   redirects when the FTB answered (`w_ftb_valid_p2`) and its p2
   successor `w_succ_p2[s]` differs from the p1 successor carried in
   `r_succ_p1_p2[s]`. For b[k] the FTB successor is b[k+1] and the p1
   successor is b[k] + 0x20.
5. FTQ acceptance and the new request. `ok_redir_p2`
   (`ftq_shadow.sv:211-212`) requires the stage-2 shadow valid and
   pointer match; `ftq_npc.sv:349-355` (arm 4) then takes the p2
   redirect PC as the next p0 request.

From the FST, the 49 accepted p2 redirects, by block and target:

```
block        target       count   uBTB at p1
0x80001000   0x80001800    2      miss
0x80001800   0x80002000    3      miss
0x80002000   0x80002800    3      miss
0x80002800   0x80003000   14      miss
0x80003000   0x80003800   12      miss
0x80004800   0x80004806   11      hit, end b[7] + 0x20
0x80004800   0x8000480A    4      hit, end b[7] + 0x20
```

34 follow a uBTB miss; 15 follow a uBTB hit for b[7]. "uBTB at p1" is
`r_ubtb_blk_p1.hit` the cycle before, for the same lookup PC. b[5] and
b[6] raise no p2 redirect in this run.

b[7] holds a conditional at position 1 and the jal at position 3. On
this model an FTB entry holds one branch, so when the jal first
resolved in a block from b[7] the FTB split the entry: it keeps the
conditional and ends at the jal's PC, 0x8000_4806 (the split at
update, `planning/arch/ftb_decisions.md` section 3; `ftb_cntrl.sv`,
THE UPDATE, lines 464 to 615). The FTB answer for b[7] therefore ends
the block at 0x8000_4806 (`bpu_blk_pft_p2`). The next block starts at
the jal and predicts it in slot 0. The uBTB entry for b[7] was split
the same way at cyc 193. The set's round-robin replacement then wrote
that way for b[3] at cyc 199. At cyc 203 the conditional's update
allocated b[7] again, with the end of a new entry, b[7] + 0x20. From
then on the jal resolves in the block that starts at 0x8000_4806, so
no update from b[7] carries it, and the uBTB entry for b[7] keeps that
end. Its p1 answer is the conditional not taken with the fall-through
0x8000_4820, past the jal. The FTB's fall-through is 0x8000_4806, so
p2 redirects to the jal's PC; this happens 11 times. The 4 redirects
to 0x8000_480A are the conditional predicted taken at p2 against the
uBTB's not taken. None of the 49 has the cluster's cut set
(`w_cut_p2`, `fe_decisions.md` 10): the FTB entry never reports a
branch no slot carries.

### 4.2 Reading the waveform

The saved view is `waves/fd04_p2_override.sucl`, which `make view
S=fd04_p2_override` opens in Surfer. Look at:

- group `bp_cluster_p1_ubtb`: a p1 block with `r_ubtb_blk_p1.hit` low
  and `bpu_pred_pft_p1` the lookup PC + 0x20.
- group `bp_cluster_p2_ftb`: one cycle later `r_val_p2` and
  `w_ftb_valid_p2`, slot 0 a taken conditional at `pos` 3, and
  `bpu_redir_p2.[0].valid` with `target_pc` the next b[k].
- group `ftq`: `w_ok_redir_p2` accepting it, `w_redir_val` and
  `w_redir_idx`.
- group `bp_cluster_p0`: the next `ftq_pred_pc_p0` is the redirect
  target.

---

## 5. Events

| # | cyc | Event                                                                                                | Other               |
|---|-----|------------------------------------------------------------------------------------------------------|---------------------|
| 0 | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                              | fast init           |
| 1 | 182 | first p2 redirect, from b[0] to b[1] (0x8000_1800): the FTB successor differs from the p1 successor  | accepted by the FTQ |
| 2 | 193 | first p2 redirect to 0x8000_480A: b[7]'s conditional predicted taken at p2                           | from b[7]           |
| 3 | 293 | first p2 redirect to the jal, 0x8000_4806: the end of the FTB entry for b[7] after the split         | from b[7]           |
| 4 | 513 | the chain exits: b[7]'s conditional taken on the last pass, a misprediction; redirect to 0x8000_480A | pass 15, backend    |
| 5 | 522 | the run ends                                                                                         |                     |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd04_p2_override` opens
`waves/fd04_p2_override.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group              | signal                            | description                                     |
|--------------------|-----------------------------------|-------------------------------------------------|
| clock              | `tb.clk`                          | clock                                           |
|                    | `tb.rstn`                         | active low reset                                |
|                    | `tb.cyc`                          | cycle number                                    |
| bp_cluster_p1_ubtb | `bpu_pred_val_p1`                 | p1 prediction valid                             |
|                    | `bpu_pred_idx_p1`                 | FTQ index of the p1 prediction                  |
|                    | `u_bpu.r_ubtb_blk_p1.hit`         | uBTB hit at p1                                  |
|                    | `bpu_pred_pft_p1`                 | p1 fetch block end, the first halfword after it |
|                    | `bpu_pred_slot_p1.[0].slot_valid` | slot 0 holds a branch                           |
|                    | `bpu_pred_slot_p1.[0].br_type`    | slot 0 branch type                              |
|                    | `bpu_pred_slot_p1.[0].pos`        | slot 0 halfword position in the fetch block     |
|                    | `bpu_pred_slot_p1.[0].taken`      | slot 0 predicted direction                      |
|                    | `bpu_pred_slot_p1.[0].target`     | slot 0 predicted target                         |
|                    | `bpu_pred_slot_p1.[0].pred_src`   | slot 0 predictor that supplied the direction    |
| bp_cluster_p2_ftb  | `u_bpu.r_val_p2`                  | p2 valid                                        |
|                    | `bpu_slot_val_p2`                 | slot valid mask                                 |
|                    | `bpu_slot_idx_p2`                 | FTQ index of the p2 group                       |
|                    | `u_bpu.w_ftb_valid_p2`            | FTB hit at p2                                   |
|                    | `bpu_slot_p2.[0].slot_valid`      | slot 0 holds a branch                           |
|                    | `bpu_slot_p2.[0].br_type`         | slot 0 branch type                              |
|                    | `bpu_slot_p2.[0].pos`             | slot 0 halfword position in the fetch block     |
|                    | `bpu_slot_p2.[0].taken`           | slot 0 predicted direction                      |
|                    | `bpu_slot_p2.[0].target`          | slot 0 predicted target                         |
|                    | `bpu_slot_p2.[0].pred_src`        | slot 0 predictor that supplied the direction    |
|                    | `bpu_redir_p2.[0].valid`          | p2 redirect from slot 0                         |
|                    | `bpu_redir_p2.[0].target_pc`      | p2 redirect target from slot 0                  |
|                    | `bpu_redir_idx_p2`                | FTQ index of the p2 redirect                    |
| ftq                | `u_ftq.w_ok_pred_p1`              | the FTQ accepts the p1 prediction               |
|                    | `u_ftq.w_ok_slot_p2`              | the FTQ accepts the p2 group                    |
|                    | `u_ftq.w_ok_slot_p3`              | the FTQ accepts the p3 group                    |
|                    | `u_ftq.w_ok_redir_p2`             | the FTQ accepts the p2 redirect                 |
|                    | `u_ftq.w_ok_redir_p3`             | the FTQ accepts the p3 redirect                 |
|                    | `u_ftq.w_redir_val`               | a redirect the FTQ takes                        |
|                    | `u_ftq.w_redir_idx`               | FTQ index of the redirect                       |
|                    | `u_ftq.w_commit_ptr`              | FTQ commit pointer                              |
|                    | `ftq_full`                        | FTQ full                                        |
|                    | `ftq_empty`                       | FTQ empty                                       |
| bp_cluster_p0      | `ftq_pred_val_p0`                 | p0 request valid                                |
|                    | `ftq_pred_pc_p0`                  | p0 request PC                                   |
|                    | `ftq_pred_idx_p0`                 | p0 request FTQ index                            |
|                    | `u_ftq.u_npc.w_hold`              | holds the p0 request                            |
