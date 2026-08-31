<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | TOOLS-005               |                          |
| Date         | 2026.09.02              |                          |
| Module       | cachegen, l1i node      | waiver, see Constraints  |
| Run time     | 53m.46s                 |                          |
| Ctx %        | 40%                     |                          |
| Model        | claude-opus-5[1m] normal |                         |
| Resume sha   | 4f1e23b9-3df8-4e62-afba-7acefa8c65cc |             |
| PA session   | 068                     |                          |

Task:   [ ] experiment  [X] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Mode:   [X] automated   [ ] manual          [ ] interactive
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview

Finish the non-blocking L1I. TOOLS-004 built the port protocol and
the MSHR file; the machine behind them is still blocking.

Three things, all in the emitter:

1. The bank control is pipelined. One access per cycle.
2. Hit latency comes from read_latency_cycles.
3. Sixteen fills in flight on the memory side.

Maintenance is OUT OF SCOPE.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion

## Claude.code Console Output

TOOLS-005 is done. Everything green, nothing regressed.

  What was built

  The l1i bank control is a pipeline now, not a state machine. It takes one
  access per cycle and answers a hit read_latency_cycles after acceptance — the
  number comes from timing/read_latency_cycles and timing/tag_compare_stage
  against the tag array's declared read port, not from a literal. A miss reports
  its line and its victim way in the compare stage and leaves; the MSHR file
  remembers it. The memory master has no state machine at all: channel A is
  straight through, channel D is reassembled per source, one partial line per
  register.

  Measured, from the emitted testbench

  ┌──────────────────────────────┬─────────────────────┬───────────────────┐
  │                              │       before        │       after       │
  ├──────────────────────────────┼─────────────────────┼───────────────────┤
  │ hits per cycle on a hit      │ 0.4 (4 in 10        │ 1.0 (4 in 4)      │
  │ stream                       │ cycles)             │                   │
  ├──────────────────────────────┼─────────────────────┼───────────────────┤
  │ hit latency                  │ 4 cycles            │ 2 =               │
  │                              │                     │ L1iReadLatency    │
  ├──────────────────────────────┼─────────────────────┼───────────────────┤
  │ fills in flight              │ 1                   │ 16 = L1iMshrs     │
  └──────────────────────────────┴─────────────────────┴───────────────────┘

  Counts — cachegen suite 97 → 108, l1i 39 → 67, every other node unchanged, 0
  lint warnings everywhere, every Makefile target run.

  Three things worth your attention

  1. The l2 is the bottleneck end. Its up_i_slv is a four-state machine holding
     one A at a time. It keys d_source correctly, so nothing is broken, but the
     l1i's sixteen fills serialise there. Closing it needs a schema field saying
     how many transactions a TileLink slave accepts (nonblocking() returns
     false for TL links today) plus the l2 getting this pipelined control. Both
     outside an l1i-scoped task. The l2 is untouched, 15/15.
  2. The timing check applies only where the pipeline is emitted. l1d declares
     read_latency_cycles 3 with same_cycle against a registered read, and l2
     declares 12; both would be refused if the check were unconditional. So
     those two fields have left unconsumed.log for l1i (74 → 72 unconsumed) and
     are still on it for l1d, l2 and mem. E5 is closed for l1i, not everywhere —
     you may want it reworded rather than closed.
  3. No schema and no configuration file changed. The waiver allowed both;
     neither was needed. The fields were already declared and carried — what was
     missing was an emitter that read them.

  Each of T11–T16 was confirmed to fail against the pre-task RTL by reverting
  rtl_cache.{cpp,h} to HEAD and keeping the testbench half: 52 passed, 14
  failed, at least one failing check in every one of the six. Two checks inside
  T15/T16 pass both ways and I've said so in Results Capture rather than
  counting them.

  Status in the header is left unset — that field is outside the RESULTS
  markers, and the only header field I'm permitted to write is Model.



## My Assessment

This appears complete.

## Claude.ai Assessment

Complete. All three requirements measured, not asserted.

	before	after	source
hits/cycle	0.4	1.0	T11
hit latency	4	2 = L1iReadLatency	T12
fills in flight	1	16 = L1iMshrs	T14

T11–T16 each confirmed to fail against the pre-task emitter by reverting rtl_cache.{cpp,h} to HEAD and keeping the testbench: 14 failures, at least one in every test. The two checks that pass both ways are named and excluded rather than counted.

Three things needing your attention

The l2 is now the bottleneck. l2_up_i_slv holds one A at a time. Sixteen fills are real at the l1i boundary and serialise at the l2, so end-to-end miss throughput is one. The IA flags this correctly under RVA23 risks: the front end sustaining 8 instructions/cycle depends on the l2 number, not the l1i number.

L1I-23 says "sixteen fills may be in flight." It's satisfied at the boundary it names and not achieved in the system. That's a specification question — whether L1I-23 is an L1I property or a system property.

E5 is closed for l1i only. The timing fields shape a pipeline; l1d and l2 have none, so the fields are still inert there. The IA suggests rewording E5 rather than closing it. Agreed — it's an emitter-wide statement and only one node moved.

Two replacement-quality consequences, reported not hidden. Two accesses to one set in consecutive cycles both read pre-update PLRU state; two outstanding misses to one set may pick the same victim, second fill overwriting the first. Both requesters get their line, so not a correctness fault. Worth recording as debt rather than leaving in Results Capture.

Smaller

No schema and no configuration changed — the fields were already declared and carried; only the emitter was missing. That's the cleanest possible form of this task.

NonBlocking.TheMemorySideSourceComesFromTheInFlightState rewritten rather than deleted when the design it asserted moved.

The tag_compare_stage next_cycle reading is an assumption stated explicitly: the cycle after the array read was issued, not after its output. The other reading makes read_latency_cycles 2 unbuildable. Worth confirming that's what you meant in L1I-5.

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
TOOLS-005

## Context Loaded
@planning/arch/icache_decisions.md
@planning/interfaces/l1i_ifu_interfaces.md
@prompts/TOOLS-004.md
@tools/cachegen/CLAUDE.md
@tools/cachegen/planning/schema/caches.schema.json
@tools/cachegen/planning/schema/links.schema.json
@tools/cachegen/testcases/pacino/pacino_caches.json
@tools/cachegen/testcases/pacino/pacino_links.json
@tools/cachegen/cli/src/rtl_cache.cpp
@tools/cachegen/cli/src/rtl_pkg.cpp
@tools/cachegen/cli/src/rtl_tb.cpp
@tools/cachegen/cli/src/link_sig.cpp

## Context Comments

READING UNDER THESE DIRECTORIES IS PERMITTED:

```
  tools/cachegen/cli/inc/
  tools/cachegen/cli/src/
  tools/cachegen/cli/tb/
  tools/cachegen/output/
  planning/
```

Directory listing anywhere in either tree is permitted.

DO NOT READ tools/cachegen/examples/ or
tools/cachegen/docs/pacino_cache.md.

TOOLS-004 IS THE IMMEDIATELY PRIOR TASK and its Results Capture
names what it built, what it left and where. Read it before the
source.

output/ IS GENERATED AND GITIGNORED. Nothing in it is evidence of
anything until this session emits it. It may be absent, or stale
from a run that crashed, or left over from a run whose source
changes were reverted -- git status will not tell you, because it
is ignored. REQUIREMENT 0 rebuilds it. Do not read a file under
output/ before then and do not treat one found there as what the
committed emitter produces.

READING UNDER output/ AFTER REQUIREMENT 0 IS EXPECTED. The
emitted l1i node is the subject of every problem below.

THE SCOPE IS THE l1i NODE. l1d, l2, mem, ifu, lsu and pacino must
continue to emit, lint and pass.

## Hypothesis

TOOLS-004 delivered the port protocol and stopped at the bank
boundary. Sixteen requests are accepted and answered out of order,
but each bank serves one at a time and the memory side fills one
line at a time, so the design is a queue in front of a blocking
cache.

Nothing in the specification changed to make this true. L1I-5 has
stated one request per cycle pipelined, and two-cycle latency, since
the document was written. What changed is L1I-23, which states the
fill count that the MSHR count always implied.

## Background

pacino is an 8-issue RVA23 out-of-order processor. Its BPU and FTQ
are built; the IFU is unbuilt. The L1I is emitted by cachegen.

TOOLS-004 built: the second core link type, the 512-bit port, the
schema for read-only links, error return, response handshake and
request qualifiers, a sixteen-entry MSHR file with four targets, and
five emitted tests proving the port protocol.

TOOLS-004 did NOT build: a pipelined bank control, a hit latency
derived from configuration, or more than one fill in flight. Its
Results Capture says so under "WHAT SURVIVED" and in Deferred Work.

That gap is not the IA's. The TOOLS-004 prompt's acceptance list was
the port protocol and did not name L1I-5 or the fill count.

## Binding Previous Decisions

1. THE SPECIFICATION IS FIXED. Where the tool cannot express
   something, REPORT IT; do not change the specification to fit.
   icache_decisions.md and l1i_ifu_interfaces.md are READ-ONLY.

2. THE THREE REQUIREMENTS, each already in the specification:

```
     L1I-5   Hit THROUGHPUT is one request per cycle, pipelined.
     L1I-5   Hit latency is 2 cycles, tag compare in the cycle
             after the array read. The configuration says this as
             read_latency_cycles 2 and tag_compare_stage
             next_cycle, and both are inert today
     L1I-23  SIXTEEN FILLS MAY BE IN FLIGHT, one per MSHR.
             a_source carries the MSHR index, d_source names the
             fill it answers, D beats may return in any order
```

3. THE PORT PROTOCOL IS BUILT AND MUST NOT REGRESS. Every IF- rule
   TOOLS-004 implemented stays true, and its five emitted tests
   T6 through T10 stay green. In particular IF-13, one response
   per cycle, and IF-14, never in the cycle the request was
   accepted, both survive a pipelined hit path.

4. MAINTENANCE IS OUT OF SCOPE. Sections 10 and 11 of
   l1i_ifu_interfaces.md, S8, TD-IF-4 and E7.

5. L1I-U7 IS OPEN AND IS NOT THIS TASK'S. Where the L1I-22 reserve
   is declared, link or node, is a PA decision. Leave it where
   TOOLS-004 put it.

## Specific Requirements

Problems, not procedure. Method, ordering and decomposition are
yours, after Requirement 0.

REQUIREMENT 0 -- REBUILD THE BASELINE. DO THIS FIRST.

```
  git -C tools/cachegen clean -xfd output
  build cli/, emit the pacino configuration into output/
```

THE CLEAN IS NOT OPTIONAL AND -x IS THE POINT. output/ is
gitignored, so an ordinary clean leaves it and git status reports
nothing. A previous run that was reverted, or that crashed, leaves
RTL there that no emitter on disk produces.

Then run the cachegen unit suite, and lint and run every emitted
node. Those figures are the BEFORE column of Problem 5 and the
pre-task emitter Problem 4 measures against.

If the rebuilt tree does not match TOOLS-004's reported counts --
97 suite, and ifu 4, lsu 3, l1i 39, l1d 15, l2 15, mem 4,
pacino 22 -- stop and report. That is a real disagreement between
the committed emitter and the committed record, and it is not
this task's to work around.

PROBLEM 1 -- THE PIPELINED BANK.

The emitted control is a blocking FSM: C_IDLE through C_DONE,
req_ready in C_IDLE only, one address latched. TOOLS-004 left it
untouched and reported so.

Replace it with a pipeline that accepts one access per cycle.
L1I-5.

What must be true:

```
  throughput   a bank accepts a new access every cycle while it is
               not stalled, and a hit does not block the access
               behind it
  latency      a hit answers read_latency_cycles after acceptance.
               The number comes from the CONFIGURATION, not from a
               literal in the emitter
  tag compare  tag_compare_stage next_cycle means the compare is in
               the stage after the array read. same_cycle is the
               other value and l1d declares it, so this is a
               branch, not a rewrite
  a miss       does not stall the pipeline. It allocates or merges
               in the MSHR file and the pipeline continues
  a fill       writing the array does not silently drop an access
               in the same cycle. Say what wins and enforce it
  ordering     IF-13 and IF-14 still hold at the core boundary
```

READ THE ARRAYS BEFORE DESIGNING THE PIPELINE. `<n>_meta_array` and
`<n>_data_array` declare registered or combinational read per the
storage configuration, and the stage count that produces
read_latency_cycles depends on which. A pipeline that assumes the
wrong one is off by a cycle and every test still passes.

THE l1d AND l2 NODES USE THE SAME EMITTER. They are blocking today
and must remain correct. Whether they become pipelined too is your
call and must be reported either way; what is not acceptable is a
pipelined l1i and a broken l1d.

PROBLEM 2 -- LATENCY FROM CONFIGURATION.

read_latency_cycles and tag_compare_stage are on unconsumed.log for
every cache node and shape nothing. INFRA-012 found this as E5,
TOOLS-003 confirmed it, TOOLS-004 reported it unchanged.

Make them shape the emitted pipeline. When this lands they leave
unconsumed.log, and Featnames.NoTestClaimsAnUnconsumedFeature stops
being the reason no test claims them.

STATE THE LEGAL RANGE. Not every value can be built: a
read_latency_cycles that is shorter than the array read plus the
compare is not implementable, and one that is longer needs a stage
that does nothing. Report the range the emitter supports and reject
the rest with a diagnostic rather than emitting something that does
not match the number.

PROBLEM 3 -- SIXTEEN FILLS IN FLIGHT.

`<n>_mem_mst` is a blocking state machine: one fill, latched at
M_IDLE, a_source naming it. L1I-23 requires sixteen.

What must be true:

```
  channel A    a new fill may issue every cycle that the link
               accepts one, up to sixteen outstanding
  a_source     the MSHR index of the fill, as TOOLS-004 already
               made it
  channel D    beats are keyed by d_source and may arrive for any
               outstanding fill in any order. A beat names the fill
               it answers and nothing else correlates them
  beats        a line is two beats on this link. Two fills may
               interleave their beats; the master must reassemble
               per source, not per arrival order
  completion   an MSHR retires when ITS line is complete, not when
               the master is idle
```

THE SOURCE WIDTH IS ALREADY 4 BITS. TOOLS-004 moved
tl_l1i_l2.source_bits 3 to 4 for exactly this. Confirm it is still
4 and that the l2 end agrees.

THE l2 IS THE OTHER END. It must accept sixteen outstanding A
requests and return D beats keyed by source. Report whether it does
today and what changes if it does not; the l2's own suite must stay
green either way.

PROBLEM 4 -- THE TESTBENCH SHOWS IT.

T6 through T10 prove the port protocol. They cannot show any of
problems 1 through 3: a queue in front of a blocking cache passes
all five.

Add tests that fail on the TOOLS-004 design. At minimum:

```
  a hit stream       back-to-back hits answered one per cycle,
                     which a blocking bank cannot do
  the hit latency    a hit answers exactly read_latency_cycles
                     after acceptance, measured, not assumed
  hit under miss     a hit to a warm line answers while a miss to
                     a different line is outstanding, with no
                     dependence on the miss completing
  fills in flight    more than one fill outstanding at the same
                     time, counted at the memory side
  interleaved beats  two fills whose beats arrive interleaved, both
                     reassembled correctly
  out-of-order fill  a later fill completing before an earlier one,
                     and the right MSHR retiring
```

EACH TEST MUST FAIL AGAINST THE PRE-TASK EMITTER, which is the
tree Requirement 0 rebuilt and nothing else. Say for each one
whether you confirmed that, and how. A test that passes both
before and after is not testing this task.

PROBLEM 5 -- THE WHOLE TREE.

Cachegen unit suite before and after. Lint and run for every emitted
node before and after. Every Makefile target enumerated and run, as
TOOLS-004 did.

No node regresses in pass count or warning count.

PROBLEM 6 -- WHAT DID NOT FIT.

Report anything in the specification this task could not emit, with
the reason, and anything in the specification found wrong.

REPORT THE THROUGHPUT THE DESIGN ACTUALLY ACHIEVES, measured from
the emitted testbench, not derived: hits per cycle on a hit stream,
and fills in flight on a miss stream. The numbers, not the intent.

## Constraints

- WAIVER, TOOLS-005 ONLY. This task MAY write:
    tools/cachegen/planning/schema/*.json
    tools/cachegen/testcases/pacino/*.json
    tools/cachegen/cli/src/*, tools/cachegen/cli/inc/*
    tools/cachegen/cli/tb/*
  It covers this task only. It is NOT precedent and does NOT
  propagate. Every file under planning/, pa_handoffs/ and docs/ in
  BOTH trees is READ-ONLY, including tools/cachegen/planning/arch/.

- icache_decisions.md AND l1i_ifu_interfaces.md ARE READ-ONLY.

- MAINTENANCE IS OUT OF SCOPE.

- NO NODE REGRESSES. l1d, l2, mem, ifu, lsu and pacino lint and run
  before and after, and T6 through T10 stay green.

- DO NOT MOVE THE L1I-22 RESERVE. L1I-U7 is the PA's.

- The riscv-codesign bpu and ftq suites are not in scope and must
  not be run. No RTL under rtl/ is touched.

- REGENERATING THE OUTPUT TREE IS REQUIRED, at Requirement 0 and
  again after the change. It is gitignored and derived; deleting
  and rebuilding it loses nothing.

## Deliverables

- tools/cachegen source, schema, configuration and fixtures as
  problems 1 through 4 require
- the regenerated output tree
- Results Capture filled in below, in this file:
  prompts/TOOLS-005.md

Fill in every section. Report the suite counts and the per-node
lint and run counts before and after, the measured throughput and
fill-in-flight figures, and for each new test whether it was
confirmed to fail against the pre-task emitter.

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary

The l1i bank control is now a PIPELINE and the memory side holds
one fill per miss handling register. A hit is accepted every cycle
and answered read_latency_cycles later; sixteen fills may be
outstanding, keyed by source, reassembled per source, and completed
in any order.

Problems 0 through 6 are done. Nothing regressed.

MEASURED, from the emitted testbench in this session, not derived:

```
  hits per cycle on a hit stream    4 answers in 4 cycles, 1.0/cycle
  hit latency, accept to answer     2 cycles, == L1iReadLatency
  fills in flight on a miss stream  16, == L1iMshrs
  interleaved beats                 observed, nb_ilv > 0
```

Counts, all from runs in this session:

```
  cachegen unit suite     before   97 passed  0 failed
                          after   108 passed  0 failed

  emitted lint, per node  before  0 warnings, 0 errors on all 7
                          after   0 warnings, 0 errors on all 7

  emitted run, per node   before          after
    ifu                    4 / 0           4 / 0
    lsu                    3 / 0           3 / 0
    l1i                   39 / 0          67 / 0
    l1d                   15 / 0          15 / 0
    l2                    15 / 0          15 / 0
    mem                    4 / 0           4 / 0
    pacino                22 / 0          22 / 0
```

REQUIREMENT 0 MATCHED THE RECORD EXACTLY. `git -C tools/cachegen
clean -xfd output` removed the directory entirely, cli/ was rebuilt
from `make clean`, and the rebuilt tree gave 97 suite and ifu 4,
lsu 3, l1i 39, l1d 15, l2 15, mem 4, pacino 22 with zero lint
warnings. Those are the BEFORE column above.

Every Makefile target of every emitted node was enumerated and run:
`lint`, `build`, `run` on all seven, plus `units` on pacino.
`default` is `run` and `all` is `lint build`, so neither adds a
target; `clean` was not run, it destroys the tree under test. The
cachegen Makefile's targets are `all`, `only`, `test` and `run`;
all four were run.

NO SCHEMA AND NO CONFIGURATION FILE CHANGED. The waiver allowed
both and neither was needed: read_latency_cycles and
tag_compare_stage were already declared and already carried, and
what was missing was an emitter that read them.

## Test Matrix (testbench sessions only, omit otherwise)

`l1i_tests.svh` gained T11 through T16, 28 checks. Every address
and every count below is derived by cgen from the pacino
configuration, not a literal in the emitter. THE STRIDE IN EACH
GROUP IS TWO LINES, so every address in one group lands in the SAME
bank: a hit under a miss in a different bank proves nothing about a
pipeline, and T7 already showed that case.

```
T11 a hit stream, one answer per cycle
    Rules   L1I-5 hit throughput, IF-13
    Setup   4 lines at 0x000a0000 + k*128, all bank 0, warmed by a
            completed read each
    Stimulus  nb_req back to back, one per cycle, identifiers 0..3
    Expected  all 4 accepted one per cycle, all 4 answered, the
            answers on CONSECUTIVE cycles, and each one exactly
            ReadLatency after its own acceptance
    Pass    nb_rsp[3] - nb_rsp[0] + 1 == 4, nb_rsp[k] ==
            nb_rsp[k-1] + 1 for every k, and nb_rsp[k] - nb_acc[k]
            == ReadLatency for every k
    Measured  4 answers in 4 cycles

T12 the hit latency is read_latency_cycles, measured
    Rules   L1I-5 hit latency, E5
    Setup   0x000a4000 warmed by a completed read
    Stimulus  one nb_req on identifier 5
    Expected  the answer exactly ReadLatency cycles after the
            acceptance. ReadLatency is the configuration's number
            carried into l1i_pkg, so the test compares the design
            against what was asked for
    Pass    nb_rsp[5] - nb_acc[5] == ReadLatency, and the package's
            own CmpStage + PipePad + 1 == ReadLatency
    Measured  2 cycles

T13 a hit under a miss, in the SAME bank
    Rules   L1I-5, L1I-12, IF-12
    Setup   0x000a8000 warmed, 0x000ac000 cold, both bank 0, which
            the test asserts rather than assumes. tb_hold high, so
            the miss cannot complete
    Stimulus  identifier 6 to the COLD line first, identifier 7 to
            the warm line one cycle later
    Expected  identifier 7 answered while 6 is still outstanding,
            and at the hit latency rather than the miss's. Release
            the hold and 6 follows
    Pass    nb_seen[7] with !nb_seen[6], nb_rsp[7] - nb_acc[7] ==
            ReadLatency, then nb_ord[7] < nb_ord[6]

T14 Mshrs fills in flight at once
    Rules   L1I-23, L1I-12
    Setup   tb_dhold high, so channel A is taken and no fill can
            complete. 16 cold lines at 0x000b0000 + k*64
    Stimulus  16 nb_req, identifiers 0..15, then 4*Mshrs cycles
    Expected  every request accepted, 16 fills outstanding at the
            memory side at once, none of them answered. Release
            channel D and all 16 come back
    Pass    nb_pk == Mshrs and nb_n == 0, then all 16 answered
    Measured  16 fills in flight

T15 two fills whose beats interleave
    Rules   L1I-23 beats, R2
    Setup   tb_dhold high then released with tb_ilv high, so the
            responder hands out beats round robin. Two cold lines
            at 0x000b8000 and 0x000b8080, one bank
    Stimulus  identifiers 1 and 2, one line each
    Expected  both fills outstanding together, their beats
            interleaved, and BOTH lines reassembled correctly. The
            expected line comes from tb_line(), emitted from the
            same place the responder's own seed function is, so a
            line reassembled in the wrong order fails
    Pass    nb_pk == 2, nb_ilv > 0, nb_data[1] == tb_line(first)
            and nb_data[2] == tb_line(second)

T16 a later fill completes before an earlier one
    Rules   L1I-23 d_source, L1I-23 completion, IF-12
    Setup   tb_dhold high then released with tb_rev high, so the
            responder serves the HIGHEST numbered source first. Two
            cold lines at 0x000bc000 and 0x000bc080, one bank.
            Identifier 1 takes register 0 and issues first,
            identifier 2 takes register 1 and issues second
    Stimulus  identifier 1 then identifier 2
    Expected  the fill issued SECOND returns first, the register
            that asked for each line is the one that gets it
    Pass    nb_seen[2] with !nb_seen[1], nb_ord[2] < nb_ord[1],
            nb_data[1] == tb_line(first) and nb_data[2] ==
            tb_line(second)
```

EACH ONE WAS CONFIRMED TO FAIL AGAINST THE PRE-TASK EMITTER. The
experiment: `cli/src/rtl_cache.cpp` and `cli/inc/rtl_cache.h` were
reverted to HEAD and nothing else was, so the RTL is the tree
Requirement 0 rebuilt and the testbench is this task's. The tool
rebuilt, the pacino configuration was emitted to a scratch tree,
and the l1i suite was run. Result: 52 passed, 14 FAILED, and every
one of T11 through T16 has at least one failing check.

```
  T11  MEASURED hits per 4 cycles got 0xa, want 0x4     FAIL
       a hit stream is answered one per cycle           FAIL
       and none of them waited on the one in front      FAIL
  T12  MEASURED hit latency got 0x4, want 0x2           FAIL
  T13  the hit was answered under the miss              FAIL, timed
                                                        out at the
                                                        cg_limit
       and at the hit latency, not the miss's           FAIL
       and the miss completed after it                  FAIL
  T14  MEASURED fills in flight got 0x1, want 0x10      FAIL
       and not one of them had completed                FAIL
  T15  two fills are outstanding together got 0x1       FAIL
       the beats of the two did interleave              FAIL
  T16  both fills are outstanding together got 0x1      FAIL
       before the one issued first                      FAIL
       and the first came back after it                 FAIL
```

Two checks inside T15 and T16 pass on the pre-task design and are
reported as such rather than counted: "the first line was
reassembled correctly" and its pair. A responder that returns one
line at a time cannot misassemble one, so those two checks only
carry weight beside the interleave and out of order checks that
fail. They are the CONSEQUENCE the test is protecting, not the
behaviour it distinguishes.

The pre-task figures also answer the throughput question directly:
the pre-task design answers 4 back-to-back hits in 10 cycles, 0.4
per cycle, at 4 cycles of latency each, with 1 fill in flight.

The tool side gained `cli/tb/test_pipeline.cpp`, 11 tests asserting
what the SystemVerilog cannot check about itself: that the
pipelined control is not a state machine, that the two timing
fields reached the package, that the emitted pipeline is built from
those numbers rather than literals, that the master holds one fill
per register, that the file issues one fill a cycle and does not
reissue, that one scan answers hits and fills alike, that the
lookup leaves in the cycle the request is accepted, and that both
ends of the supported latency range are refused with a diagnostic
that names the shortest hit that can be built. Each structural test
also asserts the BLOCKING node did NOT get the same treatment, so
the branch is proved to be a branch.

## What was delivered

PROBLEM 1, THE PIPELINED BANK. `<n>_ctrl` on a pipelined node is a
different module, not a variant: `RtlCache::ctrl_pipe`. The
blocking `ctrl` is untouched and still emitted for l1d and l2.

THE ARRAYS WERE READ FIRST. `l1i_meta_array` and `l1i_data_array`
both declare a REGISTERED read port, so a set presented in a cycle
has its output in the NEXT one. The stage count follows from that
and not from an assumption:

```
  stage 0         the accepted access presents its set to both
                  arrays. The read is issued every cycle; the
                  stage below says whether the result belongs to
                  anything
  stage CmpStage  the tag compare, the hit way and the victim.
                  CmpStage is 1 because tag_compare_stage is
                  next_cycle, which is what puts the compare in
                  the cycle AFTER the array read was issued and
                  therefore in the cycle its output arrives
  + PipePad       the hit answer leaves COMBINATIONALLY out of
                  stage CmpStage + PipePad
  + 1             the miss handling file registers it. That last
                  stage is the file's, not the bank's
```

Against the prompt's list of what must be true:

```
  throughput   req_ready is 1'b1 on this node and nothing takes it
               down. The only thing that can is the post reset
               walk, and the valid bits are cleared_on_reset here
               so no walk is emitted. A hit does not block the
               access behind it because a hit occupies no state
               the next access needs
  latency      accept at N, compare at N+CmpStage, answer out of
               the bank combinationally, registered by the file,
               response at N+ReadLatency. ReadLatency, CmpStage
               and PipePad are localparams in l1i_pkg derived from
               timing/read_latency_cycles and
               timing/tag_compare_stage. NO LITERAL IN THE EMITTER
               NAMES A DEPTH
  tag compare  a branch. next_cycle emits a register stage between
               the acceptance and the compare; same_cycle emits
               the compare on the access as it arrives and needs a
               combinational array read to be legal. l1d declares
               same_cycle and keeps the blocking control, so the
               branch is reachable and the value is checked
  a miss       leaves the pipeline in the compare stage. It
               reports its line, its register and the victim way
               the compare already had in front of it, and the
               access is gone. Nothing stalls. The register was
               allocated at the ACCEPTANCE, so the file has room
               for the report by construction and the report
               carries no ready
  a fill       both proceed. The arrays carry a read port and a
               write port, so the fill lands on the edge that ends
               the cycle and the access reads the set as it was
               before it. THE ACCESS IS NOT DROPPED AND THE FILL
               IS NOT DELAYED, and that is stated in the emitted
               comment. The one outcome that would be wrong, an
               access to the line being filled reporting a miss,
               is impossible because the file merges such a
               request onto the register that owns the line and
               stops merging on the same edge that writes the
               array. An assertion in l1i_ctrl says so rather than
               leaving it resting on that
  ordering     IF-13 holds: one response per cycle, from ONE scan.
               There is no second response path, and
               test_pipeline asserts rsp_valid is driven in
               exactly one place. IF-14 holds: the shortest
               ReadLatency the emitter accepts is 1, so an
               acceptance and its answer are never in one cycle,
               and the TOOLS-004 assertion that says so is still
               emitted
```

THE l1d AND l2 NODES ARE UNCHANGED AND STILL BLOCKING. That is a
decision, reported under Decisions below. Their emitted RTL is
byte for byte what it was; their suites are 15 and 15 as before.

PROBLEM 2, LATENCY FROM CONFIGURATION. read_latency_cycles and
tag_compare_stage now shape the emitted pipeline and have left
`unconsumed.log` for l1i. The report went from 74 unconsumed of 310
to 72.

THE LEGAL RANGE, and how each end is derived:

```
  array_stage  1 when the tag array declares a registered read
               port, 0 when it declares a combinational one
  CmpStage     1 when tag_compare_stage is next_cycle, 0 when it
               is same_cycle
  min          CmpStage + 1, the answer being registered after the
               compare
  max          8, stated. Every cycle beyond min is a stage that
               carries the answer and does nothing else, and the
               emitter stops adding them
```

REFUSED, each with a diagnostic naming the field:

```
  array_stage > CmpStage      T-11.tag_stage. A registered read
                              cannot be compared in the cycle its
                              address was presented
  read_latency < min          T-11.read_latency
  read_latency > 8            T-11.read_latency
```

For pacino's l1i, registered tag read and next_cycle, the range is
[2, 8]. Probed this session against the real configuration: 1
refused, 2 emitted, 8 emitted, 9 refused, and same_cycle refused,
each with the message naming the field and the shortest hit that
can be built. Two negative fixtures carry the two codes into the
suite.

THE PAD BRANCH WAS EXERCISED. A scratch configuration with
read_latency_cycles 4 emitted PipePad 2, linted clean with zero
warnings and ran 67 passed 0 failed, with the measured latency 4
and the measured throughput still one hit a cycle. The number
comes from the configuration and the design follows it.

The check runs where the pipeline is decided, which is emit. A
`--cmd=check` run does not build a node context and so does not
reach it; `driver.cpp` prints emitter diagnostics after the emit
stage, and the two codes were added to that list so a refusal
reaches the console instead of only the list.

PROBLEM 3, SIXTEEN FILLS IN FLIGHT.

```
  channel A    `<n>_mem_mst` on a pipelined node has no state
               machine. mreq_ready is mem_a_ready and mem_a_valid
               is mreq_valid, so a fill leaves in any cycle the
               file offers one and the link takes it. The file
               offers the lowest numbered register that has missed
               and has not been sent, one per cycle, and marks it
               sent so it is not offered again
  a_source     mem_a_source is 4'(mreq_src), the register index,
               driven straight from the file
  channel D    mem_d_ready is 1'b1. A beat is placed by
               mshr_t'(mem_d_source) and by nothing else
  beats        one partial line per register, f_buf[Mshrs]. A beat
               is written into its own source's buffer at its own
               source's beat count, so two fills interleaving
               their beats reassemble independently. T15
  completion   mrsp_valid rises when THAT source's last beat
               arrives, carrying mrsp_src, and the file sets
               e_got on the register it names. A register retires
               when its own line is complete. T16
```

THE SOURCE WIDTH IS STILL 4. `tl_l1i_l2.source_bits` is 4 in
`pacino_links.json`, unchanged by this task, and the l2's `up_i` is
the other end of that link so it moves with it: `l2_up_i_slv`
declares `up_i_a_source [3:0]` and `up_i_d_source [3:0]` in the
emitted tree.

THE l2 IS THE OTHER END AND IT DOES NOT ACCEPT SIXTEEN TODAY.
`l2_up_i_slv` is a four state machine, S_IDLE / S_REQ / S_RSP /
S_WDATA, with `up_i_a_ready` asserted only in S_IDLE and S_WDATA
and one `source_q` latched per transaction. It KEYS correctly, it
returns `d_source` from the request it is answering, but it holds
one A at a time. The l1i's sixteen fills therefore serialise at the
l2 in the pacino system, and the sixteen are provable only at the
l1i's own unit boundary, which is where T14 measures them.

What would change if the l2 accepted sixteen: the slave adapter
needs a per source record of the outstanding request rather than
one `source_q`, and the l2's own control needs to hold more than
one lookup, which is the same pipelined control this task built for
the l1i. The tool cannot express the first half today, because
`NodeCtx::nonblocking` reads `outstanding_requests` and
`read_data_return` off a CUSTOM link and returns false for a
TileLink one; there is no field on a TileLink link that says how
many transactions its slave end accepts. That is a schema addition
and an l2 change, both outside a task scoped to the l1i node. The
l2 is untouched and its suite is 15 passed 0 failed, unchanged.

PROBLEM 4, THE TESTBENCH. Covered in the Test Matrix above.

The responder was rewritten for a pipelined node,
`RtlTb::tb_mem_pipe`. It holds one pending fill per source rather
than one in total, and it takes four controls: tb_hold refuses
channel A, tb_dhold holds channel D so fills accumulate, tb_ilv
hands out beats round robin so two fills interleave, and tb_rev
serves the highest numbered source first so a later fill completes
first. With none of them set it serves the lowest numbered pending
fill and keeps the link until that line is done, so the ordinary
case is deterministic. A blocking node keeps the responder it had.

The collector gained nb_acc and nb_rsp, the cycle each identifier
was accepted and answered, so a latency is MEASURED. A memory side
monitor counts fills in flight at the link, their peak, and the
beats that arrived for one fill while another was part way through
its own line.

PROBLEM 5, THE WHOLE TREE. Counts at the top. No node regressed in
pass count or in warning count.

PROBLEM 6, WHAT DID NOT FIT. Under Deferred Work.

## Test Case Results

```
  cachegen unit suite           108 passed, 0 failed
  ifu_tb                          4 passed, 0 failed
  lsu_tb                          3 passed, 0 failed
  l1i_tb                         67 passed, 0 failed
  l1d_tb                         15 passed, 0 failed
  l2_tb                          15 passed, 0 failed
  mem_tb                          4 passed, 0 failed
  pacino_tb                      22 passed, 0 failed
  lint, every node                0 warnings, 0 errors
  build, every node               0 warnings, 0 errors
  pacino units                    every unit suite, as above
```

The l1i suite went from 39 to 67. The 39 that were there all still
pass and none was rewritten. The cachegen suite went from 97 to
108: 11 new in test_pipeline.cpp, and one existing test,
NonBlocking.TheMemorySideSourceComesFromTheInFlightState, was
rewritten rather than deleted because the design it asserted moved.
It asserted the source was LATCHED from one in flight register;
there is no longer one, so it now asserts the source is the
register the fill belongs to and that the file drives it and the
return names it back. The assertion moved with the design and did
not lapse.

## Assumptions made not explicit in the prompt

- THE LAST STAGE OF THE HIT PATH IS THE MISS HANDLING FILE'S. A
  bank that registered its own answer would put the response one
  cycle past read_latency_cycles, because the file has a register
  of its own between the bank and the port. The bank therefore
  presents a hit combinationally out of stage CmpStage + PipePad
  and the file's e_got register is stage ReadLatency. This is the
  one place the two modules are designed against each other rather
  than independently, and it is stated in both emitted files.

- THE BANK RETURNS A WHOLE LINE ON A HIT, not a word. The word a
  target asked for is selected in the file, where the offset each
  target arrived with is kept. On this node a word IS a line so
  the two are the same width, and the arrangement is what lets one
  register answer several targets at different offsets on a node
  where they differ. The emitter carries the per target offset
  only when a line is more than one word wide.

- A PIPELINED NODE IS A NON BLOCKING NODE THAT DOES NOT WRITE.
  `NodeCtx::pipelined` is `nonblocking() && one slave interface &&
  !has_writes() && !has_dirty()`. A writeback is a second array
  read and a second downstream request in the middle of the same
  access, and no field in the configuration says how those
  sequence against the accesses behind them. Such a node keeps the
  blocking control rather than getting a guess.

- tag_compare_stage next_cycle MEANS THE CYCLE AFTER THE ARRAY
  READ WAS ISSUED. It is read that way because that is what
  icache_decisions.md L1I-5 states, "tag compare in the cycle after
  the array read", against a registered array whose output arrives
  in exactly that cycle, and because it is the reading under which
  read_latency_cycles 2 is buildable. The other reading, one cycle
  after the array OUTPUT, would make the shortest hit on this
  geometry 3 cycles and the declared 2 unbuildable.

## Decisions made not explicit in the prompt

- l1d AND l2 STAY BLOCKING, and this is the answer the prompt
  asked for either way. Neither is a non blocking node: neither
  core link declares more than one outstanding request with an
  identifier keyed return, so neither has a miss handling file to
  put a pipeline in front of, and a pipelined control with nowhere
  to record a miss is not a design. l1d additionally writes and
  holds dirty lines, which the pipelined control does not carry.
  Their emitted RTL is unchanged and their suites are unchanged.

- THE TIMING CHECK APPLIES WHERE THE PIPELINE IS EMITTED. A
  blocking control reads neither timing field, so the emitter does
  not invent a range for it and does not refuse a declaration it
  never consumes. This matters: l1d declares read_latency_cycles 3
  with tag_compare_stage same_cycle against a registered tag read,
  and l2 declares 12, and both would be refused if the check were
  unconditional. The honest consequence is that both fields are
  still on unconsumed.log for l1d, l2 and mem, and they are.

- THE REPLACEMENT STATE MOVES IN THE COMPARE STAGE, on a hit and a
  miss alike, and that is the only writer of the port. Doing it
  when the fill lands instead would leave two writers of one port
  needing an arbiter no field describes, and the way it names is
  the way the fill will use. Two consequences, both reported
  rather than hidden: two accesses to one set in consecutive
  cycles both read the pre update state, and two outstanding
  misses to one set may pick the same victim way, in which case
  the second fill overwrites the first. Neither is a correctness
  fault, both requesters get the line they asked for; both are
  replacement quality.

- THE MISS REPORT IS AT THE COMPARE STAGE, not at CmpStage +
  PipePad. A pad stage delays the ANSWER, which is what
  read_latency_cycles measures; delaying the miss with it would
  add pad cycles to every fill for no reason the configuration
  gives.

- THE FILE'S READY NOW READS THE BANKS' READY, ANDed across all of
  them. It still reads no address: which bank a request needs is
  an address, and ready does not look at one, so it asks whether
  EVERY bank could take a lookup. On this node the banks' ready is
  a constant, because the valid bits are cleared on reset and no
  post reset walk is emitted. The path exists for a configuration
  whose valid bits are not.

- THE EXPECTED FILL CONTENT IS EMITTED TWICE FROM ONE PLACE. The
  responder needs the seed function and so does the test that
  checks a reassembled line against it, and they are separate
  modules. Both copies are written by the emitter from the same
  `shift` value and the same constant, so a test cannot predict a
  fill the responder would not give. Two copies in the output, one
  source in the tool.

- THE PIPELINED RESPONDER ANSWERS READS ONLY. A pipelined node
  does not write, so the store and the Put handling the blocking
  responder carries would be unreachable. It asserts on any opcode
  that is not a Get rather than dropping it.

- FOUR NEW CHECKS WERE ADDED THAT THE PROMPT DID NOT ASK FOR, each
  naming something the two halves of the design must agree about
  and nothing else enforced: an access must not miss on the line
  being filled in the same cycle, a bank's miss report must name
  the line its register holds, a fill must return for a register
  that asked for one, and a D source must name a register that
  exists when the source field is wider than the register count.
  None can fire on the emitted testbench; they exist so a later
  change cannot break the rule silently.

## RVA23 compliance risks and gaps noticed

- THE Zicbom AND Zifencei GAP IS UNCHANGED. Maintenance was out of
  scope by Constraints, so no node emits an invalidate port and
  L1I-18 still has no hardware. TD-L1I-8's maintenance half and
  section 14.3 E7 stand, untouched.

- No new compliance risk was introduced. The l1i is still read
  only on its core boundary and every request is still line
  aligned, checked at the boundary. The pipeline changes when an
  answer arrives, not what it contains.

- WORTH A NOTE FOR THE IFU. The miss throughput the IFU would be
  built against is now sixteen fills at the l1i's own boundary and
  one at the l2's, because the l2 end holds one A at a time. The
  front end sustaining 8 instructions a cycle depends on the
  second number, not the first.

## Deferred Work

- THE l2 END. Reported in full under Problem 3. It keys d_source
  correctly and holds one transaction. Closing it needs a schema
  field saying how many transactions a TileLink slave end accepts,
  and the l2 getting the pipelined control this task built. Both
  are outside a task scoped to the l1i node.

- THE FIELDS STILL INERT ON l1i, from unconsumed.log after the
  change: fill/beat_order, fill/bypass_to_upstream, inclusion, all
  four maintenance booleans, miss_handling/fill_buffer_entries,
  miss_handling/victim_buffer_entries, storage/way_access,
  storage/data_array_organization, three storage byte_enables, two
  storage cleared_on_reset, timing/emit_parameters. That is 17,
  against TOOLS-004's 19. The two that left are
  timing/read_latency_cycles and timing/tag_compare_stage, which is
  E5.

- READ_LATENCY_CYCLES AND TAG_COMPARE_STAGE ARE STILL INERT ON
  l1d, l2 AND mem. They shape a pipeline and those nodes have
  none. See Decisions.

- THE UPPER END OF THE RANGE IS A CHOICE, not a derivation. Eight
  is stated in the diagnostic and in `NodeCtx::MaxLatency` and
  nothing in the specification asks for it. A configuration that
  wants a deeper pipeline needs the constant moved and nothing
  else.

- MERGED TARGETS AT DIFFERENT OFFSETS are emitted but not
  exercised. A line is one word wide on this node, so the per
  target offset the file would keep is not emitted here. The
  branch exists for a node where a line is several words and no
  node in this configuration is one.

- MAINTENANCE, out of scope by Constraints. Sections 10 and 11 of
  l1i_ifu_interfaces.md, S8, TD-IF-4 and E7 are untouched.

- L1I-U7, where the L1I-22 reserve is declared, was NOT moved. It
  is on the qualifier declaration where TOOLS-004 put it.

## Other Notes

NOTHING IN EITHER PLANNING DOCUMENT WAS FOUND WRONG. What follows
is status that has changed under them. Both are read only here and
the PA drafts the amendment.

```
  icache_decisions.md, L1I-5
    APPLIED. Hit throughput is one request per cycle and hit
    latency is 2 cycles, both measured at the port in
    l1i_tests.svh T11 and T12, and both derived from
    read_latency_cycles and tag_compare_stage rather than from a
    literal.

  icache_decisions.md, L1I-23
    APPLIED at the l1i's own boundary. Sixteen fills in flight,
    a_source the register index, d_source keying the return,
    beats reassembled per source, returns in any order. Measured
    at 16 in T14. NOT applied end to end: the l2 holds one
    transaction, see Problem 3.

  icache_decisions.md 9, closing paragraph
    The count of node fields that reach no emitted logic drops by
    two more. read_latency_cycles and tag_compare_stage now reach
    emitted logic on l1i.

  l1i_ifu_interfaces.md 14.3
    E5 CLOSED for l1i. The two timing fields shape the emitted
    pipeline and have left unconsumed.log. They remain inert on
    l1d, l2 and mem, which have no pipeline; that is a narrower
    statement than E5 makes and the PA may want E5 reworded rather
    than closed outright.

  l1i_ifu_interfaces.md 3.1, the parameter table
    l1i_pkg gained L1iReadLatency, L1iCmpStage and L1iPipePad. The
    bp_defines_pkg column is unchanged and TD-IF-1 stands.

  l1i_ifu_interfaces.md, IF-13 and IF-14
    Both still hold on a pipelined hit path. IF-13 by
    construction, one response scan; test_pipeline asserts
    rsp_valid is driven in exactly one place. IF-14 by the
    shortest latency the emitter accepts being 1, with the
    TOOLS-004 assertion still emitted.
```

A NEW DIAGNOSTIC GROUP, T-11, was added to `diag_codes.h`:
T-11.read_latency and T-11.tag_stage, both Fixture, both with a
negative fixture under `cli/tb/fixtures`.

HOW THE TREE IS BUILT AND RUN is unchanged from TOOLS-004:

```
  emit   CGEN_ROOT=<cachegen>, so the master Vars.mk is found at
         $CGEN_ROOT/planning/tools/Vars.mk
  run    CGEN_ROOT=<pacino>, so the emitted
         VERILATOR=$(CGEN_ROOT)/tools/bin/verilator resolves.
         That is verilator 5.048
```

## Files Modified
- tools/cachegen/cli/inc/diag_codes.h
- tools/cachegen/cli/inc/node_ctx.h
- tools/cachegen/cli/inc/rtl_cache.h
- tools/cachegen/cli/inc/rtl_tb.h
- tools/cachegen/cli/src/driver.cpp
- tools/cachegen/cli/src/emitter.cpp
- tools/cachegen/cli/src/node_ctx.cpp
- tools/cachegen/cli/src/rtl_cache.cpp
- tools/cachegen/cli/src/rtl_pkg.cpp
- tools/cachegen/cli/src/rtl_tb.cpp
- tools/cachegen/cli/src/sv_file.cpp
- tools/cachegen/cli/tb/test_nonblocking.cpp
- tools/cachegen/cli/tb/test_pipeline.cpp
- tools/cachegen/cli/tb/fixtures/neg_read_latency/caches.json
- tools/cachegen/cli/tb/fixtures/neg_read_latency/links.json
- tools/cachegen/cli/tb/fixtures/neg_read_latency/ports.json
- tools/cachegen/cli/tb/fixtures/neg_read_latency/system.json
- tools/cachegen/cli/tb/fixtures/neg_tag_stage/caches.json
- tools/cachegen/cli/tb/fixtures/neg_tag_stage/links.json
- tools/cachegen/cli/tb/fixtures/neg_tag_stage/ports.json
- tools/cachegen/cli/tb/fixtures/neg_tag_stage/system.json
- tools/cachegen/output/ (regenerated, 85 files)

:: RESULTS:END ::

:: CONTEXT:START ::

# Context Usage

Context used: 40%

| Field  | Value              |
|--------|--------------------|
| Model  | claude-opus-5[1m]  |
| Tokens | 399.3k / 1m        |
| Used   | 40%                |
| Free   | 600.7k (60.1%)     |

## Estimated usage by category

| Category                | Tokens | Percent |
|-------------------------|--------|---------|
| System prompt           | 4.0k   | 0.4%    |
| System tools            | 20.3k  | 2.0%    |
| System tools (deferred) | 17.3k  | 1.7%    |
| MCP tools (deferred)    | 1.5k   | 0.1%    |
| Memory files            | 4.9k   | 0.5%    |
| Skills                  | 2.9k   | 0.3%    |
| Messages                | 367.3k | 36.7%   |
| Free space              | 600.7k | 60.1%   |

## Largest contributor

Bash tool results account for 158.8k tokens, 16% of the window and
43% of the message total.
:: CONTEXT:END ::

