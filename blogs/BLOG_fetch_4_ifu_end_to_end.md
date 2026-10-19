<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

```
TITLE:     "Building the Fetch Unit and Running the Front End End to End"
FILE:      BLOG_fetch_4_ifu_end_to_end.md
AUTHOR:    Jeff Nye
DATE:      2026-10-19
STATUS:    REVIEW BEFORE POSTING
COPYRIGHT: "Copyright 2026 Jeff Nye"
```

<!--
---

::SERIES DESCRIPTION::
::BEGIN LINKS::
::END LINKS::
-->

# Building the Fetch Unit and Running the Front End End to End

## Abstract

At the start of this range the Pacino RVA23 front end had a verified branch
prediction cluster and fetch target queue (FTQ), a generated instruction
cache, and a specified but unbuilt instruction fetch unit (IFU). Four planning
sessions and eleven tasks built the IFU, the instruction buffer, the
instruction TLB, the PMP/PMA checker, a page table walker, decode on the
IFU's packet, and a front-end top that fetches, predicts, decodes and retires
real programs.

The IFU was built in one task, and the build reported 15 conflicts between
planning documents that had been declared complete. A cross-check run
afterwards found 12 more. Integrating the front end then found defects that
every unit suite had passed over. The most consequential: a branch the
branch target buffer did not already hold could never be learned, so four of
the seven predictors received no training in any program.

The middle of the range is a change of method. Four consecutive tasks each
listed known defects and limited the implementation assistant to the files
those fixes needed, so every run ended with findings it was not permitted to
fix, and each became the next task. The fifth task was written as an end
state with a write grant across the front end and design decisions taken in
session. It fixed 16 defects in one run, each shown by reverting the fix on a
copy and observing a check fail.

The last three tasks used that form to complete uncached fetch, FENCE.I and
cbo.inval, a two-stage Sv39 walker with Svade and Svadu, and the decode
representation and legality of the RVA23 scalar and vector spaces, checked
over 458,752 encodings against an independent disassembler. At the close of
the range the regression runs 153 targets green and 36 front-end programs
retire exactly.

## Where the range starts

The previous fetch post ended with the instruction side specified and the
FTQ free of open technical debt. The regression, `tools/regress.sh`, ran 78
targets green. The IFU's remaining blockers were three rulings: what happens
to requests in flight when a redirect arrives (TD#134), where uncached fetch
goes (TD#135), and the IFU half of `FENCE.I` and `cbo.inval` (TD#136), which
also waited on the cache generator emitting an invalidate port (TD#119).
`rtl/core/frontend/ifu/rtl` held a `.gitkeep`.

Session 074 started by settling the IFU's open items. I ruled that the
interface between the IFU and the instruction buffer is a new struct,
`ifu_pd_pkt_t`, declared in `bp_structs_pkg` beside `ftq_pd_info_t`, and that
the older `predecode_pkt_t` stays in place for the built decoder until a later
task moves decode across (TD#143). The struct gained `is_rvc`, because
expansion of compressed instructions erases the instruction length and the
backend needs it. The line buffer depth became a parameter with a default of
16, one slot per L1I request identifier, with requests issued in order and a
block coalesced only against the previous request (TD#116). A block that
crosses a page holds two translation results in one queue entry, the second
from a second ITLB lookup (IFU-25). The translation queue depth became a
parameter, default 4 (IFU-U5). A new document, `cachegen_decisions.md`,
recorded that pacino drives the cache generator: the cache RTL may depart
from the emission, and the two are reconciled later by a comparison task and
a gap-fixing task.

`CLAUDE.md` was also updated in that session to allow a task to add, change
or remove package declarations, with the regression as the gate. The
previous rule had allowed additions only, and every package task in the
previous range had needed an exception.

## The packages and an assertion census

BP-115 declared the six L1I port parameters in `bp_defines_pkg`, the fault
cause enum `ifu_fault_e`, and `ifu_pd_pkt_t` at 175 bits. `PPN_WIDTH` was
rewritten as `PA_WIDTH - 12`, which keeps its value of 24. The task added a
lint-only module, `l1i_param_chk`, that compares each L1I parameter against
the emitted `l1i_pkg` by scoped reference and raises `$error` at elaboration
on a mismatch. A second target, `lint_neg`, overrides `PA_WIDTH` to 32 and
passes only if Verilator exits non-zero with the mismatch message, so the
check is seen to fail on every regression run. The IA reported that Verilator
5.048 reports an elaboration `$error` as `%Warning-USERERROR`, which is fatal
only because `-Wall` makes warnings fatal; adding `-Wno-fatal` would turn
`lint_neg` red, so the check cannot be weakened without a failure. It also
found that the task cited IB-4 for the fault causes where IB-9a was meant.

INFRA-013 was a read-only census of the FTQ's 85 property labels, built in
the previous range. The task asked which were declared but absent from a
simulation build. The method was to build each target with its exact command
line and read the hierarchical assertion names out of the C++ Verilator
generates, rather than counting source lines. Eight labels were absent from
at least one build. All eight had one cause: the property restated a direct
assignment, so Verilator folded it to a constant and removed it. Where a copy
of such a property survived in another build, it compiled to a comparison of
an expression with itself. Three more labels, I7, I10 and I11, restated
assignments and stayed compiled in every build. In `ftq_ifu_assert.sv`, 9 of
18 properties checked nothing.

The result produced a rule in `CLAUDE.md`'s assertion section: a property
compares the checked signal against a source independent of the RTL that
drives it, and a property that restates its driving assignment is not
written. TD#114 closed and TD#144 opened for the fixes.

## Building the IFU

BP-116 had two parts. Part A fixed TD#144: the eleven labels were deleted or
restated, four new properties checked the same rules from an independent
source, and an `assert_labels` target was added that fails if a declared
label is missing from any simulation model. Each new or restated property was
shown to fail under a mutation of the RTL line it protects. One of them, E8,
never fired in its own testbench because `tb_ftq_entry` reset immediately
after the write it checked, so no clock edge sampled the killed state; the IA
added a group to `tb_ftq_ifu` in which E8 has traffic.

Part B built the IFU: a structural top, `ifu.sv`, over seven modules
(`ifu_xlate`, `ifu_fetch`, `ifu_lbuf`, `ifu_rvc_exp`, `ifu_predecode`,
`ifu_f3`, `ifu_wb`), nine bound properties and three testbenches. The
expander testbench checks every 16-bit encoding at all 17 positions,
3,194,907 checks. The unit testbench drives all four boundaries from a memory
image, a page map and an L1I model with chosen latencies and return orders,
and derives the expected slot vector and writeback independently of the RTL;
it ran 385 checks over 16 named tests. Three deferred areas were stubbed, each
guarded by an assertion that fires if the testbench reaches the unbuilt case.

The task required the IA to list every conflict between the planning
documents before writing RTL. It listed 15, C1 to C15, built a reading for
each and presented none as a ruling. Two changed behavior. In C3, IFU-11 had
an instruction straddling a block boundary complete in the next block, while
IFU-8 and DCD-2 had it complete in its own; under IFU-11 its position in the
next block would be -1, which `ifu_pd_pkt_t.pos` cannot hold. In C6, the
instruction buffer truncates a predecode-redirected block after the
mispredict, while the FTQ refetches that block, so its first instructions
reach the buffer twice. Others were gaps: M1 did not say whether a JAL before
a predicted-taken position counts, and M3 can compare only the taken slot's
target because no other target reaches the IFU.

The PA had told me before BP-116 that the IFU planning side was complete. It
had applied rulings to each of eleven documents without checking any one
document's statement of a fact against another's. After the build it ran
that cross-check and found 12 more conflicts, C16 to C27, three in files it
had edited the same day. All 27 were resolved in the documents. Three needed
RTL and became TD#146: the predecode flush index (C6), the M1 rule (C5), and
the width of the ITLB request VPN (C19), which at 27 bits could not carry the
41-bit guest physical fetch PC.

BP-116's expander testbench used decode's existing `rvc_expander.sv` as its
reference and corrected it from the specification's field tables. In doing
so it found that `rvc_expander.sv` mis-expanded 12,456 of the 49,152 16-bit
encodings in six classes, among them C.BEQZ and C.BNEZ with negative offsets,
c.mul expanded as MULW, and the doubleword store offsets. That module had been
marked complete and passed its own tests. I ruled that it is not repaired: it
is retired with decode's old input path (TD#145, TD#143).

## An independent oracle for the expander

BP-117 built the three TD#146 rulings. A predecode redirect now flushes the
IFU at K+1, and the translation and fetch pointers each take the smaller of
their value and K+1; p2 and p3 redirects still flush at K. The change is
keyed on the FTQ's arbitration-arm signal, since the redirect cause cannot
carry the distinction. New checks failed 9, 2 and 13 times on the pre-edit
tree in three testbenches. A side effect was measured: a predecode redirect
now takes two cycles to its first translation request, not one, because the
flush target is a newly allocated block. M1 now fires on the first JAL before
the predicted-taken position and never on a JALR. The IA made M1 outrank M2
to M4, because a JAL before the taken position ends the path there; the
documents did not state a priority, and I ruled it as built.

The task also asked for a reference for `ifu_rvc_exp` independent of the
testbench model that had found TD#145, since that model was the only check on
it. Spike was not installed in this copy of the tree. The IA found an LLVM 21
toolchain installed outside the path. It wrote all 49,152 encodings to one
object file, had `llvm-objdump` expand each through LLVM's own compression
tables, and had `clang` re-encode the printed 32-bit form. No part of that
chain comes from the RTL or the testbench. 46,396 encodings compare directly.
The remainder are decided by the specification where LLVM keeps the encoding
16-bit (363 HINTs), has no 32-bit form (8 C.MOP encodings), prints an
equivalent but different word (992 C.MV encodings, where LLVM writes
`addi rd, rs2, 0` and the specification `add rd, x0, rs2`), or disagrees with
the specification (23 C.LUI encodings with a zero immediate, which the
specification reserves and LLVM accepts). The first run showed 22 mismatches
in both the RTL and the reference; they were the C.LUI encodings, and the
oracle was wrong, not the design. After that correction `ifu_rvc_exp` and the
testbench reference had zero mismatches. The comparison runs in the
regression as `oracle_ifu_rvc_exp`, and it confirms TD#145 from an
independent source.

The oracle depends on a toolchain at a fixed path outside the repository. On
a machine without it the target fails. That became TD#147.

## The front end in one task

BP-118 was written as two tasks and merged before either ran, to test how far
one IA session would go. It covered TD#113 (the FTQ entry's fall-through,
written at p1 and never corrected), TD#134 (the IFU flush with requests in
flight), the instruction buffer, the PMP/PMA checker, the ITLB, decode on
`ifu_pd_pkt_t`, two rulings to be checked against the built RTL, and a
front-end top, `fe_top`, with a testbench that fetches and decodes real
programs. Problems 3 to 6 were built by three sub-agents in parallel. It used
80% of a one-million-token context without compaction.

Its Problem 0 found the task's premise wrong. The task described the RAS half
of the p2 block-scalar group, `bpu_blk_ras_p2`, as existing. It had been ruled
in session 071 and never built. The documents described it in the present
tense, and the PA had taken that as fact. The IA stopped and asked, and I
ruled that the task build the full group.

TD#113 was built as a new p2 port, `bpu_blk_pft_p2`, driven from the same net
the cluster uses for the not-taken term of its p2 successor, so the entry's
fall-through and the redirect decision share one source. The IA found four
readers of the fall-through field where the interface document named two:
the fetch successor, the predecode successor, the RAS commit return address,
and the FTB update. TD#134 was built as IFU-28 to IFU-32: each structure
computes survival from the commit pointer, keeps blocks older than the flush
index, discards responses for dropped blocks, holds an L1I request already
presented until it is accepted and then discards its response, and waits for
dead ITLB lookups to drain. The two behaviors the documents did not state, the
held request and a rule for the straddle register, were accepted as built.

The new units: an instruction buffer that accepts a block whole and raises
ready only with 16 entries free (52 checks); a PMP/PMA checker with TOR and
NAPOT matching, a 4 KiB grain and a region-table parameter, referenced to
Spike's source for each rule (60 checks); and a 64-entry ITLB with four page
sizes, a permission check on every hit and every invalidate form (113 checks
at walk-tracker depth 1, 116 at depth 2). The IA reran each sub-agent's
mutation campaign itself rather than relying on the sub-agent's report.

The top-level testbench runs a bare-mode program of 107 instructions and an
Sv39 program of 54. Each retired instruction is checked for its PC, its FTQ
index and position, its expansion and its fault fields, and the retired
stream is exact across predecode redirects, backend mispredicts, traps, an
access fault and a page fault. Integration found disagreements between units
that each passed alone. One was a defect, fixed in the run: `ftq_status`
applied a writeback in the same cycle as a squash after the squash, so a
squashed entry kept its writeback-received bit. Another was not fixable in
scope: the FTQ presents one update record, the cluster takes a different
payload type per predictor, and no unit converts between them, so in the
integrated front end only the FTB and the RAS were trained. The run also
found that the uBTB never predicted a taken JAL at p1, that the `RETURN_CALL`
branch type existed in the documents and not in the enum, and that an IFU
line buffer count's stated bound was one short.

## Training every predictor

BP-119 built the update converter, `ftq_upd_conv`, inside the FTQ. Every field
of the five per-predictor payloads was traced to a source in the update
record, the predictor metadata or the FTQ entry, and the table is in the
task's results. The per-slot readies of each queued predictor are combined
by AND, and a slot is accepted only when every predictor it trains is ready
(TD#150). The SC ready is a grant that depends on the SC valid, so the
handshake presents the SC valid ahead of the SC ready.

With the converter connected, the integration exposed the defect the IA
reported as the main finding. A conditional branch or JALR that the FTB did
not already hold never got a slot in its FTQ entry: the p2 correction carries
only what the FTB returned, and predecode writes a slot only on a structural
mispredict, which only a JAL raises. Such a branch's resolution matched no
slot, and nothing was trained from it, the FTB included. In the `loops`
program 88 of 88 resolutions were unmapped, and TAGE, SC, the loop predictor
and ITTAGE received zero updates in every program, before and after the
converter. The unit suites were green throughout.

I first ruled to report it and leave the regression red. The IA then laid
out a proposal: place an unmapped resolution of a live entry in a slot in
program order, by the rule predecode corrections already use, and train it as
a mapped branch. I ruled to build it and to train the table predictors on that
first execution from the placed slot's prediction-time metadata. The placed
slot is written into the entry when the resolution is accepted, so the commit
walk sees it. In `loops` the cycles fell from 765 to 605 and the mispredicts
from 79 to 51, and every predictor trained.

Training exposed a second defect. An FTB entry covers a 32-byte region and has
one jump field. When a different jump in the region trained that field,
`ftb_cntrl.sv` kept the stored position and overwrote only the type and
target. In the `coro` program a return-call at position 4 and a return at
position 9 share a region; the entry ended up describing a return-call at
position 9, every block starting in the region predicted past the real one,
and all 20 return-calls mispredicted. `coro` went from 399 to 550 cycles. The
uBTB had the same rule. That defect was outside the task's files and became
TD#156.

The task also built `RETURN_CALL` at encoding 3'b111 everywhere (TD#152): the
RAS pops then pushes for it at prediction, repair and commit. Before the
change the RAS treated 3'b111 as no operation at every stage, and nothing
upstream ever produced it. It retired `rvc_expander.sv`, after fixing the
coverage script, which had credited compressed instructions only when their
mnemonic appeared in the RTL text. It fixed the uBTB jump case in the
cluster's p1 multiplexer rather than in the uBTB, because the uBTB interface
already said consumers must not read `br_taken` for a non-conditional type;
this removed every p2 redirect in two programs, 22 to 0 and 19 to 0. The line
buffer bound became a parameter, `LB_RD_MAX`, with a default of 33 derived
from the pipeline and an assertion that fires above it.

## Fixing what training exposed

BP-120 fixed what BP-119 had found and its task had not permitted it to fix.
A filled FTB or uBTB field now keeps its position only for an update at the
same region position; otherwise the jump field is rewritten whole and a
conditional field is filled as a new branch (TD#156). `coro` did not recover:
its mispredicts stayed at 39, because its two jumps now took turns in the one
jump field. The cause is the recorded design choice that every block start in
a region shares one FTB entry (`ftb_decisions.md` 4.6), which became TD#168.
A resolution held for a predictor's ready now trains the FTB once rather than
on every presentation (TD#157); in `loops` that removed 35 duplicate FTB
updates and raised mispredicts from 51 to 58, because the duplicates had been
stepping the FTB confidence. Two resolutions naming one slot are now
serialized, with an age rule stated in the results (TD#158). The RAS gained a
next-on-stack link per speculative entry (TD#159), proven at unit level; it
moved no front-end figure, because the RAS rarely operated at p2. The rise in
predecode redirects that BP-119 had noted turned out to be passes of the halt
loop during the testbench's 200-cycle drain after the program had retired
(TD#160).

The run found four more defects outside its files: a p3 slot write that
erased the p1 slots when the FTB had not answered, which caused a block that
did not follow its predecessor to be fetched; an FTB update that took the
read port in the cycle after a redirect and dropped that block's lookup; a
stale carried miss that overwrote a live entry; and a RAS push address taken
from the region-shared block end. None was fixed. Each became the next set of
technical debt items, TD#161 to TD#164.

## Changing the task form

BP-117 to BP-120 had each listed known defects and limited the IA's writes to
the files those fixes needed. Each run then found defects in other files,
reported them, and they became the next task. The front end had first run end
to end in BP-118, and each fix let a part run that had not run before, which
exposed the next defect. Rulings made before a task could not cover defects
that only a run could find. I asked why the work was iterating when the
intent had been to do it in one task.

I ruled a different form for BP-121, recorded in the project status:

- the IA may change anything under `rtl/core/frontend/`, its tests,
  Makefiles and the front-end programs, each fix with a check that fails
  before it;
- the packages may change, each change listed with its reason;
- the git calls `tools/regress.sh` makes are granted, and no other;
- a design choice is put to me in session; if I do not answer, the IA takes
  its recommended option, marks it provisional and continues;
- the task is written as an end state, not a defect list, and starts by
  writing programs that exercise every predictor path.

## The end-state task

BP-121 defined completion as: every program retires exactly and is a
regression target; each of the seven predictors both trains and supplies a
prediction that is used, in at least one program, shown by a count; no known
correctness defect in the front end is open; every repeating mispredict after
warm-up is fixed or has its cause stated and put to me; and the regression
passes.

It wrote 14 new programs, for 19 in all: a fixed-trip loop, history-dependent
conditionals, two conditionals in one block, branches the FTB holds and the
uBTB cannot, five-deep nesting, recursion, a call chain beyond the 15 usable
speculative RAS entries, history-dependent indirect jumps and calls, two
calls and a return in one region, one region entered from two starts, a block
crossing a region boundary with a straddling instruction, compressed control
transfers, a backend mispredict followed by a call, and predecode redirects.
On the tree as received, every program failed at least five checks and six
had stream errors.

The run fixed 16 defects, including the four BP-120 had found. The p3 slot
write is gated on the FTB having answered at p2, every resolution now writes
its slot, and slots above a resolved end are cleared, so the commit walk
commits only what executed. TAGE, ITTAGE and SC were returning 70 to 90
percent of their p2 responses late, because an update grant delayed a
prediction; the arbitration now grants a prediction first and an update only
when no prediction is presented, with a starvation hold. The FTQ holds p0 in
the cycle before an FTB update, so no lookup is dropped. The FTB stores one
bit per jump field saying whether the jump is compressed, and the RAS pushes
the jump PC plus 2 or 4 rather than the region-shared block end. History is
corrected on a redirect and the checkpoint rewritten. The FE-14 squash is
applied to the RAS, the p3 RAS repair uses the p3 reachability, and the p1
slots are put in position order.

Nine design questions went to me during the run and all nine were answered,
so none is provisional. Three replaced rules recorded in planning documents:
the arbitration rules of `bp_arb_spec.md` 4.5, the imprecise history of
`bp_history_decisions.md` 3.5, and a new backend assumption, A7, that the
backend commits an entry only after every resolution naming it is accepted.
The backend contract also gained a redirect input, `bkend_ftq_redir_taken`,
and a field, `ftq_resolve_t.is_rvc`.

Each fix was reverted alone on a copy of the final tree and shown to make at
least one check fail (m01 to m15). The IA found during that pass that two of
its fixes had no failing check and added two to the cluster testbench. It
also corrected its own in-session figures: they had come from a simulation
that ran every program in sequence with the predictor tables carried from one
to the next, which made every figure after the first program depend on
order. The regression now runs each program in its own simulation, and every
figure in the results comes from that mode.

Where the cause was a defect, mispredicts fell: `loops` 66 to 21, `lp` 110 to
17, `indir` 180 to 24, `hist` 126 to 33. Where it was not, they remained:
`deep` kept 91 mispredicts after warm-up out of 146, nearly all returns in
regions whose single jump field held another jump, which is TD#168. I had
ruled to keep the shared entry. The loop predictor trained in every program,
1,193 updates in all, and none of its predictions was used, because its update
rewrote the entry from the predict-time snapshot. I had ruled to leave it as
specified during the run, so that one end-state item was reported as blocked
by my ruling.[F1] No property was added for any of the 16 fixes; all are
covered by testbench checks (TD#170).[F1] The run took 3 hours 58 minutes and
one compaction.

## Uncached fetch, maintenance and a walker

Session 076 recorded BP-121's rulings and fixes in the documents and ruled the
IFU's memory path. Uncached fetch goes through the L1I marked uncached, as a
forced miss that never allocates, reversing the separate instruction source
IFU-21 had specified. Non-idempotent memory is never executable (MMU-15b), so
a whole-line read is safe. The L1I is changed in pacino's own copy of the
RTL rather than in the generator (CG-D1). Session 077 then ruled the walker:
there is no L2 TLB now, an ITLB miss goes to a walker shared by the I and D
sides outside the front-end top, and the walker has its own memory port. Full
Svadu was confirmed beside Svade. A PPN is never truncated, and page tables
are permitted only in cacheable coherent memory.

BP-123 was one end-state task in three parts. Part A copied the generated L1I
into `rtl/core/frontend/icache`, showed the unchanged copy passing the
emitted testbench as a regression target before changing it, and then added
the maintenance port (drain then clear) and the uncached request. The IFU
gained the commit-stage maintenance path and the uncached path. Uncached fetch
delivers one instruction per FTQ entry, under a gate that waits for every
older instruction to commit; this follows the XiangShan MMIO scheme [3]. The
results list eleven differences between the copy and the emission, for the
generator to catch up on later (TD#173).

Part B built the walker: Sv39 and nested Sv39x4 in all four combinations of
VS-stage and G-stage enabled or bare, Svade and Svadu per stage with a
compare-and-store that restarts the walk on a mismatch, Svnapot and Svpbmt at
both stages with every reserved encoding, PMP and PMA on every walker access,
and the guest physical address with an implicit-access kind for the backend
to form `htinst`. The walker has 526 checks and 10 properties in its own
testbench, and 16 new front-end programs cover every fault cause and source.
Part C examined the RVA23 extensions that reach the expander and decoder.

The run found defects in RTL built by earlier tasks. The ITLB applied its
U-bit check to translations with no VS-stage leaf, so every VS-mode fetch
through such an entry faulted. The checker accepted an executable,
non-idempotent region, and its own testbench used one. Decode raised illegal
on every Zba, Zbb and Zbs instruction except `sh1add`, which it decoded as a
plain ADD, so four Zcb instructions that expand to those forms trapped; it
also rejected Zimop, Zicond, Zawrs, SFENCE.VMA, Svinval, the hypervisor
loads and stores, and FLH and FSH, and it matched HFENCE.VVMA on the wrong
funct7, an error its test shared. Each was fixed with a check that failed
first, and 91 reversions on copies of the final tree were all caught. 18 of
the 19 earlier programs kept identical figures; `sv39` went from 206 to 309
cycles because its seven walks now run in RTL.

The Ziccif evidence is a property of the structure: every naturally aligned
32-bit instruction lies within one 64-byte line, both halfwords come from the
line buffer slot one L1I response filled, and an invalidate drains before it
clears. A testbench mode stamps every L1I response and checks that both halves
of every delivered instruction carry the same stamp.

The task's overview stated that every decision it needed had been ruled
before it was written. The IA took eight decisions, D1 to D8, provisionally,
because the planning set did not settle them; among them the uncached
mechanism, an access-type input on the walker, and which `PBMTE` governs each
stage, where the IA followed the specification over the planning text. Two
of the PA's recommendations had left gaps the IA reported: MMU-30 returned a
guest physical address that does not fit as zero, which collides with a fault
on guest page 0, and under Svadu the walker set the A bit before the ITLB's
U check could fault the access.

## Decode representation and legality

I ruled on BP-123's results: the faulting guest physical address is carried
whole at 56 bits and the zero sentinel is withdrawn; the walker makes every
leaf check, U against the request's privilege included, before it sets A;
and decode gains a complete representation. BP-124 built all three in one
task.

The decoder change was the largest. `alu_op_t` went to 8 bits with 79 new
operations; `decode_pkt_t` gained seven fields for FP precision, operand
register files and hypervisor accesses; register use became exact; every
immediate went to a defined position; and the legality of the FP, AMO, fence,
CBO, SYSTEM and vector spaces was implemented, with Zvbb decoded. The decoder
testbench went from 863 to 1,323 checks. Each of its 216 new test words was
assembled by `clang` and disassembled by `spike-dasm`, and a regression target
re-checks them.

A sweep then compared decode against `spike-dasm` over 458,752 encodings: every
value of every function, format, rounding-mode, width and selector field of the
FP, FMA, AMO, MISC-MEM, SYSTEM and vector spaces, with register fields at 0
and 1 and every operation-selecting register field over all 32 values. Decode
matched the expectation on every encoding. 47,733 disagreed with
`spike-dasm`'s literal answer, each resolved by a named rule: 21,147 belong to
extensions this design does not implement, 1,844 use the reserved rounding
modes, and 24,742 are reserved vector encodings that decode accepted. The
specification makes those reserved, not illegal, and the planning set at the
time said to report them for a ruling. The sweep also found a defect:
whole-register vector loads and stores were decoded as segment operations,
because the segment test ran before the whole-register test.

The task's Problem 0 asked what the expander oracle actually ran, because I
had reported no LLVM on the system. The IA found the LLVM 21 toolchain
installed outside the path, which is what BP-117 had used. The PA had accepted
my statement without checking and had written it into a decode rule; it had
also named `llvm-mc`, a tool sourced from nothing, as a requirement. Both
were corrected. The IA reported one number in its own results wrong: an
expected-legal total off by 140 against its own per-space figures.

BP-124 also reported an FTQ observation outside its scope. Under an M3
mispredict on a predicted-taken conditional with a wrong target, the FTQ wrote
the slot as not taken, so the successor became the fall-through. IFU-18 says
predecode cannot know a conditional's direction. I ruled that the FTQ keeps
the entry's taken bit and corrects only the target (TD#174), and that every
reserved vector encoding raises illegal-instruction (TD#175).

## The last task of the range

BP-125 built both rulings and three items I added. Part A changed one
expression in `ftq_ifu.sv`; no front-end program produces an M3 writeback on a
conditional, so it is checked at unit level only. Part B made the 24,742
reserved vector encodings illegal; the per-class counts sum to the number
BP-124 reported, and the expected-legal total fell to 208,902. Part D removed
two fields from `ifu_pd_pkt_t`, which decode computes for itself, taking the
struct from 192 to 190 bits. Part E measured the p2 and p3 post-redirect
latency, which the FTQ documents had recorded as inferred: one cycle for both.

Part C asked for a directed test of one case in the L1I's merge logic: a
cacheable request merging onto an uncached MSHR in the cycle its fill lands.
The test found a defect in all merge cases, not only the one it targeted. A
cacheable request merged onto an MSHR taken by an uncached request installed
the line but never updated the replacement state, because the uncached
lookup skips that update, the merged request does no lookup, and the fill
never wrote it. The installed line stayed its set's next victim. The fix is a
replacement update at install time, a second writer of the replacement state.

The run applied 33 reversions. 31 failed their named checks. One was caught
by different checks than the ones named, because in that run the translation
pointer was already at the redirect index and the reverted rewind had
nothing to undo. One was not caught at all: a gate that stops an ordinary
cacheable install from updating the replacement state a second time. No
planning rule asked for it and no test can see it, and it became TD#177.

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|------------|-------------|--------|--------|---------|---------|
| BP-115 | L1I parameters, ifu_pd_pkt_t, l1i_param_chk | PASS | 80/80 targets; lint_neg | 9m 29s | 16% |
| INFRA-013 | FTQ property census, read-only | PASS | 85 labels; 8 absent | 8m 25s | 14% |
| BP-116 | TD#144; the IFU, eight modules | PASS | 93/93; ifu 385/0; 27 doc conflicts | 1h 14m 40s | 60% |
| BP-117 | TD#146; LLVM oracle for the expander | PASS | 94/94; 49,152 encodings, 0 mismatches | 41m 3s | 40% |
| BP-118 | TD#113, TD#134; ibuf, PMP/PMA, ITLB, decode, fe_top | PASS | 104/104; 2 programs exact | 2h 2m 41s incl. regression | 80% |
| BP-119 | Update converter; unmapped placement; RETURN_CALL | PASS | 104/104; fe_top 35/0 | 1h 30m 35s incl. fix | 69% |
| BP-120 | FTB/uBTB position, FTB trained once, RAS link | PASS | 104/104; 4 defects reported | 1h 39m 5s | 54% |
| BP-121 | End-state task; 19 programs | PASS | 123/123; 16 defects, 9 decisions | 3h 57m 57s | 100%+20%, 1 compaction |
| BP-123 | L1I copy, maintenance, uncached, walker, Z* | PASS | 149/149; 91 reversions caught | 2h 44m 26s | 100%+10%, 1 compaction |
| BP-124 | 56-bit GPA, leaf checks, decode legality | PASS | 153/153; 458,752-encoding sweep | 2h 15m, IA estimate | 83% |
| BP-125 | W1, reserved vector, L1I merge, FTQ items | PASS | 153/153; 31 of 33 reversions caught | 1h 9m 6s | 45% |

## Design Process Notes

### The IA contribution

The IA found most of what this range fixed by running the design, not by
reading documents. BP-116 listed 15 document conflicts before writing RTL.
BP-118's integration found the missing converter and the squash ordering
defect. BP-119 found that a branch absent from the FTB could never be learned,
diagnosed the cause across the cluster, predecode and the FTQ, and proposed
the placement rule I ruled. BP-121 found 16 defects and stopped to have nine
design questions answered. BP-123 and BP-124 found decode defects in
instruction classes no task had named. BP-125's directed test found a defect
in cases broader than the one it was written for.

Its evidence standard was the same in every RTL task: a check that fails on
the unmodified tree before a fix, and for each new property or fix a
reversion on a copy outside the tree that makes it fail. Where that standard
did not hold it said so: BP-121 found two fixes with no failing check and
added them; BP-125 reported one reversion that was caught by other checks and
one that was not caught. It corrected its own figures when it found they came
from a simulation with carried predictor state. It reported each case where a
task's premise was false: the unbuilt p2 group, the 27-bit VPN, the
uncached-fetch mechanism the documents did not specify, the LLVM toolchain.

It also acted outside its limits. It ran git commands the task prohibited in
INFRA-013, BP-118 and BP-123, and BP-118's sub-agent did the same. It read
files outside the manifest in BP-119 and BP-120, and ran a tool outside the
run grant in BP-124. Each was reported by the IA itself. After BP-118 I set
git commands to require approval in the project settings; BP-123's command
ran without the prompt appearing. Enforcement outside the model, a sandbox
for the tool, is planned. From BP-124 every task carries a fixed paragraph
stating that the IA runs no git command, that running `tools/regress.sh` does
not grant the commands it contains, and that reading it grants nothing.

### The PA contribution

The PA wrote the eleven task files and recorded every ruling in the document
that owns it, with a checksum script updated in the same delivery so that I
could confirm the installed planning files matched what it wrote. It drafted
the converter field sourcing, the IFU flush rules IFU-28 to IFU-32, the
walker rules of session 077 against the ratified privileged specification,
and the decode representation DCD-21 to DCD-35 that BP-124 built.

Several of its errors changed artifacts. It declared the IFU documents
complete without cross-checking them, and 27 conflicts followed. It described
the p2 RAS port as built, listed `rvc_expander.sv` for deletion without
checking its users, took `RETURN_CALL` and a configuration input from the
documents without checking the RTL, and left the ITLB-to-walker VPN at 27
bits after widening the IFU side for the same reason. It scoped BP-119's
decode cleanup without the package change its fields required, and wrote
BP-120 to require the regression while forbidding the git calls the
regression makes. It wrote BP-117 to BP-120 with narrow file grants, which is
what produced one task per finding. It stated in BP-123 that every decision
was ruled when eight were not, and recommended MMU-30, which had the guest
page 0 gap. It accepted my LLVM statement without evidence and invented a
tool requirement. It copied a vsetvl field range, bits 30:25, from BP-124's
report into DCD-32 unchecked; BP-125 built 29:25, which is correct because bit
30 set is vsetivli. Each correction is in the documents.

### My contribution

I ruled the session 074 IFU items, the TD#146 rulings and the M1 priority,
the retirement of `rvc_expander.sv`, the merge of BP-118, the full p2 group,
and the placement of unmapped resolutions with training of every predictor
on first execution. I changed the task form after BP-120 and answered the
nine BP-121 questions in session, including keeping the shared FTB entry and
replacing the arbitration and history rules. I ruled uncached fetch through
the L1I, the pacino L1I copy, no L2 TLB with the walker on its own port, full
Svadu, the 56-bit faulting address, the leaf checks before A, the decode
representation, W1 for a conditional, and every reserved vector encoding
illegal. I accepted the IA's provisional decisions in BP-123 to BP-125. I
rebuilt Spike for the decoder check, moved git commands to require approval,
and planned the sandbox.

### The generalization

Two observations hold across this range.

The first concerns task form. BP-117 to BP-120 each ended with findings in
files the task did not grant, and each finding became a task. BP-121, with a
write grant across the front end, decisions taken in session and a defined
end state, ended with 16 defects fixed and nothing carried except by ruling.
BP-123 to BP-125 used the same form with the decisions settled beforehand
where the PA could foresee them, and each ended with provisional decisions I
accepted. The cost of the form was run length, up to four hours and one
compaction, and a larger review of each result.

The second concerns where defects were found. Every unit suite passed while
four of seven predictors received no training, while the commit walk depended
on a p3 write defect, and while the L1I left merged lines as the next victim.
The integrated programs and new directed tests found them. Figures from the
integrated runs were themselves wrong until each program ran in its own
simulation. In this range a passing unit suite was not evidence that the
assembled front end worked, and an integrated figure was not evidence until
its measurement conditions were checked.

## What comes next

At the close of the range the front end fetches, translates, predicts,
decodes and retires 36 programs exactly, with every predictor trained and
used.[F1] The regression runs 153 targets green. The generator does not yet
emit what the pacino L1I copy carries (TD#173). The out-of-repository
toolchain the oracles depend on has a ruling and no path variable yet
(TD#147, TD#176). The shared FTB entry stays by ruling and remains the largest
remaining source of mispredicts (TD#168). The next session scrubs the
remaining open technical debt item by item.

## Technical Debt Referenced

The table below reports status as of the close of this range. Later
experiments outside the range have since changed the state of some items.

| # | Item | Resolution path |
|---|---|---|
| 113 | FTQ entry fall-through written at p1, never corrected. | Closed by BP-118. |
| 114 | FTQ property labels absent from simulation builds. | Closed by INFRA-013. |
| 116 | IFU line buffer, issue and coalescing unspecified. | Closed by ruling, session 074. |
| 119 | No invalidate port on the emitted L1I. | Closed by BP-123 in the pacino copy. |
| 122 | L1I parameters undeclared; nothing checks them. | Closed by BP-115. |
| 134 | IFU flush with requests in flight. | Closed by BP-118. |
| 135 | The uncached fetch path. | Closed by BP-123. |
| 136 | The IFU half of FENCE.I and cbo.inval. | Closed by BP-123. |
| 143 | Retire predecode_pkt_t, predecode.sv and rvc_expander.sv. | Closed by BP-119. |
| 144 | FTQ properties that restate their driving assignment. | Closed by BP-116. |
| 145 | rvc_expander.sv wrong in 12,456 encodings. | Closed by ruling: retired, not repaired. |
| 146 | Predecode flush at K+1, M1 rule, ITLB VPN width. | Closed by BP-117. |
| 147 | Oracle depends on a toolchain at a fixed path. | Open. Ruled: a configurable path, carried by TD#176.[F2] |
| 148 | is_vsetvl and needs_vtype in ifu_pd_pkt_t have no reader. | Closed by BP-125. |
| 150 | Per-slot readies ANDed per predictor. | Open, deferred to measurement. |
| 151 | No conversion from the update record to predictor payloads. | Closed by BP-119. |
| 152 | RETURN_CALL in the documents and not the RTL. | Closed by BP-119. |
| 153 | ifu_lbuf reader bound one short. | Closed by BP-119. |
| 154 | uBTB never predicts a taken jump at p1. | Closed by BP-119. |
| 155 | Dead decode enables en_c, en_zcb, MASK_BITS. | Closed by BP-120. |
| 156 | FTB and uBTB keep a stored position for a different branch. | Closed by BP-120. |
| 157 | FTB trained twice for a held resolution. | Closed by BP-120. |
| 158 | Two resolutions naming one slot. | Closed by BP-120. |
| 159 | RAS pointer rules after a pop then a push. | Closed by BP-120. |
| 160 | Predecode redirect count rose with the uBTB trained. | Closed by BP-120: the halt loop in the drain. |
| 161 | p3 slot write erases the p1 slots; stream error. | Closed by BP-121. |
| 162 | FTB update drops the lookup after a redirect. | Closed by BP-121. |
| 163 | Stale carried miss overwrites a live entry. | Closed by BP-121. |
| 164 | RAS pushes the region-shared block end. | Closed by BP-121. |
| 165 | Two return-call repair pairings wrong. | Closed by ruling: unreachable by construction. |
| 166 | p3 RAS repair never fires. | Closed by BP-121. |
| 167 | tb_fe_top counts measured past the last retirement. | Closed by BP-121. |
| 168 | Every start in a region shares one FTB jump field. | Kept by ruling; measured by BP-121.[F2] |
| 169 | Loop predictor trained, never used. | Closed by BP-122, outside this post.[F1] |
| 170 | No properties for the BP-121 fixes. | Closed by BP-122, outside this post.[F1] |
| 171 | Faulting GPA width, leaf checks before A, decode representation. | Closed by BP-124. |
| 172 | Same-cycle L1I merge untested. | Closed by BP-125. |
| 173 | Generator to catch up with the pacino L1I copy. | Open. |
| 174 | W1 writes a predicted-taken conditional as not taken. | Closed by BP-125. |
| 175 | Reserved vector encodings accepted. | Closed by BP-125. |
| 176 | A path variable for out-of-repository tools. | Open.[F2] |
| 177 | The install-time replacement gate has no check. | Open.[F2] |

## References

[1] RISC-V International, "RVA23 Profiles", ratified,
https://github.com/riscv/riscv-profiles

[2] RISC-V International, "The RISC-V Instruction Set Manual", release
riscv-isa-release-1b9ca13-2026-10-08, unprivileged F, Zfa and vector chapters
and privileged supervisor, hypervisor and machine chapters,
https://github.com/riscv/riscv-isa-manual

[3] XiangShan front-end design documentation, https://docs.xiangshan.cc

- Specifying the Instruction Side, and What Building Against It Found
  (BLOG_fetch_3), for the specification this range builds.

## Footnotes

<!-- ticfinder_off -->
[F1] BP-122, in session 076, put the loop predictor into use with a
read-before-write update and a speculative iteration count, closing TD#169,
and added properties for the BP-121 fixes, closing TD#170. It is covered in
the branch prediction series.

[F2] TD#147 and TD#176 closed by BP-132; TD#177 closed by BP-132; TD#168
closed by BP-140, which gave each block start its own FTB entry.
<!-- ticfinder_on -->

---
<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
