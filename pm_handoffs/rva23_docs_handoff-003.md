# Session Handoff: RVA23 Co-Design Documentation Project

This is the documentation sub-project for the RVA23 Co-design project.

This is a handoff from a previous documentation session where we are doing
postmortem on co-design results for the RVA23 Co-Design project. This
document was generated in RVA23 Co-Design PM 3 (PM = postmortem). This
new session will be RVA23 Co-Design PM 4.

Hand off files are named for the current session. This was generted in
PM 3 so the file is rva23_docs_handoff-003.md. It's possible this conflicts
with info below. If so please mention this. 

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

## Work Completed This Session (PM 3)

### Diagrams (Complete)
All four diagrams are SVG files, stored as separate files, referenced in
Markdown as ![alt](path/to/diagram.svg). No inline SVG in Markdown source.

- **diagram_scalar_encoding_formats.svg** — 32-bit base formats (R/I/S/B/U/J)
  and 16-bit compressed RVC formats (CR/CI/CSS/CIW/CL/CS/CB/CJ), sourced
  directly from the attached RISC-V reference card PDF. Belongs in Blog 1.
- **diagram_vector_encoding_formats.svg** — All seven vector ALU (Application
  Level Unit) funct3 groups, vector configuration instructions (vsetvl,
  vsetvli, vsetivli), and vector memory addressing modes. Belongs in Blog 1.
  Verified against riscv-opcodes/extensions/rv_v via Claude Code. All funct3
  values, memory opcodes, mop values, and EEW width values confirmed correct.
  One prompt wording error identified and resolved (vsetvl bit range
  description); diagram itself is correct.
- **diagram_dual_packet_output.svg** — Three parallel output streams from
  the decoder with type labels and steering signal. Belongs in Blog 2,
  placed after the code block showing signal declarations and before the
  prose explaining the invariant.
- **diagram_opcode_width_disambiguation.svg** — The 0x07/0x27 disambiguation
  rule, width field split between vector EEW and scalar FP precision values.
  Belongs in Blog 3, placed after the paragraph listing the width field
  values and before the implementation paragraph about the outer if guard.

### Diagram Placement Recommendations
- Blog 1: scalar format diagram first, then vector format diagram, both
  placed after the extension list introduction and before the decoder
  problem statement paragraph
- Blog 2: dual-packet diagram after the signal declaration code block,
  before "Every slot produces output in both bundles"
- Blog 3: disambiguation diagram after the width field value list paragraph,
  before the surgical fix implementation paragraph
- General rule: figure comes after the prose that motivates it, not before

### Blog Reviews and Corrections (PM 3)
Blog 2 opening paragraph corrections applied:
- "tasks" changed to "experiments" for consistency with methodology language
- "DECODE-001 thru DECODE-11" corrected to "DECODE-001 through DECODE-011"
- riscv-opcodes scope broadened from "all funct6 and funct3 values" to
  "all instruction encodings" to correctly reflect its use throughout

Blog 1 profile paragraph corrections noted:
- "To be precise we are building" needs comma: "To be precise, we are building"
- "64bit" needs hyphen: "64-bit"
- "targetting" corrected to "targeting"
- "server class machines" needs hyphen: "server-class machines"
- ISA (Instruction Set Architecture) needs expansion on first use in Blog 1

### Reference Strategy Established
Blog posts are not journal publications. References should be minimal and
only where genuinely needed. For the decoder blog series:
- Cross-links between posts in the series are internal links, not formal
  references
- riscv-opcodes warrants one formal reference entry as it is the cited
  ground truth for all implementation work:
  [1] RISC-V International, "riscv-opcodes," GitHub,
      https://github.com/riscv/riscv-opcodes
- RVA23 profile spec reference belongs in Blog 1, not repeated in Blog 2
- No other references needed for the decoder series

### Author, Copyright, Date and Navigation Established
YAML front matter block at the top of each Markdown file:

  ---
  title: "post title here"
  author: Jeff Nye
  date: YYYY-MM-DD
  copyright: "Copyright 2025 Jeff Nye"
  ---

Series navigation block placed immediately after the title, before the
first paragraph:

  *This is part N of a three-part series.
  [Part 1: title](blog1.md) | [Part 2: title](blog2.md) | ...*

Stats table header "Task ID" changed to "Experiment" for consistency with
"experiments" used throughout the blog text.

### Repository Updates (PM 3)
- atemp repo established as the new working repository
- riscv-opcodes installed as a git submodule at tools/riscv-opcodes
- .claude/settings.json updated for atemp paths, trimmed to minimum
  permissions needed for current work (riscv-opcodes read, python3, make,
  statusline)
- spike submodule deferred until needed; spike is large and has nested
  submodules

### Publishing Platform
- Target: GitHub Pages (jeffnye-gh.github.io)
- Static site generator: Jekyll with minima theme
- Minimum _config.yml: theme, title, author fields
- Preview options: GRIP locally (already installed), GitHub repo view,
  or GitHub Pages after Jekyll setup

## Remaining Work (Sessions 4-29)

### Immediate Next Priorities
- **TAGE/BPU sessions**: Parts 11-25 identified as methodologically rich;
  TAGE (TAgged GEometric history length predictor) implementation is the
  most publication-worthy content. User will gather materials before PM 4.
- **Tools blog**: BLOG_tools.md has not been written. Source material
  rva23_docs_tools-pm-001.md exists from PM 1. Deferred until after
  TAGE/BPU work.

### Known Open Items Carried Forward
- PROJECT_STATUS.md and PROJECT_CORE.md have not yet been introduced
  in the blog narrative — these are referenced in the co-design sessions
  and deserve a mention somewhere in the methodology discussion
- NOP (No Operation) filtering and instruction fusion: not yet scoped,
  flagged as future work in Blog 3
- Per-instruction Zbb/Zbs/Zfhmin/Zfa enable gating: deferred, flagged
  in Blog 3
- DECODE-012 (frontend pre-decode restructuring): deferred to fetch unit
  design phase, noted in Blog 3
- Methodology blog (BLOG1.md) is a copy of rva23_docs_methodology-pm-001.md;
  a revised narrative version is warranted after more sessions are documented
- Series index page (index.md) worth creating when series grows beyond
  three posts; each post links back to it

### Documentation Templates Established
- **Technical Implementation**: Problem -> Approach -> Results -> Decisions
  -> Lessons
- **Methodology Innovation**: Challenge -> Solution -> Validation -> Impact
- **Tools & Validation**: Problem -> Framework -> Implementation ->
  Integration
- **Blog series**: Context post -> Implementation part 1 -> Implementation
  part 2, with stats tables and "what comes next" section in final post

### Documentation Rules From Now On
- Avoid non-ASCII characters in all output. This includes postmortems,
  blogs and documentation sub-project handoffs
- This rule excludes diagrams
- Diagrams are SVG, stored as separate files, referenced in Markdown as
  ![alt](diagram.svg). No inline SVG in Markdown source.
- When an acronym is introduced for the first time in a document it should
  be expanded, e.g. "needed by the BPU (Branch Prediction Unit) and FTQ
  (Fetch Target Queue)"

### SEO Guidelines
The target audience is narrow and technical (RISC-V implementers,
microarchitecture engineers, AI-assisted design researchers). SEO should
serve discoverability within that community, not broad traffic.

- Titles and headings must use canonical technical terms exactly as the
  community searches them: "RVA23", "RISC-V", "TAGE branch predictor",
  "RTL co-design", not paraphrases
- Acronym expansion rule (see Documentation Rules) passively serves SEO
  by indexing both the abbreviation and the full term
- Meta description -- each blog post should have one or two sentences
  summarizing the technical content precisely; this is what appears in
  search results
- Cross-linking -- posts in a series must link to each other explicitly;
  this matters for crawlability on GitHub Pages
- Keyword density targets, readability scores, and schema markup are out
  of scope for this audience

### Analysis Framework
For each session group, extract:
1. **Technical Achievements** -- What was built and how
2. **Methodological Innovations** -- Process improvements and new techniques
3. **Design Decisions** -- Architectural choices and rationale
4. **Lessons Learned** -- What worked, what failed, why
5. **AI Co-design Insights** -- Effectiveness of different prompting
   approaches

### Potential Publication Themes Emerging
- **AI-Assisted Hardware Design Methodology** -- The dual assistant
  architecture and experimental framework
- **Systematic Processor Co-design** -- Technical progression from decoder
  through branch predictor
- **Validation Framework Integration** -- Third-party verification in
  AI-assisted design flows
- **Prompt Engineering for Hardware** -- Effective strategies for RTL
  generation, including read-before-write discipline and debt scheduling

## Session Approach for PM 4

### Suggested Starting Point
TAGE/BPU sessions (Parts 11-25) are the next content priority. User will
provide session materials. These are the highest-value sessions for
methodology publication purposes.

### Process
1. **Session Selection** -- Choose next session(s) based on content
   richness and methodological interest
2. **Content Analysis** -- Search and extract key technical and
   methodological content
3. **Documentation Creation** -- Apply established templates to create
   focused post-mortems
4. **Pattern Recognition** -- Identify recurring themes and evolving
   methodology
5. **Integration Planning** -- Consider how individual session analyses
   build toward larger narratives

### Tools Available
- conversation_search for finding specific technical content and decisions
- recent_chats for chronological progression analysis
- Established post-mortem document templates
- Pattern analysis from Parts 1-3 and decoder track as baseline

### Success Metrics
- Clear technical narrative extraction from each session
- Methodology evolution documentation
- Lessons learned that could benefit future AI-assisted design projects
- Foundation material for potential publications or best practices guides

## Current Status
**Phase 1 Complete**: RVA23 Co-Design Part 1 fully documented (4 files)
**Phase 2 Complete**: Decoder track fully documented (2 postmortems,
  3 blogs, all DECODE-001 through DECODE-011)
**Phase 3 Complete**: All four diagrams created and verified, blog reviews
  done, reference and publishing conventions established
**Phase 4 Ready**: TAGE/BPU sessions next
**Templates Stable**: Consistent format proven across decoder track

## Files Created or Revised This Session (PM 3)

### New Diagrams
- diagram_scalar_encoding_formats.svg
- diagram_vector_encoding_formats.svg
- diagram_dual_packet_output.svg
- diagram_opcode_width_disambiguation.svg

### Blogs Reviewed (no new files, corrections noted above)
- BLOG_decoder_1_rva23_profile.md
- BLOG_decoder_2_scalar_to_alu.md

### Carried Forward from PM 2
- rva23_docs_decoder_part2-pm-002.md
- rva23_docs_decoder_part3-pm-002.md
- BLOG_decoder_1_rva23_profile.md
- BLOG_decoder_2_scalar_to_alu.md
- BLOG_decoder_3_memory_to_closure.md

### Carried Forward from PM 1
- rva23_docs_methodology-pm-001.md
- rva23_docs_tools-pm-001.md
- rva23_docs_decoder_part1-pm-001.md
- BLOG1.md

