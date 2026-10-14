# Session Handoff 080
Written by Claude.ai during session-079.
Date: 2026-10-14

Read PROJECT_STATUS.md, then this file, then CLAUDE.md.

THREE TASKS RAN THIS SESSION, BP-133, BP-134 AND SYS-001, AND ALL
THREE ARE RECORDED. TD#178 IS CLOSED: planning/arch/csr_decisions.md
exists and SYS-001 built it. A NEW TASK SERIES, SYS, began. The next
session starts by writing and issuing SYS-002 (section "Job 1" below
has everything needed). BP-135, a front-end clean-up batch, follows.

---

## Read This First

### 1. Scope is Jeff's, every time.

Nothing is opened, written into a document or put in a task without
Jeff ruling that item by name. But do not ask Jeff to rule on what the
PA can simply decide and write down (a file location, a placeholder
name). Session-079 asked him where a package should live: "why do you
need the location of a package that does not exist ?"

### 2. Planning documents are written for the IA.

csr_decisions.md took many drafts. What Jeff required, in the end:
- State the organization, the implemented bits and how they connect
  to the RTL. Nothing else.
- No narrative, no justification, no history of how a rule came to be,
  no statements about the current state of the tree ("there is no CSR
  file").
- No provenance IDs (FE-20, MMU-24a, ITLB-7). State the fact itself.
- No other project's name (XiangShan) in a pacino document.
- References at the bottom, with URLs.
- Every internal cross-reference resolves inside the document.
- Plain tone; no capitalised emphasis.
Review the whole document line by line before sending it. Jeff: "go
through the entire document again. you are half ass-ing this work".

### 3. Verify before stating.

Do not describe a tool, a specification or a repository from a search
summary. Session-079 described UDB from slide summaries, oversold it,
and claimed things about custom CSRs it had not checked. Clone or fetch
the primary source, check it, and say what was and was not checked.
Bit positions and CSR addresses were checked against Spike's
encoding.h and riscv-opcodes csrs.csv; the HTML specification gives
field positions only in figures the PA cannot read.

### 4. Do not invent dependencies.

Session-079 made a scope question depend on "the backend's CSR file",
which exists in no document, then made it a requirement. Jeff: "why
did you make it an requirement ?"

### 5. Ask for files first, read what is used, say when a read is
partial.

When asked "did you read every line", the true answer this session
was no. Read fully before reporting.

### 6. Issue files when they change.

Every changed file is sent with PROJECT_STATUS.md and check_planning.sh
together, without being asked. Do the edit; do not hand Jeff a script
to run for an edit the PA can make.

### 7. The git wording, verbatim in every task file.

"the IA runs no git command. It may run tools/regress.sh, which makes
git calls of its own; that grant is to run the script, not to run any
command the script contains. Reading regress.sh to see what it calls
grants nothing either."

---

## Session Summary

### Rulings by Jeff

```
  doc conflicts     closed TD rows rewritten to begin CLOSED ("Was:"
                    kept); the PA's other conflict findings set aside
                    as suspect
  TD#18             keep BP-133's fix: T0 trains as the use_alt_on_na
                    provider (rows 19.1-19.8)
  TD#78             keep BP-133's fix: the undo restores recursion
                    counts
  TD#79             closed, not a defect; commit_rctr removed (BP-134)
  TD#89, TD#90      closed without FTB storage (ftq_upd_conv forms
                    both)
  TD#182            opened and closed: the T0 counter is read as
                    {ctr[1], ctr[0], ctr[0]} (BP-134)
  BP-134            accepted, provisional choices D1-D3 included
  TD#178            csr_decisions.md: both groups (config and csr);
                    custom CSRs 0x7C0 (enables), 0x7C1 (intervals);
                    ext_enable not a CSR; RTL ports become struct
                    types; resets from tb_fe_top
  SYS series        new, for system-level work; SYS-001 first
  SYS-001           accepted; pt_ad_h 1435 -> 1395 accepted;
                    provisional choices accepted
  CSR-5 additions   henvcfg.PBMTE read-0; pmpcfg R=0/W=1 stored W=0;
                    pmpaddr locked by next entry's TOR lock. Implemented
                    by SYS-002
  MMU-24a, IF-30,   confirmed
  IF-36
  TD#74             folded into BP-135
  TD#183, TD#184    opened, Performance / Verification Debt
  ras_theory doc    added to check_planning.sh (location MISC);
                    TD#101 and commit wrap corrected
```

### Tasks run

```
  BP-133   TD#18, 78 fixed provisionally (kept); TD#79 not a defect;
           TD#89/90 already served by ftq_upd_conv. 265 PASS. No
           tb_fe_top figure moved
  BP-134   TD#182 (T0 3-bit mapping); tb_tage sampling race; commit_rctr
           removed; saturated undo-push fixed; rec_undo program;
           comments. 267 PASS. 10 programs changed at 2 slots, 9 at 1,
           all from TD#182
  SYS-001  csr_pkg, csr_tb_pkg, struct ports, 15 testbenches moved.
           270 PASS. pt_ad_h 1435 -> 1395 (accepted)
```

### Documents changed this session

Every file below is in check_planning.sh with its new checksum.

```
  PROJECT_STATUS.md
  arch:   csr_decisions (new), mmu_decisions, ras_decisions,
          sc_decisions, tage_cntrl_ctr_update_rules,
          tage_cntrl_decisions
  intf:   l1i_ifu, ras, sc, tage, ubtb
  misc:   ras_theory_of_operation (new to check_planning.sh, MISC)
```

---

## Next session (080)

### Job 1: write and issue SYS-002.

SYS-002 is ruled (Jeff, session-079); it is not yet written. Files the
PA needs to write it: planning/arch/csr_decisions.md (as delivered,
checksum in check_planning.sh), prompts/SYS-001.md (its Results
Capture names the tests and lines below), and the task template. No
RTL is needed.

Contents:
1. Baseline: tools/regress.sh, with every tb_fe_top program's retired,
   cycles and mispredicts at 2 and 1 slots.
2. Implement in csr_tb_pkg the three CSR-5 rules not yet built:
   - henvcfg.PBMTE reads 0 when menvcfg.PBMTE is 0, at csr_read and in
     pack_ptw_csr; the stored bit is kept (as for ADUE)
   - a pmpcfg entry written with R = 0 and W = 1 is stored with W = 0
   - pmpaddr[i] is not written when entry i+1 is locked with A = TOR
     (pmpaddr15 has no next entry)
   with tb_csr_tb_pkg checks for each, each shown to fail with the rule
   removed.
3. Expected fallout, the same as ADUE in SYS-001: tb_fe_top pt_rsv_h
   (W.csr_env(0,0,0,1)) and tb_ptw h_g_pbmte set henvcfg.PBMTE 1 with
   menvcfg.PBMTE 0, which no CSR write can produce. Under the rule both
   change; the IA updates their expectations and reports every changed
   figure and count.
4. Restore tb_pmp_pma_chk's coverage of the PMP checker's own low-bit
   masking at G = 10 (checks G5-G8b, which since SYS-001 receive
   pmpaddr as software reads it back). Method is the IA's to propose
   (for example a csr_tb_pkg pack of stored values without read-back
   rules, used only by that testbench); proof is a mutation of the
   checker's masking that fails those checks.
5. Report whether any test covers the G-stage guest-page fault on a
   VS-stage A-bit update when the G-stage leaf does not grant write
   (implicit-access kind 10, mmu_decisions.md MMU-8a). SYS-001 removed
   the Svade path to that fault; if no test reaches it, add one in
   tb_ptw.
6. Measurement at 2 and 1 slots against the baseline; regression
   passes; every changed count listed with its reason.
Write access: rtl/core/csr, the tb directories of fe_top, pmp and ptw,
and prompts/SYS-002.md. Planning documents read-only; proposed text in
Results Capture.

### Job 2: BP-135, front-end clean-up batch.

Proposed by the PA; TD#74 is ruled into it (Jeff), the rest is not yet
ruled. Put the list to Jeff before writing:
1. sim_tage_manual reports "-/0": regress.sh cannot read its count
2. BP-133's TAGE rows 19.x seed counters against their own prediction
   direction (results right, states unreachable)
3. no tb_fe_top program reaches the 19.x case (T0 as the
   use_alt_on_na provider)
4. ubtb.sv body comment, "combinational from registered mem" (BP-134
   Deferred Work)
5. Open Item 13, sc_ready strapped under fast init: check whether
   BP-126's sim_bp_cluster_init overtook it, and close
6. ittage_table_interfaces.md use/EPC write-enable note: check against
   the ITTAGE RTL and report
7. TD#74: report what covers the slot-1 TAGE and ITTAGE update path

### Open, not tasked

```
  Technical Debt   TD#2, 3, 6 (rename, dispatch, vector execution);
                   TD#74 (into BP-135); TD#173 (cachegen CG-5)
  Perf / Verif     TD#80, 85, 86, 93, 98, 118, 120, 128, 133, 149,
  Debt             150, 168, 179; TD#180, 181 (coverage); TD#183 (hist
                   after TD#182); TD#184 (RAS recursion counts on
                   wrong paths)
  comments         bp_history.sv and tb_bp_history.sv comments still
                   mention XiangShan; change only if Jeff asks
```

### Pending rulings, not raised

```
  CSR-3            the sc_enable rule (PROPOSED); closes FE-U6
  CSR-5 vsatp      unsupported MODE ignores the whole write (PROPOSED)
  CSR-U1           names for the CSRs at 0x7C0 and 0x7C1 (CSR_7C0,
                   CSR_7C1 until named)
  dcd 10b          the PA additions dcd_decisions.md 10b lists
  git amendment    the session-075 ruling item 3 amendment
  L1I-U7           prefetch reserve on the link or the node
  CG-U1, CG-U2     cachegen_decisions.md 5
  FE-U4, FE-U5     PHR in the hashes; indirect chain update
  CU-03, CU-04     tage_coverage_plan primary-provider CTR rows
```

### Later, in order

```
  benchmarks       compiled benchmarks and a backend model for
                   performance numbers; TD#179 and the Performance /
                   Verification Debt rows wait on it
  formal flow      with the coverage exercise (TD#180, 181)
```

### Numbers

```
  next free BP     BP-135
  next free SYS    SYS-002
  next free INFRA  INFRA-014
  next free TOOLS  TOOLS-007
  next free TD     TD#185
```

---

## IA behaviour, recorded

- BP-133 and BP-134 both edited RTL while their own baseline regression
  was still running in the same tree. Each stopped the run, restored
  the files and reran the baseline (BP-133 on a scratch copy, so its
  baseline has no git sha). Both disclosed it. Worth a line in the next
  task: run the baseline to completion before any edit.
- SYS-001 reports Ctx 100%+5%. Its Results Capture is complete and its
  regression summaries check out target by target.
- No departure from a grant was reported for BP-133, BP-134 or SYS-001.
  SYS-001 needed no edit to rtl/Makefile or regress.sh: both find unit
  Makefiles themselves.

---

## Postmortem Record -- PA performance (session-079)

1. PARTIAL READ PRESENTED AS A REVIEW. Asked "did you read every
   single line", the answer was no. The full read was done only when
   Jeff required it.

2. SUSPECT FINDINGS. After the full read the PA listed document
   conflicts, several of them narrow readings or about history text.
   Jeff: "these documents have been scrubbed many times. I think you
   are creating problems."

3. SCRIPT INSTEAD OF EDIT. The PA wrote a script for Jeff to run for a
   PROJECT_STATUS.md edit it could make itself, then made it.

4. UNVERIFIED TOOL CLAIMS. UDB described from summaries and oversold;
   custom-CSR support claimed before it was checked. Jeff: "do you know
   what you are talking about regarding UDB ?" and "UDB's maturity is
   suspect."

5. INVENTED DEPENDENCY. A scope question built on a non-existent
   "backend CSR file", then made a requirement.

6. PLANNING DOCUMENT QUALITY. csr_decisions.md drafts were wordy, used
   narrative, named XiangShan, cited bare IDs, put references first and
   carried statements about the tree. Many rounds. Jeff: "you are
   half ass-ing this work", "you are wasting my tokens and time".

7. ASKED INSTEAD OF DECIDING. The package location was put to Jeff.

8. WRONG ASSUMPTION ABOUT STATE. The PA assumed SYS-001 had not been
   issued and planned around it.

What worked: regression summaries compared target by target by script
for every task; CSR addresses and bit positions checked against Spike;
checksums with every document change; the BP-134 measurement and the
SYS-001 pt_ad_h analysis.
