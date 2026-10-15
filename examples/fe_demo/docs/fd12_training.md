<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd12_training: Predictor Training and the FTB Update Bubble
```
 FILE:    fd12_training.md
 SOURCE:  DOC-002
 STATUS:  WORKING
 UPDATED: 2026-10-15
 CONTACT: Jeff Nye
```

`fd12_training` is the FD-12 demonstration scenario. It is a demo, not a
verification test. It runs nested counted loops whose body holds every
kind of control transfer the predictors train on: conditionals, an
indirect jump, an indirect call and its return. Each retired control
transfer is resolved by the backend, converted by `ftq_upd_conv` into
per-predictor updates, and presented to the cluster; each FTB update
withholds one p0 request. The run passes if every predictor receives at
least one update and at least one p0 request is withheld for an FTB
update.

A recorded run (DOC-002):

```
DEMO PASS fd12_training: update cycles uBTB 154 LP 112 FTB 154 TAGE 112
SC 112 ITTAGE 28 RAS commit 28; FTB update p0 holds 154 (cycles 449)
```

---

## 1. The program

Source: `programs/fd12_training.svh`, task `prog_fd12`. Bare M-mode,
code at RESET_VECTOR 0x8000_0000 (`bp_defines_pkg.sv:40`). Addresses
below are derived from the writer's emitters (`mixed` is c.addi, addi,
c.addi repeating: 2, 4, 2 bytes).

```
0x8000_0000  mixed(4)                                     10 bytes
otop = +0x0A mixed(2)                     outer body
itop = +0x10 mixed(3)                     inner body
       +0x18 bne x6,x0,itop               inner loop branch, 6 passes
       +0x1C beq x0,x0,+0x28              always taken
       +0x28 mixed(2)
       +0x2E jalr x0,0(x7)  -> +0x6E      indirect jump
       +0x6E mixed(2)
       +0x74 jalr x1,0(x28) -> fn         indirect call
       +0x78 mixed(1)                     return lands here
       +0x7A bne x6,x0,otop               outer loop branch, 14 passes
       +0x7E mixed(3), jal x0,0           halt
fn = 0x8000_0800  mixed(3); jalr x0,0(ra) -> +0x78   return
```

- The loops are built by `loop_br` and `rep_iter`
  (`rtl/core/frontend/fe_top/tb/models/fe_tb_writer.svh:352`, `:364`):
  the body is written once and its expected-stream entries are
  replicated, the last execution of each loop branch not taken.
- `rep_iter(eo, 14)` replicates the outer body including the six inner
  passes already expanded, so the stream holds 14 x 6 inner branches.
- `jalr_to` (`fe_tb_writer.svh:389`) types the jump by the RAS hint
  rules: `jalr x0,0(x7)` is INDIRECT_NONRET, `jalr x1,0(x28)` is
  INDIRECT_CALL; `ret` (`:280`) is RETURN.

Control transfers in the stream, per outer pass: 6 inner branches, the
always-taken `beq`, the indirect jump, the indirect call, the return,
the outer branch. Over 14 passes: 154 transfers, of which 112
conditionals (8 per pass), 28 indirect (jump and call) and 28 RAS
operations (call and return). The halt (`jal x0,0`) is the stream's
last entry; the counts below (154, not 155, for the uBTB and FTB) show
that its update falls after the measurement window closes.

---

## 2. Why the program produces the behaviour

1. Resolution and conversion. `ftq_upd_conv`
   (`rtl/core/frontend/ftq/rtl/ftq_upd_conv.sv`) forms the per-slot
   uBTB, LP, TAGE, ITTAGE and SC payloads from the resolved record. A
   slot's predictor valids are presented only when the slot is
   accepted by every predictor it trains (`upd_acc`, lines 136-138
   and 171; the handshake is described in the file header, lines
   29-36).
2. The cluster's type gate. `bp_cluster` classifies each update
   channel from its uBTB payload (`upd_br_type`,
   `rtl/core/frontend/bpu/rtl/bp_cluster.sv:1678-1685`) and fans it out
   by type (fe_decisions.md 7.2):
   - uBTB: any type but NO_BRANCH (`bp_cluster.sv:1691-1692`)
   - LP: conditionals (`:1617-1618`)
   - TAGE, SC: conditionals, each also gated by its queue ready, SC by
     `sc_enable` (`:1737-1746`)
   - ITTAGE: INDIRECT_NONRET and INDIRECT_CALL (`:1683-1685`,
     `:1740-1742`)
   - FTB: its own channel, a branch or a jump (`:1582-1583`)
   - RAS commit: DIRECT_CALL, INDIRECT_CALL, RETURN, RETURN_CALL
     (`:1588-1592`)
3. The FTB update bubble. The FTB has one read port. When
   `ftq_ftb_sched` will issue an FTB update next cycle (`issue_next`,
   `rtl/core/frontend/ftq/rtl/ftq_ftb_sched.sv:327`, wired to
   `h3_ftb_upd` at `ftq.sv:492`), `ftq_npc` holds its p0 request
   (hold term H3 in `w_hold`, `ftq_npc.sv:307-309`; rationale at
   `ftq_npc.sv:132-137`). One p0 request is withheld per FTB update.

---

## 3. What the monitor counts

The counts come from `tb/fe_demo_mon.svh:464-476`, sampled every cycle
while the stream is being measured (`meas`,
`rtl/core/frontend/fe_top/tb/models/fe_tb_backend.svh:416`). They read
the valids after the cluster's gates.

```
n_upd_ubtb   per slot: w_ubtb_upd_u0[s].valid, summed over the slots
             of the cycle (DOC-002)
n_upd_lp     cycles with w_lp_upd_val_p0 != 0
n_upd_tage   cycles with w_tage_upd_val_u0 != 0
n_upd_itt    cycles with w_ittage_upd_val_u0 != 0
n_upd_sc     cycles with w_sc_upd_val_u0 != 0
n_upd_ftb    cycles with w_ftb_upd_val_u0
n_upd_ras    cycles with w_ras_commit_val
n_ftb_bub    cycles with u_ftq.u_npc.h3_ftb_upd
```

The proof (`tb/fe_demo_proofs.svh:97-99`) requires every one of the
eight counts to be non-zero. `tb_fe_demo.sv` also requires the whole
stream to retire with no errors before it accepts the proof.

---

## 4. Reading the numbers

- The figures match the program's control transfers exactly: uBTB and
  FTB 154 (every transfer), LP, TAGE and SC 112 (the conditionals),
  ITTAGE 28 (the indirect jump and call), RAS commit 28 (the call and
  the return). FTB update p0 holds 154: one per FTB update.
- Except `n_upd_ubtb`, the counters count cycles with any slot valid,
  not slot updates; the DEMO line says "update cycles" for that
  reason. DOC-002 changed `n_upd_ubtb` to sum its slots. In this run
  the counts equal the transfer counts, so no cycle carried an update
  on both slots; a DOC-002 scratch check of `n_upd_ubtb` against an
  independent per-slot count found no such cycle either, and the
  figure is unchanged by the fix.
- Departure from `planning/showcase/fe_demo_scenarios.md` FD-12: the
  program there is "any branch, first execution and the next"; the
  program as built is tb_fe_top's `loops`, with every update type, so
  that the proof can require an update at each predictor. The proof as
  built adds the RAS commit to the predictors FD-12 names.

---

## 5. Waveform

The saved views are `waves/fd12_training.gtkw` (GTKWave, `make view
S=fd12_training`) and `waves/fd12_training.sucl` (Surfer, `make sview
S=fd12_training`). Groups: clock, backend, ftq_upd_conv, ftb_update,
bp_cluster_p0. Look at:

- `bkend_ftq_rsv_val`: a resolution from the backend.
- `w_ubtb_upd_u0.[s].valid`, `w_lp_upd_val_p0`, `w_tage_upd_val_u0`,
  `w_sc_upd_val_u0`, `w_ittage_upd_val_u0`, `w_ras_commit_val`: the
  updates after the cluster's gates, by type.
- `ftb_upd_valid_u0` with `ftb_upd_pc_u0`: an FTB update; in the cycle
  before it `u_npc.h3_ftb_upd` is high, `u_npc.w_hold` is high and
  `ftq_pred_val_p0` is low: the withheld p0 request.
