<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd15_faults: Page, Access and Guest-Page Fetch Faults
```
 FILE:    fd15_faults.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
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

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).
A recorded run:

```
-I: fd15_faults: PASS, page faults at decode 1, guest-page faults at decode 1,
    access faults at decode 1, cyc 700
```

---

## 1. The program

Source: `programs/fd15_faults.svh`, task `prog_fd15`. The address map
is `tb/fe_demo_lib.svh:91-106`: C 0x8001_0000, H 0x8002_0000 (handlers
`hnd(k)` = H + 0x40 k), V 0x8005_0000, targets `tgt(k)` =
0x8040_0010 + 0x20_0000 k.

```
setup   S-mode, satp Sv39 (begin_scen use_sv39 = 1)
        PMP: entry 2 everything RWX (pmp_all, fe_tb_csr.svh:162-165);
             entry 0 NAPOT 4 KiB at 0x8140_0000, R W, no X
             (pmp_page, fe_tb_csr.svh:155-159)
        h2_tables (fe_demo_lib.svh:123-130), V's handler page mapped
        two-stage; map_ch (fe_demo_lib.svh:110-118): reset page, C, H
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
  (`tb/fe_demo_mon.svh:336-345`).

---

## 2. Why the program produces the behavior

Each `jalr` is first mispredicted (no target known), so the backend
redirects to the target; its fetch then faults. In the run (cyc is
`tb.cyc`, `fe_tb_dut.svh:129`):

1. Page fault. Walk for VPN 0x80400 (V=0) at cyc 90; the walker
   answers ST_FAULT (`rtl/mmu/ptw/rtl/ptw.sv:226`) cause 12 at cyc
   104. The ITLB does not install a fault; it holds it in its tracker
   and answers the re-request with it (`rtl/mmu/itlb/rtl/itlb.sv:105-110`,
   `:525-528`).
2. Access fault. Walk for VPN 0x80600 at cyc 166 answers ST_HIT, PPN
   0x81400, at cyc 187. The ITLB checks every translation with its
   PMP/PMA checker (`pmp_pma_chk`, `itlb.sv:423-441`, execute access,
   privilege S) and answers a hit that fails it as ST_FAULT with the
   access cause (`itlb.sv:517-519`). PMP entry 0 matches first and has
   X clear.
3. Guest-page fault. After the ecall retires (redirect to V at cyc
   202), walk for VPN 0x80800 with V=1 at cyc 399. The VS-stage leaf
   gives GPA 0x2000_0000, which the G-stage does not map. The walker
   answers ST_FAULT cause 20 (0x14) at cyc 490. A
   G-stage page fault is a guest-page fault (`ptw.sv:79`, MMU-22).
4. Carriage to decode. The IFU's translation queue records each
   page's fault (`xq_fault0`,
   `rtl/core/frontend/ifu/rtl/ifu_xlate.sv:316`); `ifu_fetch` requests
   no line on a faulting page (`ifu_fetch.sv:24`, same directory); F3
   assigns each position its fault, cause and VA
   (`rtl/core/frontend/ifu/rtl/ifu_f3.sv:252-279`) and writes them
   into the packet (`fault_cause`, `fault_va`, `ifu_f3.sv:391-392`).
   Decode sees, at `pd_out[0]`:
   - cyc 108, `start_pc` 0x8040_0010, `fault_cause` IFU_FAULT_PAGE
   - cyc 191, `start_pc` 0x8060_0010, `fault_cause` IFU_FAULT_ACCESS
   - cyc 494, `start_pc` 0x8080_0010, `fault_cause`
     IFU_FAULT_GUEST_PAGE
   (`ifu_fault_e`,
   `rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv:563-566`).

---

## 3. What the monitor counts

The counts come from the backend's retirement hook,
`tb/fe_demo_mon.svh:317-323`, called for every retired expected entry
while the stream is being measured.

```
n_flt_page    an expected PAGE fault entry retired with
              fault_cause == expected and fault_va == expected
n_flt_guest   the same, GUEST_PAGE
n_flt_acc     the same, ACCESS
```

The proof (`tb/fe_demo_proofs.svh:129`) is
`n_flt_page > 0 && n_flt_guest > 0 && n_flt_acc > 0`. The backend also
checks every retired entry against the expected stream, the guest-page
fault's GPA included, and `tb_fe_demo.sv` requires the whole stream to
retire with no errors before it accepts the proof.

---

## 4. Reading the numbers

- Each figure is 1: one faulting fetch of each kind, as the program
  has.
- The walker is asked twice for each of VPN 0x80400 (cyc 90 and 107)
  and VPN 0x80800 (cyc 399 and 493), each time answering the
  fault. The run does not show which lookup starts the second walk;
  faults are not installed (section 2, step 1), so any later lookup of
  the page walks again.
- A V=1 walk for VPN 0x80020 (page H) starts at cyc 201, the cycle
  before the redirect to V, for a fetch younger than the ecall; it answers
  a fault at cyc 278 that nothing delivers. FD-14 shows the same.
- The program is FD-15's as `planning/showcase/fe_demo_scenarios.md`
  gives it. The proof as built also checks each packet's VA.

---

## 5. Waveform

The saved view is `waves/fd15_faults.sucl`, which `make view
S=fd15_faults` opens in Surfer. Groups: clock, itlb, walker, ifu_xlate,
ifu_fault, decode, backend. Look at:

- `itlb_ifu_rsp_val` with `itlb_ifu_status` 2 (ST_FAULT,
  `itlb.sv:239`) and `itlb_ifu_cause`: the ITLB's fault answer.
- `l2t_itlb_status` 1 with `l2t_itlb_cause` 12 or 20: a walk that
  faulted; `l2t_itlb_status` 0 with PPN 0x81400: the walk that
  succeeded before PMP refused it.
- `xq_fault0` on the translation queue entry, `ifu_ftq_fault_val`.
- `pd_out.[0].fault_cause` and `pd_out.[0].fault_va` at the cycles of
  section 2, step 4. After each, `bkend_ftq_redir_val` with cause
  RC_TRAP to the handler.
- The encoded fields are shown as numbers (DOC-006):
  - `itlb_ifu_status` (`planning/interfaces/itlb_ifu_interfaces.md`
    IT-4): 0 hit, 1 miss (a walk has started), 2 fault, 3 reserved.
  - `itlb_ifu_cause` (IT-6), valid with a fault: 1 instruction access
    fault, 12 instruction page fault, 20 instruction guest-page fault.
  - `l2t_itlb_status` (`itlb_l2tlb_interfaces.md` IL-4): 0 hit,
    1 fault, 2 retry, 3 reserved.
  - `l2t_itlb_cause`, valid with a fault: the same exception codes,
    for the three causes of IL-10.
  - `itlb_l2t_priv` (IL-3d): 0 U, 1 S; with `itlb_l2t_v` it is the
    effective privilege. 2 (reserved) and 3 (M) are never presented.

---

## 6. Events

| cyc | Event                                            | Other              |
|-----|--------------------------------------------------|--------------------|
| 0   | reset released (`tb.rstn`); the FTQ requests     | S-mode, Sv39       |
|     | 0x8000_0000 the same cycle                       |                    |
| 90  | walk for VPN 0x80400, the page of tgt(0),        | nothing mapped     |
|     | single-stage                                     |                    |
| 104 | the walker answers a page fault, cause 12        | status 1           |
| 108 | the page fault reaches decode: lane 0 at         |                    |
|     | 0x8040_0010, `fault_cause` IFU_FAULT_PAGE        |                    |
| 166 | walk for VPN 0x80600, the page of tgt(1)         |                    |
| 187 | the walker answers a hit, PPN 0x81400; the       | status 0           |
|     | ITLB's PMP check refuses it                      |                    |
| 191 | the access fault reaches decode: lane 0 at       |                    |
|     | 0x8060_0010, IFU_FAULT_ACCESS                    |                    |
| 202 | the ecall's trap redirect to V, 0x8005_0000      | backend            |
| 399 | walk for VPN 0x80800, the page of tgt(2), with   | nested             |
|     | `itlb_l2t_v` 1                                   |                    |
| 490 | the walker answers cause 20, a guest-page fault: | status 1           |
|     | the G-stage does not map GPA 0x2000_0000         |                    |
| 494 | the third fault reaches decode: lane 0 at        |                    |
|     | 0x8080_0010, IFU_FAULT_GUEST_PAGE                |                    |
| 700 | the run ends                                     |                    |
