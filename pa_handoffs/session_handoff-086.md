# Session Handoff 086
Written by Claude.ai at the end of session-085.
Date: 2026-11-16

Read PROJECT_STATUS.md, then this file, then CLAUDE.md.

EIGHT TASKS RAN THIS SESSION AND ALL ARE COMPLETE: BP-145, BP-146,
BP-147, BP-148, TOOLS-007, BP-149, INFRA-014, INFRA-015. The paging
modes are done:
- VA_WIDTH 59 and PA_WIDTH 48;
- the walker and the ITLB in every mode of MMU-20;
- Sv57 the default the translated tests run under;
- tools/regress_weekly.sh covering every mode;
- the trace page-table generator, pt_gen.
The regression takes about 5 minutes warm, and tb_fe_top's cold build
is 55 s. No task is written and waiting.

THE INFRA-015 PLANNING SET IS NOT YET PUSHED. origin/main is at
2c34748. The set: rtl/CLAUDE.md (the Verilator rules), PROJECT_STATUS
(INFRA-015 recorded, TD#203 opened), CLOSED_TECH_DEBT (TD#201), and
check_planning.sh. Confirm it is in before building on it.

Job 1 next session is the PERF renumbering and the PERF-002 task file.
Job 2 is TD#202, the front-end delivery bandwidth.

---

## Read This First

Handoff 085's rules stand, with these changes and additions:

### 1. Reading (Jeff, session-085, replaces handoff 085 rule 1)

Read only what the work needs, until Jeff states the full-read
requirement again. For an assessment, find Jeff's own assessment in the
file first, and read the results sections the assessment depends on.
When a reminder says to read a file whole, do so.

### 2. A task that is running is not touched.

"Running" means running now. Do not edit the task file, and do not
re-send it in a later set. The IA writes its Results Capture into the
running copy, and a re-sent copy would overwrite it if committed. Both
happened this session: BP-145 was edited, and INFRA-014 was re-sent.

### 3. One home for each value.

A value is stated in exactly one place. Every other document names the
parameter, not the number. The homes:
- VA_WIDTH: fe_decisions.md FE-19.
- GPA_WIDTH: mmu_decisions.md MMU-20.
- FAULT_GPA_WIDTH: MMU-23.
- PA_WIDTH: l1i_ifu_interfaces.md IF-1.
- The FTQ widths: ftq_entry_formats section 1.

Do not refer to a rule only by the file that holds it. State what the
rule says.

### 4. Work from Jeff's sha.

Clone fresh at the sha Jeff gives, and say which commit a file comes
from. Ask for the sha when the planning files may have changed since
the last clone; do not ask when the change could not affect the work.
A set built on an earlier unpushed set says that it replaces it.

### 5. Task files.

- **Context.** Every file the IA must read is in Context Loaded, or is
  named with permission to read it. That includes the baseline's
  regress summary, by line range. BP-148 and TOOLS-007 missed this.
- **The standard Constraints** are INFRA-015's: the COMMANDS block, the
  Grep fallback, RVA_ROOT for scratch builds, and regress.sh once at
  the end in the background. Use them as written.
- **Background facts are checked before writing.** This session's
  errors: exp_gpf41, the "12 sites", the baseline sha, cache-hit times
  given as run times, and INFRA-015's hypothesis. Problem 0 caught
  them; it should not have had to.
- **A measured quantity is defined as Jeff means it.** INFRA-014's
  "cold" disabled the cache for every Makefile, when the figure that
  mattered was cold for tb_fe_top only.
- **No SKIP.** A test whose stimulus exists only in some modes tests a
  mode's limit and names its mode (PROJECT_CORE.md).
- **The prefix follows the purpose.** Regression and build time is
  INFRA, not BP.
- **Numbers follow the order of work.** Do not skip a reserved number.

### 6. CLAUDE.md holds rules, not narrative.

Write it in the imperative, and give no task references. Jeff rejected
the IA's text, and then the PA's first two drafts, for this.

### 7. Terms.

- **Fetch** is the L1I read: a 64-byte line, or two lines when the
  block starts in the upper half of a line (IFU-7).
- **The prediction block** is what the predictors cover and the IFU
  delivers per cycle: 32 bytes.
Do not confuse the two.

### 8. Answer the question asked.

Do not add history or background Jeff did not ask for. P870 as a
reference had nothing to do with "pacino needs two taken branches".

---

## Worth your attention

1. The INFRA-015 planning set is unpushed (above).
2. fe_demo has only been built, not run, on the new shared CSR model
   (class methods since INFRA-015). The next regress_demo.sh, at the
   next tag move, is its check.
3. A regress.sh with a cold tb_fe_top inside it has not been measured.
   It is expected near 5 minutes. The first push after a tb_fe_top edit
   shows it.
4. Stale build output, for Jeff to delete: fe_top/obj_dir and
   fe_top/obj_1slot_fe_top.
5. pacino_features.md still describes fe-1.0.0 (Sv39, PA 36).
   examples/fe_demo is regenerated before the next tag.
6. The two accidental artifacts from session-084 (handoff 085, item 6)
   are not mentioned since. Delete only if Jeff says so.

---

## Session Summary

### Rulings by Jeff

```
  widths        VA_WIDTH 59; PA_WIDTH 48 (was 36); GPA_WIDTH 59
  modes         MMU-20: Bare, Sv39, Sv48, Sv57 and the x4 modes, one
                build; MMU-32 levels and the 16 KiB x4 root
  MMU-33        an unsupported MODE is walked and checked as Sv39
  ITLB          ITLB-3 512 GiB and 256 TiB pages; ITLB-18 the check
                per mode; IL-7 only 3'b11x reserved
  CSR           debug_support at 0x7C2: bit 31 allow_all_satp_writes,
                bit 30 allow_all_vsatp_writes, reset 0 (TD#198)
  tests         Sv57 the default; regress_weekly.sh every mode, by
                hand; a test of a named mode or of a mode's limit
                names its mode; no SKIP
  PF-16/PF-17   traces behind Sv57 page tables; pt_gen's leaf flags,
                table placement and image format
  regression    INFRA-014 and INFRA-015 as built
  debt          closed rows move to CLOSED_TECH_DEBT.md in the update
                that closes them
  front end     pacino needs two taken branches per cycle and a
                64-byte prediction block (TD#202)
  PERF order    PERF-002 the delivery-bandwidth scan; PERF-003 the
                trace gasket (renumber not yet applied)
  reading       read what the work needs (Read This First 1)
```

### Tasks run

```
  BP-145     VA_WIDTH 59 and the width cleanup
  BP-146     the walker in every mode; pt_build_pkg
  BP-147     PA_WIDTH 48; the pacino L1I edited to it
  BP-148     the ITLB in every mode; tb_fe_top on pt_build_pkg;
             programs sv48, sv57, h57
  TOOLS-007  Verilator 5.048 drops a self-store across a same-object
             call loop; rule in rtl/CLAUDE.md
  BP-149     Sv57 default (+PT_MODE); tb_ptw on the builder;
             regress_weekly.sh; pt_gen and sim_ptw_img
  INFRA-014  one tb_fe_top build per slot count; slot1 in parallel;
             pt_gen error targets
  INFRA-015  tb_fe_top cold build 711 s -> 55 s; oracle by an
             absolute path; slot1 runs in its own directory
```

### Planning changed

- Debt and process: the closed technical debt moved (116 rows) and
  BLOG_GENERATION_PROCESS corrected. check_planning.sh covers 74 files.
- Rules: PROJECT_CORE gained the translation modes and the regression
  job layout; rtl/CLAUDE.md gained the Verilator rules (TOOLS-007,
  INFRA-015).
- Opened:
  - TD#198: debug_support.
  - TD#199: cachegen at PA_WIDTH 48.
  - TD#200: the Verilator report.
  - TD#202: front-end delivery bandwidth.
  - TD#203: tb_fe_demo's cold build.
- Closed: TD#201.

---

## Next session (086)

### Job 1: the PERF renumbering and PERF-002

Neither PERF-002 nor PERF-003 is written, so the numbers follow the
order of work (Jeff):
- PERF-002 becomes the delivery-bandwidth scan, PROJECT_STATUS's
  "PERF-003 TO BE WRITTEN".
- PERF-003 becomes the trace gasket.

Change every mention of each:
- perf_decisions.md PF-17, "PERF-002's gasket", twice;
- the PROJECT_STATUS entries that name them;
- TD#133;
- TD#202.
Next free stays PERF-004.

Then write PERF-002, which uses no RTL:
- Read the CBP traces through tools/scan_traces.py's reader.
- Measure the instructions between taken branches.
- Report the average delivered per cycle against 8 for three shapes:
  1. a 32-byte block with one taken branch (today);
  2. a 64-byte block with one taken branch;
  3. a 64-byte block with two taken branches.
- Model the block start as any 2-byte address (IFU-6).
- The traces are Arm's: every PC is 4-byte aligned and no record
  carries instruction bytes (PF-1). So bytes depend on the fraction of
  instructions that would be compressed. Report each shape over a range
  of that fraction, for example 0, 30 and 50 percent.

### Job 2: TD#202, after PERF-002

A planning note before any RTL task. It covers:
- the uBTB and FTB entries;
- the predictors, and history update with two taken per cycle;
- the RAS;
- the FTQ entry;
- the IFU;
- the L1I reads per cycle;
- the ibuf write;
- the rulings it reverses: session-073's one block per cycle (TD#133,
  ftq_ifu_interfaces.md 8 item 2), and FTB_BLOCK_BYTES 32.
Decode width is 8 (IBUF-9).

### Then

- PERF-003, the gasket. It runs traces through fe_top on pt_gen's
  images (PF-17).
- TD#203: tb_fe_demo's cold build.
- TD#198, TD#199 and TD#200.
- INFRA-016, the bpu 1-slot split. It is a candidate only, if a warm
  run is well over 5 minutes.
- Carried from handoff 085: Job B (B7, B11, B10, the next fe-* tag and
  Phase C); TD#196 and TD#197.

### Numbers

```
  next free BP     BP-150
  next free SYS    SYS-003
  next free DOC    DOC-017
  next free INFRA  INFRA-017   (INFRA-016 is the bpu-split candidate)
  next free TOOLS  TOOLS-008
  next free PERF   PERF-004    (002 the scan, 003 the gasket)
  next free TD     TD#204
```

---

## IA behaviour, recorded

- **Problem 0 found real errors** in the PA's Background in every task,
  and reported them before working.
- **The IA settled questions by measurement:**
  - BP-148's replay proved that no table address moved.
  - TOOLS-007 used a control run and -fno-life.
  - INFRA-015 measured first, and so overturned the PA's hypothesis.
- **The IA found faults no check would have caught:**
  - tb_csr_tb_pkg's 34-bit pmpaddr width (BP-147);
  - five tests that relied on the old Sv39 default without naming it
    (BP-149);
  - Verilator folding pass_cnt to 0 (INFRA-015), which it proved
    harmless with 84 logs compared line for line.
- **The IA asked when the task was wrong**, instead of guessing:
  - fe_demo's direct use of the writer helpers (BP-148);
  - permission for files missing from Context Loaded.
- **Deviations were disclosed every time**:
  - the Grep tool was missing, so grep ran through Bash;
  - occasional cd, loops and shell variables;
  - approval waits from shell variables cost BP-147 much of its run
    time.

---

## Postmortem Record -- PA performance (session-085)

1. **A running task edited.** The PA read "running" as "set up to run"
   and edited BP-145 while it executed. Later it re-sent INFRA-014's
   file, unchanged, while it ran.
2. **Raw numbers in 27 files.** Widths were written as values, and
   then redone with one home each.
3. **Facts stated without checking:**
   - vsatp.PPN was given as 47 bits;
   - the PF-16 counts came from minimum and maximum PCs;
   - BP-149's and INFRA-015's Background errors (Read This First 5).
4. **The validator run in the clone again.** This is handoff 085's item
   11, repeated.
5. **Who edits.** The PA asked "do I edit the L1I copy"; the IA edits.
   The PA also floated 0x7B0 and 0x800 as CSR ranges after a typo.
6. **Measures defined wrongly.** INFRA-014's "cold", and a SKIP rule
   that let tests check nothing.
7. **Terms confused.** Fetch and the prediction block.
8. **Answers padded.** P870's history, given in reply to a requirement.
9. **CLAUDE.md drafts as narrative**, with task references. Two drafts
   were rejected.
10. **Numbering and prefixes.** BP used for an INFRA task, and the PERF
    order inverted.
11. **Inconsistent about the sha.** The PA asked for it when it was not
    needed, and Jeff's own correction then showed that the push had
    been needed.

The common cause: answering from what was nearest to hand, an old
reading, a habit of format, a guessed mechanism, instead of from the
files and the question. What worked:
- the full-authority task with a measure-first step (INFRA-015);
- fresh clones named by commit;
- line-multiset checks on every mechanical move of planning text.
