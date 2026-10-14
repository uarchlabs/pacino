<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# CSR Decisions
```
 FILE:    csr_decisions.md
 SOURCE:  session-079, TD#178
 STATUS:  DRAFT
 UPDATED: 2026-10-14
 CONTACT: Jeff Nye
```

Owns the CSR-N and CSR-UN registries.

---

## 1. Organization

CSR-1  rtl/core/csr/rtl/csr_pkg.sv declares, for each CSR in
       sections 2 and 3:
         CSR_<NAME>_ADDR   12-bit localparam
         <name>_t          packed struct, full XLEN layout
         encodings         MODE values, PMP A-field values
         reset value
       and the three group structs of section 4.

CSR-2  rtl/core/csr/tb/csr_tb_pkg.sv (testbench only) holds a
       shadow of every CSR in csr_pkg and provides:
         csr_write(addr, value)   applies the write rules of CSR-5
         csr_read(addr)
         pack functions           shadow -> fe_cfg_t, fe_csr_t,
                                  ptw_csr_t
         csr_reset()              every CSR, priv, V and
                                  ext_enable to reset (CSR-7)
         set_ext_enable(v)        ext_enable has no address
         set_priv(p), set_v(v)    priv and V have no address
         set_pmp_g(g)             grain of the read-back rules; 10
                                  unless a PMP checker testbench
                                  builds another PMP_GRAN_LG2
         named setters            each field of 0x7C0 and 0x7C1
       The shadow is a class with static members behind these
       package functions. An address with no CSR in csr_pkg stops the
       simulation ($fatal).
       Every testbench that drives a group member takes its value
       from csr_tb_pkg. Testbenches of fe_top, the ITLB, the PMP
       checker and the walker drive the struct ports from the pack
       functions; testbenches of other modules drive their existing
       ports from the struct members.

---

## 2. Custom CSRs

Machine-level read/write, range 0x7C0-0x7FF.

```
  0x7C0   CSR_7C0, predictor enables
  bit     field                when 1
  0       sc_enable            SC participates in prediction and update
  1       ftb_fastpath_en      saturated FTB counter may commit at p2
  2       tage_enable_aging    TAGE useful-counter aging runs
  3       ittage_enable_aging  ITTAGE useful-counter aging runs
  63:4    reserved, read 0, writes ignored

  0x7C1   CSR_7C1, aging intervals
  bits    field
  31:0    tage_aging_interval
  63:32   ittage_aging_interval
```

CSR-3  sc_enable = 0: no SC update is issued, the SC prediction
       response is not consumed or waited on, SC-related FTB state
       is still buffered. PROPOSED.

CSR-4  ext_enable is not a CSR and has no address. It is a member of
       fe_cfg_t of type decode_pkg::ext_enable_t (one enable per
       decoded extension), set only through set_ext_enable, reset
       RVA23_ENABLE (all ones). Clearing a bit makes decode treat that
       extension as illegal; such a configuration is not RVA23.

---

## 3. Standard CSRs

XLEN 64. Fields as defined in [PRIV]; the table gives the implemented
subset. Bits not listed read 0.

```
  addr   CSR       field   bits    implemented
  0x180  satp      MODE    63:60   0 Bare, 8 Sv39
                   ASID    59:44   16 bits
                   PPN     43:0    23:0 (PPN_WIDTH 24)
  0x280  vsatp     MODE    63:60   0 Bare, 8 Sv39
                   ASID    59:44   16 bits
                   PPN     43:0    28:0 (GPA_WIDTH 41 - 12)
  0x680  hgatp     MODE    63:60   0 Bare, 8 Sv39x4
                   VMID    57:44   14 bits
                   PPN     43:0    23:0; 1:0 read 0 in Sv39x4
  0x30A  menvcfg   PBMTE   62
                   ADUE    61
  0x60A  henvcfg   PBMTE   62      read 0 when menvcfg.PBMTE = 0
                   ADUE    61      read 0 when menvcfg.ADUE = 0
  0x3A0  pmpcfg0   entries 0-7, one byte each:
  0x3A2  pmpcfg2   entries 8-15  L 7, A 4:3, X 2, W 1, R 0
                                   A: 0 OFF, 1 TOR, 3 NAPOT
                                   (NA4 not selectable, G = 10)
  0x3B0- pmpaddr0  ADDR    53:0    33:0 (PA_WIDTH 36)
  0x3BF  -15
```

priv and V are hart state, not CSRs. priv encoding: 00 U, 01 S,
11 M.

CSR-5  csr_write rules:

```
  satp     unsupported MODE: no field written
  hgatp    unsupported MODE: MODE unchanged, VMID and PPN written
  vsatp    unsupported MODE: no field written. PROPOSED
  pmpcfg   locked entry (L = 1): entry and its pmpaddr not written
           A = NA4 written: stored as NAPOT
           R = 0 with W = 1 written: stored with W = 0
  pmpaddr  not written when the next entry is locked with A = TOR
           read-back with G = 10: NAPOT entry, bits 8:0 read 1;
           OFF or TOR entry, bits 9:0 read 0
  henvcfg  PBMTE read 0 when menvcfg.PBMTE = 0
           ADUE read 0 when menvcfg.ADUE = 0
  all      unimplemented bits read 0
```

       Read-0 rules apply at csr_read and in the pack functions; the
       stored bit is kept. The R = 0/W = 1, next-entry TOR lock and
       henvcfg.PBMTE rules are implemented by SYS-002.

---

## 4. Group structs and RTL connection

CSR-6  fe_top and the ITLB take fe_csr_t, fe_top takes fe_cfg_t and
       the walker takes ptw_csr_t, as whole-group ports. The PMP
       checker takes pmpcfg and pmpaddr, entries 0 to PMP_ENTRIES-1,
       as csr_pkg pmpcfg_ent_t and pmpaddr_imp_t arrays; its
       privilege input is not a group member (the walker's site
       checks at S). Inside fe_top the members drive the existing
       ports of the consumers below. Member names are the former
       port names without the csr_itlb_ or csr_ptw_ prefix.

```
  fe_cfg_t   source: 0x7C0, 0x7C1, ext_enable
  member                  consumer
  sc_enable               bp_cluster, FTQ (sc carries the port,
                          unused)
  ftb_fastpath_en         bp_cluster (FTB fast path)
  tage_enable_aging       tage
  tage_aging_interval     tage
  ittage_enable_aging     ittage
  ittage_aging_interval   ittage
  ext_enable              decode

  fe_csr_t   source: satp, vsatp, hgatp, pmpcfg, pmpaddr, priv, V
  member                  consumer
  v, priv                 ITLB, ITLB PMP checker (priv only)
  satp MODE, ASID         ITLB
  vsatp MODE, ASID        ITLB
  hgatp MODE, VMID        ITLB
  pmpcfg[16], pmpaddr[16] ITLB PMP checker

  ptw_csr_t  source: satp, vsatp, hgatp, menvcfg, henvcfg, pmpcfg,
             pmpaddr
  member                  consumer
  satp, vsatp, hgatp
    MODE, PPN             walker
  menvcfg ADUE, PBMTE     walker
  henvcfg ADUE, PBMTE     walker
  pmpcfg[16], pmpaddr[16] walker PMP checker
```

       fe_top takes fe_cfg_t and fe_csr_t and distributes the
       members above. The walker is outside fe_top and takes
       ptw_csr_t directly. The walker samples the MODE, PPN, ADUE
       and PBMTE members at the start of each walk; its PMP checker
       reads pmpcfg and pmpaddr every cycle.

CSR-7  Reset values (csr_reset):

```
  0x7C0     0x1                  sc_enable 1, the other three 0
  0x7C1     0
  satp      0x0000_0000_0008_F000  MODE Bare, ASID 0, PPN 0x8F000
  vsatp     0
  hgatp     0
  menvcfg   0x4000_0000_0000_0000  PBMTE 1, ADUE 0
  henvcfg   0x4000_0000_0000_0000  PBMTE 1, ADUE 0
  pmpcfg0   0x1F                 entry 0 NAPOT RWX, entries 1-7 OFF
  pmpcfg2   0
  pmpaddr0  0x3_FFFF_FFFF        every implemented bit
  pmpaddr1-15  0
  priv      11 (M)
  V         0
  ext_enable  RVA23_ENABLE (all ones)
```

---

## 5. Open

CSR-U1 Names of the CSRs at 0x7C0 and 0x7C1.
CSR-U2 Hardware delivery of CSR state to the groups, and ordering
       of a CSR write against fetch, SFENCE.VMA, HFENCE, FENCE.I.

---

## 6. References

```
  [PRIV]   RISC-V Privileged Architecture, ISA manual v20260120
           https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html
           https://docs.riscv.org/reference/isa/v20260120/priv/machine.html
           https://docs.riscv.org/reference/isa/v20260120/priv/supervisor.html
           https://docs.riscv.org/reference/isa/v20260120/priv/hypervisor.html
  [RVA23]  RVA23 Profiles v1.0
           https://docs.riscv.org/reference/rva23/v1.0/rva23-profiles.html
```

---

## 7. Document History

```
  2026-10-13  session-079. Created for TD#178.
  2026-10-14  session-079, after SYS-001. CSR-2 setters, CSR-5 rules
              (NA4, R=0/W=1, next-entry TOR lock, henvcfg.PBMTE),
              CSR-6 port shapes and walker sampling, CSR-7 reset
              values.
```
