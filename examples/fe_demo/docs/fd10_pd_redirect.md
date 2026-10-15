<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd10_pd_redirect: Predecode Redirect
```
 FILE:    fd10_pd_redirect.md
 SOURCE:  DOC-002
 STATUS:  WORKING
 UPDATED: 2026-10-15
 CONTACT: Jeff Nye
```

`fd10_pd_redirect` is the FD-10 demonstration scenario. It is a demo,
not a verification test. It runs a chain of JALs to distinct blocks,
three times. On the first pass neither the uBTB nor the FTB knows any of
them, so each block is predicted to fall through. Predecode at F3 finds
the JAL, the IFU writes the block back with a mispredict position, and
the FTQ redirects fetch to the JAL's target. The run passes if at least
one predecode redirect occurred without a backend redirect in the same
cycle.

A recorded run:

```
DEMO PASS fd10_pd_redirect: predecode redirects 13 (cycles 247)
```

---

## 1. The program

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

## 2. Why the program produces the behaviour

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
   (`rtl/core/frontend/ftq/rtl/ftq_npc.sv:329-336`).
4. Flush. Any redirect raises `ftq_ifu_flush_val`
   (`ftq_ifu.sv:352`), which drops the blocks younger than the
   redirected entry in the IFU, and the redirect rolls back history
   (`rollback_val`, `ftq_npc.sv:399`).

From the run (out/fd10_pd_redirect/fd10_pd_redirect.fst): `w_pd_redir_val`
pulses 13 times between cycles 19 and 165, with `w_pd_redir_pc` the
chain targets 0x8000_0200 to 0x8000_0620 in order and then 0x8000_0108.
At cycle 175 it pulses together with a backend redirect (the back edge,
cold, resolved taken) and is not counted. Passes 2 and 3 have no
predecode redirect.

---

## 3. What the monitor counts

The counter is in the shared models, beside the FTQ fetch log
(`rtl/core/frontend/fe_top/tb/models/fe_tb_be_state.svh:74-75`):

```
n_pd_redir   meas && u_ftq.w_pd_redir_val && !bkend_ftq_redir_val
```

`meas` is the measurement window: out of reset, the backend running and
the stream not yet fully retired (`fe_tb_backend.svh:416`).

The proof (`tb/fe_demo_proofs.svh:80`) is `n_pd_redir > 0`.
`tb_fe_demo.sv:144` also requires the whole stream to retire with no
errors.

---

## 4. Reading the numbers

- 13 is exactly the JALs of the first pass. After their first
  retirement the uBTB and FTB predict them, so the second and third
  passes add none.
- A predecode redirect in the same cycle as a backend redirect is lost
  to the backend redirect in the arbiter and is not counted (cycle
  175).
- After the run ends (cycle 247) `w_pd_redir_val` keeps pulsing about
  every 9 cycles while the front end runs on during the drain; the
  monitor does not count the drain.
- Spec and build agree. FD-10's program is "a JAL in code not yet seen
  by the uBTB or FTB"; the build uses 13 such JALs (tb_fe_top `jals`)
  and runs them three times, so the trained passes show the same JALs
  predicted.

---

## 5. Waveform

The saved views are `waves/fd10_pd_redirect.gtkw` (`make view
S=fd10_pd_redirect`) and `waves/fd10_pd_redirect.sucl` (`make sview
S=fd10_pd_redirect`). Look at:

- ifu_f3 group: `ifu_ftq_pdwb_val` with `ifu_ftq_mis_val` set,
  `ifu_ftq_mis_pos` the JAL's position and `ifu_ftq_target` its target.
- `w_pd_redir_val` the same cycle, and the next `ftq_pred_pc_p0` the
  target (bp_cluster_p0 group).
- ftq_ifu group: `ftq_ifu_flush_val` with `ftq_ifu_flush_idx`, then
  `ftq_ifu_req_val` with `ftq_ifu_start_pc` the target.
- Compare cycles 19-165 (first pass) with the second pass, where the
  same blocks are predicted taken and no writeback carries
  `ifu_ftq_mis_val`.
