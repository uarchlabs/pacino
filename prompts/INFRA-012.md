<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | INFRA-012               |                          |
| Date         | 2026.08.28              |                          |
| Module       | tools/cachegen          | assessment, no changes   |
| Run time     | 14m.49s                 |                          |
| Ctx %        | 23%                     |                          |
| Model        | claude-opus-5[1m] default | effort not reported    |
| Resume sha   | ac111839-cea6-4860-a0d0-eeabd3cd2337 |             |
| PA session   | 068                     |                          |

Task:   [X] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Mode:   [X] automated   [ ] manual          [ ] interactive
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview

CAN CACHEGEN REPRESENT THE L1 INSTRUCTION CACHE THAT PACINO NEEDS?

planning/arch/icache_decisions.md is the target. This task assesses
cachegen against it and PROPOSES the changes required, split across
the C++ in cli/, the configuration in testcases/pacino, and the
schema in planning/schema.

No file is changed. The deliverable is the assessment and the
proposal, written into Results Capture.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion

## Claude.code Console Output

  Problem 1 — the answer

  No. Cachegen can emit the geometry of the L1I in icache_decisions.md sections
  1-9, and nothing else the document decides.

  The gap is not the field list. 13 of the 22 fields in section 9's first table 
  are accepted, carried, and reach no emitted logic. The tool's own
  unconsumed.log names 12 of them for l1i; the thirteenth, mshrs, is read once —
  rtl_cache.cpp:1046 — where it is written into a comment saying the control
  does not use it. Seven fields shape RTL. One (indexing) shapes only a
  diagnostic. One (prefetch_arbitration) does not exist.

  Split: 4 configuration items (free, land today), 5 schema items, 8 C++ items.

  Findings worth your attention

  - Section 1.2's arithmetic is correct, and matches geometry.cpp exactly — bank
    select at PA[6], setidx PA[12:7], 64 sets per bank. The check the prompt
    aimed at that section comes back clean.
  - C3 costs nothing. A link cannot be parameterised per edge (schema and
    resolver both forbid it), but nothing binds a port type to one link — so a
    second link type is two JSON edits and no tool change. That was the item I
    expected to be expensive.
  - A 512-bit core port breaks the emitter. WordsPerLine becomes 1, WordIdxBits
    becomes 0, and rtl_pkg.cpp:373-381 emits logic [-1:0]. Derived from source,
    not run — the constraints forbid running cgen.
  - inclusion is inert on every node. TD-L1I-1's disagreement between l1i's nine
    and l2's inclusive changes no emitted bit today; both declarations are dead
    text.
  - Zicbom is unbuildable. All four maintenance fields are inert and no
    generated node emits an invalidate port. RVA23 mandates it.

  Document errors (Problem 6)

  L1I-11 is cited three times and never stated · bank_interleave should be
  bank_interleave_granularity · non_inclusive should be nine, and that row's
  "Changed: yes" is wrong since the value is already set · address_width_bits: 
  pa_bits has no symbolic form in the input language · L1I-9 contradicts 5.2 — a
  whole-line core response cannot bank the beat that critical-first is
  justified by. That last one is a decision, and it also touches L1I-14.

  misc/example_pacino_icache.json is a superseded single-file schema (1.0.0,
  tool 0.1.0-draft) the current tool cannot read. It answers nothing.

  Build and suite (Problem 7)

  All three build submodules were uninitialized; I checked them out, which the
  build required. Clean build, exit 0, one -Wunused-parameter warning at
  rtl_tb.cpp:400. 86 tests, 14 suites, 86 passed, 0 failed, 2861 ms. The output/
  tree is untouched — verified by timestamp — and cgen itself was not run. The
  suite never invokes Verilator, which is the line between what the C++ suite
  can prove (all config and schema items, plus E1) and what needs a simulation
  (E2-E8).

  Two existing tests hardcode the present geometry and break on the config
  change: GeometryPacino.L1iDerivation and Pacino.ViptIndexBudgetIsMet.


## My Assessment

cachegen needs to support non-blocking cache behavior intrinsically

## Claude.ai Assessment

What it actually found

Cachegen is a finished geometry stage in front of a blocking-cache emitter. Thirteen of twenty-two fields validate, get carried into the package, and move no RTL. Seven shape hardware. That is not "some fields are missing" — it is that the configuration language describes a cache the emitter does not build, and the tool says so itself in unconsumed.log and, more precisely, in features.log's third state: read, but shapes only emitted text. mshrs reaching a comment that says the control doesn't use it is the whole finding in one line.

The consequence for planning: icache_decisions.md sections 5 through 8 are specifications for hardware cachegen cannot currently emit at all, and no amount of configuration reaches them.

C3 was the item I expected to be expensive and it costs nothing. A link can't be parameterised per edge, but nothing binds a port type to one link, so a second link type is two JSON edits. I'd flagged that as needing a ruling; it doesn't.

Zicbom is the hard one. No node emits an invalidate port of any kind, all four maintenance fields inert. RVA23 mandates it, so this is external and not a preference. E7 should probably sit higher than the IA's ordering puts it.

My errors

Five are mechanical and I'll fix them: the missing L1I-11, bank_interleave_granularity, nine rather than non_inclusive with its wrong Changed mark, pa_bits as a symbolic value the input language doesn't have, and write_width_bits: 0 stated as if available.

6f is a real contradiction and it's mine. L1I-9 says the core port returns a whole 512-bit line; 5.2 justifies critical-first by the requested 32 bytes being forwarded as it arrives. Both cannot hold. I changed L1I-9 when you ruled "the interface returns a cache line" and left 5.2 carrying the earlier block-at-a-time reasoning.

There's a resolution that keeps both halves. One line per request, delivered as two 256-bit beats, critical beat first, as one logical response — which is how TileLink's D channel already works. The IFU assembles; L1I-14 is unchanged. 256 bits per cycle is 32 bytes, exactly one fetch block per cycle, which is what Kunminghu and Zen 5 per-pipe do. The 512-bit port was over-provisioned for a front end that produces one prediction block per cycle.

That resolution also dissolves E1. The logic [-1:0] break comes from WordsPerLine collapsing to 1 at a 512-bit core port. At 256 bits it's 2, WordIdxBits is 1, and nothing breaks. One C++ item disappears and G4's link body changes.

I'd want your ruling on that rather than applying it — it's a port width, not a typo.

Next task

The IA's ordering is right and item 1 is free: G1 through G4 in one change, with the two hardcoded tests edited in the same commit. That's configuration only, and it gets the geometry and link shape correct before any emitter work. If you take the 6f resolution, G4's link body changes before that task is written.

E2+E3+E4 as one task is the correct call — eight outstanding requests with in-order return and no miss tracking is the blocking cache with extra wires.

One thing worth folding into prereqs.sh or setup.sh: three build submodules were uninitialized and the IA had to check them out before make all would run.

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
INFRA-012

## Context Loaded
@planning/arch/icache_decisions.md
@tools/cachegen/CLAUDE.md
@tools/cachegen/planning/arch/cgen_decisions.md
@tools/cachegen/planning/schema/caches.schema.json
@tools/cachegen/planning/schema/links.schema.json
@tools/cachegen/planning/schema/system.schema.json
@tools/cachegen/planning/schema/ports.schema.json
@tools/cachegen/planning/schema/topology.schema.json
@tools/cachegen/misc/example_pacino_icache.json
@tools/cachegen/misc/example_pacino_icache.elaborated.json
@tools/cachegen/testcases/pacino/pacino_caches.json
@tools/cachegen/testcases/pacino/pacino_links.json
@tools/cachegen/testcases/pacino/pacino_ports.json
@tools/cachegen/testcases/pacino/pacino_system.json
@tools/cachegen/testcases/pacino/pacino_topology.json
@tools/cachegen/output/logs/geometry.log
@tools/cachegen/output/logs/features.log
@tools/cachegen/output/logs/unconsumed.log
@tools/cachegen/output/l1i/rtl/l1i_pkg.sv

## Context Comments

READING UNDER THESE DIRECTORIES IS PERMITTED and is expected:

```
  tools/cachegen/cli/inc/       headers
  tools/cachegen/cli/src/       the tool itself
  tools/cachegen/cli/tb/        the unit suite and its fixtures
  tools/cachegen/output/l1i/    the emitted l1i node
  tools/cachegen/output/pacino/ the system top and link packages
```

The manifest names files whose content is the subject of a specific
problem. The directories above are the tool's source and must be
read to answer any of them; naming every file ahead of a first
reading would be inference. Directory listing anywhere under
tools/cachegen is permitted.

DO NOT READ tools/cachegen/examples/. It is a hand-written cache
model predating cachegen, not the tool, and reading it produces
findings about a design this task is not about.

ONLY THE CLI MATTERS. No functional-model feature is developed and
none is in scope.

THE TOOL IS C++, with nlohmann JSON and a googletest suite under
cli/tb. The emitters are C++, not templates.

THE output/ TREE IS A COPY, checked in for this work. It records
one run of one configuration and is evidence of what the tool DID
emit. It is not a workspace.

DO NOT ANSWER FROM tools/cachegen/docs/pacino_cache.md. It is
generated, its own header calls it incomplete or likely incorrect,
and it is deliberately not in the manifest. Read the source, the
schema, the JSON and the emitted tree.

## Hypothesis

Cachegen as it stands cannot represent the L1 instruction cache
icache_decisions.md specifies. The gap is a bounded set of changes
across three places -- the C++, the pacino configuration, and the
schema -- and which of the three a given gap falls in is itself a
finding.

Some of the gap is expected to be VOCABULARY rather than values:
the tool may have no concept of a read-only cache, no way to
express inclusion as a property of a pair, no way to let two edges
of one link differ. Those do not appear as a field holding a wrong
value and will not be found by checking values alone.

A finding that a capability already exists is as valuable as a
finding that it is missing.

## Background

Pacino is an 8-issue RVA23 out-of-order processor. Its branch
prediction unit and fetch target queue are built and verified; its
instruction fetch unit is unbuilt. The cachegen-generated l1i node
is intended to become that machine's L1 instruction cache.

icache_decisions.md is the specification. Sections 1 through 9 are
decided; section 10 records what is open.

The l1i node as configured today is 32 KiB, 8-way, VIPT, 4 MSHRs,
with a 32-bit core port carrying one outstanding request. Every one
of those differs from the target, and the core port in particular
was a test-agent port rather than a fetch port.

TWO FACTS READ FROM A DIRECTORY LISTING AND NOT FROM A FILE. Check
them; do not build on them:

- cli/tb/fixtures holds neg_vipt_alias, neg_tag_bits,
  neg_banks_not_divide, neg_sets_not_pow2, neg_sets_not_integer and
  neg_capacity_not_pow2, which suggests the checker already
  enforces geometry rules. If so, several problems below return no
  change needed.
- misc/example_pacino_icache.json and its elaborated form exist and
  may already be an instruction-cache configuration written for
  this purpose. READ IT FIRST; it may answer much of Problem 3.

## Binding Previous Decisions

1. icache_decisions.md IS THE TARGET. It is the specification
   cachegen is assessed against, and its values are not this task's
   to evaluate or improve.

   IT MAY STILL BE WRONG. Problem 6 is where that is reported. What
   is not wanted is silent substitution: adopting a different value
   because the tool prefers it, or because it seemed more sensible,
   without saying so.

2. SECTIONS 1 THROUGH 9 ARE THE REQUIREMENT. Section 10's open
   items -- pa_bits, the ITLB, the walker topology, PMP and PMA --
   are NOT requirements. Problem 5 assesses them separately and
   asks only whether the tool's model could express them at all. Do
   not treat an open item as something the tool must support today.

3. THIS TASK CHANGES NOTHING. It proposes. See Constraints.

4. THE PROPOSAL IS WANTED, not withheld. Where a change is needed,
   say what it should be, name the alternatives if there are real
   ones, and recommend. An assessment that stops at "this is
   missing" leaves the next task to redo the thinking.

## Specific Requirements

Problems, not procedure. Method, ordering and decomposition are
yours.

PROBLEM 1 -- THE ANSWER.

Can cachegen, as it stands, emit the L1 instruction cache of
icache_decisions.md sections 1 through 9?

Answer yes or no, and bound it. If no, the enumeration of what
prevents it IS the answer, and every subsequent problem is
supporting evidence for a line in that enumeration.

State it first, before the detail. A reader who stops after this
problem should know how large the work is.

PROBLEM 2 -- CAPABILITY, NOT FIELDS.

Some of the target is not a value in an existing field but a
concept the tool may not have. For each of the following, report
whether cachegen can express it, how, and if not what is missing.

```
  C1  A READ-ONLY CACHE. The L1I has no write port, no dirty
      state, no write-back and no flush. Does the node model have
      a notion of read-only, or does every cache carry the write
      machinery whether the configuration uses it or not? What
      does the emitter produce today for a node whose policy block
      declares no write behaviour?

  C2  INCLUSION AS A PROPERTY OF A PAIR. l1i declares nine and l2
      declares inclusive; those describe one relationship and are
      free to disagree. icache_decisions.md L1I-15 makes the L1I
      non-inclusive with the L2 while leaving the L1D relationship
      alone, so the l2 node needs a per-upstream-interface answer.
      Can the model express that? If inclusion is per-node, what
      would make it per-edge or per-interface?

  C3  ONE LINK, TWO DIFFERENT EDGES. pe_port is declared once and
      used on both ifu-to-l1i and lsu-to-l1d. The I-side edge now
      needs 512 bits, eight outstanding and no write channel; the
      D-side is unchanged. Can a link be parameterised per edge,
      or must a second link type be declared? Report what the
      schema and the resolver support, and recommend which way to
      go.

  C4  OUT-OF-ORDER RESPONSE. Eight outstanding requests are
      pointless if responses must return in order, because one
      miss then blocks every hit behind it. The current pe_port
      declares outstanding_requests 1 and appears to carry no
      response-ordering field at all. What would carry a request
      identifier and an out-of-order return, and does anything in
      link_sig or the adapter emitters assume in-order today?

  C5  PREFETCH POLICY. icache_decisions.md 8.1 states three rules
      -- demand first, never starve a demand miss of an MSHR, a
      dropped prefetch is not retried -- and asks for them to be a
      named parameter rather than prose. Does any notion of
      prefetch exist in the tool? TlAIntent is in the shared
      opcode package; is anything emitted that uses it?

  C6  MSHRs AT ALL. The configuration carries an mshrs count. Does
      the emitted control implement miss-status holding registers,
      or is the count carried and unconsumed? unconsumed.log is
      evidence. A count no emitter reads is a different finding
      from a count that is wrong.
```

C6 GENERALISES. If any other field of the target is carried but
unconsumed, report it here. A parameter that reaches no emitted RTL
is worse than an absent one, because the configuration claims a
capability the design does not have.

PROBLEM 3 -- THE FIELD MAPPING.

For every field in icache_decisions.md section 9, both tables,
report one of:

```
  ACCEPTS   the field exists and takes the target value
  REJECTS   the field exists and refuses it. Give the constraint,
            and the file and line enforcing it
  ABSENT    no such field. Name the schema object it belongs in
```

This is evidence for Problem 1, not the deliverable. Keep it a
table.

PROBLEM 4 -- THE PROPOSAL, SPLIT THREE WAYS.

For everything Problems 2 and 3 found missing, say what to change,
and put each change in exactly one of:

```
  C++            cli/src and cli/inc. Name the file and what it
                 does today
  CONFIGURATION  tools/cachegen/testcases/pacino. A value change
                 only, needing no tool change
  SCHEMA         tools/cachegen/planning/schema. A new field, a
                 widened enumeration, a relaxed constraint
```

THE SPLIT IS THE POINT. A change that is purely configuration costs
nothing and can happen immediately. A schema change plus an emitter
change plus a checker rule is a task. Sizing the follow-on work
depends entirely on which bucket each item lands in, and an item
spanning two buckets must say which part is which.

Where a change has real alternatives, give them and recommend one.
Where it does not, say so rather than inventing a choice.

Order the result by what unblocks the most.

PROBLEM 5 -- WHAT THE MODEL CANNOT HOLD.

icache_decisions.md section 10 records four open items. None is a
requirement today. The question is whether cachegen's model could
express them at all, because a decision the tool structurally
cannot represent is worth knowing about before it is taken.

```
  pa_bits at 36    L1I-U1. Can it be set today? Does anything
                   assume 32 other than by reading pa_bits -- a
                   hardcoded width, a 32-bit literal, an address
                   type sized independently? A value parameterised
                   in one place and assumed in five is the finding
  an ITLB          L1I-U2. A TLB has no cache geometry: no line
                   size, no sets in the cache sense, fully
                   associative, mixed page sizes. Is it a node
                   type the model could carry, or is the node
                   model cache-shaped throughout?
  a walker node    L1I-U3. A shared L2 TLB containing a page table
                   walker, with a TileLink master edge into l2
                   alongside up_i and up_d. That is a third
                   upstream interface on an existing node plus a
                   new node in the graph. Does the topology model
                   allow it?
  PMP and PMA      L1I-U4. Physical address checks in the
                   translation path. Anything in the model for
                   them?
```

Assessment only. Do not propose an implementation for these.

PROBLEM 6 -- WHERE THE TARGET IS WRONG.

icache_decisions.md was written by the PA against a generated
summary of cachegen's output rather than against the tool, so it is
expected to contain errors.

Report anything in it that is wrong, unbuildable, or internally
inconsistent. Specifically:

- a derived value that does not follow from its own inputs.
  Section 1.2 states 128 sets, offset PA[5:0], index PA[12:6],
  bank PA[6], set index PA[12:7]. Check the arithmetic against the
  tool's own geometry computation
- a field name in section 9 that does not match the schema's name
  for the same thing
- a requirement contradicting another requirement in the document
- a claim about cachegen that is false

Report. Do not correct the document; it is a planning file.

PROBLEM 7 -- WHAT PROVES A CHANGE.

The tool has a googletest suite under cli/tb. Report how it is
built and run, how many tests exist, and the pass and fail counts
from a clean build in this session.

Then, for each item in the Problem 4 proposal, name what in cli/tb
would prove it BEFORE any RTL is generated -- the test file, and
where a new fixture is needed, the fixture pattern it follows.

A change provable in the C++ suite is a different task from one
provable only by generating and simulating. Say which each is.

## Constraints

- NO FILE IS MODIFIED, CREATED OR DELETED, in either repository,
  except this task file's Results Capture section. That includes
  the cachegen source, the schema, the pacino JSON, the fixtures
  and the emitted output/ tree.
- BUILDING IS PERMITTED and Problem 7 requires it. Building cli/
  and running its unit suite are expected; build artifacts are the
  consequence, not a violation. Report where they land.
- DO NOT RUN cachegen ITSELF. Regenerating overwrites the copied
  output/ tree, which is evidence.
- Both repositories' planning/ directories are read-only. The
  cachegen schema lives under planning/schema and is READ here.
- PROPOSE, do not implement. Problem 4 wants each change described
  well enough to write a task from. It does not want the change.
- The riscv-codesign bpu and ftq suites are not in scope and must
  not be run. No RTL in this repository is touched.

## Deliverables

- Results Capture filled in below, in this file:
  prompts/INFRA-012.md

No other deliverable. No file is created or modified.

Fill in every section. Test Matrix is omitted: this task adds no
test cases. Problem 1's answer goes at the top of Summary. Report
Problem 3 as a table and Problem 4 grouped by its three buckets.

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary

PROBLEM 1 -- THE ANSWER. NO.

Cachegen cannot emit the L1 instruction cache of icache_decisions.md
sections 1 through 9. It can emit the GEOMETRY, and nothing else the
document decides.

The size of the gap is not in the field list. It is that 13 of the 22
fields in section 9's first table are ACCEPTED, CARRIED, and reach no
emitted logic. The tool's own unconsumed.log names 12 of them for node
l1i; the thirteenth, `mshrs`, is read once, at rtl_cache.cpp:1046,
where it is written into a comment that says the control does not use
it. Seven fields shape RTL: capacity_bytes, line_bytes, associativity,
banks, bank_interleave_granularity, read_miss, replacement. One,
`indexing`, shapes a diagnostic and nothing else. One,
`prefetch_arbitration`, does not exist.

WHAT PREVENTS IT, enumerated. Each line is a finding; Problems 2
through 5 are its evidence.

CONFIGURATION, no tool change, four items:

```
  G1  capacity_bytes 32768 -> 65536, banks 1 -> 2, and
      bank_interleave_granularity "line" added
  G2  indexing VIPT -> PIPT
  G3  mshrs 4 -> 16, mshr_targets 2 -> 4
  G4  a second link type for the I-side core edge, so pe_port stops
      being shared with the L1D edge
```

SCHEMA, five items:

```
  S1  prefetch_arbitration does not exist anywhere
  S2  custom.write_width_bits has minimum 8 and is required, so a
      read-only link cannot declare 0
  S3  out_of_order_response has no field. The CAPABILITY exists under
      another name and is unused
  S4  inclusion is a property of a node, not of an edge or an
      interface
  S5  a link's address width and the system's pa_bits are two
      independent integers and nothing checks that they agree
```

C++, eight items, in cli/src:

```
  E1  a 512-bit core port breaks the emitted package. WordsPerLine
      becomes 1 and WordIdxBits becomes 0, which emits
      logic [-1:0]. rtl_pkg.cpp:373-381
  E2  the core slave adapter is single-outstanding by construction.
      outstanding_requests is read by no stage
  E3  no request identifier and no out-of-order return reaches any
      emitted module. link_sig.cpp builds the signals and nothing
      consumes them
  E4  no MSHR file exists. The control is a blocking FSM,
      rtl_cache.cpp:1004-1017
  E5  read_latency_cycles and tag_compare_stage are inert for a cache
      node. A hit occupies three cycles and the path is not pipelined
  E6  beat_order and bypass_to_upstream are inert. l1i_mem_mst.sv
      collects both beats, then answers
  E7  the four maintenance fields are inert. No invalidate port is
      emitted on any node
  E8  nothing in the tool has any notion of prefetch
```

NONE OF THE EIGHT IS A ONE-LINE FIX except E1. E2 through E4 are one
piece of work: an outstanding-request cache is an MSHR file, an
identifier on the core port, and a non-blocking control, and doing any
one alone buys nothing.

---

## What was delivered

An assessment, in this section. No file in either repository was
changed. Build artifacts and three dependency submodule checkouts are
listed under Files Modified.

### PROBLEM 2 -- CAPABILITY, NOT FIELDS

C1  A READ-ONLY CACHE.  EXISTS, in the node model. PARTIAL, in the
    emitter.

    `node_type: icache` is the tool's notion of read-only and it is
    first class. node_ctx.h:84 is the whole definition:
    `has_writes() { return type_ != "icache"; }`. Read-only is not
    inferred from the policy block, and a policy block that declares
    no write behaviour on a dcache is a T-6 group error
    (checker.cpp:246-250), not a read-only cache.

    The schema enforces the same thing independently,
    caches.schema.json:382-425: an icache may not carry write_miss,
    write_hit or dirty_bits, and flush_line and flush_all must be
    false.

    WHAT THE EMITTER PRODUCES. rtl_cache.cpp branches on has_writes()
    in six places and drops the write path, the dirty bits and the
    write-back data. Two things survive that should not:

    - the writeback states are emitted and tied off. l1i_ctrl.sv
      declares C_EVICT and C_EVICT_W, `wire evict_needed = 1'b0`, and
      a lint-off block reading the victim line so the array output is
      not reported unused. rtl_cache.cpp:1210, 1481
    - the core port carries a write channel. l1i_core_slv.sv has
      core_rw, core_wdata and core_wstrb, all tied into a
      `wire unused_wr`. That is not the node model's doing; it is the
      LINK, which is shared with the L1D edge and declares
      write_width_bits 32. C1 and C3 are the same finding seen from
      two ends

    So: the node knows it is read-only, the link does not, and no
    link can be told.

C2  INCLUSION AS A PROPERTY OF A PAIR.  ABSENT, and inert.

    `inclusion` is a single enum on the cache node,
    caches.schema.json:177-183, values inclusive / exclusive / nine.
    There is no per-interface and no per-edge form. The topology
    edge object is `additionalProperties: false` with six required
    string fields and nothing else (topology.schema.json:117-152), so
    an edge cannot carry an inclusion answer either.

    IT IS ALSO INERT. NodeCtx::inclusion() exists at node_ctx.cpp:89
    and no caller anywhere in cli/src invokes it. unconsumed.log lists
    /caches/l1i/inclusion, /caches/l1d/inclusion and
    /caches/l2/inclusion. So TD-L1I-1's disagreement has no
    consequence in emitted RTL today: both declarations are dead
    text.

    WHAT WOULD MAKE IT PER-EDGE. The clean form is to move inclusion
    off the node and onto the interface object, which already exists
    and already carries a link and an arbitration field
    (caches.schema.json:307-345). l2 would then declare
    `up_i: { inclusion: "nine" }` and `up_d: { inclusion: "inclusive" }`
    and the l1i node would stop declaring inclusion at all, because
    inclusion is the lower cache's obligation. That is the
    recommendation. The alternative, a `pair` list in topology naming
    two nodes and a value, adds a fourth place a reader must look
    and is not recommended.

C3  ONE LINK, TWO DIFFERENT EDGES.  A LINK CANNOT BE PARAMETERISED
    PER EDGE. A SECOND LINK TYPE IS THE ANSWER, and it costs nothing.

    The schema forbids it: the edge object carries from / to /
    interface / port names and nothing else, `additionalProperties:
    false`. The resolver forbids it in the same words --
    resolver.cpp:303, "The link is not on the edge, both ends carry
    one" -- and the checker requires both ends of an edge to name the
    same link definition (checker.cpp T-9, link_agree).

    A SECOND LINK TYPE IS PURE CONFIGURATION. Nothing binds a port
    type to one link: two link definitions may both declare
    master_port_type pe_mstr and slave_port_type pe_slv, and no check
    in checker.cpp objects. So the I-side edge is served by adding
    one link to pacino_links.json and changing two `link:` strings in
    pacino_caches.json, on ifu/interfaces/mem and l1i/interfaces/core.
    No tool change and no schema change.

    RECOMMENDATION: declare `if_port`, leave `pe_port` untouched for
    the LSU-to-L1D edge. Parameterising per edge is the wrong shape
    anyway -- it would put a link's widths in two files and give T-9
    nothing to compare.

C4  OUT-OF-ORDER RESPONSE.  THE SIGNALS EXIST. NOTHING USES THEM.

    `custom.handshake.read_data_return` already has `valid_with_id`
    beside `valid_flag` and `same_cycle`, and `custom.id_width_bits`
    already exists (links.schema.json:173-181, 259-263). LinkSig
    implements both: link_sig.cpp:247 adds an `id` on the request,
    and 299-303 adds `rvalid` plus `rid` on the response. So a
    configuration CAN declare an identified, out-of-order link and
    cgen will emit the wires.

    NOTHING BEHIND THE WIRES EXISTS.

    - `outstanding_requests` is read by no stage. It is in
      unconsumed.log under /links/pe_port/custom/outstanding_requests
    - the emitted core adapter is single-outstanding as a matter of
      generated text, not of configuration. l1i_core_slv.sv says
      "one outstanding request, so the state is a single flag" and
      implements exactly that
    - the control behind it is a blocking FSM that asserts req_ready
      only in C_IDLE
    - on the memory side the same is true against TileLink:
      l1i_mem_mst.sv drives `mem_a_source = '0'` unconditionally,
      although the link declares source_bits 3

    So nothing "assumes in-order" in the sense of a broken ordering
    rule. The adapters assume ONE, which is stricter.

C5  PREFETCH POLICY.  ABSENT ENTIRELY.

    `prefetch` appears nowhere in cli/src, cli/inc or any schema. No
    field, no enum value, no emitted signal.

    TlAIntent IS in the shared opcode package: rtl_pkg.cpp:91 emits
    it and it is present in output/pacino/rtl/cgen_tl_pkg.sv:31, so
    icache_decisions.md 8.2 is correct on that point. NOTHING EMITS
    IT. The only channel A opcode any generated master drives is
    TlAGet, and TlAPutFullData where a node has writes
    (l1i_mem_mst.sv, always_comb block on channel A). The opcode
    package is emitted whole by design, so the constant's presence is
    not evidence of a path.

C6  MSHRs AT ALL.  THE COUNT IS CARRIED AND REACHES A COMMENT.

    `mshrs` is not in unconsumed.log, which makes it look consumed.
    It is read in exactly one place. rtl_cache.cpp:1046:

      f.note("  mshrs        " + std::to_string(c.mshrs()) +
             " declared, the control is blocking and does not use
             them");

    That is the whole of it, and the emitted l1i_ctrl.sv carries the
    sentence verbatim. rtl_cache.cpp:1004-1017 states the same thing
    as a design note: "A blocking cache: one request at a time ...
    mshrs is carried into the package as the declared depth and
    reported, it does not size anything yet". No MSHR file, no
    merging, no target tracking. mshr_targets is fully inert.

    The tool's own feature table agrees and is more precise than
    unconsumed.log: features.log classifies
    /caches/l1i/miss_handling/mshrs as "NO TEST consumed -- read by
    the tool, and its effect is not observable from a port. It shapes
    emitted text or a derived width rather than behaviour."

C6 GENERALISED -- EVERY OTHER TARGET FIELD CARRIED BUT UNCONSUMED.
From output/logs/unconsumed.log, node l1i, restricted to fields
section 9 names:

```
  /caches/l1i/inclusion
  /caches/l1i/fill/beat_order
  /caches/l1i/fill/bypass_to_upstream
  /caches/l1i/miss_handling/mshr_targets
  /caches/l1i/miss_handling/victim_buffer_entries
  /caches/l1i/miss_handling/fill_buffer_entries
  /caches/l1i/timing/read_latency_cycles
  /caches/l1i/timing/tag_compare_stage
  /caches/l1i/maintenance/invalidate_line
  /caches/l1i/maintenance/invalidate_all
  /caches/l1i/maintenance/flush_line
  /caches/l1i/maintenance/flush_all
  /links/pe_port/custom/outstanding_requests
```

Two of these matter more than the count suggests.

  MAINTENANCE. All four are inert, so NO INVALIDATE PORT IS EMITTED
  ON ANY NODE. The `meta_inv_en` signal in l1i_ctrl.sv is the
  post-reset set walk, gated on `cstate == C_INIT`, and for l1i that
  state is unreachable because reset enters C_IDLE. L1I-18 has no
  hardware at all today, and RVA23's Zicbom depends on it.

  FILL. beat_order critical_first and bypass_to_upstream are inert,
  and l1i_mem_mst.sv shows what is emitted instead: beats are written
  into fill_q at their linear index, M_DONE is entered on the last
  beat, and only then is mrsp_valid raised. The whole line is
  assembled before anything is answered. L1I-16's stated reason for
  critical-first is not achievable.

  There is also one field outside section 9 worth naming: the
  interface-level `arbitration` enum in caches.schema.json:314-322 is
  consumed by nothing. node_ctx.cpp:361 says so: "nothing consumes
  arbitration yet". It does not appear in unconsumed.log only because
  pacino does not declare it.

### PROBLEM 3 -- THE FIELD MAPPING

Section 9, first table. Verdict is against the SCHEMA. `inert` in the
last column means the schema accepts the value and no emitted RTL
moves when it changes; it is not part of the ACCEPTS/REJECTS/ABSENT
verdict but it is the reason Problem 1's answer is no.

| Field                  | Target         | Verdict | Note |
|------------------------|----------------|---------|------|
| capacity_bytes         | 65536          | ACCEPTS |      |
| line_bytes             | 64             | ACCEPTS |      |
| associativity          | 8              | ACCEPTS |      |
| banks                  | 2              | ACCEPTS | n1   |
| bank_interleave        | line           | REJECTS | n2   |
| indexing               | PIPT           | ACCEPTS | n3   |
| read_miss              | allocate       | ACCEPTS |      |
| replacement            | tree_plru      | ACCEPTS |      |
| inclusion              | non_inclusive  | REJECTS | n4   |
| mshrs                  | 16             | ACCEPTS | n5   |
| mshr_targets           | 4              | ACCEPTS | inert|
| victim_buffer_entries  | 0              | ACCEPTS | inert|
| fill_buffer_entries    | 0              | ACCEPTS | inert|
| beat_order             | critical_first | ACCEPTS | inert|
| bypass_to_upstream     | true           | ACCEPTS | inert|
| read_latency_cycles    | 2              | ACCEPTS | inert|
| tag_compare_stage      | next_cycle     | ACCEPTS | inert|
| invalidate_line        | true           | ACCEPTS | inert|
| invalidate_all         | true           | ACCEPTS | inert|
| flush_line             | false          | ACCEPTS | n6   |
| flush_all              | false          | ACCEPTS | n6   |
| prefetch_arbitration   | demand_first   | ABSENT  | n7   |

Section 9, second table, the core link. These are fields of a link
definition in pacino_links.json, under `custom`, not fields of the
l1i node.

| Field                  | Target         | Verdict | Note |
|------------------------|----------------|---------|------|
| read_width_bits        | 512            | ACCEPTS | n8   |
| address_width_bits     | pa_bits        | REJECTS | n9   |
| outstanding_requests   | 8              | ACCEPTS | inert|
| write_width_bits       | 0              | REJECTS | n10  |
| out_of_order_response  | true           | ABSENT  | n11  |

NOTES

```
  n1   accepts, but caches.schema.json:120-137 then REQUIRES
       bank_interleave_granularity, which the l1i node does not
       currently carry. Adding banks 2 alone fails validation
  n2   the schema's name is bank_interleave_granularity,
       caches.schema.json:112. `geometry` is
       additionalProperties: false, so `bank_interleave` is refused
       by name. The VALUE "line" is accepted under the right name
       and is fully implemented, geometry.cpp:230-329
  n3   caches.schema.json:139-144. Consumed only by the VIPT index
       check in geometry.cpp:174-193; PIPT and VIPT emit identical
       RTL, so this is a diagnostic-shaping field
  n4   caches.schema.json:177-183 enumerates inclusive / exclusive /
       nine. `non_inclusive` is not a member. `nine` is the schema's
       spelling of it and the l1i node ALREADY DECLARES IT, so the
       "Changed: yes" mark on this row is wrong. Inert either way
  n5   caches.schema.json:188-192, maximum 1024. Reaches a comment
       only, see C6
  n6   already false, and caches.schema.json:417-425 pins both to
       false for an icache regardless
  n7   no such field in any schema and no such concept in cli/.
       It belongs in the cache_node object of caches.schema.json,
       as a new `prefetch` group beside `fill`, guarded to icache /
       dcache / unified
  n8   links.schema.json:227-231, minimum 8 maximum 4096, so the
       schema takes it. THE EMITTER BREAKS ON IT, see E1 below
  n9   links.schema.json:210-214 takes an integer 1..128. There is
       no symbolic reference to pa_bits anywhere in the input
       language. As the integer 36 it ACCEPTS, and nothing then
       checks it against topology addressing pa_bits
  n10  links.schema.json:232-236 gives minimum 8, and 145-147 makes
       write_width_bits required inside `custom`. 0 is refused and
       omission is refused
  n11  no such field. The capability is present under another name:
       handshake.read_data_return "valid_with_id" plus
       id_width_bits, links.schema.json:173-181 and 259-263
```

### PROBLEM 4 -- THE PROPOSAL, SPLIT THREE WAYS

Ordered by what unblocks the most. Every item is in exactly one
bucket; where an item spans two, the split is stated on its own line.

---

CONFIGURATION -- tools/cachegen/testcases/pacino. No tool change, no
schema change. All four can land in one commit today.

```
  G4  A SECOND CORE LINK TYPE. Unblocks the most, because every
      other core-port change is blocked behind not being allowed to
      touch the D-side.

      pacino_links.json: add `if_port`, protocol custom,
      master_port_type pe_mstr, slave_port_type pe_slv. Copy
      pe_port's body and change read_width_bits to 512,
      outstanding_requests to 8, handshake.read_data_return to
      "valid_with_id", and add id_width_bits 3.
      pacino_caches.json: change two `link` strings, on
      /caches/ifu/interfaces/mem and /caches/l1i/interfaces/core.
      pacino_ports.json: no change, port types are reusable.

      ALTERNATIVE: parameterise pe_port per edge. Rejected. It
      requires a schema change and a resolver change, it puts one
      link's widths in two files, and it leaves T-9 nothing to
      compare. Not recommended.

      write_width_bits stays at 32 in if_port until S2 lands. That is
      the one part of G4 that cannot be finished in configuration
      alone.

  G1  GEOMETRY. /caches/l1i/geometry: capacity_bytes 32768 -> 65536,
      banks 1 -> 2, and add bank_interleave_granularity "line".
      All three must land together; banks 2 without the granularity
      fails schema validation, n1.
      Derived result, from geometry.cpp: sets 128, sets_per_bank 64,
      bytes_per_way 8192, offset [5:0], index [12:6], bank [6:6],
      setidx [12:7], tag [31:13] at the current pa_bits 32. That is
      icache_decisions.md 1.2 exactly.

  G2  INDEXING. /caches/l1i/indexing VIPT -> PIPT. One string. It
      also REMOVES a diagnostic risk: at 65536 bytes and 8 ways,
      bytes_per_way is 8192 against a 4096 byte page, so leaving
      indexing at VIPT with G1 applied raises T-8.vipt_index and
      cgen refuses to emit. G1 and G2 must land together.

  G3  MISS HANDLING. mshrs 4 -> 16, mshr_targets 2 -> 4. Free, and
      buys nothing until E4. Land it anyway so the configuration
      states the intent.
```

TWO EXISTING TESTS BREAK on G1 and G2 and must be updated in the same
change. Both are in cli/tb and both hardcode the present geometry:

```
  test_geometry.cpp:63  GeometryPacino.L1iDerivation asserts
                        sets 64, index_bits 6, tag_bits 20,
                        index.msb 11, masks 0x00000fc0 and
                        0xfffff000, bank_bits 0
  test_pacino.cpp:30    Pacino.ViptIndexBudgetIsMet asserts
                        l1i->indexing == "VIPT" and
                        bytes_per_way == page_bytes
```

---

SCHEMA -- tools/cachegen/planning/schema.

```
  S2  A READ-ONLY CUSTOM LINK. links.schema.json.
      Change custom.write_width_bits minimum from 8 to 0, and remove
      it from the `custom` required list at 145-147 so absence means
      the same thing. Then link_sig.cpp needs one line: add() already
      drops a zero-width signal, but data_bits_ is computed as
      max(read, write) at link_sig.cpp:222 and wstrb is computed from
      ww_bits, so a zero write width must not zero the data width.
      SPLIT: the minimum and the required list are SCHEMA; the
      data_bits_ guard is C++.
      ALTERNATIVE: a `read_only: true` boolean on the custom link.
      Rejected -- it duplicates information the widths already carry
      and creates a pair that can disagree.

  S1  prefetch_arbitration. caches.schema.json. A new `prefetch`
      group in cache_node, beside `fill`, with a single enumerated
      member. Enumerate the policy, do not decompose it:
      `"prefetch": { "arbitration": { "enum": ["none",
      "demand_first"] } }`, where demand_first means all three of
      icache_decisions.md 8.1 P1, P2 and P3 together. Guard it to
      icache / dcache / unified in the same allOf style the file
      already uses.
      SPLIT: SCHEMA for the field, C++ for a consumer. Adding the
      field alone makes it appear in unconsumed.log, which the suite
      permits but which is the state Problem 1 is complaining about.

  S3  out_of_order_response. NO NEW FIELD. Use the two that exist:
      handshake.read_data_return "valid_with_id" and id_width_bits.
      This is a finding that the capability is already there. The
      only schema work is a constraint tying them together: reject
      read_data_return "valid_with_id" when id_width_bits is absent
      or 0, which the file can express with the same if/then pattern
      it already uses for mshrs / mshr_targets.
      ALTERNATIVE: add a boolean out_of_order_response as the
      document names it. Rejected -- it would be a second way to say
      what read_data_return already says, and the two could
      disagree.

  S5  pa_bits AGREEMENT. Either a schema constraint or a checker
      rule; a checker rule is better because the schema cannot see
      across files. Report an error when a link's
      custom.address_width_bits or tilelink.address_bits differs
      from topology addressing pa_bits on an edge whose endpoints
      are cache or memory nodes.
      SPLIT: C++, in checker.cpp, as a new T-code with a negative
      fixture. Listed here because it is a rule about the input
      language rather than about emission. See Problem 5, L1I-U1.

  S4  INCLUSION PER INTERFACE. Move `inclusion` from cache_node to
      the interface object in caches.schema.json. LOWEST PRIORITY of
      the five: inclusion is inert, so TD-L1I-1 changes no emitted
      bit today. Do it when something consumes it, not before.
```

---

C++ -- tools/cachegen/cli/src and cli/inc.

```
  E1  THE 512-BIT CORE PORT BREAKS THE PACKAGE. Blocks L1I-9, and
      blocks G4 from being useful.
      rtl_pkg.cpp:373-381 emits
        WordBytes    = core_data_bits() / 8
        WordsPerLine = LineBytes / WordBytes
        WordIdxBits  = $clog2(WordsPerLine)
        WordIdxMsb   = WordIdxLsb + WordIdxBits - 1
      At read_width_bits 512 and line_bytes 64, WordBytes is 64,
      WordsPerLine is 1 and WordIdxBits is 0. The package then
      declares `function automatic logic [WordIdxBits-1:0] word_of`,
      which is logic [-1:0].
      FIX: guard WordIdxBits the way BeatIdxBits at rtl_pkg.cpp:392
      is already guarded, and drop the word extract from the control
      when WordsPerLine is 1 -- at a line-wide core port there is no
      word to select and rtl_cache.cpp's word_out() is the identity.
      NOT RUN. Derived by reading rtl_pkg.cpp, not by running cgen,
      which the constraints forbid. One command settles it:
      emit a copy of pacino with read_width_bits 512 into a scratch
      directory and verilate the l1i node.

  E2  OUTSTANDING REQUESTS. Blocks L1I-10.
      rtl_cache.cpp emits the core slave adapter with a single `busy`
      flag. `outstanding_requests` must reach it and size a request
      queue. NodeCtx has no accessor for it at all; link_sig.cpp does
      not read it either, so it needs a reader as well as a consumer.

  E3  IDENTIFIED, OUT-OF-ORDER RESPONSE. Blocks R2.
      link_sig.cpp already emits `id`, `rvalid` and `rid` when the
      link declares valid_with_id. The adapter must carry the id
      alongside the request and return it with the response, and the
      internal request bundle in rtl_cache.cpp must gain an id field.
      On the memory side the same work drives mem_a_source, which
      l1i_mem_mst.sv currently ties to '0'.

  E4  THE MSHR FILE. Blocks L1I-12 and L1I-13, and makes E2 and E3
      worth having.
      rtl_cache.cpp:1004-1017 is the design note that says this does
      not exist. A new emitter, sized by mshrs and mshr_targets, and
      a control that leaves C_IDLE ready rather than blocking.
      THIS IS THE LARGEST ITEM. E2, E3 and E4 are one task, not
      three: eight outstanding requests with in-order return and no
      miss tracking is the blocking cache with extra wires.

  E5  LATENCY AND PIPELINING. Blocks L1I-5.
      read_latency_cycles and tag_compare_stage are read into NodeCtx
      (node_ctx.cpp:318-320) and their accessors are called only by
      rtl_mem.cpp, for the memory node. For a cache node they are
      dead. The emitted control takes three cycles per hit
      (C_IDLE, C_TAG, C_HIT) and accepts one request at a time.
      Sequenced AFTER E4; a pipelined hit path in a blocking cache
      is not a pipeline.

  E6  CRITICAL FIRST AND BYPASS. Blocks L1I-16's stated reason.
      NodeCtx::beat_order() exists at node_ctx.cpp:96 and no caller
      invokes it. bypass_to_upstream appears nowhere in cli/ at all
      and needs a reader first. l1i_mem_mst.sv's M_RSP state must
      request the critical beat first and forward it upstream rather
      than filling fill_q and waiting.
      NOTE FOR THE PA: with L1I-9 as written this buys nothing. See
      Problem 6, item 6f.

  E7  THE MAINTENANCE PORT. Blocks L1I-18 and RVA23 Zicbom.
      All four maintenance fields are inert and no node emits an
      invalidate port. This is a new interface on the generated
      module, an `inv_valid` / `inv_addr` / `inv_all` bundle, plus a
      control path that clears valid bits. The reset-branch clear
      that L1I-6 relies on already exists in the flop-file valid
      array, so invalidate_all is cheap; invalidate_line needs a tag
      lookup and a per-way clear.
      SCHEMA SPLIT: none. The fields exist. This is emitter work
      only.

  E8  PREFETCH. Blocks L1I-19 and 8.1.
      Nothing exists. Sequenced last, and behind E4, because P2 --
      a prefetch never occupying an MSHR a demand miss requires --
      cannot be expressed before MSHRs exist.
```

PROVABLE WITHOUT RTL, from cheapest to dearest: G1 through G4, S1
through S5, E1. Everything from E2 to E8 changes behaviour that only a
simulation shows. See Problem 7.

### PROBLEM 5 -- WHAT THE MODEL CANNOT HOLD

Assessment only. Note that section 10.1 records FIVE open items,
L1I-U1 through L1I-U5, not four; U5 is delegated to
ifu_decisions.md and is not assessed here.

```
  pa_bits at 36     CAN BE SET. It is topology addressing.pa_bits,
                    topology.schema.json:52-56, integer 8..64, and it
                    reaches the emitted package as PaBits and the
                    address type as addr_t (rtl_pkg.cpp:256, 401).
                    Tag width follows from it in geometry.cpp:157.

                    THE FINDING IS THE SECOND ASSUMPTION, and it is
                    exactly the shape the problem describes. A LINK
                    declares its own address width, independently:
                    custom.address_width_bits and
                    tilelink.address_bits, both defaulting to 32 in
                    link_sig.cpp:206 and 141. Nothing checks the two
                    against each other -- checker.cpp has no such
                    rule. At pa_bits 36 with the current links the
                    adapters silently adapt: rtl_cache.cpp:193 emits
                    `assign req_addr = addr_t'(core_addr)`, which
                    zero-extends a 32-bit link address into a 36-bit
                    node address with no diagnostic, and
                    l1i_mem_mst.sv drives a 32-bit mem_a_address from
                    a 36-bit addr_q, truncating the top four bits.
                    Four bits of physical address would be lost on
                    every refill and nothing would say so.

                    So: parameterised in one place, assumed in three
                    -- two link address fields and one silent cast.
                    S5 is the rule that would catch it.

  an ITLB           NOT A NODE TYPE, and the node model is
                    cache-shaped throughout.
                    node_type is a closed enum of six:
                    icache, dcache, unified, memory, agent,
                    interconnect (caches.schema.json:76-85).
                    Anything with storage must be one of the first
                    four, and all four require a `geometry` block
                    (caches.schema.json:596-612) whose four members
                    are capacity_bytes, line_bytes, associativity and
                    banks, with line_bytes a closed enum of
                    16/32/64/128/256 and capacity_bytes minimum 256.
                    geometry.cpp then forces sets to be a power of
                    two and offset + index + tag to sum to pa_bits.

                    A 32-entry fully associative TLB has no line, no
                    index and no power-of-two set count worth the
                    name. Fully associative is expressible by
                    accident -- capacity / (line * ways) = 1 gives
                    index_bits 0 -- but only by inventing a line size
                    the structure does not have. Mixed page sizes
                    have no representation at all, and `indexing` is
                    a two-member enum of PIPT and VIPT, neither of
                    which describes a VA-indexed PA-producing
                    structure.

                    An `agent` node CAN model a TLB with no storage,
                    since an agent carries interfaces and nothing
                    else. That is a placeholder, not a TLB.

  a walker node     THE TOPOLOGY ALLOWS IT. The node is the problem,
                    not the graph.
                    A third upstream interface on l2 is already
                    supported and already generic: rtl_cache.cpp:1703
                    reads slaves() as a vector, emits NSlv, and
                    builds round-robin arbitration across however
                    many there are (rtl_cache.cpp:1719-1732). l2
                    already has two. A third named `up_w` with its
                    own link is a configuration change.
                    Adding a NODE is also supported: topology nodes
                    are an open map and edges are an open array.
                    THE LIMIT IS WHAT THE NODE CAN BE. An L2 TLB
                    containing a page cache, a walker, a miss queue
                    and a prefetcher is not any of the six node
                    types, for the reasons above. As an `agent` it
                    would carry the TileLink master edge into l2 and
                    hold nothing.
                    ONE MORE LIMIT: a node may have at most one
                    downstream edge. geometry.cpp:352-359 reports
                    "several downstream links, beat count is
                    ambiguous" and leaves refill_beats unset, and
                    NodeCtx::mem_data_bits() returns the FIRST master
                    interface and ignores the rest. A walker that
                    talks to more than one thing below it is not
                    expressible.

  PMP and PMA       NOTHING. No field, no node type, no enum value,
                    no emitted signal. `pmp`, `pma`, `tlb`, `walker`
                    and `page_table` do not appear in cli/src,
                    cli/inc or any of the five schemas. The model has
                    no notion of an access check anywhere in a path.
```

ONE MORE MODEL LIMIT, relevant to icache_decisions.md 0.1. The
document names three L1I interfaces and marks `itlb` as IN only. An
interface in cachegen is an edge endpoint: caches.schema.json:307-345
requires every interface to carry a `link` and a `ports` map, and the
link is bidirectional by construction. A one-way input that is not a
link cannot be declared. The translated physical address would have to
arrive on the core link, which is what L1I-4 effectively assumes.

### PROBLEM 6 -- WHERE THE TARGET IS WRONG

FIRST, WHAT IS RIGHT, because the prompt directs a specific check at
it. Section 1.2's arithmetic is CORRECT and it matches the tool's own
derivation exactly, not approximately.

At capacity 65536, ways 8, line 64: sets = 65536 / (8 * 64) = 128,
index_bits = 7, offset_bits = 6, tag = pa_bits - 13. With banks 2 and
line granularity, geometry.cpp:315-317 places the bank select at the
bottom of the index, PA[6:6], and leaves setidx at PA[12:7], 6 bits,
64 sets per bank. geometry.cpp:325-336 then corroborates that against
sets_per_bank derived independently as sets / banks, and the two
agree. The l2 node in the checked-in geometry.log is the same
derivation at a different size and confirms the reading. Section 2.2's
alias table is also correct at all four rows, and 24576 tag-array bits
is 128 * 8 * 24.

NOW THE ERRORS.

```
  6a  L1I-11 IS CITED AND NEVER STATED. Section 1.1's derived table
      attributes banks 2 to L1I-11, and section 9 attributes both
      `banks` and `bank_interleave` to it. No L1I-11 appears
      anywhere in the document. The registry paragraph claims the
      file owns L1I-1 through L1I-19, so this is a hole in the
      registry, not a citation of another file.

  6b  A FIELD NAME THAT IS NOT THE SCHEMA'S. Section 9 row
      `bank_interleave`. The schema's name is
      bank_interleave_granularity, caches.schema.json:112, and
      `geometry` is additionalProperties: false, so the document's
      name would be refused. The value is right.

  6c  A VALUE THAT IS NOT IN THE ENUM, AND A WRONG "CHANGED" MARK.
      Section 9 row `inclusion`, value non_inclusive, marked
      Changed: yes. The schema enumerates inclusive / exclusive /
      nine (caches.schema.json:177-183). `nine` IS the schema's
      spelling of non-inclusive non-exclusive, and the l1i node
      already declares it. Nothing changes on this row. Section 5.1
      states the same fact correctly ("l1i declares nine"), so the
      document contradicts itself between 5.1 and 9.

  6d  A SYMBOLIC VALUE THE INPUT LANGUAGE DOES NOT HAVE. Section 9
      second table, address_width_bits: pa_bits. There is no symbol
      reference anywhere in the configuration language; every width
      is a literal integer. The row must name a number, and Problem
      5's first item is why naming one is not enough on its own.

  6e  A VALUE THE SCHEMA REFUSES. Section 9 second table,
      write_width_bits: 0. links.schema.json:232-236 sets minimum 8
      and 145-147 makes the field required. This is a real gap and
      S2 proposes the fix; it is listed here because the document
      states the value as if it were available.

  6f  A REQUIREMENT CONTRADICTING ANOTHER REQUIREMENT. L1I-9 says
      the core interface returns ONE FULL CACHE LINE, 64 bytes, per
      request. Section 5.2 justifies critical-first and
      bypass_to_upstream with "The requested 32-byte block returns
      in the first beat and is forwarded upstream as it arrives, so
      a miss costs the L2 latency and not the L2 latency plus a
      second beat."
      Both cannot hold. If the core response is a whole 512-bit
      line, the L1I cannot answer until the second 256-bit beat has
      arrived, and the beat saved by forwarding is spent waiting.
      Critical-first still orders the refill usefully for a second
      requester, but the stated saving is not available to the
      requester that missed.
      Either L1I-9 admits a beat-granular core response -- which
      also changes what L1I-14 asks the IFU to hold -- or 5.2's
      justification is withdrawn. This is a decision, not a typo,
      and it is the PA's.

  6g  A DERIVED VALUE ATTRIBUTED TO A DECISION IT DOES NOT FOLLOW
      FROM. Section 1.1's derived table lists `banks 2, From
      L1I-11`. Banks is an input to the geometry, not a derived
      value; every other row of that table is genuinely computed.
      Minor, and it compounds 6a.
```

CLAIMS ABOUT CACHEGEN THAT ARE TRUE, checked this session and listed
so the next task does not re-check them:

```
  - TlAIntent is in the shared opcode package. rtl_pkg.cpp:91,
    cgen_tl_pkg.sv:31. Section 8.2 is correct
  - TL-UH carries A and D only, with no B channel and no probe path.
    link_sig.cpp:141-158 gates B, C and E on TL-C. Section 5.2's
    withdrawal of the earlier "missing channel B" finding is correct
  - the l1i-to-l2 link is 256 bits, 32 bytes per beat, 2 refill
    beats for a 64-byte line. tl_l1i_l2 declares data_bus_bytes 32
    and geometry.cpp:364 derives 2. Section 5.2's numbers are right
  - l1i declares nine and l2 declares inclusive. Section 5.1 is
    right about the disagreement, and Problem 2 C2 adds that both
    are inert
  - pe_port is shared between the ifu-to-l1i and lsu-to-l1d edges,
    and the initial port was 32 bits with one outstanding request.
    Section 4.1 is right
  - the initial capacity was 32 KiB and the initial mshrs was 4.
    Sections 1.1 and 6 are right
  - l1d and l2 both carry mshr_targets 4. Section 6 is right
  - l1i's storage declaration already matches L1I-6 and L1I-8
    exactly: inferred_sram registered for tag and data, flop_file
    combinational cleared_on_reset for valid and replacement,
    array_per_way, parallel. Those five rows of section 9 need no
    change and are correctly unmarked
  - the l2 node declares SRAM valid bits and the emitted control
    walks the sets after reset to clear them. Section 3 is right;
    the walk is C_INIT in the generated control
```

ONE FILE THE PROMPT SUGGESTED MIGHT ANSWER PROBLEM 3 DOES NOT.
misc/example_pacino_icache.json is a SUPERSEDED SINGLE-FILE SCHEMA,
not an input the current tool can read. It declares schema_version
1.0.0, has no file_type, and uses a flat shape -- cache_type, level,
an addressing block inside the node, an emission block, a
verification block -- that no current schema defines. The current
system file is pinned to schema_version 0.10.0 with file_type
"system" and five separate documents. The elaborated form records
tool_version 0.1.0-draft and generated_utc 2026-08-23. It also
carries no inclusion, no outstanding_requests and no prefetch, so it
would not have answered Problem 3 even if it loaded.

### PROBLEM 7 -- WHAT PROVES A CHANGE

HOW IT IS BUILT AND RUN.

```
  build   cd tools/cachegen/cli && make all
          g++, C++20, -Wall -Wextra, -g -O1, no CMake.
          Produces bin/cgen and bin/cgen_tests.
  run     cd tools/cachegen/cli &&
          CGEN_SCHEMA_DIR=../planning/schema ./bin/cgen_tests
          The Makefile's `test` target does exactly this.
  deps    three git submodules under tools/cachegen/tools:
          jnutils (msg.h), json-schema-validator (six sources
          compiled in), googletest (gtest-all.cc compiled in).
          Boost.ProgramOptions from the system. ALL THREE
          SUBMODULES WERE UNINITIALIZED and had to be checked out
          before the build would run.
```

COUNTS, from a clean build in this session. `make clean` was not
needed; cli/obj and cli/bin did not exist.

```
  build    clean, exit 0, one warning:
           rtl_tb.cpp:400:48 unused parameter 'c' [-Wunused-parameter]
  tests    86 tests, 14 suites, 2861 ms
  passed   86
  failed   0
```

Per suite:

```
  Bank              6    GeometryPacino    5    Negative         29
  Diagnostic        2    Logs              7    Pacino            3
  Diagnostics       3    Base              1    SchemaFiles       1
  Emit             10    Loader            2    Vars              9
  Featnames         6    GeometryMath      2
```

The suite does NOT run Verilator. test_emit.cpp checks the emitted
tree mechanically -- the expected file set, byte-identical
re-emission, the generated header on every file, 80 columns, no tabs
-- and never compiles what it emitted. That is the line between the
two kinds of proof below.

THE FIXTURE PATTERN. A negative fixture is a directory under
cli/tb/fixtures holding a system.json plus only the documents it
overrides; everything else is included from ../base. neg_vipt_alias
is the model to copy: two files, system.json and caches.json, with
caches.json including ../base/base_ports.json. The test is one line,
`expect_one("<fixture>", "<T-code>", "<substring the message must
name>")`, and expect_one asserts EXACTLY ONE diagnostic
(test_negative.cpp:26-39). Fixture::configs() enumerates fixture
directories rather than listing them, so a new directory is picked up
with no edit to the harness.

WHAT PROVES EACH PROPOSAL, BEFORE ANY RTL IS GENERATED.

Provable in the C++ suite:

```
  G1  test_geometry.cpp, GeometryPacino.L1iDerivation. EDIT, do not
      add: the existing test asserts the 32 KiB derivation and must
      be rewritten to sets 128, index_bits 7, tag_bits 19 at
      pa_bits 32, bank_bits 1, index.msb 12, setidx 6 bits at
      shift 7. test_bank.cpp is the pattern for the bank half --
      Bank.L2DecomposesAsTheRulingSays is the same assertion at a
      different size.
  G2  test_pacino.cpp, Pacino.ViptIndexBudgetIsMet. EDIT: l1i is no
      longer VIPT, so l1i must come out of the `vipt` array and the
      test's name and comment must follow. Pacino.NoDiagnostics
      then proves G1 and G2 together, because a VIPT l1i at 8192
      bytes per way would raise T-8.vipt_index and fail it.
      A NEW NEGATIVE FIXTURE is worth adding here: the 64 KiB
      8-way geometry left at VIPT, asserting T-8.vipt_index. It
      documents why G1 and G2 cannot land separately.
      Pattern: neg_vipt_alias, which already asserts that code at a
      different size.
  G3  test_logs.cpp, Logs.TheUnconsumedReportAgreesWithWhatTheTool
      Read. Changing mshrs and mshr_targets proves nothing about
      behaviour, and the suite says so: mshr_targets stays on the
      unconsumed list until E4 lands.
  G4  test_emit.cpp, Emit.ProducesTheExpectedFileSetForPacino, plus
      Pacino.NoDiagnostics. A second link definition must not add or
      remove a node file, and must not raise T-3.port_type or
      T-9.link_agree. A NEW positive assertion belongs in
      test_emit.cpp: the emitted pe_port_pkg.sv and if_port_pkg.sv
      carry different DataBits.
  S1  test_logs.cpp, Logs.TheUnconsumedReportAgreesWithWhatTheTool
      Read, and test_features.cpp, Featnames.EveryFeatureHasATest
      OrAReason. A new schema field with no consumer MUST appear on
      the unconsumed list and MUST carry the inert reason. Both
      tests already enforce that, so adding the field alone is
      provable and self-documenting.
      A NEW NEGATIVE FIXTURE for the rejected enum value, following
      neg_schema_violation.
  S2  A NEW NEGATIVE FIXTURE is not what is wanted here -- the
      change REMOVES a rejection. The proof is a positive one: a
      fixture declaring write_width_bits 0 that produces no
      diagnostic, asserted with Fixture::run the way
      Base.CleanConfigurationHasNoDiagnostic does, plus an emit
      assertion in test_emit.cpp that the generated slave adapter
      carries no wdata and no wstrb port.
  S3  A NEW NEGATIVE FIXTURE: read_data_return "valid_with_id" with
      id_width_bits 0, asserting the new schema violation. Pattern:
      neg_schema_violation.
  S5  A NEW NEGATIVE FIXTURE: pa_bits 36 against a link declaring
      address_width_bits 32, asserting the new T-code. Pattern:
      neg_addressing_disagree, which is the closest existing check
      and is already the fixture for a cross-document disagreement.
      This one is worth having EVEN IF pa_bits stays at 32, because
      it is what makes L1I-U1 a decision rather than a hazard.
  S4  test_logs.cpp as for S1, and a schema fixture. Inert either
      way, so the test proves the shape and nothing more.
  E1  PROVABLE IN THE C++ SUITE, and it is the only C++ item that
      is. test_emit.cpp already reads every emitted file as text.
      A new test in the Emit suite: emit a configuration whose core
      link is 512 bits and whose line is 64 bytes, and assert that
      no emitted line contains "[-1:0]" and that WordIdxBits is
      declared with a guard. That is a text assertion on generated
      output, which is exactly what test_emit.cpp does today
      (NoEmittedLineIsWiderThanEightyColumns is the pattern).
```

Provable only by generating and simulating:

```
  E2  eight outstanding requests. Nothing in cli/tb can distinguish
      an adapter that accepts eight from one that accepts one; both
      emit legal text. The proof is the generated l1i_tb driving
      eight requests without a stall.
  E3  out-of-order return. Same. The proof is a response arriving
      with an id that is not the oldest outstanding.
  E4  MSHRs, merging and targets. Same, and this is the largest
      simulation-side item.
  E5  a 2-cycle pipelined hit at one request per cycle. Same. The
      C++ suite can assert that read_latency_cycles has left the
      unconsumed list; it cannot assert the cycle count.
  E6  critical-first and bypass. Same. features.log's coverage
      column is the C++-side evidence that a test now claims the
      field; the claim itself is a simulation.
  E7  the maintenance port. PARTLY C++: that an invalidate port
      appears in the emitted module text is a test_emit.cpp
      assertion. That it clears the right line is a simulation.
  E8  prefetch arbitration. Same split: the emitted parameter is a
      text assertion, P1 through P3 are simulations.
```

TWO SUITE-WIDE GATES that every item above must pass, and that are
easy to forget because they are not about the feature:

```
  Featnames.NoTestClaimsAnUnconsumedFeature   a test may not claim
      coverage of a field no stage reads. So an emitter change and
      its test must land together, or the suite fails
  Logs.EditingAnUnconsumedFieldChangesNothingEmitted   the inverse.
      A field that starts being consumed must leave the unconsumed
      list in the same change
```

---

## Test Case Results

No test case was added; this task changes nothing. The existing
cachegen unit suite was built and run to answer Problem 7.

```
  suite    tools/cachegen/cli/bin/cgen_tests
  invoked  CGEN_SCHEMA_DIR=../planning/schema ./bin/cgen_tests
  tests    86 in 14 suites
  passed   86
  failed   0
  time     2861 ms
  build    g++ C++20, exit 0, 1 warning
           (rtl_tb.cpp:400:48 unused parameter 'c')
```

The riscv-codesign bpu and ftq suites were NOT run, per the
constraints. No RTL in the pacino repository was touched and no
Verilator target was run.

cgen ITSELF WAS NOT RUN. The constraint forbids it and the checked-in
output/ tree was verified untouched after the suite: every file under
tools/cachegen/output still carries its 2026-08-28 10:49:28 timestamp.
The gtest suite exercises the emitter into scratch directories under
the system temp area, not into output/.

---

## Assumptions made not explicit in the prompt

- EFFORT LEVEL. The running effort level is not reported to the
  session, so the Model header field records the model id and
  "default". Correct it by hand if the session ran at another
  setting.

- BUILDING INCLUDES FETCHING DECLARED DEPENDENCIES. All three build
  submodules were uninitialized, so `make all` could not run at all
  until they were checked out. The constraints permit building and
  call its artifacts a consequence rather than a violation; a
  dependency the Makefile names and the tree does not contain was
  read the same way. This is reported under Files Modified rather
  than buried.

- PROBLEM 3'S VERDICT IS AGAINST THE SCHEMA. ACCEPTS, REJECTS and
  ABSENT are defined in the prompt as properties of the field, so
  they are answered against the five schema documents. Whether the
  accepted value then reaches emitted RTL is a separate column, and
  it is where the answer to Problem 1 actually lives.

- SECTION 9's SECOND TABLE IS A LINK, NOT A NODE. The table is
  captioned "Core link, replacing the pe_port shape", so its rows
  were mapped to links.schema.json custom link fields and not to
  anything in the l1i node.

- E1 IS DERIVED, NOT OBSERVED. cgen was not run, so the 512-bit
  package break is read out of rtl_pkg.cpp:373-381 rather than seen
  in output. The arithmetic is stated in full so it can be checked
  without rerunning anything.

---

## Decisions made not explicit in the prompt

- WHERE A CHANGE SPANS TWO BUCKETS, IT IS FILED UNDER THE BUCKET
  THAT BLOCKS THE OTHER, and the other half is named on its own
  line. S1 and S2 are both filed under SCHEMA with their C++ halves
  stated, because the schema half must land first.

- E2, E3 AND E4 ARE REPORTED AS ONE TASK. They are listed
  separately because the prompt asks for an enumeration, but doing
  any one alone produces a cache that is no less blocking than
  today's. Sizing the follow-on work from three separate line items
  would understate it.

- PROBLEM 6 REPORTS WHAT IS RIGHT AS WELL AS WHAT IS WRONG. The
  prompt says a finding that a capability exists is as valuable as
  a finding that it is missing; the same logic applies to the
  document. Section 1.2 is checked and correct, and a list of
  verified-true claims is included so the next task does not spend
  its budget re-deriving them.

- MISC/EXAMPLE_PACINO_ICACHE.JSON WAS READ FIRST, as the prompt
  directed, and then set aside. It is a superseded schema and
  answers nothing.

---

## RVA23 compliance risks and gaps noticed

- ZICBOM IS UNBUILDABLE TODAY. RVA23 mandates Zicbom, and
  icache_decisions.md 7 M2 puts cbo.inval on the L1I. All four
  maintenance fields are inert and no generated node emits an
  invalidate port of any kind. This is E7 and it is a hard RVA23
  gap, not a preference.

- FENCE.I HAS NO MECHANISM EITHER. L1I-18's invalidate_all is the
  same inert field. The flop-file valid array that L1I-6 relies on
  IS emitted with cleared_on_reset, so the storage is right and only
  the port is missing.

- pa_bits 32 AGAINST va_bits 39. The pacino topology declares
  va_bits 39 and pa_bits 32 and nothing checks the pair. Under Sv39
  a 32-bit physical address is small once MMIO is placed alongside
  DRAM, which is L1I-U1's own argument for 36. Flagging it here
  because it is a system-level RVA23 sizing question, not an l1i
  one, and because S5 is what would make it visible.

- NO PARITY AND NO ECC ANYWHERE IN THE MODEL. TD-L1I-5 records this
  as absent from the schema rather than declined, and that is
  correct: neither the array_storage object
  (caches.schema.json:794-825) nor anything else carries an
  error-detection field. Not RVA23-mandated for an L1I, but it is a
  gap in the tool and not only in the l1i node.

- SECTION 4.3 R3 IS SAFE. The C extension's 2-byte fetch boundary is
  pushed to the IFU by R1's line-aligned request, and the emitted
  L1I already addresses by line base (l1i_line_base). No gap.

---

## Deferred Work

Everything in Problem 4. This task proposes and changes nothing.

Suggested next tasks, in the order Problem 4 gives:

```
  1  CONFIGURATION. G1 through G4 in one change, with the two
     existing test edits named in Problem 4. Costs nothing, needs no
     tool change, and gets the geometry and the I-side link shape
     right before any emitter work starts.
  2  E1. The 512-bit package break. One guarded expression plus an
     Emit-suite text assertion. Small, and it is what makes G4's
     512-bit link mean anything.
  3  S2 plus its C++ half. A read-only custom link.
  4  E2 + E3 + E4 as ONE task. Outstanding requests, request ids and
     the MSHR file. The largest item by a wide margin.
  5  E7. The maintenance port. Independent of 4 and required by
     RVA23.
  6  E5, E6.
  7  S1 + E8. Prefetch, which needs 4 to exist first.
  8  S4, S5. Model corrections with no emitted consequence today.
```

Two items are the PA's, not an IA's:

```
  - icache_decisions.md 6f, the L1I-9 against 5.2 contradiction. It
    is a decision about the core response granularity and it also
    touches L1I-14
  - icache_decisions.md 6a, the missing L1I-11
```

---

## Other Notes

- THE TOOL ALREADY REPORTS ITS OWN GAP, and reports it better than
  this assessment could have. unconsumed.log is derived, not
  maintained, and features.log carries a third state that
  unconsumed.log does not: a field that IS read but only shapes
  emitted text. `mshrs` is that state, and the distinction between
  "no stage reads it" and "read, and it moves nothing observable"
  is exactly the C6 distinction the prompt asked for. Reading those
  two logs first would have shortened this task considerably.

- THE GEOMETRY STAGE IS THE PART THAT IS FINISHED. geometry.cpp
  computes the target decomposition correctly today, corroborates
  the bank field against an independently derived sets_per_bank,
  refuses to guess when the reading is ambiguous (word granularity
  is left unresolved WITH A REASON rather than approximated), and
  has a negative fixture for each of its six rules. Nothing in
  Problem 4 touches it. The distance between that stage and the
  emitter is the whole of Problem 1's answer.

- THE NEGATIVE-FIXTURE DISCIPLINE IS THE THING TO PRESERVE. One
  fixture per diagnostic, each producing EXACTLY ONE diagnostic, all
  cut from one clean base that must produce none. Every schema item
  in Problem 4 has been given its fixture and its pattern for that
  reason.

- BACKGROUND FACT 1 IS CONFIRMED. The geometry negative fixtures do
  enforce the geometry rules: neg_vipt_alias, neg_tag_bits,
  neg_banks_not_divide, neg_sets_not_pow2, neg_sets_not_integer and
  neg_capacity_not_pow2 all exist and all assert their T-8 code
  (test_negative.cpp:249-281). None of the target geometry values is
  refused, so no Problem 3 row returns REJECTS on a geometry rule.

- BACKGROUND FACT 2 IS NOT CONFIRMED. misc/example_pacino_icache.json
  is not an instruction-cache configuration the current tool can
  read. See the end of Problem 6.

---

## Files Modified

- none

Build artifacts and dependency checkouts, created by the permitted
build and listed for completeness. All are gitignored or are
submodule working trees; no tracked file changed.

- tools/cachegen/cli/obj/
- tools/cachegen/cli/bin/cgen
- tools/cachegen/cli/bin/cgen_tests
- tools/cachegen/tools/jnutils/
- tools/cachegen/tools/json-schema-validator/
- tools/cachegen/tools/googletest/

:: RESULTS:END ::

:: CONTEXT:START ::

```
 FILE:    context-report.md
 SOURCE:  session context measurement, INFRA-012
 STATUS:  WORKING
 UPDATED: 2026-08-28
 CONTACT: Jeff Nye
```

# Context Usage Report

Measured at the end of the INFRA-012 session.

```
  model     claude-opus-5[1m]
  used      231.1k of 1m tokens
  Ctx %     23
  free      768.9k  (76.9%)
```

## By category

| Category                | Tokens | Pct   |
|-------------------------|--------|-------|
| Messages                | 193.6k | 19.4% |
| System tools            | 26.5k  | 2.6%  |
| System tools, deferred  | 16.4k  | 1.6%  |
| Memory files            | 4.5k   | 0.5%  |
| System prompt           | 4k     | 0.4%  |
| Skills                  | 2.6k   | 0.3%  |
| MCP tools, deferred     | 1.5k   | 0.1%  |
| Free space              | 768.9k | 76.9% |

Messages is the task itself. Everything else is fixed overhead and
totals 37.5k, so INFRA-012 cost 193.6k of the 231.1k.

## Memory files

| Type    | Path                     | Tokens |
|---------|--------------------------|--------|
| Project | CLAUDE.md                | 4.1k   |
| AutoMem | MEMORY.md, see note      | 369    |

AutoMem path: ~/.claude/projects/
-home-jeff-Development-jeffnye-gh-pacino/memory/MEMORY.md

## Skills loaded

| Skill                    | Source   | Tokens |
|--------------------------|----------|--------|
| run                      | Project  | ~20    |
| dataviz                  | Built-in | ~380   |
| claude-api               | Built-in | ~360   |
| design                   | Built-in | ~340   |
| code-review              | Built-in | ~270   |
| update-config            | Built-in | ~240   |
| artifact-capabilities    | Built-in | ~210   |
| claude-in-chrome         | Built-in | ~180   |
| schedule                 | Built-in | ~130   |
| loop                     | Built-in | ~120   |
| keybindings-help         | Built-in | ~80    |
| artifact-diagramming     | Built-in | ~70    |
| artifact-design          | Built-in | ~70    |
| fewer-permission-prompts | Built-in | ~60    |
| simplify                 | Built-in | ~60    |
| security-review          | Built-in | ~30    |
| init                     | Built-in | ~20    |

Only `run` was invoked. The rest are listed descriptions, loaded on
demand.

## MCP tools

Six, all deferred and none called: Gmail, Google Calendar and Google
Drive authenticate / complete_authentication pairs. 1.5k total.
:: CONTEXT:END ::

