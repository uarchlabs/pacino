<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd01_reset_init: Reset and SRAM Initialization
```
 FILE:    fd01_reset_init.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-30
 CONTACT: Jeff Nye
```

## 1. Introduction

Scenario fd01_reset_init (FD01) shows the post-reset initialization of the RAMs in the TAGE, ITTAGE and SC. These branch predictor tables require an initial value before they are trained by executed branch behavior. 

Initialization is done with simple FSMs that walk the table addresses writing the constants one cycle per entry. There are 2048 TAGE entries, 512 ITTAGE entries and 1024 SC entries. All tables are initialized in parallel.

Ready signals indicate to upstream logic when the predictors have completed this initialization. 

This waveform shows ~2048 cycles for completion of the init process. This is followed by ~295 cycles of example requests. Lastly there are ~100 cycles before termination of the scenario.

The RAS (return address stack) initialization is also shown. The RAS init is a simple reset.

This scenario runs in the 1-prediction slot Pacino configuration. The operations are the same in either 1 or 2 prediction slots.


### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                          |
  |--------------------|-----------------------------------------------|
  | This file          | $DEMO/docs/fd01_reset_init.md                 |
  | Program (stimulus) | $DEMO/programs/fd01_reset_init.svh            |
  | Surfer sucl        | $DEMO/waves/fd01_reset_init.sucl              |
  | Log                | $DEMO/out/fd01_reset_init/fd01_reset_init.log |
  | Waveform           | $DEMO/out/fd01_reset_init/fd01_reset_init.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd01_reset_init.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd01_reset_init.sucl) |


---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd01_reset_init
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd01_reset_init
```

Console output:
```
-I: fd01_reset_init : PASS : cyc = 2344
```

Log file output:

```
-I: fd01_reset_init: PASS, TAGE ready at cyc 2049, ITTAGE ready at cyc 513,
    SC ready at cyc 1025, readies seen low first 3 of 3, RAS ready at cyc 1,
    first p0 request at cyc 2049, first accepted p1 prediction at cyc 2050,
    first TAGE response at cyc 2051, first ITTAGE response at cyc 2051,
    first SC response at cyc 2052, first TAGE update at cyc 2069,
    first ITTAGE update none, first SC update at cyc 2069,
    events checked 9 of 9, cyc 2344
```

---

## 3. Events

| cyc  | Event                                            | Other              |
|------|--------------------------------------------------|--------------------|
| 0    | reset released (`tb.rstn`); the FTQ withholds    | full init walk     |
|      | its p0 request (`u_npc.w_hold`)                  |                    |
| 1    | the three table walks start at address 0; the    | each `u_sram_init` |
|      | RAS reset is done (`ras_rst_done`)               | in INIT, `waddr` 0 |
| 513  | ITTAGE ready (`bpu_ittage_rdy`)                  | 512 entries        |
| 1025 | SC ready (`bpu_sc_ready`)                        | 1024 entries       |
| 2049 | TAGE ready (`bpu_tage_rdy`), the last of the     | 2048 entries       |
|      | three; the FTQ makes its first p0 request in the |                    |
|      | same cycle                                       |                    |
| 2050 | first p1 prediction the FTQ accepts              |                    |
|      | (`w_ok_pred_p1`)                                 |                    |
| 2051 | first TAGE and ITTAGE responses at p2            |                    |
| 2052 | first SC response at p3                          |                    |
| 2344 | the run ends (`tb.cyc_run`): the last            | a 100 cycle drain  |
|      | instruction retires                              | follows, to 2444   |

---

## 4. Waveform

`make -C examples/fe_demo view S=fd01_reset_init` opens
`waves/fd01_reset_init.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

- group `clock`
    - `tb.clk` - clock
    - `tb.rstn` - active low reset
    - `tb.cyc` - cycle number
- group `tage_init`, signals under `u_bpu.u_tage`, then the ready
    - `u_sram_init.state` - initialization FSM state
    - `tbl_ri_wr` - RAM write enable, high cyc 1 to 2048
    - `u_sram_init.waddr` - RAM address
    - `tbl_ri_wd` - T1-T4 RAM write data, 0 (entry invalid, u = 0)
    - `u_tage_bim.tbl_ri_wd` - T0 RAM write data, 2 (`2'b10`, weakly taken)
    - `bpu_tage_rdy` - TAGE ready
- group `ittage_init`, signals under `u_bpu.u_ittage`, then the ready
    - `u_sram_init.state` - initialization FSM state
    - `ri_wr` - RAM write enable, high cyc 1 to 512; ITTAGE gates it per
      table
    - `u_sram_init.waddr` - RAM address
    - `ri_wd` - RAM write data, 0; ITTAGE slices it per table
    - `bpu_ittage_rdy` - ITTAGE ready
- group `sc_init`, signals under `u_bpu.u_sc`, then the ready
    - `u_sram_init.state` - initialization FSM state
    - `tbl_ri_wr` - RAM write enable, high cyc 1 to 1024
    - `u_sram_init.waddr` - RAM address
    - `tbl_ri_wd` - RAM write data, 0
    - `bpu_sc_ready` - SC ready
- group `ras_init`
    - `u_bpu.u_ras.ras_rst_done` - RAS reset done, high from cyc 1
- group `bp_cluster_p0`
    - `ftq_pred_val_p0` - p0 request valid
    - `ftq_pred_pc_p0` - p0 request PC
    - `ftq_pred_idx_p0` - p0 request FTQ index
    - `u_ftq.u_npc.w_hold` - holds the p0 request until all three readies
      are high
- group `request_stages`, one request from p0 to p3
    - `ftq_pred_val_p0` - p0 request valid
    - `bpu_pred_val_p1` - p1 prediction valid
    - `u_ftq.w_ok_pred_p1` - the FTQ accepts the p1 prediction
    - `u_bpu.w_tage_pred_rdy_p2` - TAGE response at p2
    - `u_bpu.w_ittage_pred_rdy_p2` - ITTAGE response at p2
    - `u_bpu.w_sc_pred_rdy_p3` - SC response at p3
