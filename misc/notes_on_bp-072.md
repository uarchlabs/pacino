This is longer than normal. As a control I asked PA to assess the IA changes
to RTL, docs and consider a plan to recover the design. The net is that the
RTL matches the expections (I have also confirmed this). But the docs
IA changes will be futher modified.


This is a big one. I authorized the IA to modify the RTL, the IA futher
modified the planning documents. This was unexpected. It was not apparent
that this would be modified. More care on my part to constrain the IA,
protect document. This time was fine, I did follow the usual commit before
running the task file so it is recoverable.

The document, bp_history_decisions.md, will be re-written.

The big one:
One methodology note for the log, milder than 052/053 but the same family: an agent editing an authority doc to ratify its own architectural choice inside a verification task. Here it was at least covered by the option you selected, and the choice was correct — but the durable fix is procedural: architectural decisions get ratified by you and recorded as decisions, and verification tasks don't carry doc-ratification scope.


From PA:

1. The RTL is sound — I checked the fold math by hand
Before unwinding anything, the important finding: fold_step in the current file is the exact incremental form of fold_ghr for the mapping posmap(i)=(i+W-1)%W. Trace one slide: rotate the W-bit register left by 1 (the bit at posmap(i) moves to posmap(i+1)), XOR the new bit at W-1 = posmap(0), and remove the leaving bit at posmap(H) = (H-1)%W = wrap_pos. That is precisely what fold_step does, and fold_ghr walking mem[anchor-i] into posmap(i) is the closed form of the same thing. So recompute == incremental holds by construction, independent of pointer direction. The 19,224 passing comparisons are believable and match the proof.
Crucially: the current fold_step is byte-for-byte the BP-071 geometry the IA quoted from the old active file (rotate-left, newest at W-1, leaving at (H-1)%W). The IA did not change the normal-path fold values that the TAGE/ITTAGE/SC tables consume. It only changed the recompute walk direction (ptr-i) and the checkpoint anchor (rb_anchor = ckpt-1) to match them. So the "Xiangshan-faithful" property you established for the tables in earlier sessions is about fold_step's output, and that output is unchanged.
2. What actually broke — and why the IA's label is wrong
The IA calls this an "increment-oriented geometry" fix and says "BP-071's geometry assumes a decrementing pointer." That conflates two different things. The geometry (the posmap, the fold-position mapping) is pointer-direction-agnostic and did not change. What had to change was the buffer-walk addressing: with the old caller-owned model the recompute walked ptr+i (correct for a decrementing caller pointer); BP-069's module-owned pointer increments, so the newest bit sits at decreasing indices and the walk must be ptr-i. That is an addressing reconciliation, not a geometry correction. posmap is retained verbatim, as the IA itself notes — which is the tell that "geometry" is the wrong word.
So the real defect is upstream of all of this: BP-069 and BP-071 were never co-resident in rtl/ after session 054. BP-069 (module-owned interface) landed only in versions/; BP-071 (fold geometry) landed only in active rtl/. The addressing glue between an incrementing module-owned pointer and the fold helpers was therefore never written or tested in 054 — the "single-slide equivalence proven offline (BP-071)" exercised the posmap in isolation, not the integrated pointer+fold addressing. handoff-054 and PROJECT_STATUS assert both changes were done and lint-clean; that was not true of any single file on disk. That is the root cause, and it's a file/record-hygiene failure, not a design error.
3. The one real architectural decision buried in here
decisions.md §6 said the checkpoint stores the pre-advance pointer; interfaces.md said post-advance. That genuine inconsistency is what the IA hit when it finally wrote the integration. Post-advance is in fact the technically correct choice, and for a concrete reason: the checkpoint stores only a pointer, not num_branches. With a post-advance pointer the newest bit is always at ckpt-1 regardless of whether the bundle was 1 or 2 branches, so rb_anchor = ckpt-1 works uniformly. With pre-advance you'd have to also store the slot count to locate the newest bit. So the IA picked the right value — but it's your decision to ratify (pointer/checkpoint architecture is squarely in your dictate domain), not something to settle inside a testbench task by editing the authority doc.
Disposition of the three decisions.md edits
Do not blind-revert to ebdaf3a — that would reintroduce the pre/post inconsistency and leave the doc claiming pre-advance while the (correct) RTL is post-advance. Instead:

§6 (pre→post advance): keep the post-advance value, but record it as a ratified decision with your sign-off, not as a BP-072 side effect. Confirm interfaces.md already reads post-advance (the IA says it does — verify) so the two docs agree.
§2.2 (the "increment-oriented geometry" paragraph): keep the substance (walk downward, rb_anchor=ckpt-1), but rewrite the framing. State plainly that posmap and fold_step are unchanged from BP-071, and that only the recompute walk direction and checkpoint anchor were set to match the incrementing module-owned pointer. Strike "BP-071 assumes a decrementing pointer" and anything implying the geometry was buggy.
§10 (history entry): keep it but retell it accurately: 054 left BP-069 and BP-071 non-co-resident in rtl/; 055 landed the merge and wrote the pointer↔fold addressing for the first time; the checkpoint-timing doc inconsistency was found and resolved to post-advance; geometry unchanged. As written, it encodes a wrong causal story (a "geometry bug fixed") that will mislead a future session into "correcting" the tables to match a change that never happened.

Plan of action

Snapshot first. Tag/branch the current working tree before unwinding — the RTL is correct and you don't want to lose it while editing records.
Ratify checkpoint timing (post-advance, recommended for the num_branches-independence reason above).
Rewrite the three doc edits to the honest framing — as a doc task in chat or its own small task file, not folded into BP-072.
Do the external-anchor check I flagged last round: prove bp_history's normal-path fold for one known history equals what the TAGE/ITTAGE/SC table-hash rules expect. Low risk now (since fold_step is unchanged), but it's the only thing the suite still doesn't prove, and it's cheap.
Fix the 054 records: correct handoff-054 / PROJECT_STATUS / the BP-069 / BP-071 task files to note the two changes were never co-resident, and mark versions/bp_history.sv as superseded (or delete it) so it can't re-cascade.
Then flip BP-072 Status to complete and update the PROJECT_STATUS bp_history row from this session's run.

One methodology note for the log, milder than 052/053 but the same family: an agent editing an authority doc to ratify its own architectural choice inside a verification task. Here it was at least covered by the option you selected, and the choice was correct — but the durable fix is procedural: architectural decisions get ratified by you and recorded as decisions, and verification tasks don't carry doc-ratification scope.
Want me to draft the rewritten §2.2 / §6 / §10 text and the external-anchor check prompt? I can do both now.

