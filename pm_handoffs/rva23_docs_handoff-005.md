<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Session Handoff: RVA23 Co-Design Documentation Project

This is the documentation sub-project for the RVA23 Co-design project.

This is a handoff from PM 5. The new session will be PM 6.
This file is named rva23_docs_handoff-005.md.

We are continuing the postmortem and blog series for the BPU co-design
track. Read this document fully before proceeding. Raise any
inconsistencies immediately.

NOTE: the context isolation pattern is only for the IA (Claude Code)
sessions. This is a documentation session using the PA (Claude.ai) pattern.

---

## BPU Blog Series Structure (Unchanged)

Four posts planned:

  BLOG_bpu_1_cluster_arch.md   -- Part 3 sessions. BP-001. SIGNED OFF.
  BLOG_bpu_2_history_ubtb.md   -- Parts 4 and 5 combined. Not yet written.
  BLOG_bpu_3_loop_pred.md      -- Parts 6-9. Not yet written.
  BLOG_bpu_4_limits.md         -- Part 10 standalone. Not yet written.

---

## Work Completed This Session (PM 5)

### BLOG_bpu_1_cluster_arch.md -- Signed Off

The blog is complete and signed off. All PM 4 open items resolved.
Current file is at:
  /mnt/user-data/outputs/BLOG_bpu_1_cluster_arch.md

Final section list:
  - A New Aspect of Co-Design
  - Predictor Hierarchy
  - Predictor Operation
  - Redirect Architecture (rewritten, direction/target separated)
  - Return Address Stack Design
  - FTQ Entry Split
  - Predictor Parameter Reference
  - Interface First: BP-001
  - Prompt Discipline and AI Leverage
  - Experiment Summary
  - What Comes Next
  - Design Process Notes (NEW -- added PM 5)
  - References (populated with [1]-[11])

### Changes Applied in PM 5

Redirect Architecture section fully rewritten. Now has three
subsections: Direction, Target, Pipeline Staging. Direction and
target concerns are cleanly separated throughout. No paragraph
mixes both.

Dual prediction paragraph added to Predictor Hierarchy section.
States: controlled by NUM_PRED_SLOTS elaboration parameter, dual
is the default, single is for silicon debug only, two independent
update channels when dual.

Citations inserted:
[1] riscv-opcodes, https://github.com/riscv/riscv-opcodes, accessed 2026.05.01

[2] Wang, Kaifan, et al. "XiangShan open-source high performance RISC-V processor design and implementation." Journal of Computer Research and Development 60.3 (2023): 476-493.

[3] Zhao, Jerry, et al. "Sonicboom: The 3rd generation berkeley out-of-order machine." Fourth Workshop on Computer Architecture Research with RISC-V. Vol. 5. International Symposium on Computer Architecture Valencia, 2020.

[4] Grayson, Brian, et al. "Evolution of the samsung exynos cpu microarchitecture. In 2020 ACM/IEEE 47th Annual International Symposium on Computer Architecture (ISCA)." IEEE, may. 2020.

[5] 6th Championship Branch Prediction (CBP2025), in conjunction with ISCA-52, Tokyo, Japan, June 21, 2025. Organizers: R. Sheikh and S. Jain (ARM), https://ericrotenberg.wordpress.ncsu.edu/cbp2025/ , accessed 2026.05.01

[6] 5th JILP Workshop on Computer Architecture Competitions (JWAC-5): Championship Branch Prediction (CBP-5), in conjunction with ISCA-43, Seoul, South Korea, June 2016. URL: https://jilp.org/cbp2016/ , accessed 2026.05.01

[7] A. Seznec and P. Michaud, "A Case for (Partially) TAgged GEometric History Length Branch Prediction," Journal of Instruction Level Parallelism, vol. 8, Feb. 2006.

[8] A. Seznec, "TAGE-SC-L Branch Predictors Again," in JWAC-5: Championship Branch Prediction (CBP-5), June 2016, Seoul.

[9] A. Seznec, "A 64-Kbytes ITTAGE Indirect Branch Predictor," in JWAC-2: Championship Branch Prediction, June 2011.

[10] Tan Hongze and Wang Jian, "A Return Address Predictor Based on Persistent Stack," Journal of Computer Research and Development, vol. 60, no. 6, pp. 1337–1345, 2023. DOI: 10.7544/issn1000-1239.202111274

[11] A. Seznec, "TAGE: an Engineering Cookbook," Inria Technical Report RR-9561, November 2024. Available: https://hal.science/hal-04804900

Design Process Notes section added. Covers: what the user
contributed, what the PA contributed, what the BP-001 prompt
constrained vs what the IA filled in, and a generalization
paragraph for domain-expert readers. Closing sentence:
"Evidence from this session indicates the methodology works
effectively with clear separation of roles."

LP duplicate paragraph removed (was an artifact of earlier
drafting).

Diagram alt text corrected: push/pop diagram now reads
![RAS Push and Pop](diagrams/ras_push_pop.svg).

ITTAGE design choice paragraph: left as written (3rd cycle
design was correct for the BP-001 state; bp_cluster.md has
since been updated to direct VA storage but the blog
accurately reflects the BP-001 timeline).

### New Diagrams Produced (PM 5)

Two standalone SVGs produced, hardcoded colors, Inkscape and
Jekyll compatible:

  ras_structure.svg  -- dual-stack structural diagram.
    Shows speculative stack (persistent linked circular array,
    48 entries) with TOSR/TOSW/BOS pointer labels and NOS links,
    commit stack (conventional circular), and FTQ slot checkpoint
    box (TOSR/TOSW/BOS, 6b each). Post-execute vs retirement
    update annotations.
    Stored at: /mnt/user-data/outputs/ras_structure.svg
    Referenced in blog as: ![RAS Structure](diagrams/ras_structure.svg)

  ras_push_pop.svg -- push/pop operation diagram.
    Two-section diagram. Push: before (3 entries, TOSR/TOSW at C)
    and after (4 entries, new entry D at top, D->C NOS link
    highlighted). Pop: before (same as push after) and after
    (TOSR follows NOS to C, D preserved/grayed). NOS links
    staggered to avoid overlap. "data preserved" conveyed by
    gray style on D in pop-after.
    Stored at: /mnt/user-data/outputs/ras_push_pop.svg
    Referenced in blog as: ![RAS Push and Pop](diagrams/ras_push_pop.svg)

Both diagrams are placed within the Return Address Stack Design
section, ras_structure.svg before the persistent stack description,
ras_push_pop.svg after it.

### Reference Research Completed (PM 5, all inserted)

The following citations were researched and confirmed. 

[1] riscv-opcodes, https://github.com/riscv/riscv-opcodes, accessed 2026.05.01

[2] Wang, Kaifan, et al. "XiangShan open-source high performance RISC-V processor design and implementation." Journal of Computer Research and Development 60.3 (2023): 476-493.

[3] Zhao, Jerry, et al. "Sonicboom: The 3rd generation berkeley out-of-order machine." Fourth Workshop on Computer Architecture Research with RISC-V. Vol. 5. International Symposium on Computer Architecture Valencia, 2020.

[4] Grayson, Brian, et al. "Evolution of the samsung exynos cpu microarchitecture. In 2020 ACM/IEEE 47th Annual International Symposium on Computer Architecture (ISCA)." IEEE, may. 2020.

[5] 6th Championship Branch Prediction (CBP2025), in conjunction with ISCA-52, Tokyo, Japan, June 21, 2025. Organizers: R. Sheikh and S. Jain (ARM), https://ericrotenberg.wordpress.ncsu.edu/cbp2025/ , accessed 2026.05.01

[6] 5th JILP Workshop on Computer Architecture Competitions (JWAC-5): Championship Branch Prediction (CBP-5), in conjunction with ISCA-43, Seoul, South Korea, June 2016. URL: https://jilp.org/cbp2016/ , accessed 2026.05.01

[7] A. Seznec and P. Michaud, "A Case for (Partially) TAgged GEometric History Length Branch Prediction," Journal of Instruction Level Parallelism, vol. 8, Feb. 2006.

[8] A. Seznec, "TAGE-SC-L Branch Predictors Again," in JWAC-5: Championship Branch Prediction (CBP-5), June 2016, Seoul.

[9] A. Seznec, "A 64-Kbytes ITTAGE Indirect Branch Predictor," in JWAC-2: Championship Branch Prediction, June 2011.

[10] Tan Hongze and Wang Jian, "A Return Address Predictor Based on Persistent Stack," Journal of Computer Research and Development, vol. 60, no. 6, pp. 1337–1345, 2023. DOI: 10.7544/issn1000-1239.202111274

[11] A. Seznec, "TAGE: an Engineering Cookbook," Inria Technical Report RR-9561, November 2024. Available: https://hal.science/hal-04804900

---

## Open Items for PM 6

### Begin BLOG_bpu_2_history_ubtb.md

Source materials for BPU-2:
  - Session handoffs 003 and 004 (search PA session history)
  - bp_history_interfaces.md (search PA session history for
    "bp_history port semantics checkpoint rollback")
  - ubtb_interfaces.md (search PA session history for
    "uBTB prediction update port semantics timing contracts")
  - BP-002 experiment file (history module)
  - BP-003 experiment file (uBTB)

BP-002 and BP-003 results summary (from session-006 handoff):
  - bp_history.sv: GHR/PHR circular buffers, 27 folded histories,
    checkpoint and rollback. PASS.
  - ubtb.sv: 256-entry 4-way associative, hit/miss/replacement,
    TC1-TC10 passing.

BPU-2 covers the s1 prediction infrastructure: the history module
and the uBTB as the first prediction-path module.

---

## Current Blog File Status

### Signed off
  BLOG_bpu_1_cluster_arch.md -- complete

### Not yet started
  BLOG_bpu_2_history_ubtb.md -- Parts 4 and 5 (history + uBTB)
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

## Suggested PM 6 Starting Point

1. Retrieve BPU-2 source materials by searching PA session history
   for bp_history and uBTB interface specs and BP-002/BP-003 results.

2. Write BLOG_bpu_2_history_ubtb.md covering the history module and
   uBTB. Follow the same structure conventions as BPU-1.

