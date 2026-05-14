---
title: "TAGE -- Implementation"
author: Jeff Nye
date: 2026-04-22
copyright: "Copyright 2026 Jeff Nye"
---

*This is part 6 of a series on branch predictor co-design.
[Part 1: Cluster Architecture](BLOG_bpu_1_cluster_arch.md) |
[Part 2: History and uBTB](BLOG_bpu_2_history_ubtb.md) |
[Part 3: Loop Predictor](BLOG_bpu_3_loop_pred.md) |
[Part 4: When the Tools Fail](BLOG_bpu_4_limits.md) |
[Part 5: TAGE -- Architecture and the Decomposition Problem](BLOG_bpu_5_tage_arch.md) |
[Part 6: TAGE -- Implementation](BLOG_bpu_6_tage_impl.md)*

---

## Where Things Stood

The previous post ended with tage_table.sv working and two modules
unwritten: tage_cntrl.sv and tage.sv. The interface-first discipline
established during the decomposition recovery had produced a clean
tage_table boundary. The same discipline now had to be applied to
tage_cntrl -- the most complex module in the TAGE design -- before
any prompt was authored.

This post covers the five sessions that took TAGE from a working
storage layer to a complete, lint-clean RTL implementation. The
path was not linear. A structural decision made early in the
tage_cntrl design invalidated a completed module midway through,
and the compile-only strategy adopted for intermediate deliverables
proved its value by containing that cost.

---

## Requirements Before RTL

The tage_cntrl module owns the provider selection logic, the
alternate-provider selection logic, the USE_ALT_ON_NA (UAON)
mechanism, the CTR update rules, the useful bit update rules, and
the allocation path. Writing a prompt for this module without a
complete specification of each of those mechanisms would have
reproduced the failure from the first decomposition attempt.

A design session produced four planning documents before any prompt
was written:

- tage_cntrl_decisions.md -- architectural decisions: T0 behavior,
  CTR encoding, UAON counter width and threshold, allocation
  sentinel, concurrent write handling, and aging policy
- tage_cntrl_ctr_update_rules.md -- a full truth table for CTR
  update behavior across all provider/outcome combinations
- tage_cntrl_useful_update_rules.md -- useful bit update rules
  by case
- tage_cntrl_alloc_rules.md -- allocation scan order, guard
  conditions, and write path

The most consequential decision captured in tage_cntrl_decisions.md
was T0 behavior: tage_cntrl treats T0 as always-hit. T0 has no valid
bit, no tag, and no useful field. It is never the alternate provider.
Its CTR is 2b, initializes to 2'b10, and is updated by a dedicated
path that does not touch the T1-T4 logic.

The same session removed the struct typedef blocks from
tage_interfaces.md. The interface document had been carrying
full SystemVerilog struct definitions alongside the semantic
descriptions. These were replaced with references to
bp_structs_pkg.sv, which is the authoritative location. The
interface document retains its value as a timing and semantic
reference; the struct layouts live in exactly one place.

---

## tage_cntrl: Shell and Prediction Logic

BP-008a was decomposed into two prompts before either was run.
BP-008a-1 produced the module shell: ports, signal declarations,
pipeline registers, and reset logic. No prediction logic. BP-008a-2
added the prediction logic to that shell: provider selection,
alternate-provider selection, UAON counter, UAON mux,
tage_pred_strong computation, and tage_pred_meta population.
Both passed lint clean on the first run.

The decomposition was a direct application of the generation
ceiling lesson from the loop predictor sessions. A single prompt
for the full tage_cntrl prediction path would have been large.
Splitting at the shell boundary kept each generation task within
a size that had proven reliable.

One defect was found in BP-008a-2 and recorded as technical debt
rather than fixed in place: the UAON counter had been implemented
as a predict-time flip-flop update rather than an update-time
operation. This was architecturally wrong -- UAON is updated
post-execute, not at prediction time -- but it did not affect
lint correctness. It was flagged for correction in BP-008b.

The compile-only strategy also surfaced a second issue during
review: tage_cntrl had been given its own index and tag hash
logic, reproducing computation that tage_table already performed
internally via its embedded hash functions. This was not a lint
error but a structural redundancy that would have produced
incorrect behavior at integration time.

---

## The Hash Logic Migration

The hash redundancy problem required three sequential experiments
before BP-008b could proceed.

BP-007d added two missing allocation ports to tage_table.sv --
alc_tbl_sel_u0 and alc_index_u0 -- that had been omitted from
the original BP-007a implementation. These were needed by the
update path tage_cntrl was about to implement. Lint clean, no
functional change.

BP-007e removed the hash logic from tage_cntrl entirely.
The fld_hist_p0 input port, the index and tag output ports, and
all associated combinational logic were deleted. tage_cntrl
became a pure control module: it receives pre-computed hit,
taken, and cntrl_bits from the tables, and drives write-enable
and write-data signals back.

BP-007f embedded the hash functions directly in tage_table.sv.
Each table instance now computes its own index and tag hashes
using its own history length parameters. The fld_hist_p0 input
was added to the tage_table port list. The table-specific
history field widths -- FH, FH1, FH2 -- are module parameters,
so the hash computation is naturally parameterized without
requiring a separate tage_hash module.

This made tage_hash.sv redundant. The module remained on disk
but was no longer instantiated in the design. Its formal
deletion came in a later cleanup session.

The three-experiment sequence had a clear cause: the original
decomposition had assigned hash computation to tage_hash as a
standalone module, then migrated it to tage_cntrl during the
recovery in the previous session, and now moved it again to
tage_table where it belongs architecturally. Each move was
correct given what was known at the time it was made. The final
placement -- hash logic local to the table that consumes it --
is the cleanest boundary and the one that eliminates cross-module
hash signal routing entirely.

---

## tage_cntrl: Update Logic

BP-008b added the update logic to the tage_cntrl shell. The four
planning documents -- decisions, CTR rules, useful rules,
allocation rules -- were loaded as context alongside the current
tage_cntrl.sv. The UAON flip-flop defect from BP-008a-2 was
corrected: UAON is now updated in the update path, not at
prediction time. The T0 CTR path was gated on tage_prm_comp==0
to distinguish T0 updates from T1-T4 updates without requiring
T0-aware logic in the shared CTR update block.

BP-008b passed lint clean. The update-side output ports, which
had been held at zero since BP-008a-1, were now driven with
correct logic.

---

## tage.sv and the T0 Split

BP-009 produced tage.sv, the top-level integration module. Its
responsibilities are purely structural: instantiate tage_cntrl,
instantiate T1-T4 via a generate loop over tage_table, instantiate
T0, instantiate sram_init, and route signals between them.

The T0 instantiation question, which had been deferred since the
decomposition recovery, was resolved here. The original plan was
to instantiate T0 as a tage_table with HAS_TAG=0 and HAS_USEFUL=0.
Implementation revealed that the generate logic for zero-width
fields inside tage_table produced unresolvable lint warnings under
Verilator 5.020. A zero-width packed array is not legal SV in the
contexts where it appeared.

The solution was to introduce tage_bim.sv as a dedicated T0
module. tage_bim implements exactly what T0 requires: two bw_ram
instances (one per prediction slot), a 2b CTR per entry, no tag,
no valid, no useful. It has no generate logic and no conditional
field widths. BP-009a produced tage_bim.sv and updated tage.sv
to instantiate it in place of the T0 tage_table instance.

sram_init was instantiated once in tage.sv, shared across all
tables. The tbl_ri_* signals are broadcast from the single
sram_init instance to all table instances. No external tbl_ri_*
ports are exposed on tage.sv.

---

## Integration Fixes and Testbench Startup

BP-009a passed lint but two structural problems were found during
review. The first was a bank_addr connection error on one of the
tage_bim RAM instances. BP-009a-1 corrected the wiring and passed.
BP-009b regenerated tage.sv against the corrected specification
and passed.

BP-010a and BP-010b produced the initial testbench infrastructure.
The primary goal at this stage was not test cases but path probe
verification: confirming that the Verilator simulation hierarchy
resolved correctly so that subsequent test cases could access
internal state. The path probe confirmed:

- u_tage_bim as the T0 instance name in tage.sv
- gen_tage_tbl[t].u_tage_tbl as the generate block label and
  instance name for T1-T4
- u_ram_s0 and u_ram_s1 as the bw_ram instance names inside
  both tage_bim and tage_table
- mem as the internal array name in bw_ram

A tage_rdy output was added to tage.sv during this session to
signal when the SRAM initialization cycle was complete and
predictions could be trusted. The port had been absent from
earlier drafts and was identified as needed when the testbench
reset sequence was designed.

Both BP-010a and BP-010b passed. The testbench infrastructure
was in place for the test case development that would follow in
subsequent sessions.

---

## Experiment Summary

| Experiment  | Description                           | Status | Checks | Runtime  | Context |
|-------------|---------------------------------------|--------|--------|----------|---------|
| BP-008a-1   | tage_cntrl.sv shell                   | PASS   | --     | 29m 25s  | 72%     |
| BP-008a-2   | tage_cntrl.sv prediction logic        | PASS   | --     | 35m 5s   | 69%     |
| BP-007d     | tage_table.sv alc ports added         | PASS   | 10/10  | 7m       | 43%     |
| BP-007e     | Hash logic removed from tage_cntrl    | PASS   | --     | 5m 57s   | 40%     |
| BP-007f     | Hash logic embedded in tage_table     | PASS   | 12/12  | 32m 48s  | 73%     |
| BP-008b     | tage_cntrl.sv update logic            | PASS   | --     | 32m 24s  | 67%     |
| BP-009      | tage.sv top level (lint)              | PASS   | --     | 34m 51s  | 79%     |
| BP-009a     | tage_bim.sv, tage.sv T0 split         | PASS   | --     | 11m 58s  | 56%     |
| BP-009a-1   | bank_addr fix, TBL_SEL_WIDTH, din_mux | PASS   | 12/12  | 6m 29s   | 40%     |
| BP-009b     | tage.sv regenerated                   | PASS   | --     | 19m 32s  | 83%     |
| BP-010a     | Testbench startup, path probe         | PASS   | 1/1    | 20m 21s  | --      |
| BP-010b     | Testbench reset and sram_init sequence| PASS   | 2/2    | 7m 34s   | 46%     |

---

## What Comes Next

The testbench infrastructure at the end of these sessions was
structural: reset, initialization, and hierarchy path confirmation.
No branch prediction behavior had been tested. The update path had
not been exercised. The provider selection logic, the useful bit
mechanics, the allocation scan, and the UAON threshold behavior
were all untested.

The next sessions developed the test cases that exercised each of
these behaviors, found and fixed several RTL defects in the
process, and produced a complete validation suite for the TAGE
predictor.

---

## Design Process Notes

### What the sessions exposed about the methodology

The compile-only strategy -- lint clean only, no testbench, for
each intermediate deliverable -- proved its value during the hash
logic migration. When the structural redundancy between tage_cntrl
and tage_table was identified after BP-008a-2, the cost of
correcting it was three focused experiments rather than a large
debug session against a partially working system. The redundancy
was caught at review, not at simulation. The strategy of keeping
each generation task small and verifiable independently is what
made that possible.

The tage_bim split tells a different story. The T0 geometry
problem -- a degenerate table that cannot share the same
parameterized wrapper as T1-T4 -- had been visible since the
original decomposition failure. The decision at the recovery was
to defer it using HAS_TAG and HAS_USEFUL parameters. That deferral
held through tage_table implementation and tage_cntrl design,
but collapsed at tage.sv integration when Verilator rejected
zero-width packed arrays. The cost of the deferral was one
unplanned module and a regeneration of tage.sv. The alternative
-- resolving T0 geometry at the interface design stage -- would
have been cheaper. The pattern from the Part 14 failure applies
here too: structural problems deferred past the interface design
stage eventually surface as implementation surprises.

### What the PA contributed

The PA produced the four tage_cntrl planning documents in the
requirements session, authored all prompts for BP-008a through
BP-010b, and identified the hash logic redundancy during review
of the BP-008a-2 result. The tage_bim.sv introduction was a PA
decision made at the point where the HAS_TAG/HAS_USEFUL deferral
was found to be unworkable.

### What the IA contributed

The IA produced tage_cntrl.sv in two passes (shell and prediction
logic), correctly implementing provider selection, UAON counter,
alternate-provider selection, and tage_pred_meta population
against the planning documents. BP-007d through BP-007f executed
the hash migration cleanly. BP-008b added update logic with the
UAON defect corrected. BP-009a produced tage_bim.sv on the first
attempt against the new specification.

### The generalization

The five sessions described in this post produced a complete,
lint-clean TAGE RTL implementation across seven modules. The
planning document investment before BP-008a -- four documents
covering CTR rules, useful rules, allocation rules, and
architectural decisions -- directly enabled the IA to implement
a module of this complexity without architectural decisions being
made during generation. That investment was not a one-time cost:
the same documents were reloaded as context for BP-008b, and the
allocation rules document was referenced again during testbench
development in subsequent sessions.

---

*No references required for this post.*

