# TAGE Coverage Plan

## Status
| Field        | Value                        |
|--------------|------------------------------|
| Created      | 2026.04.24                   |
| Last updated | 2026.04.26 (BP-028)          |
| Baseline     | INFRA-003/INFRA-004          |
| tage         | 97.2% line/branch            |
| tage_table   | 90.1% line/branch            |
| tage_cntrl   | included in tage             |
| tage_bim     | included in tage             |
| Target       | 90% line/branch before       |
|              | bp_cluster integration       |

---

## Purpose

Define the functional coverage goals for the TAGE branch
predictor unit prior to bp_cluster integration. This
document covers tage.sv, tage_cntrl.sv, tage_table.sv,
and tage_bim.sv as a single verification scope.

Coverage is measured using Verilator --coverage-line via
the cov_tage Makefile target. HTML reports are generated
by genhtml and viewed at coverage/tage/html/index.html.
Annotated source reports are produced by
verilator_coverage --annotate and land in
coverage/tage/annotated/.

Functional coverage via covergroup/coverpoint is deferred
pending Verilator support (see debt #38).

---

## Coverage Matrix

Each row is a coverage goal. Status is updated manually
after each coverage closure session or gap analysis.

Status values:
  covered  -- exercised by existing tests
  gap      -- confirmed not exercised
  deferred -- accepted gap with documented rationale
  conflict -- plan said covered but annotation says not;
              needs investigation
  unknown  -- not yet analyzed

### Prediction Path

| ID    | Description                              | Rules ref         | Status   |
|-------|------------------------------------------|-------------------|----------|
| CP-01 | T0 sole provider, taken prediction       | CTR rows 13a,13d  | covered  |
| CP-02 | T0 sole provider, not-taken prediction   | CTR rows 13b,13c  | covered  |
| CP-03 | T1-T4 primary provider, alt T0           | CTR rows 14-17    | covered  |
| CP-04 | T1-T4 primary, T1-T4 alt (longer hist)   | CTR rows 1-12     | covered  |
| CP-05 | UAON mux switches provider               | UAON rules        | covered  |
| CP-06 | UAON threshold crossing restore          | TC-40, TC-41      | covered  |
| CP-07 | Slot 0 prediction                        | NUM_PRED_SLOTS=2  | covered  |
| CP-08 | Slot 1 prediction                        | NUM_PRED_SLOTS=2  | covered  |
| CP-09 | Simultaneous slot 0 + slot 1 prediction  | TC-22             | covered  |
| CP-10 | T3/T4 fh_sel exercised                   | tage_table fh_sel | covered  |
|       |                                          | TC-57 (BP-026)    |          |
| CP-11 | T2 fh_sel arm exercised                  | tage_table fh_sel | covered  |
|       |                                          | TC-61 (BP-028)    |          |
| CP-12 | T3 fh_sel arm exercised                  | tage_table fh_sel | covered  |
|       |                                          | TC-62 (BP-028)    |          |

Note CP-11 and CP-12: functional coverage confirmed via
raw per-instance dat counts (pi2=1, pi3=1). verilator_coverage
--annotate displays 0 for these lines due to multi-instance
aggregation artifact. See BP-028 Results Capture.

### Update Path

| ID    | Description                              | Rules ref          | Status   |
|-------|------------------------------------------|--------------------|----------|
| CU-01 | T0 CTR increment (resolved taken)        | Row 13a            | covered  |
| CU-02 | T0 CTR decrement (resolved not-taken)    | Row 13d            | covered  |
| CU-03 | T1-T4 CTR increment, primary provider   | Rows 1-8           | covered  |
| CU-04 | T1-T4 CTR decrement, primary provider   | Rows 1-8           | covered  |
| CU-05 | USE increment (pred correct, pred diff)  | Rows 14-17         | covered  |
| CU-06 | USE decrement (pred wrong, pred diff)    | Rows 14-17         | covered  |
| CU-07 | EPC write on allocation                  | TC-42, TC-43       | covered  |
| CU-08 | Aging: age=1 not candidate               | TC-44              | deferred |
| CU-09 | Aging: age=2 is candidate                | TC-45              | deferred |
| CU-10 | Slot 0 update                            | NUM_PRED_SLOTS=2   | covered  |
| CU-11 | Slot 1 update                            | NUM_PRED_SLOTS=2   | covered  |
| CU-12 | Simultaneous slot 0 + slot 1 update      | TB-ARB-05          | covered  |

### Arbitration Path

| ID    | Description                              | Rules ref          | Status   |
|-------|------------------------------------------|--------------------|----------|
| CA-01 | Pred only, RB not full (Rule 5)          | TC-47              | covered  |
| CA-02 | Upd only, bypass (Rule 6)               | TC-48              | covered  |
| CA-03 | Concurrent pred wins (Rule 3)            | TC-49              | covered  |
| CA-04 | Concurrent upd wins after pred (Rule 3)  | TC-50              | covered  |
| CA-05 | RB full blocks pred, PQ fills (Rule 1)   | TC-52              | covered  |
| CA-06 | RB full, upd wins (Rule 4)              | TC-53              | covered  |
| CA-07 | Credit exhaustion, upd granted (Rule 4)  | TC-54              | covered  |
| CA-08 | Starvation override (Rule 2)             | debt #39           | deferred |

### Error and Boundary Paths

| ID    | Description                              | Rules ref          | Status   |
|-------|------------------------------------------|--------------------|----------|
| CE-01 | CTR at max (11), increment saturates     | bw_ram sat_alu     | covered  |
| CE-02 | CTR at min (00), decrement saturates     | bw_ram sat_alu     | covered  |
| CE-03 | USE at max (1111), increment saturates   | sat_alu            | covered  |
| CE-04 | USE at min (0000), decrement saturates   | sat_alu            | covered  |
| CE-05 | No allocation candidate available        | tage_cntrl alloc   | covered  |
| CE-06 | tage_cntrl error path (mispredict=0,     | tage_cntrl         | covered  |
|       | no update required)                      |                    |          |
| CE-07 | PQ full, pred request dropped            | arbiter            | deferred |
| CE-08 | UQ full, upd request dropped             | arbiter            | deferred |
| CE-09 | Aging counter active; interval           | tage_cntrl         | covered  |
|       | decrements; epoch rolls over             | TC-58 (BP-026)     |          |
| CE-10 | Allocation fires end-to-end; ueff==0     | tage_cntrl alloc   | covered  |
|       | entry found, allocated, written to RAM   | TC-60 (BP-026)     |          |
| CE-11 | Alt-provider CTR write reaches           | tage_table         | covered  |
|       | tage_table RAM                           | TC-59 (BP-026)     |          |

---

## Conflicts

Rows where the plan previously marked status as covered but
INFRA-005 gap analysis found zero annotation counts.

| ID    | Conflict description                     | Resolution         |
|-------|------------------------------------------|--------------------|
| CU-08 | tage_enable_aging never driven high in   | Deferred.          |
|       | any test cycle. lcl_epoch never          | tage_enable_aging  |
|       | advanced. age=1 path in tage_table       | not driven by TB   |
|       | unreachable. Confidence: medium.         | in TC-44. Aging    |
|       |                                          | paths reached via  |
|       |                                          | alternate path or  |
|       |                                          | plan description   |
|       |                                          | incorrect.         |
|       |                                          | Accepted gap.      |
|       |                                          | Revisit at         |
|       |                                          | bp_cluster aging   |
|       |                                          | integration.       |
| CU-09 | Same root cause as CU-08.               | Same as CU-08.     |
|       | age=2 path unreachable.                  | Deferred.          |
| CU-11 | Slot 1 tage_table RAM writes showed      | Resolved BP-026    |
|       | zero execution. Plan marked covered via  | (TC-55, TC-56)     |
|       | TB-ARB-05 and TC-23. Root cause:         | and BP-027         |
|       | TB-ARB-05 drove tage_prm_comp=0          | (TC-14). Slot 1    |
|       | routing updates to tage_bim, not         | norm_we_s1         |
|       | tage_table. Testbench metadata bug.      | confirmed via      |
|       |                                          | hierarchical ref.  |

---

## Gap Analysis Process

1. Run: cd rtl/core/frontend/bpu && make cov_tage
2. Run: verilator_coverage --annotate
         coverage/tage/annotated
         coverage/tage/coverage.dat
3. Read annotated files in coverage/tage/annotated/
4. Map uncovered regions to matrix rows above
5. Update status column and Conflicts table
6. Scope closure testbench prompt from gap list

Priority order for closure:
  1. CE-01 through CE-06 (unknown rows, handle before
     bp_cluster; logic reused as ITTAGE reference)
  2. CU-08, CU-09 (deferred, revisit at bp_cluster
     aging integration)
  3. CA-08 (blocked on debt #39)
  4. CE-07, CE-08 (deferred, revisit at bp_cluster)

---

## Coverage Closure Sessions

| Session   | Target rows               | Result    |
|-----------|---------------------------|-----------|
| BP-014a-h | CP-01 through CP-09       | PASS      |
|           | CU-01 through CU-07       |           |
|           | CU-10, CU-12              |           |
| BP-023c   | CA-01 through CA-07       | PASS      |
| INFRA-005 | Gap analysis              | complete  |
| BP-026    | CU-11, CE-09, CE-10       | PASS      |
|           | CE-11, CP-10              |           |
| BP-027    | CU-11 (unit level)        | PASS      |
|           | cov_tage_table 90.1%      |           |
| BP-028    | CP-11 (fh_sel T2)         | COND PASS |
|           | CP-12 (fh_sel T3)         |           |
|           | annotation artifact noted |           |
| accepted  | CU-08, CU-09 (aging)      | deferred  |
|           | tage_enable_aging never   |           |
|           | driven; plan vs. RTL      |           |
|           | conflict; accepted gap,   |           |
|           | revisit at bp_cluster     |           |
| BP-029    | CE-01 through CE-04       | PASS      |
|           | CE-05 - 06                | --        |

---

## Deferred

- Functional coverage via covergroup/coverpoint: blocked
  on Verilator issue #7099. See debt #38.
- Inter-predictor coverage (override chain SC>TAGE>FTB>
  uBTB): deferred to bp_cluster integration.
- CA-08 Rule 2 starvation override: blocked on debt #39
  parameter invariant decision.
- CU-08, CU-09 aging paths: tage_enable_aging never
  driven high in TC-44/TC-45. Aging paths may have been
  reached via alternate code path or plan description is
  incorrect. Accepted gap. Revisit at bp_cluster aging
  integration when tage_enable_aging control is defined
  at the cluster interface.
- CE-07 PQ full, CE-08 UQ full: deferred to bp_cluster
  integration where queue depth and backpressure
  behavior will be exercised at the cluster interface.
