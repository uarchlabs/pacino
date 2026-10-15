<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd15_faults: Page, Access and Guest-Page Fetch Faults
```
 FILE:    fd15_faults.md
 SOURCE:  DOC-002
 STATUS:  WORKING
 UPDATED: 2026-10-15
 CONTACT: Jeff Nye
```

`fd15_faults` is the FD-15 demonstration scenario. It is a demo, not a
verification test. Three indirect jumps fetch from targets that fault:
an unmapped page (instruction page fault), a mapped page whose physical
page PMP denies execute (instruction access fault), and, after an ecall
into VS-mode, a page whose VS-stage leaf names a GPA the G-stage does
not map (instruction guest-page fault). Each fault travels with its
block through the IFU to decode in `ifu_pd_pkt_t`. The run passes if
each cause reaches decode on its packet with the expected cause and VA.

A recorded run (DOC-002):

```
DEMO PASS fd15_faults: faults at decode: page 1, guest-page 1, access 1
(cycles 700)
```

---

## 1. The program

Source: `programs/fd15_faults.svh`, task `prog_fd15`. The address map
is `tb/fe_demo_lib.svh:55-70`: C 0x8001_0000, H 0x8002_0000 (handlers
`hnd(k)` = H + 0x40 k), V 0x8005_0000, targets `tgt(k)` =
0x8040_0010 + 0x20_0000 k.

```
setup   S-mode, satp Sv39 (begin_scen use_sv39 = 1)
        PMP: entry 2 everything RWX (pmp_all, fe_tb_csr.svh:162-165);
             entry 0 NAPOT 4 KiB at 0x8140_0000, R W, no X
             (pmp_page, fe_tb_csr.svh:155-159)
        h2_tables (fe_demo_lib.svh:87-94), V's handler page mapped
        two-stage; map_ch (fe_demo_lib.svh:74-82): reset page, C, H
0x8000_0000  mixed(3); jal x0, C
C            mixed(2)
C+0x06       jalr x0,0(x7) -> tgt(0) 0x8040_0010   nothing mapped
             -> page fault, trap to H
H            mixed(2)
H+0x06       jalr x0,0(x7) -> tgt(1) 0x8060_0010   VA -> 0x8140_0000
             -> access fault (PMP), trap to H+0x40
H+0x40       mixed(2)
H+0x46       ecall -> V                            V=1 when it retires
V            mixed(2)
V+0x06       jalr x0,0(x7) -> tgt(2) 0x8080_0010   VS leaf -> GPA
             0x2000_0000, not G-mapped
             -> guest-page fault, GPA 0x2000_0010, trap to V+0x1000
V+0x1000     mixed(4), jal x0,0                     halt
```

- `jr_fault` and `jr_gfault` (`fe_tb_writer.svh:707-723`) emit the
  `jalr` and an expected-stream entry for the faulting fetch at the
  target, with its cause, its VA (`fva` = the target) and, for the
  guest-page fault, its GPA. Nothing is written at the targets.
- The access-fault page has a valid Sv39 leaf (`mk_pte` with
  `PTE_LEAF`), so translation succeeds and only PMP refuses it.
- The VS-mode switch is FD-14's: `ecall_to_vs` and `be_trap_hook`
  (`tb/fe_demo_mon.svh:298-307`).

---

## 2. Why the program produces the behaviour

Each `jalr` is first mispredicted (no target known), so the backend
redirects to the target; its fetch then faults. In the run (cyc is
`tb.cyc`, `fe_tb_dut.svh:129`):

1. Page fault. Walk for VPN 0x80400 (V=0) at cyc 0x5a; the walker
   answers ST_FAULT (`rtl/mmu/ptw/rtl/ptw.sv:225`) cause 12 at cyc
   0x68. The ITLB does not install a fault; it holds it in its tracker
   and answers the re-request with it (`rtl/mmu/itlb/rtl/itlb.sv:105-110`,
   `:525-528`).
2. Access fault. Walk for VPN 0x80600 at cyc 0xa6 answers ST_HIT, PPN
   0x81400, at cyc 0xbb. The ITLB checks every translation with its
   PMP/PMA checker (`pmp_pma_chk`, `itlb.sv:423-441`, execute access,
   privilege S) and answers a hit that fails it as ST_FAULT with the
   access cause (`itlb.sv:517-519`). PMP entry 0 matches first and has
   X clear.
3. Guest-page fault. After the ecall retires (redirect to V at cyc
   0xc9), walk for VPN 0x80800 with V=1 at cyc 0x18f. The VS-stage
   leaf gives GPA 0x2000_0000; the G-stage has no mapping for it, and
   the walker answers ST_FAULT cause 20 (0x14) at cyc 0x1ea. A
   G-stage page fault is a guest-page fault (`ptw.sv:79`, MMU-22).
4. Carriage to decode. The IFU's translation queue records each
   page's fault (`xq_fault0`,
   `rtl/core/frontend/ifu/rtl/ifu_xlate.sv:316`); `ifu_fetch` requests
   no line on a faulting page (`ifu_fetch.sv:24`, same directory); F3
   assigns each position its fault, cause and VA
   (`rtl/core/frontend/ifu/rtl/ifu_f3.sv:252-265`) and writes them
   into the packet (`fault_cause`, `fault_va`, `ifu_f3.sv:391-392`).
   Decode sees, at `pd_out[0]`:
   - cyc 0x6c, `start_pc` 0x8040_0010, `fault_cause` 2 (PAGE)
   - cyc 0xbf, `start_pc` 0x8060_0010, `fault_cause` 1 (ACCESS)
   - cyc 0x1ee, `start_pc` 0x8080_0010, `fault_cause` 3 (GUEST_PAGE)
   (`ifu_fault_e`,
   `rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv:563-566`).

---

## 3. What the monitor counts

The counts come from the backend's retirement hook,
`tb/fe_demo_mon.svh:279-285`, called for every retired expected entry
while the stream is being measured.

```
n_flt_page    an expected PAGE fault entry retired with
              fault_cause == expected and fault_va == expected
n_flt_guest   the same, GUEST_PAGE
n_flt_acc     the same, ACCESS
```

The proof (`tb/fe_demo_proofs.svh:117`) is
`n_flt_page > 0 && n_flt_guest > 0 && n_flt_acc > 0`. The backend also
checks every retired entry against the expected stream, the guest-page
fault's GPA included, and `tb_fe_demo.sv` requires the whole stream to
retire with no errors before it accepts the proof.

---

## 4. Reading the numbers

- Each figure is 1: one faulting fetch of each kind, as the program
  has.
- The walker is asked twice for each of VPN 0x80400 (cyc 0x5a and
  0x6b) and VPN 0x80800 (cyc 0x18f and 0x1ed), each time answering the
  fault. The run does not show which lookup starts the second walk;
  faults are not installed (section 2, step 1), so any later lookup of
  the page walks again.
- A V=1 walk for VPN 0x80020 (page H) starts at cyc 0xc9, in the cycle
  of the redirect to V, for a fetch younger than the ecall; it answers
  a fault at cyc 0x116 that nothing delivers. FD-14 shows the same.
- The program is FD-15's as `planning/showcase/fe_demo_scenarios.md`
  gives it. The proof as built also checks each packet's VA.

---

## 5. Waveform

The saved views are `waves/fd15_faults.gtkw` (GTKWave, `make view
S=fd15_faults`) and `waves/fd15_faults.sucl` (Surfer, `make sview
S=fd15_faults`). Groups: clock, itlb, walker, ifu_xlate, ifu_fault,
decode, backend. Look at:

- `itlb_ifu_rsp_val` with `itlb_ifu_status` 2 (ST_FAULT,
  `itlb.sv:239`) and `itlb_ifu_cause`: the ITLB's fault answer.
- `l2t_itlb_status` 1 with `l2t_itlb_cause` 12 or 20: a walk that
  faulted; `l2t_itlb_status` 0 with PPN 0x81400: the walk that
  succeeded before PMP refused it.
- `xq_fault0` on the translation queue entry, `ifu_ftq_fault_val`.
- `pd_out.[0].fault_cause` and `pd_out.[0].fault_va` at cyc 0x6c,
  0xbf and 0x1ee, then `bkend_ftq_redir_val` with cause 1 (the trap)
  to the handler.
