<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Superscalar Out-of-Order Machines (publicly announced)

`?` = not found / not verified. `0` = confirmed absent. L1/L2 are per-core unless noted; L3 is per-cluster.

**Core columns:** ISA · IW (issue/decode width: `Ns`=N issue ports from RTL; `Nd`=N-wide decode/dispatch published) · L1Ds/L1Is (size) · L1Dw/L1Iw (way count) · L1Dl/L1Il (line) · L1Iw/c (I-fetch B/cyc) · L2I/L2D (unified shown in L2I as `(unified)`, L2D=`(comb)`) · FUS (fusion) · MOC (macro/micro-op cache; `0`=absent)
**System columns:** Clk (GHz) · Cores (max) · L3 · Vec (vector bits) · Proc
**Provenance:** [rtl] read from source · [ds] datasheet · [pub] published vendor/press/analysis, verified this session · [rec] recalled from general knowledge, **not** verified this session — confirm before relying

---

## RISC-V

| Name | URL | IW | L1Ds | L1Is | L1Dl | L1Il | L1Dw/c | L1Iw/c | L2I | L2D | FUS | MOC | Clk | Cores | L3 | Vec | Proc |
|------|-----|----|------|------|------|------|------|------|-----|-----|-----|-----|-----|-------|----|----|------|
| rsd | https://github.com/rsd-devel/rsd | 5 (2INT+1CPX+1MEM+1FP) | 4KB | 4KB | 8B | 8B | ? | 8B | ? | ? | N | 0 | FPGA | 1 | ? | ? | FPGA |
| riscyOO | https://github.com/csail-csg/riscy-OOO | 2d | ? | ? | ? | ? | ? | ? | ? | ? | N | 0 | FPGA | cfg | ? | ? | FPGA |
| soomRV | https://github.com/mathis-s/SoomRV | 5 (3ALU+2AGU) | 16KB | ? | 64B | ? | ? | 16B | ? | ? | Y(opt) | 0 | ? | 1 | ? | 0 | ? |
| sonicboom | https://github.com/riscv-boom/riscv-boom | 7 (3ALU+2MEM+1FP+1U) | 32KB | 32KB | 64B | 64B | 16B | 16B | ? | ? | N | 0 | cfg | cfg | SoC | cfg | cfg |
| xuantie C910 | https://github.com/XUANTIE-RV/openc910 | 3 | 64KB (2-way) | 64KB (2-way, VIPT) | 64B | 64B | 16B | ? | 256KB–8MB (unified, 16-way PIPT) | (comb) | N | 0 (see note) | ~2.0 | 4/cl | 0 | 128 (RVV0.7) | cfg |
| pulp C910 | https://github.com/pulp-platform/pulp-c910 | 3 | 64KB (2-way) | 64KB (2-way) | 64B | 64B | 16B | ? | 1MB–8MB (unified) | (comb) | N | 0 | ? | 4/cl | 0 | 128 | cfg |
| naxriscv | https://github.com/SpinalHDL/NaxRiscv | 2 (2ALU)+LSU | 16KB | 16KB | 64B | 64B | 8B | 8B | ? | ? | N | 0 | FPGA | cfg | ? | 0 | FPGA |
| Xiangshan Yanqihu | https://github.com/OpenXiangShan/XiangShan | ? | ? | ? | ? | ? | ? | ? | ? | ? | Y | 0 | ? | ? | ? | ? | 28nm |
| Xiangshan Nanhu | https://github.com/OpenXiangShan/XiangShan | 6d | 64KB | 64KB | 64B | 64B | ? | ? | 1MB (unified) | (comb) | Y | 0 | 2.0 | cfg | cfg | 128 | 14nm |
| Xiangshan Kunminghu | https://github.com/OpenXiangShan/XiangShan | 8d | 64KB (8-way) | 64KB (4-way) | 64B | 64B | 64B | 32B | ? | ? | Y | 0 | ? | cfg | cfg (CHI) | RVV1.0 | ? |
| toooba | https://github.com/bluespec/Toooba | 2d | ? | ? | ? | ? | ? | ? | ? | ? | N | 0 | FPGA | cfg | ? | ? | FPGA |
| ridecore | https://github.com/ridecore/ridecore | ? | ? | ? | ? | ? | ? | ? | ? | ? | N | 0 | FPGA | 1 | ? | 0 | FPGA |
| ssrv | https://github.com/risclite/SuperScalar-RISCV-CPU | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | 0 | FPGA | 1 | ? | 0 | FPGA |
| SiFive P550 | https://www.sifive.com/cores/performance-p500 | 3d | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | 4/cl | shared | 0 | cfg |
| SiFive P670 | https://www.sifive.com/cores/performance-p600 | 4d | ? | ? | ? | ? | ? | ? | ? | ? | Y | ? | ? | 4/cl | shared | 2x128 (RVV1.0) | cfg |
| SiFive P870 | https://www.sifive.com/cores/performance-p800 | 6d | ? | 64KB | ? | ? | ? | 36B | 4MB ex. (unified, non-incl) | (comb) | Y | N | >3.0 | 32 | shared | 2x128 (RVV1.0) | cfg |
| XuanTie C930 | https://www.xrvm.com/product/xuantie/C930 | 6d | 64KB (typ, cfg) | 64KB (typ, cfg) | ? | ? | ? | ? | 1MB (typ, cfg) | (comb) | ? | ? | ? | 4/cl typ, 32 max | ? | 256 (RVV1.0) | cfg |
| Akeana 5300 | https://www.akeana.com/ | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | ~3.0 | cfg | ? | RVV1.0 | cfg |
| TT-Ascalon X | https://tenstorrent.com/en/ip/tt-ascalon | 8d (6 INT/2br, 3 LS, 2 FP) | ? | ? | ? | ? | ? | 32B | cfg (shared, ≤8 cores) | (comb) | ? | Y | >2.5 | 8/cl | ? | 2x256 | Samsung SF4X |
| TT-Ascalon H / S / U | https://tenstorrent.com/en/ip/tt-ascalon | 6d / 4d / 2d | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | cfg | ? | cfg | cfg |
| Ventana Veyron V1 | (site retired, Qualcomm acq.) | 8d (4 int+mem ports) | 64KB (VIVT) | 512KB (L1+L2 combined) | ? | ? | 64B | 64B | 512KB | 512KB | Y | ? | 3.6 (?) | 192 (16/cl) | 48MB/16-core cl (3MB/core) | 0 (none) | TSMC 5nm |
| Ventana Veyron V2 | (site retired, Qualcomm acq.) | 15d | 128KB | ? | ? | ? | ? | ? | 1MB/core (unified) | (comb) | Y | Y | 3.6 | 192 (32/cl) | 128MB/cl | 512 (RVV1.0) | <5nm |
| Ventana Veyron V3 | (previewed; Qualcomm) | ? | ? | ? | ? | ? | ? | ? | ? | ? | Y | Y | 4.2 (target) | ? | ? | 512 (RVV1.0, +FP8 matrix) | ? |

## x86-64

| Name | ISA | IW | L1Ds | L1Is | L1Dl | L1Il | L1Dw/c | L1Iw/c | L2 | FUS | MOC | Clk | Cores | L3 | Vec | Proc |
|------|-----|----|------|------|------|------|------|------|----|-----|-----|-----|-------|----|----|------|
| AMD Zen 4 | x86-64 | 4d | 32KB (8-way) | 32KB (8-way) | 64B | 64B | 32B | 32B | 1MB (8-way, unified) | Y | Y (6.75K) | 5.7 | 16/CCD | 32MB/CCD | 512 (dbl-pumped) | TSMC N5 |
| AMD Zen 5 | x86-64 | 8d (2×4) | 48KB (12-way) | 32KB (8-way) | 64B | 64B | 64B | 2×32B | 1MB (16-way, unified) | Y | Y (6K, 16-way, 2×6-wide) | ~5.7 | 16/CCD | 32MB/CCD (4MB/core) | 512 (full) | TSMC N4X |
| Intel Golden Cove | x86-64 | 6d | 48KB | 32KB | 64B | 64B | 3×32B | 32B | 1.25MB (client) / 2MB (server) | Y | Y (~4K) | ~5.5 | cfg | cfg | 512 (server) | Intel 7 |
| Intel Redwood Cove | x86-64 | 6d | 48KB | 64KB | 64B | 64B | ? | ? | 2MB | Y | Y | ~5.1 | cfg | cfg | 256 | Intel 4 |
| Intel Lion Cove | x86-64 | 8d | 48KB L0 + 192KB L1 | 64KB | 64B | 64B | 128B | 128B | 2.5MB (LNL) / 3MB (ARL) | Y | Y (5.25K, 12 µop/clk) | ~5.7 | 8 | 12MB/4-core cl | 256 | TSMC N3B |

## Arm

| Name | ISA | IW | L1Ds | L1Is | L1Dl | L1Il | L1Dw/c | L1Iw/c | L2 | FUS | MOC | Clk | Cores | L3 | Vec | Proc |
|------|-----|----|------|------|------|------|------|------|----|-----|-----|-----|-------|----|----|------|
| Neoverse N1 | ARMv8.2 | 4d | 64KB | 64KB (4-way) | 64B | 64B | ? | 16B | 512KB–1MB | ? | 0 | 3.0 | 128 | SLC | 128 (NEON) | TSMC 7nm |
| Neoverse V1 | ARMv8.4 | 8d | 64KB | 64KB | 64B | 64B | ? | ? | 1MB | ? | Y | ~2.6 | 80 | SLC (CMN-700) | 2×256 (SVE) | 5nm |
| Neoverse V2 | ARMv9.0 | 6d (8 rename claimed) | 64KB | 64KB | 64B | 64B | ? | ? | 2MB (128B/cyc, quad-bank) | ? | Y (~1.5K) | ~3.1 | 72–144 | SLC | 4×128 (SVE2) | 4nm/5nm |
| Neoverse V3 | ARMv9.2 | 8d | 64KB | 64KB | 64B | 64B | ? | ? | 3MB (+ECC) | ? | ? | ~3.4 | 128+ | SLC | 4×128 (SVE2) | 3nm |
| Cortex-X4 | ARMv9.2 | 10d | 64KB | 64KB | 64B | 64B | ? | ? | 512KB–2MB | Y | 0 (removed) | ~3.4 | 14/cl | 0.5–32MB | 4×128 (SVE2) | 4nm |
| Cortex-X925 | ARMv9.2 | 10d | 64KB | 64KB | 64B | 64B | ? | 2× X4 | 2–3MB | Y | 0 | ~3.6 | 14/cl | 0.5–32MB | 4×128 (SVE2) | 3nm |
| Apple Firestorm (M1) | ARMv8.5 | 8d | 128KB | 192KB (6-way) | 128B | 64B | ? | 64B | 12MB/cluster | Y | 0 | 3.2 | 4/cl | 8MB SLC | 4×128 (NEON) | TSMC 5nm |
| Apple M4 P-core | ARMv9.2 (no SVE) | 10d | 128KB | 192KB (6-way) | 128B | 64B | ? | 64B (16 instr) | 16MB/cluster | Y | 0 | 4.51 | 6/cl, 2 cl | SLC | 4×128 + SME | TSMC N3E |
| Qualcomm Oryon (X Elite) | ARMv8.7 | 8d | 96KB | 192KB | 64B | 64B | ? | ? | 12MB/4-core cl | Y | 0 | 4.3 | 12 | 6MB SLC | 4×128 | TSMC N4 |

## Other

| Name | ISA | IW | L1Ds | L1Is | L1Dl | L1Il | L2 | FUS | MOC | Clk | Cores | L3 | Vec | Proc |
|------|-----|----|------|------|------|------|----|-----|-----|-----|-------|----|----|------|
| IBM POWER10 | Power ISA v3.1 | 8d | 32KB (8-way) | 48KB (6-way) | 128B | 128B | 2MB/core | ? | 0 | ~4.0 | 15–30 | 120MB (L3 as NUCA) | 4×128 (VSX) + MMA | Samsung 7nm |
| IBM z16 (Telum) | z/Architecture | 6d | 128KB | 128KB | 256B | 256B | 32MB/core (private) | ? | 0 | 5.2 | 8/chip | 256MB virtual L3 / 2GB virtual L4 | 128 (SIMD) | Samsung 7nm |
| IBM zEC12 | z/Architecture | ~3d | 96KB | 64KB | 256B | 256B | 1MB I + 1MB D | ? | 0 | 5.5 | 6 | 48MB | 0 | 32nm |

---

## Notes by row

### RISC-V

**XuanTie C910** [pub, chipsandcheese + T-Head docs] — L1I is **VIPT, 2-way**, L1D **64KB 2-way, 3-cycle**, split into 4-byte banks, one load + one store per cycle (128-bit stores take two). **Both L1s use FIFO replacement**, not LRU/PLRU. L1D tags are **split into two arrays, one for loads and one for stores**. Misses tracked by **8 line-fill buffer entries**; refill data held in two 512-bit fill registers. L2 is PIPT, 16-way, 64B lines, configurable 256KB/512KB/1MB/2MB/4MB/8MB, inclusive, 12-cycle beyond L1. Sv39, XMAE. MESI at L1, MOESI at L2. One secondary source claims a 32-entry macro-op cache; **not confirmed in the T-Head user manual or the openc910 RTL** — treat MOC=0 as the working assumption until read from source.

**XuanTie C930** [pub, The Register] — 6-decode, 16-stage, RVA23. 64KB I / 64KB D / 1MB L2 are described by XuanTie as **"typical" and configurable**, not fixed. Typical cluster is 4 cores; scales to 32. Vector unit is **256-bit** RVV1.0 with FP16/BF16/FP32/FP64/INT8-64. No line sizes, associativity, or fetch widths published.

**TT-Ascalon** [pub, Tenstorrent + xpu.pub] — launched Dec 4 2025 as licensable IP; **Ascalon S launched June 30 2026**. Family is X (extreme) / H / S / U, all derived from X. RV64ACDHFMV, RVA23, 2×256-bit RVV1.0. 8 decoders; 6 integer ALUs (2 branch-capable), 3 load/store, 2 FP. µop cache present. >22 SPECint2006/GHz, >2.3 SPECint2017/GHz, >3.6 SPECfp2017/GHz, >2.5 GHz on Samsung SF4X. Clusters of 2–8 cores share a configurable L2; CHI.E / AXI5-LITE, drop-in for Arm. **No cache sizes, line sizes, or associativity have been published** — EE Times notes Tenstorrent asked for commercially sensitive detail to be removed from coverage. Next gen is **Babylon** (18-month cadence); **Alexandria** is the automotive variant. Alastor (6d) appears to have been folded into the Ascalon H/S naming.

**Ventana Veyron V1/V2/V3** — unchanged from prior revision; see original notes. V1's **512KB combined L1+L2 i-cache with no separate levels** remains the most unusual I-side organization in the table and is worth a second look for the icache work.

**SiFive P870** [pub, chipsandcheese] — 64KB I-cache, **36B/cycle fetch** (9 instructions) into 6-wide decode. The 36B figure is a genuine oddity: not a power of two, and not a whole cache line. 8-table TAGE, 16K entries. Fusion handled broadly; no µop cache.

**Xiangshan Kunminghu** [rtl] — L1D 64KB **8-way**, L1I 64KB **4-way**, 64B lines, 512-bit (64B) L1D port, ~32B fetch. FusionDecoder present with explicit fused pairs. No macro-op cache.

### x86-64

**AMD Zen 5** [pub, AMD Hot Chips 2024 slides — the strongest single source in this table] — I-Cache **32KB 8-way with two independent 32B/cycle fetch pipes**, each feeding its own 4-wide decode cluster (one per SMT thread). Op-Cache 6K instructions, 16-way, dual-ported, 2×6-wide, up to 12 ops to the op queue. D-Cache 48KB 12-way, 4 mem ops/cycle, **4-cycle load-to-use maintained despite the 50% capacity increase**. L2 1MB 16-way, 64B/clk to L1I and L1D (doubled from Zen 4). L1/L2 BTB 16K/8K. ITLB 64/2048. **124 outstanding L1 misses** trackable, up from 24 in Zen 3/Zen 4 — a very large MSHR-equivalent budget and the number most worth noting for a non-blocking I-side design. Dual fetch pipes each maintain an independent L1i miss queue.

**Intel Lion Cove** [pub, chipsandcheese + Intel] — 64KB L1i carried over from Redwood Cove, **128B/cycle fetch**, 8-wide decode, 5250-entry µop cache emitting 12 µops/clk, 192-entry µop queue. Data side is genuinely four levels: 48KB L0 (4-cycle) → 192KB L1 (9-cycle) → 2.5MB/3MB L2 (17-cycle) → L3. Intel's renaming of L1D to L0 is contested; chipsandcheese calls the 192KB tier "L1.5". **24 L1 fill buffers, 80 L2/MLC queues.** Notably the µop cache hitrate is *lower* than Zen 5's 6K op cache despite being nominally similar in size.

**Zen 4 / Golden Cove / Redwood Cove** [rec] — recalled, not verified this session. Golden Cove L2 differs between client (1.25MB) and server (2MB); Redwood Cove's move from 32KB to 64KB L1i is the change worth noting, since it puts Intel on the same I-side capacity as Arm's server cores.

### Arm

**Neoverse V2** [pub, chipsandcheese/Hot Chips 2023] — **Arm explicitly called its 64KB L1i "small"**, which is telling given AMD and Intel were at 32KB. L1i misses tracked by a **16-entry fill buffer**, enough MLP to sustain 4 IPC running from L2. L2 is 2MB, quad-banked, each bank servicing a 64B line request every two cycles for **128B/cycle aggregate**. Renamer is claimed 8-wide but measures 6-wide sustained. L1 DTLB 48 entries fully associative; L2 TLB 2048 8-way, +5 cycles.

**Neoverse V3** [pub] — 3MB/core L2 with ECC. Other microarchitectural detail thinner than V2's.

**Cortex-X4 / X925** [pub] — both **dropped the µop cache entirely** (X3 had 1.5K entries, X1 had 3K). X925 doubles L1i bandwidth over X4 and moves to 10-wide decode/dispatch. The X-series trajectory — bigger I-cache, wider fetch, no µop cache — is the opposite of the x86 trajectory and is the more relevant precedent for a RISC-V I-side.

**Apple P-cores** [pub, Apple Silicon CPU Optimization Guide via jia.je] — **L1I is 192KiB, 6-way, 64B lines, unchanged from M1/A14 through M4/A18.** E-cores are 128KiB, 64B lines, 8-way on M1/A14 and 4-way from M2/A15 onward. Confirmed by `sysctl hw.perflevel0.l1icachesize` = 196608. Fetch is 16 instructions (one 64B line) per cycle; measured IPC saturates at 10 due to backend width. **6-way associativity at 192KB is the single most interesting datapoint in this table for VIPT work** — 192KB/6 = 32KB per way, which is 8× a 4KB page, so this cannot be a non-aliasing VIPT arrangement under 4KB pages; Apple's 16KB base page size makes it 2× and still requires alias handling. Worth chasing.
*Caveat:* L1D line size is widely reported as 128B while the optimization guide gives 64B for L1I. The discrepancy is real in the sources; do not assume both are 128B.

**Qualcomm Oryon** [rec] — recalled, not verified. 192KB L1i mirrors Apple, unsurprising given the Nuvia lineage.

### Other

**IBM POWER10 / z16** [rec] — recalled, not verified this session. Both use **very large lines** (128B on POWER, 256B on z) and z16's 32MB private per-core L2 with virtual L3/L4 is an outlier organization worth reading about but not a model for anything at pacino's scale.

---

## Observations relevant to L1I design

Extracting the parts that bear on a read-only I-cache rather than the general survey:

1. **64KB is the modern high-performance I-side consensus.** Arm (all Neoverse, all Cortex-X), SiFive P870, XuanTie C910/C930, Xiangshan, Ventana V1's L1D-side all land at 64KB. x86 sat at 32KB and Intel moved *up* to 64KB with Redwood Cove. Apple is the outlier at 192KB. A 32KB target is on the small side of current practice but is squarely in the FPGA/prototype range and matches SonicBOOM.

2. **Associativity clusters at 4-way and 8-way.** Xiangshan uses 4-way I / 8-way D — the asymmetry is deliberate and common. Apple's 6-way is the only non-power-of-two in the table. C910's 2-way is a low-end outlier and chipsandcheese is explicitly critical of C910's cache subsystem.

3. **Fetch width is decoupled from line size.** 32B fetch over 64B lines (Xiangshan, Zen 5 per pipe, Ascalon) is the common arrangement, which is exactly the 32B-prediction-block-over-64B-fetch-block shape in `ftq_ifu_interfaces.md` §3. SiFive's 36B is the only design that doesn't fetch a power-of-two.

4. **Miss parallelism budgets vary by an order of magnitude.** C910: 8 line-fill buffers. Neoverse V2: 16-entry L1i fill buffer. Lion Cove: 24 L1 fill buffers. Zen 5: 124 outstanding L1 misses. A 4-MSHR I-side is at the low end but not out of family for a first implementation — Neoverse V2 sustains 4 IPC from L2 with 16.

5. **The µop/macro-op cache is not a settled question.** Arm removed it (X3→X4, and X925 keeps it removed) while widening fetch and decode. x86 keeps it and grows it. RISC-V high-end is split: Ventana and Tenstorrent have one, Xiangshan and SiFive do not. For a RISC-V I-side with fixed-width instructions the Arm answer is the more relevant precedent.

6. **Replacement policy is rarely published.** C910 uses FIFO — notable because it is simpler than tree-PLRU and someone shipped it in a commercial core. Everything else in this table is undisclosed or presumed pseudo-LRU.

---

## Still `?`

- Ascalon cache sizes, line sizes, associativity, fusion specifics (commercially withheld).
- Akeana 5300 everything below the top-level description.
- C930 line sizes, associativity, fetch width, fusion, MOC.
- ridecore / ssrv internals; Xiangshan Yanqihu specifics.
- Veyron ROB / RF depths; V1 and V2 line sizes.
- L1D fetch bandwidth per cycle for most Arm cores (Arm publishes L2 bandwidth, rarely L1).
- FPGA-core achieved clocks across the board.
- Rows tagged **[rec]** — Zen 4, Golden Cove, Redwood Cove, Oryon, POWER10, z16 — need a verification pass.

