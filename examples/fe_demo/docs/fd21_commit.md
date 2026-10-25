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

`fd21_commit` is the FD-21 demonstration scenario. It is a demo, not a
verification test. Calls and returns retire in order. The backend's
retirement watermark moves the FTQ commit pointer one entry per cycle,
and each committed entry whose prediction block ends in a call or a
return pushes or pops the RAS commit stack. The run passes if the
commit pointer moves in at least 16 cycles and the commit stack
changes.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).
A recorded run:

```
-I: fd21_commit: PASS, cycles the commit pointer moved 42,
    cycles the RAS commit stack changed 36, cyc 214
```

---

## 1. The program

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

## 2. Why the program produces the behaviour

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

---

## 3. What the monitor counts

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

---

## 4. Reading the numbers

- `cycles the commit pointer moved 42`: since the walk frees one entry
  per cycle, this is also the number of FTQ entries committed inside
  the measured window.
- `cycles the RAS commit stack changed 36` is 3 calls and 3 returns
  times 6 passes (derived from the source; the run shows 36 RAS
  commits, section 2). Each operation changes `csp` in its own cycle.
- Departures from `planning/showcase/fe_demo_scenarios.md` FD-21:
  - FD-21's proof is "commits advance; the commit stack changes". The
    proof as built sets a floor of 16 cycles for the first; the number
    is the testbench's, not FD-21's.

---

## 5. Waveform

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
