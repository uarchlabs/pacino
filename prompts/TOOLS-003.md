<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | TOOLS-003               |                          |
| Date         | 2026.08.28              |                          |
| Module       | cachegen config, L1I/IFU| waiver, see Constraints  |
| Run time     | 25m.12s                 |                          |
| Ctx %        | 26%                     |                          |
| Model        | claude-opus-5[1m] high  |                          |
| Resume sha   | bf830537-f5c1-4772-a4c8-47fe09241819 |             |
| PA session   | 068                     |                          |

Task:   [X] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Mode:   [X] automated   [ ] manual          [ ] interactive
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview

Three parts, one task.

1. pa_bits 32 -> 36 across the cachegen configuration, together
   with every link address width, in ONE commit.
2. The IFU-to-L1I interface required for a non-blocking L1I.
3. The same interface's maintenance path, for Zicbom and FENCE.I,
   both ends.

Parts 2 and 3 produce one new planning document,
planning/interfaces/l1i_ifu_interfaces.md.

WAIVER, THIS TASK ONLY. See Constraints.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion

## Claude.code Console Output

TOOLS-003 is complete. All three parts landed and proven.

  Part 1 — pa_bits 36. Confirmed the three field paths against the schema before
  editing (INFRA-012 had them right). Five values in two files moved together:
  addressing.pa_bits, pe_port.custom.address_width_bits, and address_bits on all
  three TileLink links.

  Part 2 — the checker rule. New T-10.addr_width in cli/src/checker.cpp:333,
  with a neg_link_addr_width fixture cut from base that produces exactly one
  diagnostic. Reverting the link widths in a scratch copy now yields two errors
  naming exactly the two sites INFRA-012 found adapting silently. TD-L1I-6
  closes.

  Part 3 — proof. Suite 86/0 before, 87/0 after. Five tests encoded pa_bits, not
  the two the task named — Bank.L2DecomposesAsTheRulingSays was the one that
  actually failed the build. Pacino.ViptIndexBudgetIsMet, which the task did
  name, needed no change: the VIPT budget lives below the page offset and
  pa_bits only adds bits above the index.

  Three things worth your attention:

  The regeneration exposed three emitter width defects. Hardcoded 32-bit
  intermediates in rtl_tb.cpp and rtl_cache.cpp — arithmetic done at a literal
  32 and widened afterwards. Four of seven nodes failed lint. Fixed, because a
  tree that doesn't lint isn't a landed change. All seven now lint clean and all
  fourteen sim/lint targets pass. The 512-bit core port defect I confirmed by
  experiment (it's a hard Verilator error, and it breaks the emitted testbench
  too, which E1 doesn't cover) — deliberately not fixed, since that's Part 2's
  interface and out of scope.

  Two correctness defects in icache_decisions.md, not just accuracy ones:
  - 7 M1's "FENCE.I is a single-cycle operation" is wrong. The clear is
    single-cycle; with sixteen requests outstanding a fill lands after it and
    re-validates the line the fence removed. It's drain-then-clear.
  - L1I-14 and L1I-18 don't meet. The IFU holds a 64-byte line and nothing says
    an invalidate clears it — the same stale-instruction-line failure section
    2.2 uses to reject VIPT, by another route.

  On cbo.inval, I checked spike rather than asserting: the CBIE gate is real (2
  bits at [5:4], value 2 reserved, 0 traps below M), but whether cbo.inval
  reaches an instruction cache is not fixed by the architecture at all. So
  TD-L1I-2 is partly resolved, not closed — the port is specified for both
  readings and the routing choice is yours as IF-U3.

  The document is planning/interfaces/l1i_ifu_interfaces.md, 1047 lines,
  IF-1..IF-37. Four items are marked yours and not taken: the req_rdy
  implementation (address-dependent vs conservative — a frequency call),
  invalidate_line latency, cbo.inval routing, and the non-blocking ITLB
  assumption.

## My Assessment

I found no issues in review of l1i_ifu_interfaces.md or the results reported
by the IA.

pasted icache_decisions.md and l1i_ifu_interfaces.md as requested by PA.

## Claude.ai Assessment

Strong result, and the anti-iteration structure did what it was meant to: 25 minutes, 26% context, no questions came back.

The two that matter

D1 and D2 are correctness defects in my document, not accuracy. FENCE.I as single-cycle is wrong — a fill in flight lands after the clear and re-validates the line the fence removed. It's drain-then-clear. And L1I-14 and L1I-18 don't meet: I put a 64-byte line in the IFU and put the invalidate path through the IFU, and never said the buffer is part of what gets cleared. That's the stale-instruction-line failure section 2.2 uses to reject VIPT, arriving by a route I created.

Both are the exercise working. Writing down what the IFU must drive found them, same as TD-FE-6 and TD-FE-7 in the FTQ.

D4 is the one I'd have missed longest. 8.1 P2 says a prefetch never occupies an MSHR a demand miss requires, and L1I-19 puts the prefetch requester at the IFU, which cannot see the MSHR file. The rule has no enforcer. Either the interface distinguishes prefetch from demand — a port the IA deliberately didn't add — or P2 gets restated. That's a decision for you.

What the task got wrong

I named two tests; five encoded pa_bits. Three the IA found from the derivation, and Bank.L2DecomposesAsTheRulingSays only surfaced by running the suite. My list came from INFRA-012's report, which named the two that encode geometry — I read it as the complete set of tests touching the L1I derivation and it wasn't.

Pacino.ViptIndexBudgetIsMet needed no change, and the reason is clean: the VIPT budget lives below the page offset and pa_bits only adds bits above the index. That's the "number that didn't move where you expected" case answered properly.

Three notes

The three emitter width defects are all one mistake — arithmetic at a literal 32, widened afterward — and none could produce a wrong answer at pa_bits 32. Invisible until the value moved. The fourth, key_of, correctly left alone as value-correct.

VA_WIDTH 40 in bp_defines_pkg.sv against topology va_bits 39 is the same class T-10 just closed, on the other address, with nothing checking it. That's DEF-3 and it's a real finding.

The tag is 24, not the 23 in section 1.2, because the configured geometry is still 32 KiB 1 bank. Both numbers are right for different geometries and my document doesn't say which. G1 through G4 remain unapplied.

Where this leaves things

Six document defects to fold into icache_decisions.md, two of them correctness. Then the configuration task — G1 through G4 — is the next cachegen step, and it's the one that makes the 23-bit tag real.

I'd want to read l1i_ifu_interfaces.md before the fold, since D1 and D2 change what section 7 and L1I-14 say, and the new document already specifies drain-then-clear as IF-something.

## Follow-on Actions
- [ ] As needed document here

## CLAUDE.md Updates
Nothing required

## Other Planning File Updates
Nothing required

:: DISCUSSION:END ::

=============================================================
:: PROMPT:START ::
=============================================================

## Task ID
TOOLS-003

## Context Loaded
@planning/arch/icache_decisions.md
@planning/interfaces/ftq_ifu_interfaces.md
@planning/arch/ftq_decisions.md
@prompts/INFRA-012.md
@tools/cachegen/CLAUDE.md
@tools/cachegen/planning/schema/caches.schema.json
@tools/cachegen/planning/schema/links.schema.json
@tools/cachegen/planning/schema/system.schema.json
@tools/cachegen/planning/schema/ports.schema.json
@tools/cachegen/planning/schema/topology.schema.json
@tools/cachegen/testcases/pacino/pacino_caches.json
@tools/cachegen/testcases/pacino/pacino_links.json
@tools/cachegen/testcases/pacino/pacino_ports.json
@tools/cachegen/testcases/pacino/pacino_system.json
@tools/cachegen/testcases/pacino/pacino_topology.json
@tools/cachegen/output/l1i/rtl/l1i_core_slv.sv
@tools/cachegen/output/l1i/rtl/l1i_ctrl.sv
@tools/cachegen/output/l1i/rtl/l1i_mem_mst.sv
@tools/cachegen/output/l1i/rtl/l1i_pkg.sv
@tools/cachegen/output/pacino/rtl/pe_port_pkg.sv

## Context Comments

READING UNDER THESE DIRECTORIES IS PERMITTED:

```
  tools/cachegen/cli/inc/       headers
  tools/cachegen/cli/src/       the tool
  tools/cachegen/cli/tb/        the unit suite and its fixtures
  tools/cachegen/output/        the emitted tree
  planning/                     the riscv-codesign planning record
```

Directory listing anywhere in either tree is permitted.

DO NOT READ tools/cachegen/examples/. A hand-written cache model
predating cachegen; not the tool.

DO NOT ANSWER FROM tools/cachegen/docs/pacino_cache.md. It is
generated, its own header calls it incomplete or likely incorrect,
and it has already produced two wrong field paths on the PA side.
Read the JSON, the schema and the source.

INFRA-012 IS IN THE MANIFEST AS THE PRIOR AUDIT. Its Results
Capture enumerates what cachegen can and cannot do today, with file
and line references. Treat its findings as a starting point to be
CONFIRMED, not as fact: it was a read-only audit and this task
changes things it only inspected.

ONLY THE CLI MATTERS in cachegen. No functional-model feature is in
scope.

## Hypothesis

Part 1 is mechanical and its risk is entirely in what moves
together. pa_bits and the link address widths are independent
integers today and nothing checks that they agree, so changing one
without the others silently zero-extends on one side of an adapter
and truncates on the other.

Parts 2 and 3 are a specification, not an implementation. The L1I
that icache_decisions.md describes cannot be emitted by cachegen
today (INFRA-012). Its core interface is nonetheless decidable now,
because what the IFU needs does not depend on how the cache is
built, and writing it down is what lets the emitter work be
specified without a second round of questions.

## Background

Pacino is an 8-issue RVA23 out-of-order processor. Its BPU and FTQ
are built and verified; the IFU is unbuilt, and
rtl/core/frontend/ifu/rtl holds only a .gitkeep.

planning/arch/icache_decisions.md specifies the L1 instruction
cache. It is DELIBERATELY INCOMPLETE at its core boundary: section
4 states the shape -- one full 64-byte line per request, sixteen
outstanding, out-of-order response carrying an identifier -- and
stops. There is no port list, no handshake, no backpressure rule
and no maintenance path. Part 2 and part 3 close that, and the gap
is the reason this task exists rather than a cachegen task being
written directly.

pa_bits is 32 today. RVA23 does not fix it: Sv39 bounds it through
the PTE's PPN field and the implementation chooses. RULED
session-068: 36 bits, matching XiangShan Kunminghu under Sv39.
icache_decisions.md L1I-U1 records it as open with that
recommendation; this task is where it stops being open.

## Binding Previous Decisions

1. pa_bits IS 36. Jeff's ruling, session-068. Not this task's to
   evaluate. The tag becomes 23 bits at the L1I geometry.

2. icache_decisions.md IS THE L1I SPECIFICATION. Sections 1 through
   9 are decided. Parts 2 and 3 must be consistent with them and
   must not restate them; the new document specifies PORTS, the
   decisions document specifies BEHAVIOUR.

   Load-bearing for parts 2 and 3:

```
     L1I-9   one full 64-byte line per request, 512-bit data path
     L1I-10  sixteen outstanding requests
     L1I-12  sixteen MSHRs, L1I-13 four targets each
     L1I-14  the IFU holds the returned line; the L1I has no
             last-line register
     L1I-4   the L1I receives a PHYSICAL address; T1/T2/T3 of 2.3
             are what it requires of the ITLB
     L1I-18  the only invalidate path is core side, through the
             IFU. invalidate_line and invalidate_all yes,
             flush_line and flush_all no
     4.3 R1  requests are LINE ALIGNED; the IFU does the block
             extract
     4.3 R2  responses may return OUT OF ORDER, carrying the
             identifier of the request they answer
```

3. THE CONFIGURATION IS THE OTHER SIDE OF THE SAME BOUNDARY. What
   part 2 specifies as ports, cachegen must eventually emit. Where
   the two disagree, REPORT IT; do not bend the specification to
   what the tool can express today.

4. ftq_ifu_interfaces.md IS THE IFU'S OTHER BOUNDARY and is built
   on the FTQ side. The new document must not contradict it and
   must not duplicate it.

## Specific Requirements

Problems, not procedure. Method, ordering and decomposition are
yours. Parts 1, 2 and 3 are independent; part 1 first is
suggested, not required.

PART 1 -- pa_bits 36

PROBLEM 1 -- ONE COMMIT, OR NONE.

Set pa_bits to 36 and set every link's address width to match, in
a single change. INFRA-012 reports the field as topology
addressing.pa_bits and the link fields as custom.address_width_bits
and tilelink.address_bits; CONFIRM those paths against the schema
and the JSON before editing, and report what you found if they
differ.

WHY THIS IS ONE CHANGE AND NOT TWO. Nothing checks the two against
each other. INFRA-012 found that at pa_bits 36 with the links left
at 32, rtl_cache.cpp zero-extends a 32-bit link address into a
36-bit node address with no diagnostic, and the memory-side master
drives a 32-bit address from a 36-bit register, truncating the top
four bits -- four bits of physical address lost on every refill,
silently. A tree in that state builds and passes.

Report every file changed, every key, and the before and after
value.

PROBLEM 2 -- MAKE IT IMPOSSIBLE TO REINTRODUCE.

Add the checker rule that reports an error when a link's address
width disagrees with the system pa_bits, on an edge whose endpoints
are cache or memory nodes.

This is a checker rule and not a schema constraint because the
schema cannot see across documents. Follow the existing pattern:
one diagnostic code, one negative fixture producing EXACTLY ONE
diagnostic, cut from the clean base. neg_addressing_disagree is the
closest existing fixture and is the model.

The rule is worth having even though problem 1 makes the tree
agree, because it is what stops the next change from silently
disagreeing.

PROBLEM 3 -- PROVE IT.

Run the cachegen unit suite before and after. Report both counts.
Two existing tests are known to encode the current geometry
(GeometryPacino.L1iDerivation, Pacino.ViptIndexBudgetIsMet); if
either encodes pa_bits or a tag width, it changes with this task
and the change is reported.

Regenerate and report what moved in the emitted tree: the tag
width, the address type, the package constants. A number that did
not move where you expected it to is a finding.

PART 2 -- THE NON-BLOCKING IFU-TO-L1I INTERFACE

PROBLEM 4 -- SPECIFY THE PORTS.

Write the interface an IFU needs to drive a NON-BLOCKING L1I as
icache_decisions.md section 4 describes it. Signal names, widths,
directions, and the protocol.

What the specification must settle, because none of it is decided
anywhere today:

```
  the request     what identifies a request, how wide the id is,
                  what the address is (L1I-4: physical, line
                  aligned), and what the IFU must hold until the
                  response returns
  the response    how it names the request it answers, and whether
                  a response may be presented in the same cycle as
                  the request that produced it
  backpressure    what the L1I asserts when it cannot accept, and
                  what the IFU is required to do about it.
                  SIXTEEN outstanding is the limit; say what
                  happens at seventeen
  the miss        whether a miss is visible on this interface at
                  all, or only as latency. If visible, what the IFU
                  may do with the knowledge
  merging         two requests naming the same line while the first
                  is in flight. L1I-13 gives four targets per MSHR;
                  say what the requester sees
  the fault path  2.3 T2 puts translation faults BESIDE the L1I,
                  not through it. Say what that means for this
                  interface: does a faulting request reach the L1I
                  at all, and if not, what the IFU does instead
  reset           what is required of both sides out of reset
```

STATE THE PROTOCOL AS RULES, each numbered, each checkable. A rule
a testbench cannot check is a comment.

WHERE A CHOICE EXISTS, take it and say what you rejected. Do not
leave an open item for something this interface can settle.

WHERE A CHOICE BELONGS TO JEFF, say so plainly and do not take it.
A parameter that changes area or frequency is his; a signal name is
not.

PROBLEM 5 -- WHAT THE CONFIGURATION CAN AND CANNOT SAY.

For the interface of problem 4, report which parts a cachegen link
definition can express today, which need a schema change, and which
need an emitter change. INFRA-012's problem 4 has most of this
already; confirm it and extend it to whatever problem 4 adds.

This is the input to the cachegen task that follows. It does not
change the specification.

PART 3 -- MAINTENANCE

PROBLEM 6 -- THE INVALIDATE PATH, BOTH ENDS.

RVA23 mandates Zicbom. icache_decisions.md 7 M1 and M2 name
FENCE.I and cbo.inval as the drivers and L1I-18 puts the path core
side, through the IFU. No generated node emits an invalidate port
of any kind today (INFRA-012 E7), so this is specification only.

Specify BOTH ENDS:

```
  IFU -> L1I    the invalidate ports. Line and all. What carries
                the address, what acknowledges completion, and
                whether fetch may proceed while an invalidate is
                in flight
  in -> IFU     where FENCE.I and cbo.inval REACH the IFU from.
                They are executed instructions; something upstream
                must tell the front end. Name the boundary, its
                ports, and what the IFU owes back -- an
                acknowledgement is required or FENCE.I has no
                completion semantics
```

The second half has no existing document and no built producer.
Specify what the IFU requires, name the assumptions it makes about
the producer, and mark each assumption unverifiable if the producer
does not exist.

CHECK THE PRIVILEGED SPECIFICATION on one point rather than
asserting it: whether cbo.inval on an instruction cache reaches the
cache at all is conditioned by menvcfg.CBIE, and the architecture
permits the instruction to trap or to be remapped. icache_decisions
TD-L1I-2 carries this as unverified. Report what you find; if it is
not determinable, say so and specify the port for both readings.

PROBLEM 7 -- THE DOCUMENT.

Deliver parts 2 and 3 as one document,
planning/interfaces/l1i_ifu_interfaces.md.

Follow the conventions of the planning/interfaces/ set --
ftq_ifu_interfaces.md is the nearest model. Header block, scope
section naming companion documents, numbered sections, a document
history entry.

NUMBERING. This document owns the IF- registry, IF-1 upward, for
its own decisions and rules. Do not use IC- (an interface-check
identifier in ftb_interfaces.md and sc_interfaces.md), L1I-
(icache_decisions.md), or FE- / TD-FE- / FE-U (fe_decisions.md).
Open items are IF-U1 upward; technical debt is TD-IF-1 upward.

REPORT ANY DEFECT YOU FIND IN icache_decisions.md rather than
working around it. Writing down what the IFU must drive is exactly
the exercise that found TD-FE-6 and TD-FE-7 in the FTQ, and the
same is expected here.

## Constraints

- WAIVER, TOOLS-003 ONLY. This task MAY write:
    planning/interfaces/l1i_ifu_interfaces.md   (new)
    tools/cachegen/planning/schema/*.json
    tools/cachegen/testcases/pacino/*.json
    tools/cachegen/cli/src/*, tools/cachegen/cli/inc/*
    tools/cachegen/cli/tb/*
  It covers this task only. It is NOT precedent and does NOT
  propagate to the next task, including one continuing this work.
  Every other file under planning/, pa_handoffs/ and docs/ in
  BOTH trees remains read-only.

- DO NOT MODIFY any other planning document. icache_decisions.md is
  READ-ONLY in this task: report what it should say, in Results
  Capture, and the PA will draft it.

- PART 1 IS ONE COMMIT. The pa_bits change and the link address
  widths land together. If that turns out to be impossible, stop
  and report why rather than landing half.

- PARTS 2 AND 3 ARE SPECIFICATION. No RTL. No emitter change for
  the interface they describe; problem 5 reports what such a change
  would be and stops there.

- The riscv-codesign bpu and ftq suites are not in scope and must
  not be run. No RTL under rtl/ is touched.

- Regenerating the cachegen output tree IS permitted and problem 3
  requires it. Report what the regeneration changed.

## Deliverables

- planning/interfaces/l1i_ifu_interfaces.md, new
- tools/cachegen configuration, schema, source and fixtures as
  problems 1 and 2 require
- Results Capture filled in below, in this file:
  prompts/TOOLS-003.md

Fill in every section. Test Matrix is omitted: this task adds no
RTL test cases. Report the cachegen suite counts before and after,
every configuration key changed with its before and after value,
and any defect found in icache_decisions.md.

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary

All three parts complete. pa_bits is 36 and every link address width
moved with it in one change. A new checker rule, T-10.addr_width,
makes the two disagreeing an error on any edge touching a cache or
memory node, with a negative fixture producing exactly one
diagnostic. The cachegen unit suite went 86 pass / 0 fail before to
87 pass / 0 fail after, the +1 being the new fixture's test.

Regenerating the tree at pa_bits 36 EXPOSED TWO EMITTER WIDTH
DEFECTS that were invisible while pa_bits equalled every data width.
Both were fixed, because a tree that no longer lints is not a landed
change. A third defect, the one INFRA-012 predicted for a 512-bit
core port, was CONFIRMED BY EXPERIMENT and deliberately NOT fixed:
it belongs to the interface of Part 2, which the constraints put out
of scope for emitter work.

Parts 2 and 3 are delivered as planning/interfaces/
l1i_ifu_interfaces.md, 1047 lines, 37 numbered rules IF-1 through
IF-37, 5 open items, 5 technical debt entries, 6 defects reported
against icache_decisions.md and 5 unverifiable assumptions about a
producer that does not exist.

## What was delivered

### PART 1 -- PROBLEM 1, ONE COMMIT

FIELD PATHS CONFIRMED against the schema and the JSON before
editing. INFRA-012's report was correct on all three:

```
  topology.schema.json  addressing.pa_bits, integer, min 8 max 64
  links.schema.json     custom.address_width_bits, min 1 max 128,
                        in the custom required list
  links.schema.json     tilelink.address_bits, min 0 max 128,
                        in the tilelink required list
```

Five values changed, in two files, in one edit set.

```
  FILE                    KEY                                BEFORE AFTER
  pacino_topology.json    /addressing/pa_bits                    32    36
  pacino_links.json       /links/pe_port/custom/
                            address_width_bits                   32    36
  pacino_links.json       /links/tl_l1i_l2/tilelink/
                            address_bits                         32    36
  pacino_links.json       /links/tl_l1d_l2/tilelink/
                            address_bits                         32    36
  pacino_links.json       /links/tl_l2_mem/tilelink/
                            address_bits                         32    36
```

Nothing else in the configuration changed. The l1i geometry is
still 32 KiB, 8-way, 1 bank, VIPT: INFRA-012's G1 through G4 are a
different change and were not in this task's scope.

### PART 1 -- PROBLEM 2, THE CHECKER RULE

New diagnostic `T-10.addr_width`, reach Fixture. T-10 is the next
free number; T-1 through T-9 are in use and T-8 lives in Geometry.

```
  cli/inc/diag_codes.h    one X() row, after t9_link_agree so the
                          checker rules stay grouped
  cli/inc/checker.h       addr_width(), link_addr_bits(),
                          is_addressed(), and the header note
  cli/src/checker.cpp     the rule, 96 lines, called from run()
                          after port_roles and before graph
```

THE RULE. For each edge whose link resolved, where AT LEAST ONE
endpoint is a node of type icache, dcache, unified or memory, read
the link's address width -- `tilelink.address_bits` or
`custom.address_width_bits` per its protocol -- and report an error
when it differs from the system pa_bits.

ONE DIAGNOSTIC PER OFFENDING LINK, not per edge. The width is one
value in one file, so one edit clears it, and pe_port is carried by
two edges and would otherwise report the same field twice. The T-5
cycle rule already sets the deduplication precedent.

THE FIXTURE. `cli/tb/fixtures/neg_link_addr_width/`, cut from base
exactly as neg_addressing_disagree is: system.json includes
../base/base_caches.json and ../base/base_topology.json unchanged
and carries a local links.json that is base_links.json with l_core
widened to 40. l_mem is untouched, so exactly one link disagrees
and exactly one diagnostic is produced. Verified:

```
  neg_link_addr_width/links.json:/links/l_core/custom/
  address_width_bits: [T-10.addr_width] link 'l_core' declares an
  address width of 40 bits and the system pa_bits is 32. Edge 'e0'
  carries it into a node whose address type is pa_bits wide, so the
  two must agree
```

REINTRODUCTION PROVEN. A scratch copy of the pacino configuration
with pa_bits left at 36 and pe_port and tl_l1i_l2 reverted to 32
now produces two errors, naming exactly the two sites INFRA-012
found silently adapting:

```
  /links/pe_port/custom/address_width_bits   edge ifu_l1i
  /links/tl_l1i_l2/tilelink/address_bits     edge l1i_l2
```

The pe_port diagnostic is reported once although pe_port is on two
edges, which is the deduplication working.

TD-L1I-6 IS CLOSED by this rule.

### PART 1 -- PROBLEM 3, PROOF

SUITE COUNTS, both from runs in this session.

```
  BEFORE   86 tests, 86 passed, 0 failed
  AFTER    87 tests, 87 passed, 0 failed
```

The +1 is `Negative.LinkAddressWidthDisagreesWithPaBits`.

FIVE TESTS ENCODED pa_bits 32, NOT THE TWO THE TASK NAMED. The task
named GeometryPacino.L1iDerivation and Pacino.ViptIndexBudgetIsMet.
The actual set:

```
  test_geometry.cpp  GeometryPacino.L1iDerivation      CHANGED
                     tag_bits 20 -> 24, tag.msb 31 -> 35, tag.mask
                     0xfffff000 -> 0xffffff000, the field sum
                     32 -> 36, offset and index masks re-spelled at
                     9 hex digits. Offset, index and their masks'
                     VALUES are unchanged: pa_bits moves the tag and
                     nothing below bit 12.

  test_geometry.cpp  GeometryPacino.L2Derivation       CHANGED
                     tag_bits 16 -> 20. NOT NAMED IN THE TASK.

  test_geometry.cpp  GeometryPacino.MemoryIsTerminal   CHANGED
                     tag_bits 2 -> 6. NOT NAMED IN THE TASK.

  test_bank.cpp      Bank.L2DecomposesAsTheRulingSays  CHANGED
                     tag.bits 16 -> 20, tag.msb 31 -> 35. NOT NAMED
                     IN THE TASK, and it is the one that actually
                     failed the build: the three geometry edits were
                     made from the derivation, this one was found by
                     running the suite.

  test_pacino.cpp    Pacino.EverythingElseResolves     CHANGED
                     m.pa_bits 32 -> 36, and a T-10.addr_width
                     zero-count added beside the other T-codes so
                     the positive fixture proves the new rule stays
                     silent. NOT NAMED IN THE TASK.

  test_pacino.cpp    Pacino.ViptIndexBudgetIsMet       UNCHANGED
                     NAMED IN THE TASK AND DID NOT NEED CHANGING.
                     It asserts indexing == VIPT, bytes_per_way ==
                     page_bytes and offset+index == 12. All three
                     are geometry and page size; none involves
                     pa_bits. This is the "number that did not move
                     where you expected it to" case, and the reason
                     is that the VIPT budget is about the bits BELOW
                     the page offset and pa_bits only adds bits
                     above the index.
```

WHAT MOVED IN THE EMITTED TREE. Regenerated with --cmd=emit into
the tracked output directory; 40 files differ. The baseline was
captured first by emitting into a scratch directory and confirming
it was byte-identical to the committed tree.

```
  l1i_pkg.sv    L1iPaBits    32 -> 36
                L1iTagBits   20 -> 24
                L1iTagMsb    31 -> 35
  l1d_pkg.sv    same three, same values
  l2_pkg.sv     L2PaBits 32 -> 36, L2TagBits 16 -> 20,
                L2TagMsb 31 -> 35
  mem_pkg.sv    MemPaBits 32 -> 36, MemTagBits 2 -> 6,
                MemTagMsb 31 -> 35
  pe_port_pkg.sv       PePortAddrBits and PePortWAddr 32 -> 36
  tl_l1i_l2_pkg.sv     TlL1iL2AddrBits, TlL1iL2WAAddress 32 -> 36
  tl_l1d_l2_pkg.sv     AddrBits, WAAddress, WBAddress, WCAddress
  tl_l2_mem_pkg.sv     AddrBits, WAAddress
  every adapter and top   [31:0] -> [35:0] on every address port
  testbenches             address literals respelled 36'h0_...
  logs/geometry.log       pa_bits 36, every tag and mask
  logs/features.log       four `declared 32` -> `declared 36`
```

NUMBERS THAT DID NOT MOVE, AND WHY EACH IS CORRECT.

```
  l1i_meta_array.sv, l1i_data_array.sv, l1i_bank.sv, l1i_ctrl.sv
      UNCHANGED. They take the tag width through the l1i_tag_t
      typedef rather than a literal, so a wider tag needs no textual
      change. Verified by reading l1i_meta_array.sv, which declares
      tag_mem as l1i_tag_t.

  logs/unconsumed.log
      UNCHANGED. address_width_bits and address_bits were already
      consumed by link_sig during emit, so the checker's new read of
      them adds nothing to the report. Confirmed byte-identical.

  emission.log file list
      UNCHANGED. 83 files before and after; no file appeared or
      disappeared.

  L1I TAG IS 24, NOT THE 23 icache_decisions.md 1.2 NAMES.
      Reported as defect D5. 23 is the tag at the L1I-1 geometry,
      64 KiB 8-way 2 banks. The configuration still carries 32 KiB
      1 bank, so 6 offset + 6 index + 24 tag = 36 is right for what
      is configured. Both numbers are in the document and it does
      not say which geometry each belongs to.
```

EMITTED TREE VERIFIED, not just diffed. Every node's Makefile has a
lint target and a run target and all fourteen were run:

```
  NODE     lint   run    checks
  ifu       ok     ok     3 passed, 0 failed
  lsu       ok     ok     3 passed, 0 failed
  l1i       ok     ok    14 passed, 0 failed
  l1d       ok     ok    15 passed, 0 failed
  l2        ok     ok    15 passed, 0 failed
  mem       ok     ok     4 passed, 0 failed
  pacino    ok     ok    22 passed, 0 failed
```

THIS IS WHERE THE TWO EMITTER DEFECTS CAME FROM. The first
regeneration lint-failed on four of the seven nodes. Both defects
are hardcoded 32-bit intermediates that were invisible while the
address width and the data width were both 32.

```
  DEFECT 1  cli/src/rtl_tb.cpp, the agent testbench slave model.
            A read of an address never written answers with the
            ADDRESS as the read DATA. At 36-bit address into 32-bit
            rdata that is WIDTHTRUNC on the assign and WIDTHEXPAND
            on the conditional's other arm.
            FIX: cast to WordBits. Sites: ifu_tb_slv.sv,
            lsu_tb_slv.sv, and both again inside pacino_tb.

  DEFECT 2  cli/src/rtl_cache.cpp, the TileLink slave adapter's
            per-beat address. It emitted
              addr_t'({16'd0, beat_i} << WordShift)
            which performs the shift in 32 bits and widens the
            answer. The 16'd0 hardcodes the 32.
            FIX: (addr_t'(beat_i) << WordShift), so the shift is at
            addr_t width. Sites: l2_up_i_slv.sv, l2_up_d_slv.sv.

  DEFECT 3  cli/src/rtl_tb.cpp, the top-level eviction loop.
              abits'((k + 1) * stride)
            with k an int, computing in 32 bits and widening.
            FIX: (abits'(k) + abits'd1) * abits'd<stride>.
            Site: pacino_tests.svh.
```

All three are the same mistake in three places: arithmetic done at a
literal 32 and widened afterwards, instead of done at the address
width. None of them could produce a wrong answer at pa_bits 32,
which is why the tree was green with them in it.

A FOURTH, NOT FIXED AND REPORTED INSTEAD. `key_of` in both
rtl_tb.cpp and rtl_mem.cpp emits `longint'({32'd0, a})`. At AddrBits
36 that is a 68-bit concatenation truncated to 64 by the cast. It is
VALUE-CORRECT for any AddrBits up to 64, because the truncation
removes only leading zeros, and Verilator does not warn on it. It is
the same hardcoded 32 as the other three and is left alone because
changing it changes no emitted behaviour.

### PART 2 AND PART 3 -- THE DOCUMENT

`planning/interfaces/l1i_ifu_interfaces.md`, new, 1047 lines.
Follows the ftq_ifu_interfaces.md conventions: SPDX block, FILE
block, scope section naming companion documents, direction-based
naming with no stage suffix and the reason for it, numbered
sections, departures and open items stated, document history.

REGISTRY. IF-1 through IF-37, IF-U1 through IF-U5, TD-IF-1 through
TD-IF-5. IC-, L1I-, FE-, TD-FE- and FE-U are not used.

The interface, in one page:

```
  REQUEST    ifu_l1i_req_val / _rdy / _id[3:0] / _paddr[35:0]
             Physical, byte, line aligned. Four wires, two buses,
             no rw strobe and no write data: the L1I is read only.

  RESPONSE   l1i_ifu_rsp_val / _id[3:0] / _data[511:0] / _err
             NO READY. The identifier free list is the flow
             control and a second one could disagree with it.
             Out of order permitted; one per cycle; never in the
             cycle its request was accepted.

  LIMIT      Sixteen identifiers, allocated by the IFU. A
             seventeenth request cannot be PRESENTED, so the L1I
             has an assertion and no counter and no recovery.

  MISS       Not visible. Latency only. A performance strobe is
             named as permitted and explicitly outside the
             protocol so adding it later is not a protocol change.

  MERGING    Not visible. N requests on one line get N responses,
             each with its own identifier, over N cycles. A fifth
             target is REFUSED by ready, not rejected and not
             queued and not given a second MSHR.

  FAULT      No port, in either direction. A faulting request never
             reaches the L1I, so section 8 specifies an absence and
             then says what the IFU does instead. rsp_err is the
             memory side only and is a different fault class.

  INVALIDATE ifu_l1i_inv_val / _rdy / _all / _paddr, and
             l1i_ifu_inv_done. Fetch does NOT proceed while one is
             in flight. inv_all drains everything then clears;
             inv_line drains only a matching MSHR, reusing the
             merge comparison.

  UPSTREAM   cmt_ifu_maint_val / _rdy / _op / _paddr and
             ifu_cmt_maint_ack, from the BACKEND COMMIT STAGE. The
             acknowledgement is required or FENCE.I has no
             completion semantics.
```

## Test Case Results

Omitted by the task: no RTL test cases are added. The counts that
exist are these, all from runs in this session.

```
  cachegen unit suite, before   86 tests   86 passed   0 failed
  cachegen unit suite, after    87 tests   87 passed   0 failed

  emitted tree, per node, lint and run, after regeneration:
    ifu     lint 0 warnings   run  3 passed  0 failed
    lsu     lint 0 warnings   run  3 passed  0 failed
    l1i     lint 0 warnings   run 14 passed  0 failed
    l1d     lint 0 warnings   run 15 passed  0 failed
    l2      lint 0 warnings   run 15 passed  0 failed
    mem     lint 0 warnings   run  4 passed  0 failed
    pacino  lint 0 warnings   run 22 passed  0 failed

  cgen --cmd=check on the pacino configuration:
    0 diagnostics, 0 errors, pa_bits 36
```

The riscv-codesign bpu and ftq suites were NOT run, as the
constraints require. No RTL under rtl/ was touched.

## Assumptions made not explicit in the prompt

```
  A-1  "AN EDGE WHOSE ENDPOINTS ARE CACHE OR MEMORY NODES" IS READ
       AS AT LEAST ONE ENDPOINT, NOT BOTH. Taken because requiring
       both would exclude the ifu_l1i edge -- ifu is an agent -- and
       that is the exact edge INFRA-012's note n1 names as the one
       that zero-extends silently. The generated address type is
       pa_bits wide inside the cache or memory node, so one such
       endpoint is enough to make the disagreement a defect. An
       agent-to-agent edge is left alone; it carries no pa_bits
       wide type.

  A-2  READING OUTSIDE THE MANIFEST FOR THE PRIVILEGED
       SPECIFICATION. Problem 6 requires checking menvcfg.CBIE
       against the privileged specification, which is in neither the
       Context Loaded manifest nor the directories the Context
       Comments open. tools/spike, the reference implementation
       carried in this tree, was read for it, plus
       tools/cachegen/tools/jnutils/ncurses/rva23.md for the
       profile mandates. Both reads are cited in the document at
       the line level. No file outside the waiver was written.

  A-3  rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv WAS READ, not
       written, to establish that no physical address width exists
       on the IFU side. That is TD-IF-1 and it cannot be stated
       without checking.

  A-4  THE EMITTER FIXES ARE IN SCOPE. "PART 1 IS ONE COMMIT" and
       Problem 3's "regenerate and report what moved" together mean
       the tree must still build after the change. Three emitter
       width defects blocked that. They were fixed. The 512-bit
       core port defect was NOT fixed, because it belongs to the
       interface of Part 2 and the constraints put emitter work for
       that interface out of scope.

  A-5  THE COMMIT STAGE IS THE UPSTREAM MAINTENANCE PRODUCER. No
       document names one. Commit rather than execute is argued in
       section 11.1 of the new document from FENCE.I's completion
       semantics, and five further assumptions about the producer
       are listed as A1 through A5 in section 12 of that document,
       each marked unverifiable.
```

## Decisions made not explicit in the prompt

```
  D-1  T-10 REPORTS ONCE PER LINK, NOT ONCE PER EDGE. The width is
       one JSON value, so one edit clears it. Rejected: per edge,
       which is what T-3 and T-4 do, but would report pe_port
       twice. The T-5 cycle rule already deduplicates.

  D-2  T-10 IS PLACED AFTER port_roles AND BEFORE graph IN run().
       It reads only resolved edges and the symbol table, so
       ordering is free; this keeps the link-related rules
       together.

  D-3  THE T-10 SITE IS THE LINK'S WIDTH FIELD, NOT THE EDGE. That
       is where the fix goes.

  D-4  THE CORE INTERFACE CARRIES A FULL BYTE ADDRESS, PA[35:0],
       WITH ALIGNMENT AS A CHECKABLE RULE. Rejected: PA[35:6], 30
       bits, which the schema can express as address_granularity
       "line". Reasons in section 4.2 of the document, the decisive
       one being that a rule a testbench can check is worth more
       than six constant-zero wires.

  D-5  THE RESPONSE HAS NO READY. The identifier free list is the
       flow control. A second flow control could disagree with it
       and would need a holding register that can deadlock against
       a retiring MSHR.

  D-6  A MISS IS NOT VISIBLE. Rejected: an rsp_hit bit. It would
       arrive after the request was issued and the identifier
       allocated, so there is nothing left to do with it.

  D-7  A FIFTH MSHR TARGET IS REFUSED BY ready, NOT REJECTED ON A
       CHANNEL. A reject forces the IFU to re-present and reorders
       the fetch stream against the FTQ entry order. The cost of
       refusing -- one ready wire blocks unrelated requests too --
       is stated plainly in the document rather than hidden.

  D-8  INVALIDATE DRAINS. inv_all drains every outstanding request;
       inv_line drains only a matching MSHR. The asymmetry is
       deliberate: a range invalidation loop would otherwise drain
       sixteen requests per line, and the line comparison reuses
       the merge comparison rather than adding one.

  D-9  MAINTENANCE IS ONE PORT GROUP WITH AN OP BIT, NOT TWO
       GROUPS. Only one operation is in flight, so two groups would
       be two ways to drive one piece of hardware.

  D-10 THE PRODUCER BOUNDARY IS COMMIT, NOT EXECUTE, AND THE
       ACKNOWLEDGEMENT IS REQUIRED. Argued from completion
       semantics, not from speculation safety, because an empty
       instruction cache is always a legal instruction cache.

  D-11 cbo.inval ROUTING TO THE I-SIDE IS RECOMMENDED AND NOT
       TAKEN. It decides whether a whole port group is live or
       dead, which is Jeff's. IF-U3.

  D-12 THE ready IMPLEMENTATION AND THE invalidate_line LATENCY ARE
       LEFT TO JEFF, as IF-U1 and IF-U4. Both are frequency or area
       figures of the same kind as L1I-5's two cycles.
```

## RVA23 compliance risks and gaps noticed

```
  R-1  Zicbom IS MANDATORY IN RVA23U64 AND HAS NO HARDWARE. Checked
       against the RVA23U64 mandatory string in
       tools/cachegen/tools/jnutils/ncurses/rva23.md. TD-L1I-8
       already records this; TOOLS-003 confirms it at the emitter:
       no generated node emits an invalidate port of any kind, and
       section 14.2 S8 of the new document adds that the SCHEMA has
       nowhere to describe one either. The gap is therefore two
       layers deep, not one.

  R-2  Zifencei IS MANDATORY IN RVA23S64, WHICH PACINO IS. Same
       source; Zifencei is in the RVA23S64 additions, not in the
       RVA23U64 mandatory list. Pacino implements Sv39 and
       supervisor mode, so it is bound by RVA23S64 and FENCE.I is
       mandatory. Same hardware gap as R-1.

  R-3  FENCE.I HAS NO COMPLETION PATH SPECIFIED ANYWHERE ELSE. The
       new document's IF-35 supplies one and marks it against an
       unverifiable assumption, A1: that the commit stage can hold
       the post-fence restart until the acknowledgement. If it
       cannot, the fence is not architecturally complete when the
       instruction retires. This is the RVA23 risk with the least
       cover behind it, because there is no backend document at all.

  R-4  cbo.inval's I-SIDE BEHAVIOUR IS AN IMPLEMENTATION CHOICE AND
       PACINO HAS NOT MADE IT. Section 13.2 shows the architecture
       does not fix it. Not making it is legal; leaving it
       unrecorded is what IF-U3 prevents.

  R-5  NO C-EXTENSION CONSEQUENCE ON THIS INTERFACE. IF-5 makes
       every request line aligned and 4.3 R3 puts the block extract
       in the IFU, so no 2-byte boundary is visible here. Recorded
       because the absence is worth stating.
```

## Deferred Work

```
  DEF-1  THE 512-BIT CORE PORT. Confirmed broken by experiment,
         deliberately not fixed. The fix is INFRA-012's E1 plus a
         second site this session found: the emitted testbench
         driver task sizes its write path from write_width_bits and
         its data argument from the read width, so an asymmetric
         link breaks the testbench as well as the package. Both
         sites are named in section 14.3 of the new document.

  DEF-2  THE THREE NEW SCHEMA GAPS. TD-IF-2, no error return on a
         custom link; TD-IF-3, no response-side handshake; TD-IF-4,
         nowhere to describe a maintenance port. None is in
         INFRA-012's list; all three were found by writing the port
         list down.

  DEF-3  TD-IF-1, THE MISSING PARAMETERS. bp_defines_pkg.sv has no
         physical address width. The 36 lives only in the cachegen
         topology file, and the generated l1i_pkg names its
         constants under a different convention. The same file sets
         VA_WIDTH to 40 against the topology's va_bits 39, which is
         the identical class of defect T-10 just closed for pa_bits,
         on the other address, and nothing checks it.

  DEF-4  TD-IF-5. The predecode writeback is one per fetch block and
         the line responses that feed it may return out of order, so
         the IFU reorders between its two boundaries and nothing
         bounds the buffer that implies. Belongs to ifu_decisions.md.

  DEF-5  THE l1i GEOMETRY. INFRA-012's G1 through G4 -- 64 KiB, 2
         banks, PIPT, 16 MSHRs, a second core link type -- are still
         unapplied. TOOLS-003 changed pa_bits only. The 23-bit tag
         icache_decisions.md 1.2 names arrives with G1, not with
         this task.

  DEF-6  TD-L1I-2 IS PARTLY RESOLVED, NOT CLOSED. Section 13 of the
         new document settles what the architecture does say and
         shows that it does not say the part TD-L1I-2 is actually
         asking. What remains is IF-U3, a pacino decision.
```

## Other Notes

DEFECTS FOUND IN icache_decisions.md. Six, reported here and in
section 15 of the new document, not worked around. Two are
correctness and four are accuracy.

```
  D1  CORRECTNESS. Section 7 M1 says FENCE.I is "implemented by the
      reset-branch clear of the flop valid bits, so it is a
      single-cycle operation". The CLEAR is single cycle. THE
      OPERATION IS NOT. L1I-10 allows sixteen outstanding requests,
      and a fill in flight when the clear happens lands in the array
      afterwards and re-validates a line the fence was supposed to
      remove. FENCE.I is drain then clear.

  D2  CORRECTNESS. L1I-14 and L1I-18 do not meet. L1I-14 puts a
      64-byte line in the IFU; L1I-18 puts the only invalidate path
      through the IFU. Neither says the IFU's buffer is part of what
      an invalidate clears. A fence that clears the array and not
      the buffer leaves a stale instruction line behind -- which is
      the same correctness failure section 2.2 invokes to reject
      VIPT, arriving by a different route.

  D3  Section 9's core link table, row address_width_bits, reads 32
      with note n1. It is 36 now, the disagreement is an error now,
      and TD-L1I-6 should close.

  D4  8.1 P2 is not enforceable by its own owner. L1I-19 puts the
      prefetch requester at the IFU; P2 says a prefetch never
      occupies an MSHR a demand miss requires. The IFU cannot see
      the MSHR file. Either the core interface distinguishes a
      prefetch from a demand request, which is a port the new
      document deliberately does not have, or P2 is restated as
      something the IFU can act on. P1 and P3 are fine.

  D5  1.2 states the tag conditionally -- "THE TAG WIDTH IS NOT
      FIXED because pa_bits is not decided" -- and the condition is
      resolved. L1I-U1 should close. Separately, the 23 it names is
      the tag at the L1I-1 geometry, and the configured geometry is
      still 32 KiB 1 bank, so cgen emits 24. The amendment should
      say which geometry the number belongs to.

  D6  0.1 lists three interfaces and the maintenance path is not one
      of them. Section 10 of the new document is a fourth: same peer
      as `core`, different port group, different handshake,
      different flow control. Either 0.1 gains a row or its `core`
      row says it carries two independent groups.
```

WHAT INFRA-012 GOT RIGHT AND WHAT IT DID NOT COVER. Every claim of
INFRA-012's that this task could test was confirmed: the three field
paths, the zero-extend at l1i_core_slv, the truncation at
l1i_mem_mst, the two named tests, E1's WordIdxBits collapse, E2's
unconsumed outstanding_requests. It did not cover the three emitter
width defects, because pa_bits had never moved and they cannot fire
at 32; and it did not cover the three schema gaps of DEF-2, because
those only appear once the port list is written down.

THE OUTPUT TREE IS GITIGNORED in the cachegen submodule
(.gitignore:21), so the 40 regenerated files are not listed under
Files Modified. They are reproducible from the configuration with
one command and were verified byte-identical to a fresh emit before
the change was made.

## Files Modified
- planning/interfaces/l1i_ifu_interfaces.md
- prompts/TOOLS-003.md
- tools/cachegen/testcases/pacino/pacino_topology.json
- tools/cachegen/testcases/pacino/pacino_links.json
- tools/cachegen/cli/inc/diag_codes.h
- tools/cachegen/cli/inc/checker.h
- tools/cachegen/cli/src/checker.cpp
- tools/cachegen/cli/src/rtl_cache.cpp
- tools/cachegen/cli/src/rtl_tb.cpp
- tools/cachegen/cli/tb/test_negative.cpp
- tools/cachegen/cli/tb/test_geometry.cpp
- tools/cachegen/cli/tb/test_bank.cpp
- tools/cachegen/cli/tb/test_pacino.cpp
- tools/cachegen/cli/tb/fixtures/neg_link_addr_width/system.json
- tools/cachegen/cli/tb/fixtures/neg_link_addr_width/links.json

:: RESULTS:END ::

:: CONTEXT:START ::

# Context Usage

Context used: 26 percent

## Totals

| Field  | Value              |
|--------|--------------------|
| Model  | claude-opus-5[1m]  |
| Used   | 257.7k tokens      |
| Window | 1m tokens          |
| Used % | 26%                |
| Free   | 742.3k tokens      |
| Free % | 74.2%              |

## By category

| Category                | Tokens | Percent |
|-------------------------|--------|---------|
| System prompt           | 4.0k   | 0.4%    |
| System tools            | 20.3k  | 2.0%    |
| System tools, deferred  | 17.3k  | 1.7%    |
| MCP tools, deferred     | 1.5k   | 0.1%    |
| Memory files            | 4.9k   | 0.5%    |
| Skills                  | 2.9k   | 0.3%    |
| Messages                | 225.6k | 22.6%   |
| Free space              | 742.3k | 74.2%   |

## MCP tools

| Tool                                            | Tokens |
|-------------------------------------------------|--------|
| mcp__claude_ai_Gmail__authenticate              | 203    |
| mcp__claude_ai_Gmail__complete_authentication   | 268    |
| mcp__claude_ai_Google_Calendar__authenticate    | 213    |
| mcp__claude_ai_Google_Calendar__complete_auth   | 281    |
| mcp__claude_ai_Google_Drive__authenticate       | 209    |
| mcp__claude_ai_Google_Drive__complete_auth      | 277    |

## Skills

| Skill                    | Source   | Tokens |
|--------------------------|----------|--------|
| cntx                     | Project  | 30     |
| run                      | Project  | 20     |
| dataviz                  | Built-in | 480    |
| claude-api               | Built-in | 360    |
| design                   | Built-in | 340    |
| code-review              | Built-in | 270    |
| update-config            | Built-in | 240    |
| artifact-capabilities    | Built-in | 210    |
| claude-in-chrome         | Built-in | 180    |
| schedule                 | Built-in | 130    |
| loop                     | Built-in | 120    |
| workflow-authoring       | Built-in | 80     |
| keybindings-help         | Built-in | 80     |
| artifact-diagramming     | Built-in | 70     |
| artifact-design          | Built-in | 70     |
| fewer-permission-prompts | Built-in | 60     |
| simplify                 | Built-in | 60     |
| security-review          | Built-in | 30     |
| init                     | Built-in | 20     |
:: CONTEXT:END ::

