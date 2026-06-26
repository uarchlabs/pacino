<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 056
Written by Claude.ai at end of session-055.
Date: 2026-06-26

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

Session-055 took bp_history from "reworked but not re-verified" to
COMPLETE: ran BP-072 (which surfaced and fixed a real integration
defect), added an external fold anchor (BP-073), captured the fold
geometry natively into the decisions doc (the durable win), and
verified doc-RTL consistency (BP-074). bp_history is done at the
unit level. SC is the agreed next unit.

The bp_history authority docs:
  planning/arch/bp_history_decisions.md        (now carries s6,
                                                the canonical fold)
  planning/interfaces/bp_history_interfaces.md

---

## Read This First

bp_history.sv is COMPLETE and frozen: module-owned pointer, corrected
increment-oriented fold geometry, the fold definition captured
natively in decisions.md s6, full bpu suite 33/33 green. Two git tags
mark the verified state: bp_history-pre-bp073 and
bp_history-bp073-complete.

The headline of the session is NOT just "BP-072 passed." Running it
exposed that session-054 left BP-069 (module-owned pointer) and
BP-071 (fold geometry) in SEPARATE files -- BP-069 only in
versions/bp_history.sv, BP-071 only in the active rtl/ file. No single
file held both, so the pointer-to-fold addressing for an incrementing
module-owned pointer was never written or run, even though handoff-054
and PROJECT_STATUS recorded both as landed and lint-clean. That record
was inaccurate; it is corrected in PROJECT_STATUS (BUG-005) this
session. The merge produced an incremental-vs-recompute divergence
(0x92 -> 0x00 on rollback), fixed under authorized scope expansion.

The second, more durable outcome: the fold geometry no longer depends
on an external source. It is now defined in the project's own terms in
bp_history_decisions.md s6, with Xiangshan demoted to an origin
footnote. This closes the loop that the whole bp_history saga turned
on -- a citation to a living external repo was never a real spec.

Remaining bp_history work is bookkeeping only (commit/push, sha fill,
checkbox flips, file retirement); see Open Work. SC is greenfield and
needs planning docs first; see Next Session.

---

## Session Summary

1. BP-072 (testbench + RTL, COMPLETE, scope expanded with
   authorization). The prompt premised BP-069 and BP-071 both already
   in rtl/. They were not. The IA stopped at the precondition, gave
   git/interface-doc evidence, and confirmed versions/bp_history.sv
   was the BP-069 copy -- but also that it carried the PRE-BP-071 fold
   geometry, so a straight copy would regress BP-071. Neither file had
   both. Authorized to merge: BP-069 interface + BP-071 folds. The
   merge then showed incremental fold != rollback recompute, because
   BP-071's geometry walk and BP-069's incrementing pointer disagreed
   on direction. Fixed: increment-oriented walk (fold_ghr ptr-i;
   fold_step evicts at write_addr-H) + POST-advance checkpoint with
   recompute anchor ckpt-1. The BP-071 posmap and high-end insertion
   are UNCHANGED -- an addressing reconciliation, not a geometry
   change; no table-consumed fold value moved. Result: 16 directed
   TCs, 19224 golden fold comparisons, single-slot + dual-slot (TD
   #74) + GHR-wrap + SC ST3 all proven in-sim; full bpu 33/33 green.
   While landing it the IA found the checkpoint pre/post-advance
   inconsistency between decisions.md and interfaces.md; resolved to
   POST-advance (num_branches-independent anchor).

2. BP-073 (verification, COMPLETE). External fold-value anchor. BP-072
   proved DUT-incremental == fold_ref == DUT-recompute, but fold_ref
   shares the DUT geometry, so that was self-consistent, not
   externally anchored. BP-073 found the table hash-rule docs define
   fold CONSUMPTION only (not computation), so there was no
   independent table-side definition; per the prompt's fallback it
   computed from the Xiangshan definition and committed THREE literal
   anchors -- TAGE T1 0xE5, ITTAGE IT1 0x9, SC ST3
   0xC000_0000_0000_0000 -- as fixed constants a shared-geometry drift
   cannot co-move with. All matched DUT + literal. The doc gap (no
   computation definition) was flagged, which motivated step 3.

3. Canonical fold capture (doc edit). Added bp_history_decisions.md
   section 6 (Fold Definition): age indexing, posmap(i) = (i+W-1)%W,
   eviction at (H-1)%W, the recompute == incremental invariant, and a
   checkable worked example tied to the BP-073 TC14 anchor
   (0xD3 -> 0xE5). Xiangshan demoted to an origin footnote (s6.6, sha
   placeholder). Old sections 6-10 renumbered 7-11; s2.2 now cites s6
   as the geometry authority; s7 ratifies POST-advance checkpoint.

4. BP-074 (verification, COMPLETE). Doc-RTL consistency audit of s6:
   repo drift isolated to the decisions doc (RTL/tb/packages/Makefile
   byte-identical to tag), all 18 cross-references resolve after the
   renumber, s6 matches fold_ghr/fold_step line-by-line, the three
   anchors re-derived from s6's rules reproduce the committed literals
   and the DUT output, interfaces.md confirms post-advance, full bpu
   33/33 green. It flagged that decisions.md s10 still called the
   cluster "the pointer authority" -- stale vs the s2 module-owned
   ruling, and (honestly) a line the PA carried forward unaudited
   during the renumber. Jeff applied the PA-supplied reword.

5. PROJECT_STATUS updated: bp_history.sv In progress -> Complete; the
   stale "NOT re-verified / WAIVED / BP-072 not run" notes replaced
   with the BP-072/073/074 outcomes; TD #74 bp_history part CLOSED;
   BUG-004 closed; BUG-005 added (the never-co-resident integration
   defect); TD #83 (s6.6 sha fill) and TD #84 (producer/consumer
   end-to-end fold check, -> bp_cluster) added.

6. Git: tagged bp_history-pre-bp073 (before BP-073) and
   bp_history-bp073-complete (after). Per-step tagging was scaffolding
   for the unverified-state risk and is no longer needed now that the
   unit is frozen; back to normal commit/push rhythm.

Note: the BP-072 prompt was tightened mid-session (fold_ref input
contract + impulse-sweep + no-fold self-checks) but the executed run
appears to have used the pre-tightening version. Moot -- BP-073's
external anchor and BP-074's re-derivation cover the same ground more
directly.

---

## What Was Accomplished

  - bp_history.sv COMPLETE: module-owned pointer (BP-069),
    increment-oriented Xiangshan fold geometry (BP-071/BP-072), 64b
    helpers. Lint clean; no TAGE/ITTAGE/RAS/FTB regression.
  - Dual-slot fold equivalence (TD #74) proven in-sim (BP-072).
  - External fold anchor committed (BP-073).
  - Fold geometry captured NATIVELY into decisions.md s6; external
    dependency on Xiangshan removed (origin footnote only).
  - Doc-RTL consistency verified (BP-074).
  - PROJECT_STATUS corrected (bp_history Complete; 054 record fixed
    via BUG-005; TD #74 closed; TD #83/#84 added).
  - Task files: BP-072, BP-073, BP-074 done.

---

## Open Work

### bp_history -- bookkeeping only (do early in 056, not blocking SC)

  - Commit the decisions.md (s6 capture + s7 post-advance + s10
    reword) and the updated PROJECT_STATUS, then PUSH. The verified
    state currently lives only on rosencrantz under local tags.
  - Fill bp_history_decisions.md s6.6 <XS-COMMIT-SHA> /
    <XS-CAPTURE-DATE> (TD #83). Informational; s6 is the authority.
  - Flip the Status checkboxes in prompts/BP-072.md and
    prompts/BP-073.md to complete (BP-074 already shows complete).
    The IA cannot edit those checkboxes; manual.
  - Retire versions/bp_history.sv (the stale BP-069 copy, superseded
    by the merged rtl/ file; BUG-005). Remove or clearly mark.
  - Optional: correct handoff-054 at source (it still asserts
    BP-069/BP-071 both landed clean). PROJECT_STATUS already
    supersedes it via BUG-005; fixing the handoff itself is for the
    record only.
  - Clean stray untracked files BP-074 reported (ho, notes,
    get_ras.sh, context-report.md, .swp). gitignore or remove.

### bp_history -- deferred (not this unit's work)

  - HI2 (PHR fold mixing) -> TAGE/ITTAGE hashing.
  - HI5 (checkpoint slot reclaim) -> FTQ (= G23).
  - TD #82 if/else-if slot cleanup (decisions 3.5; no behavior
    change). Fold into the next bp_history RTL touch.
  - TD #69/#70 (TAGE/ITTAGE rollback recompute) -> bp_cluster for
    rollback stimulus. Unblocked by G20/G21/G22 but needs the cluster.
  - TD #84 producer/consumer end-to-end fold check -> bp_cluster.
    BP-073 proved the fold VALUE against s6; it did NOT run that fold
    through the actual table index hash to confirm the derived index.
    That end-to-end format check needs cluster stimulus.

### Carried infra (Jeff's priority call, independent of SC)

  - #43 ITTAGE CTR 3b->2b, #75 sim_ittage_fast, #77 path scrub,
    #67/#68 sram_init non-fast, #38 covergroup #7099 re-check.

---

## bp_history State: COMPLETE

bp_history.sv is at the module-owned pointer interface with the
corrected increment-oriented Xiangshan fold geometry, the fold
definition captured natively in decisions.md s6, lint-clean, and
green across the full bpu suite (33/33, BP-074). It is verified in
simulation (BP-072 19224 comparisons), externally anchored (BP-073),
and doc-RTL consistent (BP-074). Mark it Complete. The remaining
items are bookkeeping (above) and cluster-deferred (TD #69/#70/#84,
HI2/HI5); none gate the unit.

---

## SC -- Next Unit (greenfield; needs planning docs first)

SC is the last unbuilt predictor and is Not started. It is
self-contained (its own counter tables, no cluster wiring), so it is
buildable now in the TAGE/ITTAGE/FTB mold -- but unlike those it has
NO decisions or interfaces doc yet. The first SC session is
architectural: create the planning docs and resolve the open
parameter, before any RTL.

Known SC facts already settled (scattered in PROJECT_STATUS / 
bp_cluster.md, to be consolidated into an sc_decisions.md):
  - Pipeline stage s3; override chain SC > TAGE > FTB > uBTB (SC is
    the final override).
  - Five tables, all PURE COUNTER ARRAYS, NO tag bits.
  - SC index split: sc_upd_idx[MAIN_TBLS], sc_imli_idx.
  - ST4 is the BrIMLI table -- SC only, not ITTAGE. ST0 has hist=0.
  - SC ST1-ST3 consume folded history (idx folds) from bp_history.
    Their fold geometry is now CANONICAL in bp_history_decisions.md
    s6 (ST3 is the H=W=64 case the 64b helpers were widened for).
    ST0 (hist=0) and ST4 (IMLI) have no folds.

Open SC decision to resolve at impl:
  - G7: SC threshold value -- TBD, fixed at implementation.
  - G14: confidence counter purpose (reserved, 4b) -- may interact
    with SC; confirm.
  - The statistical-corrector update rule (Seznec TAGE-SC-L style)
    and the IMLI / BrIMLI mechanism are not yet specified in a
    project doc; the SC decisions doc must define them. Verify the
    update/threshold scheme against the Seznec source (fetch, do not
    recall), the same verify-before-asserting discipline that caught
    the bp_history fold bug.

Suggested first SC task: an architectural/planning task (not RTL) ->
create planning/arch/sc_decisions.md and
planning/interfaces/sc_interfaces.md: the five tables and their
widths, the index/IMLI split, the SC fold consumption (cite
bp_history_decisions.md s6), the update rule, the threshold (G7), and
the s3 override integration point. Then RTL in a following session,
storage-split if an SRAM array is wanted (the FTB ftb_array pattern).

---

## Postmortem Record -- PA performance (session-055)

Continuing the trend log (052/053 asserting unchecked claims; 054
over-asking).

1. No fabrication, no invented process. Artifacts produced on request
   only (BP-073, BP-074, the decisions-doc s6 capture, the
   PROJECT_STATUS update, the s10 reword). Verify-before-asserting
   held: the fold math was checked by hand (the TC14 0xD3 -> 0xE5
   derivation; fold_step confirmed as the exact incremental form of
   fold_ghr) rather than asserted, and the self-consistency-vs-
   external-anchor gap was identified and addressed by design (BP-073)
   rather than hand-waved.

2. The notable miss: while renumbering the decisions doc for the s6
   capture, the PA carried forward the stale s10 "cluster is the
   pointer authority" wording without re-reading it against the s2
   module-owned ruling. The IA caught it in BP-074. This is the same
   stale-summary-vs-decision failure the session was about, reproduced
   in a doc the PA was editing FOR consistency. The PA did a targeted
   edit (renumber + the one row it cared about) instead of auditing
   the whole section it was rewriting. Owned, corrected (reword
   supplied and applied). Pattern to watch in 056: when editing a doc
   for consistency, audit the whole touched section against the
   ratified decisions, not just the lines being changed.

3. Minor: the PA initially proposed per-experiment git tagging and was
   asked why it was still tagging; acknowledged the scaffolding had
   served its purpose. No cost; noted for calibration.

Impact. The session reached a correct, verified, externally-anchored
result and -- the durable win -- a native fold spec that removes the
external dependency the whole bp_history saga turned on. The residual
PA cost was the single under-audited carried-forward line, caught by
the IA's BP-074 audit. The methodology guards (verify before assert,
do-not-self-heal, all-targets-run) held throughout.

---

## Next Session (056)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-056.md (this file)
  CLAUDE.md
  planning/arch/bp_cluster.md (for the SC override chain and the
  scattered SC decisions to consolidate)
  and, once it exists, planning/arch/sc_decisions.md /
  planning/interfaces/sc_interfaces.md.

Do first (quick bp_history close-out bookkeeping): commit + push the
decisions doc and PROJECT_STATUS; fill the s6.6 sha (TD #83); flip
BP-072/BP-073 status checkboxes; retire versions/bp_history.sv. None
of this blocks SC.

Then SC: start with the planning task -- create sc_decisions.md and
sc_interfaces.md (five counter tables, index/IMLI split, fold
consumption per bp_history_decisions.md s6, update rule, G7 threshold,
s3 override integration). Verify the SC update/threshold scheme
against the Seznec source before specifying. RTL follows in a later
session.

Given the Postmortem Record: in 056, when editing any authority doc
(SC's new ones included), audit the whole touched section against the
ratified decisions, not just the changed lines. Produce only what Jeff
requests, use answers already given, verify before asserting, and
confirm the session is wrapping before writing a handoff.

