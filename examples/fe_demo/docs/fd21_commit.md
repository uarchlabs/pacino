<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd21_commit: Commit
```
 FILE:    fd21_commit.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

## 1. Introduction

`fd21_commit` is the FD-21 demonstration scenario. It is a demo, not a
verification test. Calls and returns retire in order. The backend's
retirement watermark moves the FTQ commit pointer one entry per cycle,
and each committed entry whose prediction block ends in a call or a
return pushes or pops the RAS commit stack. The run passes if the
commit pointer moves in at least 16 cycles and the commit stack
changes.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).

### 1.1 Files

`DEMO=$RVA_ROOT/examples/fe_demo`

  | File               | Path                                  |
  |--------------------|---------------------------------------|
  | This file          | $DEMO/docs/fd21_commit.md             |
  | Program (stimulus) | $DEMO/programs/fd21_commit.svh        |
  | Surfer sucl        | $DEMO/waves/fd21_commit.sucl          |
  | Log                | $DEMO/out/fd21_commit/fd21_commit.log |
  | Waveform           | $DEMO/out/fd21_commit/fd21_commit.fst |
  | Waveform (online)  | [Link](https://app.surfer-project.org/?load_url=https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd21_commit.fst&startup_commands=run_command_file_from_url%20https%3A%2F%2Fuarchlabs.github.io%2Fpacino-waves%2Ffd21_commit.sucl) |

---

## 2. Run the scenario

Run simulation:
```
make -C examples/fe_demo fd21_commit
```

View the waveform (runs simulation first if FST is not up to date):
```
make -C examples/fe_demo view S=fd21_commit
```

Console output:
```
-I: fd21_commit : PASS : cyc = 214
```

Log file output:
```
-I: fd21_commit: PASS, cycles the commit pointer moved 42,
    cycles the RAS commit stack changed 36, events checked 8 of 8, cyc 214
```

### 2.1 What the monitor counts

The counts come from `tb/fe_demo_mon.svh:577-582`, sampled every cycle
while `meas` is set. Both are counts of CYCLES.

```
n_commit_adv  u_ftq.w_commit_ptr differs from its value the cycle
              before (pv_commit)
n_csp_chg     u_bpu.u_ras.csp or u_ras.commit_top_addr differs from
              the cycle before (pv_csp, pv_ctop)
```

`pv_commit`, `pv_csp` and `pv_ctop` are updated every cycle, inside or
outside the measured window (`fe_demo_mon.svh:639-641`).

The proof (`tb/fe_demo_proofs.svh:167`) is
`n_commit_adv >= 16 && n_csp_chg > 0`. `tb_fe_demo.sv` also requires
the whole stream to retire with no errors, and the backend checks every
RAS commit against the retired call or return (the RAS commit check,
`fe_tb_backend.svh:391-415`).

### 2.2 Reading the numbers

- `cycles the commit pointer moved 42`: since the walk frees one entry
  per cycle, this is also the number of FTQ entries committed inside
  the measured window.
- `cycles the RAS commit stack changed 36` is 3 calls and 3 returns
  times 6 passes (derived from the source; the run shows 36 RAS
  commits, section 4.1). Each operation changes `csp` in its own cycle.
- Departures from `planning/showcase/fe_demo_scenarios.md` FD-21:
  - FD-21's proof is "commits advance; the commit stack changes". The
    proof as built sets a floor of 16 cycles for the first; the number
    is the testbench's, not FD-21's.

---

## 3. The program

Source: `programs/fd21_commit.svh`, task `prog_fd21`, ported from
tb_fe_top's `calls`. M-mode, bare. Offsets from RESET_VECTOR
0x8000_0000; f = +0x800, g = +0xA00, h = +0xC00. Addresses derived from
the source.

```
+0x00  mixed(3)
top = +0x08
+0x08  10 x c.addi
+0x1C  jal x1,f            main calls f (link +0x20)
f+0x00 mixed(3); 10 x c.addi
f+0x1C jal x1,g            f calls g (link f+0x20)
g      mixed(2); ret       g returns
f+0x20 c.addi; 13 x c.addi
f+0x3C jal x1,h            f calls h (link f+0x40)
h      mixed(2); ret       h returns
f+0x40 c.addi
f+0x42 ret                 f returns to main
+0x20  c.addi
+0x22  bne x6,x0,top       loop_br; rep_iter: 6 passes, the last not
                           taken
+0x26  mixed(3), then jal x0,0 (halt)
```

- Each pass makes three calls and three returns; the deepest point is
  main -> f -> g (or h), two return addresses on the stack.
- `loop_br` and `rep_iter` (`fe_tb_writer.svh:352-383`, in
  `rtl/core/frontend/fe_top/tb/models/`) write the body once and
  append its other five executions to the expected stream.

---

## 4. Walkthrough

### 4.1 Why the program produces the behavior

1. The watermark. The backend raises `bkend_ftq_commit_val` with
   `bkend_ftq_commit_idx` the newest FTQ entry all of whose
   instructions have retired: when the first instruction of a new
   entry retires, the watermark becomes the entry before it
   (`track_entry`, `fe_tb_backend.svh:70-93`; driven at `:458-459`
   when the resolution queue is empty).
2. The commit walk. ftq_commit frees every entry from commit_ptr to
   the watermark, ONE ENTRY PER CYCLE because the RAS commit port is
   scalar (`rtl/core/frontend/ftq/rtl/ftq_commit.sv:26-31`):
   `commit_step_val` (`:235`) advances `commit_ptr` by one (`:252`).
   `w_commit_ptr` in ftq.sv is that pointer.
3. The RAS commit. The committing entry's taken call, return or
   return-call slot sets `ras_commit_val` and `ras_commit_br_type`
   (`rtl/core/frontend/ftq/rtl/ftq_entry.sv:275-285`). In the RAS a
   pop moves `csp` down and a push writes `commit_ret_addr` and moves
   `csp` up (`c_pop`, `c_push`, `c_nxt`,
   `rtl/core/frontend/bpu/rtl/ras.sv:749-759`; registered at
   `:844-848`). `commit_top_addr` is the entry below `csp`
   (`ras.sv:185-187`).
4. Seen in the run (fst2vcd on `out/fd21_commit/fd21_commit.fst`,
   while `meas` is set): `w_commit_ptr` changes in 42 cycles;
   `ras_commit_val` is high in 36 cycles, 18 with `ras_commit_br_type`
   DIRECT_CALL and 18 with RETURN; `csp` reaches 2.

### 4.2 Reading the waveform

The saved view is `waves/fd21_commit.sucl`, which `make view
S=fd21_commit` opens in Surfer. Look at:

- backend group: `bkend_ftq_commit_val` and `bkend_ftq_commit_idx`, the
  watermark.
- ftq group: `w_commit_ptr` stepping by one per cycle up to the
  watermark.
- ras_commit group: `ras_commit_val` with `ras_commit_br_type` DIRECT_CALL or
  RETURN and `ras_commit_ret_addr`; `u_ras.csp` moving between 0 and 2;
  `commit_top_valid` and `commit_top_addr` (+0x20, f+0x20, f+0x40).
- ras group: the speculative pointers `tosr` and `tosw`, which move at
  prediction time, ahead of the commit stack.

---

## 5. Events

| # | cyc | Event                                                                     | Other           |
|---|-----|---------------------------------------------------------------------------|-----------------|
| 0 | 0   | reset released (`tb.rstn`); the FTQ requests 0x8000_0000 the same cycle   | fast init       |
| 1 | 40  | first commit watermark from the backend (`bkend_ftq_commit_val`)          | backend         |
| 2 | 40  | the commit pointer first moves (`w_commit_step_val`), one entry per cycle |                 |
| 3 | 40  | first RAS commit of a call (`ras_commit_br_type` DIRECT_CALL)             |                 |
| 4 | 62  | the commit stack reaches depth 2 (`u_ras.csp`)                            | main, f         |
| 5 | 62  | first RAS commit of a return                                              |                 |
| 6 | 204 | back edge falls through, a misprediction; redirect to 0x8000_0026         | pass 5, backend |
| 7 | 214 | the run ends                                                              |                 |

---

## 6. Waveform

`make -C examples/fe_demo view S=fd21_commit` opens
`waves/fd21_commit.sucl` in Surfer, with a marker at each event above.
Signal paths below are under `tb.dut` unless they start with `tb.`.

| group      | signal                          | description                           |
|------------|---------------------------------|---------------------------------------|
| clock      | `tb.clk`                        | clock                                 |
|            | `tb.rstn`                       | active low reset                      |
|            | `tb.cyc`                        | cycle number                          |
| backend    | `tb.bkend_ftq_redir_val`        | backend redirect                      |
|            | `tb.bkend_ftq_redir_idx`        | FTQ index of the backend redirect     |
|            | `tb.bkend_ftq_redir_pc`         | backend redirect PC                   |
|            | `tb.bkend_ftq_redir_cause`      | backend redirect cause                |
|            | `tb.bkend_ftq_redir_self`       | self flag of the backend redirect     |
|            | `tb.bkend_ftq_rsv_val`          | resolution from the backend, per slot |
|            | `tb.bkend_ftq_commit_val`       | commit watermark valid                |
|            | `tb.bkend_ftq_commit_idx`       | commit watermark FTQ index            |
| ftq        | `u_ftq.w_commit_ptr`            | FTQ commit pointer                    |
|            | `ftq_full`                      | FTQ full                              |
|            | `ftq_empty`                     | FTQ empty                             |
|            | `ftq_pred_idx_p0`               | p0 request FTQ index                  |
|            | `ftq_ifu_idx`                   | FTQ index of the block                |
| ras_commit | `ras_commit_val`                | RAS commit valid                      |
|            | `ras_commit_br_type`            | branch type of the RAS commit         |
|            | `ras_commit_ret_addr`           | return address of the RAS commit      |
|            | `u_bpu.u_ras.csp`               | commit stack pointer                  |
|            | `u_bpu.u_ras.commit_top_valid`  | commit stack top valid                |
|            | `u_bpu.u_ras.commit_top_addr`   | commit stack top address              |
| ras        | `u_bpu.u_ras.tosr`              | RAS read pointer                      |
|            | `u_bpu.u_ras.tosw`              | RAS write pointer                     |
|            | `u_bpu.u_ras.bos`               | RAS bottom of stack                   |
|            | `u_bpu.u_ras.ras_rst_done`      | RAS reset done                        |
|            | `u_bpu.w_ras_pred_val_p2.[0]`   | slot 0 presented to the RAS at p2     |
|            | `u_bpu.w_br_type_p2.[0]`        | slot 0 branch type at p2              |
|            | `u_bpu.u_ras.spec_ret_addr.[0]` | RAS entry 0 return address            |
|            | `u_bpu.u_ras.spec_ret_addr.[1]` | RAS entry 1 return address            |
|            | `u_bpu.u_ras.spec_ret_addr.[2]` | RAS entry 2 return address            |
|            | `u_bpu.u_ras.spec_ret_addr.[3]` | RAS entry 3 return address            |
|            | `u_bpu.u_ras.spec_rctr.[0]`     | RAS entry 0 recursion count           |
|            | `u_bpu.u_ras.spec_rctr.[1]`     | RAS entry 1 recursion count           |
|            | `u_bpu.u_ras.spec_rctr.[2]`     | RAS entry 2 recursion count           |
|            | `u_bpu.u_ras.spec_rctr.[3]`     | RAS entry 3 recursion count           |
