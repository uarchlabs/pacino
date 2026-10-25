<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd18_uncached: Uncached Fetch
```
 FILE:    fd18_uncached.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

`fd18_uncached` is the FD-18 demonstration scenario. It is a demo, not
a verification test. Code runs from a page whose Sv39 leaf has PBMT NC,
then from one whose leaf has PBMT IO (DOC-003). The IFU fetches each one
instruction per FTQ entry, each block only after every older entry has
committed, with uncached L1I requests that are answered from memory and
never written into the array. The run passes if the L1I takes uncached
requests from each page and no line of either page is filled into the
L1I.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).
A recorded run:

```
-I: fd18_uncached: PASS, uncached requests from the NC page 28,
    from the IO page 10, uncached lines filled 0, cyc 797
```

---

## 1. The program

Source: `programs/fd18_uncached.svh`, task `prog_fd18`, ported from
tb_fe_top's `uc_nc`. S-mode under satp Sv39. The pages
(`map4k`, and `map4k_pbmt` at
`rtl/core/frontend/fe_top/tb/models/fe_tb_writer.svh:770`):

```
RESET_VECTOR 0x8000_0000 -> PA 0x8000_0000   cacheable
c            0x8001_0000 -> PA 0x8100_0000   cacheable
u            0x8001_1000 -> PA 0x8120_3000   PBMT 1 (NC)
io           0x8001_2000 -> PA 0x8120_4000   PBMT 2 (IO)
```

```
RESET  mixed(3); jal x0, c
c      mixed(4); jal x0, u+0x10
u+0x10 mixed(3)                   +0x10 +0x12 +0x16
u+0x18 bne (cskip, taken)         to +0x22; +0x1C..+0x21 written dry
u+0x22 mixed(2)                   +0x22 +0x24
u+0x28 bne (cskip, not taken)
u+0x2C c.addi
u+0x2E jal x0, u+0x200
u+0x200 mixed(2); bne x6 at +0x206 back to +0x200, 3 iterations
u+0x20A mixed(2); jal x0, c+0x200 at +0x210
c+0x200 mixed(3); jal x1, u+0x400 at c+0x208 (link c+0x20C)
u+0x400 mixed(2); ret at +0x406
c+0x20C mixed(2); jal x0, io+0x10 at c+0x212
io+0x10 mixed(3)                  +0x10 +0x12 +0x16
io+0x18 bne (cskip, taken)        to +0x22; +0x1C..+0x21 written dry
io+0x22 mixed(2); jal x0, c+0x300 at io+0x28
c+0x300 mixed(2), then jal x0,0 (halt)
```

- 24 instructions execute on page u (derived from the source): 9 at
  u+0x10..u+0x2E, 12 at u+0x200..u+0x210, 3 at u+0x400..u+0x406. 7
  execute on page io, at io+0x10..io+0x28.
- The program records the IO page's PPN in `io_ppn`
  (`tb/fe_demo_mon.svh` line 160), which the monitor uses to split the
  uncached requests between the two pages.
- `map4k_pbmt` with a non-zero PBMT also records the PA and VA pages in
  `uc_ppn` and `uc_vpn` (`fe_tb_writer.svh:774-776`), which the
  monitor reads.
- The program sets the backend's eager mode (`eager = 1'b1`,
  `programs/fd18_uncached.svh:31`). With nothing presented, the backend
  then resolves a branch that ended its block against the block the
  FTQ fetched after it, and commits the entry of the last retired
  instruction (`rtl/core/frontend/fe_top/tb/models/fe_tb_backend.svh:162-191`).

---

## 2. Why the program produces the behaviour

1. Uncached marking. On an ITLB hit the IFU translation queue marks
   the page uncached when its effective attributes are not both
   cacheable and idempotent (`rtl/core/frontend/ifu/rtl/ifu_xlate.sv:226`).
   The ITLB passes the leaf's PBMT to the PMA check
   (`rtl/mmu/itlb/rtl/itlb.sv:420`, `:435`); NC is not cacheable, and IO
   is neither cacheable nor idempotent.
   `xq_uc` carries the mark (`ifu_xlate.sv:324`).
2. The commit gate. F0 does not match an uncached block until
   `commit_ptr` equals its FTQ index (`w_uc_gate`,
   `rtl/core/frontend/ifu/rtl/ifu_fetch.sv:278`, IFU-22). Its requests
   carry `ifu_l1i_req_uncached` (`ifu_fetch.sv:316`).
3. One instruction per entry. F3 delivers only the block's first valid
   instruction; when more would follow (`w_uc_cut`), it ends the block
   there with `mis_val` and `ifu_ftq_uc_end`, so the FTQ redirects to
   the next sequential instruction, a new entry
   (`rtl/core/frontend/ifu/rtl/ifu_f3.sv:368-373`, the writeback at
   lines 421 to 431; the rule is described at `ifu_f3.sv:94-114`). A
   JALR is delivered alone with no redirect.
4. No allocation. An uncached lookup is a miss whatever the tags hold
   (`rtl/core/frontend/icache/rtl/l1i_ctrl.sv:229-230`, L1I-24). A free
   MSHR register taken by an uncached request is marked not to
   allocate (`e_alloc <= !req_uncached`,
   `rtl/core/frontend/icache/rtl/l1i_mshr.sv:486`), and a fill is
   installed only when `fil_alloc` is set (`l1i_mshr.sv:350-360`).

---

## 3. What the monitor counts

The counts come from `tb/fe_demo_mon.svh:540-554`, sampled every cycle
while `meas` is set.

```
n_uc_req_nc  ifu_l1i_req_val && ifu_l1i_req_rdy && ifu_l1i_req_uncached,
             with the request's PA page not in io_ppn
             an uncached request the L1I took from the NC page (one per
             line requested)
n_uc_req_io  the same, with the PA page in io_ppn: from the IO page
n_uc_alloc   per bank b: u_l1i.u_mshr.b_fil_valid[b] and the filled
             line's PA page is in W.uc_ppn
             a line of an uncached page written into the array
```

`n_uc_alloc` sums the two banks of a cycle into `n_ucal` and adds the
sum once (DOC-002; it counted a cycle with both banks once before). It
is 0 in this run either way.

The proof (`tb/fe_demo_proofs.svh:144`) is
`n_uc_req_nc > 0 && n_uc_req_io > 0 && n_uc_alloc == 0`.
`tb_fe_demo.sv` also requires the whole stream to retire with no
errors.

---

## 4. Reading the numbers

- `uncached requests from the NC page 28` counts lines requested, not
  instructions. From the run (fst2vcd on
  `out/fd18_uncached/fd18_uncached.fst`, requests with
  `ifu_l1i_req_uncached` taken):
  - 14 for the 9 instructions at u+0x10..u+0x2E: the 4 in the lower
    half of the line request PA 0x8120_3000 alone; the 5 in the upper
    half (u+0x22 onward) request 0x8120_3000 and 0x8120_3040 in
    consecutive cycles (IFU-7);
  - 11 for the 12 instructions at u+0x200..u+0x210 (line
    0x8120_3200). Which instruction was served without a request of
    its own was not traced;
  - 3 for the 3 instructions at u+0x400 (line 0x8120_3400).
- `from the IO page 10`: the 7 instructions at io+0x10..io+0x28. The 4
  in the lower half of the line request PA 0x8120_4000 alone; the 3 in
  the upper half (io+0x22 onward) request 0x8120_4000 and 0x8120_4040
  (IFU-7). The first is at cyc 647.
- The requests are about 19 to 25 cycles apart (cycles 111, 130, 149,
  168, ... in the run): each waits at F0 for the previous entry to
  commit.
- `uncached lines filled 0` is the proof's last term: no fill of a line
  of PA page 0x81203 or 0x81204.
- FD-18 of `planning/showcase/fe_demo_scenarios.md` covers NC and IO
  (DOC-003); the program runs both. The commit gate FD-18's waveform
  names is `w_uc_gate`, in the `ifu_fetch` group with `xq_uc`.

---

## 5. Waveform

The saved view is `waves/fd18_uncached.sucl`, which `make view
S=fd18_uncached` opens in Surfer. Look at:

- `u_xlate.xq_uc` set for the blocks on the two uncached pages, and the
  commit gate `u_fetch.w_uc_gate` opening for each block.
- `ftq_ifu_commit_ptr` reaching each uncached block's `ftq_ifu_idx`
  before its `ifu_l1i_req_val` with `ifu_l1i_req_uncached`.
- each uncached block closing after one instruction, and the next block
  starting at the next instruction (`ftq_ifu_start_pc`). The writeback
  that closes it, `ifu_ftq_mis_val`, is not in this command file;
  `waves/fd10_pd_redirect.sucl` shows it.
- In the l1i group: `b_mis_valid` for each uncached request, an MSHR
  `e_val`, `l1i_mem_a_valid` and `l1i_mem_d_valid`, and no
  `b_fil_valid` for the 0x8120_3xxx or 0x8120_4xxx lines.
