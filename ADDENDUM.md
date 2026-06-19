<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->

This is out of date after the mkdocs changes

# Dirs

blogs           blog narratives for design phases
misc            ...
pa_sessions     Claude.ai chat sessions
pm_handoffs     postmortem session handoffs
postmortem      Analysis, phasing out for blog content


# Naming conventions

```
<rva23_docs>  this is the sub project
<decoder>     this is the module
<partsN>      module in parts
<pm-00N>      the postmortem session in c.ai
```

e.g.  RVA23 documentation for decoder part 2, generated in pm session 001

`rva23_docs_decoder_part2-pm-001.md`


# Contents

Postmortems - I have moved away from strict separation of postmortem and
blog, focusing on blogs for now. If a publication opportunity presents
I will use the `pa_sessions` directory contents for this effort.

## Blog posts

File location: `$RVA_ROOT/docs/blogs`

| File                                | Description |
|:------------------------------------|:------------|
| BLOG_introduction.md                | tbd         |
| BLOG_decoder_1_rva23_profile.md     | tbd         |
| BLOG_decoder_2_scalar_to_alu.md     | tbd         |
| BLOG_decoder_3_memory_to_closure.md | tbd         |


## Methodology reference

- **misc/ai_pairings.md** 
    - selection of AI pairs that would support the PA/IA pattern
    -  Right now the flow uses Claude.ai (PA) and Claude Code(IA)
    - A future effort will be to compare other Chat/code couplings
      for efficacy.

## Other Misc files

File location: `$RVA_ROOT/docs/misc`

| File                             | Description                          |
|:---------------------------------|:-------------------------------------|
| block_org.md                     | RTL module hierarchy                 |
| closed_tech_debt.md              | technical debt items now closed      |
| mutation_testing.md              | notes for future mutation testing    |
| observations.md                  | notes on the flow, future talk       |
| pa_session_map.md                | Map of named PA sessions to topic    |
| sva_prompt_template.md           | experimental prompt template for SVA |
| sv_verification_session_notes.md | notes from PA session on SVA         |


## Documentation work hand-offs
TODO: needs refresh

- **./handoffs/rva23_docs_handoff-001.md**
    - documentation session handoff 001->002

