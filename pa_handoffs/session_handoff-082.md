# Session Handoff 082
Written by Claude.ai during session-081.
Date: 2026-10-19

Read PROJECT_STATUS.md, then this file, then CLAUDE.md.

FIVE TASKS RAN THIS SESSION AND ALL ARE RECORDED: BP-138, DOC-006,
BP-139, BP-140, DOC-007. BP-139 and BP-140 fix TD#179's central
defect: every branch is now predicted at every slot count, with
per-start FTB and uBTB entries and the split at update. The fe_demo
builds at one slot by default, with a 2-slot build for four
scenarios; all 24 pass. TD#168 is CLOSED. TD#189 to TD#193 are
OPENED. TASK FILES MOVED TO THE IA (Jeff); the IA wrote BP-139 and
BP-140, the PA wrote DOC-007 at Jeff's request. No task is written
and waiting.

---

## Read This First

### 1. Scope is Jeff's, every time.

Nothing is opened, written into a document or put in a task without
Jeff ruling that item by name. Do not ask Jeff to rule on what the PA
can decide and write down.

### 2. Planning documents are decisions only, written for the IA.

No narrative, no justification, no history in the body, no statements
about the current state of the tree. The IA never edits a planning
document: it proposes text in Results Capture and the PA applies it.

### 3. Task files are the IA's (Jeff, session-081).

The PA writes a task file only when Jeff asks. Then it copies
TASK_TEMPLATE.md and replaces the placeholders only, and diffs the
result against the template before sending it. The input says "All
experiment files need to follow the task template exactly"; BP-138
broke it (a heading renamed, the Deliverables note dropped).

### 4. Verify every Background claim before the task is issued.

PROJECT_CORE.md, Prompt generation rules: "Every factual claim in a
Hypothesis or Background section must be verified against a file in
the manifest before the prompt is issued." BP-138 carried an IA note's
claims unchecked; two were wrong. What cannot be checked is marked
unchecked and given to Problem 0.

### 5. Reads outside the manifest are asked for first (Jeff).

Every task file's Context Comments carries it: "Any other read needs
permission first. Ask before reading, listing or grepping a path
outside these grants. If a read happens without asking, report every
one in Results Capture."

### 6. IA planning instructions are applied as written, after a check.

The IA gives each change as File / Where / Action / Current / New /
Why. The PA confirms every Current text occurs exactly once and every
insert anchor exists in the installed copy, then applies it. Anything
the PA changes beyond the entries is named in its reply.

### 7. Answer the question asked.

When Jeff asks why, give the fact first. In session-081 the PA gave
reasons in place of the fact (it had not read the input line by
line) and was told so repeatedly.

### 8. Verify before stating, and say what was and was not checked.

Session-081 stated XiangShan's design from memory three times, wrongly
each time (per-start entries; the TAGE interface; "the older split
rule"). Facts about another design come from its source or documents,
cited, or are not stated.

### 9. Ask for files first, read what is used, say when a read is
partial. Ask only for files the PA itself needs; the IA reads the
tree.

### 10. Issue files when they change.

Every changed file is sent with PROJECT_STATUS.md and check_planning.sh
together, without being asked. Checksums are md5, 12 characters,
verified by running check_planning.sh on a temporary tree.

### 11. The git wording, verbatim in every task file.

"The IA runs no git command. It may run tools/regress.sh, which makes
git calls of its own; that grant is to run the script, not to run any
command the script contains. Reading regress.sh to see what it calls
grants nothing either."

### 12. FIX WHAT YOU FIND goes in every task file.

A fix not set by a planning document is provisional and listed with
its reason.

### 13. Writing rules for the descriptions (FDT-13a).

Full sentences; no jargon; no abbreviation the text has not
introduced; testbench variables, tasks and files named explicitly with
where they are defined; no "lands", no "shape", no "X but not Y"
framing. Checker: tools/ticfinder/tools/ticfinder.py. Lines at most 80
columns, ASCII.

---

## Worth your attention

1. ras_theory_of_operation.md (misc/) is stale beyond BP-138's edits:
   it still describes a simple circular buffer (4.1 and 4.3 call the
   linked array rejected), s-stage notation, VA_WIDTH 40, the
   pred_pc+32 two-slot model with its same-cycle bypass, and a
   three-way JALR split; it does not have BP-140's BOS rule. Raised
   twice, not ruled.
2. w_jmp_cut_p2 in bp_cluster.sv is read by nothing since DOC-007; the
   comment at lines 563-568 is stale. Recorded: removed by the next BP
   task that edits bp_cluster.sv. Jeff answered "everything is
   accepted" to two options; confirm if in doubt.
3. ftb_upd_br_idx_u0 and ubtb_upd_t.br_idx are unread since BP-140 and
   kept RESERVED, as the flush ports (Jeff).
4. Session numbering: the history lines say session-081 throughout;
   BP-140's header says PA session 082.
5. Line citations in the fe_demo descriptions go stale with every RTL
   task: DOC-007 found 188 wrong of about 1570 after BP-139 and
   BP-140. Every BP task that edits a cited file leaves the docs
   wrong until the next DOC task.
6. The proposed read rule (Read This First 5) is in task files only.
   Whether it goes into PROJECT_CORE's prompt generation rules was
   asked, not ruled.

---

## Session Summary

### Rulings by Jeff

```
  record fixes     PROJECT_CORE Tools Status, layout and inventory;
                   fe_demo_tb_decisions row; ittage_cntrl_uaon_update_
                   rules.md added to check_planning.sh
  BP-138           D1 option b accepted (provisional); D2 RAS fix
  read rule        ask before any read outside manifest and grants
  DOC-006          one-slot default build, 2-slot build for FD-3 and
                   FD-22 to FD-24; the three new scenarios; the format
                   table; encoded fields Unsigned with the encoding in
                   the description; the IA's choices accepted
  TD#179           every branch is predicted at every slot count; the
                   BP-128 D2 hold lifted; XiangShan's choices adapted;
                   no performance study needed ("a flaw no other
                   design has"); training stays at resolve
  task files       move to the IA; the PA's BP-139 draft withdrawn
  BP-139           option A (the cut for any unslotted branch) and
                   item C (no training through another branch's slot),
                   both slot counts; accepted
  BP-140           4.6 reopened; per-start FTB and uBTB entries; the
                   split at update; complete; provisional choices
                   accepted; fd13 and fd23 to the next DOC task
  TD#168           CLOSED by BP-140
  TD#189-193       opened (below)
  TD#190           Jeff reopens "track every branch" for measurement
  br_idx ports     kept reserved
  DOC-007          the PA writes it; everything accepted: FD-23
                   re-pointed at the split, FD-13 re-timed, a leading
                   "0. Introduction" allowed (FDT-12c, FDT-13)
```

### Tasks run

```
  BP-138   RAS empty test kept exact (bottom bit, TOSR moves with BOS,
           undo to BOS); jump in no slot ends the block (D1 option b).
           Written by the PA. 274 PASS
  DOC-006  fe_demo at one slot; 2-slot build; FD-22 to FD-24; format
           table FORMATS; all descriptions to their build.
           Written by the PA. 274 PASS
  BP-139   option A cut; item C; placed-slot write rule. Written by
           the IA. 274 PASS
  BP-140   per-start FTB and uBTB entries; split at update; FA1; RAS
           BOS fix (TD#189). Written by the IA. 274 PASS. tb_fe_top
           cycles 36095 -> 30840 (two slots), 38381 -> 31697 (one)
  DOC-007  FD-23 on the split; FD-13 re-timed; 188 citations fixed;
           fd09 rewritten; section 0 allowed. Written by the PA at
           Jeff's request. 274 PASS
```

### Documents changed this session

Every file below is in check_planning.sh with its new checksum.

```
  PROJECT_STATUS.md, PROJECT_CORE.md
  arch:   ras_decisions, fe_decisions, ftb_decisions,
          ftq_entry_formats
  intf:   ras_interfaces, ftb_interfaces, ftq_bpu_interfaces,
          ubtb_interfaces
  test:   fe_demo_tb_decisions
  show:   fe_demo_scenarios
  misc:   ras_theory_of_operation
  check:  ittage_cntrl_uaon_update_rules.md added (unchanged file)
```

---

## Next session (082)

No task is written. Jeff chooses the order. Task files are the IA's.

### Job A: the scenario descriptions.

fd09, fd22, fd23 and fd24 are in the FDT-13 form; the other 20 are
not. Jeff edits by hand and wants a section 0 (allowed since DOC-007).

### Job B: the TD#188 counters (FDT-10b).

Unchanged from handoff 081: counters from init-ready to the result
line; holds by ftq_decisions.md 4.5 cause; FTB updates by kind;
Jeff's notes.md for the baseline; FDT-10a format.

### Job C: the diagrams.

fe_block.svg and fe_pipe.svg, from the PA's mk_fe_block.py and
mk_fe_pipe.py; ask Jeff for them. BP-140 changed the FTB and uBTB
organisation, so fe_block.svg may need the per-start identity.

### TD#179 and the new TDs.

TD#179 still holds the entry shape (2+1 leaves fields unused under the
split), training at resolve or commit, and per-start occupancy on
compiled code. TD#189 to TD#193 are open; TD#190, 191 and 193 bear on
the uBTB and FTB design directly.

### Small items, not tasked

```
  chk_sucl.py     the viewer default duplicated with rtl/Vars.mk
  explainer       one TRICOLON in demo_explainer.md section 7 (PA's
                  DOC-004 text); not checked since DOC-007
  make view       fall back to a Surfer .ron state file when present
  Surfer          as a submodule built into tools/bin; not decided
  FD-U item       an optional scenario showing an H1 hold
  stale comments  fe_top.sv:30-32, :52-54, :69, :273, bp_cluster.sv:194,
                  ftq.sv:200; bp_cluster.sv:563-568 (w_jmp_cut_p2);
                  fe_tb_dut.svh declares itlb_l2t_acc and itlb_l2t_priv
                  after fe_top dut (.*) uses them
  shared models   ERROR: and tb_fe_top: lines outside the FDT-10a
                  format; changing them touches tb_fe_top
  csr_pkg.sv      henvcfg_t comment names only the ADUE read rule
  trace writer    FDT-U1; TR-U1 to TR-U4 wait on the trace format
```

### Open, not tasked

```
  Technical Debt   TD#2, 3, 6 (rename, dispatch, vector execution);
                   TD#173 (cachegen CG-5)
  Perf / Verif     TD#80, 85, 86, 93, 98, 118, 120, 128, 133, 149,
  Debt             150, 179; TD#180, 181 (coverage); TD#183, 184;
                   TD#185 a walk for a flushed fetch holds the walker;
                   TD#186 one p0 hold for every predictor;
                   TD#187 FTB updates that change nothing cost a p0
                   bubble;
                   TD#188 the p0 hold and FTB update counters (Job B);
                   TD#189 RAS BOS on a pop commit after a TOSW wrap;
                   TD#190 track every branch vs taken-only insertion;
                   TD#191 uBTB organisation vs XiangShan's FauFTB;
                   TD#192 a split update can be dropped by
                   ftq_ftb_sched;
                   TD#193 the uBTB re-allocates a split entry with the
                   full-block end
```

### Pending rulings, not raised

```
  CSR-3            the sc_enable rule (PROPOSED); closes FE-U6
  CSR-5 vsatp      unsupported MODE ignores the whole write (PROPOSED)
  CSR-U1           names for the CSRs at 0x7C0 and 0x7C1
  dcd 10b          the PA additions dcd_decisions.md 10b lists
  git amendment    the session-075 ruling item 3 amendment
  L1I-U7           prefetch reserve on the link or the node
  CG-U1, CG-U2     cachegen_decisions.md 5
  FE-U4, FE-U5     PHR in the hashes; indirect chain update
  CU-03, CU-04     tage_coverage_plan primary-provider CTR rows
  FE-17 group      the group for the ungrouped fe_top outputs (D5, D6)
  TR-U1 to TR-U4   fe_trace_decisions.md, with the trace writer
  read rule        into PROJECT_CORE (Worth your attention 6)
  ras_theory       scrub misc/ras_theory_of_operation.md (Worth your
                   attention 1)
```

### Later, in order

```
  benchmarks       compiled benchmarks and a backend model; TD#179's
                   occupancy item, TD#186, 187, 190, 191 wait on it
  formal flow      with the coverage exercise (TD#180, 181)
```

### Numbers

```
  next free BP     BP-141
  next free SYS    SYS-003
  next free DOC    DOC-008
  next free INFRA  INFRA-014
  next free TOOLS  TOOLS-007
  next free TD     TD#194
```

---

## Front end and demonstration facts, for reference

```
  FTB / uBTB     one entry per block start PC (BP-140); FTB tag
                 {VA[39:14], VA[4:1]}, index VA[13:5] XOR
                 (VA[4:1] << 5); positions and end start-relative; an
                 entry holds at most NUM_PRED_SLOTS branches; the end is
                 the PC of the first branch not kept
  cluster cut    BP-139 option A, a backstop; 0 events in tb_fe_top
  item C         a placement into an occupied slot trains the uBTB and
                 FTB only
  RAS            TOSR == BOS exact (bottom bit, BP-138); a RETURN
                 commit with an empty-stack snapshot leaves BOS (BP-140)
  builds         obj_fe_demo at NUM_PRED_SLOTS = 1, obj_fe_demo_2slot
                 at 2; SCEN_2S: fd03, fd22, fd23, fd24
  scenarios      fd01..fd24, make fdNN_<name>; make -k scenarios
  formats        the table FORMATS in waves/fe_demo_sigs.py (FDT-12a)
  markers        from a description in the FDT-13 form, with an
                 optional leading "0. Introduction"; the table found by
                 its "4. Events" heading
  view           make view S=<s>, the scenario's own model
```

---

## IA behaviour, recorded

- The IA wrote BP-139 and BP-140 from the TD#179 note and Jeff's
  rulings; both met their Deliverables. BP-140 marked itself
  in-progress for two fe_demo proofs it could not edit; Jeff ruled it
  complete.
- The IA found and fixed a RAS defect in BP-140 (RS2 fired once
  predictions changed), and in BP-138 withdrew its own first RAS fix
  when its property exposed a hole.
- Reads outside the grants: BP-138 and DOC-006 read without asking
  (rtl/Vars.mk, sram_init.sv); BP-139 onward asked first through
  AskUserQuestion. DOC-007 read a memory note under ~/.claude.
- DOC-007 used read-only agents to check about 1570 line citations.
- The IA's TD#179 note framed the defect as a block-boundary problem
  correctly; the PA did not.

---

## Postmortem Record -- PA performance (session-081)

RULING (Jeff): the PA repeatedly failed to accomplish tasks in its
role this session. Task file generation moved to the IA.

1. TEMPLATE NOT FOLLOWED. BP-138 renamed "Specific Requirements" and
   dropped the Deliverables note, against the input's "follow the task
   template exactly". Asked why, the PA gave reasons in place of the
   fact, and had said it read the inputs in full when it had not read
   them line by line.

2. UNCHECKED BACKGROUND. BP-138 carried the IA note's claims into the
   Background unverified; the IA corrected two. TREND: claims carried
   into prompts unchecked (BP-097, BP-112, SYS-002, BP-138).

3. WRONG CORRECTION OF THE IA. The BP-138 assessment called the Resume
   sha field an error; it holds a resume id, as labeled.

4. FILES ASKED FOR WITHOUT NEED. The regression summary, a find
   listing, fd07_calls_returns.md; Jeff asked why each time.

5. ARCHITECTURE STATED FROM MEMORY, WRONG. On TD#179 the PA stated
   XiangShan's entry organisation, a TAGE interface change and "the
   older XiangShan split rule", each wrong; the PA did not show it
   knew how to fix the defect. Jeff: out of its depth.

6. BP-139 (PA DRAFT) WRONG. Withdrawn; the IA wrote BP-139.

7. FLOW FINDING (Jeff): the overhead of passing files to the PA is not
   returned in better architecture choices. The PA works from pasted
   copies with no view of the tree; the architectural insight in
   session-081 came from the IA (D1 and D2 found by trial, the RAS
   root causes, TD#179 framed as block boundaries).

What worked: every IA planning instruction checked against the
installed copy before applying;
checksums verified on a temporary tree for every delivery; the
XiangShan V3 documents read and cited when Jeff asked, with what they
did not say marked unknown.
