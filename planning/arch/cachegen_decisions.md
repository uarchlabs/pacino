<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Cache Generator Decisions
```
 FILE:    cachegen_decisions.md
 SOURCE:  session-074
 STATUS:  DRAFT
 UPDATED: 2026-10-09
 CONTACT: Jeff Nye
```

Owns the CG-N, CG-GN and CG-UN registries.

---

## 1. Scope

What pacino needs from tools/cachegen that cachegen does not
provide today, and the decisions about closing the gap. Every
pacino cache is in scope: l1i, l1d, l2 and mem. Every TOOLS task
that changes cachegen cites this document.

tools/cachegen is a git submodule of pacino, with its own
repository and its own test environment.

The cache specification is not here. It is icache_decisions.md
and l1i_ifu_interfaces.md, and they do not change to fit the
generator. pacino_cache.md is a generated snapshot of the output
tree and is not cited (PROJECT_CORE.md).

---

## 2. Approach

CG-1  Pacino drives. Its cache requirements are specified in its
      own planning documents first. What cachegen supports today
      does not constrain them.

CG-2  A TOOLS task then adds to cachegen what it needs to emit
      the pacino design. Its first step is the shortest path to a
      working pacino cache structure. Generality beyond pacino
      comes after.

CG-3  The emitted output goes under tools/regress.sh BEFORE any
      generator change (CG-G1). Features are not added to the one
      part of the tree with no automatic check.

CG-4  The pacino cache RTL may depart from what cachegen emits
      wherever the design needs it. An IA task working on a
      pacino cache may restructure it as appropriate; it is not
      held to the generator's output.

CG-5  Departures are reconciled afterwards, by two tasks in
      order: a comparison task that records every difference
      between what cachegen emits and what the design is, as
      CG-G entries here, then a gap-fixing task that closes them
      in cachegen.

Session-074, Jeff. CG-3 to CG-5 resolve handoff-074 Task 2.

---

## 3. What cachegen emits today

Figures are session-068's (TOOLS-003 to TOOLS-005), not
re-measured.

```
  config      testcases/pacino
  output      tools/cachegen/output/, seven nodes, all lint clean
  l1i         64 KiB, 8-way, 64-byte lines, 128 sets, 2 banks
              PIPT, tree-PLRU, pa_bits 36
              core port 512 bits, one line per request
              16 outstanding, out-of-order return by ID
              16 MSHRs, 4 targets each, 2 reserved for prefetch
              hit latency 2, one hit per cycle, 16 fills in flight
  l1i_pkg     L1iPaBits 36, L1iReqIdBits 4, L1iMaxOutstanding 16
  suites      cachegen unit 108 passed; l1i 67 checks
```

import/l1i/ is an older emission (32-bit address) and is not used.

---

## 4. Gaps

CG-G1 NO REGRESSION. tools/cachegen/output/ is outside every
      Makefile regress.sh finds, so nothing checks that the
      generator still emits something that builds. Close: a
      Makefile with lint and a smoke sim of the emitted l1i.
      regress.sh scans rtl/ and the output is inside the
      submodule, so where that Makefile lives is part of the
      task. The cachegen unit suite is believed to run in the
      submodule's own environment, not under regress.sh; the
      CG-5 comparison task confirms it. Handoff-074 Task 2.
      First, by CG-3.

CG-G2 NO MAINTENANCE PORTS. No node emits an invalidate port of
      any kind, so L1I-18 has no hardware. Two layers: the schema
      describes maintenance as four booleans on the node and has
      nowhere to describe a port (l1i_ifu_interfaces.md 14.2 S8),
      and no emitter emits one (14.3 E7). Schema first, then
      emitter. Required for RVA23: Zifencei and Zicbom are
      mandatory. Session-068 also routes FENCE.I to the D-side,
      so the l1d needs a port as well. TD#119; gates TD#136.

CG-G3 L2 SERIALISES MISSES. The l1i has 16 fills in flight; the
      l2's up_i slave is a four-state machine latching one
      source, so they complete one at a time. Two changes: a
      per-source record in the l2 slave adapter, and the
      pipelined control TOOLS-005 built for the l1i. cachegen
      cannot express the first: NodeCtx::nonblocking reads
      outstanding_requests off a custom link and returns false
      for TileLink, and no field says how many transactions a
      TileLink slave accepts. The performance gap: miss
      throughput is the l2's, not the l1i's, and a change to the
      l1i alone does not fix it. TD#118.

CG-G4 PIPELINE FIELDS ARE L1I ONLY. read_latency_cycles and
      tag_compare_stage shape the l1i pipeline; l1d, l2 and mem
      have none. 14.3 E5, Open Item 20.

CG-G5 REPLACEMENT TIMING. The replacement state moves in the
      compare stage, so back-to-back accesses to one set read
      the pre-update state, and two misses to one set may pick
      the same victim. Correct, lower quality. Moving it to fill
      time needs two writers of one port and an arbiter no field
      describes. TD#120.

CG-G6 NO TLB SUPPORT. The ITLB and the L2 TLB are written RTL
      (itlb_decisions.md, mmu_decisions.md). The walker needs a
      TileLink edge into the l2 (L1I-U3), a topology change the
      generated l2 must accept.

CG-G8 NO UNCACHED REQUEST. The core link has one request
      qualifier, prefetch (custom.request_qualifiers, TOOLS-004).
      icache_decisions.md L1I-24 needs a second, uncached, that
      forces a miss and suppresses allocation. Ruled session-076.

CG-G7 PACKAGE TIE. pacino declares the L1I parameters in
      bp_defines_pkg; the emitted l1i_pkg is checked equal at
      elaboration (TD#122, TD-IF-1, session-074). Generating
      l1i_pkg from pacino's parameters would remove the check.

---

## 4a. Departures under CG-4

CG-D1 BP-123 copies the emitted l1i into rtl/core/frontend/icache
      and changes it there: the maintenance ports of CG-G2 and the
      uncached bit of CG-G8. The copy is under tools/regress.sh, so
      the pacino l1i is regressed; CG-G1, the emitted output, is
      not closed by it. CG-5 compares the copy against cachegen and
      records any further difference here. Ruled session-076
      (Jeff).

---

## 5. Open

CG-U1 What CG-2's shortest path is: generator changes for the
      pacino l1i first, or the minimum gap set (CG-G1, CG-G2)
      and then the rest.

CG-U2 Order of CG-G3 to CG-G7 after the shortest path.

---

## 6. Bindings

L1I-18    Maintenance, CG-G2.
L1I-23    Sixteen fills in flight, CG-G3.
L1I-U3    The walker edge, CG-G6.
TD#118    CG-G3.
TD#119    CG-G2.
TD#120    CG-G5.
TD#122    CG-G7.
TD#136    Waits on CG-G2 in cachegen; built in the pacino RTL by
          BP-123 under CG-D1.
L1I-24    The uncached request, CG-G8.

---

## 7. Document History

```
  2026-10-09  session-076. CG-G8, the uncached request qualifier.
              Section 4a: CG-D1, BP-123 changes the pacino l1i in
              rtl/core/frontend/icache under CG-4. This document had
              no history section; its earlier changes are in
              PROJECT_STATUS.
```
