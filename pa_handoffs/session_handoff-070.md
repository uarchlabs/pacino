<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 070
Written by Claude.ai at end of session-069.
Date: 2026-09-15

Read PROJECT_STATUS.md, then this file, then CLAUDE.md.

No tasks were run. The session was planning. Eight documents were
created, four were amended, and the I-side front end is specified
end to end for the first time.

Next session: a citation audit, then RTL generation for the IFU
and the modules around it. See Next Session.

---

## Read This First

### 1. Nothing built, everything specified

Six modules now have decision documents and none has RTL: the
IFU, the predecoder, the instruction buffer, the ITLB, the shared
L2 TLB with its walker, and the front end top. Three interface
documents give their ports.

Every port named in the three new interface documents connects to
something that does not exist yet.

### 2. The ITLB and the MMU are written, not emitted

The L1I is emitted by cachegen. Nothing else on the I side is.
The ITLB, the L2 TLB and the walker are ordinary modules written
from their decision documents, as the bpu and the ftq were.
cachegen has no TLB support and is not on their path.

One cachegen dependency remains and it belongs to the l2, not to
the MMU. MMU-2 puts a TileLink master port from the L2 TLB into
the l2, and the l2 is emitted, so it may need a schema or emitter
change to accept a third master and to carry an atomic on it.
MMU-U3.

### 3. The predecoder is new, not an extension

`predecode.sv` and the existing `predecode_pkt_t` are superseded.
`dcd_decisions.md` specifies one predecoder producing two views of
one classification: `ftq_pd_info_t` at 16 block positions for the
FTQ writeback, and `predecode_pkt_t` at 8 slots for decode.

The old struct carries a conservative `may_be_branch` hint and no
PC, FTQ index, fault cause or faulting VA. DCD-16 redefines it
with all of them. That is a package edit, so it widens the
verification run to both units.

The RVC expander is not in `dcd_decisions.md`. Its encodings are
the compressed chapter of the specification and the project's
decisions about it are placement and ordering, IFU-1 and IFU-4.

### 4. H IS MANDATORY. Two-stage translation is in.

Pacino implements the RVA23S64 mandatory set and no optional
extension. H is NOT an optional extension: RVA23 makes Sha
mandatory and H is part of Sha. Recorded in the PROJECT_STATUS
decoder track.

The PA got this backwards mid-session, told Jeff H was optional,
and removed guest page fault from the fault classes in
`ftq_ifu_interfaces.md` and `l1i_ifu_interfaces.md`. Both edits
were reverted and the consequence worked through properly.

What two-stage translation costs, all now in the documents. The
walk is NESTED, MMU-21: every address the VS-stage produces is a
guest physical address needing its own G-stage walk, so a
three-level VS-stage walk costs up to four G-stage walks. ITLB
entries carry a VMID and a V bit, ITLB-4a. `henvcfg.ADUE` governs
the VS-stage while `menvcfg.ADUE` governs the G-stage, MMU-7a, so
one nested walk can have two stages under different A/D rules.
There is a third fault cause, instruction guest-page fault at
cause 20, MMU-16. Shtvala means the faulting GUEST PHYSICAL
address travels back from the walk and out to the backend, IT-6a,
IL-11a: it is the one address the IFU did not supply and therefore
the one that returns on the translation port. HFENCE.VVMA and
HFENCE.GVMA join SFENCE.VMA, MMU-17a.

### 5. Sixteen fills are still real at the l1i and not at the l2

TD#118 is unchanged and now bounds three more items: ITLB-U1,
MMU-U2 and IBUF-11. Outstanding walk counts and buffer depth all
depend on a miss latency that is the l2's number, not the l1i's.

### 6. Maintenance, TD#119, does not reach the new modules

The schema gap stops the emitted L1I carrying an invalidate port.
The ITLB and the L2 TLB are written, so ITLB-14 and MMU-18 give
each a distinct invalidate port written with the module. TD#119 is
unchanged and applies to the L1I only.

---

## Session Summary

### Documents created

```
  planning/arch/itlb_decisions.md       ITLB-1..14, ITLB-U1
  planning/arch/mmu_decisions.md        MMU-1..18, MMU-U1..U5
  planning/arch/ifu_decisions.md        IFU-1..27, TD-IFU-1..10,
                                        IFU-U4, IFU-U5
  planning/arch/ibuf_decisions.md       IBUF-1..11, TD-IBUF-1,
                                        IBUF-U1
  planning/arch/dcd_decisions.md        DCD-1..16, TD-DCD-1..2,
                                        DCD-U1..U2
  planning/interfaces/
    ifu_ibuf_interfaces.md              IB-1..11, IB-U1
    itlb_ifu_interfaces.md              IT-1..15, no open item
    itlb_l2tlb_interfaces.md            IL-1..14, no open item
```

### Documents amended

```
  fe_decisions.md          section 15, the front end top,
                           FE-15..18 and FE-U10. Document History
                           renumbered 15 to 16; nothing referenced
                           15. Overview rewritten: the prose is
                           BPU and FTQ plus the top, the
                           registries are front end wide, and the
                           rest of the front end is listed by
                           document
  ftq_ifu_interfaces.md    ftq_ifu_commit_ptr added to section 4,
                           IFU-22. Guest page fault dropped from
                           the section 6 fault classes
  l1i_ifu_interfaces.md    Guest page fault dropped from section
                           8. IF-24's citation of L1I-U3 now
                           points at ITLB-8 and ITLB-9
  PROJECT_STATUS.md        Decoder track corrected, eight
                           documents added to Shared planning,
                           eleven Module Status rows added, the
                           duplicate `fetch` row removed
  bp_history_decisions.md  3.4 restore is no longer mispredict-
                           only. Corrected at three sites: 3.4,
                           the HI5 note, and the history entry
  ftq_backend_interfaces.md  D1 unchanged and correct; a note
                           records that bp_history was the side
                           that moved
  ftb_decisions.md         4.5 fall-through guard RESTORED,
                           FTB-G1 and FTB-G2. 4.1 tag claim
                           qualified. BP-099 staleness corrected
                           at 4.2, 4.4, 5.5, section 8, FTB-1
  ubtb_interfaces.md       pft_addr bounds checked to match
                           FTB-G1. The two meanings of `carry`
                           separated, G18/UI2
  ftq_decisions.md         5.1 is FOUR pointers: xlate_ptr added
                           between alloc_ptr and fetch_ptr. FQ-1
                           extended. 4.7 alignment clarified as
                           reset-vector only
  icache_decisions.md      4.3 gains R4: the physical address is
                           produced ahead of the request, in a
                           pipeline the L1I does not see
```

`fe_decisions.md` was considered for replacement and kept.
`ftq_ifu.sv` cites it eight times, FE-3, FE-6, FE-8, FE-10 twice,
TD-FE-4, and `fe_decisions.md 2.4` twice by section number, and
`ftq_bpu_interfaces.md` references sections 7.2 and 2.4. Section
4, 5, 6 MOVED is the precedent: content leaves, numbers are
retired rather than reused, outside references still resolve.

---

## Decisions (session-069)

```
   1  ITLB 64 entries, fully associative, all three Sv39 page
      sizes in one array, ASID tagged, 1-cycle hit. Zen is the
      shape; Neoverse N1 and V2 and XiangShan are at 48; the only
      128-entry L1 ITLB in the survey, Broadwell, is 4-way with a
      separate large-page array
   2  L1I-U3 adopted as recommended. Shared L2 TLB with the
      walker inside it, master port into l2, non-blocking ITLB
      returning miss to the requester
   3  PMP at two sites, the translated PA and every walker
      address. PMA on the final PA only. PMA decides whether an
      access may be speculated, PMP whether it may complete
   4  Both Svade and Svadu. menvcfg.ADUE selects at runtime. The
      walker writes, the update is atomic, and the master port
      cannot be Get-only
   5  Compressed expansion in the IFU, before the ibuf, so the
      ibuf holds uniform 32-bit slots and the IFU owns the
      straddle
   6  Predecode in the IFU. Decode has no planning document
      because it is close to a translation of the specification
      and predecode is not in the specification
   7  Expansion before predecode, the reverse of XiangShan.
      Expansion is position-independent so the start mask and the
      expanders run in parallel, and predecode then sees base-ISA
      encodings only. BOOM orders it this way
   8  The prediction block is unaligned. Two lines fetched when
      the block starts in the upper half of a line, 34 bytes
      covered, 17 halfword positions, 16 slots
   9  Wide port to the ibuf. 16 slots with one enable mask, no
      compaction in the IFU
  10  Whole-block acceptance at the ibuf. Ready only when 16
      entries are free
  11  Bypass when the ibuf is empty
  12  ibuf depth 64, a parameter. Floor is 32 from decision 10;
      XiangShan is 48 at decode width 6, and 8 times our decode
      width of 8 is 64
  13  Five IFU FETCH stages, F0 F1 F2 F3 WB, the XiangShan
      segmentation with pacino contents
  14  Expansion stays in F3 with predecode, the prediction check
      and the mask. F2 keeps the data return, fault information
      and position select
  15  Uncached fetch has its own instruction source, not through
      the L1I, and the FTQ drives its commit pointer to the IFU
      so the transaction issues only on the committed path
  16  One ITLB request port with a one-bit tag, not two ports.
      Responses may return out of order
  17  Two-bit tag on the ITLB to L2 TLB port, decoupled from the
      tracker depth
  18  The front end top is its own subject, section 15 of
      fe_decisions.md, taking FE numbers. The L1I is INSIDE it,
      a sibling of the IFU and not inside the IFU, per L1I-2:
      what matters is that the cache is self contained, which is
      what physical design needs. The ITLB is inside on the same
      reasoning; the shared L2 TLB is outside
  19  Pacino implements no optional RVA23S64 extensions at this
      time. Recorded in the PROJECT_STATUS decoder track. H is
      NOT optional: RVA23 mandates Sha and H is part of Sha, so
      two-stage translation is in. MMU-19..23, ITLB-4a
  20  The FTB and uBTB fall-through reconstruction is BOUNDS
      CHECKED, restoring the guard an earlier revision removed.
      The full tag stops partial-tag aliasing but the low five
      bits are in neither index nor tag, and blocks are
      unaligned, so two lookup PCs in one 32-byte region share
      an entry. Fallback is start + FTB_BLOCK_BYTES, never
      XiangShan's FetchWidth*4
  21a History restore applies to EVERY redirect that names an
      entry: RC_MISPREDICT, RC_TRAP and RC_REPLAY, per
      ftq_backend_interfaces.md D1. bp_history_decisions.md 3.4
      had it mispredict-only with traps reinitializing; corrected.
      Its own granularity rule settles it, one checkpoint per
      accepted bundle rather than per branch, so the index
      resolves for a bundle with no branch in it
  21  The IFU has TWO decoupled pipelines: translation ahead of
      fetch, joined by a queue, driven by a new FTQ xlate_ptr.
      L1I-3 makes the L1I physically indexed, so a fetch cannot
      be issued in the cycle its translation begins. This is
      the XiangShan arrangement WITHOUT the way lookup: the
      MetaArray stays out of the prefetch path because the L1I
      is emitted and a second pipeline inside it is a cachegen
      change
```

Four values were read from source and are not decisions: SLOTS is
8, `FTB_BLOCK_BYTES` 32 so `FTQ_PD_WIDTH` is 16 and
`FTQ_PD_POS_BITS` 4, and XiangShan's IBuffer is 48 entries in 6
banks of 8 with DecodeWidth 6, banked for read-mux area only.

---

## Next session (070)

### Task 1: the citation audit

READ-ONLY. No file is modified by this task; it produces a report.

Every document created this session ends with a Bindings section.
Each line in one names a rule in another document and asserts
something about it. Verify every one.

```
  itlb_decisions.md        section 9
  mmu_decisions.md         section 10
  ifu_decisions.md         section 9
  ibuf_decisions.md        section 8
  dcd_decisions.md         section 12
  ifu_ibuf_interfaces.md   section 8
  itlb_ifu_interfaces.md   section 9
  itlb_l2tlb_interfaces.md section 8
```

For each citation, report one of: the cited rule exists and says
what the citing document claims; the rule exists but says
something different, with both texts quoted; the rule does not
exist.

WHY THIS TASK EXISTS. The PA wrote TD-ITLB-1 into
`itlb_decisions.md` asserting that `l1i_ifu_interfaces.md` IF-8
collapsed two fault causes into one bit and needed amending. IF-8
is a gate condition and IF-23 and IF-24 behind it already separate
fault from miss. The claim was wrong, it survived the whole
session, it reached the previous draft of this handoff as pending
work, and it was caught only when Jeff uploaded the file. The PA
had written a claim about a document it had never read.

That is the failure this task is scoped to catch. The PA
reconciled the eight new documents against each other at the end
of the session and found three real conflicts. It did not and
could not verify their claims about documents it has not read:
`icache_decisions.md`, `ftq_decisions.md`, `ftq_entry_formats.md`,
`ftq_bpu_interfaces.md`, `bp_cluster.md`, `ras_decisions.md`,
`predecode.sv`.

SCOPE IT NARROWLY. This is not "find inconsistencies in the
planning documents". That form was attempted by the PA at the
start of this session: nine findings reported, eight withdrawn
under questioning, one survived. The failure mode is reporting a
mismatch between two statements without tracing whether anything
depends on it. A citation either checks out or it does not, which
is why the task is written this way.

DO NOT report: documents that do not cross-reference each other,
stale status fields, formatting, or anything not reachable from a
Bindings line.

### Task 2 onward: RTL generation

FOUR THINGS DO BLOCK THE IFU, found after this section was first
written. TD#116 is narrowed, not closed: `ifu_decisions.md` covers
none of the L1I-14 line buffer and L1I-U5, the issue policy against
`mshr_targets`, the TD-IF-5 reorder buffer, or the maintenance
path. They are TD-IFU-7 through TD-IFU-10 in that document. The
first three are structure rather than sizing, so an IA generating
the IFU will invent a line buffer depth, an issue policy and a
reorder buffer, and none of the three will appear in any document.

Resolve those before the IFU. The ITLB, the L2 TLB, the predecoder
and the ibuf are unaffected and can be generated now.

Nothing else blocks generation. Every module has a decision document
and every port has an interface document.

```
  predecoder    dcd_decisions.md
  IFU           ifu_decisions.md
  ibuf          ibuf_decisions.md
  ITLB          itlb_decisions.md
  L2 TLB        mmu_decisions.md
  front end top fe_decisions.md 15
```

Two edits to built files come first:

```
  decode_pkg.sv   redefine predecode_pkt_t per DCD-16. A package
                  edit, so the run widens to both units
  ftq_ifu.sv      add the ftq_ifu_commit_ptr output of IFU-22.
                  The interface document already carries it.
                  Complete and verified at 67 checks today
```

### The open items will be answered silently if left

Twelve are unresolved and none stops a module being written. What
they do is leave a choice the IA will make on its own, and the
number then exists in RTL and in no document.

```
  MMU-U1   L2 TLB geometry
  MMU-U2   outstanding walk count, bounded by TD#118
  MMU-U3   atomic form, and the l2 third-master change
  MMU-U4   whether RVA23S64 mandates Smepmp. A specification
           lookup, taskable
  MMU-U5   whether Svpbmt is a second PMA source. Same
  ITLB-U1  in-flight walk tracker depth, bounded by TD#118
  IBUF-U1  whether the ibuf is banked. XiangShan banks for read
           mux area and requires banks >= decode width
  IFU-U4   uncached bus width, and whether it forces a split
  IFU-U5   translation queue depth. Sets how far translation runs
           ahead of fetch and how much ITLB miss latency hides
  DCD-U1   where vtype_hazard is computed. Not the predecoder
  DCD-U2   the order of pop and push in the RAS case

  IB-U1    which source clears the ibuf, with the deferred flush
```

TD-DCD-2 is a read of the built RAS: does it accept `is_call` and
`is_ret` both set on one instruction. Taskable.

### Deferred by Jeff, do not re-raise

Flush and redirect across the IFU pipeline are deferred until the
full data path exists. IFU-20 records the obligation from
`ftq_ifu.sv`; the design waits. This was raised three times in
session-069 after being deferred.

### Two conflicts raised by another session, both resolved

Both were the PA's to answer for and both are now fixed.

ALIGNMENT. That session reported IFU-6 and DCD-5 saying blocks may
start at any 2-byte address while the FTB, the uBTB and FTQ 4.7
assumed 32-byte alignment. Unaligned is correct and stands; it is
the XiangShan mechanism and the reason for the 34-byte, 17-position
block. What the PA then found is that unaligned blocks make the
FTB's removed fall-through guard unsafe: FTB_OFFSET_BITS of 5 are
in neither index nor tag, so two lookup PCs in one 32-byte region
share an entry. XiangShan carries fallThroughErr for the same
failure by a different route, partial-tag aliasing. The guard is
RESTORED as FTB-G1 and FTB-G2, fallback start + FTB_BLOCK_BYTES.
`ubtb_interfaces.md` takes the same check. FTQ 4.7 now says the
alignment requirement is on the RESET VECTOR only.

The BP-099 staleness in `ftb_decisions.md` is corrected at every
site: FTB_BR_POS_BITS 4 not 3, PFTADDR_BITS 5 not 4, ENTRY_WIDTH
110 not 106, POS_OFFSET_BITS 1 not 2, and 4.4 no longer claims
expanded-granularity addressing.

The `carry` collision, G18/UI2, is resolved in the
`ubtb_interfaces.md` field semantics: the per-slot carry means this
slot's target is outside the block, the block carry means the
fall-through crosses the boundary.

FETCH PIPELINE ORDER. That session reported IFU-10 issuing the L1I
request in the same stage it started the ITLB lookup, against
L1I-3, IF-8, IT-11 and MMU-14. Correct, and the PA's error. Fixed
by decision 21. A second defect surfaced with it: ITLB-12 lumped
the PMA idempotent attribute in with the PMP check, so one rule
both gated a response and decided whether a request was made. Split
into ITLB-12 and ITLB-12a.

### Open, not blocking

```
  TD#113  the pft_addr fix. Specified, not built. Carried from
          session-067 untouched
  TD#114  the property census. Carried untouched
  TD#115  CLOSED by itlb_decisions.md
  TD#116  STILL OPEN, narrowed. ifu_decisions.md exists but
          covers none of its four items: the L1I-14 line buffer
          and L1I-U5, the issue policy against mshr_targets, the
          TD-IF-5 reorder buffer, and the maintenance path.
          Carried in that document as TD-IFU-7..10. An earlier
          draft of this handoff called it closed
  TD#117  CLOSED by fe_decisions.md 15
  TD#118  sixteen fills at the l2. Now bounds ITLB-U1, MMU-U2 and
          IBUF-11
  TD#119  maintenance, the RVA23 gap. L1I only; the written
          modules carry their own invalidate ports
  TD#120  two replacement-quality consequences of the pipelined
          bank
  L1I-U7  whether the L1I-22 reserve is on the link or the node
  E5      closed for l1i only; reword rather than close
  Open 17 the planning-document convention change. Tabled
  Open 18 the bpu 47 and ftq 22 have not been run since the
          session-067 package additions
```

### Numbers

```
  next free BP     BP-109
  next free INFRA  INFRA-013
  next free TOOLS  TOOLS-006
```

---

## Postmortem Record -- PA performance (session-069)

Continuing the trend log (058 over-asking; 059 fabricated
constraint + manifest by inference; 060 manifest-by-inference +
verbosity; 061 template-field misreads; 062 fabricated technical
claims + withheld conclusions; 063 three tasks abandoned for
incomplete specification; 064 constraints that blocked real fixes,
invented decision points, micro-stepping, a fabricated diagnosis;
065 unauthorised deletion ordered, discussion block pre-filled,
false claim carried into a prompt; 066 authorised IA modification
of planning documents, four false premises in problem statements;
067 manufactured blockers, underscoped tasks, a broken build
called cleanup, a session number invented and propagated; 068 an
incomplete acceptance list, paths inferred twice, an assumption
defended, a circular open item shipped).

Every error below was caught by Jeff.

1. A NINE-ITEM REVIEW OF WHICH ONE ITEM SURVIVED. The session
   opened with a review of the corpus. Nine findings were
   reported. Eight were withdrawn under questioning and the ninth
   was a stale table row, the duplicate `fetch` entry, fixed this
   session. The mechanism was the same in every case: a rule in
   one document did not match something in another, and the
   mismatch was reported as a consequence without tracing whether
   anything depended on it.

2. A CLAIM WRITTEN ABOUT A DOCUMENT NEVER READ. TD-ITLB-1
   asserted that `l1i_ifu_interfaces.md` IF-8 collapsed two fault
   causes and needed amending. IF-8 is a gate condition and
   IF-23 and IF-24 behind it already separate fault from miss.
   The claim was written from the handoff's one-line summary of
   IF-8, survived the session, and reached the first draft of
   this handoff as pending work. Task 1 exists because of it.

3. FOUR OBJECTIONS TO L1I-U3, ALL WITHDRAWN. Asked for issues
   with adopting a recommendation, the PA produced a list of
   topics the resulting specification would have to cover and
   presented it as risk. Two were missing documents restated as
   complexity, one was a sequencing preference, and the fourth
   dissolved because the fix was already scheduled for another
   reason.

4. THE EMITTED CASE TREATED AS THE DEFAULT. The PA stated that
   RTL for the I-side translation path could not be produced
   until cachegen was extended. Every module in the project
   except the L1I is written by hand from a decision document.
   One session of cachegen work displaced that. Two documents had
   already been written in the wrong frame and had to be
   corrected.

5. A QUESTION COUNT WRONG BY TWO WITH THE ANSWER ALREADY READ.
   Asked what questions remained, the PA said one. Three
   recommendations sat unruled in `icache_decisions.md` 10.1,
   quoted back to Jeff twice in the same session.

6. DEFERRED WORK RAISED THREE TIMES. Flush was deferred
   explicitly. It appeared in the next summary, was deferred
   again, and appeared again under a different heading.

7. VAGUE PHRASING DEFENDED RATHER THAN FIXED. "Not on its path",
   "real form as opposed to imaginary", "corrected range",
   "survives", "recorded on purpose". Each required a question.
   In at least two cases the first reply explained the phrase
   instead of replacing it. Sentence fragments were used
   throughout and were called out.

8. A SYNTHESIS RUN OFFERED IN PLACE OF JUDGEMENT. IFU-U3 was
   written as wanting a synthesis run to settle the F2/F3
   boundary. There is no synthesis flow. The judgement answer
   existed and was given only after Jeff rejected the deferral.

9. AN ALREADY-MADE DECISION REOPENED. The choice of what to
   expand was raised as a question with the alignment answer as
   its precondition. Session-068 decision 4 had already fixed it:
   the IFU extracts the 32-byte block and expands that.

10. TWO PREDECODERS INVENTED FROM A WIDTH DIFFERENCE.
    `ftq_pd_info_t` at 16 positions and `predecode_pkt_t` at 8
    slots were read as two modules. They are one classification
    at two points. TD-IFU-5 was written in that frame and had to
    be rewritten.

11. WORK ITEMS PRESENTED AS OPEN QUESTIONS. TD-IFU-4 was listed
    as remaining when IFU-22 had already ruled it. A verification
    instruction was written into a decision document as though it
    were a decision. Both reduce to "do not build it wrong".

12. THE DATE WAS WRONG IN NINE FILE HEADERS. Every document
    written this session was stamped 2026-09-01. The date was
    2026-09-15 and was available throughout. The error was
    reported to Jeff as a discrepancy between two files rather
    than recognised as the PA's own, and it is not the first
    session in which the date has been wrong.

13. H WAS STATED AS OPTIONAL WHEN IT IS MANDATORY. Mid-session the
    PA said RVA23S64 lists H among its options. RVA23 mandates Sha
    and H is part of Sha. On that basis guest page fault was
    removed from the fault classes of `ftq_ifu_interfaces.md` and
    `l1i_ifu_interfaces.md`, both of which were correct before the
    edit. Reverted, and the two-stage consequence written through
    ten documents.

    THIS ONE IS AN ADVISORY FOR THE ARCHITECT RATHER THAN A
    PROCESS FAILURE. H was genuinely optional before RVA23 and was
    reorganised into Sha for it, so the record shifted more than
    once inside the span of the training data and the older state
    is well represented in it. Profile membership is therefore a
    class where the PA's recall is unreliable in a way that does
    not feel unreliable, and a confident answer should be treated
    as a prompt to check the ratified profile text rather than as
    a result. The PA did say the first answer was unconfirmed and
    then let it harden; the durable fix is that profile questions
    get looked up every time, not that this instance was careless.

What held:

  - Every citation used in the two documents written before the
    corpus was dropped from context was re-checked against the
    file at write time rather than recalled. L1I-3, L1I-14,
    L1I-21, L1I-22, IF-8, L1iReadLatency, up_i and up_d, and the
    l2 single-transaction limit were all confirmed by grep
    immediately before use.
  - Three claims about ITLB sizing were checked rather than
    agreed. Zen at 64 fully associative was confirmed, Broadwell
    at 128 was corrected from fully associative to 4-way with a
    separate large-page array, and the Neoverse claim of 64 was
    corrected to 48 for the two parts that could be verified,
    with N2 and V1 left unstated rather than guessed.
  - `fe_decisions.md` was checked for live references before
    being proposed for replacement. Eight citations from built
    RTL were found and the proposal was withdrawn.
  - The eight new documents were reconciled against each other at
    the end of the session. Three real conflicts were found:
    IFU-5's two masks against IB-2's one, ITLB-11's returned VA
    against IT-5, and two tech debt items left open after
    `dcd_decisions.md` closed them.
  - The guest page fault question was raised rather than assumed
    away. It was the difference between `mmu_decisions.md` being
    correct and being materially incomplete.
  - Every document written this session is 80-column clean and
    ASCII-only, checked by script rather than asserted.

Not the PA's, and worth recording: the ordering of expansion
before predecode, decision 7, came from Jeff. The PA had recorded
the XiangShan order and the reason for reversing it, that
predecode on expanded encodings needs only the base-ISA branch
forms, was Jeff's observation.
