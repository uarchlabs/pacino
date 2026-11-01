<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd10_pd_redirect: Predecode Redirect
```
 FILE:    fd10_pd_redirect.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd10_pd_redirect` is the FD-10 demonstration scenario. It is a demo,
not a verification test. It runs a chain of JALs to distinct blocks,
three times. On the first pass neither the uBTB nor the FTB knows any of
them, so each block is predicted to fall through. Predecode at F3 finds
the JAL, the IFU writes the block back with a mispredict position, and
the FTQ redirects fetch to the JAL's target. The run passes if at least
one predecode redirect occurred without a backend redirect in the same
cycle.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                            |
  |--------------------|-------------------------------------------------|
  | This file          | $DEMO/docs/fd10_pd_redirect.md                  |
  | Program (stimulus) | $DEMO/programs/fd10_pd_redirect.svh             |
  | Surfer sucl        | $DEMO/waves/fd10_pd_redirect.sucl               |
  | Log                | $DEMO/out/fd10_pd_redirect/fd10_pd_redirect.log |
  | Waveform           | $DEMO/out/fd10_pd_redirect/fd10_pd_redirect.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd10_pd_redirect.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd10_pd_redirect.sucl) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd10_pd_redirect
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd10_pd_redirect
```

Console output:
```
-I: fd10_pd_redirect : PASS : cyc = 255
```

Log file output:
```
-I: fd10_pd_redirect: PASS, predecode redirects 14, events checked 8 of 8,
    cyc 255
```

### 2.1 What the monitor counts

The counter is in the shared models, beside the FTQ fetch log
(`rtl/core/frontend/fe_top/tb/models/fe_tb_be_state.svh:74-75`):

```
n_pd_redir   meas && u_ftq.w_pd_redir_val && !bkend_ftq_redir_val
```

`meas` is the measurement window: out of reset, the backend running and
the stream not yet fully retired (`fe_tb_backend.svh:416`).

The proof (`tb/fe_demo_proofs.svh:93`) is `n_pd_redir > 0`.
`tb_fe_demo.sv:160` also requires the whole stream to retire with no
errors.

### 2.2 Reading the numbers

- 14 is the 13 JALs of the first pass and the `jal` at top+2 once more,
  in the block that starts at top after the back edge's backend
  redirect (cycle 186). After their first retirement from a block the
  uBTB and FTB predict them from that block's start, so the rest of the
  second pass and the third add none.
- A predecode redirect in the same cycle as a backend redirect is lost
  to the backend redirect in the arbiter and is not counted (cycle
  175).
- After the run ends (cycle 255) `w_pd_redir_val` keeps pulsing about
  every 9 cycles while the front end runs on during the drain; the
  monitor does not count the drain.
- Spec and build agree. FD-10's program is "a JAL in code not yet seen
  by the uBTB or FTB"; the build uses 13 such JALs (tb_fe_top `jals`)
  and runs them three times, so the trained passes show the same JALs
  predicted.

---

## 3. The program

Source: `programs/fd10_pd_redirect.svh`, task `prog_fd10` (line 20).
Addresses derived from the source (`RESET_VECTOR` 0x8000_0000):

```
0x8000_0000          mixed(3)
top = 0x8000_0008    c.addi
top+2                jal x0,T0
T(k) = 0x8000_0200 + k*0x60, k = 0..11:
  T(k)               mixed(2)               6 bytes
  T(k)+6             jal x0,T(k+1)          (k = 11: jal x0,top+0x100)
top+0x100 = 0x8000_0108
                     c.addi
0x8000_010A          bne x6,x0,top          taken on passes 0 and 1
0x8000_010E          mixed(3)
0x8000_0116          jal x0,0               halt (demo_go -> W.halt)
```

- 13 JALs per pass: the 12 of the chain and the one to top+0x100. Each
  is `DIRECT_UNC` (rd x0; `jal`,
  `rtl/core/frontend/fe_top/tb/models/fe_tb_writer.svh:268`).
- Each target block is 0x60 bytes from the last, so every JAL starts a
  new fetch block.
- The writer decides the back edge (`bcc`, `fe_tb_writer.svh:412`).

---

## 4. Walkthrough

### 4.1 Why the program produces the behavior

1. No prediction on the first pass. The uBTB and FTB are trained from
   resolved branches (FD-12), so before a JAL first retires the block
   holding it is predicted with no taken slot.
2. F3 check M1. Predecode marks each position's control-transfer type.
   The first valid JAL in the block that is before the predicted taken
   position, or anywhere when nothing is predicted taken, sets
   `w_mis_val` at its position (`w_m1_val`,
   `rtl/core/frontend/ifu/rtl/ifu_f3.sv:310-329`). The writeback
   registers it as `ifu_ftq_mis_val` (`ifu/rtl/ifu_wb.sv:86`).
3. The FTQ redirect. The FTQ's IFU interface raises `pd_redir_val` when
   it accepts a writeback with `ifu_ftq_mis_val` not already received
   for the entry, with the corrected successor as `pd_redir_pc`
   (`rtl/core/frontend/ftq/rtl/ftq_ifu.sv:548-550`). In the p0 arbiter
   it is arm 2, below a backend redirect and above p3 and p2
   (`rtl/core/frontend/ftq/rtl/ftq_npc.sv:329-337`).
4. Flush. Any redirect raises `ftq_ifu_flush_val`
   (`ftq_ifu.sv:352`), which drops the blocks younger than the
   redirected entry in the IFU, and the redirect rolls back history
   (`rollback_val`, `ftq_npc.sv:399`).

From the run (out/fd10_pd_redirect/fd10_pd_redirect.fst): `w_pd_redir_val`
pulses 13 times between cycles 19 and 165, with `w_pd_redir_pc` the
chain targets 0x8000_0200 to 0x8000_0620 in order and then 0x8000_0108.
At cycle 175 it pulses for the halt's `jal` at 0x8000_0116, fetched
past the cold back edge, as the backend raises its redirect for the
back edge (`bkend_ftq_redir_val`, high in cycle 176, to 0x8000_0008);
the counter sees both at the end of cycle 175 and does not count it.
At cycle 186 it pulses for the `jal` at top+2, with `w_pd_redir_pc`
0x8000_0200. The backend redirect restarted fetch at top. The
predictors have not seen this block start, since each block start has
its own entry (BP-140). The `jal` in it is found at F3 again. The third
pass has no predecode redirect.

### 4.2 Reading the waveform

The saved view is `waves/fd10_pd_redirect.sucl`, which `make view
S=fd10_pd_redirect` opens in Surfer. Look at:

- ifu_f3 group: `ifu_ftq_pdwb_val` with `ifu_ftq_mis_val` set,
  `ifu_ftq_mis_pos` the JAL's position and `ifu_ftq_target` its target.
- `w_pd_redir_val` the same cycle, and the next `ftq_pred_pc_p0` the
  target (bp_cluster_p0 group).
- ftq_ifu group: `ftq_ifu_flush_val` with `ftq_ifu_flush_idx`, then
  `ftq_ifu_req_val` with `ftq_ifu_start_pc` the target.
- Compare cycles 19-165 (first pass) with the second pass, where the
  chain's blocks are predicted taken and no writeback for them carries
  `ifu_ftq_mis_val`.

---

## 5. Events

| # | cyc | Event                                                                                                                                                                | Other                    |
|---|-----|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------|
| 0 | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                                                                                              | fast init                |
| 1 | 19  | first predecode redirect: the jal at top + 2, found at F3, to T(0), 0x8000_0200                                                                                      | pass 0                   |
| 2 | 165 | the 13th predecode redirect: the jal of T(11), to 0x8000_0108                                                                                                        | pass 0                   |
| 3 | 175 | a predecode redirect to 0x8000_0116, the halt's jal fetched past the cold back edge; the backend's redirect takes the next request, so the monitor does not count it | not counted              |
| 4 | 176 | the back edge mispredicted, cold; redirect to 0x8000_0008                                                                                                            | backend                  |
| 5 | 186 | last predecode redirect: the jal at top + 2 again, to 0x8000_0200, in the block that starts at top                                                                   | pass 1, the 14th counted |
| 6 | 246 | back edge falls through, a misprediction; redirect to 0x8000_010E                                                                                                    | pass 2, backend          |
| 7 | 255 | the run ends                                                                                                                                                         |                          |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd10_pd_redirect` opens
`waves/fd10_pd_redirect.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group         | signal                 | description                                       |
|---------------|------------------------|---------------------------------------------------|
| clock         | `tb.clk`               | clock                                             |
|               | `tb.rstn`              | active low reset                                  |
|               | `tb.cyc`               | cycle number                                      |
| ftq_ifu       | `ftq_ifu_req_val`      | FTQ presents a block to the IFU                   |
|               | `ftq_ifu_req_rdy`      | the IFU takes the block                           |
|               | `ftq_ifu_idx`          | FTQ index of the block                            |
|               | `ftq_ifu_start_pc`     | block start address                               |
|               | `ftq_ifu_next_pc`      | address after the block                           |
|               | `ftq_ifu_taken_val`    | the block holds a predicted-taken transfer        |
|               | `ftq_ifu_taken_pos`    | halfword position of the predicted-taken transfer |
|               | `ftq_ifu_flush_val`    | flush of the blocks younger than the named entry  |
|               | `ftq_ifu_flush_idx`    | FTQ index the flush names                         |
|               | `ftq_ifu_commit_ptr`   | FTQ commit pointer as the IFU sees it             |
| ifu_f3        | `ifu_ftq_pdwb_val`     | predecode writeback to the FTQ                    |
|               | `ifu_ftq_pdwb_idx`     | FTQ index of the writeback                        |
|               | `ifu_ftq_cfi_val`      | the writeback reports a control transfer          |
|               | `ifu_ftq_cfi_pos`      | halfword position of the control transfer         |
|               | `ifu_ftq_mis_val`      | the writeback reports a mispredict position       |
|               | `ifu_ftq_mis_pos`      | the mispredict position                           |
|               | `ifu_ftq_target`       | the corrected target                              |
|               | `u_ftq.w_pd_redir_val` | predecode redirect                                |
| ftq           | `u_ftq.w_ok_pred_p1`   | the FTQ accepts the p1 prediction                 |
|               | `u_ftq.w_ok_slot_p2`   | the FTQ accepts the p2 group                      |
|               | `u_ftq.w_ok_slot_p3`   | the FTQ accepts the p3 group                      |
|               | `u_ftq.w_ok_redir_p2`  | the FTQ accepts the p2 redirect                   |
|               | `u_ftq.w_ok_redir_p3`  | the FTQ accepts the p3 redirect                   |
|               | `u_ftq.w_redir_val`    | a redirect the FTQ takes                          |
|               | `u_ftq.w_redir_idx`    | FTQ index of the redirect                         |
|               | `u_ftq.w_commit_ptr`   | FTQ commit pointer                                |
|               | `ftq_full`             | FTQ full                                          |
|               | `ftq_empty`            | FTQ empty                                         |
| bp_cluster_p0 | `ftq_pred_val_p0`      | p0 request valid                                  |
|               | `ftq_pred_pc_p0`       | p0 request PC                                     |
|               | `ftq_pred_idx_p0`      | p0 request FTQ index                              |
|               | `u_ftq.u_npc.w_hold`   | holds the p0 request                              |
