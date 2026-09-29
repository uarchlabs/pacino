<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 074
Written by Claude.ai at end of session-073.
Date: 2026-09-22

Read PROJECT_STATUS.md, then this file, then CLAUDE.md.

SIX TASKS RAN AND THE TREE IS GREEN. TOOLS-006 built the regression
command, BP-109 to BP-114 cleared the FTQ and the BPU gates on the
IFU. Thirteen TDs closed, eleven opened. Every task ended with
tools/regress.sh at 78 of 78.

THE FTQ HAS NO OPEN TECHNICAL DEBT. The frontier is the IFU, and its
gates are rulings, not code: TD#134 and TD#135. TD#136 sits behind
TD#119 and cachegen.

---

## Read This First

### 1. Verify the tree before anything else.

```
  ./tools/regress.sh              78 targets, expect exit 0
  ./check_planning.sh .           expect every line MATCH
```

check_planning.sh's baseline is session-071 EXCEPT the files
session-073 changed, whose lines carry new checksums:
PROJECT_STATUS.md, l1i_ifu_interfaces.md, mmu_decisions.md,
ftb_decisions.md, ftb_interfaces.md, ubtb_interfaces.md,
ftq_bpu_interfaces.md, ftq_entry_formats.md,
ittage_table_entry_formats.md, ftq_decisions.md,
ftq_ifu_interfaces.md, ifu_decisions.md, ftq_backend_interfaces.md,
ifu_ibuf_interfaces.md. A DIFFER on any other file means something
was lost; a DIFFER on one of these means the delivered copy was not
the one installed.

The script's FILES block is fixed-column. A filename of 35 characters
or more collides with its checksum: ittage_table_entry_formats.md
did, and the script reported MISSING until the padding was fixed. Add
a row by hand with care, or give the script an update mode.

### 2. tools/regress.sh IS THE VERIFICATION CONTRACT NOW.

Built by TOOLS-006. It finds every Makefile under rtl/, classifies
every target from make's rule database, and fails a run if a target
is in neither the regress set nor the exclusion list, so the `make
all` gap cannot return under a new name. A target fails on a non-zero
exit OR on any %Warning. tools/known_failures.txt waives a listed
failure; a listed target that now passes, or that was not run, also
fails the run.

```
  tools/known_failures.txt   EMPTY. No waived failure in the tree.
                             THE IA NEVER EDITS IT. Jeff does.
  tools/hooks/pre-push       installed via core.hooksPath. A red
                             regression refuses the push.
```

FOUR TESTBENCHES REPORTED A FAILED CHECK AND EXITED 0 before
TOOLS-006 fixed them (tb_components, tb_rvc_expander,
tb_instr_decoder, tb_predecode). They now exit through $fatal(1).
Any new testbench must do the same or the gate is blind to it.

### 3. CLAUDE.md's Packages line still forbids what Jeff has
authorised three times.

The rule allows additions only and forbids changing or removing a
declaration. BP-109, BP-111 and BP-112 all needed a change; each was
authorised in-session and disclosed. The waiver scheme discussed
early in session-073 was DROPPED in favour of regress.sh: a package
edit is now checked by running the whole tree rather than by a
per-task permission. CLAUDE.md was not updated to match. Until it is,
every package task starts by breaking a written rule.

Intended wording, Jeff's to apply:

```
  A task may add, change or remove package declarations.
  Every task ends by running tools/regress.sh, and its summary goes
  in Results Capture.
  Any red result not in tools/known_failures.txt blocks Status:
  complete.
  The IA does not edit tools/known_failures.txt.
```

### 4. A DOCUMENT STATING A RULE IS NOT EVIDENCE THE RTL CAN MEET IT.

Three instances this session, all found by BUILDING against the
document, none by the session-072 audit that swept 47 files against
each other:

```
  FTB-G1     ftb_decisions.md 4.5 recorded the bounds check as
             restored in session-069. The FTB had NO fall-through
             check at all. TD#124, built by BP-110.
  TD#127     xlate_ptr specified session-069, after BP-107 finished
             the unit. Never built until BP-112.
  W3         ftq_ifu_interfaces.md 7 keyed the IFU flush index on
             the redirect CAUSE. ftq_npc drives RC_MISPREDICT with
             _self clear for p2, p3, predecode and the backend
             alike, so the distinction is not on the bus. The rule
             was unmeetable as written. BP-112 routed arm_win.
```

The method that finds this class is an IA reading the RTL against the
document, or building from it. Document-to-document review does not.

### 5. A PASSING SUITE IS NOT EVIDENCE EITHER.

Three instances, also this session:

```
  four testbenches exited 0 on a failed check (2)
  tb_bp_cluster's model of the ITTAGE reconstruction ZERO-extended
    while the RTL SIGN-extended. 1795 checks never noticed, because
    no test set bit 38. BP-109.
  five checks in tb_ftq and tb_ftq_ptr ENCODED the TD#139 defect as
    expected behaviour, including the two written to cover that
    path. They were corrected, each with its old value recorded.
    BP-113. One more, tb_ftq_ifu B6, for TD#141.
```

The working practice, and it should continue: pin the defect with a
check that FAILS on the unmodified tree before fixing it, and prove
each new assertion fires by mutation on a scratch copy outside the
repo. Every task from BP-109 on did this. BP-111 went further with
three-way injection, showing each check fails on the defect it
targets and on nothing else.

### 6. PA inferences written into documents, not ruled.

Session-072's item 4 again, in a new place. R3a in
ftq_entry_formats.md 4.3 was written by the PA and said section 7's
W1 and W2 apply to the W3 refetch's second writeback. Section 7
applies them only on a reported mispredict, and the rewrite and the
redirect are one event (ftq_ifu_assert I5), so the sentence would
have split them and changed an entry's successor with no flush.
BP-114 reported the conflict rather than implementing it. 4.3 is
corrected.

Anything in a planning document that the RTL has not met should be
read as a claim, not a rule, until someone has built against it.

---

## Session Summary

### Rulings by Jeff

```
  package changes          gated by regress.sh, not by a waiver.
                           CLAUDE.md not yet updated (item 3)
  IT_MAX_TGT_WIDTH 38->40  ITTAGE stores VA[40:1]; no extension rule
                           survives. 8,192 bits in the array, 512 in
                           the FTQ slow path. prop1.md NOT adopted
  every target is a        a conditional from the branch PC (O-1), a
  displacement from its    jump from the jump PC. TD#137
  own instruction
  ftb_decisions.md 4.6     O-1, O-2 (FTB-G3) and O-3 (a, b, c) all
                           as proposed. All of 4.6 is ruled
  uBTB divergence          explicit: mask only, no compaction, no
                           reorder, region-base targets, NOT bounds
                           checked, br_idx names a storage field
  ftb_upd_br_idx_u0        a PORT SLOT as the update's start saw it
  one prediction block     per cycle. Two blocks is a measurement,
                           deferred as TD#133
  the nine ITLB/MMU widths GPA 41, GVPN 29, VPN 27, PPN 24, ASID 16,
                           VMID 14, PERM 8, CAUSE 5, PMA 4
  TD#138                   the DOCUMENT changes, not the RTL. No
                           request accompanies a flush
  TD#140                   W3 has priority; the refetch writeback is
                           expected and derives no redirect
  IFU scope                wrong-path, uncached and fence.i are NOT
                           in the first IFU task: TD#134, TD#135,
                           TD#136, each its own session
  ftq_entry_formats 3.1    the metadata union stays DEFERRED
  git                      THE IA GETS NO PERMISSION FOR GIT
                           COMMANDS THAT MODIFY GIT STATE. A
                           launcher setting, not a rule to remember
```

### Settled from evidence in the tree

- PMA_WIDTH is 4, one bit per MMU-13 attribute, not 2. The PBMT of
  IL-9a is a separate two-bit field. The PA proposed 2 and the
  documents corrected it.
- The x2 in the ITTAGE storage arithmetic is the two per-slot RAM
  copies, not IT_TBL_BANKS, which divide a copy. Right number, wrong
  reason; corrected in two documents.
- TD#137 had one observable effect after all, and it is WHERE THE
  REACH WINDOW SITS, not the round trip. BP-111 pinned it and
  reported that its other case could not be made to fail.
- The post-redirect translation stall is 1 cycle for a front-end
  redirect and 2 for a backend one, because F is the target entry
  itself. ftq_decisions.md 5.1 and ifu_decisions.md IFU-27 both said
  one for both and now separate them.
- ftq_backend_interfaces.md 7 R1 ranks redirect, commit and resolve
  AND NOTHING ELSE. It does not rank a redirect against an
  allocation, and it had been read that way twice, once in the RTL
  that produced TD#139 and once in a testbench check that cited it.

### Closed this session

```
  TOOLS-006   TD#99
  BP-109      TD#122
  BP-110      TD#124, TD#125
  BP-111      TD#132, TD#137
  BP-112      TD#126, TD#127
  BP-113      TD#139
  BP-114      TD#140, TD#141, TD#142
  by ruling   TD#138
```

TD#139 was the one that mattered: in a redirect cycle the p0 request
carried the pre-rewind alloc index, so the redirect target block was
written to a squashed entry and never fetched and the first 32 bytes
of the corrected stream were skipped, on every cause. Found by
BP-112, fixed by BP-113.

---

## Next session (074)

### Task 1: the two small things first

```
  1  CLAUDE.md Packages line            Jeff, Read This First 3
  2  the stale RTL comments below       fold into task 2
```

### Task 2: cachegen, or the decision not to

TD#119 is the cachegen schema gap that leaves the emitted L1I with no
invalidate port. It gates TD#136. TOOLS-007 is the next free number.

Before writing it, settle a question raised and not answered this
session: tools/cachegen/output/ IS OUTSIDE EVERY MAKEFILE regress.sh
finds. Nothing checks that the generator still emits something that
builds. Adding features to the one part of the tree with no automatic
check, immediately after building the check for everything else, is
the wrong order. A Makefile with lint and a smoke sim for the emitted
L1I would land it inside regress.sh automatically.

Jeff also floated, and did not decide, writing the L1I pacino needs
as ordinary RTL and pointing cachegen at it afterwards. That decision
belongs before TOOLS-007, not after.

### Task 3: the IFU

Blocked on rulings, not on code:

```
  TD#134   wrong-path requests after a redirect. Lifting this lifts
           the session-069 flush-and-redirect deferral. Needs an
           epoch or generation scheme on in-flight L1I requests and
           a rule for the line buffer; the L1I has NO CANCEL PORT
  TD#135   the uncached path. WHERE IT GOES IS NOT ESTABLISHED:
           a non-allocating mode in the L1I, or a second IFU port.
           Confirm against ifu_decisions.md IFU-21 first
  TD#136   fence.i and cbo.inval. Blocked at the far end by TD#119
```

An IFU built without TD#134 is UNIT-TESTABLE ONLY. It cannot be
integrated against the FTQ redirect path until that closes. The first
IFU task must say what it stubs rather than leaving the stubs
implicit.

Two obligations the FTQ has already placed on the IFU:

```
  ftq_ifu_interfaces.md 5   the IFU MUST IGNORE any request presented
                            while the flush is asserted, on both the
                            section 4 and 4.1 groups. Accepting one
                            fetches an entry twice under one
                            generation tag, or fetches a squashed
                            entry
  IFU-22                    ftq_ifu_commit_ptr is driven every cycle
                            and is read for uncached fetch only
```

Before the IFU prompt: read ifu_decisions.md, l1i_ifu_interfaces.md
and ftq_ifu_interfaces.md COMPLETE, and diff ftq_ifu_interfaces.md's
port names against ftq_ifu.sv's port list. The FTQ side is built and
is the reference.

### Comment-only RTL, fold into whichever task next opens the file

```
  ftq_ifu.sv, above the flush always_comb
                         still says the accompanying request is the
                         first fetch of the corrected stream. TD#138
                         overturned that
  ftq_ptr.sv 403-405     still says the flush-cycle handshake rule is
                         "not ruled; see TD#138". It is ruled
  ftq_meta.sv, tb_ftq_meta.sv
                         "421 bits per slot"; it is 425 after BP-111
  tb_ittage_cntrl.sv     helpers chk38 and chk57 are named for widths
                         that are now 40 and 59
  sc.sv 30-32, 148       cite TD#73/#94; TD#123 now
  tb_ftq_resolve.sv 174, 525
                         literal 32 stride, not the parameter
```

### Residue, carried

THESE HAVE CARRIED UNCHANGED FOR THREE SESSIONS. Either schedule them
or drop them; a list nobody acts on is noise.

- NEVER SUPPLIED AND NOT SWEPT against session-071 or 072:
  tage_coverage_plan, tage_tb_decisions, tage_mtb_decisions,
  sc_tb_decisions, manual_tb_decisions, and CLAUDE.md. They are in
  check_planning.sh with their session-071 checksums.
- ftb_confidence_override_rules.md was touched but NOT swept against
  the session-071 position and fast-path rulings.
- bpu_port_inventory.md sections 3 to 8 unverified against the RTL;
  finding 4 unchecked.
- CLAUDE.md names the deleted bp_pkg in two rationales.
- PROJECT_CORE.md defines three task prefixes while TOOLS-NNN is in
  use. Its "Document status" calls DRAFT permanent.
- E4 from session-070 was never answered.
- docs/superscalar_ooo_survey.md, cited by icache_decisions.md, is
  NOT IN THE TREE. L1I-1, L1I-7 and L1I-12 rest on evidence recorded
  only there. D33.
- PROJECT_STATUS "Shared components track" names a directory that
  does not exist.
- ftq_bpu_interfaces.md 4: what happens when lp_pred_is_loop is set
  and the uBTB misses is stated nowhere.
- ifu_notes.md lives at misc/, which is not in PROJECT_CORE's
  repository layout and not in check_planning.sh.
- A PTE PPN above the implemented 24 bits is unchecked, MMU-U9,
  raised session-073 and NOT ruled. The cause and the stage are
  open and the specification has not been read on it.

### Open, not blocking

TD#113, TD#114, TD#116, TD#118, TD#120, L1I-U5, L1I-U7, MMU-U1, the
p3 RAS repair against 4c, Open 17, Open 18. New this session: TD#128,
TD#130 (regress.sh reporting gaps), TD#131 and the ftq_ptr timing
jump (a suite 3x or 10x faster or slower with identical check counts,
twice, unexplained), TD#133.

### Deferred by Jeff, do not re-raise

Flush and redirect across the IFU pipeline remain deferred from
session-069, now carried as TD#134 with its own session.
ftq_entry_formats.md 3.1, the metadata union, stays deferred.

### Numbers

```
  next free BP     BP-115
  next free INFRA  INFRA-013
  next free TOOLS  TOOLS-007
  next free TD     TD#143
```

---

## Postmortem Record -- PA performance (session-073)

Continuing the trend log (058 over-asking; 059 fabricated
constraint + manifest by inference; 060 manifest-by-inference +
verbosity; 061 template-field misreads; 062 fabricated technical
claims + withheld conclusions; 063 three tasks abandoned for
incomplete specification; 064 constraints that blocked real fixes,
invented decision points, micro-stepping, a fabricated diagnosis;
065 unauthorised deletion ordered, discussion block pre-filled,
false claim carried into a prompt; 066 authorised IA modification
of planning documents, four false premises in problem statements;
067 manufactured blockers, underscoped tasks, a broken build called
cleanup, a session number invented and propagated; 068 an incomplete
acceptance list, paths inferred twice, an assumption defended; 069 a
nine-item review of which one survived; 070 fixing the named site
and not the file, nine conflicts from one edit; 071 sweeping only
the files in hand and calling it complete; 072 the PA's own residue
became the audit's main source, claims written from memory with the
source in hand).

1. A PROMPT WRITTEN WITHOUT READING THE UNIT'S DOCUMENTS. BP-112's
   Problems 2, 3 and 4 instructed the IA to implement
   ftq_ifu_interfaces.md 4.1, ftq_decisions.md 5.1 and 7 W3. The PA
   had read none of them. It had two TD rows it had written itself.
   Three of the four in-session interruptions follow directly, as
   does the ftq_entry.sv manifest miss. For BP-110 the PA read
   ftb_decisions.md end to end first and the prompt named sites,
   rules and arithmetic; the difference in the two tasks is entirely
   this. Jeff has never refused a file.

2. A RULE WRITTEN INTO A DOCUMENT THAT WAS WRONG. R3a, above. The
   IA caught it by building against it. This is the second time in
   two turns on the same item; the first was raising TD#140 as an
   open question, twice, when the surrounding rules already
   determined the answer. SILENCE IN A DOCUMENT IS NOT ALWAYS A
   QUESTION.

3. A CITATION CARRIED WITHOUT CHECKING WHAT IT WAS. "C9" went into
   BP-110's prompt against ubtb_pred_t.carry. It is a session-071
   audit batch finding number, not a registry tag. The IA searched
   planning/ for it and found nothing.

4. AN EDIT THAT SILENTLY DELETED A ROW. Replacing the TD#132 block
   in PROJECT_STATUS by anchor removed the TD#137 row that had been
   inserted inside the same span. Caught two turns later while
   closing it, by chance. Block replacement by anchor needs the
   range checked for what else lives in it.

5. A CLAIM ABOUT THE PROJECT'S HISTORY MADE FROM FOUR TASKS. Asked
   why one session had more back and forth, the PA answered that
   BP-112 was "the first task built against documents rather than
   RTL". It is the 112th task; most were document-first. The PA had
   seen four. Stated as fact, with no basis, and corrected only
   when Jeff pushed back.

6. TASK HEADERS DELIVERED WITH YYYY.MM.DD UNFILLED, twice, before
   the PA started dating them.

7. ARITHMETIC RIGHT FOR THE WRONG REASON. The ITTAGE storage cost
   was given as "2048 entries x 2 banks". The x2 is the two
   per-slot RAM copies; IT_TBL_BANKS divides a copy. The number was
   correct, so nothing downstream broke, and the wrong reason went
   into two documents before BP-111 corrected it.

8. MOTIVATION DELIVERED WHERE INSTRUCTIONS WERE ASKED FOR. Asked
   what direction to send the IA, the PA wrote three paragraphs of
   reasoning that could not be pasted. Jeff asked twice.

THE PATTERN is 072's, moved from documents into prompts: the PA
acted on what it held and reported as though it had the whole. What
worked, and should continue: reading the unit's documents before
drafting, which is the entire difference between BP-110 and BP-112;
pinning a defect with a check that fails BEFORE the fix, which every
task from BP-109 on did and which caught five tests that had encoded
a defect; asking for files rather than inferring paths; and running
check_planning.sh against a scratch tree built from the delivered
files, which caught the padding collision in item 1 that reading the
script would not have.
