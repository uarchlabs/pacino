<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd19_fencei_cbo: FENCE.I and cbo.inval
```
 FILE:    fd19_fencei_cbo.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

`fd19_fencei_cbo` is the FD-19 demonstration scenario. It is a demo,
not a verification test. A function is called, rewritten by a store,
and called again after a FENCE.I; a second function is treated the same
way with a cbo.inval of its line. Each maintenance operation retires,
the backend holds decode, the IFU passes the invalidate to the L1I,
the L1I drains and clears, the IFU acknowledges, and the backend
restarts fetch at the next instruction. The run passes if both
invalidates complete and fetch restarts after each.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).
A recorded run:

```
-I: fd19_fencei_cbo: PASS, whole-cache invalidates 1, line invalidates 1,
    invalidates done 2, maintenance acknowledgements 2,
    restarts at the next instruction 2, cyc 235
```

---

## 1. The program

Source: `programs/fd19_fencei_cbo.svh`, task `prog_fd19`, with the
self-modifying-code tasks `smc_*` (`tb/fe_demo_lib.svh:148-187`, after
tb_fe_top's tasks of the same names). M-mode,
bare. Offsets from RESET_VECTOR 0x8000_0000; f = +0x800, g = +0xC40.
Addresses derived from the source.

```
+0x00  mixed(3)
+0x08  jal x1,f ; f: 6 c.addi, ret      smc_fn(f, 2): two calls
+0x0C  jal x1,f ; (the same)
+0x10  mixed(2)
+0x16  sw x0,0(a0)       smc_store(f): retiring it rewrites f as
                         3 x addi t1 and ret
+0x1A  mixed(2)
+0x20  fence.i
+0x24  mixed(2)
+0x2A  jal x1,f          smc_call_new(f): the stream expects the new
                         body (3 x addi t1, ret)
+0x2E  mixed(2)
+0x34  jal x1,g ; +0x38 jal x1,g        smc_fn(g, 2)
+0x3C  sw x0,0(a0)       smc_store(g)
+0x40  bne (cskip, taken) to +0x46; +0x44 written dry
+0x46  cbo.inval (a0)    PA 0x8000_0C64: the line of g, 0x8000_0C40
+0x4A  mixed(60)         160 bytes of code not yet fetched
+0xEA  jal x1,g          smc_call_new(g)
+0xEE  mixed(2), then jal x0,0 (halt)
```

- A store's memory effect is a list of halfword patches applied when it
  retires (`fe_tb_writer.svh:644-668`; the shared models are in
  `rtl/core/frontend/fe_top/tb/models/`).
  Until then memory holds the old code, so a fetch of f or g after the
  store and before the maintenance operation would return the old body
  and the stream would not retire.
- `fence_i` and `cbo_inval` (`fe_tb_writer.svh:673-677`, `:698-703`)
  mark their stream entries with `maint` 1 and 2; cbo.inval's entry
  carries the PA.

---

## 2. Why the program produces the behavior

1. The backend. When a maintenance entry retires it stops taking
   decode's output (`mt_pend`) and raises `cmt_ifu_maint_val` with the
   operation and PA (`fe_tb_backend.svh:357-365`, `:463-470`). After
   `ifu_cmt_maint_ack` it redirects to the
   instruction after the operation with cause RC_REPLAY
   (`fe_tb_backend.svh:156-161`).
2. The IFU (`rtl/core/frontend/ifu/rtl/ifu_maint.sv`). `r_st` steps
   I_IDLE -> I_REQ -> I_WAIT -> I_ACK (`ifu_maint.sv:58-63`, `:87-96`).
   I_REQ drives `ifu_l1i_inv_val` with `ifu_l1i_inv_all` for FENCE.I
   or the address for cbo.inval (`:72-74`); I_WAIT waits for
   `l1i_ifu_inv_done` and clears the IFU line buffer in that cycle
   (`lb_clr_val`, `:75`); I_ACK raises `ifu_cmt_maint_ack` for one
   cycle (`:71`).
3. The L1I (`rtl/core/frontend/icache/rtl/l1i_maint.sv`). From the
   acceptance cycle the core port takes nothing new (`hold`, `:73`).
   M_DRAIN waits for `!busy_any` (inv_all) or `!busy_line` (inv_line)
   (`:96-98`), M_CLEAR applies the clear in one cycle, M_DONE raises
   `inv_done` (`:75`, `:99-100`). inv_line clears every way of the
   line's set (`:25-27`).
4. Seen in the run (fst2vcd on `out/fd19_fencei_cbo/fd19_fencei_cbo.fst`):

```
cycle  FENCE.I                       cbo.inval
71     cmt_ifu_maint_val (op 0);     184  cmt_ifu_maint_val (op 1);
       L1I takes inv_all                  L1I takes the line,
       (mt_busy_any 0)                    mt_busy_any 1, mt_busy_line 0
72-73  M_DRAIN, M_CLEAR              185-186  M_DRAIN, M_CLEAR
74     l1i_ifu_inv_done              187  l1i_ifu_inv_done
75     ifu_cmt_maint_ack             188  ifu_cmt_maint_ack
77     redirect to +0x24, cause 2    190  redirect to +0x4A, cause 2
79     fetch starts at +0x24         192  fetch starts at +0x4A
```

  RC_REPLAY is 2'b10 (`rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv:128`).
  The taken branch at +0x40 is resolved as a mispredict: a backend
  redirect to +0x46 with cause 0 at cycle 174.

---

## 3. What the monitor counts

The counts come from `tb/fe_demo_mon.svh:555-570`, sampled every cycle
while `meas` is set.

```
n_inv_all    ifu_l1i_inv_val && ifu_l1i_inv_rdy && ifu_l1i_inv_all
n_inv_line   ifu_l1i_inv_val && ifu_l1i_inv_rdy && !ifu_l1i_inv_all
n_inv_done   l1i_ifu_inv_done
n_mt_ack     ifu_cmt_maint_ack; arms mt_wait with mt_pc, the PC of
             the maintenance entry + 4
n_restart    the first fetch the FTQ presents after the ack
             (ftq_ifu_req_val && ftq_ifu_req_rdy && !ftq_ifu_flush_val)
             starts at mt_pc
```

The proof (`tb/fe_demo_proofs.svh:152-153`) is `n_inv_all > 0 &&
n_inv_line > 0 && n_inv_done >= 2 && n_restart >= 2`. `n_mt_ack` is
only reported. `tb_fe_demo.sv` also requires the whole stream to retire
with no errors, which here includes the new bodies of f and g.

---

## 4. Reading the numbers

- One FENCE.I, one cbo.inval: `whole-cache invalidates 1, line
  invalidates 1`, a done and an ack for each, and each followed by a
  fetch at the next instruction.
- The drains had nothing to wait for. At the FENCE.I take
  `mt_busy_any` was 0. At the cbo.inval take `mt_busy_any` was 1 (the
  fills of the code after it), but inv_line waits only for
  `busy_line`, which was 0: no register held line 0x8000_0C40. So
  M_DRAIN lasted one cycle both times. The program's comment ("so fills
  are in flight when the L1I takes the invalidate") holds for
  `mt_busy_any`; it does not make the line drain wait.
- Departures from `planning/showcase/fe_demo_scenarios.md` FD-19:
  - FD-19's program is "code modified then FENCE.I; a cbo.inval of a
    code line". The program does both, and also reruns the modified
    code, so the stream check shows each invalidate took effect.
  - FD-19's proof is "the invalidate completes and fetch restarts".
    The proof as built asks for both kinds, two dones and two restarts
    at the next instruction. It is stronger.

---

## 5. Waveform

The saved view is `waves/fd19_fencei_cbo.sucl`, which `make view
S=fd19_fencei_cbo` opens in Surfer. Look at, around cycles 71-79 and
184-192:

- `cmt_ifu_maint_val`, `cmt_ifu_maint_op` (0 FENCE.I, 1 cbo.inval) and
  `cmt_ifu_maint_paddr`.
- the IFU's `u_maint.r_st` stepping from I_REQ to I_ACK, and
  `ifu_l1i_inv_val` with `ifu_l1i_inv_rdy`. `ifu_l1i_inv_all` is set
  for the FENCE.I; `ifu_l1i_inv_paddr` names the cbo.inval's line.
- `mt_busy_any`, `l1i_ifu_inv_done`, `ifu_cmt_maint_ack`.
- `bkend_ftq_redir_val` with `bkend_ftq_redir_cause` RC_REPLAY, then
  `ftq_ifu_req_val` with `ftq_ifu_start_pc` at the next instruction.
- `mt_busy_line`, which decides the cbo.inval drain, and the L1I's
  `u_maint.r_st` (M_DRAIN, M_CLEAR, M_DONE), both in the maintenance
  group.
