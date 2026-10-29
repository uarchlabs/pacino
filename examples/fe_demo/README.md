<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Front-End Demonstration Testbench
```
 FILE:    README.md
 SOURCE:  DOC-001, DOC-002, DOC-003, DOC-006, DOC-007, DOC-009
 STATUS:  WORKING
 UPDATED: 2026-10-29
 CONTACT: Jeff Nye
```

Twenty-four short programs, each making one behaviour of the front end
visible in a waveform. The scenarios are
planning/showcase/fe_demo_scenarios.md (FD-1 to FD-24); the testbench is
planning/testbenches/fe_demo_tb_decisions.md (FDT-N).

This is a demonstration, not a verification testbench. It is not part
of tools/regress.sh; tools/regress_demo.sh, the demonstration
regression, runs it (FDT-2, section 2).

---

## 1. What runs

fe_top with the page table walker beside it, on the models tb_fe_top
uses, included from rtl/core/frontend/fe_top/tb/models/:

```
  fe_tb_dut.svh       clock, reset, fe_top, the walker hookup
  fe_tb_writer.svh    the program writer and the expected stream
  fe_tb_mem.svh       the memory model: L1I link, walker memory port
  fe_tb_be_state.svh  the in-order backend's state, the FTQ fetch log
  fe_tb_backend.svh   the in-order backend
  fe_tb_csr.svh       CSR setup through csr_tb_pkg
```

Two simulation models are built from it (DOC-006). They differ only in
NUM_PRED_SLOTS, the number of prediction slots per fetch block: the
branches of one block that are predicted together, each slot one of
the branch fields of the block's FTB entry, slot 0 the earliest
(planning/arch/fe_decisions.md section 10). An FTB entry holds at most
one branch per slot. A block with more branches ends at the first one
its entry does not hold, and the next block starts with that branch
(the split at update, planning/arch/ftb_decisions.md section 3,
BP-140). The default model, obj_fe_demo/, has one slot, and every
scenario runs on it except four. FD-3 and FD-22 to FD-24 show what a
second slot does and run on the two-slot model, obj_fe_demo_2slot/
(the Makefile's SCEN_2S); on the one-slot model they fail.

The backend still compares every retired instruction with the
program's executed stream, so a run whose stream does not retire says
so. Each run then checks its scenario's proof from RTL signals, and the
events of its description's event table (FDT-10c, below), and prints
one result line (FDT-10):

```
  -I: fd04_p2_override: PASS, p2 redirects 49, events checked 6 of 6,
      cyc 522
```

or `-E: <scenario>: FAIL, ...`, which exits non-zero. The final `cyc`
is the cycle count from the release of reset to the last retirement.
Every line the testbench prints begins with `-I:`, `-W:` or `-E:` and
the scenario name, and is at most 80 columns; a longer message breaks
after a comma and continues on lines indented four spaces (FDT-10a):

```
  -I: fd09_tage: PASS, tagged-provider predictions 188, allocations 59,
      T0 by use_alt_on_na 22, events checked 15 of 15, cyc 1364
```

A passing run prints nothing else. The shared models print their own
`ERROR:` lines on a stream error, and the simulator prints its `$fatal`
lines after a FAIL. docs/demo_explainer.md explains the program
writer, the expected stream, the backend model, the result line and
`cyc`.

THE EVENT CHECKS (FDT-10c, DOC-009). Every description, docs/fdNN_*.md,
has an Events section with a table of the scenario's events, one row
per event with its cyc. The program of the scenario checks each event:
a condition on signals of the run, written for that event in
programs/fdNN_*.svh, whose first cycle is compared with the row's cyc.
Every event is checked for order; cyc 0, the release of reset, must
match exactly, and any other cycle must fall within plus or minus a
tenth of its value, and at least 8 cycles. A row and its check are
matched by the row's marker label (FDT-12c), so a changed row, a row
with no check or a check with no row fails the run, and each failed
check prints an `-E:` line naming the row. The expected values come
from the descriptions: waves/mk_sucl.py --svh writes the tables into
each model's directory before the compile, and a changed description
rebuilds the models. `events checked <n> of <m>` in the result line
counts the rows with a condition (n) of the rows in the table (m).
`+EVDUMP` prints, after the result line, the cycle each check saw.

Files here:

```
  Makefile                 the targets below
  tb/tb_fe_demo.sv         the top, module tb
  tb/fe_demo_mon.svh       the monitors the proofs read
  tb/fe_demo_lib.svh       start and end of a run, address map, helpers
  tb/fe_demo_proofs.svh    the proofs
  tb/fe_demo_events.svh    the event checks (FDT-10c)
  tb/fe_demo_finish.cpp    the simulator's $finish without its message
  programs/fdNN_*.svh      one program per scenario; its header holds
                           its shows / program / waveform / trace /
                           proof entry (FD-0b); its event checks follow
                           the program
  waves/fdNN_*.sucl        one Surfer command file per scenario
  waves/fe_demo_sigs.py    the signal lists of the command files, built
                           for the slot count of the FST, the format
                           table, and the FST reader
  waves/mk_sucl.py         writes the command files from each
                           scenario's FST and description event table,
                           and with --svh the event tables for the
                           models (FDT-10c)
  waves/chk_sucl.py        loads each command file in Surfer and checks
                           what it shows against fe_demo_sigs.py, FDT-12a
                           and FDT-12c
  docs/demo_explainer.md   how a scenario is built and run, and the
                           glossary of the descriptions
  docs/fdNN_*.md           one description per scenario
  docs/fe_top_connectivity.md
                           the fe_top connectivity inventory
  ../../tools/regress_demo.sh
                           the demonstration regression (FDT-2)
  obj_fe_demo/             the one-slot model, not committed
  obj_fe_demo_2slot/       the two-slot model, not committed
  out/<scenario>/          run output, not committed
```

---

## 2. Build and run

From examples/fe_demo:

```
  make fd04_p2_override     build its model if needed, run one scenario
  make scenarios            every scenario in FD order, stopping at
                            the first FAIL
  make -k scenarios         every scenario, whatever fails
  make build                both models only (about 10 to 25 seconds
                            each, DOC-009)
  make clean                the models and out/
  make view S=fd04_p2_override
                            open the run in Surfer
  make                      the targets, the scenarios and the slot
                            count of the model each runs on
  make scenario_list        the scenarios, the 2-slot ones and the
                            models, for tools/regress_demo.sh
```

THE DEMONSTRATION REGRESSION (FDT-2, FDT-2a). From the repository root,
with no arguments:

```
  ./tools/regress_demo.sh
```

It builds each model once from the tree it runs in (make -B), runs
every scenario on its model, one at a time, and prints one line per
scenario with its events checked and the totals; about a minute. It
exits non-zero on a failing scenario not listed in
tools/known_failures_demo.txt, a file in the format of
tools/known_failures.txt (`examples/fe_demo <scenario> TD#<n>
<description>`) that Jeff alone edits; a missing file is empty, and the
summary says so. As tools/regress.sh does for a listed target, a listed
scenario that passes, or one that did not run, also fails the run. It
gates no push and records no pass, and makes no git call. A DOC task
that changes examples/fe_demo/ ends by running it, and a failing
scenario not listed blocks its completion; a task that changes rtl/
runs it and reports each failing scenario. `tools/regress_demo.sh
<root>` runs it on a scratch copy of the tree.

A run writes out/<scenario>/<scenario>.fst and .log, whichever model
runs it. make view builds the scenario's model if needed and runs the
scenario first when its FST is missing or older than that model. It
then opens the FST in Surfer with waves/<scenario>.sucl. Surfer is the one
supported viewer (FDT-12); the FST opens in any viewer that reads FST,
without the command file. A run that fails still writes its FST, and
make view opens it with a note. S missing prints the usage; an S that
is not a scenario lists the names. Either fails.

The viewer is the variable SURFER. Its default, set in rtl/Vars.mk, is
$(RVA_ROOT)/tools/bin/surfer, built by tools/build_tools.sh; the command
line or the environment may set it, for example SURFER=surfer for the
one on PATH. SURFER_LOG, default
warn, sets Surfer's log level (RUST_LOG): warn hides the INFO lines
Surfer prints on every start and keeps its warnings and errors, such as
a command in the .sucl it does not understand; SURFER_LOG=info gives
the full output.

```
  make view S=fd09_tage SURFER=surfer
  SURFER=surfer make view S=fd09_tage
  make view S=fd09_tage SURFER_LOG=info
```

The command file (FDT-12a) shows the signals grouped by unit, in
pipeline order, the clock group first, with tb.cyc, the cycle count
from the release of reset (FDT-12b). Names have Surfer's name type
Unique: the shortest suffix of the path that tells the signal apart
from the others shown. The per-slot signals are those of the model
that wrote the FST: slot 0 only on the one-slot model, and both slots
on the two-slot model.

Every format comes from the table FORMATS in waves/fe_demo_sigs.py
(DOC-006), in Surfer's format names:

```
  tb.clk                                    Clock
  a 1-bit signal, tb.rstn included          Bit
  an enum-typed signal                      Enum, the value names
                                            Verilator writes into the FST
  a per-slot or per-lane mask               Binary (a per-slot mask is
                                            1 bit, so Bit, at one slot)
  a count or iteration number, tb.cyc,      Unsigned, at any width
  an SRAM init write address, an index,
  pointer, position or table number
  an address, target, PC or data            Hexadecimal
  an encoded field: trx_type, the ITLB      Unsigned; the description
  and walker status, cause and privilege    gives the encoding
```

A signal the table does not match stops waves/mk_sucl.py.

Every scenario also has one marker per event of its description's
event table (a row with a cyc value), named c<cyc>_<label>, and opens
with the view at the first marker (FDT-12c). The table is the one of
the description's level-2 section headed Events, with or without a
section number, in the five-section form (FDT-13) or not (DOC-009):
section 4 of fd09_tage and FD-22 to FD-24, section 6 of the others. A
description that cites a cycle as cyc <n> with no Events section, or an
Events table the script cannot read, stops waves/mk_sucl.py with the
file and line; one with neither has no markers and opens on the whole
run.

Plusargs, if running the model directly:
`+SCEN=<name>`, `+FST=<file>`, `+TRACE`, and the three `*_FAST_INIT=1`
options, which the Makefile passes to every scenario but FD-1. The
Makefile also passes `+verilator+quiet`, which drops the simulator's
end-of-run report.

After a change to the RTL that renames a signal, or to a
description's event table, run the scenarios, regenerate the Surfer
command files, and check them in Surfer (it opens a window per
scenario). Each command file is written from its own scenario's FST.
The FST gives the slot count and the signal names, and the markers are
placed from it. Either
script takes scenario names; with none it does every scenario.
chk_sucl.py takes SURFER from the environment, default
$RVA_ROOT/tools/bin/surfer as for make view:

```
  make -k scenarios
  python3 waves/mk_sucl.py
  python3 waves/chk_sucl.py
```

On a missing FST or a signal the FST does not have, mk_sucl.py stops
and writes no file. chk_sucl.py fails a file whose contents differ from
what it derives itself from fe_demo_sigs.py and the FST.

---

## 3. The scenarios and what to look for

Each scenario has a description in docs/<scenario>.md: the program,
why it produces the behaviour, what the monitor counts, how to read the
result line and what to look at in the waveform. The descriptions of
FD-22 to FD-24 are in the five-section form of FDT-13, and
docs/fd09_tage.md is too, with an introduction ahead of the sections;
the other twenty predate the form. The slots column is the model the
scenario runs on.

```
scenario             FD     slots  title

fd01_reset_init      FD-1   1      Reset and SRAM initialization
fd02_steady          FD-2   1      Steady-state prediction and fetch
fd03_two_branch      FD-3   2      Two branches in one block
fd04_p2_override     FD-4   1      p2 override
fd05_p3_override     FD-5   1      p3 override
fd06_loop_pred       FD-6   1      Loop predictor
fd07_calls_returns   FD-7   1      Calls and returns
fd08_indirect        FD-8   1      Indirect jump
fd09_tage            FD-9   1      TAGE provider, allocation, use_alt_on_na
fd10_pd_redirect     FD-10  1      Predecode redirect
fd11_be_mispredict   FD-11  1      Backend mispredict
fd12_training        FD-12  1      Training
fd13_l1i             FD-13  1      L1I hit and miss
fd14_translation     FD-14  1      Translation
fd15_faults          FD-15  1      Faults
fd16_page_cross      FD-16  1      Page-crossing block
fd17_rvc             FD-17  1      Compressed and unaligned code
fd18_uncached        FD-18  1      Uncached fetch
fd19_fencei_cbo      FD-19  1      FENCE.I and cbo.inval
fd20_backpressure    FD-20  1      Backpressure
fd21_commit          FD-21  1      Commit
fd22_sc_slot1        FD-22  2      SC reversing slot 1
fd23_jump_cut        FD-23  2      A jump behind two conditionals
fd24_call_slot1      FD-24  2      A call in slot 1
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
the redirect target. At one slot the last block of the chain, a
conditional before a jump, also redirects at p2 to the jump's own
address: its FTB entry holds the conditional and ends at the jump (the
split at update), while its uBTB entry ends past the jump.

**fd05_p3_override.** At p3, `w_sc_hit_p3` with `w_taken_p3` opposite
to the p2 slot's `taken`. The slot's `pred_src` is PRED_SC.
`w_ok_redir_p3` accepts the slot's `bpu_redir_p3`.

**fd06_loop_pred.** After the warm-up passes, the inner loop branch's
slot carries `pred_src` PRED_LOOP at p1 and p2; on the tenth pass
its `taken` drops and the retired branch is not followed by a backend
redirect.

**fd07_calls_returns.** `tosw` and `tosr` move up on each call and down
on each return; during the recursion `spec_rctr` of the top entry
climbs above 1 instead of the pointers moving. `w_br_type_p2`
RETURN_CALL marks the coroutine switches.

**fd08_indirect.** `w_ittage_pred_rdy_p2` with
`w_ittage_pred_meta_p2.[s].ittage_hit` set, and the p2 slot of the jump
taking `pred_src` PRED_ITTAGE with the alternating target.

**fd09_tage.** In `tage_pred_meta_p2`, `tage_prm_comp` non-zero with
`tage_using_primary` set is a tagged provider; `tage_using_primary` low
with `tage_alt_comp` 0 is T0 by use_alt_on_na (watch `uaon` rise). An
allocation is `trx_type` with `u_alc_wr` set.

**fd10_pd_redirect.** On the first pass, `ifu_ftq_pdwb_val` with
`ifu_ftq_mis_val` set and `ifu_ftq_target` the JAL's target;
`w_pd_redir_val` follows and `ftq_ifu_flush_val` drops the younger
blocks.

**fd11_be_mispredict.** `bkend_ftq_redir_val` with cause
RC_MISPREDICT, then `ftq_ifu_flush_val`. `ftq_rollback_val` steps
`bpu_ghist_ptr` back and comes with `ras_restore_val`. The next
`ftq_ifu_req_val` starts at `bkend_ftq_redir_pc`.

**fd12_training.** `bkend_ftq_rsv_val` resolutions, then the per
predictor update valids of `u_bpu`; each `ftb_upd_valid_u0` comes with
`h3_ftb_upd` and `w_hold`, the cycle with no p0 request.

**fd13_l1i.** In the loop, `b_rsp_valid` two cycles after each
`ifu_l1i_req_val`; at the cold line, `b_mis_valid`, an MSHR `e_val`,
`l1i_mem_a_valid`, two `l1i_mem_d_valid` beats and the fill. The block
back at line X raises `mrg_hit`: it joins the register already
fetching X (cyc 183, after the FENCE.I and its line of fillers).

**fd14_translation.** `itlb_l2t_req_val` for each new page; with
`itlb_l2t_v` 0 the walker's `r_st` runs the S_S states only, with
`itlb_l2t_v` 1 (after the ecall) it alternates through the S_G states.
The CAS is `ptw_mem_req_op` 1 on the leaf's address.

**fd15_faults.** The ITLB answers `itlb_ifu_status` 2 (fault) with
`itlb_ifu_cause` 12, then 1, then 20, and the translation queue marks
`xq_fault0`. Each faulting packet reaches decode with the matching
`pd_out.[0].fault_cause` (`IFU_FAULT_*`).

**fd16_page_cross.** The block at the page's last 16 bytes: two
`ifu_itlb_req_val` lookups for adjacent VPNs, and its translation queue
entry popped with `xq_cross` set and `xq_ppn0` and `xq_ppn1` the two
pages' PPNs (0x81000 and 0x81205).

**fd17_rvc.** The 32-bit instruction at +0x3E reaches decode whole in
the block that starts before it, at `pos` 15, with `is_rvc` 0; in the
loop, 16-bit control transfers appear expanded in `pd_out.instr`.

**fd18_uncached.** Fetch from a page with PBMT NC, then from one with
PBMT IO. `ifu_l1i_req_uncached` requests one at a time, each after
`ftq_ifu_commit_ptr` has reached its block (`w_uc_gate`); `xq_uc` marks
the page; no `b_fil_valid` for either page's lines installs them. The
result line counts the requests from each page.

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
stall starts at decode (`pd_out.[0].valid` waiting, from cyc 18),
reaches the ibuf (`ibuf_ifu_rdy` low, from cyc 71) and then the FTQ
(`ftq_full`, from cyc 138), after which `ftq_pred_val_p0` is low while the
FTQ is full. The earlier single-cycle drops of `ftq_pred_val_p0` are
FTB update holds, not backpressure.

**fd21_commit.** `bkend_ftq_commit_val` moves `w_commit_ptr`; each
`ras_commit_val` call pushes the commit stack (`csp`,
`commit_top_addr`) and each return pops it.

**fd22_sc_slot1.** Two slots: in the block at 0x8000_0008,
`bpu_slot_p3.[1].pred_src` PRED_SC behind a slot 0 with PRED_TAGE, and
`bpu_redir_p3.[1].valid` with `w_ok_redir_p3`; from cyc 110.

**fd23_jump_cut.** Two slots: the FTB update that splits the entry for
the block at 0x8000_0008 (`upd_split`, cyc 65); then a p2 group with two
not-taken conditionals, `w_cut_p2` clear and `bpu_blk_pft_p2` the
jump's address 0x8000_0016, the FTB's stored end, from cyc 71; the next
group, at 0x8000_0016, with the jump in slot 0, from cyc 98.

**fd24_call_slot1.** Two slots: a not-taken conditional in
`bpu_slot_p2.[0]` and the call in `.[1]`, with
`w_ras_pred_val_p2.[1]`; `u_ras.tosr` and `tosw` move and the return
address 0x8000_0014 is written; from cyc 90.

---

## 4. Release

A showcase release is an annotated tag fe-<major>.<minor>.<patch>
(planning/showcase/showcase_release_decisions.md SR-1); Jeff applies
every tag by hand (SR-2). The Showcase pages and the hosted waveforms
show the commit of one tag (SR-5): the CI docs build takes the pages
from examples/fe_demo/docs/ at the latest tag (SR-4, SR-6), and
tools/publish_waves.py publishes the waveforms of the commit at a tag
and records the tag in pacino-waves/manifest.json (SR-9).

Steps, in order, from the repository root:

```
  1. Bring main to the release state and push it: the RTL, the
     descriptions and their event checks, and the .sucl files
     (section 2). The commit must hold .github/workflows/docs.yml
     with the fe-* tag trigger: a tag push runs the workflow file
     of the tag's commit.

  2. Tag that commit, annotated, with HEAD at it:
       git tag -a fe-1.0.0 -m "fe-1.0.0: <one line>"

  3. Fetch the published manifest for the staleness report:
       curl -fsSL -o /tmp/published.json \
         https://uarchlabs.github.io/pacino-waves/manifest.json

  4. Dry run: checks HEAD is at the tag, runs every scenario, computes
     the digests, reports each scenario against the published
     manifest, and writes the files it would push into
     examples/fe_demo/out/publish_dry_run/:
       tools/publish_waves.py --dry-run --published /tmp/published.json
     A patch release (no RTL change) reports every scenario
     unchanged. A scenario reported changed has a waveform that
     differs from the published one: its description must match the
     new waveform before the release goes out.

  5. Publish the waveforms:
       tools/publish_waves.py --published /tmp/published.json
     Then https://uarchlabs.github.io/pacino-waves/manifest.json has
     "tag": "fe-1.0.0" once GitHub Pages has updated.

  6. Push the tag. The docs workflow rebuilds the site with the
     Showcase pages of the tag:
       git push origin fe-1.0.0

  7. Check the Showcase landing page: it reads "Release fe-1.0.0" and
     links the tag, a scenario's "Source of this page" link is at
     blob/fe-1.0.0/, and its Open waveform link loads the waveform.
```

The waveforms go out before the tag is pushed, so the pages never name
a tag whose waveforms are not yet published. Without a tag the script
refuses; --untagged publishes HEAD and records the tag as untagged
(SR-9). --tag and --commit give the tag and its commit without a git
lookup (SR-10). tools/publish_waves.py --help lists the options, and
its header documents every key of manifest.json, the digest and the
staleness report.
