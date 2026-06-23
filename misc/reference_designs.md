<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Superscalar Out-of-Order RISC-V Machines (publicly announced)

`?` = not found / not verified. `0` = confirmed absent. L1/L2 are per-core unless noted; L3 is per-cluster.

**Core columns:** IW (issue/decode width: `Ns`=N issue ports from RTL; `Nd`=N-wide decode/dispatch published) · L1Ds/L1Is (size) · L1Dl/L1Il (line) · L1Dw/L1Iw (fetch B/cyc) · L2I/L2D (unified shown in L2I as `(unified)`, L2D=`(comb)`) · FUS (fusion) · MOC (macro/micro-op cache; `0`=absent)
**System columns:** Clk (GHz) · Cores (max) · L3 · Vec (vector bits) · Proc
**Provenance:** [rtl] read from source this session · [ds] datasheet · [pub] published vendor/press/analysis

| Name | URL | IW | L1Ds | L1Is | L1Dl | L1Il | L1Dw | L1Iw | L2I | L2D | FUS | MOC | Clk | Cores | L3 | Vec | Proc |
|------|-----|----|------|------|------|------|------|------|-----|-----|-----|-----|-----|-------|----|----|------|
| rsd | https://github.com/rsd-devel/rsd | 5 (2INT+1CPX+1MEM+1FP) | 4KB | 4KB | 8B | 8B | ? | 8B | ? | ? | N | 0 | FPGA | 1 | ? | ? | FPGA |
| riscyOO | https://github.com/csail-csg/riscy-OOO | 2d | ? | ? | ? | ? | ? | ? | ? | ? | N | 0 | FPGA | cfg | ? | ? | FPGA |
| soomRV | https://github.com/mathis-s/SoomRV | 5 (3ALU+2AGU) | 16KB | ? | 64B | ? | ? | 16B | ? | ? | Y(opt) | 0 | ? | 1 | ? | 0 | ? |
| sonicboom | https://github.com/riscv-boom/riscv-boom | 7 (3ALU+2MEM+1FP+1U) | 32KB | 32KB | 64B | 64B | 16B | 16B | ? | ? | N | 0 | cfg | cfg | SoC | cfg | cfg |
| xuantie C910 | https://github.com/XUANTIE-RV/openc910 | 3 | 64KB | 64KB | 64B | 64B | ? | ? | 1MB–8MB (unified) | (comb) | N | 0 | ~2.0 | 4/cl | 0 | 128 (RVV0.7) | cfg |
| pulp C910 | https://github.com/pulp-platform/pulp-c910 | 3 | 64KB | 64KB | 64B | 64B | ? | ? | 1MB–8MB (unified) | (comb) | N | 0 | ? | 4/cl | 0 | 128 | cfg |
| naxriscv | https://github.com/SpinalHDL/NaxRiscv | 2 (2ALU)+LSU | 16KB | 16KB | 64B | 64B | 8B | 8B | ? | ? | N | 0 | FPGA | cfg | ? | 0 | FPGA |
| Xiangshan Yanqihu | https://github.com/OpenXiangShan/XiangShan | ? | ? | ? | ? | ? | ? | ? | ? | ? | Y | 0 | ? | ? | ? | ? | 28nm |
| Xiangshan Nanhu | https://github.com/OpenXiangShan/XiangShan | 6d | 64KB | 64KB | 64B | 64B | ? | ? | 1MB (unified) | (comb) | Y | 0 | 2.0 | cfg | cfg | 128 | 14nm |
| Xiangshan Kunminghu | https://github.com/OpenXiangShan/XiangShan | 8d | 64KB | 64KB | 64B | 64B | 64B | 32B | ? | ? | Y | 0 | ? | cfg | cfg (CHI) | RVV1.0 | ? |
| toooba | https://github.com/bluespec/Toooba | 2d | ? | ? | ? | ? | ? | ? | ? | ? | N | 0 | FPGA | cfg | ? | ? | FPGA |
| ridecore | https://github.com/ridecore/ridecore | ? | ? | ? | ? | ? | ? | ? | ? | ? | N | 0 | FPGA | 1 | ? | 0 | FPGA |
| ssrv | https://github.com/risclite/SuperScalar-RISCV-CPU | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | 0 | FPGA | 1 | ? | 0 | FPGA |
| SiFive P550 | https://www.sifive.com/cores/performance-p500 | 3d | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | 4/cl | shared | 0 | cfg |
| SiFive P670 | https://www.sifive.com/cores/performance-p600 | 4d | ? | ? | ? | ? | ? | ? | ? | ? | Y | ? | ? | 4/cl | shared | 2x128 (RVV1.0) | cfg |
| SiFive P870 | https://www.sifive.com/cores/performance-p800 | 6d | ? | 64KB | ? | ? | ? | 36B | 4MB ex. (unified, non-incl) | (comb) | Y | N | >3.0 | 32 | shared | 2x128 (RVV1.0) | cfg |
| Alibaba XuanTie C930 | https://www.xrvm.com/product/xuantie/C930 | 6d | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | 32 | ? | RVV1.0 | cfg |
| Akeana 5300 | https://www.akeana.com/ | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | ~3.0 | cfg | ? | RVV1.0 | cfg |
| Tenstorrent Ascalon (X) | https://tenstorrent.com/en/ip/risc-v-cpu | 8d (6 INT/2br, 3 LS, 2 FP) | ? | ? | ? | ? | ? | 32B | cfg (shared) | (comb) | ? | Y | >2.5 | 8/cl | ? | 2x256 | Samsung SF4X |
| Tenstorrent Alastor | https://tenstorrent.com/en/ip/risc-v-cpu | 6d | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | cfg | ? | 256 | cfg |
| Ventana Veyron V1 | (site retired, Qualcomm acq.) | 8d (4 int+mem ports) | 64KB (VIVT) | 512KB (L1+L2 combined) | ? | ? | 64B | 64B | 512KB | 512KB | Y | ? | 3.6 (≤) | 192 (16/cl) | 48MB/16-core cl (3MB/core) | 0 (none) | TSMC 5nm |
| Ventana Veyron V2 | (site retired, Qualcomm acq.) | 15d | 128KB | ? | ? | ? | ? | ? | 1MB/core (unified) | (comb) | Y | Y | 3.6 | 192 (32/cl) | 128MB/cl | 512 (RVV1.0) | <5nm |
| Ventana Veyron V3 | (previewed; Qualcomm) | ? | ? | ? | ? | ? | ? | ? | ? | ? | Y | Y | 4.2 (target) | ? | ? | 512 (RVV1.0, +FP8 matrix) | ? |

## Notes by row

**Ventana Veyron V2** [pub] — 15-wide OoO, 3.6 GHz, 32 cores/chiplet to 192 cores; **1MB L2 per core** (The Register), up to **128MB shared L3/cluster**; UCIe, AMBA CHI, RVA23; silicon early 2026; <5nm (TSMC, node unspecified). **Has a macro-op cache (MOC=Y)** and aggressive macro-op fusion — Ventana states macro-ops "magnify effective decode width, backend capacity, and parallelism without physically increasing resources." Fusion mechanism patented (Favor/Ventana, now Qualcomm): fuses sequences that may begin with a control-flow op into a non-branch micro-op; the macro-op-cache patent (US12253951, US12282430) fuses across fetch blocks and filters MOC allocation by fetch-block "hotness." Adds the 512-bit RVV1.0 vector + AI matrix (24 TFLOPS/core FP8) that V1 lacked. ~40% uplift over V1. (Earlier "512KB L2I / 1MB L2D" was a misread of a launch slide; The Register's "1MB L2 per core" supersedes it. Slide also listed 128KB D-cache / 512KB I-side.)

**Ventana Veyron V3** [pub, NAND Research] — previewed next-gen design targeting **up to 4.2 GHz** and adding **FP8 data-type support to the matrix accelerator**. Trade press places release ~late 2026 / early 2027. Now under Qualcomm. Carries the V2 fusion + macro-op-cache lineage (FUS/MOC Y). Other microarch specifics not yet disclosed. (I wrongly deleted this row last revision after one search missed it; it is real and sourced.)

**Ventana Veyron V1** [pub, chipsandcheese] — 8-wide OoO, 15-cycle mispredict. Execution: only **4 combined integer+memory ports**. **12K-entry BTB** (back-to-back taken). **512KB combined L1+L2 i-cache** (no separate levels) + loop buffer; **misaligned fetch up to 64B/cycle**. **64KB VIVT L1D** (ASID-tracked), 4-cycle. Single-level **3K-entry iTLB + 3K-entry dTLB**. Split **512KB L2I / 512KB L2D**. **48MB L3/16-core cluster (3MB/core)**, ring interconnect. **No vector unit** (scalar FP only). TSMC 5nm. Fusion present.

**Tenstorrent Ascalon X** [pub, xpu.pub/MPR] — 8 decoders; execution: **6 integer ALUs (2 branch-capable), 3 load/store, 2 FP, 2× 256-bit vector**; **µop cache present (MOC=Y)**; >2.5 GHz on Samsung SF4X; RVA23; 2–8 cores/cluster, configurable shared L2; CHI.E / AXI5-LITE; >22 SPECint2006/GHz. Variants X (extreme), H, S, U. Alastor = 6-wide sibling (fusion/MOC not separately confirmed).

**SiFive P870** [pub, chipsandcheese] — 6-wide; 64KB I-cache, 36B/cycle fetch (9 instrs) to 6-wide decode; 8-table TAGE (16K entries); **handles many fusion cases, "capable of much more" (FUS=Y)**; no µop cache in the described pipeline (**MOC=N**); dual-128b vector; shared non-inclusive L2 (~4MB example, 16-cycle); up to 32 cores (8×4 clusters); ">3 GHz range". P670 is the 4-wide predecessor (dual-128b vector, fusion Y).

**[rtl] source-verified this session:** rsd, soomRV, sonicboom/LargeBOOM, naxriscv, Xiangshan Kunminghu (decode 8; L1D 64KB/8-way, L1I 64KB/4-way, 64B lines, 512-bit L1D port, ~32B fetch; **FusionDecoder present with explicit fused pairs → FUS=Y; no macro-op cache → MOC=0**), riscyOO/toooba (SupSize 2).

**[ds]:** xuantie/pulp C910 — L1I/L1D 64KB 2-way, 64B lines, unified L2 ≤8MB (1MB on TH1520), 3-issue, no fusion, no MOC, 128-bit RVV0.7.1.

**[pub] not re-verified from source:** Xiangshan Nanhu (6-wide, FusionDecoder), Yanqihu (specifics unconfirmed); SiFive P550 (3-wide); XuanTie C930 (6-wide, 16-stage, RVA23, 8–32 cores); Akeana 5300 (OoO ~3GHz).

**Still ?:** ridecore/ssrv internals; Yanqihu specifics; many commercial L1 line sizes / fetch widths / exact L2-L3 sizes; C930 & Akeana fusion/MOC; Ascalon fusion specifics and cache sizes; Veyron ROB/RF depths; FPGA-core clocks.

