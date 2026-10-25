<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd20_backpressure: Backpressure
```
 FILE:    fd20_backpressure.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

`fd20_backpressure` is the FD-20 demonstration scenario. It is a demo,
not a verification test. The backend takes decode's output one cycle in
four. Decode stalls first, the ibuf fills and refuses the IFU, the
IFU stops draining the FTQ, the FTQ fills, and the FTQ stops issuing
p0 requests. The run passes if each of the four stalls occurs.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).
A recorded run:

```
-I: fd20_backpressure: PASS, stall cycles with the instruction buffer full 378,
    FTQ full 324, decode held 368, no p0 request 331, cyc 537
```

---

## 1. The program

Source: `programs/fd20_backpressure.svh`, task `prog_fd20`. M-mode,
bare. Offsets from RESET_VECTOR 0x8000_0000.

```
+0x00  mixed(3)
top = +0x08
       mixed(23)          15 c.addi and 8 addi, 62 bytes
top+62 bne x6,x0,top      taken on passes 0..38, 40 passes
       mixed(3), then jal x0,0 (halt)
```

- `be_rdy_pat = 4` (`programs/fd20_backpressure.svh:24`, FD-U2): the
  backend drives `dec_ibuf_rdy` only in cycles with `cyc % 4 == 0`
  (`rtl/core/frontend/fe_top/tb/models/fe_tb_backend.svh:463-465`).
- The stream is 3 + 40 x 24 + 3 = 966 instructions plus the halt
  (derived from the source).

---

## 2. Why the program produces the behavior

1. Decode. With `dec_ibuf_rdy` low three cycles in four, the ibuf's
   read port presents a bundle that is not taken.
2. The ibuf. Its ready is registered occupancy: `ibuf_ifu_rdy` is high
   while `r_count <= DEPTH - FTQ_PD_WIDTH`
   (`rtl/core/frontend/ibuf/rtl/ibuf.sv:114`). DEPTH is 64
   (`ibuf.sv:57`; fe_top instantiates it without an override,
   `rtl/core/frontend/fe_top/rtl/fe_top.sv:802`) and FTQ_PD_WIDTH 16
   (`rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv:237`), so it refuses
   above 48 slots.
3. The IFU. F3 holds its block, payload and all, while `ibuf_ifu_rdy`
   is low (`rtl/core/frontend/ifu/rtl/ifu_f3.sv:56-57`, IB-7). Fetch
   and retirement slow to the backend's rate while p0 keeps
   allocating, so the FTQ fills.
4. The FTQ. `ftq_full` is set when the age of alloc_ptr over
   commit_ptr reaches FTQ_ALLOC_LIMIT
   (`rtl/core/frontend/ftq/rtl/ftq_ptr.sv:247`), which is FTQ_DEPTH,
   64 (`ftq_ptr.sv:196`, `bp_defines_pkg.sv:30`). It is hold condition
   H2 of ftq_npc: `w_hold` includes `h2_ftq_full`
   (`rtl/core/frontend/ftq/rtl/ftq_npc.sv:306-309`) and
   `ftq_pred_val_p0 = ~w_hold` (`ftq_npc.sv:377`).
5. Seen in the run (fst2vcd on
   `out/fd20_backpressure/fd20_backpressure.fst`): the first cycle with
   `pd_out[0].valid` and `dec_ibuf_rdy` low is 18; the first
   `ifu_ibuf_val` with `ibuf_ifu_rdy` low is 71, with `u_ibuf.r_count`
   52; the first `ftq_full` is 138 (tb.cyc values).

---

## 3. What the monitor counts

The counts come from `tb/fe_demo_mon.svh:571-576`, sampled every cycle
while `meas` is set. All four are counts of CYCLES in which the
condition holds, not of stall events.

```
n_ibuf_full  ifu_ibuf_val && !ibuf_ifu_rdy   the IFU offers, the ibuf
                                             refuses
n_ftq_full   ftq_full                        (tb's ftq_full, fe_top's
                                             port, fe_tb_dut.svh:98,
                                             :101)
n_dec_stall  pd_out[0].valid && !dec_ibuf_rdy
n_p0_held    !ftq_pred_val_p0                for any hold reason
```

The proof (`tb/fe_demo_proofs.svh:160-161`) is that each count is above
zero. `tb_fe_demo.sv` also requires the whole stream to retire with no
errors.

---

## 4. Reading the numbers

- `cyc 537` is the measured window, so the stall counts are
  fractions of it: the ibuf refuses the IFU in 378 of 537 cycles, the
  FTQ is full in 324, decode holds a bundle in 368.
- `no p0 request 331` counts every hold, not only backpressure. From
  the run: of the 331 cycles, 324 have `ftq_full` and 7 have
  `u_ftq.u_npc.h3_ftb_upd` (the FTB update hold, H3) without it.
- The order of onset (18, 71, 138) is the propagation from decode back
  to the FTQ; the counts alone do not show it.
- Departures from `planning/showcase/fe_demo_scenarios.md` FD-20:
  - FD-20's program is "a long run with the backend accepting slowly";
    the program fixes the rate at one cycle in four (be_rdy_pat 4,
    FD-U2 closed).
  - FD-20's proof is "each stall occurs". The proof as built also
    counts `n_p0_held`, which includes the FTB update holds; it does
    not separate the p0 stall caused by the full FTQ. `n_ftq_full` is
    the count of that cause.

---

## 5. Waveform

The saved view is `waves/fd20_backpressure.sucl`, which `make view
S=fd20_backpressure` opens in Surfer. Look at:

- decode group: `dec_ibuf_rdy` high one cycle in four and
  `pd_out.[0].valid` held, from cycle 18.
- ibuf group: `ifu_ibuf_val` with `ibuf_ifu_rdy` low from cycle 71;
  `u_ibuf.w_n_pres` and `w_n_pop`, the slots presented and taken.
- ftq group: `ftq_full` from cycle 138, with `w_commit_ptr`,
  `ftq_pred_idx_p0` and `ftq_ifu_idx`.
- bp_cluster_p0 group: `ftq_pred_val_p0` low while `ftq_full` is set;
  `u_npc.w_hold` high with it.
- `u_ibuf.r_count` in the ibuf group, the occupancy the ready is
  computed from: 52 at cyc 71, when `ibuf_ifu_rdy` first refuses.
