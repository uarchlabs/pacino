# Session Handoff 081
Written by Claude.ai during session-080.
Date: 2026-10-16

Read PROJECT_STATUS.md, then this file, then CLAUDE.md.

NINE TASKS RAN THIS SESSION AND ALL ARE RECORDED: SYS-002, BP-135,
BP-136, DOC-001, BP-137, DOC-002, DOC-003, DOC-004, DOC-005. SYS-002,
BP-135 and BP-136 finish session-079's jobs; DOC-001 to DOC-005 build
the front-end demonstration; BP-137 fixes the defect DOC-001 found.
TD#74 and Open Item 13 are CLOSED. TD#185 to TD#188 are OPENED. A
NEW TASK SERIES, DOC, began, with a new top-level directory,
examples/fe_demo. GTKWave is dropped; Surfer is the one viewer. No
task is written and waiting. The next session starts with section
"Worth your attention" below, then the jobs Jeff chooses from "Next
session".

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

### 3. Verify before stating, and say what was and was not checked.

Session-080 stated Surfer's state-file extension wrongly (".surf.ron";
it is .ron) and muddled whether Surfer saves a signal's format. Answer
about the tool Jeff names, from its source or documentation, not from
what the PA's scripts do. Jeff: "ignore the scripts I'm talking about
the tool".

### 4. Read IA prose critically before using it.

The IA's first fd09_tage.md was abbreviations without introduction
(W.wp, cskip, bcc, tk). The PA took it as a model without reading it as
a reader would. Jeff: "no one will understand this crap." When Jeff
points out faults, scrub the whole document, not only the lines he
named; he asked "did you fix just what i pointed out".

### 5. Ask for files first, read what is used, say when a read is
partial.

### 6. Issue files when they change.

Every changed file is sent with PROJECT_STATUS.md and check_planning.sh
together, without being asked. Checksums are md5, 12 characters,
verified by running check_planning.sh on a temporary tree.

### 7. The git wording, verbatim in every task file.

"The IA runs no git command. It may run tools/regress.sh, which makes
git calls of its own; that grant is to run the script, not to run any
command the script contains. Reading regress.sh to see what it calls
grants nothing either."

For a task that does not run regress.sh (DOC-005), the constraint is
"The IA runs no git command, not even a read-only one". Jeff removes
files with git himself: the IA lists files to remove and changes no git
state.

### 8. FIX WHAT YOU FIND goes in every task file.

BP-135's Problem 7 was report-only, so the gaps it found could not be
closed in the run (PA error). A fix not set by a planning document is
provisional and listed with its reason.

### 9. Writing rules for the descriptions (FDT-13a).

Full sentences; no jargon; no abbreviation the text has not
introduced; testbench variables, tasks and files named explicitly with
where they are defined; no "lands", no "shape", no "X but not Y"
framing. Checker: tools/ticfinder/tools/ticfinder.py. Lines at most 80
columns, ASCII.

---

## Worth your attention (from DOC-005)

1. The Surfer path is written in two places, rtl/Vars.mk
   (SURFER ?= $(HOME)/.cargo/bin/surfer) and waves/chk_sucl.py (default
   ~/.cargo/bin/surfer). A change to one must be made to the other. The
   fix would be a make target that runs the check and passes SURFER to
   it; small enough to fold into the next DOC task if Jeff wants it.
2. ticfinder reports one TRICOLON in docs/demo_explainer.md section 7,
   the paragraph starting "The descriptions give the full path in
   Surfer's form." That was the PA's DOC-004 text, so it is the PA's to
   fix, unless Jeff fixes it in his hand edit.
3. Two items carried from DOC-004 are still open:
   - mk_sucl.py says nothing when a description has an event table but
     is not in the five-section form (FDT-13). It should warn.
   - fd09_tage.md gives the end of the run as cyc 1277, while the
     waveform runs to cyc 1377.
4. The DOC-005 Model field: the IA says it set "low"; the header says
   medium. It matters only if effort levels are being tracked.

---

## Session Summary

### Rulings by Jeff

```
  SYS-002          accepted; provisional choices accepted (grain-0 pack
                   for the PMP checks, the h_g_pbmte check,
                   pmpaddr_wr_ok a class helper)
  BP-135           all seven items; P-1 to P-5 accepted
  Open Item 13     closed (tb_bp_cluster H2b reaches the sc_ready guard)
  TD#74            kept after BP-135, narrowed; closed after BP-136: the
                   uaon update applies only with a tagged alternate, the
                   rule document follows the RTL
  showcase         a front-end demonstration in examples/fe_demo,
                   outside the regression, NUM_PRED_SLOTS = 2;
                   tb_fe_top's models factored into
                   rtl/core/frontend/fe_top/tb/models/
  DOC series       new, for the demonstration and its documentation;
                   new planning directories showcase/, observ/, docs/
  BP-137           the init fix is upstream: the FTQ withholds p0 until
                   tage_rdy, ittage_rdy and sc_ready are high
                   (ftq_decisions.md 4.5 H5); predictors unchanged
  fast init        every scenario but FD-1 uses the fast SRAM init
                   (FDT-7)
  trace writer     out of DOC-002, to a later DOC task (FDT-U1)
  descriptions     the five-section form (FDT-13), the reader, the
                   writing rules (FDT-13a), demo_explainer.md with the
                   glossary (FDT-13b)
  message format   FDT-10, FDT-10a: -I:/-E:, PASS/FAIL, 80 columns,
                   wrap after a comma with a four-space indent
  FD-18            covers IO pages as well as NC
  viewer           Surfer only; GTKWave dropped; make view S=<s>;
                   SURFER from rtl/Vars.mk with ?=; RUST_LOG from
                   SURFER_LOG, default warn
  TD#185-188       opened (below)
```

### Tasks run

```
  SYS-002  CSR-5 rules in csr_tb_pkg; PMP checker coverage restored.
           270 PASS
  BP-135   front-end clean-up batch; t0_uaon program. 272 PASS
  BP-136   slot-1 TAGE and ITTAGE update checks (TD#74). 272 PASS
  DOC-001  shared tb models; examples/fe_demo, FD-1 to FD-21; FD-1
           failed on the init-ready defect. 272 PASS
  BP-137   FTQ init-ready hold (H5); init_walk program. 274 PASS
  DOC-002  view targets, Surfer command files, counter fix,
           fe_top_connectivity.md, 20 descriptions. 274 PASS
  DOC-003  message format, cyc in every view, FD-18 IO page,
           demo_explainer.md, fd09_tage.md. 274 PASS
  DOC-004  Surfer only, name type Unique, formats, event markers,
           chk_sucl.py. 274 PASS
  DOC-005  SURFER workaround removed; DOC-004's docs/ text applied;
           chk_sucl.py viewer default and missing-viewer message
           (follow-ons by Jeff). No regression needed
```

Regressions were compared target by target by the PA for every task
that ran one; BP-137 to DOC-004 are identical at 274 targets.

### Documents changed this session

Every file below is in check_planning.sh with its new checksum.

```
  PROJECT_STATUS.md, PROJECT_CORE.md
  arch:   csr_decisions, ftq_decisions, fe_decisions,
          tage_cntrl_ctr_update_rules, tage_cntrl_uaon_update_rules,
          tage_cntrl_use_update_rules
  intf:   bp_arb_spec, ftq_bpu_interfaces, itlb_l2tlb_interfaces,
          ittage_interfaces, ittage_table_interfaces, sc_interfaces,
          tage_interfaces, tage_table_interfaces
  test:   fe_demo_tb_decisions (new)
  show:   fe_demo_scenarios (new)
  obsv:   fe_trace_decisions (new)
```

---

## Next session (081)

No task is written. Jeff chooses the order.

### Job A: the scenario descriptions.

Jeff judges the IA's descriptions not yet usable and is editing them by
hand; interactive IA sessions are the other route. fd09_tage.md is the
only one in the FDT-13 form; the other 20 are not. Wait for Jeff's
direction before writing a task.

### Job B: the TD#188 counters (FDT-10b).

Jeff said a prompt would come. When writing it:
- the counters start when the three init readies are all high and stop
  at the result line (the scratch counter of TD#187 ran to cyc+100,
  which is why its totals exceeded the scenarios' cycle counts);
- holds by cause as ftq_decisions.md 4.5 numbers them (H1 per predictor,
  queue full and starvation; H2; H3; H4), not by RTL name (h3_ftb_upd is
  H4);
- FTB updates in total, missed, and unchanged on a hit, each by
  conditional and jump;
- per-scenario expected figures from the TD#187 measurement as the
  baseline the IA checks against (Jeff's notes.md);
- printed in the FDT-10a format after the result line.

### Job C: the diagrams.

fe_block.svg (block diagram, 1820x1060; FDT-14 places it at
docs/fe_block.svg): Jeff liked it; may be
tweaked. fe_pipe.svg (pipeline view, 2050x840): delivered, no feedback
yet. Open: time alignment, size, whether to split it. The generators
are the PA's scripts mk_fe_block.py and mk_fe_pipe.py, sent with this
handoff; ask Jeff for them at the start of a session that changes a
diagram.

### Small items, not tasked

```
  mk_sucl.py      warn on an event table outside the FDT-13 form
  fd09_tage.md    end of run cyc 1277 against the FST's 1377
  chk_sucl.py     the duplicated viewer default (Worth your attention 1)
  make view       fall back to a Surfer .ron state file when present
  Surfer          as a submodule built into tools/bin (GitLab
                  surfer-project/surfer, EUPL-1.2; Codeberg mirror); a
                  TOOLS task; not decided
  FD-U item       an optional scenario showing an H1 hold
  stale comments  fe_top.sv:30-32, :52-54, :69, :273, bp_cluster.sv:194,
                  ftq.sv:200; fe_tb_dut.svh declares itlb_l2t_acc and
                  itlb_l2t_priv after fe_top dut (.*) uses them
  shared models   ERROR: and tb_fe_top: lines outside the FDT-10a
                  format; changing them touches tb_fe_top
  csr_pkg.sv      henvcfg_t comment names only the ADUE read rule
  trace writer    FDT-U1; fe_trace_decisions.md TR-U1 to TR-U4 wait on
                  Jeff's trace-format decision (Catscan-like DAG
                  discussed)
```

### Open, not tasked

```
  Technical Debt   TD#2, 3, 6 (rename, dispatch, vector execution);
                   TD#173 (cachegen CG-5)
  Perf / Verif     TD#80, 85, 86, 93, 98, 118, 120, 128, 133, 149,
  Debt             150, 168, 179; TD#180, 181 (coverage); TD#183,
                   TD#184;
                   TD#185 a walk for a flushed fetch holds the walker
                   (fd14, fd15);
                   TD#186 one p0 hold for every predictor;
                   TD#187 FTB updates that change nothing still cost a
                   p0 bubble (4300 of 5322 in the 21 runs);
                   TD#188 the p0 hold and FTB update counters (Job B)
  comments         bp_history.sv and tb_bp_history.sv comments still
                   mention XiangShan; change only if Jeff asks
```

TD#186 must be measured with TD#187 in place, or both together: H1 was
0 in all 21 runs, probably because the FTB-update bubbles drain the
predictor update queues first.

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
```

### Later, in order

```
  benchmarks       compiled benchmarks and a backend model for
                   performance numbers; TD#179, TD#186, TD#187 and the
                   Performance / Verification Debt rows wait on it
  formal flow      with the coverage exercise (TD#180, 181)
```

### Numbers

```
  next free BP     BP-138
  next free SYS    SYS-003
  next free DOC    DOC-006
  next free INFRA  INFRA-014
  next free TOOLS  TOOLS-007
  next free TD     TD#189
```

---

## Demonstration facts, for reference

```
  scenarios      fd01..fd21, make fdNN_<name>; make -k scenarios
  output         out/<s>/<s>.fst and .log (not committed)
  view           make view S=<s>: Surfer with waves/<s>.sucl (-c);
                 a .ron is Surfer's own state file (-s); Surfer never
                 writes .sucl
  command files  written by waves/mk_sucl.py from fe_demo_sigs.py and
                 the descriptions' event tables; checked by
                 waves/chk_sucl.py
  names, formats name type Unique; clk Clock, rstn Bit, cyc Unsigned,
                 enums Enum, others from fe_demo_sigs.py
  markers        c<cyc>_<label>, one per event row with a cyc value;
                 the view opens with zoom_to (Surfer 0.7 cannot
                 goto_marker from a command file)
  FST reader     fst2vcd, from the GTKWave distribution, stays a
                 dependency of the waves/ scripts
  holds          H1 queues, H2 FTQ full, H3 fault (r1_fault_hold),
                 H4 FTB update (RTL h3_ftb_upd), H5 init readies
```

---

## IA behaviour, recorded

- DOC-002 ran git show HEAD:examples/fe_demo/README.md once; DOC-004 ran
  git diff --stat once and read Surfer source outside the allowed set.
  Both read-only, both disclosed. DOC-005 followed the stricter wording
  ("not even a read-only one") and ran none.
- DOC-005's first attempt at a 20-file edit used one Python script; the
  permission check refused it before anything was written, and the IA
  made each edit with the Edit tool.
- DOC-005 took two follow-on edits from Jeff in the session, outside the
  task's write list (waves/chk_sucl.py), and recorded both in Results
  Capture as Follow-on 1 and 2.
- The IA's description prose is the weak point: correct facts, poor
  explanation. It corrected two factual errors in the PA's fd09 draft.

---

## Postmortem Record -- PA performance (session-080)

1. IA TEXT USED AS A MODEL UNREAD. The IA's first fd09_tage.md was
   taken as the model without reading it as a reader would. Jeff: "no
   one will understand this crap."

2. PARTIAL SCRUB. After Jeff's critique the PA fixed the lines he named
   and scrubbed the rest only when asked.

3. FACTUAL ERRORS IN A PA DRAFT. The fd09 listing left out the
   loop-body c.addi at 0x8000_0014, and section 3.1 gave the wrong
   cause of the TAGE allocations. The IA corrected both.

4. UNCHECKED HYPOTHESIS. SYS-002 predicted pt_rsv_h and h_g_pbmte would
   change and implied no test reached kind 10; neither was checked
   against ptw.sv or tb_ptw.

5. REPORT-ONLY PROBLEM. BP-135 Problem 7 could not close the gaps it
   found; BP-136 was needed.

6. TOOL FACTS STATED WRONGLY. The Surfer state-file extension; whether
   Surfer saves formats, answered about the PA's scripts instead of the
   tool.

What worked: regression summaries compared target by target for every
task; checksums verified on a temporary tree with every document
change; TD#186 and TD#188 drafts corrected against ftq_decisions.md
4.5 before they were recorded; the block diagram, drawn from the
connectivity inventory.
