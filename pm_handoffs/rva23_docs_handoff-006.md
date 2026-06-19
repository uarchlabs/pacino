<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Session Handoff: RVA23 Co-Design Documentation Project

This is the documentation sub-project for the RVA23 Co-design project.

This is a handoff from PM 6. The new session will be PM 7.
This file is named rva23_docs_handoff-006.md.

We are continuing the postmortem and blog series for the BPU co-design
track. Read this document fully before proceeding. Raise any
inconsistencies immediately.

NOTE: the context isolation pattern is only for the IA (Claude Code)
sessions. This is a documentation session using the PA (Claude.ai) pattern.

---

## BPU Blog Series Structure (Unchanged)

Four posts planned:

  BLOG_bpu_1_cluster_arch.md   -- Part 3 sessions. BP-001. SIGNED OFF.
  BLOG_bpu_2_history_ubtb.md   -- Parts 4 and 5 combined. Written PM 6.
  BLOG_bpu_3_loop_pred.md      -- Parts 6-9. Not yet written.
  BLOG_bpu_4_limits.md         -- Part 10 standalone. Not yet written.

---

## Work Completed This Session (PM 6)

### BLOG_bpu_2_history_ubtb.md -- Written, Pending Diagram Edits

The blog is written and substantially complete. Diagrams are produced
but flagged for user hand-editing before sign-off.
Current file is at:
  /mnt/user-data/outputs/BLOG_bpu_2_history_ubtb.md

Final section list:
  - The s1 Prediction Infrastructure
  - History Module Design
    - The Circular Buffer Model
    - Dual Prediction and the GHR
    - Folded Histories
    - Checkpoint and Rollback
  - uBTB Design
    - Structure and Lookup
    - Read-During-Write
    - Dual Prediction
    - Branch Type Encoding
  - Experiments BP-002, BP-003, and BP-003-FIX
  - Prompt Discipline
  - Experiment Summary
  - What Comes Next
  - Design Process Notes
    - Domain knowledge supplied by the user
    - What the PA contributed
    - What the prompt constrained versus what the IA filled in
    - The generalization
  - References ([1]-[2])

### Corrections Applied During PM 6

The following corrections were made during drafting and review:

T0 (TAGE base/BIM table) has no history and no folds. Added explicit
statement in Folded Histories section. T0 is not a consumer of
bp_history folded outputs.

Dual prediction and dual GHR bit shifts added as a dedicated subsection
(Dual Prediction and the GHR). When NUM_PRED_SLOTS=2, two bits written
to GHR per cycle in slot order. Fold update applies twice in sequence.

pred_pc introduced on first use as: the fetch block PC the cluster
presents to the history module each prediction cycle.

upd[u].valid introduced on first use as: the resolved update bundle
driven by the post-execute resolution path for prediction slot u.

pred_pc + 32 for slot 1 explained: slot 1 must form its s0 address
before slot 0 result is available. pred_pc + 32 is a speculative
stand-in for the sequential next 32-byte block. Overridden by s2 if
slot 0 is taken.

Encoding conflict attribution corrected: UBTB_BR_* localparams were
introduced by the PA-authored BP-003 prompt. The IA implemented them
as specified and flagged the conflict in results capture. The PA
identified and authored BP-003-FIX.

"s1 infrastructure complete" corrected to "first two modules of the
s1 prediction infrastructure are in place." The loop predictor also
fires at s1 and is not yet implemented.

Section heading changed from "What the user contributed" to "Domain
knowledge supplied by the user."

"locked" changed to "specified" throughout, in reference to decisions
in the bp_history interface specification.

Five errors attribution clarified: the user identified all five errors
during the pre-run review of the PA-authored draft.

### New Diagrams Produced (PM 6)

Four standalone SVGs produced, hardcoded colors, Inkscape and Jekyll
compatible:

  history_module.svg  -- structural block diagram of bp_history.
    Four structural blocks: ghr_mem, phr_mem, fold registers
    (bp_folded_hist_t), checkpoint register array. Inputs route
    to the specific block they feed. Outputs from the correct
    blocks. PHR-to-fold connection shown dashed and labeled
    deferred. Rollback_en routes to both ghr_mem and fold
    registers. No behavioral annotation.
    Stored at: /mnt/user-data/outputs/history_module.svg
    Referenced in blog as: ![History Module Structure](diagrams/history_module.svg)
    STATUS: flagged for user hand-editing.

  ghr_checkpoint.svg  -- circular buffer checkpoint and rollback.
    Intent: show the buffer as a strip of cells with pre- and
    post-checkpoint regions visually distinct, the checkpoint
    boundary marker, the rollback pointer restore arrow, and the
    fold recompute window extending backwards from the restored
    pointer (illustrating the contamination model for large H).
    Checkpoint storage shown as register array (not RAM).
    Contamination model note (TC8 reference).
    Stored at: /mnt/user-data/outputs/ghr_checkpoint.svg
    Referenced in blog as: ![GHR Checkpoint and Rollback](diagrams/ghr_checkpoint.svg)
    STATUS: flagged for user hand-editing.

  ubtb_structure.svg  -- uBTB prediction and update flow.
    Two-row layout: prediction path (top) and update path (bottom).
    Prediction: pred_pc -> Index/Tag Derivation -> SRAM Array ->
    Tag Match -> pred[s] output. Update: upd[] -> derivation ->
    hit/miss write -> SRAM. Read-during-write contract as
    highlighted bar between paths (TC10). SRAM block references
    entry diagram rather than restating field layout.
    Stored at: /mnt/user-data/outputs/ubtb_structure.svg
    Referenced in blog as: ![uBTB Structure](diagrams/ubtb_structure.svg)
    STATUS: flagged for user hand-editing.

  ubtb_entry.svg  -- uBTB entry bit-field strip.
    Horizontal rectangle subdivided into six named fields:
    valid (1b), tag (20b, PC[26:7]), br_type (3b, bp_br_type_e),
    target (40b, VA_WIDTH), br_taken (1b), carry (1b). Bit
    positions annotated at field boundaries. Per-field notes
    below strip. Total width 66b annotated.
    Stored at: /mnt/user-data/outputs/ubtb_entry.svg
    Referenced in blog as: ![uBTB Entry Fields](diagrams/ubtb_entry.svg)
    STATUS: flagged for user hand-editing.

All four diagrams placed within their relevant sections. ubtb_entry.svg
placed before the carry bit description in Structure and Lookup.
history_module.svg and ghr_checkpoint.svg placed at the end of the
Checkpoint and Rollback subsection.

### Design Discussions This Session

The following questions were raised and answered during PM 6. Relevant
context for future sessions:

ghr_mem is the circular buffer (the 256b register array). ghist_ptr
gives it orientation. Pre- and post-checkpoint cells are not cleared
on rollback; only the pointer is restored.

Fold recompute direction is backwards from the restored ghist_ptr.
Each fold reads H consecutive bits going back from the restored
pointer position. H differs per fold (T1: 8b, T2: 13b, T3: 32b,
T4: 119b etc.). Large H causes the recompute window to cross the
checkpoint boundary into post-checkpoint bits -- the contamination
model confirmed by TC8.

PHR uses the same circular buffer and checkpoint model as GHR.
PHR folding is deferred; no fold currently uses PHR bits.
The contamination question does not yet arise for PHR.

The checkpoint register array (ckpt_gptr[64], ckpt_pptr[64]) is
indexed by FTQ slot index (ckpt_idx, 6b). One-to-one correspondence
with FTQ slots. Write path: ckpt_wr_en + ckpt_idx + current pointer
values. Read path: redirect logic reads FTQ entry ghist_ptr/phist_ptr
and drives rollback inputs. The checkpoint array in bp_history stores
the same pointer values as the FTQ fast-path entry; they are redundant
by design so bp_history can restore its own internal state without
reading back from the FTQ.

The checkpoint array is register arrays (flip-flops), not SRAM.
64 x 13b = 832 flip-flops. bp_history contains no SRAM.

The history_module.svg block diagram went through several revisions.
Key structural insight reached: the four structural elements are
ghr_mem, phr_mem, fold registers, and checkpoint register array.
Rollback Recompute is a behavior not a structure and does not belong
as a block. Checkpoint Array is legitimate as a block because it is
a real register array with write and read ports.

---

## Open Items for PM 7

### BLOG_bpu_2_history_ubtb.md -- Diagram Sign-Off

The blog text is complete. The four diagrams are produced but
flagged for user hand-editing. PM 7 should confirm diagram status
at the start of the session. If diagrams are accepted as-is or
after edits, BPU-2 can be signed off.

### Begin BLOG_bpu_3_loop_pred.md

Source materials for BPU-3:
  - PA/IA session covering BP-004 (loop predictor)
  - Loop predictor interface specification if written
  - Session handoffs covering BP-004

BPU-3 covers Parts 6-9: the loop predictor design, implementation,
and verification. The loop predictor is the only predictor in this
cluster not derived from the Xiangshan Kunminghu architecture.

Search terms for PA session history:
  - "loop predictor BP-004"
  - "LP_TBL loop predictor iteration counter confidence"

---

## Current Blog File Status

### Signed off
  BLOG_bpu_1_cluster_arch.md -- complete

### Written, pending diagram sign-off
  BLOG_bpu_2_history_ubtb.md -- text complete, diagrams need user review

### Not yet started
  BLOG_bpu_3_loop_pred.md    -- Parts 6-9 (loop predictor)
  BLOG_bpu_4_limits.md       -- Part 10 (PA limits and failures)

### Carried Forward (unchanged from PM 3)
  rva23_docs_decoder_part2-pm-002.md
  rva23_docs_decoder_part3-pm-002.md
  BLOG_decoder_1_rva23_profile.md
  BLOG_decoder_2_scalar_to_alu.md
  BLOG_decoder_3_memory_to_closure.md
  rva23_docs_methodology-pm-001.md
  rva23_docs_tools-pm-001.md
  rva23_docs_decoder_part1-pm-001.md
  BLOG1.md

---

## Deferred Items (Unchanged from PM 3/4)

- BLOG_tools.md not yet written. Source: rva23_docs_tools-pm-001.md.
  Deferred until after TAGE/BPU work.
- PROJECT_STATUS.md and PROJECT_CORE.md not yet introduced in blog
  narrative.
- Series index page (index.md) deferred until series grows beyond
  three posts.
- Methodology blog (BLOG1.md) is a copy of rva23_docs_methodology-pm-001.md.
  Revised narrative version deferred until more sessions documented.

---

## Documentation Rules (Unchanged)

- No non-ASCII characters in any output except diagrams.
- Diagrams are SVG, stored as separate files, referenced in Markdown as
  ![alt](diagram.svg). No inline SVG in Markdown source.
- Acronyms expanded on first use in each document.
- Blog posts use YAML front matter with title, author, date, copyright.
- Copyright year: 2026.
- Series navigation block immediately after title, before first paragraph.
- Stats table header: "Experiment" not "Task ID".
- References minimal, only where genuinely needed.

---

## Suggested PM 7 Starting Point

1. Confirm BLOG_bpu_2_history_ubtb.md diagram status with user.
   If diagrams accepted, sign off BPU-2.

2. Retrieve BPU-3 source materials by searching PA session history
   for BP-004 loop predictor experiment and results.

3. Write BLOG_bpu_3_loop_pred.md covering the loop predictor.
   Follow the same structure conventions as BPU-1 and BPU-2.

