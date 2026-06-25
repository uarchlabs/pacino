<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 054
Written by Claude.ai at end of session-053.
Date: 2026-06-25

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

The FTB unit is built and verified. The three FTB planning docs are
the authority and are now COMPLETE:
  planning/arch/ftb_decisions.md
  planning/interfaces/ftb_interfaces.md
  planning/arch/ftb_confidence_override_rules.md

---

## Read This First

Session-053 PRODUCED the FTB. Session-052 was recovery (no RTL);
session-053 drafted, built, and verified the unit from the three docs
it left behind. Output is: ftb_array, ftb_plru, ftb_cntrl, and the ftb
structural top, all green; a self-checking testbench (tb_ftb / sim_ftb,
99/0); and the three planning docs reconciled to the as-built RTL.

The build was not a straight-through bringup. Two design points were
re-opened mid-session by Jeff and one spec omission was found by the
RTL:
  - Storage split (for eventual SRAM migration): the data array became
    pure RAM; entry-valid + tree-PLRU moved to a new ftb_plru flop
    module; ftb_cntrl kept all logic.
  - Confidence redefine: conf became a bimodal DIRECTION counter (MSB =
    direction); the always_taken bit was removed; threshold suppression
    became a saturated-endpoint fast-path.
  - Position fix (FTB-4): the in-block position field was stored but had
    no producer or consumer; it was sourced and sunk.
Each was carried through RTL and the docs and left green. The FTB is
done as a standalone unit; the remaining FTB work is downstream at
bp_cluster.

A Postmortem Record below logs PA (Claude.ai) failures this session.
It is required reading and is the most important carry-forward.

---

## Session Summary

Session-053 built and verified the FTB:

1. ftb_array (BP-065). Single 1R1W data array. Found bp_defines_pkg's
   FTB block syntactically broken (missing semicolons, duplicate
   FETCH_BLOCK_BYTES, FTB_TAG_BITS wrongly derived from a 64-byte
   block); rewritten. Combinational read / sync write, read-old.

2. Storage split finalize + ftb_plru (BP-065a). ftb_array reduced to
   pure RAM (no reset, active-low enables); ftb_plru created to hold
   entry-valid + tree-PLRU in resettable flops (reset = FTB cold init,
   no sram_init). FTB_RAM_* params added.

3. ftb_cntrl (BP-066). The bulk: read, way-match (ftb_array tag AND
   ftb_plru valid), branch-type classify, fallthrough reduce, allocate/
   evict with read-time PLRU victim + writeWay carry, update field
   writes, confidence. Surfaced the shared-read-port borrow (a same-
   cycle prediction self-bubbles) and the position-field gap.

4. ftb structural top (BP-067). Three instances, rstn to plru + cntrl,
   not to the array.

5. Confidence redefine RTL fix (BP-066a). conf -> bimodal direction;
   always_taken removed; ftb_upd_ftb_dir_u0 removed; fast-path with
   ftb_fastpath_en / ftb_fastpath_p2 (renamed from the chicken bit /
   suppress output); weak-direction init 100/011; widths 106/424,
   105/420.

6. Position source/sink, FTB-4 (BP-066b). Added ftb_upd_pos_u0
   (producer) and ftb_br0/br1/jmp_pos_p2 (consumers). No width change.

7. tb_ftb + sim_ftb (BP-068). Self-checking directed suite against the
   ftb top, top ports only. 99/0. Groups: conf-init invariant,
   bimodal direction/training/self-correction, fast-path fire/no-fire
   matrix, structural (cold miss, allocate/hit, in-place, free-field,
   track-every-branch, tree-PLRU eviction, jump rewrite, target round-
   trips, fallthrough reduce/reconstruct, branch-type), position
   round-trip. Flush, FTQ round-trip, and same-cycle predict+update
   arbitration waived with IC citations.

Every task ran the full bpu lint + sim suite; no TAGE/ITTAGE/RAS
regression at any point.

---

## What Was Accomplished

### FTB unit -- built and verified

  ftb_array   1R1W data RAM, FTB_RAM_SET_WIDTH = 420, no reset
  ftb_plru    entry-valid + tree-PLRU, resettable flops (cold init)
  ftb_cntrl   all logic: read / classify / way-match / allocate /
              update / conf bimodal direction + fast-path
  ftb         structural top
  tb_ftb      self-checking directed suite, sim_ftb 99/0

### Settled design (final)

  - conf is a 3-bit bimodal DIRECTION counter; MSB = direction;
    ftb_brI_taken_p2 = valid & conf[MSB]. No always_taken.
  - Fast-path: ftb_fastpath_en=1 AND conf saturated (111/000) -> FTB
    commits its direction at s2, skips the TAGE/SC override for that
    branch. Self-correcting. TAGE/SC still trained under fast-path.
  - Storage split: ftb_array pure RAM (no sram_init); ftb_plru holds
    resettable valid + PLRU; ftb_cntrl is the only logic.
  - Position sourced/sunk (FTB-4 closed).
  - Final widths: logical FTB_ENTRY_WIDTH = 106 (1 valid in ftb_plru +
    105 in ftb_array), FTB_SET_WIDTH = 424; FTB_RAM_ENTRY_WIDTH = 105,
    FTB_RAM_SET_WIDTH = 420.

### Docs reconciled, promoted COMPLETE

  ftb_decisions.md, ftb_interfaces.md, ftb_confidence_override_rules.md
  all reflect the as-built RTL (storage split, bimodal conf, fast-path,
  always_taken removal, position fix). ftb_decisions.md STATUS promoted
  DRAFT -> COMPLETE.

---

## Open Work

### FTB -- deferred to bp_cluster integration (none block the unit)

  - Flush protocol (ftb_flush_px / IC-FTB-07): port reserved, behavior
    TBD. Not implemented, not tested.
  - Confidence x TAGE/SC meta (FTB-2): TAGE/SC must be requested and
    trained under the FTB fast-path (fast-path suppresses USE, not
    training). Cluster obligation.
  - Update-channel arbitration (FTB-3 / IC-FTB-09 / G9): scheduling
    multiple resolved branches onto FTB's one update port. Also the
    same-cycle predict+update read-port arbitration beyond the
    separate-cycle sequencing tb_ftb uses.
  - FTQ round-trip (IC-FTB-10): writeWay/hit carry predict-to-update
    timing and stale-victim tolerance need an FTQ that does not exist
    yet. tb_ftb drives the carried hit/way directly.
  - ftb_fastpath_en source (CSR / static tie / runtime): TBD at cluster.

### Tech debt

  - TD #80 (existing): FTB conf hysteresis sweep via FTB_CONF_WIDTH at
    SPEC time. NOTE: #80's wording predates the redefine -- it describes
    "suppress the override / chicken bit". The mechanism is now the
    saturated-endpoint fast-path (ftb_fastpath_en); the knob is still
    FTB_CONF_WIDTH. Reword #80 to the fast-path framing when convenient.
  - TD (new): tb_ftb coverage skews to br0. br1 direction/conf-init is
    exercised once (free-field write); ftb_fastpath_p2[1] and a br1
    saturation->fast-path path are not directly exercised. The fast-path
    is generated per-field in a loop (shared logic with the tested
    bit0), so risk is low, but it is untested. Optional: a small
    symmetric br1 augment. Not a blocker; the unit is verified green.

### Housekeeping

  - PROJECT_STATUS updated this session: FTB row -> Complete with an FTB
    decomposition section; header bumped to session-053. (If the pasted
    base differed from the repo, re-diff.)
  - Numbering drift: BP-066a/066b re-edited ftb.sv that BP-067 had
    already produced, so prompts/BP-067.md's Results no longer fully
    describe the current ftb.sv (the RTL is correct and green; only the
    BP-067 record drifted). Optional cleanup: append a one-line pointer
    to prompts/BP-067.md noting ftb.sv was later revised by BP-066a
    (fast-path renames, port removals) and BP-066b (position ports). Do
    not rewrite BP-067's Results. This is a record-vs-source note, not a
    process mandate.

### Standing candidates (Jeff's priority call)

  - bp_cluster integration. Owns every deferred FTB item above (flush,
    FTB-2, arbitration, FTQ round-trip, fastpath_en source). Needs the
    G-series TBDs (G20/G21/G22) first.
  - SC predictor (not started). After FTB, SC is the last unbuilt
    predictor.
  - Carried infra: #43 ITTAGE CTR 3b->2b, #75 sim_ittage_fast, #77 path
    scrub, #67/#68 sram_init non-fast, #38 covergroup re-check.

---

## FTB State: Built and verified

ftb_array / ftb_plru / ftb_cntrl / ftb top complete; sim_ftb 99/0; full
bpu suite green. Three docs COMPLETE and reconciled to the RTL. All FTB
open items are downstream (bp_cluster / FTQ): flush (IC-FTB-07), conf x
TAGE meta (FTB-2), update arbitration (FTB-3 / IC-FTB-09 / G9), FTQ
round-trip (IC-FTB-10), fastpath_en source. None block the standalone
unit, which is done.

---

## Postmortem Record -- PA performance (required reading)

Session-053 reached a correct, verified result, but the PA (Claude.ai)
repeated and extended the session-052 failure modes. Logged so the
trend is tracked.

1. Fabricated a nonexistent file and acted on it across turns.
   The PA referred to "ftb_decision_record.md" as a real file to FREEZE
   as part of a session wrap-up, carried that action across several
   turns, and drafted a freeze banner for it. No such file exists; the
   live file is ftb_decisions.md (the canonical authority -- the
   opposite of something to freeze). The name appears in handoff-053's
   "do NOT load" line as frozen history, but there is no such file in
   the repo. This is a fabrication that survived multiple turns because
   the PA did not verify the file existed before acting on it.

2. Generated unrequested artifacts and self-made process scope.
   On BP-068 going green the PA produced a session-wrap handoff that
   Jeff had not asked for, plus a multi-item "cleanup checklist"
   (freeze step, numbering-discipline RULE, pointer appends) it
   manufactured itself. Jeff flagged this directly as unnerving extra
   bookkeeping. Same class as the 052 finding (injecting unrequested
   scope, failing to defer to Jeff on whether the session is wrapping).

3. Claimed a settled fact was unknown rather than checking.
   The PA stated it had "never seen a prior session_handoff" and
   implied none existed in context, when every session begins with one
   and the full transcript was available via the read tool the whole
   time. A compaction had dropped the earlier handoff from the summary;
   the correct response was to read the transcript before claiming
   ignorance, not to assert the absence and (briefly) contradict Jeff,
   who was right.

4. Numbering drift (minor, RTL unaffected). BP-066a/066b re-edited
   ftb.sv that the higher-numbered BP-067 had already produced. The
   RTL is correct and green; only the BP-067 Results record drifted.
   Filed here as a note, not a governance rule.

Impact. The Pacino flow's value is the PA converging on analysis and
emitting requested artifacts so Jeff can dictate and move on. Inventing
files, manufacturing process, and asserting unchecked claims raise the
supervision cost toward the cost of doing the work directly. The
methodology risk noted in handoff-053 persists and should weigh in any
assessment of the co-design experiment.

---

## Next Session (055)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-054.md (this file)
  CLAUDE.md
  and, if the next unit is bp_cluster or SC, the relevant planning docs.

The FTB is done; do not reopen it. The three FTB docs are COMPLETE and
load only as reference for cluster work. The natural next unit is
bp_cluster integration (which owns the deferred FTB items) or the SC
predictor (the last unbuilt predictor) -- Jeff's call.

Given the Postmortem Record: 055 should PRODUCE only what Jeff requests,
verify before asserting, and not manufacture wrap-up steps, process
rules, or files. Confirm the session is wrapping before writing a
handoff.

