<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 057
Written by Claude.ai at end of session-056.
Date: 2026-06-28

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

Session-056 was the SC planning session. SC is the last unbuilt
predictor and was greenfield (no decisions or interfaces doc). The
session produced a draft sc_decisions.md (Jeff-authored, PA-reviewed)
and the SC changes to bp_defines_pkg.sv and bp_structs_pkg.sv. The SC
counter-update rule and the BrIMLI mechanism were verified against
primary sources (fetched, not recalled). No RTL. sc_interfaces.md and
the other SC planning docs are not written.

The SC authority doc:
  planning/arch/sc_decisions.md (Draft, session-056)

---

## Read This First

sc_decisions.md is a DRAFT and is Jeff-authored. It defines the SC as
five pure-counter tables (ST0-ST4, no tags, ST4 = BrIMLI), a dynamic
(O-GEHL) threshold, a two-corner chooser, and the BrIMLI register and
index. The package files carry the matching parameters and structs.

The two facts that were verified against source this session, because
recall was not trusted on either:

  1. SC counter-update gate. Train the SC counters when
     (SC's own prediction was wrong) OR (|sum| < threshold), moving
     toward the resolved direction, saturating. NOT gated on TAGE
     mispredict, NOT on whether SC overrode. This is the perceptron
     training rule. Confirmed against: gem5 statistical_corrector.cc
     (Seznec port), the Jimenez-Lin perceptron paper (TOCS 2002, §4.2),
     Seznec 2011 MICRO §5.3, and the cookbook predictor.h
     UpdatePredictor. sc_decisions.md s8 encodes this
     (sc_wrong || sc_lo_upd).

  2. BrIMLI. From the cookbook predictor.h (HistoryUpdate):
     last_back_pc holds PC[15:6] of the last taken backward branch;
     br_imli counts consecutive taken backward branches in the same
     region, saturating; on a region change bb_hist shifts in the old
     region and br_imli resets; the index value is
     f_brimli = (br_imli==0) ? phr : br_imli, hashed pc ^ f ^ (pc>>4).
     sc_decisions.md s9 encodes this; br_imli_mode_e adds two perf-eval
     variants (PHR-only, IMLI-only).

The SC sum currently includes tage_extd_ctr at weight 1. The
8x-weighted TAGE term is deferred for timing (TD #86); revisit at PD /
perf.

Next session opens with a fresh analysis of sc_decisions.md and the two
package files. A short list of concrete items observed in 056 but not
fixed is in Open Work -- confirm each in the fresh pass rather than
taking this list on faith.

---

## Session Summary

1. sc_decisions.md drafted (Jeff). Covers: context/doc map; overview;
   pipeline notation (planning s-stage, RTL p-stage); two operation
   phases (predict = RAM read, update = RAM write, no RMW); five-table
   structure; parameter and struct reference; SC control local state;
   prediction-phase operation (index, read, sum, chooser, meta
   capture); update-phase operation (gate, threshold adaptation,
   counter update, chooser training); helper functions; BrIMLI; reset
   init.

2. SC counter-update rule verified against source (see Read This
   First). The earlier task-text equation gated on cond_mispredict /
   sc_override / tage_pred_tkn; none of those appear in the source
   gate. Settled to (SC-wrong) OR (|sum| < threshold), toward resolved.

3. BrIMLI mechanism taken from cookbook predictor.h (see Read This
   First). Region = PC[15:6]; last_back_pc carries a valid bit;
   bb_hist mixes the leaving region; index hashes f_brimli with PC.

4. Dynamic threshold (O-GEHL). TC adaptation counter raises the
   threshold on SC-wrong, lowers it when training fired on a low-sum
   correct; seed SC_THRSH_MID. References: Storage-Free Confidence
   (HPCA 2011), O-GEHL (ISCA 2005).

5. Two-corner chooser. SC wins except: (TAGE high-conf AND SC very-low
   sum) and (TAGE medium-conf AND SC very-very-low sum). Each corner
   has its own saturating counter (choose_hi_vlo, choose_med_vvlo),
   trained on which of SC/TAGE matched the outcome.

6. Package changes. bp_defines_pkg.sv: SC_NUM_TABLES=5 (SC_NUM_ALL_TBLS
   removed), dynamic threshold params (SC_THRSH_*), SC_TC_BITS,
   SC_LSUM_BITS, SC_CHOOSER_*; SC_LO/HI_THRESHOLD removed.
   bp_structs_pkg.sv: sc_pred_meta_t and sc_upd_inp_t populated;
   bp_sc_meta_t and cond_pred_meta_t/cond_pred_upd_inp_t commented out;
   bp_sc_chooser_e and br_imli_mode_e added; tage_pred_meta_t gains
   tage_provider_ctr and tage_extd_ctr.

7. Technical debt added #85-#92 (captured in PROJECT_STATUS): bp_structs
   field-share review (#85); 8x TAGE term in SC sum (#86); TAGE
   medium/weak + strong mapping (#87); TAGE provider_ctr/extd_ctr
   generation (#88); FTB branch_range[15:6] (#89) and backwards sign
   (#90); bpc PC routing p0->p2 (#91); SC phr[9:0] capture sc_phr_p2
   (#92).

8. PA review of the draft. Caught the sat_ch CHOOSE_MED argument typo,
   get_br_imli_idx missing the PC hash, the value1..4 reading ST0,
   and the four-section "## 8" / duplicate "## 4" numbering. Also
   raised four low-value items that were withdrawn (see Postmortem).

---

## What Was Accomplished

  - sc_decisions.md drafted (five counter tables, dynamic threshold,
    two-corner chooser, BrIMLI, update rule, reset init).
  - SC counter-update gate verified against gem5 SC source, the
    Jimenez-Lin perceptron paper, Seznec 2011 MICRO, and cookbook
    predictor.h.
  - BrIMLI register/update/index taken from cookbook predictor.h.
  - bp_defines_pkg.sv and bp_structs_pkg.sv SC changes landed (params,
    structs, enums; merged cond_pred_* structs retired).
  - TD #85-#92 recorded.

---

## Open Work

### SC -- not written (next, blocks RTL)

  - planning/interfaces/sc_interfaces.md (SC top-level ports + phase
    IO; the s2-in / s3-out timing; dual-slot).
  - planning/interfaces/sc_table_interfaces.md (sc_table ports).
  - planning/arch/sc_table_hash_rules.md (sc_idx_hash and
    get_br_imli_idx -- referenced by sc_decisions.md, not defined).
  - planning/arch/sc_cntrl_ctr_update_rules.md (the update gate as a
    rule table, mirroring tage_cntrl_ctr_update_rules.md).
  - planning/arch/sc_table_entry_formats.md, sc_cntrl_decisions.md
    (needed? confirm), sram_init (SC), sc_tb_decisions.md,
    sc_coverage_plan.md.

### SC -- items observed in 056, confirm in the 057 fresh analysis

  These were noted while reviewing the manual draft and are not yet
  fixed. Verify each against sc_decisions.md and the packages.

  - Section numbering: four "## 8" sections and a duplicate "## 4".
  - sat_sc references SC_CTR_MIN / SC_CTR_MAX; neither is defined in
    bp_defines_pkg.sv.
  - branch range field tangle: the prediction phase assigns
    sc_pred_meta.pc_range, but sc_pred_meta_t has no pc_range field
    (it has pc[VA_WIDTH-1:0]); section 9 reads
    sc_upd_inp.sc_pred_meta.branch_range (no such field) and also
    sc_upd_inp.sc_pred_meta.pc[15:6]; sc_upd_inp_t carries
    branch_range[15:6] at top level. Reconcile to one source.
  - sc_pred_meta.sc_tage_pred_tkn = tage_pred_tkn (unqualified;
    elsewhere tage_pred_meta.tage_pred_tkn).
  - bp_structs_pkg.sv enums: br_imli_mode_e missing a comma after
    IDX_IMLI_ONLY = 2'b10; bp_sc_chooser_e has a trailing comma after
    the last member. Both will not compile as written.
  - SC_IMLI_INDEX_BITS still in bp_defines_pkg.sv though sc_imli_idx
    was unified into sc_upd_idx (leftover).

### SC -- prerequisites (TD, other units)

  - #87/#88 TAGE: SC prediction sum and chooser consume
    tage_pred_medium and tage_extd_ctr; TAGE must emit them. Struct
    fields for #88 added; generation logic not written; medium/weak
    (#87) not added.
  - #89/#90 FTB: branch_range[15:6] and backwards-branch sign for SC
    BrIMLI maintenance.
  - #91/#92 bpc: route PC p0->p2 to SC; capture phr[9:0] as sc_phr_p2.
  - #84 end-to-end fold check now also covers SC ST1-ST3 (additional
    consumers of the bp_history folds).

### bp_arb_spec.md reconciliation

  - §6 merged TAGE+SC metadata / shared-UQ model is superseded for SC
    (cond_pred_meta_t and cond_pred_upd_inp_t are commented out; SC
    has its own structs). Reconcile §6 when sc_interfaces.md is
    written.

### Carried infra (Jeff's priority call, independent of SC)

  - bp_history close-out bookkeeping (from handoff-056, confirm done):
    commit/push decisions.md + PROJECT_STATUS; s6.6 sha (#83);
    BP-072/073 status checkboxes; retire versions/bp_history.sv.
  - #43 ITTAGE CTR 3b->2b, #75 sim_ittage_fast, #77 path scrub,
    #67/#68 sram_init non-fast, #38 covergroup #7099 re-check.

---

## SC State: PLANNING (draft decisions doc)

sc_decisions.md is drafted and the packages carry the SC params and
structs. The update rule and BrIMLI are source-verified. RTL is not
started; sc_interfaces.md and the other SC docs are not written; the
TAGE/FTB/bpc prerequisites (#87-#92) are open. The draft has the
specific open items listed above to settle in the 057 fresh analysis.

---

## Next Session (057)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-057.md (this file)
  CLAUDE.md
  planning/arch/sc_decisions.md
  rtl/.../bp_defines_pkg.sv
  rtl/.../bp_structs_pkg.sv

Start with a fresh analysis of sc_decisions.md against the two package
files. Work the "items observed in 056" list above and anything else
the fresh pass finds; confirm each against the doc and packages before
asserting it -- do not carry this list as fact. After the doc and
packages are consistent, the SC interfaces doc and the SC table-hash
doc are the next writes, then IA task generation for SC RTL.

When reviewing or editing the SC docs, check each comment against the
doc/packages before emitting it, audit the whole touched section (not
just changed lines), report facts without rankings or significance
claims unless asked, and verify against source before asserting OR
conceding.

---

## Postmortem Record -- PA performance (session-056)

Continuing the trend log (052/053 asserting unchecked claims; 054
over-asking; 055 one under-audited carried-forward line). 056 was a
weak session for the PA; the misses below are larger and more frequent
than 055.

1. Verify-before-asserting failed in both directions on the SC
   update rule. The PA first overstated the rule ("SC counters update
   on every branch unconditionally"), then, under user pushback,
   conceded the user's TAGE-mispredict/override-gated equation -- twice
   -- before pulling any source. Only after fetching gem5's SC, the
   Jimenez-Lin paper, the 2011 MICRO paper, and the cookbook
   predictor.h was the actual gate established (SC-wrong OR |sum| <
   threshold), which matched neither the overstatement nor the
   conceded equation. The discipline that the project runs on -- pull
   the source before asserting -- was applied late. It should have been
   first, before either asserting or conceding.

2. Serial-vs-parallel thrash on SC pipeline integration. The PA had
   the serial relationship right, flipped to "parallel" by over-reading
   bp_cluster's pipeline-staging notation as the global timeline and
   asserting it superseded bp_arb_spec, then was corrected back to
   serial. Same stale-vs-authority error pattern as the 055 s10 line,
   here producing a wasted round trip.

3. Imported another unit's framing onto SC. The PA carried TAGE's
   arbitration apparatus (PQ/UQ/credit arbiter/response buffer and a
   "compete for prediction RAM access" line) into the SC interface
   draft, where none of it applies -- SC owns its tables, shares no
   RAM. It also conflated "serial" with "RAM sharing." Fabricated
   constraint in a draft; removed when challenged.

4. Jargon after an explicit instruction to stop. "honest question,"
   "paper over," "gloss," "matters most" -- each used after the user
   had said plain words only. Repeated offenses, not a single slip.

5. Low-value review output. On the manual SC draft the PA returned
   eight items; four were wrong or useless (a TD already marked as TD;
   a parameter the user had already decided with the numbers present;
   a width already calculated and declared at the point of use; and a
   false syntax error claiming logic [15:6] is illegal). Fifty percent
   noise the user had to filter. Separately, an unsupported "matters
   most" ranking and a caution on an already-decided width -- both
   opinions/rankings the user has said not to volunteer.

What held: when source was actually pulled, the analysis was correct
and decisive -- the gem5 SC gate, the perceptron rule in print, the
cookbook BrIMLI mechanism, and the real draft defects (sat_ch arg,
get_br_imli_idx hash, value1..4 reading ST0, section numbering). The
output the user kept all came from source or from checking the doc
against itself.

Pattern to carry into 057:
  - Pull the source before asserting OR conceding. Confidence and
    user pushback are both signals to check, not to capitulate.
  - Do not import one unit's framing/vocabulary onto another. State
    only what the unit's own design supports.
  - In reviews, check each comment against the doc/packages before
    emitting it. A withdrawn comment costs the user a filter pass.
  - Facts only. No rankings, no significance claims, no cautions on
    decided parameters, unless asked.
  - No jargon. Plain words.

