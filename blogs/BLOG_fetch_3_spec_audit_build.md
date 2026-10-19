<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

```
TITLE:     "Specifying the Instruction Side, and What Building Against It Found"
FILE:      BLOG_fetch_3_spec_audit_build.md
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

# Specifying the Instruction Side, and What Building Against It Found

## Abstract

The Pacino RVA23 front end had a complete branch prediction cluster and a
complete fetch target queue (FTQ), an instruction cache emitted by a
generator, and no instruction fetch unit (IFU). This range specified
everything between the FTQ and decode, audited the planning documents
against each other, and then built the rulings the audit produced.

One planning session wrote eight new decision and interface documents: the
IFU, predecode, the instruction buffer, the instruction TLB, the memory
management unit and the front-end top. Translation runs in its own pipeline
ahead of fetch, because the cache is physically indexed. The hypervisor
extension is mandatory in RVA23 through Sha, so the walk is two-stage and
the faulting guest physical address travels back to the IFU.

Three sessions of cross-document audit followed, driven by a separate audit
tool, amending 27, 41 and 47 documents. They produced compliance rulings:
the virtual address is 41 bits, not 40; the stored block end could not
represent an unaligned block; branch positions are stored relative to the
32-byte region.

Seven tasks then built those rulings and a regression command. Building
found what the audit did not. One recorded bounds check had never been
built. One rule keyed on a signal that cannot carry the distinction it
needed. A pointer was specified after its unit was complete and never built.
Four testbenches exited 0 on a failed check. Five existing checks encoded a
correctness defect as expected behavior: after any redirect, the first 32
bytes of the corrected instruction stream were never fetched. At the close
of the range the FTQ has no open technical debt and the IFU's remaining
gates are rulings, not code.

## Where the range starts

The previous fetch post closed with the FTQ complete: eleven modules, 22
targets, 670 checks and 73 properties, verified against a modelled
neighbor on each side. A separate tools session then specified the L1
instruction cache and had the cache generator emit it: 64 KiB, 8-way,
64-byte lines, physically indexed and tagged, a 512-bit core port returning
a full line, and sixteen misses in flight. I had decided that the cache is
a sibling of the IFU inside the front end, not part of it, and that there
is still no FTQ-to-cache interface.

Below the FTQ nothing else had a specification. `rtl/core/frontend/ifu/rtl`
held a `.gitkeep`. The instruction buffer directory existed with no planning
record. The handoff into this range named the instruction TLB as the first
blocker: a physically indexed cache puts translation in the fetch path ahead
of the array, and nothing specified it.

## Specifying the instruction side

### Two pipelines

Session 069 wrote `itlb_decisions.md`, `mmu_decisions.md`,
`ifu_decisions.md`, `ibuf_decisions.md` and `dcd_decisions.md`, three
interface documents between them, and section 15 of `fe_decisions.md`, the
front-end top. No task ran and no RTL was written.

The defining decision is that the IFU has two decoupled pipelines.
Because the cache is physically indexed, a fetch cannot be issued in the
cycle its translation begins. Translation therefore runs ahead in its own
pipeline, driven by a new FTQ pointer, `xlate_ptr`, and joined to the fetch
pipeline by a translation queue. The fetch pipeline has five stages, F0
through F3 and a writeback stage. This follows the XiangShan arrangement [2]
without its way lookup, since the cache is generated and a second pipeline
inside it would be a generator change. The FTQ moved from three pointers to
four.

The first draft of the fetch stages issued the cache request in the same
stage that started the TLB lookup. The parallel audit caught it in the same
session, and the two-pipeline decision is the correction.

### The block and its slots

A prediction block is 32 bytes and starts at any 2-byte address, so a block
can cover two cache lines. The IFU fetches both lines when a block starts
in the upper half of a line, covers 34 bytes, and examines 17 halfword
positions to produce up to 16 instruction slots. Compressed instructions are
expanded in the IFU before predecode, so the instruction buffer holds
uniform 32-bit slots and the IFU owns the instruction that straddles a
block boundary. That ordering is the reverse of the reference design. The
reason, that predecode on expanded encodings needs only the base-ISA branch
forms, was my observation during the session.

The instruction buffer takes 16 slots in and gives 8 out. It accepts a
block whole, signalling ready only when 16 entries are free, bypasses
itself when empty, and is 64 entries deep as a parameter. The floor is 32
from whole-block acceptance; 64 is eight times the decode width of 8.

### Translation

The instruction TLB is 64 entries, fully associative, with the three Sv39
page sizes in one array, ASID tagged, with a one-cycle hit. Behind it the
documents placed a shared second-level TLB containing the page table
walker.[F1] PMP is checked at two sites, the translated physical address and
every walker access, by one checker specified once and instantiated twice.

Mid-session the PA stated that the hypervisor extension was optional in
RVA23S64 and removed guest-page faults from the fault classes of two
interface documents. RVA23 makes Sha mandatory and H is part of Sha [1].
Both edits were reverted and the consequence was written through ten
documents. The walk is nested: every address the VS-stage produces is a
guest physical address needing its own G-stage walk. TLB entries carry a
VMID and a V bit. There is a third fetch fault cause, instruction
guest-page fault, cause 20. Under Shtvala the faulting guest physical
address is returned from the walk and carried to the backend, the one
address the IFU did not supply. The handoff recorded that profile
membership should be looked up in the ratified text every time rather than
recalled, because the extension's status changed between profile versions.

### The front-end top

`fe_decisions.md` section 15 defines a front-end top instantiating the
branch prediction cluster, the FTQ, the IFU, the cache, the instruction TLB,
the instruction buffer and decode. The cache and the TLB are inside it as
siblings of the IFU; the shared second-level TLB is outside. At the close
of session 069 every module had a decision document and every port had an
interface document, and every port in the three new interface documents
connected to something that did not exist.

## The audit

Session 069 also started a cross-document audit, run in a parallel session
by my audit tool. Its findings came to the PA in batches,
the PA corrected them, and I ran a checksum script after every delivery so
that a later batch was not run against a stale copy. Sessions 070, 071 and
072 continued it. They amended 27, 41 and 47 documents and ran no task. I
ruled that the audit would complete before any RTL change cycle, and closed
it at the end of session 072.

Most of the individual findings were document corrections: a stale width,
a count, a cross-reference to a moved section. The form that worked was a
specific claim in one document checked against the document it names, with
the consequence stated. A notable share of findings in each session were
against edits the PA had made earlier in the same session, and the
correction that reduced them was mechanical: after each edit, search the
whole tree for the changed identifier and the changed number.

Six rulings came out of the audit and are what the next session built.

THE VIRTUAL ADDRESS IS 41 BITS. With H mandatory, the G-stage is Sv39x4,
and `vsatp.MODE=Bare` is required, so with V=1 and Bare the fetch PC is a
guest physical address of up to 41 bits, zero extended. `VA_WIDTH` was 40.
The 41-bit range did not fit, and the ITTAGE target reconstruction sign
extended, which corrupts any guest physical address with bit 38 set. I
ruled `VA_WIDTH` 41 and pinned the FTB tag at 26 bits and the ITTAGE target
field at 38, on the distinction now recorded as FE-19: an architectural
address may not truncate, and predictor storage may.

THE BLOCK END COULD NOT BE REPRESENTED. The FTB and uBTB store the block's
fall-through as an offset from the 32-byte-aligned region base, in a 5-bit
field plus a carry bit. The RTL wrote a 4-bit slice into it, so the fifth
bit was never set, and for a block starting near the end of a region whose
last instruction straddles the boundary the offset reaches 64, which
reconstructs as base plus 32. That is wrong by 32 bytes and passes the
bounds check, because base plus 32 is still above the start. I ruled the
field 6 bits with the carry deleted, at the same storage.

BRANCH POSITIONS ARE STORED RELATIVE TO THE REGION. An informal read of the
RTL by the IA in session 071 found that the update path stored a branch
position relative to the block start and the cluster read it against the
aligned region base. Every block not starting on a 32-byte boundary got a
branch PC wrong by the start offset, and a branch recorded by an earlier
start in the same region was still reported. The suites were green because
the testbenches used aligned bases. I ruled that stored positions are
region relative, converted inside the FTB and uBTB, with a read window
that hides fields outside the block and every port start relative. The FTB
entry grew from 110 to 113 bits.

The same IA read found the IFU flush index wrong for front-end redirects
and the fourth FTQ pointer specified and not built. Each became a technical
debt item.

The other three rulings set terms the IFU work depends on. Direction is one
quantity, ranked SC over TAGE over FTB, except when the FTB fast path fires;
targets are selected by branch type, not ranked. A prediction block is 32
bytes and a fetch block is the 64-byte cache line; the documents had used
"fetch block" for both. The effective memory type of a page is the most
restrictive of the region table and both page-based memory type fields,
which the PA had first described as dictated by the specification.

The audit ended with one rule blocking the build. `CLAUDE.md` allowed a
task to add a package declaration and forbade changing or removing one.
Each pending item changed one. A per-task waiver was discussed and dropped
in favor of running the whole tree after every task.[F2]

## Building against the specification

### A regression command

TOOLS-006 built `tools/regress.sh`. It finds every Makefile under `rtl/`,
reads each one's defined targets from make's rule database, and fails the
run if a target is in neither the Makefile's regression list nor its
exclusion list. A hand-kept list that omits a target cannot pass under any
name. A target fails on a non-zero exit or on any warning in its log.
`tools/known_failures.txt` is the only waiver list; a listed target that
now passes, or was not run, also fails the run. A pre-push hook refuses a
push on a red result.

Each detection path was proven by injecting a fault into a scratch copy of
the tree. The injections found that the library testbench and all three
decode testbenches printed a failed check and exited 0. Their printed
counts were correct throughout, so no recorded result changed, but a
regression reading exit status would have reported them as passing. They
now exit through `$fatal(1)`. In an interactive follow-on the IA found that
decode and the library had been compiling with Verilator 5.020 from the
path instead of the project's 5.048; both now use the project's tool. The
decode suite then ran three times faster with identical check counts, and
the cause was recorded as unexplained.[F3]

### The 41-bit address

BP-109 changed `VA_WIDTH` to 41, pinned the two predictor widths, declared
the nine translation widths the interface documents already used, and
replaced every address literal in the tree. The inventory found 1,307 sites
in 31 files, all in the branch prediction unit and the FTQ. Seven sites
took their width from how an expression was built rather than from a
number, and no text search could find them. The IA found them by running
the regression on a copy at 41 bits and reading the width warnings. One was
the ITTAGE reconstruction.

The testbench model of that reconstruction zero extended while the RTL sign
extended. The 1,795 cluster checks had never noticed, because no test set
bit 38. Two new checks were each shown to fail on exactly the defect they
target: on the full pre-fix tree both failed, with only the sign extension
restored only one failed, and with only `VA_WIDTH` restored only the other.

The IA also reported that zero extension is wrong for a V=0 kernel
address, whose upper bits are set, and that a wrong ITTAGE entry is
sticky: the update writes back the bits the entry already holds, so the
entry keeps its confidence and keeps overriding the FTB. At my request it
wrote a proposal to take the upper bits from the PC. I ruled instead that
the ITTAGE stores bits 40:1 of the target and that no extension rule
remains, reversing the 38-bit pin.

### The block end and the positions

BP-110 built the block end and region-relative position rulings together,
since the second changes the widths of fields the first rewrites. The task
required the defects to be pinned first. The IA rebuilt the tree as it
stood at session start and ran the new cases against it: 10 failures in the
FTB testbench, 5 in the uBTB testbench and 8 in the cluster testbench, each
showing the exact defect, such as an end read back 32 bytes short.

It also found that the FTB had no fall-through bounds check at all. The
planning documents recorded the check as restored in session 069, and the
RTL comment read "no error check". The IA built it with a second, upper
bound. The uBTB received the masking without the compaction the FTB
applies, because the task said only "identical" and the interface document
said otherwise. I ruled that divergence explicit, and ruled that the uBTB
is not bounds checked. The prompt cited a finding labelled C9, an audit
batch number rather than a registry item, and the IA reported that no such
item exists.

### The ITTAGE target

BP-111 built the 40-bit ITTAGE target and moved the FTB jump target base
from the region to the jump PC, to match the ruling that every target is a
displacement from its own instruction. The entry widths went from 54, 54,
55, 55, 57 to 56, 56, 57, 57, 59 bits, and the array from 226,304 to
234,496 bits. The ruling had given 8,192 bits as two bits times 2,048
entries times two banks. The IA reported that the factor of two is the two
per-slot RAM copies; the banks divide a copy.

The pinning cases included one showing the stickiness: after a mispredict
and an update with the resolved target, the entry still produced the wrong
target. For the jump base, one round-trip case could not be made to fail,
since both bases are common to every start sharing the entry. The IA said
so rather than constructing a failure, and found the one observable
difference, a target at the edge of the 21-bit reach.

### The flush index and the fourth pointer

BP-112 built the two FTQ items the IA read had found. The flush rule keyed
the IFU flush index on the redirect cause. The FTQ's next-PC selection
drives the same cause encoding for a p2, p3, predecode or backend
mispredict, so the distinction the rule needed is not on the bus. The rule
could not be met as written. The IA routed the arbitration's winning-arm
signal, which until then was only terminated in the top, and reported that
the fix had a second half: the fetch pointer also rewound past entry K, so
flushing the IFU at K alone would have left K flushed and never presented
again.

It built `xlate_ptr` and the translation request group, stopping for
rulings where the documents were silent. Mutation found that a new property
was never evaluated, because a reset followed each redirect it watched. The
IA also ran `git stash` and `git stash pop` to compare against its
baseline, which unstaged a file; it restored the index and reported it. I
ruled that the IA has no permission for git commands that change state,
enforced in how the session is launched rather than by a rule it must
remember.

I wrote in the task assessment that its in-session questions could have
been answered in the prompt. The PA had written the three relevant problems
without reading the three documents they implement.

### The skipped redirect target

BP-112 also found the defect that mattered most in the range. In a redirect
cycle the request leaving at p0 carried the allocation index from before
the rewind. The redirect target block was written to an entry the same
redirect squashed and was never fetched, and the next entry held the target
plus 32. The first 32 bytes of the corrected instruction stream were
skipped, on every redirect cause including trap and debug entry.

BP-113 fixed it, and required the new checks to compare the PC each fetch
carried, not only the index. On the pre-edit tree the new group failed 15
checks while its index checks passed, which is how the existing checks had
missed it. Five existing checks, two of them written to cover this path,
had the defect as their expected value. They were corrected with my
approval, each with a comment recording its old value. The post-redirect
translation latency then measured one cycle for a front-end redirect and
two for a backend redirect, a split the documents had not stated.

### The RC_UNSPEC flush, and a wrong rule

BP-114 closed three FTQ items. The flush index for the redirect that names
no instruction, used for reset and debug entry, was recorded as a mismatch
between a comment and the code. The task found it was a defect: that
redirect squashes every entry, and the flush named the fetch pointer, so 18
in-flight fetches in the test case survived and would have written back
into squashed entries.

The PA had written a rule the turn before, stating that the field-rewrite
rules apply to the second writeback of a refetched entry. The IA reported
that the rewrite and the redirect are one event in the RTL and its
assertions, so the rule would have changed an entry's successor with no
flush. It left the RTL as built and asked for a ruling. The rule was
corrected in the document.

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|------------|-------------|--------|--------|---------|---------|
| TOOLS-006 | tools/regress.sh, regression plumbing, pre-push hook | PASS | 78/78 targets; 4 testbenches fixed to fail | 33m 22s + interactive | 23% |
| BP-109 | VA_WIDTH 41, nine widths, 1,307-site sweep | PASS | 78/78; cluster 1795 -> 1799 | 39m 43s | 31% |
| BP-110 | 6-bit block end, region-relative positions | PASS | 78/78; +43 checks, pinned failing first | 24m 46s | 35% |
| BP-111 | ITTAGE target VA[40:1]; jump target base | PASS | 78/78; +25 checks | 18m 50s, partly interactive | 22% |
| BP-112 | IFU flush index at K; xlate_ptr; translation group | PASS | 78/78; +95 checks; TD#139 found | 36m 12s | 33% |
| BP-113 | Redirect target allocated to a surviving entry | PASS | 78/78; +57 checks; 5 checks corrected | 20m 6s | 24% |
| BP-114 | RC_UNSPEC flush; commit pointer export; I4 | PASS | 78/78; +32 checks | 21m 2s | 25% |

## Design Process Notes

### The IA contribution

In four of the six RTL tasks the IA found something the task did not name.
It found the seven width sites no search could reach by running the tree at
the new width. It found that the FTB had no bounds check while the
documents said it had been restored. It found that the flush fix needed a
second half in the fetch pointer, that the W3 rule could not be met from
the bus it was written against, and the skipped redirect target. In BP-114
it found that a recorded comment mismatch was a defect.

It pinned each defect with a check that fails on the unmodified tree, and
in BP-109 showed each check fails on its own defect and on nothing else.
It said when a case could not be made to fail rather than manufacturing
one. When a task's premise or a planning rule was wrong it reported the
conflict and left the RTL as built: the factor of two in the ITTAGE cost,
the uBTB divergence, the refetch rule. In TOOLS-006 it found the four
testbenches that could not fail through exit status by injecting faults,
not by reading their output.

### The PA contribution

The PA wrote the eight documents of session 069 and the corrections for
every audit batch, applied by exact-match replacement against the original
text, and kept a checksum script current so each delivery could be checked
against the tree. It wrote the seven task files in the problems form, each
requiring a baseline, a defect pinned before the fix, and a mutation proof
for each new property.

Several of its errors changed artifacts. It stated that H was optional and
edited two documents on that basis before reverting them. A share of each
audit session's findings were against its own edits from earlier in that
session. It cited an audit batch number into BP-110 as if it were a registry
item. It wrote BP-112's problems without reading the documents they
implement. It wrote the refetch rule that BP-114 found wrong. In each case
the correction is in the documents and the next prompt.

### My contribution

I set the order and the scope: specification first, the audit to completion
before any RTL change, and the RTL change cycle as one task per pair of
related items. I ran the audit tool. I ordered expansion before
predecode. I ruled the 41-bit address and the two pins, the 6-bit block
end, region-relative storage and its three open points, the direction
chain, the fetch and prediction block terms, and the strict memory type
rule. In session 073 I ruled that package changes are gated by the
regression rather than a waiver, that the ITTAGE stores the full target,
that every target is a displacement from its own instruction, that the
front end delivers one prediction block per cycle, and that a redirect
cycle carries no fetch request. I split the IFU's wrong-path, uncached and
maintenance work into separate sessions, and removed the IA's permission
for state-changing git commands. In the TOOLS-006 follow-on I had the
Verilator version and the top-level Makefile fixed and rewrote the
verification rules in `CLAUDE.md`.

### The generalization

The audit compared 47 documents with each other and found inconsistency
well. It did not find a rule that no RTL could meet, because the documents
agreed with each other. Three such rules were in the tree at the close of
the audit: a bounds check recorded as restored and never built, a fourth
pointer specified after the unit was complete, and a flush rule keyed on a
signal that cannot carry the distinction. The informal IA read of the RTL
in session 071 and the build in session 073 found all three. In this range
a planning document that the RTL has not met is a claim, and the check for
it is building against it or reading the RTL against it.

The same holds for test results. Four testbenches could not fail through
exit status. A cluster model disagreed with its RTL across 1,795 passing
checks. Five checks, two written for the path, certified the skipped
target. Each was found by a different mechanism: fault injection, a
width change, and a new check written before the fix. None was found by
reading a passing result.

## What comes next

At the close of the range the FTQ has no open technical debt and the
regression runs 78 targets green. The IFU's remaining gates are three
rulings: what happens to requests in flight when a redirect arrives, where
uncached fetch goes, and the IFU half of `FENCE.I` and `cbo.inval`, which
also waits on the cache generator emitting an invalidate port. An IFU built
before the first is unit testable only. The `CLAUDE.md` package rule still
forbids what every package task in the range was authorized to do.

## Technical Debt Referenced

The table below reports status as of the close of this range. Later
experiments outside the range have since changed the state of some items.

| # | Item | Resolution path |
|---|---|---|
| 99 | `make all` silently omits targets; no repo-level regression. | Closed by TOOLS-006. |
| 122 | VA_WIDTH 40 cannot hold a fetch PC; nine translation widths undeclared. | RTL change closed by BP-109; cache parameter half open (TD-IF-1). |
| 124 | Block end cannot represent an unaligned block. | Closed by BP-110. |
| 125 | Stored positions read against the wrong base. | Closed by BP-110. |
| 126 | IFU flush index K+1 where K is required for front-end redirects. | Closed by BP-112. |
| 127 | xlate_ptr and the translation request group specified, not built. | Closed by BP-112. |
| 129 | Top-level `rtl/Makefile` targets incomplete. | Open. Complete or retire in favor of regress.sh. |
| 130 | regress.sh reporting gaps: six unparsed totals, cov_bpu count, TD field. | Open. |
| 131 | Decode suite three times faster under 5.048, unexplained. | Open.[F3] |
| 132 | ITTAGE upper-half targets; wrong entry sticky. | Closed by BP-111: stores VA[40:1]. |
| 134 | Wrong-path requests in flight after a redirect. | Open. Its own session.[F4] |
| 135 | The uncached fetch path. | Open. Its own session.[F4] |
| 136 | The IFU half of FENCE.I and cbo.inval. | Open, behind TD#119.[F4] |
| 137 | FTB jump target measured from the region base. | Closed by BP-111. |
| 138 | Redirect and request handshake in the same cycle. | Closed by ruling: no request accompanies a flush. |
| 139 | Redirect target written to a squashed entry; first block lost. | Closed by BP-113. |
| 140 | Assertion I4 treated the refetch writeback as an error. | Closed by BP-114. |
| 141 | RC_UNSPEC flush index named the fetch pointer. | Closed by BP-114. |
| 142 | ftq_ifu_commit_ptr specified, not built. | Closed by BP-114. |

## References

[1] RISC-V International, "RVA23 Profiles", ratified,
https://github.com/riscv/riscv-profiles

[2] XiangShan front-end design documentation,
https://docs.xiangshan.cc

- Building the Fetch Target Queue: Eleven Modules and Fault-Injected
  Properties (BLOG_fetch_2), for the FTQ this range builds against.

## Footnotes

<!-- ticfinder_off -->
[F1] The shared second-level TLB was reversed in session 077: there is no
L2 TLB now, and a TLB miss goes to the walker directly. The same session
corrected the PMA check to apply to every walker access. Session 076
reversed the separate uncached instruction source specified here; uncached
fetch goes through the cache, marked uncached.

[F2] `CLAUDE.md` was updated in session 074 to allow a task to add, change
or remove package declarations, with the regression as the gate.

[F3] Later explained in BP-132 as the 5.048 install enabling ccache.

[F4] TD#134 closed by BP-118; TD#135 and TD#136 closed by BP-123.
<!-- ticfinder_on -->

---
<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
