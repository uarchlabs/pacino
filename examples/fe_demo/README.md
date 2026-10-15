<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Front-End Demonstration Testbench
```
 FILE:    README.md
 SOURCE:  DOC-001, DOC-002
 STATUS:  WORKING
 UPDATED: 2026-10-15
 CONTACT: Jeff Nye
```

Twenty-one short programs, each making one behaviour of the front end
visible in a waveform. The scenarios are
planning/showcase/fe_demo_scenarios.md (FD-1 to FD-21); the testbench is
planning/testbenches/fe_demo_tb_decisions.md (FDT-N).

This is a demonstration, not a verification testbench. It is not part
of tools/regress.sh.

---

## 1. What runs

fe_top with the page table walker beside it, NUM_PRED_SLOTS = 2, on the
models tb_fe_top uses, included from
rtl/core/frontend/fe_top/tb/models/:

```
  fe_tb_dut.svh       clock, reset, fe_top, the walker hookup
  fe_tb_writer.svh    the program writer and the expected stream
  fe_tb_mem.svh       the memory model: L1I link, walker memory port
  fe_tb_be_state.svh  the in-order backend's state, the FTQ fetch log
  fe_tb_backend.svh   the in-order backend
  fe_tb_csr.svh       CSR setup through csr_tb_pkg
```

The backend still compares every retired instruction with the
program's executed stream, so a run whose stream does not retire says
so. Each run then checks its scenario's proof from RTL signals and
prints one line:

```
  DEMO PASS fd04_p2_override: p2 redirects 38 (cycles 488)
```

or `DEMO FAIL ...`, which exits non-zero. The cycle count runs from the
release of reset to the last retirement.

Files here:

```
  Makefile                 the targets below
  tb/tb_fe_demo.sv         the top, module tb
  tb/fe_demo_mon.svh       the monitors the proofs read
  tb/fe_demo_lib.svh       start and end of a run, address map, helpers
  tb/fe_demo_proofs.svh    the proofs
  programs/fdNN_*.svh      one program per scenario; its header holds
                           its shows / program / waveform / trace /
                           proof entry (FD-0b)
  waves/fdNN_*.gtkw        one GTKWave save file per scenario
  waves/fdNN_*.sucl        one Surfer command file per scenario, the
                           same signals and groups
  waves/fe_demo_sigs.py    the signal lists of both
  waves/mk_gtkw.py         writes the save files from an FST
  waves/mk_sucl.py         writes the Surfer command files from an FST
  waves/chk_sucl.py        loads each command file in Surfer and
                           compares what it shows with the save file
  waves/fe_demo.gtkwaverc  GTKWave rc file of make view: full names
  docs/fdNN_*.md           one description per scenario
  docs/fe_top_connectivity.md
                           the fe_top connectivity inventory
  out/<scenario>/          run output, not committed
```

---

## 2. Build and run

From examples/fe_demo:

```
  make fd04_p2_override     build if needed, run one scenario
  make scenarios            every scenario in FD order, stopping at
                            the first DEMO FAIL
  make -k scenarios         every scenario, whatever fails
  make build                the model only (about 4 minutes)
  make clean                the model and out/
  make view S=fd04_p2_override
                            open the run in GTKWave
  make sview S=fd04_p2_override
                            open the run in Surfer
  make                      the targets and the list of scenarios
```

A run writes out/<scenario>/<scenario>.fst and .log. make view and
make sview run the scenario first when its FST is missing or older
than the model, then open it: GTKWave with waves/<scenario>.gtkw, or
Surfer with waves/<scenario>.sucl. Both show every signal by its full
hierarchical name. The viewers are the variables GTKWAVE and SURFER,
defaults gtkwave and surfer:

```
  make sview S=fd09_tage SURFER=~/.cargo/bin/surfer
```

S missing prints the usage; an S that is not a scenario lists the
names. Either fails. The signals are grouped by unit, in pipeline
order, the clock group first. Surfer shows the same groups and order
as GTKWave, and the same radix (binary, hex, decimal); GTKWave's
signal and SST pane widths have no Surfer equivalent.

Plusargs, if running the model directly:
`+SCEN=<name>`, `+FST=<file>`, `+TRACE`, and the three `*_FAST_INIT=1`
options, which the Makefile passes to every scenario but FD-1.

After a change to the RTL that renames a signal, regenerate the save
files and the Surfer command files from any run's FST, and check the
command files in Surfer (it opens a window per scenario):

```
  python3 waves/mk_gtkw.py out/fd02_steady/fd02_steady.fst
  python3 waves/mk_sucl.py out/fd02_steady/fd02_steady.fst
  SURFER=~/.cargo/bin/surfer python3 waves/chk_sucl.py
```

Both generators stop on a signal the FST does not have.

---

## 3. The scenarios and what to look for

Each scenario has a description in docs/<scenario>.md: the program,
why it produces the behaviour, what the monitor counts, how to read the
DEMO line and what to look at in the waveform.

```
fd01_reset_init      FD-1  Reset and SRAM initialization
fd02_steady          FD-2  Steady-state prediction and fetch
fd03_two_branch      FD-3  Two branches in one block
fd04_p2_override     FD-4  p2 override
fd05_p3_override     FD-5  p3 override
fd06_loop_pred       FD-6  Loop predictor
fd07_calls_returns   FD-7  Calls and returns
fd08_indirect        FD-8  Indirect jump
fd09_tage            FD-9  TAGE provider, allocation, use_alt_on_na
fd10_pd_redirect     FD-10 Predecode redirect
fd11_be_mispredict   FD-11 Backend mispredict
fd12_training        FD-12 Training
fd13_l1i             FD-13 L1I hit and miss
fd14_translation     FD-14 Translation
fd15_faults          FD-15 Faults
fd16_page_cross      FD-16 Page-crossing block
fd17_rvc             FD-17 Compressed and unaligned code
fd18_uncached        FD-18 Uncached fetch
fd19_fencei_cbo      FD-19 FENCE.I and cbo.inval
fd20_backpressure    FD-20 Backpressure
fd21_commit          FD-21 Commit
```

**fd01_reset_init.** The three sram_init state machines step through
INIT, waddr counting, and each ready rises when its walk ends (ITTAGE
at cycle 513, SC 1025, TAGE 2049). `ftq_pred_val_p0` stays low until
the last of them (BP-137): the first p0 request is at cycle 2049 and
the first `w_ok_pred_p1` at 2050.

**fd02_steady.** Once the first lines are in, `w_ok_pred_p1` stays high
cycle after cycle while `ftq_pred_idx_p0` counts up by one, and all
eight `pd_out` slots are valid together with `dec_ibuf_rdy`.

**fd03_two_branch.** In the p2 group, find a cycle with `w_ok_slot_p2`
where both `bpu_slot_p2.[0]` and `.[1]` have `slot_valid` set, each a
conditional at its own `pos`.

**fd04_p2_override.** A p1 block with `r_ubtb_blk_p1.hit` low (or a
stale slot) is followed two cycles later by `w_ftb_valid_p2` and a
`bpu_redir_p2` valid with `w_ok_redir_p2`; the next `ftq_pred_pc_p0` is
the redirect target.

**fd05_p3_override.** At p3, `w_sc_hit_p3` with `w_taken_p3` opposite
to the p2 slot's `taken`, the slot's `pred_src` 4 (PRED_SC), and a
`bpu_redir_p3` valid that `w_ok_redir_p3` accepts.

**fd06_loop_pred.** After the warm-up passes, the inner loop branch's
slot carries `pred_src` 1 (PRED_LOOP) at p1 and p2; on the tenth pass
its `taken` drops and the retired branch is not followed by a backend
redirect.

**fd07_calls_returns.** `tosw` and `tosr` move up on each call and down
on each return; during the recursion `spec_rctr` of the top entry
climbs above 1 instead of the pointers moving. `w_br_type_p2` 7
(RETURN_CALL) marks the coroutine switches.

**fd08_indirect.** `w_ittage_pred_rdy_p2` with
`w_ittage_pred_meta_p2.[s].ittage_hit` set, and the p2 slot of the jump
taking `pred_src` 5 (PRED_ITTAGE) with the alternating target.

**fd09_tage.** In `tage_pred_meta_p2`, `tage_prm_comp` non-zero with
`tage_using_primary` set is a tagged provider; `tage_using_primary` low
with `tage_alt_comp` 0 is T0 by use_alt_on_na (watch `uaon` rise). An
allocation is `trx_type` with `u_alc_wr` set.

**fd10_pd_redirect.** On the first pass, `ifu_ftq_pdwb_val` with
`ifu_ftq_mis_val` set and `ifu_ftq_target` the JAL's target;
`w_pd_redir_val` follows and `ftq_ifu_flush_val` drops the younger
blocks.

**fd11_be_mispredict.** `bkend_ftq_redir_val` with cause 0
(RC_MISPREDICT), then `ftq_ifu_flush_val`, `ftq_rollback_val` with
`bpu_ghist_ptr` stepping back and `ras_restore_val`; the next
`ftq_ifu_req_val` starts at `bkend_ftq_redir_pc`.

**fd12_training.** `bkend_ftq_rsv_val` resolutions, then the per
predictor update valids of `u_bpu`; each `ftb_upd_valid_u0` comes with
`h3_ftb_upd` and `w_hold`, the cycle with no p0 request.

**fd13_l1i.** In the loop, `b_rsp_valid` two cycles after each
`ifu_l1i_req_val`; at the cold line, `b_mis_valid`, an MSHR `e_val`,
`l1i_mem_a_valid`, two `l1i_mem_d_valid` beats and the fill. The block
back at line X raises `mrg_hit`: it joins the register already
fetching X.

**fd14_translation.** `itlb_l2t_req_val` for each new page; with
`itlb_l2t_v` 0 the walker's `r_st` runs the S_S states only, with
`itlb_l2t_v` 1 (after the ecall) it alternates through the S_G states.
The CAS is `ptw_mem_req_op` 1 on the leaf's address.

**fd15_faults.** `itlb_ifu_status` fault with `itlb_ifu_cause`, the
translation queue's `xq_fault0`, and the faulting packet at decode with
`pd_out.[0].fault_cause` 2 (page), 1 (access) and 3 (guest page).

**fd16_page_cross.** The block at the page's last 16 bytes: two
`ifu_itlb_req_val` lookups for adjacent VPNs, and its translation queue
entry popped with `xq_cross` set and `xq_ppn0` and `xq_ppn1` the two
pages' PPNs (0x81000 and 0x81205).

**fd17_rvc.** The 32-bit instruction at +0x3E reaches decode whole in
the block that starts before it, at `pos` 15, with `is_rvc` 0; in the
loop, 16-bit control transfers appear expanded in `pd_out.instr`.

**fd18_uncached.** `ifu_l1i_req_uncached` requests one at a time, each
after `ftq_ifu_commit_ptr` has reached its block; `xq_uc` marks the
page; no `b_fil_valid` for the NC line installs it.

**fd19_fencei_cbo.** `cmt_ifu_maint_val`, the IFU maintenance `r_st`,
`ifu_l1i_inv_val` (all for FENCE.I, one line for cbo.inval), the L1I's
drain (FENCE.I waits for `mt_busy_any`, every fill in flight, to clear;
cbo.inval only for `mt_busy_line`, a fill of its own line:
l1i_maint.sv M_DRAIN), `l1i_ifu_inv_done`, `ifu_cmt_maint_ack`, then
the backend's redirect and a fetch at the next instruction. In this
run neither drain waits: no fill is in flight at the FENCE.I, and the
fills in flight at the cbo.inval are of other lines
(docs/fd19_fencei_cbo.md).

**fd20_backpressure.** `dec_ibuf_rdy` is high one cycle in four. The
stall starts at decode (`pd_out.[0].valid` waiting), reaches the ibuf
(`ibuf_ifu_rdy` low, about 70 cycles after reset) and then the FTQ
(`ftq_full`, about 137), after which `ftq_pred_val_p0` is low while the
FTQ is full. The earlier single-cycle drops of `ftq_pred_val_p0` are
FTB update holds, not backpressure.

**fd21_commit.** `bkend_ftq_commit_val` moves `w_commit_ptr`; each
`ras_commit_val` call pushes the commit stack (`csp`,
`commit_top_addr`) and each return pops it.
