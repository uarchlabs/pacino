---
title: "TAGE -- Architecture and the Decomposition Problem"
author: Jeff Nye
date: 2026-04-22
copyright: "Copyright 2026 Jeff Nye"
---

*This is part 5 of a series on branch predictor co-design.
[Part 1: Cluster Architecture](BLOG_bpu_1_cluster_arch.md) |
[Part 2: History and uBTB](BLOG_bpu_2_history_ubtb.md) |
[Part 3: Loop Predictor](BLOG_bpu_3_loop_pred.md) |
[Part 4: When the Tools Fail](BLOG_bpu_4_limits.md) |
[Part 5: TAGE -- Architecture and the Decomposition Problem](BLOG_bpu_5_tage_arch.md)*

---

## A Different Kind of Failure

The previous post documented what happens when the generation tooling reaches
its ceiling on a task that is not especially large by hardware design standards.
The loop predictor testbench hit a generation timeout on 380 lines of output.
The fix was to split the task and run again with reduced scope.

The TAGE sessions introduced a different class of problem. Not a tooling limit
but an architectural one: a module decomposition that was logically clear but
not expressible in SystemVerilog (SV). The failure came after the first
implementation attempt, before any generation limits were reached. The recovery
required rethinking the module boundary, writing a complete interface
specification, and starting over.

This post covers the first six TAGE sessions: the infrastructure work, the
architectural design decisions made before any RTL was written, the first
implementation attempt, and the failure and recovery that established a
different way of approaching module boundaries for the rest of the project.

---

## TAGE Pipeline Summary

The Tagged GEometric history length predictor (TAGE) is a well known branch predictor architecture [1]. For this RVA23 (RISC-V Architecture profile) implementation, the TAGE predictor has five tables:

- T0: base table (aka BIM)
    - 2048 entries, saturating counter, CTR(2b), no tag, no useful bit
- T1-T4: tagged tables
    - 2048 entries each, entry layout of tag(8b)+ CTR(3b) + useful(2b) + valid(1b)
    - *Note: in this iteration the epoch bits, EPC(2b), were overlooked by the user, they are subsequently added.*

The prediction pipeline runs 2-3 stages. p0 computes index and tag hashes. p0 does not utilize the entire clock cycle, only the hash operations from the prediction PC consume p0. p1 reads the SRAMs and performs tag comparison. p2 registers the output.
Provider selection scans T4 down to T1 for a tag hit; T0 is the unconditional
fallback when no tagged table hits. TAGE sits between the Fetch Target Buffer
(FTB) and the Statistical Corrector (SC) in the override chain: SC overrides
TAGE, TAGE overrides FTB.

This TAGE implementation supports dual prediction and can deliver two predictions per cycle. In standard terms TAGE operates with latency of 2 cycles and throughput of 1 cycle per prediction pair.

---

## Before the RTL: Data Structures and Component Library

Two sessions of infrastructure work preceded any TAGE RTL.

The first session, BP-005, added the TAGE type definitions to the project
packages. Three structs went into bp_structs_pkg.sv: tage_pred_inp_t (the
prediction request), tage_pred_meta_t (the prediction metadata captured for
post-execute update), and tage_upd_inp_t (the update request, which embeds
tage_pred_meta_t as a sub-struct). A companion interface specification,
tage_interfaces.md, was created to document port timing contracts, the update
policy, and a set of open design items labeled TI1 through TI8 -- things
known to require decisions before RTL could be written.

The second session produced three parameterized library primitives and a combined testbench via COMP-001. The PA authored the prompt with binding constraints -- no initial blocks, active-low suffix convention, array uninitialized at simulation start -- and the IA generated all deliverables: bw_ram.sv (synchronous bit-write RAM), sat_alu.sv (saturating arithmetic, used for CTR updates), and dual_lm1.sv (dual leftmost-1 finder, used for provider and alternate-provider selection), together with tb_components.sv reaching 21 passing test cases. Two follow-on experiments in the same session added sram_init.sv (COMP-003, power-on SRAM initialization required for simulation correctness) and refactored dual_lm1 to eliminate for loops (COMP-002), bringing the combined testbench to 34 passing test cases.

This session also changed the prompt file block marker format from HTML comment
style to a :: MARKER :: convention throughout the project. The HTML style syntax created issues in IA output.

This session also established a context minimization discipline, recorded in the project handoff as: only load context files that Claude Code actually needs for the specific task.

---

## Settling the Architecture Before Writing Code

Before the first implementation prompt could be written, five architectural questions in tage_interfaces.md remained open. BP-005 had settled the table geometry, the three-stage pipeline, the provider selection policy, the post-execute update policy, and the port names and struct layouts. What it had not settled was how the RAMs were banked, how the alternate-provider selection mechanism would be specified, whether path history would contribute to hashing, how T0 would be structured, and what the allocation scan order would be. A design session worked through all five before any RTL prompt was authored.

The bank selection question (TI6) turned out to be a terminology problem. The interface document described T1-T4 as "2-bank x 2048 entry" tables, suggesting some form of address-based bank selection at prediction time. The actual intent was different: the two "banks" are two independent RAMs, one per prediction slot. Slot 0 reads RAM0, slot 1 reads RAM1. No runtime bank selection mux is needed. The selection is structural -- slot index is the RAM select at elaboration time. This also clarified that bw_ram's internal BANKS parameter is an unrelated concept.

The USE_ALT_ON_NA (UAON) counter (TI2) was deferred to a 4-bit saturating counter stub with a threshold of 8 (TAGE_UAON_THRES). UAON is a Seznec mechanism that tracks whether using the alternate provider produces better predictions when the primary provider's counter is at a weak state. The detailed update rules were left for a later planning document.

PHR (Path History Register) contribution to index and tag hashing (TI1) was deferred. All hashing in the initial implementation uses the Global History Register (GHR) only.

T0 structure was confirmed as direct-mapped using two bw_ram instances, one per prediction slot, consistent with the TI6 resolution.

Allocation priority on misprediction was settled as a lowest-index-first scan: search T(provider+1) through T4 for an entry with useful equal to zero, selecting the shortest qualifying table. One entry is allocated per misprediction. An additional constraint was added: no allocation in consecutive tables -- if table Tj is selected, Tj+1 is skipped even if its useful bit is also zero.

With these decisions recorded, the project moved to implementation.

---

## The First Implementation Attempt

The first implementation attempt planned four modules: tage_hash.sv (combinational index and tag hash computation), tage_table.sv (parameterized table storage wrapper, instantiated five times via a generate loop in tage.sv), tage_cntrl.sv (all prediction control logic and update path), and tage.sv (top-level integration).

BP-006, the hash module, was written and passed. The T0 index is a direct PC slice (pc[12:2]). T1-T4 index hashes are pc[12:2] XOR a table-specific folded history field, zero-extended to 11 bits. T1-T4 tag hashes are an 8-bit truncation of pc[12:2] XOR two independent folded history fields, which reduces tag aliasing between tables using the same PC.

BP-007, BP-008, and BP-009 were drafted but not run. The remaining three prompts -- tage_table.sv, tage_cntrl.sv, and tage.sv -- were reviewed before being handed to the IA. That review found the decomposition unsound in two respects that could not be worked around.

---

## What Broke

The first problem was a missed SV syntax constraint. The planned tage_cntrl module
called for vectored ports connecting to each of the five tage_table instances
-- one set of prediction outputs and one set of update inputs per table. This
is a natural way to structure a control module managing multiple storage
instances, but SV does not support parameterized port counts. A module cannot
declare ports whose number depends on a parameter. The planned tage_cntrl port
list was not legal SV.

The second problem was the T0 and T1-T4 entry geometry mismatch. A
parameterized tage_table module would need to serve both T0 (2 bits: CTR only)
and T1-T4 (14 bits: valid + tag + CTR + useful). A packed array approach to
unify these two geometries was examined and rejected. T0 has no valid bit, no
tag, and no useful field; the entries are not just different widths but
structurally different. A uniform representation cannot serve both without
either wasting bits in the T0 case or requiring T0-aware unpacking logic at
every consumer, which defeats the encapsulation purpose of a parameterized
wrapper.

The session handoff recorded both problems and deferred to the next session to
find a workable boundary.

---

## The Recovery

The recovery required answering two questions: where should the module boundary sit, and how should the T0 geometry difference be handled at the interface level.
On the module boundary: tage_cntrl needs to communicate with each table instance but cannot have parameterized ports. The workable solution is to let tage.sv be the fan-out layer. tage_cntrl operates on decoded, flattened signals. tage.sv instantiates the tables and routes between them and tage_cntrl at a fixed width. The parameterized generate loop lives in tage.sv, not in a module that would need a port for each loop iteration.

On the T0 geometry: the decision at this stage was to handle it through HAS_TAG and HAS_USEFUL parameters on tage_table, with T0 instantiated with both set to zero. The full separation of T0 into its own dedicated module (tage_bim.sv) came later, when implementation revealed that generate logic for zero-width fields was not workable in practice.

Before writing the new BP-007 prompt, a planning document was produced: tage_table_interfaces.md. It specified the module boundary precisely -- the parameter set, port list with pipe stage annotations, entry layouts for both geometries, and read and write path timing contracts. Writing this document before authoring the prompt was a direct response to the decomposition failure. The earlier draft had conceived the interface in terms of logical function without checking what SV required at the boundary. The interface document forced that question first.

BP-007a implemented tage_table.sv against the new specification. It passed 10 of 10 test cases on the first run, lint clean with zero warnings. Tag comparison, hit generation, CTR and useful field extraction, and one-cycle update write behavior were all correct across both T0 and T1-T4 geometries.

---

## The Audit Session

A documentation audit cross-checked the project state documents, the current handoff, and all five interface documents against each other. Several inconsistencies were found and six corrected in session.

In an effort to reconcile the differences the user pasted four documents
PROJECT_STATE.md, PROJECT_STATUS.md, the session handoff and CLAUDE.md and the PA to perform a consistency check. The project files were merged into PROJECT_STATUS.md. There was a gap in the bp_defines.pkg for parameters, this was aligned manually. 

This audit session produced one structural document and resolved accumulated inconsistencies between the planning files. The merge of PROJECT_STATE.md and PROJECT_STATUS.md into a single file eliminated a synchronization problem that had caused the label drift in the first place. bp_cluster.md was unlocked and stripped of its standalone Known Gaps table, with open item tracking consolidated into PROJECT_STATUS.md.

This reconciliation was directed towards consistency towards the upcoming bulk of the TAGE design.

---

## Experiment Summary

| Experiment | Description                          | Status    | Checks | Runtime | Context |
|------------|--------------------------------------|-----------|--------|---------|---------|
| BP-005     | TAGE data structures, packages       | PASS      | --     | 3m.12s  | 25%     |
| COMP-001   | bw_ram, sat_alu, dual_lm1, sram_init | PASS      | 34/34  | 11m.59s | 41%     |
| BP-006     | tage_hash.sv                         | PASS      | --     | 17m.34s | 61%     |
| BP-007     | tage_table.sv -- first attempt       | Abandoned | --     | --      | --      |
| BP-008     | tage_cntrl.sv -- first attempt       | Abandoned | --     | --      | --      |
| BP-009     | tage.sv -- first attempt             | Abandoned | --     | --      | --      |
| BP-007a    | tage_table.sv -- second attempt      | PASS      | 10/10  | 27m.36s | 85%     |

---

## What Comes Next

The recovery in Part 15 left tage_table.sv working and tage_hash.sv (BP-006)
confirmed correct. tage_cntrl.sv, the most complex module in the TAGE design,
had not been started. tage.sv had not been started.

Before tage_cntrl could be prompted, the Seznec-style control logic needed
enough specification that a generation session could implement it without making
architectural decisions mid-run. That specification work -- prediction phase
responsibilities, the CTR update rules, the useful bit update rules, the
allocation rules, and the UAON update policy -- is the subject of the next
post.

---

## Design Process Notes

### What the sessions exposed about the methodology

The decomposition failure in Part 14 is the clearest example from the project
of a problem that has nothing to do with generation limits. The session set out
to produce the full TAGE predictor in one pass, with four modules planned before
any were implemented. The approach had worked for simpler predictors -- uBTB and
the loop predictor were each implemented in a single session with a single
decomposition -- but TAGE's structural complexity made the implicit assumptions
fail.

The failure came from designing the module boundary in terms of logical function
without checking whether that function was expressible in SV. The tage_cntrl
port list was conceived as "one set of signals per table" without verifying that
parameterized port counts are legal in SV. They are not.

Writing tage_table_interfaces.md before BP-007a was the direct response. The
interface document forced the question of what the boundary requires at the
language level before a prompt was authored. For modules above a certain
structural complexity, the interface specification is not a convenience -- it
is a prerequisite. The loop predictor was simple enough that the interface could
be implied from the module description. TAGE was not. The pattern established
here carried forward through the remaining TAGE sessions.

### What the PA contributed

The PA conducted the architecture Q&A in Part 13, working through the five open
design questions in tage_interfaces.md against the project planning documents.
The TI6 resolution -- banks are per-slot RAMs, not address-banked -- came from
that exchange. The PA wrote tage_table_interfaces.md in Part 15 based on the
recovery discussion, authored the BP-007a prompt, and conducted the
documentation audit in Part 16.

### What the IA contributed

The IA implemented tage_hash.sv in BP-006, correctly deriving the T0
direct-index path and the T1-T4 XOR-based index and tag hashes without
producing lint warnings. BP-007a implemented tage_table.sv against the new
interface specification, passing 10 of 10 test cases on the first run with
correct tag comparison, hit generation, and one-cycle update behavior.

### The generalization

The cost of the Part 14 failure was approximately one session: the time to
draft three unsound prompts, recognize the problem, and produce the recovery
design. That cost was paid once. The interface-first pattern it produced was
applied to every subsequent module boundary in the TAGE implementation and is
the main process contribution of these six sessions.

---

# References

[1] A. Seznec and P. Michaud, "A Case for (Partially) TAgged GEometric History Length Branch Prediction," Journal of Instruction Level Parallelism, vol. 8, Feb. 2006.

