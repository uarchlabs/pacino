# Blog Proposal, Sessions 069-081

Proposed, not assigned. Session 068 (BLOG_tools_1) is not covered.

| Post    | Range   | Experiments                                    | Subject                                      |
|---------|---------|------------------------------------------------|----------------------------------------------|
| fetch/3 | 069-073 | TOOLS-006, BP-109 to BP-114                    | Specification, audit, building against it    |
| fetch/4 | 074-077 | BP-115, INFRA-013, BP-116 to BP-121,           | Front end end to end; fetch path complete    |
|         |         | BP-123 to BP-125                               |                                              |
| bpu/21  | 076-077 | BP-122, BP-126, BP-127                         | Loop predictor in use; predictor findings    |
| bpu/22  | 078-080 | BP-128 to BP-136, SYS-001, SYS-002             | Slots at 1 and 2; last debt; CSR tie-off     |
| doc/1   | 080-081 | DOC-001 to DOC-005, BP-137, BP-138             | Front-end demonstration                      |

## Arcs

| Post    | Arc                                                                                     |
|---------|-----------------------------------------------------------------------------------------|
| fetch/3 | Instruction side specified (069), audited (070-072, one section), built against (073). |
|         | Building found three rules no RTL could meet and a skipped redirect target (TD#139).   |
| fetch/4 | IFU built; front end runs end to end; task method moves from defect lists to end      |
|         | states (BP-121); that method carries uncached fetch, FENCE.I, the walker and decode.   |
| bpu/21  | Loop predictor put into use; predictor TD closure reported as findings only (D-1, the  |
|         | CTR step direction); SC index change.                                                   |
| bpu/22  | Slot parameter real at 1 and 2; BP-131 shows directed tests cannot decide the slot     |
|         | questions; last debt as a findings list; CSR tie-off as one section (pt_ad_h).         |
| doc/1   | Showing the design found defects the regression did not (BP-137, BP-138).             |

## Exceptions accepted

- fetch/3 spans bpu and ftq units in session 073.
- fetch/4 exceeds the 2-8 experiment reference and may exceed 5000 words.

## Open

- bpu/21: separate, or folded into bpu/22.
- Session 081: confirm in scope.
- Row 68: what BLOG_tools_1 covers.
