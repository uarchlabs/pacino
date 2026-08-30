<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | TOOLS-004               |                          |
| Date         | 2026.09.01              |                          |
| Module       | cachegen, l1i node      | waiver, see Constraints  |
| Run time     | 44m.8s                  |                          |
| Ctx %        | 46%                     |                          |
| Model        | claude-opus-5 normal    |                          |
| Resume sha   | 83c34700-dfe0-4462-bd33-49e3ab3a7ed5 |             |
| PA session   | 068                     |                          |

Task:   [ ] experiment  [X] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Mode:   [X] automated   [ ] manual          [ ] interactive
Status: [ ] in-progress [X] complete        [ ] abandoned

# Task Overview

Make cachegen emit the non-blocking L1 instruction cache specified
by icache_decisions.md and l1i_ifu_interfaces.md.

Three layers: the pacino configuration, the schema, and the
emitter. The emitter is the bulk of it and the MSHR file is the
largest single piece.

Maintenance is OUT OF SCOPE.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion

## Claude.code Console Output

TOOLS-004 is complete. Everything green.

  What was built

  The emitted L1I is now non-blocking. cachegen gained a <n>_mshr module — 16
  registers, 4 targets each, sized from the configuration — sitting between the
  core adapter and the banks, replacing the slave-to-bank arbitration entirely
  on a node whose core link declares more than one outstanding request with an
  identifier-keyed response.

  The four schema gaps and S3 all closed, each with its consumer

  ┌─────┬─────────────────────────────────┬─────────────────────────────────┐
  │     │             change              │            consumer             │
  ├─────┼─────────────────────────────────┼─────────────────────────────────┤
  │ S2  │ write_width_bits min 0, not     │ the bundle drops the whole      │
  │     │ required                        │ write channel                   │
  ├─────┼─────────────────────────────────┼─────────────────────────────────┤
  │ S6  │ custom.error_response           │ the adapter drives rerr instead │
  │     │                                 │  of dropping it                 │
  ├─────┼─────────────────────────────────┼─────────────────────────────────┤
  │ S7  │ handshake.response_accept       │ none is now declared, not tool  │
  │     │                                 │ policy                          │
  ├─────┼─────────────────────────────────┼─────────────────────────────────┤
  │ S9  │ custom.request_qualifiers       │ one bit, read only in the ready │
  │     │                                 │  path                           │
  ├─────┼─────────────────────────────────┼─────────────────────────────────┤
  │ S3  │ valid_with_id ⇒ id_width_bits ≥ │ negative fixture proves it      │
  │     │  1                              │                                 │
  └─────┴─────────────────────────────────┴─────────────────────────────────┘

  Counts, all from this session

  - cachegen suite: 87 → 97 passed, 0 failed
  - lint: 0 warnings on all 7 nodes, before and after
  - runs: ifu 3→4, lsu 3, l1i 14→39, l1d 15, l2 15, mem 4, pacino 22 — all 0
    failed

  All five behaviours the prompt named are proved in the emitted testbench
  (T6–T10): sixteen accepted before any response, an out-of-order return, a
  merged pair answered separately from one fill, a fifth target refused, and the
  prefetch reserve.

  Three things worth your attention

  1. tl_l1i_l2.source_bits moved 3 → 4, which the prompt did not list. It had
     to: mem_a_source now names the miss-handling register and 16 of them need 4
     bits. The l2 is the other end of that link and its run is unchanged.
  2. S9 carries its reserve. The prompt scoped prefetch_arbitration
     (S1/TD-L1I-3) out, and IF-39 needs the number two. I put it on the
     qualifier declaration. Whether it belongs there or on the node beside mshrs
     is a PA call — Results Capture states both arguments.
  3. The memory side is still one fill at a time. The core port is 16
     outstanding; the TileLink master is blocking, so sixteen misses serialise
     two at a time across the two banks. Nothing in the spec asks for more, but
     it's the miss throughput the IFU would be built against.

  E5 is unchanged: read_latency_cycles and tag_compare_stage are still dead.
  IF-14 is now enforced, but by a direct assertion, not by those fields.

## My Assessment

Incomplete

## Claude.ai Assessment

| Requirement	| Source	| Delivered |
|hit throughput one request per cycle, pipelined	| icache_decisions.md L1I-5	| no — <n>_ctrl unchanged, blocking per bank, req_ready in C_IDLE only |
|hit latency 2 cycles	| L1I-5	no | E5 unchanged, read_latency_cycles still dead; the FSM is C_IDLE/C_TAG/C_HIT |
|16 MSHRs for miss parallelism	| L1I-12, derived from Neoverse V2's 16-entry fill buffer sustaining 4 IPC from L2	|no — <n>_mem_mst still one fill at a time |

The MSHR file accepts sixteen requests and returns them out of order. The banks serve them one at a time each, and the memory side fills one line at a time. That is a queue in front of a blocking cache.

This is my error, not the IA's. Problem 4's acceptance list was the port protocol — every line cites an IF rule, and every IF rule is a port rule. Throughput, latency and fill parallelism live in icache_decisions.md and I put them under Binding Decision 1 ("the specification is fixed") without listing them as conditions. The IA delivered what was asked.

One contradiction in the report. Deferred Work says sixteen misses are "serialised at the TileLink master, two at a time across the two banks." There is one mem interface. Serialised at the master means one at a time, not two. Worth confirming which.

Two items needing your ruling.

	
S9 reserve placement	on the link beside the bit, or on the node beside mshrs. IA recommends the PA decide
schema version bump	0.12.0 → 0.13.0 with nothing forcing it, which churned six fixture files

What TOOLS-005 has to cover: a pipelined bank control at one access per cycle, hit latency from read_latency_cycles, and multiple fills in flight on the memory side.

ME: i meant my assessment was incomplete, not that the IA's work incomplete

PA:
Understood — "Incomplete" was your Assessment field left unfinished, not a verdict.

Reassessing the IA output on what was asked:

| Problem	| Delivered |
| 1 configuration	| six keys plus the link swap; both stale tests found by enumeration and rewritten to assert the pair rather than a list |
| 2 schema	| S2, S6, S7, S9, S3, each with its consumer; nothing new in unconsumed.log |
| 3 512-bit port	| both sites; the degenerate shape emitted directly rather than computed, l1d keeps the computed form |
| 4 MSHR file	| 16×4, sized from config; slave-to-bank arbitration removed rather than joined |
| 5 testbench	| T6–T10, generated from the configuration rather than literals |
| 6 whole tree	| 87→97 suite, all seven nodes lint clean, no regression |
| 7 what did not fit	| E5 unchanged and said so |

Complete against the prompt.

Three things it did that weren't asked.

tl_l1i_l2.source_bits 3→4, required because a_source now names one of sixteen registers. Correctly identified as necessary and the l2 end checked.

test_nonblocking.cpp asserts the blocking node didn't get the treatment — the branch proved to be a branch, not just taken.

The system testbench handles agents of different widths, and the ifu write test replaced rather than deleted, with lsu keeping its write so the branch stays covered.

Two rulings for you. S9's reserve placement — link or node. And the 0.12.0→0.13.0 bump, which nothing forced and which touched six fixture files.

What remains, and it's my prompt's gap not the IA's: L1I-5's pipelined hit and 2-cycle latency, and fill parallelism on the memory side. <n>_ctrl and <n>_mem_mst are both still blocking. That's TOOLS-005.
## Follow-on Actions
Nothing required

## CLAUDE.md Updates
Nothing required

## Other Planning File Updates
Nothing required

:: DISCUSSION:END ::

=============================================================
:: PROMPT:START ::
=============================================================

## Task ID
TOOLS-004

## Context Loaded
@planning/arch/icache_decisions.md
@planning/interfaces/l1i_ifu_interfaces.md
@prompts/INFRA-012.md
@prompts/TOOLS-003.md
@tools/cachegen/CLAUDE.md
@tools/cachegen/planning/schema/caches.schema.json
@tools/cachegen/planning/schema/links.schema.json
@tools/cachegen/planning/schema/topology.schema.json
@tools/cachegen/testcases/pacino/pacino_caches.json
@tools/cachegen/testcases/pacino/pacino_links.json
@tools/cachegen/testcases/pacino/pacino_ports.json
@tools/cachegen/testcases/pacino/pacino_topology.json
@tools/cachegen/output/l1i/rtl/l1i_core_slv.sv
@tools/cachegen/output/l1i/rtl/l1i_ctrl.sv
@tools/cachegen/output/l1i/rtl/l1i_mem_mst.sv
@tools/cachegen/output/l1i/rtl/l1i_pkg.sv
@tools/cachegen/output/l1i/tb/l1i_tb.sv
@tools/cachegen/output/l1i/tb/l1i_tests.svh

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

DO NOT READ tools/cachegen/examples/. A hand-written cache model
predating cachegen.

DO NOT ANSWER FROM tools/cachegen/docs/pacino_cache.md. Generated,
its own header calls it incomplete, and it is not in the manifest.

l1i_ifu_interfaces.md IS THE PORT SPECIFICATION. Every IF- rule in
it is a requirement on this task except those in sections 10 and 11,
which are maintenance and out of scope.

INFRA-012 and TOOLS-003 ARE PRIOR WORK, in the manifest for their
file and line references. TOOLS-003 changed things INFRA-012 only
inspected; where the two disagree, TOOLS-003 is later.

THE SCOPE IS THE l1i NODE. l1d, l2 and mem must continue to emit
and to pass. A change that helps l1i and breaks another node is not
done.

## Hypothesis

The emitted L1I is a blocking cache: one request at a time, in-order
return, no miss tracking. The specification is a non-blocking cache:
sixteen outstanding, out-of-order return keyed by an identifier,
sixteen MSHRs with four targets each.

The gap is enumerated. INFRA-012 found it and TOOLS-003 confirmed
the parts it could test. What is not known is how much of the
control emitter survives the change: a blocking FSM and an MSHR file
are different structures, not the same structure with more state.

## Background

pacino is an 8-issue RVA23 out-of-order processor. Its BPU and FTQ
are built; the IFU is unbuilt. The L1I is emitted by cachegen.

TOOLS-003 set pa_bits to 36 across the configuration, added the
T-10.addr_width checker rule, and fixed three emitter width defects
exposed by that change. It did NOT touch the l1i geometry or the
core link, which are this task's first requirement.

The specification is complete. icache_decisions.md carries no open
item that bears on this work, and l1i_ifu_interfaces.md carries
none at all.

## Binding Previous Decisions

1. THE SPECIFICATION IS FIXED. icache_decisions.md sections 1
   through 9 and l1i_ifu_interfaces.md sections 1 through 9 are
   decided. This task implements them. Where the tool cannot express
   something, REPORT IT; do not change the specification to fit.

2. THE TARGET GEOMETRY, icache_decisions.md 9 first table.
   64 KiB, 8-way, 64-byte lines, 2 banks line interleaved, PIPT,
   tree-PLRU, 16 MSHRs, 4 targets.

   GEOMETRY AND INDEXING LAND TOGETHER. At 64 KiB 8-way,
   bytes_per_way is 8192 against a 4096-byte page, so VIPT raises
   T-8.vipt_index and cgen refuses to emit. PIPT is required by the
   same change that raises the capacity.

3. THE CORE LINK, icache_decisions.md 9 second table.
   512-bit read, 36-bit address, 16 outstanding, no write channel,
   read_data_return valid_with_id, id_width_bits 4, plus the
   prefetch request bit of L1I-21.

   A SECOND LINK TYPE, not a change to pe_port. pe_port is carried
   by the lsu-to-l1d edge as well and that edge is unchanged. A link
   cannot be parameterised per edge; nothing binds a port type to
   one link, so a second definition plus two `link` string changes
   is the whole of it.

4. MAINTENANCE IS OUT OF SCOPE. l1i_ifu_interfaces.md sections 10
   and 11, S8, TD-IF-4 and E7 are a separate task. Do not add an
   invalidate port and do not add the schema object for one.

5. THE RULES THIS TASK IMPLEMENTS, by number, from
   l1i_ifu_interfaces.md:

```
     IF-1 to IF-3    widths
     IF-4 to IF-7    the request handshake
     IF-9, IF-38     prefetch on the same ports
     IF-10 to IF-15  the response, its identifier, no ready
     IF-16 to IF-18  backpressure and the outstanding limit
     IF-39           the prefetch reserve, two free MSHRs
     IF-40           conservative ready
     IF-19 to IF-21  misses and merging
     IF-25 to IF-27  reset
```

   IF-22 to IF-24 are fault rules and specify an ABSENCE on this
   boundary; nothing is emitted for them.

## Specific Requirements

Problems, not procedure. Method, ordering and decomposition are
yours. The order below is suggested because each step makes the
next testable.

PROBLEM 1 -- THE CONFIGURATION.

Apply Binding Decision 2 and the part of Binding Decision 3 the
schema accepts today. Report which fields the schema refuses; those
are Problem 2.

Existing tests encode the current geometry and the current link.
TOOLS-003 found five that encoded pa_bits when the task named two,
so ENUMERATE rather than trust a list: run the suite, and read
cli/tb for anything asserting a geometry, a tag width, an index
width or a link shape.

PROBLEM 2 -- THE SCHEMA.

Four fields cannot be declared today. Each is named in
l1i_ifu_interfaces.md 14.2 with the file and the constraint.

```
  S2  custom.write_width_bits has minimum 8 and is required, so a
      read-only link cannot be declared. TD-L1I-7
  S6  no error return on a custom link, so IF-15's rsp_err cannot
      be declared. TD-IF-2
  S7  no response-side handshake, so IF-10's absence of a response
      ready is a tool policy rather than a configured property.
      TD-IF-3
  S9  no requester-supplied qualifier, so the prefetch bit of
      L1I-21 cannot be declared. TD-L1I-9
```

S3, tying read_data_return valid_with_id to a non-zero
id_width_bits, is a constraint rather than a field and is smaller
than the four above. Include it.

FOR EACH, the schema change and its consumer land together. A field
with no consumer appears in unconsumed.log, and
Featnames.NoTestClaimsAnUnconsumedFeature forbids a test claiming
coverage of it.

PROBLEM 3 -- THE 512-BIT CORE PORT.

At read_width_bits 512 over a 64-byte line, WordsPerLine is 1,
WordIdxBits is 0, and rtl_pkg.cpp emits logic [-1:0]. TOOLS-003
confirmed this is a hard Verilator error, not a warning.

TWO SITES, not one. The second is the emitted testbench driver task,
which sizes its write path from write_width_bits and its data
argument from the read width, so an asymmetric link breaks the
testbench as well as the package. l1i_ifu_interfaces.md 14.3 E1.

PROBLEM 4 -- OUTSTANDING REQUESTS, IDENTIFIERS AND THE MSHR FILE.

This is the task. E2, E3 and E4 of l1i_ifu_interfaces.md 14.3 are
one piece of work: sixteen outstanding requests with in-order return
and no miss tracking is the blocking cache with extra wires.

What must be true when this is done:

```
  the request     accepts a new request every cycle while ready,
                  up to sixteen in flight (IF-4, IF-6, IF-18)
  the identifier  carried with the request, returned with the
                  response, and the ONLY correlation between them
                  (IF-11, IF-12)
  the response    presented without a ready, one per cycle, in any
                  order, never in the cycle its request was
                  accepted (IF-10, IF-13, IF-14)
  the MSHR file   sixteen entries, four targets each, sized from
                  mshrs and mshr_targets (IF-20, L1I-12, L1I-13)
  merging         a second request for a line in flight attaches to
                  its MSHR and is answered separately with its own
                  identifier (IF-20)
  the fifth       refused by ready. Not queued, not rejected on a
                  channel, not given a second MSHR (IF-21)
  ready           CONSERVATIVE: low whenever any MSHR holds four
                  targets, whatever address the request names. No
                  address compare in the ready path (IF-40, IF-17)
  the prefetch    refused unless two MSHRs are free. The bit is
                  read HERE AND NOWHERE ELSE (IF-38, IF-39)
  the memory side mem_a_source is driven from the in-flight state
                  rather than tied to zero
  reset           free list all sixteen free; ready may assert in
                  the first cycle after rstn (IF-26, IF-27)
```

THE CONTROL IS NOT THE SAME STRUCTURE WITH MORE STATE. The emitted
control is a blocking FSM that asserts req_ready only in C_IDLE,
and rtl_cache.cpp carries a design note saying so. Report what
survives and what is replaced.

PROBLEM 5 -- THE EMITTED TESTBENCH.

The generated l1i testbench drives one request at a time. It cannot
show any of Problem 4.

Extend it to prove, at minimum: sixteen requests accepted before any
response; a response returning out of order; two requests to one
line answered separately; a fifth target refused; a prefetch refused
with fewer than two MSHRs free and accepted with more.

A rule with no test is a rule the next change breaks silently.

PROBLEM 6 -- THE WHOLE TREE STILL WORKS.

Run the cachegen unit suite before and after. Run lint and the run
target for every emitted node, not only l1i. Report counts for both.

l1d, l2 and mem are not in this task's scope and must not regress.
A change that helps l1i and breaks another node is not done.

PROBLEM 7 -- WHAT DID NOT FIT.

Report anything in the specification this task could not emit, with
the reason. Report anything in the specification found wrong while
implementing it; l1i_ifu_interfaces.md is READ-ONLY here and the PA
drafts the amendment.

E5 is expected to be one of these: read_latency_cycles and
tag_compare_stage are dead for a cache node, so IF-14's one-cycle
minimum is not enforced by anything. Say whether this task changed
that.

## Constraints

- WAIVER, TOOLS-004 ONLY. This task MAY write:
    tools/cachegen/planning/schema/*.json
    tools/cachegen/testcases/pacino/*.json
    tools/cachegen/cli/src/*, tools/cachegen/cli/inc/*
    tools/cachegen/cli/tb/*
  It covers this task only. It is NOT precedent and does NOT
  propagate to the next task, including one continuing this work.
  Every file under planning/, pa_handoffs/ and docs/ in BOTH trees
  is READ-ONLY, including tools/cachegen/planning/arch/.

- icache_decisions.md AND l1i_ifu_interfaces.md ARE READ-ONLY.
  Report what they should say; the PA drafts it.

- MAINTENANCE IS OUT OF SCOPE. No invalidate port, no maintenance
  schema object. l1i_ifu_interfaces.md sections 10 and 11 are not
  implemented by this task.

- THE OTHER NODES DO NOT REGRESS. l1d, l2 and mem lint and run
  before and after.

- The riscv-codesign bpu and ftq suites are not in scope and must
  not be run. No RTL under rtl/ is touched.

- Regenerating the cachegen output tree is required.

## Deliverables

- tools/cachegen schema, configuration, source and fixtures as
  problems 1 through 5 require
- the regenerated output tree
- Results Capture filled in below, in this file:
  prompts/TOOLS-004.md

Fill in every section. Report the cachegen suite counts before and
after, the per-node lint and run counts before and after, every
configuration key changed with its before and after value, and
anything in the specification that could not be emitted.

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary

cachegen now emits a NON BLOCKING l1i. The core link declares 16
outstanding requests and a response keyed by a 4 bit identifier, the
node carries a 16 entry miss handling file with 4 targets each, and
the emitted testbench proves all five behaviours the prompt named.
Problems 1 through 6 are done. Problem 7 is reported below.

Counts, all from runs in this session:

```
  cachegen unit suite     before  87 passed  0 failed
                          after   97 passed  0 failed
  emitted lint, per node  before  0 warnings on all 7
                          after   0 warnings on all 7
  emitted run, per node   before          after
    ifu                   3 / 0          4 / 0
    lsu                   3 / 0          3 / 0
    l1i                  14 / 0         39 / 0
    l1d                  15 / 0         15 / 0
    l2                   15 / 0         15 / 0
    mem                   4 / 0          4 / 0
    pacino               22 / 0         22 / 0
```

Every Makefile target of the emitted tree was enumerated and run:
lint, build, run. `default` is `run` and `all` is `lint build`, so
they add no target of their own. `clean` was not run, it destroys
the tree under test. The cachegen Makefile's targets are `all`,
`only`, `test` and `run`; all four were run.

l1d, l2, mem, lsu and pacino are unchanged in pass count and in
warning count. ifu gained one check because its unit test could no
longer write to a read only link; see Decisions.

## Test Matrix (testbench sessions only, omit otherwise)

The emitted `l1i_tests.svh` gained T6 through T10. Every one is
generated from the configuration, so the addresses and the counts
below are the values cgen derived for pacino and not literals in the
emitter.

```
T6  sixteen outstanding, none answered
    Rules   IF-4, IF-6, IF-18, L1I-10, L1I-12
    Setup   tb_hold high on the downstream responder, so no fill can
            complete. nb_clear. 16 cold lines at 0x00040000 + k*64,
            which is 8 sets per bank across both banks, no eviction
    Stimulus  nb_req back to back, one per cycle, identifiers 0..15
    Expected  every request accepted, nb_n still 0. Release the
            hold and all 16 answer, one per identifier
    Pass    all_ok and nb_n == 0, then nb_n == 16 with every
            nb_seen set, nb_data[0] != nb_data[1], no nb_err set

T7  an answer out of order
    Rules   IF-12, IF-13, R2, L1I-11
    Setup   0x00050040 warmed by a completed read. It is bank 1
            because PA[6] is the select. 0x00050000 is bank 0 and
            cold. tb_hold high
    Stimulus  identifier 1 to the cold bank 0 line FIRST, then
            identifier 2 to the warm bank 1 line
    Expected  identifier 2 answers while identifier 1 is still
            outstanding. Release, identifier 1 answers after it
    Pass    nb_seen[2] with !nb_seen[1], then nb_ord[2] < nb_ord[1]

T8  two requests for one line, answered separately
    Rules   IF-20, L1I-13
    Setup   tb_hold high, nb_clear, one cold line at 0x00060000
    Stimulus  identifiers 3 and 4, both naming that one line
    Expected  both accepted, both answered, same 512 bits, and ONE
            fill left for memory
    Pass    nb_data[3] == nb_data[4] and nb_fill == 1

T9  the target after the last one is refused
    Rules   IF-21, IF-40, IF-17
    Setup   tb_hold high, nb_clear, four requests to 0x00070000,
            which is MshrTargets of them on one register
    Stimulus  nb_ready with no request presented, then nb_try to
            0x00071000, an UNRELATED line, for 8 cycles
    Expected  ready low both times. After the hold is released and
            the four drain, ready is high again
    Pass    !rdy_dm, !took, then all four answered separately with
            nb_n == 4, then rdy_dm

T10 the prefetch reserve
    Rules   IF-38, IF-39, L1I-21, L1I-22
    Setup   tb_hold high, 15 cold lines at 0x00080000 + k*64, which
            leaves ONE register free against a reserve of two
    Stimulus  nb_ready with the prefetch bit high, then with it low
    Expected  refused with the bit, accepted without it. After the
            file drains, accepted with the bit, and a real prefetch
            request is answered like any other
    Pass    !rdy_pf and rdy_dm, then rdy_pf, then the request is
            accepted and answered
```

The tool side gained `test_nonblocking.cpp`, nine tests asserting
what the SystemVerilog cannot check about itself: the read only
bundle, the degenerate word index, the driver's write path, the
file's existence and sizing, the consumption of the four new
declarations, the qualifier being read in exactly one place, the
error return being driven, the memory side source, and the file
replacing the arbitration rather than joining it. Each also asserts
the BLOCKING node did not get the same treatment, so the branch is
proved to be a branch.

`test_negative.cpp` gained the S3 fixture: a link declaring
`valid_with_id` with `id_width_bits` 0 is refused by the schema.

## What was delivered

PROBLEM 1, THE CONFIGURATION. Applied. Every key, before to after:

```
  caches, l1i
    geometry.capacity_bytes                32768 -> 65536
    geometry.banks                             1 -> 2
    geometry.bank_interleave_granularity  absent -> line
    indexing                                VIPT -> PIPT
    miss_handling.mshrs                        4 -> 16
    miss_handling.mshr_targets                 2 -> 4
    interfaces.core.link                 pe_port -> pe_port_i
  caches, ifu
    interfaces.mem.link                  pe_port -> pe_port_i
  links, tl_l1i_l2
    tilelink.source_bits                       3 -> 4
  links, pe_port_i                        NEW, see below
  links, schema_version                 0.12.0 -> 0.13.0
```

GEOMETRY AND INDEXING LANDED TOGETHER, as Binding Decision 2
requires. At 65536 over 8 ways a way is 8192 bytes against a 4096
byte page, so VIPT raises T-8.vipt_index and cgen refuses to emit.
The two moved in one edit and the derivation agrees with
icache_decisions.md 1.2 exactly: 128 sets, 64 per bank, offset
PA[5:0], index PA[12:6], bank PA[6], set index PA[12:7], tag
PA[35:13], 23 bits.

`tl_l1i_l2.source_bits` was NOT in the prompt's list. It had to
move: the memory side now names the miss handling register on
channel A and 16 registers need 4 bits, not 3. It is the l1i's own
downstream link, the l2's up_i is the other end of it and moves with
it, and the l2 run is unchanged.

The five fields TOOLS-003 warned about were ENUMERATED rather than
trusted. `cli/tb` was read for anything asserting a geometry, a tag
width, an index width or a link shape, and the suite was run to find
the rest. Two tests encoded the old l1i:

```
  test_geometry.cpp  GeometryPacino.L1iDerivation, 15 assertions on
                     the 32 KiB one bank shape
  test_pacino.cpp    Pacino.ViptIndexBudgetIsMet, which named l1i in
                     a VIPT list
```

Both were rewritten rather than deleted. The geometry test now
carries the two bank decomposition and asserts that bytes per way
EXCEEDS the page, which is the reason the node is PIPT. The pacino
test now walks the model rather than naming a list, asserts the pair
(every VIPT node meets the budget AND the node that cannot is PIPT),
and would fail on a configuration that quietly dropped the capacity
back to where the budget is met.

PROBLEM 2, THE SCHEMA. All five landed, each with its consumer.

```
  S2  write_width_bits minimum 8 -> 0, and dropped from custom's
      required list. Consumer: LinkSig::custom drops the write
      channel, the read/write strobe and write_granularity_bytes
      when it is zero, and reports the absence in tied_off.
      TD-L1I-7 CLOSED
  S6  custom.error_response, boolean. Consumer: the bundle gains
      rerr and the slave adapter drives it from the internal
      rsp_err instead of tying it into unused_err. TD-IF-2 CLOSED
  S7  custom.handshake.response_accept, none | ready. Consumer:
      the bundle gains rready on `ready`, and `none` is now a
      DECLARED absence rather than a tool policy. pe_port_i
      declares none, which is IF-10. TD-IF-3 CLOSED
  S9  custom.request_qualifiers, an array of {name, policy,
      reserve}. Consumer: the bundle gains one bit per qualifier,
      and the miss handling file reads it in the ready path.
      TD-L1I-9 CLOSED
  S3  a conditional: read_data_return valid_with_id requires
      id_width_bits present and at least 1. Negative fixture
      neg_id_width_zero proves it
```

Nothing new appears in `unconsumed.log`. The only pe_port_i fields
on that list are `address_granularity` and `address_alignment_bytes`,
both of which were already inert for pe_port and are not this task's.

PROBLEM 3, THE 512 BIT CORE PORT. Both sites.

```
  site 1, the package. rtl_pkg computes words per line in C++ and
    emits the DEGENERATE shape directly when it is 1: WordIdxBits
    is a literal 0, WordIdxMsb is WordIdxLsb rather than
    WordIdxLsb + 0 - 1 which underflows an unsigned int, and
    word_of is a one bit function returning constant zero that
    still reads its argument so the linter does not report the
    address unread. No [-1:0] is emitted. l1d keeps the computed
    $clog2 form, so this is a branch rather than a rewrite
  site 2, the emitted testbench. With write_width_bits 0 the
    bundle has no wdata and no wstrb, so the driver task assigns
    neither and there is nothing to truncate 512 into 32. The
    driver instead reports a failure if it is asked for a write on
    a read only link, so the argument list every other node's
    driver has is kept without becoming a silent no-op
```

PROBLEM 4, OUTSTANDING REQUESTS, IDENTIFIERS AND THE MSHR FILE.

WHAT SURVIVED. `<n>_ctrl` is unchanged. It is still the blocking
per bank control: C_IDLE through C_DONE, req_ready in C_IDLE only,
one address latched. `<n>_bank`, `<n>_meta_array`, `<n>_data_array`
and the bank to master arbitration are unchanged.

WHAT WAS REPLACED.

```
  <n>_core_slv   the busy flag and pend_read are GONE. The
                 adapter is now wires: valid, addr, id and the
                 qualifier across, ready back, and the response
                 with its identifier and its error. Nothing is
                 registered, because a holding register would be
                 a second place a request could sit beside the
                 identifier free list that is already the flow
                 control
  <n>_mshr       NEW. 16 registers of 4 targets, sized from
                 miss_handling.mshrs and mshr_targets
  <n>            the slave to bank arbitration, b_sel, b_owner
                 and rr_slv are NOT EMITTED on a non blocking
                 node. The file is the only thing presenting to
                 the banks, so there is nothing left to arbitrate
  <n>_mem_mst    gained mreq_src, latched at M_IDLE and driven
                 onto a_source, plus an assertion that the D beat
                 names the request it answers
```

Against the prompt's list of what must be true:

```
  the request     nb_req accepts one per cycle while ready and T6
                  shows all 16 in flight at once
  the identifier  carried on core_id, returned on core_rid, and
                  the only correlation. T7 turns on that
  the response    no ready on the link, one per cycle from a
                  single scan, any order, and an assertion that
                  no identifier is answered in the cycle it was
                  accepted
  the MSHR file   16 x 4, from the configuration. The package
                  carries L1iMshrs, L1iMshrTargets, L1iReqIdBits
                  and L1iMaxOutstanding, which is what section 3.1
                  of l1i_ifu_interfaces.md said l1i_pkg had no
                  counterpart for
  merging         a request whose line is in flight and not yet
                  returned takes a target slot. T8 shows two
                  answers and ONE fill
  the fifth       refused by ready. T9
  ready           rstn && a free register && no register full &&
                  the qualifier's reserve. It reads no address and
                  no valid
  the prefetch    read in exactly one place, the ready path, and
                  test_nonblocking counts the occurrences to keep
                  it that way
  the memory side a_source is b_src[m_sel], which is the register
                  the bank is working for
  reset           every e_val clears, so all 16 are free, and
                  ready is combinational from those flops and from
                  rstn. It is low during reset and may stand in
                  the first cycle after it
```

A register whose line HAS returned is not merged onto. It is
retiring, and a second fill of one line is two writes to one set
with the replacement decision taken twice. Such a request allocates
its own register and then hits in the array, because the bank
control is blocking and cannot take a new lookup until the fill it
just installed is done.

PROBLEM 5, THE EMITTED TESTBENCH. Extended with a response
collector standing on the port, five task level primitives
(nb_req, nb_idle, nb_ready, nb_try, nb_wait, nb_clear) and the five
tests above. The downstream responder gained a `tb_hold` input: a
test that has to show what the node does WHILE a fill is
outstanding needs the fill to stay outstanding, and holding channel
A is the only way to arrange that from a test. Every node's
responder has it and every blocking node ties it to zero.

PROBLEM 6, THE WHOLE TREE. Counts at the top. Nothing regressed.

## Test Case Results

```
  cachegen unit suite            97 passed, 0 failed
  ifu_tb                          4 passed, 0 failed
  lsu_tb                          3 passed, 0 failed
  l1i_tb                         39 passed, 0 failed
  l1d_tb                         15 passed, 0 failed
  l2_tb                          15 passed, 0 failed
  mem_tb                          4 passed, 0 failed
  pacino_tb                      22 passed, 0 failed
  lint, every node                0 warnings, 0 errors
```

The l1i suite went from 14 to 39. The 14 that were there all still
pass and none was rewritten; T1 gained the bank argument to
line_addr because the node now has two banks, which the emitter
already handled.

## Assumptions made not explicit in the prompt

- THE MISS HANDLING FILE IS BUILT FOR ONE CORE INTERFACE. It is
  emitted only when the node has exactly one slave interface. A
  second one would contend with it for the banks and no field
  describes how. The emitter falls back to the arbitration it
  already had rather than guessing, and l1i has one core interface
  so nothing is lost here.

- ONE FILL AT A TIME ON THE MEMORY SIDE. `<n>_mem_mst` is still a
  blocking state machine, so a_source names the one fill in flight
  rather than indexing a pool. The prompt asked that a_source be
  driven from the in-flight state rather than tied to zero, and it
  is. Sixteen fills in flight downstream is a different piece of
  work and is not asked for.

- THE SCHEMA VERSION WAS BUMPED, 0.12.0 to 0.13.0, and the seven
  files declaring file_type links moved with it. The additions are
  backward compatible so nothing forced the bump, but the shape
  changed and a version that does not move is a version that stops
  meaning anything.

## Decisions made not explicit in the prompt

- S9 CARRIES ITS POLICY. The prompt scopes S1, prefetch_arbitration
  and TD-L1I-3, OUT of this task, and IF-39 needs a number: the
  reserve is two. With no node field in scope to hold it, the
  qualifier declaration carries it:

    "request_qualifiers": [
      { "name": "prefetch", "policy": "mshr_reserve", "reserve": 2 }
    ]

  One addition declares the bit AND its one reading, which is what
  keeps the rule emitted rather than reimplemented per node.
  RECOMMENDATION FOR THE PA: decide whether the reserve belongs on
  the link beside the bit or on the node beside `mshrs`. The
  argument for the link is that the bit and the rule that reads it
  are one thing. The argument for the node is that it counts a NODE
  structure, and TD-L1I-3 already puts prefetch_arbitration there.
  If the node wins, this row moves and S9 keeps only {name, policy}.

- THE ifu AGENT'S UNIT TEST LOST ITS WRITE. Its link is now read
  only, so "a read sees the write before it" cannot be run. It was
  replaced by a second read at a DIFFERENT address, checked against
  its own seed and against the first read's answer, which still
  proves the agent runs a second request to completion. The lsu
  agent keeps the write test, so the branch is a branch.

- THE SYSTEM TESTBENCH NOW HANDLES AGENTS OF DIFFERENT WIDTHS. It
  took `ag[0]`'s data width as the width of everything, which is
  now 512 for the ifu against 32 for the lsu. Each agent's r0 and
  r1 are declared at its OWN width, and every cross agent or
  against-memory comparison is made at the NARROWEST agent's width.
  Both addresses in the shared line test are line aligned, so the
  narrow agent's word is the front of the wide agent's line.

- TWO ASSERTIONS WERE ADDED THAT THE PROMPT DID NOT ASK FOR, both
  naming rules the specification states and nothing else enforced:
  no identifier accepted while already in flight (IF-18), and no
  answer in the cycle its request was accepted (IF-14). Neither can
  fire on the emitted testbench; they exist so a later change
  cannot break the rule silently.

- `lp()` in rtl_pkg gained a guaranteed space before the '='. The
  node prefix is added after padding, so L1iMaxOutstanding reached
  the column and emitted `L1iMaxOutstanding= 16`. Valid, ugly.

## RVA23 compliance risks and gaps noticed

- THE Zicbom AND Zifencei GAP IS UNCHANGED. Maintenance was out of
  scope by Constraints, so no node emits an invalidate port and
  L1I-18 still has no hardware. TD-L1I-8's maintenance half and
  section 14.3 E7 stand. This task closed E1 through E4 of that
  list and did not touch E7.

- No new compliance risk was introduced. The l1i is read only on
  its core boundary, which is what RVA23 requires of an instruction
  side that reaches software through FENCE.I, and the C extension
  sees nothing here because every request is line aligned.

## Deferred Work

PROBLEM 7, WHAT DID NOT FIT.

- E5 IS UNCHANGED BY THIS TASK. `read_latency_cycles` and
  `tag_compare_stage` are still on `unconsumed.log` for l1i and
  still shape nothing. IF-14's one cycle minimum is now ENFORCED,
  by an assertion in the miss handling file, but it is not
  enforced BY THOSE FIELDS: the assertion states the rule directly
  and the two timing fields remain dead. Making the emitted
  pipeline depth follow read_latency_cycles is a separate piece of
  work and this task did not do it.

- THE FIELDS STILL INERT ON l1i, from unconsumed.log after the
  change: fill/beat_order, fill/bypass_to_upstream, inclusion, all
  four maintenance booleans, miss_handling/fill_buffer_entries,
  miss_handling/victim_buffer_entries, storage/way_access,
  storage/data_array_organization, three storage byte_enables, two
  storage cleared_on_reset, timing/emit_parameters,
  timing/read_latency_cycles, timing/tag_compare_stage. That is 19,
  against INFRA-012's thirteen of twenty-two: `mshrs`,
  `mshr_targets`, `banks`, `bank_interleave_granularity` and
  `indexing` all moved to consumed, and the count above enumerates
  more leaves than INFRA-012's field count did.

- SIXTEEN FILLS DOWNSTREAM. The core port is 16 outstanding and the
  memory side is one. Sixteen misses to sixteen distinct lines are
  therefore serialised at the TileLink master, two at a time across
  the two banks. Nothing in the specification asks for more, and
  L1I-16 does not, but the miss throughput of the emitted design is
  two fills at a time and not sixteen. Worth a decision before the
  IFU is built against it.

- MAINTENANCE, out of scope by Constraints. Sections 10 and 11 of
  l1i_ifu_interfaces.md, S8, TD-IF-4 and E7 are untouched.

## Other Notes

WHAT THE PLANNING DOCUMENTS SHOULD SAY. Both are read only here and
the PA drafts the amendment. Nothing was found WRONG in either; what
follows is status that has changed under them.

```
  icache_decisions.md 9, the node table
    The capacity, banks, bank_interleave_granularity, indexing,
    mshrs and mshr_targets rows are APPLIED. The 'Changed' column
    on those six can read DONE, as the address_width_bits row
    already does.

  icache_decisions.md 9, the core link table
    read_width_bits 512, outstanding_requests 16,
    read_data_return valid_with_id and id_width_bits 4 are
    APPLIED. Note n2 is closed: write_width_bits 0 is declarable
    and pe_port_i declares it. Note n4 is closed: the prefetch bit
    is declarable, as custom.request_qualifiers, and the row can
    name the field. The paragraph below the table describing the
    second link type is now the built arrangement rather than a
    proposal.

  icache_decisions.md 9, closing paragraph
    "THIRTEEN OF THE TWENTY-TWO NODE FIELDS ABOVE ARE ACCEPTED,
    CARRIED AND REACH NO EMITTED LOGIC" is now out of date. mshrs,
    mshr_targets, banks, bank_interleave_granularity and indexing
    reach emitted logic. indexing still shapes only a diagnostic.

  icache_decisions.md 10.2
    TD-L1I-7 CLOSED, a read only link is declarable.
    TD-L1I-9 CLOSED, the prefetch bit is declarable.
    TD-L1I-8 is PARTLY closed: the MSHR file exists, the core
    adapter is no longer single outstanding, the identifier
    reaches every module on the path, and prefetch has a notion in
    the tool. What remains of it is the maintenance half, which is
    the Zicbom RVA23 gap, and it is untouched.
    TD-L1I-4 CLOSED, the second link type is declared and both
    edges name it.
    TD-L1I-3 is UNCHANGED as written, and its scope has narrowed:
    the reserve of L1I-22 is now expressible, on the link. What
    prefetch_arbitration would still add is P1 and P3, which this
    interface does not see. See Decisions.

  l1i_ifu_interfaces.md 3.1, the parameter table
    The two rows reading "(no counterpart)" are wrong now.
    l1i_pkg carries L1iReqIdBits (4) and L1iMaxOutstanding (16),
    and also L1iMshrs, L1iMshrTargets, L1iMshrIdxBits,
    L1iMshrTgtBits, L1iMshrCntBits and L1iQualReserve. The
    bp_defines_pkg column is unchanged and TD-IF-1 stands: nothing
    still makes the hand written and the generated side agree.

  l1i_ifu_interfaces.md 14.2
    S2, S6, S7, S9 and S3 are all APPLIED. S8 is not, and is out
    of scope by Constraints.

  l1i_ifu_interfaces.md 14.3
    E1 CLOSED, both sites. E2 CLOSED. E3 CLOSED. E4 CLOSED.
    E5 UNCHANGED, see Deferred Work. E7 UNTOUCHED.

  l1i_ifu_interfaces.md 17
    TD-IF-2 CLOSED. TD-IF-3 CLOSED. TD-IF-4 unchanged, out of
    scope. TD-IF-5 unchanged, it is an ifu_decisions.md item.
```

HOW THE TREE IS BUILT AND RUN, recorded because the two halves want
different values of one variable:

```
  emit   CGEN_ROOT=<cachegen>, so the master Vars.mk is found at
         $CGEN_ROOT/planning/tools/Vars.mk
  run    CGEN_ROOT=<pacino>, so the emitted
         VERILATOR=$(CGEN_ROOT)/tools/bin/verilator resolves.
         That is verilator 5.048
```

The master Vars.mk is copied verbatim by R-11, so the emitted
Vars.mk is byte identical to what it was before this task.

## Files Modified
- tools/cachegen/planning/schema/links.schema.json
- tools/cachegen/testcases/pacino/pacino_caches.json
- tools/cachegen/testcases/pacino/pacino_links.json
- tools/cachegen/cli/inc/link_sig.h
- tools/cachegen/cli/inc/node_ctx.h
- tools/cachegen/cli/inc/rtl_cache.h
- tools/cachegen/cli/src/link_sig.cpp
- tools/cachegen/cli/src/node_ctx.cpp
- tools/cachegen/cli/src/rtl_cache.cpp
- tools/cachegen/cli/src/rtl_pkg.cpp
- tools/cachegen/cli/src/rtl_agent.cpp
- tools/cachegen/cli/src/rtl_tb.cpp
- tools/cachegen/cli/src/sv_file.cpp
- tools/cachegen/cli/src/emitter.cpp
- tools/cachegen/cli/tb/test_geometry.cpp
- tools/cachegen/cli/tb/test_pacino.cpp
- tools/cachegen/cli/tb/test_negative.cpp
- tools/cachegen/cli/tb/test_nonblocking.cpp
- tools/cachegen/cli/tb/fixtures/base/base_links.json
- tools/cachegen/cli/tb/fixtures/neg_duplicate_definition/dup_links.json
- tools/cachegen/cli/tb/fixtures/neg_link_addr_width/links.json
- tools/cachegen/cli/tb/fixtures/neg_link_port_type/links.json
- tools/cachegen/cli/tb/fixtures/neg_port_role_mismatch/links.json
- tools/cachegen/cli/tb/fixtures/neg_port_type_mismatch/links.json
- tools/cachegen/cli/tb/fixtures/neg_id_width_zero/links.json
- tools/cachegen/cli/tb/fixtures/neg_id_width_zero/system.json
- tools/cachegen/output/ (regenerated, 85 files)

:: RESULTS:END ::

:: CONTEXT:START ::

# Context Report

## Headline

```
  Context used   46%
  Tokens         459.6k of 1m
  Free           540.4k, 54.0%
  Model          claude-opus-5[1m], Opus 5 (1M context)
```

## Breakdown

| Category               | Tokens | Percent |
|------------------------|--------|---------|
| System prompt          | 4.0k   | 0.4%    |
| System tools           | 20.3k  | 2.0%    |
| System tools, deferred | 17.3k  | 1.7%    |
| MCP tools, deferred    | 1.5k   | 0.1%    |
| Memory files           | 4.9k   | 0.5%    |
| Skills                 | 2.9k   | 0.3%    |
| Messages               | 427.6k | 42.8%   |
| Free space             | 540.4k | 54.0%   |

Messages are 93% of what was used. Everything the harness carries
before the first prompt is read, prompt plus tools plus memory plus
skills, is 51.9k, which is 5.2% of the window.

## Skills loaded

```
  project    cntx ~30, run ~20
  built-in   dataviz ~480, claude-api ~360, design ~340,
             code-review ~270, update-config ~240,
             artifact-capabilities ~210, claude-in-chrome ~180,
             schedule ~130, loop ~120, workflow-authoring ~80,
             keybindings-help ~80, artifact-diagramming ~70,
             artifact-design ~70, fewer-permission-prompts ~60,
             simplify ~60, security-review ~30, init ~20
```

## MCP tools available, deferred

```
  claude_ai_Gmail            authenticate, complete_authentication
  claude_ai_Google_Calendar  authenticate, complete_authentication
  claude_ai_Google_Drive     authenticate, complete_authentication
```

None was invoked.
:: CONTEXT:END ::

