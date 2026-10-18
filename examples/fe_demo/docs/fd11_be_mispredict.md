<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd11_be_mispredict: Backend Mispredict
```
 FILE:    fd11_be_mispredict.md
 SOURCE:  DOC-002, DOC-006
 STATUS:  WORKING
 UPDATED: 2026-10-17
 CONTACT: Jeff Nye
```

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
A recorded run:

```
-I: fd11_be_mispredict: PASS, backend mispredict redirects 20,
    fetches at the redirect address 20, history rollbacks 125, RAS restores 125,
    cyc 502
```

---

## 1. The program

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

## 2. Why the program produces the behaviour

1. The backend redirect. The in-order backend resolves each branch
   against the FTQ's prediction and on a difference raises
   `bkend_ftq_redir_val` with `bkend_ftq_redir_cause` `RC_MISPREDICT`
   (2'b00, `rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv:126`) and the
   correct PC.
2. Priority. In the FTQ's p0 arbiter a backend redirect is arm 1 and
   outranks every BPU and predecode redirect
   (`rtl/core/frontend/ftq/rtl/ftq_npc.sv:316-327`); the next p0
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
   (`rtl/core/frontend/ftq/rtl/ftq.sv:517`): the RAS restores TOSR, TOSW
   and BOS from the entry's snapshot (`ras_restore_snapshot`, port
   `rtl/core/frontend/bpu/rtl/ras.sv:65-72`, writes lines 793-796 and
   819-820). bp_cluster drops the restore when the redirect is the
   block's own p2 or p3 redirect (`w_ras_restore_val`,
   `bp_cluster.sv:1378`).

From the run (out/fd11_be_mispredict/fd11_be_mispredict.fst,
`bkend_ftq_redir_pc` at each `bkend_ftq_redir_val`): 17 of the 20
redirects are A, 6 to 0x8000_0010 (taken) and 11 to 0x8000_000E (not
taken); one is the return at cyc 48 (to 0x8000_0014), one the back edge
at cyc 60, cold (to 0x8000_0008), and one the loop exit at cyc 492 (to
0x8000_001A). Every one has cause 0 (`RC_MISPREDICT`).

---

## 3. What the monitor counts

Every cycle (`tb/fe_demo_mon.svh:484-497`):

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

---

## 4. Reading the numbers

- 20 of 20 backend mispredicts were followed by a fetch at the
  corrected PC.
- `rollbacks` and `RAS restores` are equal because the two are one net
  (`ftq.sv:517`). They count every redirect the FTQ takes with a cause,
  from any arm: backend, predecode, p3 and p2. So 125 includes the 20
  backend redirects and 105 from the other arms. `RAS restores` counts
  `ras_restore_val` at the FTQ, before bp_cluster drops the restore of
  a block's own p2 or p3 redirect.
- Departure from FD-11 in `planning/showcase/fe_demo_scenarios.md`: the
  spec's program is "a data-dependent branch the predictors get wrong".
  The build's branch has a pseudo-random outcome chosen by the writer
  (tb_fe_top `misp_call`); no data dependence is modelled. The proof
  matches the spec.

---

## 5. Waveform

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
