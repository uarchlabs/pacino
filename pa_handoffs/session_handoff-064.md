<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 064
Written by Claude.ai at end of session-063.
Date: 2026-08-08

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

Session-063 built the branch prediction cluster. bp_cluster.sv now
instantiates all eight modules, carries the full prediction and
update behaviour, elaborates and lints clean, and all 45 bpu targets
pass. Nothing in bp_cluster has ever been simulated.

NEXT SESSION: nine items stand between here and a tb_bp_cluster
task -- three design closures that change the boundary, three
testbench decisions, one Makefile addition, and two record items.
They are enumerated in NEXT SESSION Part 1.

---

## Read This First

The BPU is structurally complete and functionally unverified above
the unit level. That single sentence is the state of the design.

Every predictor is green in isolation. bp_cluster instantiates them,
wires p0 through p3, and implements the stage registers, the p1
selection mux, the RAS branch-type decode, redirect derivation at p2
and p3, update fan-out by resolved branch type, the SC credit
arbiter, and both prediction-metadata write groups. Every boundary
output has a producer. lint_bp_cluster passes with zero warnings.

No prediction request has ever been driven through it. There is no
tb_bp_cluster and no sim target for it. Every statement in this
handoff about cluster behaviour comes from reading RTL and from
elaboration, not from a run.

---

## Session Summary

### Tasks run

Task IDs used this session: INFRA-011, BP-082 through BP-086,
BP-090. BP-087, BP-088 and BP-089 were abandoned. Next free BP
number is BP-091.

  INFRA-011  Port inventory of the eight BPU top-level modules,
             read off the RTL and compared against the eight
             interface documents. 140 ports. Four doc-vs-RTL
             findings, all in ubtb and bp_history, which were the
             two documents session-061 did not audit.
  BP-082     bp_structs_pkg dual-slot FTQ entry. Found already
             applied at commit 2b60115; verified rather than
             re-applied. Found tb_bp_pkg.sv as the only consumer of
             the removed scalar fields.
  BP-083     tb_bp_pkg retrofit to the dual-slot entry. Mutation
             tested against four injected defects.
  BP-084     bp_cluster.sv structural top: eight instances, wiring,
             tie-offs, elaborate-only.
  BP-085     bp_cluster.sv behavioural: stage registers, p1 mux,
             RAS decode, redirect derivation, update fan-out, SC
             credit arbiter.
  BP-086     ubtb.sv and tb_ubtb.sv rewritten to the single-lookup
             block descriptor model. Mutation tested against five
             injected defects.
  BP-090     bp_cluster rewired to the reshaped uBTB, prediction
             metadata write ports added, p1 fall-through consumer,
             SC index fold staging, tb_bp_pkg width and stimulus
             fixes, package comment corrections. 45 of 45 green.

### The abandoned tasks

BP-087, BP-088 and BP-089 were ABANDONED, all three because the PA
specified them incompletely. None of their RTL reached the tree.

NOTHING FROM THEM IS OUTSTANDING. BP-090 was written against the
tree state a failed BP-089 run reported, and carried the whole of
their intended work: the uBTB rewire, the metadata write ports, the
tb_bp_pkg SLOT_BITS correction, and the tb_bp_pkg stimulus for the
fields the package gained. There is no residue to pick up. See the
postmortem for how the three failed.

### Planning documents

  planning/interfaces/bpu_port_inventory.md   NEW (INFRA-011)
  planning/interfaces/ftq_bpu_interfaces.md   NEW
  planning/interfaces/ubtb_interfaces.md      REWRITTEN

ftq_bpu_interfaces.md is the port specification for the FTQ/BPU
boundary and the routing from it to every predictor port. Sections
3 through 9 cover the request, the p1 prediction, the late
predictions, the redirects, the prediction metadata, the updates and
the history checkpoint. Section 10 lists the corrections other files
still need.

---

## Decisions (session-063)

These are design record. They currently exist only here and in
ftq_bpu_interfaces.md. Session-063 found shipped RTL contradicting
ftb_decisions.md 2.1/2.3 -- the defence against that recurring is
promoting these into the decisions documents rather than leaving the
next reader to reconstruct intent from a chain of handoffs. See Open
Work.

### The uBTB is a block descriptor, one lookup per cycle

ubtb.sv previously did two lookups per cycle, slot 0 at pred_pc_p0
and slot 1 at pred_pc_p0 + 32. That was the retired two-PC-range
model, and it contradicted ftb_decisions.md 2.1/2.3 and
fe_decisions.md section 10 in shipped RTL rather than in a document.
XiangShan does not do it either: their uFTB is one tag, one entry,
both branch slots out of it, with a variable-length block ending at
pftAddr.

The uBTB entry now mirrors the FTB entry: two conditional branch
fields, one jump field, a partial fall-through with carry,
displacement targets with a fit/overflow/underflow status. One
lookup returns one entry describing one 32-byte block, and the two
prediction slots are that entry's two conditional fields. UI1 and
UI4 are closed.

### The uBTB reports hit once per lookup

New output blk_p1 of type ubtb_blk_t carries the entry hit and the
reconstructed fall-through. A pred_p1 slot's own valid bit now says
only that the slot carries a branch. A hit with no valid slot is a
legal state: the block is known and contains no recorded branch, and
the successor is the fall-through.

### Predictor ports are used as declared

The eight modules do not share one naming convention and this was
not corrected. INFRA-011 established the actual variance: tage,
ittage and sc use <pred>_<signal>_<stage> with unpacked slot arrays;
ras the same without queue-status ports; ubtb a packed slot
dimension on the type; loop_pred single slot with a p0 suffix on its
update; ftb flat ports with no structs and no slot dimension;
bp_history no stage suffixes and literal [1:0] and [2] dimensions.
ftq_bpu_interfaces.md names each module's real ports and proposes no
renaming.

### Redirects are named by stage, not by predictor

No predictor declares a redirect port -- confirmed across all 140.
The cluster derives the redirect by comparing a predictor's stage
output against the prediction it formed at p1 and carried in its own
stage registers. bp_cluster does not read the FTQ. The groups are
bpu_redir_p2 and bpu_redir_p3, each a bp_redirect_t array with a
scalar index alongside.

### The redirect comparison is one quantity

Both the p1 and the p2 view of a slot reduce to the address fetched
after that slot. Two not-taken views therefore compare equal. The p3
comparison is against the p2-corrected value, not the raw p1
prediction, so a p3 redirect fires only when SC changes what the
cluster published at p2.

### Every late comparison is qualified by branch_id

tage, ittage and sc carry branch_id in their metadata, and every p2
and p3 comparison requires it to equal the FTQ index in the matching
stage register. A queued or back-pressured response cannot be
compared against the wrong entry, so the redirect logic assumes no
fixed predictor latency.

### The FTQ slow path needed a producer

bp_ftq_meta_t holds what each predictor needs to train and cannot
recompute at resolution, and bp_cluster had no port to write it.
Without it the update path could not work at all: tage_upd_inp_t
embeds tage_pred_meta_t, ittage_upd_inp_t embeds
ittage_pred_meta_t, sc_upd_inp_t embeds sc_pred_meta_t.

Two write groups, disjoint members so the FTQ never merges. The p2
group writes tage, ittage, lp and ftb; the p3 group writes sc. The
loop predictor finalizes at p1 and its result is registered forward
into the p2 group so the FTQ performs one slow-path write.

### bp_ftq_meta_t gained an ftb member; bp_ftq_slot_t gained pos

New type ftb_pred_meta_t holds the FTB hit, way and jump position.
The carried writeWay scheme (IC-FTB-10) requires hit and way to
travel through the FTQ and return on the update port, and the struct
had nowhere for them.

The in-block branch position is on the fast path, in bp_ftq_slot_t,
because locating the taken branch in the fetch bundle is every-cycle
work. The jump position is in the metadata, being one value per
entry rather than one per slot.

### The p1 redirect operand is the p1 fall-through

The p2 redirect compares the p1 and p2 views of a slot. Both sides
previously used the FTB fall-through, which masked the case the
comparison exists to catch: a block whose boundary the FTB places
somewhere the uBTB did not. The p1 operand is now formed at p1 from
the p1 view only -- the slot target when taken, the uBTB
fall-through on a hit, the block-aligned PC plus FTB_BLOCK_BYTES on
a miss -- and staged to p2.

Newly redirecting: a not-taken slot where the uBTB and FTB disagree
on the block end, on a hit or a miss. A stale uBTB boundary now
corrects at p2 instead of the front end fetching past a boundary the
FTB had already contradicted.

### SC index folds are staged p0 to p2

The SC prediction PC and phr[9:0] were staged per TD#91 and TD#92;
the three SC index folds were connected live to bp_history, which
advances whenever a branch is predicted. At p2 they described
history newer than the block SC was indexing. Same class of signal,
same staging. TAGE and ITTAGE take bp_folded_hist_t whole at their
own p0 request and stage internally; only SC takes sliced folds.

### The uBTB update branch type is rederived, never restored

ubtb_upd_t no longer carries br_type. bp_cluster rederives the
resolved type from the payload's own is_br / is_jmp / is_call /
is_ret / is_jalr bits, in the same arm order as ubtb.sv jmp_br_type
and the FTB classification, with is_br outranking is_jmp.

This matters: Verilator resolves a missing br_type read to zero,
which decodes as COND. Clearing the lint error by re-adding the
field rather than rederiving the type would have silently classified
every update channel as conditional, stopped ITTAGE ever being
updated, and made the uBTB accept NO_BRANCH updates.

---

## NEXT SESSION (064)

### Part 1: what has to be settled before the testbench

Jeff asked directly whether the RTL was ready for a testbench as it
stands. The PA answered yes with two caveats. That was wrong. Nine
items stand between here and a testbench task, and three of them
change the ports a testbench binds by name.

DESIGN CLOSURES -- these change the boundary:

  1. TD#105. loop_pred dual-slot retrofit and the pred_p0 to
     pred_p1 rename. NOT a small item: a slot dimension on
     pred_pc_p0, pred_valid_p0, pred_p0, upd_p0 and upd_valid_p0,
     the internal tables reworked per TI6, and loop_pred.sv,
     tb_loop_pred.sv and loop_pred_interfaces.md all touched. This
     is a module retrofit with its own testbench work, and it
     renames a port.

  2. TD#108. Does the p1 output group carry a block successor or a
     fall-through? Today it carries val, idx, the slot array and the
     RAS snapshot. The FTQ derives the successor from the slot array
     (fe_decisions.md 2.4), but on a not-taken block it needs the
     block end, and blk_p1.pft_addr stays inside the cluster. ADDS A
     PORT if the answer is yes, and it is also an observability hole
     -- see Part 3.

  3. TD#106. Retire one of lp_pred_t / bp_loop_meta_t. The metadata
     tests check the loop metadata FIELD BY FIELD, so a struct
     consolidation invalidates them.

TESTBENCH DECISIONS -- these have to precede the task file:

  4. The branch_id injection mechanism. branch_id originates inside
     predictor metadata; a mismatched one has to be injected. Force
     the metadata, stub the predictor, or construct a pipelined-
     request-plus-backpressure scenario. Choose one.

  5. The X-assign and X-initial settings for sim_bp_cluster. See
     Part 4 -- this module is unusually exposed to X and a zero
     resolution produces a plausible wrong answer rather than a
     visible failure.

  6. TD#39. PRED_CREDITS=4 < STARVE_THRESH=8, so the SC arbiter's
     Rule 2 starvation override may be unreachable at current
     parameters, and therefore untestable. Settle whether the
     relationship is intentional before writing the arbiter tests.

MECHANICAL:

  7. Add tb_bp_cluster.sv, sim_bp_cluster and cov_bp_cluster to the
     bpu Makefile.

RECORD:

  8. Promote the session-063 decisions out of this handoff. The
     block-descriptor uBTB and the retirement of the pred_pc+32
     slot-1 lookup need a uBTB decisions document, which does not
     exist. The stage-named redirect model, the one-quantity
     comparison, the branch_id qualification and the two-group
     metadata write belong in bp_cluster.md.

  9. The ftq_bpu_interfaces.md section 10 corrections, listed under
     Open Work.

If any of items 1 through 3 is deferred rather than settled, scope
the testbench to the parts of the boundary it does not touch, and
say so in the task file.

### Part 2: why tb_bp_cluster is now writable at all

The metadata write groups added in BP-090 are what make a closed
predict-then-update test possible. The update inputs embed
predict-time metadata, so before those ports existed nothing could
carry a prediction's state out of the cluster and back into its
update. The testbench acts as the FTQ: capture the p2 and p3
metadata, hold it against the FTQ index, and feed it back on the
update channels at resolution.

### Part 3: what is drivable and observable at the boundary

  in   ftq_pred_val_p0, ftq_pred_pc_p0, ftq_pred_idx_p0
  out  bpu_pred_val_p1, bpu_pred_idx_p1, bpu_pred_slot_p1[],
       bpu_pred_ras_p1
  out  bpu_redir_p2[], bpu_redir_idx_p2,
       bpu_redir_p3[], bpu_redir_idx_p3
  out  bpu_meta_val_p2, bpu_meta_idx_p2, bpu_meta_tage_p2[],
       bpu_meta_ittage_p2[], bpu_meta_lp_p2[], bpu_meta_ftb_p2[]
  out  bpu_meta_val_p3, bpu_meta_idx_p3, bpu_meta_sc_p3[]
  in   the seven predictors' update channels
  in   ras_restore, ras_commit, ras_flush groups
  out  ghist_ptr, phist_ptr, ckpt_ghist_ptr, ckpt_phist_ptr,
       ghr_buf, phr_buf
  in   tage_enable_aging, tage_aging_interval, ittage equivalents,
       sc_enable, ftb_fastpath_en
  out  tage_rdy, ittage_rdy, sc_ready, and the queue-status group

FIVE things the boundary cannot show. Each needs a hierarchical
probe, a force, or a stimulus construction; tb_tage_manual already
establishes hierarchical probing as acceptable practice.

  1. Update fan-out reaching the predictors. Proving TAGE sees an
     update only for a conditional, or ITTAGE only for an indirect,
     requires probing the instance input.
  2. tage consumer_ready and the SC credit arbiter internals. The
     grant rules, the credit counters and the starve counter are all
     internal. consumer_ready is an internal net driven by the
     arbiter, not a port.
  3. The branch_id match rejecting a stale response. branch_id
     originates inside predictor metadata; a mismatched one has to
     be injected. Options: force the metadata, stub the predictor,
     or construct a pipelined-request-plus-backpressure scenario
     that makes a response arrive late. None is described here --
     choose and record it in the task file.
  4. The p1 redirect operand. The "uBTB and FTB disagree on block
     end" test can observe that a redirect fired, but not that the
     p1 operand was formed correctly, because blk_p1.pft_addr does
     not leave the cluster. This is TD#108 reappearing as an
     observability hole.
  5. The block successor across slots. There is no p1 output
     carrying it (TD#108 again); it is visible only through its
     effect on the redirect comparison.

### Part 4: X-handling

State this explicitly in the task file. This module is unusually
exposed to X, in both directions:

  - BP-084 built the top with tie-offs, and BP-088 shipped a field
    that passed as x. Undriven paths can pass silently.
  - The br_type decision above documents that a ZERO read decodes as
    a valid branch type (COND). Zero is also a valid FTQ index and a
    valid way. So an X that a tool resolves to zero produces a
    plausible wrong answer rather than a visible failure.

Required in the task:
  - name the --x-assign and --x-initial settings the sim target uses
  - include a boundary X-check in bring-up: after reset and one
    request, no boundary output is X where the interface says it is
    valid

### Part 5: bring-up before anything else

Nothing has ever been driven through this module. The first three
tests, in order, before any behavioural test:

  1. Reset, one request. Does bpu_pred_val_p1 assert at all, with a
     sane index, at the expected cycle?
  2. Does the harness report a NON-ZERO EXIT when a check fails?
     Prove it, do not assume it. BP-086 found the old tb_ubtb used
     $finish(1), which Verilator does not turn into a non-zero exit
     code, so a failing run reported a passing target. Use
     $fatal(1), and demonstrate the failing exit once.
  3. The boundary X-check of Part 4.

### Part 6: building predictor state

Two paths, and the tests need both. RULE: seed the tables by
hierarchical reference when a predictor's response is a FIXTURE for
a cluster-level test; drive the real update path when the CLUSTER is
the subject.

Seeding is precedented -- sc_tb_decisions.md records the mem[b][i]
convention and the TAGE and SC suites use fast-init plusargs -- and
it makes a prediction test short instead of requiring a long
training sequence. But it encodes predictor-internal layout into
cluster-level tests, so a future table reshape (like the one BP-086
just did to ubtb) breaks tests whose subject is not that predictor.
Keep the seeded surface as small as each test needs.

### Part 7: coverage, ordered, with a stop rule

Order matters: each group depends on the one before it. The task
file should stop at the end of a group if that group is not green,
rather than continuing into work built on an unverified layer.

  Group A -- bring-up (Part 5). Stop if not green.
  Group B -- p1 prediction
    - selection between uBTB and loop_pred, per slot, including the
      slot-1 case that has no loop_pred producer
    - the entry hit against the slot valid bit, including a hit with
      no valid slot
    - pos propagation from ubtb_pred_t into bp_ftq_slot_t
    - RAS engagement at p1 on a uBTB RETURN, target from the
      registered top of stack
  Group C -- p2 redirect
    - each target source by branch type: RAS pop for a return,
      ITTAGE for an indirect, TAGE direction selecting the FTB
      branch target or the fall-through for a conditional, FTB jump
      target for a direct unconditional
    - the newly redirecting case: a not-taken slot where the uBTB
      and the FTB disagree on the block end
  Group D -- p3 and supersession
    - SC override and supersession against the p2 value
    - the branch_id match rejecting a stale or delayed response
      (mechanism per Part 3 item 3)
  Group E -- history
    - checkpoint at allocation, rollback on redirect
  Group F -- metadata
    - p2 and p3 contents checked field by field
  Group G -- update
    - a closed predict-then-update loop, ONE PREDICTOR PER TASK if
      seven does not fit. Order: tage, then ittage, then sc, then
      the three that have no queue.
  Group H -- arbitration
    - SC credit arbiter grant rules and tage consumer_ready
      (hierarchical, per Part 3 item 2). Note TD#39: PRED_CREDITS=4
      < STARVE_THRESH=8, so Rule 2 may not be reachable at current
      parameters. Settle that before writing the test.

Groups A through F are one task's worth. G and H are separate. Do
not write a single task file containing all of this -- the
postmortem's own finding is that the tasks which worked had
explicitly scoped stop rules.

### Part 8: mechanics

  - Add tb_bp_cluster.sv, a sim_bp_cluster target and a
    cov_bp_cluster target to the bpu Makefile.
  - Self-checking, pass and fail counters, $fatal(1) on failure.
  - Mutation-test the suite. BP-083, BP-086 and BP-090 all did this
    unprompted and it is the reason their green results mean
    something. An out-of-tree scratch build must use the project
    Verilator, which CLAUDE.md fixes at v5.048; the system binary is
    older and will produce a false compile failure for every case.

---

## Open Work

### Design questions not settled -- these gate Part 1

  - TD#108: whether the p1 output group should carry a block
    successor or fall-through.
  - TD#105: the loop_pred dual-slot retrofit and the pred_p0 to
    pred_p1 rename.
  - TD#106: retiring one of lp_pred_t / bp_loop_meta_t.

### Design record still only in handoffs

The Decisions section above is durable design record and it lives
only here and in ftq_bpu_interfaces.md. Promote it:

  - The block-descriptor uBTB and the retirement of the pred_pc+32
    slot-1 lookup belong in a uBTB decisions document, which does
    not exist. ubtb_interfaces.md is an interface contract, not a
    decisions record.
  - The stage-named redirect model, the one-quantity comparison, the
    branch_id qualification and the two-group metadata write belong
    in bp_cluster.md.

Session-063 found shipped RTL contradicting ftb_decisions.md 2.1/2.3
because the decision lived in a document the RTL author did not
treat as governing. The same failure mode applies to everything
above.

### ftq_bpu_interfaces.md section 10 corrections outstanding

  - fe_decisions.md 2.2 and 9 place the RAS top of stack at p1;
    ras.sv declares ras_tos_addr_p0. Correct to p0.
  - fe_decisions.md 3.1 names <pred>_redir_* signals, reading as a
    per-predictor port group. No such ports exist. Rewrite to the
    cluster-derived, stage-named group.
  - bp_arb_spec.md 6.1 lists the SC prediction PC and phr as staged
    inputs and should now name the three SC index folds as well
    (TD#92).

### bp_cluster.sv stale comments, TD#107

  - The port-list comment reads "section 7: update channel", but
    ftq_bpu_interfaces.md numbers the update channel as 8; 7 is the
    prediction metadata.
  - The w_slot_pc_p1 comment still says ubtb.sv derives slot 1 from
    pred_pc_p0 + FTB_BLOCK_BYTES. BP-086 retired that.

### tb_bp_pkg.sv

  - The four predictor members of bp_ftq_meta_t are not driven in
    the metadata packing test. Each is exercised where its own type
    is checked and the width check binds their contribution, so this
    was deliberate, but a full-struct stimulus would be stronger.

### Carried, unchanged this session

  TD #101 (ras_pc_p2 declared and unread; the cluster now drives it
  from the staged p2 PC), #102 (bp_history does not generate the
  ITTAGE IT5 folds -- IT5 indexes on PC alone and contributes no
  history, so it duplicates a short-history table), #103 (tage T0
  init), #104 (two FTB stale comments), #49, #96, #100, and the full
  backlog in PROJECT_STATUS.

---

## Postmortem Record -- PA performance (session-063)

Continuing the trend log (058 over-asking; 059 fabricated constraint
+ manifest by inference; 060 manifest-by-inference + verbosity;
061 template-field misreads; 062 fabricated technical claims +
withheld conclusions). Session-063 produced working RTL but cost
Jeff heavily in rework and in time spent correcting the PA rather
than the design.

1. THREE TASKS ABANDONED FOR INCOMPLETE SPECIFICATION. BP-087,
   BP-088 and BP-089. This is the defining failure of the session.

   BP-087 forbade touching a testbench and simultaneously required
   every target to pass, when the failing target was a testbench
   width constant. The IA did exactly as instructed and stopped.

   BP-088 was written to fix that, and did, but scoped the testbench
   work to the width constant only -- leaving the new field driven
   nowhere, so it passed as x. The task that was meant to close the
   work created more.

   BP-089 was written on top of BP-088's reported results. Those
   results were never in the tree, because BP-088 had been
   abandoned. Jeff had said so explicitly and the PA misread it.
   Every premise referencing "as BP-088 left them" had no referent,
   and the constraints forbade fixing what was actually broken.

   The mechanism in all three: change a type, then specify only the
   immediate breakage rather than following the change through to
   everything that depends on it.

2. RESULTS READ AS STATE. BUG-006 has been standing since
   session-062: build from the tree, not from a summary. The PA
   quoted that rule inside the task that violated it. A task
   reporting green is not a tree that is green, and an abandoned
   task's RTL is not in the tree at all. BP-090 was written against
   the tree state a failed run actually reported, and closed in one
   run.

3. CONTRADICTORY CONSTRAINTS SHIPPED TWICE. BP-084 required the
   redirect outputs left undriven and zero lint warnings; the IA
   needed -Wno-UNDRIVEN to satisfy both and said so. BP-087 repeated
   the pattern with the testbench. Both were caught by Jeff, not by
   the PA.

4. SCOPE DECIDED AND PRESENTED AS SETTLED. BP-089 carried a "NOT in
   this task" list stated as fact. Scope is Jeff's.

5. QUESTIONS HANDED BACK THAT THE DOCUMENTS ANSWERED. On the full
   bp_cluster RTL task, the PA listed seven items as needing
   decisions. Five were already settled in the documents in front of
   it. Two were real and both dissolved on inspection.

6. JARGON AND SHORTHAND IN PLACE OF EXPLANATION.

7. ASKED TWICE FOR THE SAME WORK, REPEATEDLY. Several times Jeff had
   to repeat an instruction because the PA responded with a survey
   of considerations instead of the artifact. Twice the PA said it
   was writing something and then did not.

8. AN HOUR LOST TO A CLAUDE CODE LOGIN FAILURE, made worse by the
   PA. Four commands recommended across five turns before either
   official doc page was read. Jeff's verbatim record of the
   incident is in PROJECT_STATUS.

9. THIS HANDOFF SHIPPED WITH AN OVERCLAIM. The first revision
   asserted "the RTL is ready for it as it stands; no design change
   is required first" while its own Open Work section listed three
   unsettled items that rename or extend the ports a testbench binds
   to. Caught in review by the next session, not by the PA. The same
   three items had been in front of the PA when Jeff asked directly
   whether the testbench could be written against the RTL as it
   stands, and the PA answered yes.

What held:
  - Task files that stated the failure mode explicitly worked.
    BP-082's requirement to search for consumers found tb_bp_pkg.sv
    before it broke anything. BP-090's baseline requirement made
    every fix attributable. BP-086's stop rule was correctly scoped.
  - The IA mutation-tested its own testbenches in BP-083, BP-086 and
    BP-090 without being asked in two of the three.
  - The IA refused an instruction that was wrong and explained why:
    BP-090 requirement 6 changed one site and left the other,
    correctly, because the binding decision fixed the selection mux
    rule.
  - INFRA-011's scope discipline held. Written as gather-only with
    assessment explicitly barred, it produced clean evidence.

