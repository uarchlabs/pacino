<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd11_be_mispredict: Backend Mispredict
```
 FILE:    fd11_be_mispredict.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd11_be_mispredict` is the FD-11 demonstration scenario. It is a demo,
not a verification test. Each of 32 passes runs a conditional with a
pseudo-random outcome, then a call and its return. The predictors
cannot learn the conditional, so the backend resolves it against the
prediction and redirects. The redirect squashes the younger FTQ
entries, flushes the IFU, rolls back and corrects the global history,
restores the RAS pointers from the entry's snapshot, and fetch restarts
at the corrected PC. The run passes if a backend mispredict redirect is
followed by a fetch that starts at the redirect PC.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                                |
  |--------------------|-----------------------------------------------------|
  | This file          | $DEMO/docs/fd11_be_mispredict.md                    |
  | Program (stimulus) | $DEMO/programs/fd11_be_mispredict.svh               |
  | Surfer sucl        | $DEMO/waves/fd11_be_mispredict.sucl                 |
  | Log                | $DEMO/out/fd11_be_mispredict/fd11_be_mispredict.log |
  | Waveform           | $DEMO/out/fd11_be_mispredict/fd11_be_mispredict.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd11_be_mispredict.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd11_be_mispredict.sucl) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd11_be_mispredict
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd11_be_mispredict
```

Console output:
```
-I: fd11_be_mispredict : PASS : cyc = 480
```

Log file output:
```
-I: fd11_be_mispredict: PASS, backend mispredict redirects 21,
    fetches at the redirect address 21, history rollbacks 82, RAS restores 82,
    events checked 9 of 9, cyc 480
```

### 2.1 What the monitor counts

Every cycle (`tb/fe_demo_mon.svh:488-501`):

```
n_be_misp    bkend_ftq_redir_val with cause RC_MISPREDICT; it arms a
             wait for the next fetch, with the redirect PC
n_be_fix     the first FTQ fetch after it (ftq_ifu_req_val and
             ftq_ifu_req_rdy, no flush that cycle) whose
             ftq_ifu_start_pc is the redirect PC
n_rollback   ftq_rollback_val
n_ras_rest   ras_restore_val
```

The proof (`tb/fe_demo_proofs.svh:100`) is `n_be_fix > 0`.
`tb_fe_demo.sv:160` also requires the whole stream to retire with no
errors.

### 2.2 Reading the numbers

- 21 of 21 backend mispredicts were followed by a fetch at the
  corrected PC.
- `rollbacks` and `RAS restores` are equal because the two are one net
  (`ftq.sv:518`). They count every redirect the FTQ takes with a cause,
  from any arm: backend, predecode, p3 and p2. So 82 includes the 21
  backend redirects and 61 from the other arms. `RAS restores` counts
  `ras_restore_val` at the FTQ, before bp_cluster drops the restore of
  a block's own p2 or p3 redirect.
- Departure from FD-11 in `planning/showcase/fe_demo_scenarios.md`: the
  spec's program is "a data-dependent branch the predictors get wrong".
  The build's branch has a pseudo-random outcome chosen by the writer
  (tb_fe_top `misp_call`); no data dependence is modeled. The proof
  matches the spec.

---

## 3. The program

Source: `programs/fd11_be_mispredict.svh`, task `prog_fd11` (line 21).
Addresses derived from the source (`RESET_VECTOR` 0x8000_0000):

```
0x8000_0000          mixed(3)
top = 0x8000_0008    c.addi
0x8000_000A   A:     bne x6,x0,0x8000_0010   taken when the LFSR bit is 1
0x8000_000E          c.addi                  skipped when A is taken
0x8000_0010          jal x1,fn               call, link 0x8000_0014
fn = 0x8000_0400     mixed(2); ret           return to 0x8000_0014
0x8000_0014          c.addi
0x8000_0016   E:     bne x6,x0,top           back edge, passes 0..30
0x8000_001A          mixed(3)
                     jal x0,0                halt (demo_go -> W.halt)
```

- A's direction is one bit of the writer's 16-bit Galois LFSR, taps
  0xB400, seed 0xACE1 (`lfsr_bit`,
  `rtl/core/frontend/fe_top/tb/models/fe_tb_writer.svh:523`). Computed
  outside the testbench from that seed, the 32 bits are
  `10000111001000110100011011011100`: 15 taken, 17 not taken.
- Each pass writes the same bytes (`W.wp = top`); `cskip`
  (`fe_tb_writer.svh:502`) writes the skipped c.addi dry when A is
  taken. The backend retires against the writer's expected stream, so
  x6 is never read.

---

## 4. Walkthrough

### 4.1 Why the program produces the behavior

1. The backend redirect. The in-order backend resolves each branch
   against the FTQ's prediction and on a difference raises
   `bkend_ftq_redir_val` with `bkend_ftq_redir_cause` `RC_MISPREDICT`
   (2'b00, `rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv:126`) and the
   correct PC.
2. Priority. In the FTQ's p0 arbiter a backend redirect is arm 1 and
   outranks every BPU and predecode redirect
   (`rtl/core/frontend/ftq/rtl/ftq_npc.sv:317-328`); the next p0
   request is `bkend_redir_pc`.
3. Squash and flush. Every redirect raises `ftq_ifu_flush_val`
   (`rtl/core/frontend/ftq/rtl/ftq_ifu.sv:352`), dropping the IFU's
   younger blocks.
4. History rollback and correction. A redirect with a cause other than
   `RC_UNSPEC` raises `ftq_rollback_val` (`ftq_npc.sv:399`). bp_history
   restores the pointer from the named entry's checkpoint; with
   `rollback_corr` set it writes the corrected outcome bits
   (`rollback_n`, `rollback_tkn`, `rollback_pbit`) and advances past
   them (`rtl/core/frontend/bpu/rtl/bp_history.sv:43-58`).
5. RAS restore. `ras_restore_val` is `ftq_rollback_val`
   (`rtl/core/frontend/ftq/rtl/ftq.sv:518`): the RAS restores TOSR, TOSW
   and BOS from the entry's snapshot (`ras_restore_snapshot`, port
   `rtl/core/frontend/bpu/rtl/ras.sv:65-72`, writes lines 808-811 and
   834-835). bp_cluster drops the restore when the redirect is the
   block's own p2 or p3 redirect (`w_ras_restore_val`,
   `bp_cluster.sv:1402`).

From the run (out/fd11_be_mispredict/fd11_be_mispredict.fst,
`bkend_ftq_redir_pc` at each `bkend_ftq_redir_val`): 18 of the 21
redirects are A, 8 to 0x8000_0010 (taken) and 10 to 0x8000_000E (not
taken); one is the return at cyc 49 (to 0x8000_0014), one the back edge
at cyc 60, cold (to 0x8000_0008), and one the loop exit at cyc 471 (to
0x8000_001A). Every one has cause 0 (`RC_MISPREDICT`).

### 4.2 Reading the waveform

The saved view is `waves/fd11_be_mispredict.sucl`, which `make view
S=fd11_be_mispredict` opens in Surfer. Look at:

- backend group: `bkend_ftq_redir_val` with `bkend_ftq_redir_cause`
  `RC_MISPREDICT`, `bkend_ftq_redir_idx` and `bkend_ftq_redir_pc`.
- ftq_ifu group: `ftq_ifu_flush_val` the same cycle, then
  `ftq_ifu_req_val` with `ftq_ifu_start_pc` equal to the redirect PC.
- bp_history_ras group: `ftq_rollback_val`, `ftq_rollback_idx`,
  `ftq_rollback_corr`, `bpu_ghist_ptr` stepping back, and
  `ras_restore_val` with `ras_restore_snapshot.tosr`, `.tosw`, `.bos`.
- bp_cluster_p0 group: the next `ftq_pred_pc_p0` is the redirect PC.

---

## 5. Events

| # | cyc | Event                                                                                        | Other                |
|---|-----|----------------------------------------------------------------------------------------------|----------------------|
| 0 | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle                      | fast init            |
| 1 | 19  | first history rollback (`ftq_rollback_val`), with its RAS restore (`ras_restore_val`)        | a predecode redirect |
| 2 | 20  | first misprediction of A taken; redirect to 0x8000_0010                                      | pass 0, backend      |
| 3 | 49  | the return mispredicted; redirect to 0x8000_0014                                             | backend              |
| 4 | 53  | fetch restarts at 0x8000_0014: the FTQ presents a block from the redirect address to the IFU | `ftq_ifu_start_pc`   |
| 5 | 60  | the back edge mispredicted, cold; redirect to 0x8000_0008                                    | backend              |
| 6 | 86  | first misprediction of A not taken; redirect to 0x8000_000E                                  | backend              |
| 7 | 471 | the loop exits: the back edge falls through, a misprediction; redirect to 0x8000_001A        | pass 31, backend     |
| 8 | 480 | the run ends                                                                                 |                      |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd11_be_mispredict` opens
`waves/fd11_be_mispredict.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group          | signal                      | description                                       |
|----------------|-----------------------------|---------------------------------------------------|
| clock          | `tb.clk`                    | clock                                             |
|                | `tb.rstn`                   | active low reset                                  |
|                | `tb.cyc`                    | cycle number                                      |
| decode         | `tb.dec_ibuf_rdy`           | the backend model takes the bundle                |
|                | `tb.pd_out.[0].valid`       | lane 0 valid                                      |
|                | `tb.pd_out.[0].start_pc`    | lane 0 instruction address                        |
|                | `tb.pd_out.[0].ftq_idx`     | lane 0 FTQ index                                  |
|                | `tb.pd_out.[0].pos`         | lane 0 halfword position in the fetch block       |
|                | `tb.pd_out.[0].instr`       | lane 0 instruction, expanded if compressed        |
|                | `tb.pd_out.[0].is_rvc`      | lane 0 instruction is 16-bit                      |
|                | `tb.pd_out.[0].fault_cause` | lane 0 fetch fault cause                          |
|                | `tb.pd_out.[0].fault_va`    | lane 0 fetch fault virtual address                |
| backend        | `tb.bkend_ftq_redir_val`    | backend redirect                                  |
|                | `tb.bkend_ftq_redir_idx`    | FTQ index of the backend redirect                 |
|                | `tb.bkend_ftq_redir_pc`     | backend redirect PC                               |
|                | `tb.bkend_ftq_redir_cause`  | backend redirect cause                            |
|                | `tb.bkend_ftq_redir_self`   | self flag of the backend redirect                 |
|                | `tb.bkend_ftq_rsv_val`      | resolution from the backend, per slot             |
|                | `tb.bkend_ftq_commit_val`   | commit watermark valid                            |
|                | `tb.bkend_ftq_commit_idx`   | commit watermark FTQ index                        |
| ftq            | `u_ftq.w_ok_pred_p1`        | the FTQ accepts the p1 prediction                 |
|                | `u_ftq.w_ok_slot_p2`        | the FTQ accepts the p2 group                      |
|                | `u_ftq.w_ok_slot_p3`        | the FTQ accepts the p3 group                      |
|                | `u_ftq.w_ok_redir_p2`       | the FTQ accepts the p2 redirect                   |
|                | `u_ftq.w_ok_redir_p3`       | the FTQ accepts the p3 redirect                   |
|                | `u_ftq.w_redir_val`         | a redirect the FTQ takes                          |
|                | `u_ftq.w_redir_idx`         | FTQ index of the redirect                         |
|                | `u_ftq.w_commit_ptr`        | FTQ commit pointer                                |
|                | `ftq_full`                  | FTQ full                                          |
|                | `ftq_empty`                 | FTQ empty                                         |
| ftq_ifu        | `ftq_ifu_req_val`           | FTQ presents a block to the IFU                   |
|                | `ftq_ifu_req_rdy`           | the IFU takes the block                           |
|                | `ftq_ifu_idx`               | FTQ index of the block                            |
|                | `ftq_ifu_start_pc`          | block start address                               |
|                | `ftq_ifu_next_pc`           | address after the block                           |
|                | `ftq_ifu_taken_val`         | the block holds a predicted-taken transfer        |
|                | `ftq_ifu_taken_pos`         | halfword position of the predicted-taken transfer |
|                | `ftq_ifu_flush_val`         | flush of the blocks younger than the named entry  |
|                | `ftq_ifu_flush_idx`         | FTQ index the flush names                         |
|                | `ftq_ifu_commit_ptr`        | FTQ commit pointer as the IFU sees it             |
| bp_history_ras | `ftq_rollback_val`          | history rollback                                  |
|                | `ftq_rollback_idx`          | FTQ index of the rollback                         |
|                | `ftq_rollback_corr`         | the rollback writes corrected outcome bits        |
|                | `bpu_ghist_ptr`             | global history pointer                            |
|                | `ras_restore_val`           | RAS restore                                       |
|                | `ras_restore_snapshot.tosr` | restored RAS read pointer                         |
|                | `ras_restore_snapshot.tosw` | restored RAS write pointer                        |
|                | `ras_restore_snapshot.bos`  | restored RAS bottom of stack                      |
| bp_cluster_p0  | `ftq_pred_val_p0`           | p0 request valid                                  |
|                | `ftq_pred_pc_p0`            | p0 request PC                                     |
|                | `ftq_pred_idx_p0`           | p0 request FTQ index                              |
|                | `u_ftq.u_npc.w_hold`        | holds the p0 request                              |
