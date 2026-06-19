<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Session Handoff: RVA23 Co-Design Documentation Project

This is the documentation sub-project for the RVA23 Co-design project.

This is a handoff from a previous documentation session where we are doing
postmortem on co-design results for the RVA23 Co-Design project. This
document was generated in RVA23 Co-Design PM 2 (PM = postmortem). This
will be RVA23 Co-Design PM 3.

We will be continuing the postmortem in this and subsequent documentation
sessions. Please read and ask any clarifying questions. If there are
inconsistencies in this document or other pasted documents you should
speak up immediately. You will be asked to search previous chats for
details. I will provide the names of those chats as you request to manage
your context usage.

NOTE: the context isolation pattern is only for the IA (Claude Code)
sessions, this is a documentation session where the pattern is closer to
PA (Claude.ai). I mention this because in a previous session there was
some confusion about the isolation mechanism.

## Project Scope
The documentation sub-project will perform systematic documentation and
analysis of all RVA23 co-design sessions to extract methodology insights,
lessons learned, and potential publication material. Another aspect of
this is a whitepaper set which provides more narrative than reporting
results. Consider it a technical blog discussing what went right and wrong.

So far there are 29 phases planned in this analysis. This will change
as needed.

## Work Completed This Session (PM 2)

### Decoder Post-Mortems (Complete)
- **rva23_docs_decoder_part2-pm-002.md** — DECODE-005 through DECODE-007,
  vector ALU disambiguation (integer, FP, mask/reduce/permute)
- **rva23_docs_decoder_part3-pm-002.md** — DECODE-008 through DECODE-011,
  vector memory, pre-decode infrastructure, extension enable, closure

### Blog Posts (Complete, Revised)
- **BLOG_decoder_1_rva23_profile.md** — RISC-V profiles, RVA23 extension
  requirements, encoding formats, the decoder problem statement
- **BLOG_decoder_2_scalar_to_alu.md** — Scalar foundation through vector
  ALU disambiguation (DECODE-001 to DECODE-007), methodology observations,
  stats table
- **BLOG_decoder_3_memory_to_closure.md** — Memory disambiguation through
  decoder closure (DECODE-008 to DECODE-011), pre-decode architecture,
  extension enable, what comes next, stats table

### Key Content Decisions Made This Session
1. **Three-blog structure** adopted for decoder series: context-setting,
   implementation part 1, implementation part 2
2. **Stats tables** added to Blog 2 and Blog 3 with runtimes for all
   11 DECODE experiments
3. **ext_enable_t framing** clarified: not required for RVA23 compliance,
   added as a validation and silicon bring-up tool
4. **Branch pre-decode** correctly characterized: may_be_branch hint in
   predecode_pkt_t is a placeholder; full branch detection pre-decode
   stage is deferred to fetch unit design phase
5. **DECODE-010 pre-decode block** correctly described as combinational,
   not a registered pipeline stage; clk/rstn ports present for future
   register slice insertion without interface disruption
6. **Verilator 5.020 quirk file** (docs/observations/verilator_5020_notes.md)
   noted as referenced in DECODE-010 results but not confirmed to exist
   in the repo — blog references removed, finding described in prose only
7. **riscv-opcodes** introduced explicitly as the ground-truth encoding
   reference, installed locally in the project file system
8. **PA/IA balance** observation added to Blog 3: decoder tasks placed
   more research load on IA than typical because riscv-opcodes was
   accessible to Claude Code directly

### Source Material Used This Session
All decoder experiment prompts and results provided directly:
- DECODE-005 through DECODE-011 prompt/results files (pasted by user)
- rva23_docs_decoder_part1-pm-001.md (pasted by user)
- Supplementary searches in "RVA23 Co-Design Part 1" for arc and
  closure data

## Remaining Work (Sessions 3-29)

### Immediate Next Priorities
- **Diagrams**: Two diagrams identified as high value but not yet created:
  1. Dual-packet output architecture (Blog 2) — three parallel output
     streams from the decoder with type labels
  2. Opcode/width-field encoding split for vector vs scalar FP memory
     (Blog 3) — the 0x07/0x27 disambiguation rule
- **Tools documentation**: rva23_docs_tools-pm-001.md was created in PM 1
  but the tools blog (BLOG_tools.md) has not been written
- **Branch predictor sessions**: Parts 11-25 identified as methodologically
  rich; TAGE implementation likely the most publication-worthy content
- **Methodology blog**: BLOG1.md was a copy of rva23_docs_methodology-pm-001.md;
  a revised narrative version may be warranted after more sessions are
  documented and methodology evolution is clearer

### Known Open Items Carried Forward
- Diagrams for Blog 2 and Blog 3 (not blocked, just not done)
- PROJECT_STATUS.md and PROJECT_CORE.md have not yet been introduced
  in the blog narrative — these are referenced in the co-design sessions
  and deserve a mention somewhere in the methodology discussion
- NOP filtering and instruction fusion: not yet scoped, flagged as future
  work in Blog 3
- Per-instruction Zbb/Zbs/Zfhmin/Zfa enable gating: deferred, flagged
  in Blog 3
- DECODE-012 (frontend pre-decode restructuring): deferred to fetch unit
  design phase, noted in Blog 3

### Documentation Templates Established
- **Technical Implementation**: Problem → Approach → Results → Decisions
  → Lessons
- **Methodology Innovation**: Challenge → Solution → Validation → Impact
- **Tools & Validation**: Problem → Framework → Implementation →
  Integration
- **Blog series**: Context post → Implementation part 1 → Implementation
  part 2, with stats tables and "what comes next" section in final post

### Documentation Rules From Now On
- Avoid non-ASCII characters in all output. This includes postmortems,
  blogs and documentation sub-project handoffs
- This rule excludes diagrams. Diagram format will be defined in the
  session these diagrams are created.
- When an acronym is introduced for the 1st time in a document it should 
  be expanded e.g. "needed by the BPU (Branch Prediction Unit) and FTQ (
  Fetch Target Queue)" 


### SEO Guidelines

The target audience is narrow and technical (RISC-V implementers,
microarchitecture engineers, AI-assisted design researchers). SEO should serve
discoverability within that community, not broad traffic.

    - Titles and headings must use canonical technical terms exactly as the community searches them: "RVA23", "RISC-V", "TAGE branch predictor", "RTL co-design", not paraphrases
    - Acronym expansion rule (see Documentation Rules) passively serves SEO by indexing both the abbreviation and the full term
    - Meta description — each blog post should have one or two sentences summarizing the technical content precisely; this is what appears in search results
    - Cross-linking — posts in a series must link to each other explicitly; this matters for crawlability on GitHub Pages
    - Keyword density targets, readability scores, and schema markup are out of scope for this audience

### Analysis Framework
For each session group, extract:
1. **Technical Achievements** — What was built and how
2. **Methodological Innovations** — Process improvements and new techniques
3. **Design Decisions** — Architectural choices and rationale
4. **Lessons Learned** — What worked, what failed, why
5. **AI Co-design Insights** — Effectiveness of different prompting
   approaches

### Potential Publication Themes Emerging
- **AI-Assisted Hardware Design Methodology** — The dual assistant
  architecture and experimental framework
- **Systematic Processor Co-design** — Technical progression from decoder
  through branch predictor
- **Validation Framework Integration** — Third-party verification in
  AI-assisted design flows
- **Prompt Engineering for Hardware** — Effective strategies for RTL
  generation, including read-before-write discipline and debt scheduling

## Session Approach for PM 3

### Suggested Starting Point
Diagrams for Blog 2 and Blog 3 are the most contained next task and
would complete the decoder blog series before moving to new phases.
After that, the branch predictor work (Parts 11-25) is the highest-value
content for methodology publication purposes.

### Process
1. **Session Selection** — Choose next session(s) based on content
   richness and methodological interest
2. **Content Analysis** — Search and extract key technical and
   methodological content
3. **Documentation Creation** — Apply established templates to create
   focused post-mortems
4. **Pattern Recognition** — Identify recurring themes and evolving
   methodology
5. **Integration Planning** — Consider how individual session analyses
   build toward larger narratives

### Tools Available
- `conversation_search` for finding specific technical content and
  decisions
- `recent_chats` for chronological progression analysis
- Established post-mortem document templates
- Pattern analysis from Parts 1-3 as baseline

### Success Metrics
- Clear technical narrative extraction from each session
- Methodology evolution documentation
- Lessons learned that could benefit future AI-assisted design projects
- Foundation material for potential publications or best practices guides

## Current Status
**Phase 1 Complete**: RVA23 Co-Design Part 1 fully documented (4 files)
**Phase 2 Complete**: Decoder track fully documented (2 postmortems,
  3 blogs, all DECODE-001 through DECODE-011)
**Phase 3 Ready**: Diagrams and branch predictor sessions next
**Templates Stable**: Consistent format proven across decoder track

## Files Created or Revised This Session
### New Post-Mortems
- rva23_docs_decoder_part2-pm-002.md
- rva23_docs_decoder_part3-pm-002.md

### New/Revised Blogs
- BLOG_decoder_1_rva23_profile.md (revised from PM 2 draft)
- BLOG_decoder_2_scalar_to_alu.md (revised from PM 2 draft)
- BLOG_decoder_3_memory_to_closure.md (revised from PM 2 draft)

### Carried Forward from PM 1
- rva23_docs_methodology-pm-001.md
- rva23_docs_tools-pm-001.md
- rva23_docs_decoder_part1-pm-001.md
- BLOG1.md

