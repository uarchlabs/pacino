<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd14_translation: Sv39 Walk, Sv39x4 Nested Walk and Svadu CAS
```
 FILE:    fd14_translation.md
 SOURCE:  DOC-002
 STATUS:  WORKING
 UPDATED: 2026-10-15
 CONTACT: Jeff Nye
```

`fd14_translation` is the FD-14 demonstration scenario. It is a demo,
not a verification test. Code runs at S-mode under satp Sv39; its code
page has a leaf with A clear and menvcfg.ADUE set, so the walk sets A
by compare-and-swap (Svadu). An ecall then moves execution to VS-mode
(V=1, vsatp Sv39, hgatp Sv39x4), where the next fetch walks both
stages. The run passes if a single-stage walk, a walk with V=1 that
evaluates G-stage PTEs, and a CAS each happen at least once.

A recorded run (DOC-002):

```
DEMO PASS fd14_translation: walks V=0 2, V=1 2 (G-stage PTE evaluations
21); CAS 1 (cycles 285)
```

---

## 1. The program

Source: `programs/fd14_translation.svh`, task `prog_fd14`. The address
map constants are in `tb/fe_demo_lib.svh:55-61`.

```
setup   S-mode, satp Sv39, ASID 1, root 0x8F00_0000
        (begin_scen use_sv39 = 1; fe_tb_backend.svh:576-594)
        menvcfg.ADUE = 1 (csr_menv_adue, fe_tb_csr.svh:86)
        h2_tables: G-stage root 0x8E00_0000, a VS root, and page
        V 0x8005_0000 -> GPA 0x1005_0000 -> SPA 0x8160_0000
        RESET_VECTOR page mapped to itself; H mapped; C 0x8001_0000 ->
        0x8100_0000 with a leaf whose A bit is clear (PTE_LEAF & 0xBF)
0x8000_0000  mixed(3)
0x8000_0008  jal x0, C
C            mixed(8)                     22 bytes
C+0x16       ecall -> V                   to_h2: V=1 when it retires
V            mixed(8), jal x0,0           halt
```

- The leaf for C is written directly with `mk_pte` and `s_slot`
  (`fe_tb_writer.svh:735`, `:743`): flags 0x8B (D, X, R, V; A and U
  clear) instead of `PTE_LEAF` 0xCB.
- The regime change rides on the ecall's trap. `ecall_to_vs`
  (`tb/fe_demo_lib.svh:97-100`) marks the entry; when it retires,
  `be_trap_hook` (`tb/fe_demo_mon.svh:298-307`) sets V=1, privilege S
  (VS), vsatp Sv39 with ASID 1 and hgatp Sv39x4 with VMID 3. The
  backend's trap redirect then fetches V.

---

## 2. Why the program produces the behaviour

1. Single-stage walks. The first fetch of the reset page and of C miss
   the ITLB and walk with V=0 (`itlb_l2t_v` 0). In the run: VPN 0x80000
   at cyc 0x04, VPN 0x80010 at cyc 0x2e (cyc is `tb.cyc`,
   `fe_tb_dut.svh:129`). Each reads three PTEs from root 0x8F00_0000.
2. The CAS. For C the leaf is valid and permitted but A is clear. The
   walker's leaf evaluation sets the update instead of a page fault
   when ADUE is set (`rtl/mmu/ptw/rtl/ptw.sv:535-537`; ADUE is
   menvcfg's for V=0, `:754-756`). `S_S_UPD` with no G-stage issues one
   CAS (`r_m_op <= OP_CAS`, `ptw.sv:940-955`): compare value the PTE it
   read, swap value the PTE with A set. In the run, at cyc 0x43:
   `ptw_mem_req_op` 1, `ptw_mem_req_paddr` 0x8F00_9080,
   `ptw_mem_req_cmp` 0x2040_008B, `ptw_mem_req_swap` 0x2040_00CB (A,
   bit 6, set; PPN 0x81000). The walk answers PPN 0x81000 at cyc 0x49.
3. Nested walks. After the ecall retires, a walk with V=1 enables the
   G-stage when hgatp is not Bare (`r_g_on`, `ptw.sv:752`). Every
   VS-stage PTE address is a GPA, translated through the G-stage
   (`S_G_START`, `S_G_ADDR`, `S_G_EVAL`; states at `ptw.sv:289-301`),
   and so is the final GPA. In the run there are two V=1 walks:
   - cyc 0x5b, VPN 0x80010 (page C, the code after the ecall). The
     backend's trap redirect to V is in the same cycle; this walk is
     for a fetch younger than the ecall. C is not mapped in the
     VS-stage, and the walk ends at cyc 0xa8 with status ST_FAULT
     (`ptw.sv:225`) and cause 12. Nothing delivers it; the block was
     flushed.
   - cyc 0xaa, VPN 0x80050 (page V). It answers PPN 0x81600 (PA_V) at
     cyc 0x10b.
   The first walk spends 9 cycles in `S_G_EVAL`, the second 12.

---

## 3. What the monitor counts

The counts come from `tb/fe_demo_mon.svh:489-496`, sampled every cycle
while the stream is being measured (`meas`).

```
n_walk_s   itlb_l2t_req_val && itlb_l2t_req_rdy && !itlb_l2t_v
n_walk_g   itlb_l2t_req_val && itlb_l2t_req_rdy &&  itlb_l2t_v
n_g_eval   cycles with u_ptw.r_st == S_G_EVAL
n_cas      ptw_mem_req_val && ptw_mem_req_rdy && ptw_mem_req_op
```

The proof (`tb/fe_demo_proofs.svh:110-111`) is
`n_walk_s > 0 && n_walk_g > 0 && n_g_eval > 0 && n_cas > 0`.
`tb_fe_demo.sv` also requires the whole stream to retire with no errors
before it accepts the proof.

---

## 4. Reading the numbers

- Walks are walker requests taken, wrong path included. Of the two
  V=1 walks one is the flushed fetch of C described in section 2; the
  proof's V=1 condition would be met by either.
- `n_g_eval` counts cycles in `S_G_EVAL`, one per G-stage PTE
  evaluated: 21 = 9 + 12 over the two V=1 walks.
- The wrong-path V=1 walk occupies the walker from cyc 0x5b to 0xa8,
  so the walk for V starts at cyc 0xaa, about 80 cycles after the
  redirect. This is reported for the design owner; the demonstration
  does not depend on it.
- The program is FD-14's as `planning/showcase/fe_demo_scenarios.md`
  gives it, the regime change on the ecall's trap included. The proof
  as built adds a G-stage evaluation count to "a walk of each kind".

---

## 5. Waveform

The saved view is `waves/fd14_translation.sucl`, which `make view
S=fd14_translation` opens in Surfer. Groups: clock, ifu_xlate, itlb,
walker, walker_mem. Look at:

- `itlb_l2t_req_val` with `itlb_l2t_vpn` and `itlb_l2t_v`: each walk
  and its kind.
- `u_ptw.r_st`: before cyc 0x5b (V=0) it takes S_START, the S_ states
  (2 to 5) and the memory and response states (9 to 11), never 6 to 8;
  with V=1 the G_ states (6 to 8) appear between them, and
  `u_ptw.r_g_on` is set.
- `ptw_mem_req_op` 1 at cyc 0x43, with `ptw_mem_req_cmp` and
  `ptw_mem_req_swap` differing in bit 6: the CAS.
- `l2t_itlb_rsp_val` with `l2t_itlb_status` and `l2t_itlb_ppn`: each
  walk's answer.
