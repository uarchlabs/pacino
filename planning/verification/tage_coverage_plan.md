<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# TAGE Coverage Plan

## Status
| Field        | Value                        |
|--------------|------------------------------|
| Created      | 2026.04.24                   |
| Last updated | 2026.10.10 (BP-126)          |
| Baseline     | INFRA-003/INFRA-004          |
|              | BP-028 figures below were    |
|              | NOT re-measured after that   |
|              | task and the metric was      |
|              | line/branch: tage 97.2%,     |
|              | tage_table 90.1%.            |
|              | MEASURED BP-097 with         |
|              | --coverage-line, per DUT     |
|              | file, in cov_tage:           |
| tage.sv      | 137/144   95.1%              |
| tage_cntrl   | 253/258   98.1%              |
| tage_bim     | 35/41     85.4%              |
| tage_table   | 131/172   76.2%              |
| RTL only     | 556/615   90.4%              |
|              | In cov_tage_table:           |
| tage_table   | 155/172   90.1%              |
|              | Whole-compile: cov_tage      |
|              | 6418/8700 73.8%,             |
|              | cov_tage_table 399/502       |
|              | 79.5%. Both include the      |
|              | testbench -- 8043 of         |
|              | cov_tage's 8700 lines are    |
|              | tb_tage.sv. Quote the        |
|              | denominator with the         |
|              | number. See TD#100.          |
| Target       | 90% line/branch before       |
|              | bp_cluster integration       |
| BP-126       | RE-MEASURED per file: RTL    |
|              | 588/614 in cov_tage, every   |
|              | uncovered RTL line explained |
|              | (section below). The target  |
|              | since BP-126: every RTL line |
|              | covered or explained, per    |
|              | file with its denominator.   |

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
pending Verilator support (see debt #38). TD#38 CLOSED by BP-126:
Verilator 5.048 ignores every covergroup with COVERIGN and records no
coverage; support came after 5.048 (issue 7099, closed through
#7117).

---

## Line coverage per file, BP-126

Measured by BP-126's final regression, from the DA records of
coverage/tage/coverage.info and coverage/tage_table/coverage.info.
cov_tage merges a walk run and a +TAGE_FAST_INIT=1 run of one binary.

HOW A LINE IS COUNTED. A line in the .info file is covered only when
every coverage point on it, line and branch alike, is hit in every
instance. tage_table.sv line 292 is hit in T1, T2 and T3 and not in
T4, and reads 0. That is why tage_table.sv read 125/172 in cov_tage
and 155/172 in cov_tage_table (one instance), the BP-097 accounting
question. State the denominator with every figure.

```
cov_tage
  RTL  rtl/lib/rtl/bw_ram.sv              8/8
  RTL  rtl/lib/rtl/sram_init.sv          16/24
  RTL  bpu/rtl/tage.sv                  126/126
  RTL  bpu/rtl/tage_bim.sv               41/41
  RTL  bpu/rtl/tage_cntrl.sv            243/243
  RTL  bpu/rtl/tage_table.sv            154/172
  RTL subtotal                          588/614
  TB   bpu/tb/tage_assert.sv             10/10
  TB   bpu/tb/tb_tage.sv               6141/8401
  ALL                                  6739/9025
cov_tage_table
  RTL  rtl/lib/rtl/bw_ram.sv              8/8
  RTL  bpu/rtl/tage_table.sv            155/172
  RTL subtotal                          163/180
  TB   bpu/tb/tb_tage_table.sv          236/322
  ALL                                   399/502
```

Uncovered RTL lines, each unreachable:
- sram_init.sv, the START_DELAY != 0 arm and the DELAY state: tage
  instantiates START_DELAY = 0.
- tage_table.sv, the THIS_TABLE arms of fh_sel: each instance enters
  only its own arm, and a line counts only when every instance does.
  tb_tage_table instantiates THIS_TABLE = 1 only.
- tage_table.sv, the fh_sel default arm: tage_table is instantiated
  for T1-T4 only; T0 is tage_bim.
- tage_table.sv, the alternate-provider CTR write data in the T4
  instance: T4 is the longest table and never the alternate.
- tage_table.sv, the untaken +TAGE_FAST_INIT branch in
  cov_tage_table, which always runs with the plusarg. Covered in
  cov_tage.

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
| CP-01 | T0 sole provider, taken prediction       | CTR rows 13c,13d  | covered  |
| CP-02 | T0 sole provider, not-taken prediction   | CTR rows 13a,13b  | covered  |
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

CP-01 and CP-02 cited rows 13a,13d and 13b,13c, the T0 rows by
outcome, not by prediction (tage_cntrl_ctr_update_rules.md 13a-13d:
13c and 13d predict taken). Corrected session-077.

Note CP-11 and CP-12: functional coverage confirmed via
raw per-instance dat counts (pi2=1, pi3=1). verilator_coverage
--annotate displays 0 for these lines due to multi-instance
aggregation artifact. See BP-028 Results Capture.

### Update Path

| ID    | Description                              | Rules ref          | Status   |
|-------|------------------------------------------|--------------------|----------|
| CU-01 | T0 CTR increment (resolved taken)        | Rows 13b,13d       | covered  |
| CU-02 | T0 CTR decrement (resolved not-taken)    | Rows 13a,13c       | covered  |
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

CU-01 and CU-02 cited row 13a for a T0 increment on taken and row 13d
for a decrement on not-taken. 13a decrements (not-taken, correct) and
13d increments (taken, correct); the increments are 13b and 13d, the
decrements 13a and 13c. Corrected session-077.

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
|       |                                          | cov_gap_tst E      |          |
|       |                                          | (BP-126)           |          |
| CE-10 | Allocation fires end-to-end; ueff==0     | tage_cntrl alloc   | covered  |
|       | entry found, allocated, written to RAM   | TC-60 (BP-026)     |          |
| CE-11 | Alt-provider CTR write reaches           | tage_table         | covered  |
|       | tage_table RAM                           | TC-59 (BP-026)     |          |

CE-09 read covered from BP-026, but the interval-decrement arm never
ran before BP-126: the aging tests force the interval to 0. BP-126
cov_gap_tst E covers it (interval 2, the epoch advancing on the third
prediction and the interval reloading).

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
| BP-126    | per-file RTL coverage     | PASS      |
|           | (TD#100), CE-09 decrement |           |

---

## Deferred

- Functional coverage via covergroup/coverpoint: blocked
  on Verilator issue #7099. See debt #38. Verilator 5.048
  does not support covergroups (TD#38, closed by BP-126);
  revisit on an upgrade past #7117.
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
