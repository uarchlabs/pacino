# Session Handoff 049
Written by Claude.ai at end of session-048.
Date: 2026-06-10

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Session Summary

Session-048 closed all remaining ITTAGE directed-validation
paths. Work ran BP-050 through BP-054a. Five technical debts
closed (#56, #59, #61, #63, #65). One real RTL defect found and
fixed (missing UAON single-hit guard). Two specification
documents corrected. One prior-session testbench escape found
and repaired.

Net outcome: ITTAGE EPC write, UAON trigger rules, aging/epoch
path, allocation, and prediction-side correctness are each
directed-tested as the unit under test and proven by readback.
The only ITTAGE unit item left is the #72 round-trip capstone,
whose gate (#56/57/59/61/63/65) is now fully closed.

---

## What This Session Accomplished

### BP-050 -- ITTAGE EPC write proof (#56, abandoned)

First EPC attempt. Reported the EPC gate provider-only but never
demonstrated the non-provider check could fail under a defect,
so its discriminating value was unproven. Also leaned on UAON
carried across test cases. Abandoned; redone as BP-050b.

### BP-050a -- all-targets verification (testbench escape repair)

Ran every ittage Makefile target. Found tb_ittage_cntrl and
tb_ittage_table left uncompilable by BP-049a's t_tgt_wr_u0 port
rename (BP-049a ran only sim_ittage). Repaired both testbenches;
no RTL change. This confirmed the all-targets-must-run rule:
BP-049a's carried 77/0 and 32/0 counts in handoff-048 were stale
(not from a run). Recorded as BUG-002.

### BP-050b -- ITTAGE EPC write proof (#56, complete)

EPC write gate is provider-only by construction (piggybacks on
the mutually exclusive prm_ctr_wr / alt_ctr_wr strobes; EPC
write condition is a strict subset of the CTR write condition --
no path writes EPC without CTR). No RTL change. Two directed
tests, provider and non-provider readback, UP=1 and UP=0. Step-7
defect injection (gate forced to prm_match|alt_match) made both
non-provider checks fail (exp=2 act=0), then reverted -- the
fail-before BP-050 lacked. sim_ittage 125/0. #56 closed.

Residual: TC-EPC-UP0 reaches UP=0 through UAON. UAON was
unverified at that point; #59 (below) closed that.

### BP-051 -- ITTAGE UAON trigger rules (#59, complete)

Found and fixed a real RTL defect: the UAON update block was
missing the single-hit guard (prm_comp==0 || alt_comp==0 ->
hold). Without it, a single-hit transaction with stale alt_tgt
could move the counter. Fix added the guard; proven by removing
it (TC-UAON-08 fail exp=8 act=9) and restoring. Nine directed
tests: every update-rule clause, reset value both slots,
threshold boundary with use_alt readback. Also corrected
tc_tgt_b_ext in tb_ittage, whose UAON DEC step had been encoded
around the missing guard (single-hit); replaced with a two-hit
setup. sim_ittage_cntrl 92/0, sim_ittage 125/0. #59 closed.

### BP-052 -- ITTAGE aging / epoch path (#61, complete)

All seven aging rules conform; no RTL change. Counters forced
hierarchically (no interval walking). 20 directed tests: reset
values, interval decrement, epoch advance, epoch wrap,
EPC-vs-epoch compare (ages 0/1/2), USE-decrement discriminating
power, enable gating. sim_ittage_cntrl 112/0. #61 closed.

Note: aging boundary fires N+1 (epoch advances the tick after
interval reaches 0). Tested at N=1; typical N is in the
thousands -- the boundary mechanism is the same at large N, not
separately exercised. Not a defect; periodicity off by one tick,
negligible.

### BP-053 -- ITTAGE allocation (#63, complete)

All 13 allocation rules conform; no RTL change. 11 directed
tests: which table allocates, no-consecutive skip, alc_comp==0
sentinel and write suppression, trigger gating, no-hit scan from
IT1, pre-hashed alc_idx source, allocated entry contents.
sim_ittage_cntrl 147/0. #63 closed.

Document error found and corrected (by Jeff): the alloc-rules
write-data field order had TGT and EPC swapped vs the actual
entry layout. Resolved by creating standalone entry-format docs
(ittage_table_entry_formats.md, tage_table_entry_formats.md) as
the single source for field order, referenced from the interface
docs.

TC-ALC-11 limitation: it proves the cntrl emits the correct
per-table selector, not RAM-level write isolation (that needs
the table instantiated). The #72 capstone runs at sim_ittage and
should close this seam -- an allocation in the mixed flow that
reads back the selected table changed and a non-selected table
unchanged.

### BP-054 -- ITTAGE prediction-side (#65, complete)

All 12 prediction-path rules conform; no RTL change. Nine
directed tests at tb_ittage: provider/alternate selection,
single/no hit, using_primary across the three UAON cases,
pred_strong tracking the actual selected provider, target output
with distinct seeded values, and s2 timing (resolves the #42
test aspect -- outputs valid at p2, not p3). sim_ittage 164/0.
UAON forced as a read input, not trained.

Two document gaps reported (corrected by Jeff):
- pred_strong row read "CTR != 3 and != 4" (TAGE carryover);
  corrected to "CTR != 0" (#44).
- final-target section referenced a single ittage_pred_tgt;
  rewritten so the consumer selects prm_tgt/alt_tgt via
  using_primary (no third stored target field).

### BP-054a -- prediction-side cleanup (complete)

Verified the corrected ittage_cntrl_decisions.md is consistent
with RTL and tests. pred_strong and final-target rules conform;
no ittage_pred_tgt field or reference remains in struct, RTL, or
testbench; no code change. All 22 targets pass, sim_ittage
164/0. Closes the #65 documentation alignment.

---

## Specification and Process Changes This Session

### Document corrections (by Jeff)
- ittage_cntrl_decisions.md: pred_strong corrected to CTR != 0;
  final-target section rewritten to consumer-muxed prm/alt with
  no single pred_tgt field.
- ittage_cntrl_alloc_rules.md write-data field order corrected
  (TGT/EPC swap).
- New: ittage_table_entry_formats.md and
  tage_table_entry_formats.md -- single source for entry field
  order, referenced from the interface docs.
- Status promoted to Complete: ittage_cntrl_alloc_rules.md,
  ittage_cntrl_uaon_update_rules.md, ittage_cntrl_use_update_
  rules.md.

### CLAUDE.md changes
- Verification Expectations: the "named module's suite only"
  scope was replaced by ALL TARGETS MUST RUN -- every sim and
  lint target in the Makefile runs, whether or not it is a
  dependency of `all`; `make all` is not sufficient; per-target
  counts from the current session; any sim fail or lint warning/
  error blocks complete unless waived with a TD number.
- Verification Expectations: self-contained-tests rule added --
  a test must not depend on unverified behavior or on test
  order; enumerate and seed every mechanism the stimulus relies
  on (reset values, sentinels, thresholds, residue, hashes);
  invalidate aliasing entries; establish start state by reset
  plus driven sequence; do not carry state across cases.

### Prompt-practice changes
- Manifest scope tightened: load only the reference document(s),
  the RTL under test, the packages needed to compile, the
  testbench, and the Makefile. Do not pad with interface or
  decision docs that the task does not read. (BP-050a/053 ran
  oversized manifests; trimmed thereafter.)
- A task that renames or changes a module's ports runs every
  testbench that instantiates that module (the BP-049a escape).
- Jargon: engineering language only. "check against" not
  "adjudicate"; state what depends on what rather than
  "load-bearing"; assert/deassert not "fire". Carry into every
  prompt.

---

## Prompt-author reminder (carry forward each session)

- ALL TARGETS MUST RUN: enumerate every Makefile sim and lint
  target, run each, report per-target counts from this session
  (authority: CLAUDE.md Verification Expectations).
- Tests self-contained: seed every dependency, no carried state,
  no reliance on test order (authority: CLAUDE.md).
- Manifest minimal: reference doc(s), RTL under test, packages,
  testbench, Makefile. Nothing padded.
- Port-change tasks run every instantiating testbench.
- Engineering language only.

---

## Stale Status To Reconcile

Apply to PROJECT_STATUS before next session if not already done:
- ittage_cntrl.sv Module Status: "147 tests passing w/ BP-048"
  -> sim_ittage_cntrl 147/0; status Complete; note UAON/aging/
  alloc verified BP-051/052/053.
- ittage.sv Module Status: "sim_ittage 125" -> 164/0. Leave
  In progress until #72, or mark "directed validation complete,
  #72 capstone pending."
- ITTAGE decomposition block: "Directed validation in progress"
  -> directed validation complete except #72; line coverage
  recheck.
- TD #42: test aspect confirmed by BP-054 (outputs at s2);
  close the test portion, leave the diagram edit if pending.
- TD #44: pred_strong CTR != 0 confirmed and doc corrected;
  closeable.
- BUG-002 (new): record the BP-049a testbench escape (see
  below).

### BUG-002 text for the BUG Records section
- BUG-002: BP-049a renamed t_tgt_wr_u0 to t_prm/t_alt in
  ittage_cntrl.sv and ran only sim_ittage. tb_ittage_cntrl and
  tb_ittage_table were left uncompilable; their 77/0 and 32/0
  counts carried in handoff-048 were stale (not from a run).
  Found and repaired BP-050a. Cause of the all-targets-must-run
  rule.

---

## Open Technical Debt

ITTAGE directed validation is complete. Closed this session:
#56, #59, #61, #63, #65.
Remaining ITTAGE unit surface:
  - TD #72: ITTAGE round-trip capstone (next, see below).
TAGE unit surface (untouched this session, the parallel set):
  - TD #55 (EPC), #58 (UAON), #60 (aging), #62 (alloc),
    #64 (prediction-side), #71 (round-trip). TAGE is green
    (68/68); not urgent. The ITTAGE BP-050b..054 sequence is the
    template for these.
Carried, unchanged:
  - TD #38 covergroup #7099; #43 ITTAGE CTR 3b->2b (will churn
    CTR/aging tests written before it lands); #49 arb queue port
    renaming; #52/#73 arb submodule + test; #67/#68 sram_init
    non-fast path; #69/#70 rollback; #71 TAGE round-trip.
  - TD #75 (no sim_ittage_fast target); #77 (scrub absolute
    paths, use RVA_ROOT -- non-design, infra).

---

## Next Session (049)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-049.md (this file)
  CLAUDE.md

### Planned work -- TD #72 ITTAGE round-trip capstone

The gate is met: #56, #57, #59, #61, #63, #65 each proven alone.
Build one mixed flow that exercises CTR, USE, allocation, EPC,
and TGT together in sequence, run at sim_ittage (full ittage,
cntrl + tables). Same isolation-first rationale as #71: it is
run only now, after each path is proven alone, to avoid the
multi-cause ambiguity that stalled BP-044.

Must include:
- An allocation step with RAM readback confirming the selected
  table changed and a non-selected table did not -- this closes
  the TC-ALC-11 seam (BP-053 proved the selector, not RAM-level
  write isolation).
- Self-contained per the new rule: seed every entry, no carried
  state, no reliance on UAON/aging defaults unless forced.
- ALL ittage Makefile targets run; per-target counts this
  session.

### After #72
ITTAGE unit verification complete (directed). Remaining ITTAGE
items are deferred to bp_cluster (#69/#70 rollback) or pending
other work (#43 CTR width, #75 sim_ittage_fast, #68 sram_init
non-fast). The TAGE parallel set (#55/#58/#60/#62/#64/#71) can
follow the same BP-050b..054 template, or move to bp_cluster /
FTB-SC-RAS per Jeff's priority.

