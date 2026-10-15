<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd01_reset_init: Reset and SRAM Initialization
```
 FILE:    fd01_reset_init.md
 SOURCE:  DOC-002
 STATUS:  WORKING
 UPDATED: 2026-10-15
 CONTACT: Jeff Nye
```

`fd01_reset_init` is the FD-1 demonstration scenario. It is a demo, not a
verification test. It is the one scenario run without the fast SRAM init
(FDT-7): the TAGE, ITTAGE and SC tables are cleared by their sram_init
walks, and the FTQ presents no p0 request until all three readies are
high. The run passes if each ready is seen low, then rises, and the first
p1 prediction the FTQ accepts comes no earlier than the last of them.

A recorded run (DOC-002):

```
DEMO PASS fd01_reset_init: ready rose at cycle TAGE 2049 ITTAGE 513
SC 1025 (seen low 111), RAS 1; first p0 2049, first accepted p1 2050;
first response TAGE 2051 ITTAGE 2051 SC 2052; first update TAGE 2069
ITTAGE -1 SC 2069 (cycles 8085)
```

---

## 1. The program

Source: `programs/fd01_reset_init.svh`, task `prog_fd01`.

```
RESET_VECTOR+0   mixed(3)           c.addi, addi, c.addi        8 bytes
top = +8         mixed(6)           c.addi, addi, c.addi x2     16 bytes
top+16           bne x6,x0,top      back edge: taken on passes 0..2998
top+20           mixed(3)
top+28           jal x0,0           halt (demo_go -> W.halt)
```

- `FD01_ITERS` = 3000 passes. Each pass resets `W.wp = top` and writes
  the same bytes, so the code is fixed; only the expected stream grows.
  3000 passes of 7 instructions keep the stream retiring past the end
  of the longest walk (TAGE, 2048 entries).
- The Makefile omits `$(FAST_INIT)` for this scenario alone
  (`plusargs`, `Makefile:173`), so `fast_init_r` is 0 in TAGE and SC and
  `fast_init` is 0 in ITTAGE.
- The program is there only so that there is a first prediction to
  accept and a stream to retire; FD-1 names no program.

---

## 2. Why the readies rise when they do

1. One sram_init per predictor. `rtl/lib/rtl/sram_init.sv:47-80`: from
   reset the state is PENDING; with `START_DELAY` 0 the first clock
   moves it to INIT (line 56-57); INIT writes one address per cycle
   from `waddr` 0, and on the cycle `waddr == LAST_ADDR` it moves to
   DONE and sets `ready` (lines 68-71).
   - TAGE: `NUM_ENTRIES (1 << TAGE_MAX_IDX_WIDTH)`
     (`rtl/core/frontend/bpu/rtl/tage.sv:313-319`), 2048
     (`bp_defines_pkg.sv:386`, `TAGE_MAX_IDX_WIDTH = 11`).
   - ITTAGE: `IT_MAX_NUM_ENTRIES` (`ittage.sv:72`, `:101-106`), 512
     (`IT_MAX_IDX_WIDTH = 9`, `bp_defines_pkg.sv:498`).
   - SC: `RI_ENTRIES = SC_TBL_ENTRIES[ST4]`, 1024 (`sc.sv:120`).
2. The cycle numbers. `cyc` counts edges with `rstn` high
   (`rtl/core/frontend/fe_top/tb/models/fe_tb_dut.svh:129`). The FST
   shows the TAGE walk in INIT with `waddr` 0 at cycle 1 and `waddr`
   0x7FF at cycle 2048, so `ready` is high from cycle N + 1: ITTAGE 513,
   SC 1025, TAGE 2049.
3. The readies reach the FTQ. `fe_top.sv:488-490` (the `u_bpu`
   instance) and `:514-516` (the `u_ftq` instance) connect
   `bpu_tage_rdy`, `bpu_ittage_rdy` and `bpu_sc_ready`; the note at
   `fe_top.sv:74-78` records that BP-137 connected them.
4. The hold. `rtl/core/frontend/ftq/rtl/ftq_npc.sv:306-309` adds
   `~tage_rdy | ~ittage_rdy | ~sc_ready` to `w_hold`, and line 377
   drives `ftq_pred_val_p0 = ~w_hold`. The first p0 request is therefore
   the cycle the last ready rises, 2049; its p1 prediction is accepted
   at 2050, its TAGE and ITTAGE answers come at p2 (2051) and its SC
   answer at p3 (2052).
5. ITTAGE is never updated. `ftq_resolve.sv:506-508` raises an ITTAGE
   update only for `INDIRECT_NONRET` and `INDIRECT_CALL`; the program
   has no indirect jump, so `c_it_u` stays -1.

---

## 3. What the monitor counts

The figures come from `tb/fe_demo_mon.svh:312-336` (`mon_init`). Unlike
every other count, they are taken from the release of reset, not inside
the `meas` window.

```
c_tage_rdy, c_it_rdy, c_sc_rdy   first cycle bpu_tage_rdy,
                                 bpu_ittage_rdy, bpu_sc_ready is high
lo_tage_rdy, lo_it_rdy, lo_sc_rdy
                                 the ready was seen low after reset
                                 (printed as "seen low 111")
c_ras_rdy                        first cycle u_ras.ras_rst_done
c_p0                             first ftq_pred_val_p0
c_p1                             first u_ftq.w_ok_pred_p1
c_tage_p2, c_it_p2, c_sc_p3      first w_tage_pred_rdy_p2,
                                 w_ittage_pred_rdy_p2, w_sc_pred_rdy_p3
c_tage_u, c_it_u, c_sc_u         first w_tage_upd_val_u0,
                                 w_ittage_upd_val_u0, w_sc_upd_val_u0
```

Each is -1 until its event occurs (`mon_reset`, lines 143-157).

The proof (`tb/fe_demo_proofs.svh:16-37`) is all three `lo_*` set, all
three readies seen (`> 0`), and `c_p1 >= last`, the latest of the three
readies. The other figures are only reported. `tb_fe_demo.sv` also
requires the whole stream to retire with no errors before it accepts
the proof.

---

## 4. Reading the numbers

- `first p0 2049` equals `TAGE 2049`: the request waits for the last
  ready and starts on the same cycle. `first accepted p1 2050` is one
  cycle later, as the pipeline requires.
- `RAS 1`: the RAS reset (`ras_rst_done`) is not one of the three RAM
  Init readies and is not part of the proof.
- `ITTAGE -1` is expected: there is no indirect branch to update it.
- `cycles 8085` counts from the release of reset to the last
  retirement, so it includes the 2049 cycles of the walk.
- Departure from `planning/showcase/fe_demo_scenarios.md` FD-1: its
  program line reads "none; reset without the fast-init options". As
  built, the scenario runs a 3000-pass loop so that a prediction exists
  to be accepted and the stream has work after the walk. The reset
  without the fast-init options is as specified. The proof is FD-1's.
- Before BP-137 this scenario reported DEMO FAIL: the FTQ requested from
  the first cycle after reset (DOC-001 Results Capture; BP-137 Results
  Capture, Problem 1).

---

## 5. Waveform

The saved views are `waves/fd01_reset_init.gtkw` (GTKWave, `make view
S=fd01_reset_init`) and `waves/fd01_reset_init.sucl` (Surfer, `make
sview S=fd01_reset_init`). Look at:

- group `sram_init`: `u_tage.u_sram_init.state` 2 (INIT) from cycle 1
  with `waddr` counting, then 3 (DONE) with `bpu_tage_rdy`; the same for
  `u_ittage.u_sram_init` with `bpu_ittage_rdy` and `u_sc.u_sram_init`
  with `bpu_sc_ready`; `u_ras.ras_rst_done`.
- group `bp_cluster_first`: `ftq_pred_val_p0` low until cycle 2049,
  then `bpu_pred_val_p1` and `u_ftq.w_ok_pred_p1`, then
  `w_tage_pred_rdy_p2`, `w_ittage_pred_rdy_p2` and `w_sc_pred_rdy_p3`.
- group `bp_cluster_p0`: `ftq_pred_pc_p0` at `RESET_VECTOR`
  (0x80000000) while held, and `u_npc.w_hold` high from cycle 1 to
  2048.
