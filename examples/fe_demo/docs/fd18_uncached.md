<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd18_uncached: Uncached Fetch
```
 FILE:    fd18_uncached.md
 SOURCE:  DOC-002
 STATUS:  WORKING
 UPDATED: 2026-10-15
 CONTACT: Jeff Nye
```

`fd18_uncached` is the FD-18 demonstration scenario. It is a demo, not
a verification test. Code runs from a page whose Sv39 leaf has PBMT NC.
The IFU fetches it one instruction per FTQ entry, each block only after
every older entry has committed, with uncached L1I requests that are
answered from memory and never written into the array. The run passes
if the L1I takes uncached requests and no line of the NC page is
filled into the L1I.

A recorded run:

```
DEMO PASS fd18_uncached: uncached requests 28; uncached lines filled 0
(cycles 621)
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
c+0x20C mixed(2), then jal x0,0 (halt)
```

- 24 instructions execute on page u (derived from the source): 9 at
  u+0x10..u+0x2E, 12 at u+0x200..u+0x210, 3 at u+0x400..u+0x406.
- `map4k_pbmt` with a non-zero PBMT also records the PA and VA pages in
  `uc_ppn` and `uc_vpn` (`fe_tb_writer.svh:774-776`), which the
  monitor reads.
- The program sets the backend's eager mode (`eager = 1'b1`,
  `programs/fd18_uncached.svh:27`). With nothing presented, the backend
  then resolves a branch that ended its block against the block the
  FTQ fetched after it, and commits the entry of the last retired
  instruction (`rtl/core/frontend/fe_top/tb/models/fe_tb_backend.svh:162-191`).

---

## 2. Why the program produces the behaviour

1. Uncached marking. On an ITLB hit the IFU translation queue marks
   the page uncached when its effective attributes are not both
   cacheable and idempotent (`rtl/core/frontend/ifu/rtl/ifu_xlate.sv:226`).
   The ITLB passes the leaf's PBMT to the PMA check
   (`rtl/mmu/itlb/rtl/itlb.sv:420`, `:435`); NC is not cacheable.
   `xq_uc` carries the mark (`ifu_xlate.sv:324`).
2. The commit gate. F0 does not match an uncached block until
   `commit_ptr` equals its FTQ index (`w_uc_gate`,
   `rtl/core/frontend/ifu/rtl/ifu_fetch.sv:278`, IFU-22). Its requests
   carry `ifu_l1i_req_uncached` (`ifu_fetch.sv:316`).
3. One instruction per entry. F3 delivers only the block's first valid
   instruction; when more would follow (`w_uc_cut`), it ends the block
   there with `mis_val` and `ifu_ftq_uc_end`, so the FTQ redirects to
   the next sequential instruction, a new entry
   (`rtl/core/frontend/ifu/rtl/ifu_f3.sv:371-373`; the rule is described
   at `ifu_f3.sv:94-114`). A JALR is delivered alone with no redirect.
4. No allocation. An uncached lookup is a miss whatever the tags hold
   (`rtl/core/frontend/icache/rtl/l1i_ctrl.sv:229-230`, L1I-24). A free
   MSHR register taken by an uncached request is marked not to
   allocate (`e_alloc <= !req_uncached`,
   `rtl/core/frontend/icache/rtl/l1i_mshr.sv:486`), and a fill is
   installed only when `fil_alloc` is set (`l1i_mshr.sv:350-358`).

---

## 3. What the monitor counts

The counts come from `tb/fe_demo_mon.svh:502-511`, sampled every cycle
while `meas` is set.

```
n_uc_req     ifu_l1i_req_val && ifu_l1i_req_rdy && ifu_l1i_req_uncached
             an uncached request the L1I took (one per line requested)
n_uc_alloc   per bank b: u_l1i.u_mshr.b_fil_valid[b] and the filled
             line's PA page is in W.uc_ppn
             a line of the NC page written into the array
```

`n_uc_alloc` sums the two banks of a cycle into `n_ucal` and adds the
sum once (DOC-002; it counted a cycle with both banks once before). It
is 0 in this run either way.

The proof (`tb/fe_demo_proofs.svh:129`) is
`n_uc_req > 0 && n_uc_alloc == 0`. `tb_fe_demo.sv` also requires the
whole stream to retire with no errors.

---

## 4. Reading the numbers

- `uncached requests 28` counts lines requested, not instructions. From
  the run (fst2vcd on `out/fd18_uncached/fd18_uncached.fst`, requests
  with `ifu_l1i_req_uncached` taken):
  - 14 for the 9 instructions at u+0x10..u+0x2E: the 4 in the lower
    half of the line request PA 0x8120_3000 alone; the 5 in the upper
    half (u+0x22 onward) request 0x8120_3000 and 0x8120_3040 in
    consecutive cycles (IFU-7);
  - 11 for the 12 instructions at u+0x200..u+0x210 (line
    0x8120_3200). Which instruction was served without a request of
    its own was not traced;
  - 3 for the 3 instructions at u+0x400 (line 0x8120_3400).
- The requests are about 19 to 25 cycles apart (cycles 111, 130, 149,
  168, ... in the run): each waits at F0 for the previous entry to
  commit.
- `uncached lines filled 0` is the proof's second half: no fill of a
  line of PA page 0x81203.
- Departures from `planning/showcase/fe_demo_scenarios.md` FD-18:
  - FD-18 says "an NC or IO page"; the program uses NC only (PBMT 1).
    IO (PBMT 2) is not exercised.
  - FD-18's waveform names the commit gate; the save file has
    `ftq_ifu_commit_ptr` (ftq_ifu group) but not `w_uc_gate`.

---

## 5. Waveform

The saved views are `waves/fd18_uncached.gtkw` (GTKWave) and
`waves/fd18_uncached.sucl` (Surfer). Look at:

- `u_xlate.xq_uc` set for the blocks on page u.
- `ftq_ifu_commit_ptr` reaching each uncached block's `ftq_ifu_idx`
  before its `ifu_l1i_req_val` with `ifu_l1i_req_uncached`.
- `ifu_ftq_mis_val` closing each uncached block after one instruction,
  and the next block starting at the next instruction.
- In the l1i group: `b_mis_valid` for each uncached request, an MSHR
  `e_val`, `l1i_mem_a_valid` and `l1i_mem_d_valid`, and no
  `b_fil_valid` for the 0x8120_3xxx lines.
