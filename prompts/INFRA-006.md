=============================================================
# Task Header 
=============================================================
:: HEADER:START ::
| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | INFRA-006               |                          |
| Date         | 2026.04.24              |                          |
| Module       | tage_table.sv           |                          |
| Run time     | 7m.2s                   |                          |
| Ctx %        | 34%                     |                          |
| Model        | Sonnet 4.6 medium       |                          |
| Resume sha   | 1f15c7dc-166a-46ea-a1fb-7c8d2c849aab |             |
Task:   [ ] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [x] verification
Status: [ ] in-progress [x] complete        [ ] abandoned
# Overview of task
# Re-run verilator_coverage --annotate on current cov_tage
# coverage data. Read annotated tage_table.sv only.
# Produce a gap report scoped to tage_table with raw gaps
# and coverage plan mapping. Baseline is now 76.0%.
:: HEADER:END ::
=============================================================
# Paste c.code console output and c.ai discussion
=============================================================
:: DISCUSSION:START ::
# Results Discussion 
## Claude.code Console Output

  INFRA-006 Complete
                                                                                
  18 gap regions found in tage_table.sv across 4 categories:
                                                                                
  ┌────────────────────────────┬────────────────┬──────────────────────────┐    
  │          Category          │      Gaps      │          Status          │ 
  ├────────────────────────────┼────────────────┼──────────────────────────┤    
  │ CP-10 (fh_sel              │ G01–G04        │ OPEN confirmed           │ 
  │ T1/T2/T3/default)          │                │                          │ 
  ├────────────────────────────┼────────────────┼──────────────────────────┤ 
  │ CU-11 (slot 1 write paths) │ G10, G12–G18   │ OPEN confirmed, scope    │    
  │                            │                │ expanded                 │ 
  ├────────────────────────────┼────────────────┼──────────────────────────┤    
  │ CE-10 (allocation path     │ G06, G07, G09, │ OPEN confirmed           │
  │ s0+s1)                     │  G11           │                          │    
  ├────────────────────────────┼────────────────┼──────────────────────────┤
  │ CE-11 (alt-CTR din, slot   │ G08            │ OPEN confirmed           │    
  │ 0)                         │                │                          │
  ├────────────────────────────┼────────────────┼──────────────────────────┤
  │ New: TAGE_FAST_INIT path   │ G05            │ No plan row exists       │
  └────────────────────────────┴────────────────┴──────────────────────────┘    
  
  Key new finding (G10): norm_we_s1 was reached 335 times in addr_mux_s1 but its
   body (line 412) has count 0. This reveals the CU-11 root cause more precisely
   than INFRA-005: slot 1 update-valid with a matching table selector was never 
  asserted in any test, not just "not reaching the RAM write." The we_s1 logic
  block itself ran once (initialization), but all output enables were false
  throughout the test.

  Hypothesis result: Confirmed. The 24% gap is dominated by CU-11 slot 1 paths  
  (10 regions) and CP-10 fh_sel cases (4 regions).

※ recap: Running coverage gap analysis on tage_table.sv for INFRA-006. The      
  analysis is complete — 18 gap regions were found and documented in 
  prompts/INFRA-006.md. No further action needed unless you want to start       
  closure work. (disable recaps in /config)  

## My Assessment

TBD

Also PA predicted 5m runtime, very close the actual 7m run time.

## Claude.ai Assessment

## Follow-on Actions
Once coverage work has completed investigate mutation testing, work with PA
on establishing a routine for measuring unit testbench quality and 
completeness

## CLAUDE.md Updates
TBD as needed document here
## Other Planning File Updates
TBD as needed document here
:: DISCUSSION:END ::
=============================================================
# Claude.code Prompt 
=============================================================
:: PROMPT:START ::
## Task ID
INFRA-006

## Context Loaded
@planning/verification/tage_coverage_plan.md
@rtl/core/frontend/bpu/rtl/tage_table.sv

## Hypothesis
The remaining 24% gap in tage_table.sv (baseline 76.0%
after BP-024 diagnosis and current testbench re-run) is
concentrated in the slot 1 write paths (CU-11 conflict)
and the T1-T3 folded history select cases (CP-10 gap).
Reading the annotated tage_table.sv from the current
cov_tage run will confirm or refute this and identify
any additional uncovered regions.

## Background
INFRA-005 identified tage_table.sv as the weakest module
at 75.5%. After BP-024 confirmed the INFRA-005 baseline
was stale (cov_tage was run before TC-42/TC-43 were
integrated), a fresh cov_tage run shows tage_table at
76.0% -- marginal improvement, still below the 90%
target.

Known open items from INFRA-005 and tage_coverage_plan.md:
  CP-10: T1/T2/T3 fh_sel cases 1-3/default (gap)
  CU-11: Slot 1 tage_table RAM writes (conflict --
         plan marked covered but annotation showed
         zero counts in INFRA-005 baseline)

tage_table.sv is a parameterized module instantiated
four times (T1-T4) inside tage.sv. The cov_tage target
covers it via the top-level tb_tage.sv testbench.
Coverage data is in:
  rtl/core/frontend/bpu/coverage/tage/coverage.dat

## Binding Previous Decisions
- Do not modify any RTL or testbench .sv files.
- Do not modify any Makefile targets.
- Do not modify tage_coverage_plan.md.
- Console output only. No file writes except the
  annotated/ build artifact.
- cov_tage coverage.dat is the authoritative source.
  Do not run a separate tage_table coverage target.

## Specific Requirements

### Step 1 -- Verify coverage data is current

Check the timestamp of:
  rtl/core/frontend/bpu/coverage/tage/coverage.dat

If it is older than the current tb_tage.sv, re-run:
  cd rtl/core/frontend/bpu && make cov_tage

Then confirm the file timestamp is newer than tb_tage.sv
before proceeding.

### Step 2 -- Run verilator_coverage --annotate

Run:
  cd rtl/core/frontend/bpu && \
  verilator_coverage \
    --annotate coverage/tage/annotated \
    coverage/tage/coverage.dat

If the annotated/ directory already exists from a
prior run, remove it first to ensure a clean output:
  rm -rf coverage/tage/annotated

Output lands in:
  rtl/core/frontend/bpu/coverage/tage/annotated/

### Step 3 -- Read annotated tage_table.sv only

Read only:
  rtl/core/frontend/bpu/coverage/tage/annotated/tage_table.sv

Ignore all other annotated files. Focus on:
  - Lines prefixed with 0 (executed zero times)
  - Branch annotations showing untaken paths
  - generate-for headers (elaboration-time, not runtime
    gaps -- note but do not count as functional gaps)
  - Any blocks marked with coverage_off pragmas
    (intentional exclusions -- note but do not count)

For each uncovered region found, record:
  - Line number range
  - The RTL code on those lines (3-5 lines of context)
  - Whether it is a line gap or a branch gap

### Step 4 -- Produce gap report

Print the gap report to console in two sections.

#### Section A: Raw gaps

For each uncovered region, print:

  LINES: <start>-<end>
  TYPE: line | branch | generate (elaboration only)
  CONTEXT:
    <line N-2>
    <line N-1>
  > <uncovered line>
    <line N+1>
    <line N+2>

List gaps in line number order.

#### Section B: Coverage plan mapping

For each gap found in Section A, attempt to map it to
one or more rows in tage_coverage_plan.md.

Print each mapping as:

  GAP: tage_table.sv:<lines>
  MAPS TO: <row ID> -- <row description>
  CONFIDENCE: high | medium | low
  REASON: <one sentence explaining the mapping>

If a gap does not map to any existing row:

  GAP: tage_table.sv:<lines>
  MAPS TO: NONE -- no matching coverage plan row
  CONFIDENCE: n/a
  REASON: <one sentence describing what the gap covers>
  SUGGEST: <proposed new coverage row description>

If a gap maps to a row marked as covered or conflict:

  GAP: tage_table.sv:<lines>
  MAPS TO: <row ID> -- CONFLICT: plan marks as <status>
  CONFIDENCE: <high | medium | low>
  REASON: <explanation>

Pay particular attention to:
  - fh_sel case statements (CP-10)
  - Slot 1 RAM write paths, bweb loops, addr/din mux
    for slot 1 (CU-11)
  - Any paths not seen in the INFRA-005 analysis

## Constraints
- Do not modify any RTL or testbench .sv files.
- Do not modify any Makefile targets.
- Do not modify tage_coverage_plan.md.
- Console output only. No file writes beyond the
  annotated/ build artifact.
- Scope analysis strictly to tage_table.sv.
  Do not report gaps from other annotated files.

## Deliverables
1. Console output: Section A raw gap list for
   tage_table.sv.
2. Console output: Section B coverage plan mapping
   with confidence indicators.
3. Results Capture filled in below summarizing gap
   count, which known items (CP-10, CU-11) are
   confirmed open or closed, and any new gaps found.
:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::
## Summary
18 gap regions found in tage_table.sv. CP-10 (fh_sel cases
1-3 and default) is confirmed open. CU-11 (slot 1 write
paths) is confirmed open and wider than INFRA-005 diagnosed
-- not only RAM write lines but the addr_mux norm_we body
itself was never entered (line 412, count 0), proving
norm_we_s1 was never true during any test. CE-10 (allocation
path) and CE-11 (alt-CTR write) are confirmed open for both
slots. One new gap found: TAGE_FAST_INIT plusarg path has
no existing plan row.

Hypothesis result: CONFIRMED. The 24% gap is concentrated
in (a) slot 1 write paths (CU-11, G09-G18, 10 gap regions)
and (b) T1-T3 fh_sel cases (CP-10, G01-G04, 4 regions).
Additional gaps CE-10/CE-11 (G06/G07/G08/G09/G11) and the
fast-init path (G05) account for the remainder.

## Test Matrix
Omitted -- not a testbench session.

## What was delivered
1. Coverage data timestamp verified: coverage.dat
   (Apr 24 16:07) newer than tb_tage.sv (Apr 24 11:06).
   No cov_tage re-run required.
2. Annotated output regenerated clean (old annotated/
   removed, new run produced).
3. Section A: 18 raw gap regions listed in line order for
   tage_table.sv only.
4. Section B: All 18 gaps mapped to coverage plan rows
   with confidence indicators.
5. Results Capture completed.

## Step 1 -- Coverage data timestamp check
coverage.dat: Apr 24 16:07
tb_tage.sv:   Apr 24 11:06
coverage.dat is newer. No re-run required.

## Step 2 -- Annotate output
Removed coverage/tage/annotated/ (prior run).
Ran: verilator_coverage --annotate coverage/tage/annotated
     coverage/tage/coverage.dat
Tool reported: Total coverage (227/4789) 4.00%
Note: 4% is the raw tool-wide metric across all annotated
files including bw_ram. The 76% figure from genhtml HTML
report is the module-scoped line/branch metric for the TAGE
unit as a whole. The two numbers are not comparable.

## Step 3 -- tage_table.sv read
Read only coverage/tage/annotated/tage_table.sv (499 lines).
Ignored all other annotated files.

No coverage_off pragmas found in tage_table.sv.
No generate-for blocks found (instantiation is by module
parameter, not generate). The fh_sel case arms for
THIS_TABLE==1,2,3 and default are runtime branches, not
elaboration-time constants, and are counted as functional
gaps.

## Step 4 -- Gap report summary

Total gap regions: 18

Gap breakdown by category:
  CP-10 (fh_sel T1/T2/T3/default): G01-G04       4 regions
  CE-10 (allocation path, s0+s1):  G06,G07,G09,
                                   G11            4 regions
  CE-11 (alt-CTR din, slot 0):     G08            1 region
  CU-11 (slot 1 write paths):      G10,G12-G18    9 regions
  NONE  (fast-init plusarg):       G05            1 region

CP-10 status: OPEN (confirmed). fh_sel cases 1, 2, 3, and
default all have count 0. Only case 4 (T4 instance) was
exercised (count 1). T1/T2/T3 instances never selected
their respective folded-history case arms in any test.

CU-11 status: OPEN (confirmed, scope expanded). INFRA-005
found zero counts on RAM write lines. This session finds
the root cause is deeper: norm_we_s1 (the OR of all slot 1
write-enables) was NEVER asserted. addr_mux_s1 line 412
(body of else-if norm_we_s1) has count 0 despite the
condition being reached 335 times. All din_mux_s1 and
bweb_mux_s1 slot 1 write-data and byte-enable paths also
have count 0. The we_s1 always_comb block itself executed
(count 1 from initialization) but all output enables were
false in every test scenario. Root cause: slot 1 updates
with a table-selector matching THIS_TABLE were never driven
into any tage_table instance during the test run.

CE-10 status: OPEN (confirmed). alc_we_s0 and alc_we_s1
addr_mux branches have count 0; alc_wd din_mux bodies have
count 0 for both slots. Allocation from tage_cntrl never
reached tage_table write path.

CE-11 status: OPEN (confirmed). din_mux_s0 alt_ctr body
(line 300) has count 0. alt_ctr_we_s0 was never true while
prm_ctr_we_s0 was false during 312 evaluated else-if
occurrences. Note: CE-11 gap exists only for slot 0 here
because all slot 1 write paths (including alt-CTR) are
covered under CU-11.

New gap (no plan row): TAGE_FAST_INIT plusarg path.
Lines 224-229 (fast-init body inside initial block) have
count 0. No test passes +TAGE_FAST_INIT=1. Suggest new
coverage plan row for this path.

Notable observations:
- Slot 0 normal write path IS partially covered: addr_mux_s0
  norm_we_s0 body (line 284) has count 1, and bweb_mux_s0
  ctr/use/epc loops have non-zero counts. Slot 1 has zero
  across all write paths. The asymmetry between s0 and s1
  confirms that the testbench sends slot 0 updates but slot
  1 update valid (tage_upd_val_u0[1]) is either not driven
  or driven with a non-matching table selector.
- tag_p1 reset paths (lines 343-344, 471-472) are covered
  (count 4 each) -- 4 reset cycles observed during test.

## Test Case Results
Not applicable -- verification session.

## Assumptions made not explicit in the prompt
1. The fh_sel default arm (lines 160-163) is treated as a
   functional gap (not an elaboration-time dead case),
   because THIS_TABLE is a runtime parameter value
   evaluated inside an always_comb case statement.
   Architecturally the default is unreachable given the
   four T1-T4 instances, but the coverage tool marks it
   as a live branch.
2. The 4% figure from verilator_coverage --annotate is
   the raw tool-wide metric and is not compared to the
   76% HTML-based baseline. Analysis is scoped to
   tage_table.sv only per prompt constraints.

## Decisions made not explicit in the prompt
1. Gap G10 (addr_mux_s1 line 412, norm_we_s1 body) is
   classified as a CU-11 conflict rather than a new gap,
   because CU-11 already covers slot 1 write paths and
   this line is part of that path -- it provides root
   cause evidence rather than a new functional behavior.
2. G11-G18 (din_mux_s1 and bweb_mux_s1 bodies) are all
   mapped to CU-11 for the same reason.
3. G07 and G09 are mapped to CE-10 (allocation path) in
   addition to or instead of CU-11 because they concern
   the alc_we_s{0,1} allocation branch, which is a
   distinct functional path from normal update writes.

## RVA23 compliance risks and gaps noticed
None identified in this session. The gaps are testbench
coverage deficiencies, not RTL compliance issues.

## Deferred Work
- Closure testbench work for CU-11: determine why
  tage_upd_val_u0[1] with a matching table selector is
  never driven. Options: (a) TB-ARB-05/TC-23 test case
  does not set upd_val[1] correctly, (b) the table
  selector arbitration always routes slot 1 updates to
  a non-matching instance.
- Closure testbench work for CP-10: drive folded_hist
  into T1, T2, T3 instances (not only T4).
- Closure testbench work for CE-10: drive an allocation
  event with ueff==0 candidate end-to-end.
- Closure testbench work for CE-11: drive an alt-CTR
  update to slot 0 without a prm match on the same cycle.
- New plan row for TAGE_FAST_INIT path.
  See Suggest note in Section B.

## Other Notes
- The we_s1 always_comb block (lines 381-402) shows
  count 1 on all lines, which might appear to indicate
  coverage. This is the initialization-time evaluation
  of the combinational block. The OUTPUT enables
  (prm_ctr_we_s1, alc_we_s1, norm_we_s1, etc.) were
  all false in every meaningful test cycle, so no
  downstream write path fired.
- This analysis supersedes the INFRA-005 CU-11 conflict
  description. The root cause is not "tests exist but
  don't reach the table" but rather "norm_we_s1 is
  architecturally never asserted with a matching selector
  in the current testbench." The investigation item in
  the Conflicts table (determine if TC-23/TB-ARB-05
  correctly drove upd_val1) remains valid.
:: RESULTS:END ::

