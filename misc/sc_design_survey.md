<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Statistical Corrector (SC) Design Survey
```
 FILE:    sc_design_survey.md
 SOURCE:  literature + web survey (pa session 056)
 STATUS:  SCOPING
 UPDATED: 2026-06-26
 CONTACT: Jeff Nye
```

Survey to scope the SC unit (last unbuilt predictor). Not an
authority doc; feeds planning/arch/sc_decisions.md.

---

## Headline for scoping

The buildable SC references are Seznec and Xiangshan. Every
commercial core surveyed uses a TAGE-derived predictor, but none
disclose whether a discrete statistical corrector exists or how it
is built. Industry tells us THAT an SC is expected in this predictor
class, not HOW to build one. The authority for our SC is the Seznec
cookbook (RR-9561) plus his hardware-realistic CBP2025 entry;
Xiangshan is the only open SC RTL and serves as a contrast point.

---

## Table 1 -- Open / citable SC designs (build from these)

| Source | SC structure | History inputs | Combine with TAGE | HW-realism | Availability |
|--------|--------------|----------------|-------------------|------------|--------------|
| Seznec, "TAGE-SC, an engineering cookbook," Inria RR-9561, Nov 2024 | GEHL-style perceptron-like counter tables (adder-tree sum), no tags | Global, local, IMLI/backward; centered counters (2*ctr+1) | Sum of centered SC reads plus a weighted TAGE hit-bank counter; revert TAGE when SC disagrees and \|sum\| > dynamic threshold | Stated engineering reference; companion code | PDF + code, free. PRIMARY AUTHORITY. |
| Seznec, "TAGE-SC for CBP2025," SiFive (CBP2025) | "Realistic" TAGE-SC: 1-5 counter tables (6-bit counters), IMLI reengineered (brIMLI + tarIMLI) | Global + reengineered IMLI; loop predictor dropped | SC is a CORRECTOR fed by TAGE outputs (HCPRED, LongestMatchPred). SC precomputes its corrected result for all 4 (HCPRED,LongestMatchPred) combos; TAGE's actual output is the 4-to-1 mux select. Ahead-pipelined: +1 mux delay over TAGE. NOT a tournament chooser. Rule unchanged: revert TAGE on disagree when SC sum > dynamic threshold | Author intent: hardware-implementable | Paper + code, free. MOST RELEVANT to real RTL. |
| Xiangshan (Nanhu) TAGE-SC | 4 SC tables (fewer than CBP 5-table convention) | Global folded history only (no local, no IMLI) -- the deviation | SC indexed by (idx-fold XOR low bits of pc>>1); SC ctr + TAGE pred/ctr dynamically decide (HasSC) whether to invert TAGE | Synthesizable, taped out, GHz | OPEN RTL (Chisel) + design doc. Only open HW SC. |
| BOOM / SonicBOOM (Berkeley, open RISC-V Chisel) | NONE -- backing predictor is 2BC/BIM base + GShare + TAGE only; no SC, no loop, no ITTAGE in mainline BPD | Global history only (folded via CSRs) | N/A -- TAGE longest-match wins; no corrector stage | Synthesizable, taped out (production-grade open core) | OPEN RTL (Chisel). Contrast point: shows a real open core that stops at plain TAGE. NO SC to crib. |
| Seznec SC lineage (New Case for TAGE 2011; TAGE-SC-L CBP-4 2014 / CBP-5 2016) | Multi-GEHL SC; 3 confidence levels (high/med/low) | Local history, global branch history, return-associated branch history | Use TAGE vs SC by TAGE hit-bank confidence and SC sum-vs-threshold; TAGE high-conf + SC low-conf -> take TAGE | Championship-tuned; Seznec calls table/tag counts unrealistic | Papers + code, free. Foundational; cookbook is the buildable distillation. |
| CBP2025 contenders (context only) | MPSC (GEHL+MPP), RUNLTS (+register digests), PIP, Ros "Deep Dive" | Various; some add load-value / register features | All keep the CBP TAGE-SC-L skeleton, tweak SC width / bias-table size | Mostly 192 KB championship budget, not silicon | Papers + code, free. Shows which knobs matter, not a base RTL. |

Cross-cutting notes:
- PIP's only SC change was widening the SC counter 6 -> 7 bits and
  doubling bias-table size. Hint: SC counter width and bias-table
  sizing are the sensitivity knobs.
- Seznec dropped the loop predictor from his realistic CBP2025 entry
  -- adding it on top of reengineered IMLI gained only 0.003 MPKI, so
  for ACCURACY the IMLI subsumes it. BUT that is a coverage-only
  result from a CBP context that gives no credit for early prediction.
  It does NOT mean drop our loop predictor: ours is at s1 (early,
  overrides uBTB when trusted) and the SC is at s3 (corrector, latency
  >= TAGE, gated on TAGE HCPRED/LongestMatchPred). Same branch class,
  DIFFERENT timing role -- not interchangeable. See note below; do not
  import Seznec's "drop the loop predictor" conclusion as-is.
- BOOM (open RISC-V, production-grade) ships TAGE with NO SC, loop, or
  ITTAGE. Bounds the "plain TAGE" baseline. Confirms Xiangshan is the
  only open SC RTL; there is no open SC to crib from in BOOM.

---

## Table 2 -- Industry cores (the disclosure wall)

| Core | Branch predictor (public) | Discrete SC disclosed? | Use to us |
|------|---------------------------|------------------------|-----------|
| Ventana Veyron V2 (now Qualcomm, acq. 2025-12-10) | RVA23-compatible, up to 32 cores @3.85 GHz; "advanced branch prediction" marketing only | No internals published | Confirms RVA23 peers ship TAGE-class BP; nothing on SC |
| Tenstorrent Ascalon X | RVA23, 8-wide decode, ~21 SPECint2006/GHz, two branch-capable ALUs; "advanced TAGE-type" | No internals published | Closest public peer to our target (RVA23, 8-wide); SC unknown |
| AMD Zen 5 | First uarch to fully implement two-ahead branch prediction (2-taken / 2-ahead TAGE) | Detailed design not public; trade secret | Direction-of-travel signal (2-ahead), not an SC spec |
| Intel (Haswell -> Alder Lake) | Half&Half RE: set-associative TAGE PHTs, recovered index/tag functions; design stable, mainly longer histories | No SC recovered/confirmed | TAGE structure only |
| Qualcomm Oryon (Nuvia ARM lineage; NOT Veyron) | Reverse-engineered TAGE, six PHTs, set-associative | No SC recovered/confirmed | TAGE structure only; distinct from Ventana lineage |

---

## What this changes for our SC scope

1. Our already-settled SC facts (five pure-counter tables, ST4 =
   BrIMLI, ST0 hist=0, sc_upd_idx / sc_imli_idx split) match the
   Seznec/CBP lineage, NOT Xiangshan's 4-table global-only design.
   Coherent choice -> cookbook + CBP2025 realistic entry are the
   authority; Xiangshan is contrast/sanity, not template.

2. OPEN DECISION: SC datapath / override framing. Our cluster plan
   lists SC as an override at s3 (chain SC > TAGE > FTB > uBTB),
   which reads like a multi-way chooser among predictor outputs.
   Seznec's realistic datapath is different: the SC is a CORRECTOR
   whose tables are indexed partly by TAGE outputs (HCPRED,
   LongestMatchPred); it precomputes a corrected result for all 4
   (HCPRED,LongestMatchPred) combinations and a 4-to-1 mux selects on
   TAGE's actual output, so the SC stage is +1 mux of delay over TAGE
   and the SC output is final (TAGE "wins" only by SC confirming it).
   Decision to record: is our s3 SC literally the last mux on TAGE's
   output (Seznec), or a separate override box? These differ in the
   datapath, the critical path, and what must be checkpointed.
   NOTE: an earlier draft of this survey mischaracterized this as
   "TAGE and SC in parallel, mux picks the winner" -- that is a
   tournament reading and is WRONG; the SC consumes TAGE's output and
   reverts-on-disagree-above-threshold. Corrected per RR-9561 /
   CBP2025 paper.

3. Loop predictor: coverage overlap, NOT timing overlap. IMLI and
   the loop predictor target the same branch class (constant-iteration
   loops, loop exits), and Seznec shows IMLI covers most of that
   ACCURACY. But our loop predictor is at s1 (early; can redirect the
   front-end and kill the bubble); the SC/IMLI is at s3 and cannot
   respond before TAGE (the SC mux is gated on TAGE's HCPRED/
   LongestMatchPred, so SC latency >= TAGE latency). Different timing
   role -> not redundant. Note the IMLI counter is cheap/early but its
   PREDICTION is spent late inside the SC adder tree; getting IMLI's
   loop coverage early would mean architecting it outside the SC,
   which Seznec never needed (CBP gives no credit for early redirect).
   The real question runs OPPOSITE to Seznec's: keep the s1 loop
   predictor for timing, then decide whether the SC's IMLI tables
   still earn their area GIVEN an upstream loop predictor already
   catches most loop branches before s3.

---

## Open SC parameters to resolve in sc_decisions.md (from survey)

- G7 SC threshold value (dynamic threshold algorithm -- verify
  against RR-9561, do not recall).
- SC counter width (PIP signal: 6 vs 7 bits is a real knob; Seznec
  realistic uses 6-bit throughout).
- Bias-table sizing.
- Table count: 5 (our current assumption; Seznec realistic is 1-5,
  so 5 is the top of his realistic range) vs 4 (Xiangshan). Confirm 5.
- SC datapath: corrector ahead-pipelined on TAGE output (+1 mux,
  Seznec) vs a separate s3 override box. Resolve the s3 framing.
- SC table indexing: which use PC only, which use TAGE outputs
  (HCPRED/LongestMatchPred), which use global history, which use
  IMLI counters. Drives whether SC can be read before TAGE resolves.
- Dynamic threshold algorithm (O-GEHL style; update gated to when
  SC sum > half threshold) -- verify against RR-9561, do not recall.
- SC/IMLI vs loop predictor: NOT a redundancy/drop question. Keep the
  s1 loop predictor for its early-redirect timing role (SC at s3
  cannot match it). Open: do the SC IMLI tables still earn their area
  given an upstream s1 loop predictor already catches most loop
  branches before s3?

## Primary sources (fetch before specifying)

- RR-9561 cookbook: https://hal.science/hal-04804900
  (PDF: https://files.inria.fr/pacap/seznec/TageCookBook/RR-9561.pdf)
- Seznec CBP2025 TAGE-SC paper (ericrotenberg.wordpress.ncsu.edu
  cbp2025 final37-Seznec.pdf)
- Xiangshan TAGE-SC design doc (docs.xiangshan.cc, frontend/BPU)
- CBP2025 framework + traces: github.com/ramisheikh/cbp2025

