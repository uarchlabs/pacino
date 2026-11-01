# Session Handoff 083
Written by Claude.ai during session-082.
Date: 2026-11-01

Read PROJECT_STATUS.md, then this file, then CLAUDE.md.

FOUR TASKS RAN THIS SESSION AND ALL ARE RECORDED: DOC-008, DOC-009,
DOC-010, DOC-011, all written by the PA at Jeff's request, all
complete. The showcase has release tags (SR-1 to SR-12), a separate
demonstration regression (tools/regress_demo.sh, 24 scenarios, 210
events checked), and real-publish guards. The RAS theory of operation
matches the RTL. TD#194 and TD#195 are OPENED. No task is written and
waiting. B11 (Jeff's re-edit of the 24 pages) is in progress, and Jeff
has proposed a new page format (Next session, Job A).

---

## Read This First

Handoff 082's rules 1 to 13 stand. Added or changed this session:

### 1. git is denied, not asked (Jeff).

.claude/settings.local.json moves "Bash(git *)" from ask to deny. In
DOC-011 the ask rule caught a git call buried in a seven-part command
and the prompt was approved by mistake (transcript: rule:localSettings,
user_temporary). The task-file git wording (082 rule 11) stays.

### 2. CLAUDE.md rules added this session.

- Commands run from the repo root, with no cd to an absolute path.
- Files, scratch scripts included, are created with the Write tool,
  not shell heredocs or redirects.
- Run time, Ctx %, Resume sha and the CONTEXT region are written by
  /cntx after the task, never by the IA during it.
- THE DEMONSTRATION REGRESSION IS tools/regress_demo.sh (FDT-2, 2a).

### 3. Run time is active time.

tools/run_time.py sums Claude Code's turn_duration entries, which
exclude time blocked on a permission prompt, and prints the wall time
beside it. DOC-009 was 2h15m active against 14h08m wall: 129 prompts,
one waiting 8h13m overnight.

### 4. Task files are the PA's again when Jeff asks.

DOC-008 to DOC-011 were PA-written on request. Each was diffed against
TASK_TEMPLATE.md (placeholders only) and checked for 80 columns and
ASCII. Context Loaded takes files only: tools/validate_and_extract.py
rejects a directory entry (DOC-009 failed it once).

### 5. Do exactly what Jeff asks, and no more.

Twice this session the PA changed more than asked (the regress.sh
columns; the mockup wording) and was told so. Make the change named;
offer anything further in one line.

### 6. Public copy: say what a reader does, plainly.

The tone rule of web_presence_plan.md (claim only what the data
shows) applies, and the reader is an engineer, not a child. "Run
something in five minutes" was false for a local build; the PA's
first replacements were vague. The final form is direct links and a
Quick Start with real times.

---

## Worth your attention

1. TD#194: a redirect restores the RAS pointers but not a recursion
   count changed on the wrong path. A candidate for fd07's unexplained
   count of 4. Needs a tb_ras case, then a ruling.
2. The seven figures misc/ras_theory_of_operation.md references are
   not in misc/; every image link in it is broken. Where they live is
   not known.
3. DOC-011's D1 to D4: four statements in the scenario pages disagree
   with the RTL (fd24_call_slot1.md 114-117; fd07_calls_returns.md
   152-153 and 172-173; demo_explainer.md 295, 306). Input for B11.
4. Event checks match rows by marker label, the first six words of the
   event text (FDT-10c). Rewording the start of an event in B11 fails
   that scenario in regress_demo.sh until the check's label changes.
5. FD-1's ready cycles (513, 1025, 2049) are checked by window, not
   exactly; DOC-009 took only cyc 0 as exact. For the task after B11.
6. tools/tests/ (55 tests from DOC-008 and DOC-010) was untracked at
   DOC-010's start. Confirm it is committed.

---

## Session Summary

### Rulings by Jeff

```
  tags             fe-<major>.<minor>.<patch>, annotated, applied by
                   Jeff; pages and waveforms from one tag; fe-1.0.0
                   after B11 and DOC-009 (SR-1 to SR-4)
  two regressions  regress.sh RTL only, gates pushes; regress_demo.sh
                   the scenarios, gates no push, blocks only a DOC
                   task that changes examples/fe_demo/ (FDT-2, 2a)
  events           every page gets an Events table; the 20 without one
                   from the run as a baseline; no events is valid
  no git for IA    publish_waves.py takes tag and commit as arguments;
                   Jeff runs the real tag, publish and CI
  publish guards   a real publish always checks the tag with git and
                   refuses a dirty rtl/ or examples/fe_demo/ (SR-9a,
                   SR-10)
  DOC-008..011     complete; the IA's provisional choices accepted
  /cntx            writes Run time, Ctx %, Resume sha, CONTEXT region
  git              deny, not ask
  TD#194, TD#195   opened
  status line      .claude/statusline.sh at the repo root
```

### Tasks run

```
  DOC-008  release tags: publish_waves.py tag gate, dry run, manifest
           tag and digests, staleness report; docs.yml takes the
           Showcase pages from the latest fe-* tag; README Release.
           274 PASS, 36 tests
  DOC-009  Events tables in all 24 pages; event checks (order, exact,
           window); regress_demo.sh; mk_sucl.py reads any Events
           section; one source list (fe_top_srcs.mk); Surfer rebuilt
           with wellen 0.21.1, chk_sucl 24/24, NU-UN-3 closed.
           274 PASS, demo 24/24, 210/210 events
  DOC-010  real-publish guards (SR-9a, SR-10); a status-strip bug
           fixed. 274 PASS, demo 24/24, 55 tests
  DOC-011  ras_theory_of_operation.md to the RTL, 45 changes; scenario
           check D1-D4; TD#194, TD#195 found. 274 PASS, demo 24/24,
           sim_ras 264/0
```

### PA-direct, no task

```
  regress.sh       a progress line per finished target: count, elapsed
                   NNmNNs, result, Makefile, target, time, estimate
                   left from .git/regress_times
  regress_demo.sh  a progress line per model build and scenario
  run_time.py      active time from turn_duration, beside wall time
  cntx.md          the /cntx command writes the header and CONTEXT
  settings         additionalDirectories /tmp/claude-1000; the broad
                   "Bash(python3 -)" allow removed
  known_failures_demo.txt   header, no entries
  record fixes     TD#179 note; Open Items 7 and 10 closed; Module
                   Status rows (cachegen_decisions, pacino_cache,
                   ras_theory); Tools Status (Spike, status line);
                   layout (examples/, misc/)
  web plan         version 5: B7, B12, the quick-start times, the tag
                   decision
  workbench mockup demo waveforms table (FD-09, FD-06, FD-02), Quick
                   Start with real times, "demos" throughout
```

### Documents changed this session

Every file below is in check_planning.sh with its new checksum.

```
  PROJECT_STATUS.md, PROJECT_CORE.md, CLAUDE.md
  arch:   ras_decisions, bp_arb_spec
  intf:   ras_interfaces
  test:   fe_demo_tb_decisions (FDT-1, 2, 2a, 10, 10a, 10c, 12c, 13)
  show:   showcase_release_decisions (new, SR-1 to SR-12, SR-6a, 9a)
  obsv:   new_user_decisions (NU-17, NU-UN-3)
  misc:   ras_theory_of_operation (by DOC-011)
```

---

## Next session (083)

No task is written. Jeff chooses the order.

### Job A: the demo page and signal-file format (Jeff, in progress).

Jeff's notes, 2026-11-01:

A. A standard page format. Required sections marked reqd:

```
  1    Introduction (reqd)
  1.1  Files (reqd, the files table)
  2    Run the scenario (reqd)
  3    The program
  4    Walkthrough (reqd)
  5    Events (reqd)
  6    Waveform (reqd): a table, columns group / signal /
       description, the group name not repeated within a group
  References and Footnotes
```

fd01_reset_init.md and fd09_tage.md are Jeff's models. The example
row list gave tb.cyc twice, assumed a typo.

B. The signal files: the marker signals in a group named markers,
placed immediately after the clock group.

The PA's proposal, not ruled:
- Draft from a planning document: the new FDT-13 replaces the five-
  section form; FDT-12a and 12c change for the groups. Events moves to
  section 5; mk_sucl.py finds it by heading, so the number is safe.
- The Waveform table is generated: one description per signal in
  waves/fe_demo_sigs.py, written into each page by mk_sucl.py and
  checked by chk_sucl.py (about 1100 signal lines across 24 files;
  by hand they would drift as the line citations did). Files (1.1)
  and Run (2) can be generated too.
- Order: FDT-13 drafted and approved; DOC-012 restructures the 24
  pages and generates the sections without changing prose; Jeff
  writes B11 into the new structure; DOC-013 brings event labels back
  and makes FD-1's readies exact.

OPEN QUESTION for Jeff, asked: a Surfer marker is a time on the
timeline, not a signal. Is the "markers" group (1) the signals each
event's check reads, or (2) something else, such as a signal the
testbench drives at each event? The PA needs fd01_reset_init.md and
fd09_tage.md to draft FDT-13.

### Job B: the path to the announcement.

```
  1  B7 (workbench page, from the mockup and plan v5) and B11 in
     parallel
  2  DOC-012 / DOC-013 (Job A)
  3  B10 ticfinder over the new copy
  4  fe-1.0.0: dry run, publish waveforms, push the tag, check the
     site names fe-1.0.0 on both pages and waveforms
  5  Phase C: blog post, LinkedIn, community posts, FAQ follow-up
```

### Job C, carried: the TD#188 counters, the diagrams.

As handoff 082 Jobs B and C. fe_block.svg may need BP-140's per-start
FTB and uBTB identity.

### Small items, not tasked

```
  demo_explainer   the "events checked" sentence (DOC-009 Deferred 2),
                   for Jeff's approval
  README header    examples/fe_demo/README.md SOURCE and UPDATED (DOC-008,
                   DOC-010)
  workbench        URLs /pacino/showcase/ and .../fe_demo/<s>/ assume
                   MkDocs defaults, not confirmed; the tiles link raw
                   markdown; DOC/task counts and "25 posts" hard-coded
  mockup file      .dc.html needs the canvas tool's support.js
  /cntx            reads of ~/.claude prompt; a Read(~/.claude/projects/**)
                   allow, or Read-tool reads in /cntx
  tag tests        delete any fe-0.0.x test tags before a push with tags
  NU-UN-7          fe_top's 84 targets in one job set the regression
                   length
  handoff-082      small items and stale comments carried (fe_top.sv,
                   bp_cluster.sv w_jmp_cut_p2, ftq.sv:200)
```

### Pending rulings, not raised

Handoff 082's list, less ras_theory (done, DOC-011). Plus:

```
  read rule        into PROJECT_CORE's prompt generation rules
  w_jmp_cut_p2     removal by the next BP task on bp_cluster.sv
  sandbox          a VM for the IA, after the announcement (Jeff)
```

### Numbers

```
  next free BP     BP-141
  next free SYS    SYS-003
  next free DOC    DOC-012
  next free INFRA  INFRA-014
  next free TOOLS  TOOLS-007
  next free TD     TD#196
```

---

## Front end and demonstration facts, for reference

```
  regressions    tools/regress.sh: 274 targets, about 9.5 min at 15
                 jobs, gates pushes. tools/regress_demo.sh: 2 models,
                 24 scenarios, 210 events, about 30 s, gates no push;
                 waivers tools/known_failures_demo.txt
  event checks   FDT-10c: order always; exact for stated values and
                 cyc 0; window max(8, cyc/10); a testbench-driven
                 signal reads at cyc + 1; rows matched by marker label;
                 tables generated by mk_sucl.py --svh at build time
  pages          Events read from any "Events" section; a cyc citation
                 with no Events section stops mk_sucl.py
  release        SR-1 tags; docs.yml takes Showcase pages from the
                 latest tag by git archive (SR-6a); publish_waves.py
                 --tag/--commit/--untagged/--dry-run/--published;
                 manifest keys tag, tag_commit, digest_version, digests
  Surfer         tools/bin/surfer, 010b840, wellen pinned 0.21.1
  RAS            linked spec stack (BP-120); at most one RAS slot per
                 block; same-cycle bypass reachable only in tb_ras;
                 VA_WIDTH 41
```

---

## IA behaviour, recorded

- Every task ran a regression and reported it; every Problem 0
  corrected at least one PA premise (Open waveform links added by the
  hook, FD-U1 closed, model build times, VA_WIDTH 41).
- git: DOC-008 ran a read-only git diff, disclosed; DOC-011 put a
  pointless git call inside a format-check one-liner, caught by the
  ask rule and approved; disclosed.
- Rule deviations disclosed each time (cd prefixes, scratch files by
  redirect, a grep outside the grants).
- DOC-009 found tools/bin/surfer was the wrong build and, with Jeff,
  pinned wellen; DOC-010 found the stripped-status bug; DOC-011 found
  TD#194.

---

## Postmortem Record -- PA performance (session-082)

1. INVENTED PATH. showcase_release_decisions.md was placed in
   planning/docs/, which is for generated-documentation planning;
   Jeff moved it to planning/showcase/.
2. DIRECTORY ENTRIES IN CONTEXT LOADED. DOC-009 failed the validator.
3. AN EXAMPLE FIGURE READ AS A RESULT. A made-up "2h41m" in a format
   example; Jeff asked whether it was real.
4. OVERREACH. The regress.sh line was redesigned beyond the two
   changes asked; the mockup wording was rewritten twice, vague and
   condescending, before Jeff gave the layout.
5. INSTALL ORDER. check_planning.sh was delivered with checksums for
   files Jeff had not installed; three DIFFER lines followed. Deliver
   the files and the script together, and say which go together.
6. A REQUEST MADE A PRECONDITION. Level 1 event checks were first
   made to wait on page re-edits; a scenario with no events is valid.

What worked: every planning change checked against the installed copy
before applying; every check_planning.sh update verified on a
temporary tree; the transcripts read to settle the run time and the
git question with evidence rather than inference.
