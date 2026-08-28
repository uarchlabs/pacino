<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# L1 Instruction Cache Micro-Architectural Decisions
```
 FILE:    icache_decisions.md
 SOURCE:  session-068 rulings; pacino_cache.md; the survey in
          docs/superscalar_ooo_survey.md
 STATUS:  DRAFT
 UPDATED: 2026-08-27
 CONTACT: Jeff Nye
```

L1I-owned behaviour: geometry, indexing, storage, the two
interfaces it presents, miss handling, maintenance and prefetch.

---

## 0. Scope and companion documents

```
  ftq_ifu_interfaces.md     the FTQ <-> IFU boundary, specified
  ftq_decisions.md          FTQ-owned behaviour; section 0 states
                            the ICache position and needs the
                            amendment of L1I-2
  fe_decisions.md           front-end theory of operation; owns the
                            FE / TD-FE / FE-U registries
  pacino_cache.md           the generated description of the cgen
                            output tree, node l1i
```

Not yet written and cited here as stubs:

```
  ifu_decisions.md          IFU-owned behaviour. Owns the line
                            buffer of L1I-14 and the request
                            pipeline the L1I latency sits in
  itlb_decisions.md         the ITLB, and the L2 TLB below it
  ibuf_decisions.md         the instruction buffer between IFU and
                            decode. No planning record exists
```

REGISTRIES. This file owns L1I-1 through L1I-19, TD-L1I-1 through
TD-L1I-5, and the open items L1I-U1 through L1I-U5. It does not
duplicate the FE, TD-FE or FE-U registries, and it does not use the
IC- prefix, which is already an interface-check identifier in
ftb_interfaces.md and sc_interfaces.md.

THE L1I IS A GENERATED MODULE. It is emitted by `cgen` from JSON
configuration. This document is the SOURCE and the JSON is
downstream of it: where a decision here has no field in the current
configuration schema, the schema is what changes. Nothing here is
scoped to what the tool emits today.

### 0.1 The three interfaces

```
  core   BOTH  to the IFU. Specified here, section 4
  mem    BOTH  to the L2. Specified here, section 5
  itlb   IN    the translated physical address. NAMED here,
               section 2.3; specified in itlb_decisions.md
```

There is no L1I-to-FTQ interface and there will not be one. The FTQ
reaches the memory hierarchy through the IFU
(`ftq_ifu_interfaces.md`), and `ftq_decisions.md` 0 records why.
That argument is unchanged by L1I-2 below.

---

## 1. Geometry

### 1.1 The numbers

```
  L1I-1  capacity 64 KiB, 8-way, 64-byte lines, 128 sets
```

| Derived        | Value | From                          |
|----------------|-------|-------------------------------|
| sets           | 128   | 65536 / (8 * 64)              |
| banks          | 2     | L1I-11                        |
| sets per bank  | 64    | 128 / 2                       |
| line bits      | 512   | 64 * 8                        |
| ways           | 8     | L1I-1                         |
| bytes per way  | 8192  | 65536 / 8                     |

CAPACITY. 64 KiB is where current high-performance I-sides sit:
every Neoverse and every Cortex-X, SiFive P870, XuanTie C910 and
C930, XiangShan Kunminghu, and Intel from Redwood Cove onward. AMD
holds 32 KiB and is the outlier among 8-wide machines, and does it
with two independent fetch pipes each feeding its own decode
cluster, which is not this design. Apple's 192 KiB is the other
outlier. 32 KiB was the value in the initial pacino configuration
and is below the class this machine targets.

ASSOCIATIVITY. 8-way is the common value; Kunminghu uses 4-way on
the I-side against 8-way on the D-side, and that asymmetry is
deliberate in designs that index virtually (section 2.2). Under
PIPT the constraint that motivates it does not apply, so the I-side
takes the same 8 ways as the D-side.

LINE SIZE. 64 bytes, matching every other node in pacino and every
design in the survey except the IBM machines. Two 32-byte
prediction blocks fit one line, which is the arrangement L1I-14
depends on.

### 1.2 Address decomposition

Fields are physical throughout (L1I-3). With 2 banks and line
interleaving the bank select is taken OUT of the index rather than
added beside it, so `offset + index + tag == pa_bits` still holds.

```
  offset   PA[5:0]     6 bits
  index    PA[12:6]    7 bits
  bank     PA[6]       1 bit    line interleaved
  setidx   PA[12:7]    6 bits   64 sets per bank
  tag      PA[pa_bits-1:13]     pa_bits - 13 bits
```

THE TAG WIDTH IS NOT FIXED because `pa_bits` is not decided; see
L1I-U1. At the 36 bits recommended there the tag is 23 bits and the
tag array is 128 * 8 * (23 + 1 valid) = 24576 bits.

---

## 2. Indexing and translation

### 2.1 The decision

```
  L1I-3  The L1I is PHYSICALLY INDEXED AND PHYSICALLY TAGGED.
         Translation completes before the array is indexed.
```

### 2.2 Why not VIPT

VIPT works without alias handling only when index+offset fits
inside the page offset, because those bits are untranslated. At 4
KiB pages the page offset is PA[11:0] and index+offset spans
`capacity/ways` bytes:

```
  32 KiB 8-way    4096 bytes/way   [11:0]   0 alias bits
  64 KiB 8-way    8192 bytes/way   [12:0]   1 alias bit
  64 KiB 4-way   16384 bytes/way   [13:0]   2 alias bits
  64 KiB 16-way   4096 bytes/way   [11:0]   0 alias bits
```

At the L1I-1 geometry VA[12] is a translated bit, so two virtual
addresses mapping to one physical line index two different sets.

For READ TRAFFIC that is benign: a duplicate line is wasted
capacity, and with no write path there is no stale-data hazard. It
is not benign for INVALIDATION. A `cbo.inval` naming a physical
address does not know VA[12], so it must clear every aliasing set
or leave a stale instruction line behind, and one stale instruction
line after a `FENCE.I` is a correctness failure. Section 7 is
therefore where the cost of VIPT would have landed.

Three configurations avoid it: 64 KiB 16-way (pays 16 comparators
and a 15-bit PLRU state for nothing else), 32 KiB 8-way (pays
capacity), or PIPT. PIPT was taken. It costs a translation ahead of
the array, which the decoupled front end absorbs (2.4), and it
makes the capacity and associativity choices free of the
constraint entirely.

Kunminghu runs 64 KiB 4-way, which is two alias bits, so the
aliasing configuration is shippable. It is not cheaper here.

### 2.3 The ITLB boundary

```
  L1I-4  The L1I receives a PHYSICAL address on its core
         interface. It performs no translation and holds no
         translation state.
```

The ITLB is above the L1I, in the fetch path, and is owned by
`itlb_decisions.md`. What the L1I requires of it:

```
  T1  the physical address, valid, in the cycle the request is
      presented
  T2  a fault indication travelling with the request rather than
      through the L1I, so a translation fault does not become a
      cache access. The L1I never sees a faulting request
  T3  no L1I involvement in ITLB fill, shootdown or ASID
      management
```

T2 places the fault path between ITLB and IFU. The L1I has no
exception behaviour of its own beyond what section 5 returns from
the L2.

### 2.4 Latency

```
  L1I-5  Hit latency is 2 cycles. Tag compare is in the cycle
         after the array read (tag_compare_stage next_cycle).
         Hit THROUGHPUT is one request per cycle, pipelined.
```

Two is an array-timing figure: tag read, compare, way select and
data mux at 64 KiB do not close in one clock at the frequency this
machine targets, and forcing them to is what caps frequency.

LATENCY IS NOT THE FETCH-PATH NUMBER. Translation is a stage above
the array (2.3), so the path from PC to instruction data is the
ITLB latency plus 2. Record both; a reader taking 2 as end-to-end
will size the IFU pipeline short.

Latency is not on the dependent-load critical path that produces
the published 3- and 4-cycle L1D figures in the survey. On the
I-side the FTQ run-ahead absorbs it (`ftq_decisions.md` 5.1), which
is what the decoupled front end is for. THROUGHPUT is the figure
that matters, and it is one 64-byte line per cycle.

---

## 3. Storage and replacement

```
  L1I-6  tag_array and data_array are inferred SRAM with
         registered read. valid_bits and replacement_bits are flop
         files with combinational read, cleared by reset.
  L1I-7  Replacement is tree-PLRU, 7 bits per set for 8 ways.
  L1I-8  Arrays are per-way with parallel access
         (array_per_way, parallel).
```

Flop-file valid bits are what makes reset clear the cache in one
cycle. The l2 node declares its valid bits as SRAM and walks the
sets after reset to clear them through an invalidate port; the L1I
is small enough not to need that, and section 7's `invalidate_all`
uses the same reset-branch clear.

Tree-PLRU out of reset selects way 0, so a cold set fills from way
0 upward. No entry is valid until written, so replacement state is
not consulted before it is meaningful.

REPLACEMENT POLICY IS RARELY PUBLISHED and the survey carries only
one data point: XuanTie C910 ships FIFO on both L1s. Tree-PLRU is
the assumed policy everywhere else and is what the other pacino L1
uses. No case was found for revisiting it.

---

## 4. The core interface, to the IFU

### 4.1 Shape

```
  L1I-9   The core interface returns ONE FULL CACHE LINE, 64
          bytes, per request. The data path is 512 bits.
  L1I-10  Up to EIGHT requests may be outstanding.
```

The port in the initial pacino configuration was 32 bits wide with
one outstanding request. That is a test-agent port. It cannot feed
an 8-wide front end, and a single outstanding request collapses the
decoupling the FTQ exists to provide: the FTQ runs up to 64 entries
ahead precisely so fetch can be pipelined across misses, and a
blocking port serialises that back down.

Eight outstanding is chosen against the sixteen MSHRs of L1I-12: it
is enough that the IFU is not the limit on miss parallelism, and
below the MSHR count so a full request pipeline cannot on its own
exhaust miss tracking.

### 4.2 The line buffer is the IFU's

```
  L1I-14  The IFU holds the returned line and extracts the
          32-byte fetch block. The L1I holds no last-line
          register and answers every request from the array.
```

Two 32-byte prediction blocks fit one 64-byte line, so on
sequential fetch the second block is served from the IFU's buffer
and never reaches the L1I. That halves the L1I request rate on
straight-line code, which an L1I-side register would not do -- it
would save array power but the request would still cross the port.

The IFU also already knows about redirects, so a buffered line for
an abandoned path is dropped by the module that knows it is stale.
An L1I-side register would hold it until displaced. Harmless, since
the tag still matches, but it is state nobody owns.

The buffer is specified in `ifu_decisions.md`, not here. What this
document fixes is that the L1I does not have one.

### 4.3 Ordering and alignment

```
  R1  Requests carry a physical address (L1I-4) and are LINE
      ALIGNED. The IFU performs the block extract, so the L1I
      never sees a sub-line address
  R2  Responses may return OUT OF ORDER with respect to requests.
      A response carries the identifier of the request it answers.
      Requiring in-order return would make one miss block every
      hit behind it, which is the blocking behaviour L1I-10
      removes
  R3  The RVA23 C extension permits a fetch to begin on any
      2-byte boundary. That is the IFU's problem, not the L1I's,
      and is why R1 can be line aligned
```

---

## 5. The memory interface, to the L2

### 5.1 Inclusion

```
  L1I-15  The L1I is NON-INCLUSIVE with respect to the L2. The L2
          does not track, and cannot invalidate, L1I lines.
```

Inclusion buys exactly one thing: an external coherence probe can
be filtered at the L2 without disturbing the caches above it,
because the L2's tags are a superset. Nothing probes the I-side.
RISC-V does not make the instruction cache coherent with the data
side -- `FENCE.I` is the architectural mechanism and the burden is
on software -- so there is no probe traffic to filter and inclusion
is cost with no return.

THE l2 NODE'S `inclusive` DECLARATION IS WRONG FOR ITS `up_i`
INTERFACE. Inclusion is a property of a pair of caches and the
current configuration encodes it twice: `l1i` declares `nine` and
`l2` declares `inclusive`. This decision resolves the disagreement
in the l1i node's favour. Whether the l2 remains inclusive of the
L1D is an L2 question and is not decided here. TD-L1I-1.

### 5.2 The link

```
  L1I-16  TL-UH. Channels A and D only. No B channel and no probe
          path, which follows from L1I-15.
```

A prior reading of the configuration reported the absence of
channel B as a defect, on the strength of the l2 node's inclusive
declaration. With L1I-15 the link is correct as configured and
needs no change.

```
  data width      256 bits, 32 bytes per beat
  refill beats    2 per 64-byte line
  beat order      critical first
  bypass          to upstream, enabled
```

CRITICAL FIRST MATTERS HERE. The requested 32-byte block returns in
the first beat and is forwarded upstream as it arrives, so a miss
costs the L2 latency and not the L2 latency plus a second beat.
`bypass_to_upstream` is what permits the forward; both fields are
already set in the configuration and this records why they must
stay.

---

## 6. Miss handling

```
  L1I-12  16 MSHRs.
  L1I-13  4 targets per MSHR.
  L1I-17  No victim buffer and no separate fill buffer. Fills
          land in the array; the MSHR carries the in-flight
          state.
```

MSHR COUNT. The survey's I-side figures: XuanTie C910 tracks 8 line
fills; Neoverse V2 has a 16-entry L1i fill buffer, which Arm states
is enough MLP to sustain 4 IPC running out of L2; Intel Lion Cove
has 24 L1 fill buffers; AMD Zen 5 tracks 124 outstanding L1 misses
across two independent fetch pipes. The Neoverse figure is the
usable anchor: it is a per-core I-side structure with a published
sustained-IPC claim attached to it. This machine targets 8 issue
against Arm's 4 IPC from L2, so 16 is a floor derived from a design
achieving half the target, not a comfortable margin. The initial
pacino value of 4 is below every published I-side in the survey.

TARGETS PER MSHR. Two 32-byte blocks per line makes 2 the bare
minimum -- it merges a line's own second half and nothing else --
and the FTQ run-ahead means several queued fetches can land on one
line. 4 matches the l1d and l2 nodes.

---

## 7. Maintenance and invalidation

```
  L1I-18  The only invalidate path is CORE SIDE, arriving through
          the IFU. There is no memory-side invalidate; L1I-15.
          invalidate_line and invalidate_all are supported;
          flush_line and flush_all are not.
```

There is nothing to flush. The L1I is read-only, holds no dirty
state, and has no write path to the L2.

DRIVERS:

```
  M1  FENCE.I. Invalidates the whole cache. Implemented by the
      reset-branch clear of the flop valid bits (section 3), so
      it is a single-cycle operation
  M2  Zicbom. RVA23 mandates it. cbo.inval names one line by
      address. Under PIPT that address indexes directly and no
      alias search is needed, which is the second return on
      L1I-3
```

M2 IS NOT FULLY SPECIFIED. Whether `cbo.inval` on an instruction
cache reaches the L1I at all depends on `menvcfg.CBIE` and on how
the execution environment is configured -- the privileged
architecture permits the instruction to trap or to be remapped to a
flush. TD-L1I-2 carries it. The port exists either way; what is
undecided is what drives it.

---

## 8. Prefetch

```
  L1I-19  Instruction prefetch requests ORIGINATE AT THE IFU. The
          L1I has no prefetcher and no FTQ-facing prefetch path.
```

This is the pacino form of `ftq_decisions.md` 6.1, restated so it
survives the restructuring of L1I-2. That section defers prefetch
and records its structural cost; the ICache becoming a sibling of
the IFU does not make an FTQ-to-ICache prefetch path any more
available, because the run-ahead stream between `fetch_ptr` and
`alloc_ptr` exists only inside the FTQ and the IFU is behind
`fetch_ptr` by construction.

### 8.1 Arbitration

```
  P1  Demand fetch always wins. A prefetch is issued only in a
      cycle no demand request needs the port
  P2  A prefetch never occupies an MSHR a demand miss requires. A
      prefetch that would exhaust miss tracking is dropped, not
      queued
  P3  A dropped prefetch is not retried. It was a hint
```

THIS IS A PARAMETER, NOT PROSE. The configuration schema gains a
`prefetch_arbitration` field with an enumerated value naming this
policy, so the rule is emitted rather than reimplemented per node.
A policy stated only in a document is a policy that drifts from the
RTL. TD-L1I-3 tracks the schema addition.

### 8.2 The hint path exists

TileLink's `TlAIntent` is already in the shared opcode package and
is non-binding by construction, which is exactly the semantics P2
and P3 require. No new link feature is needed to carry a prefetch
to the L2.

---

## 9. Configuration mapping

What the l1i node in `pacino_caches.json` must carry for the
decisions above. Values differing from the initial configuration
are marked.

| Field                    | Value          | Decision | Changed |
|--------------------------|----------------|----------|---------|
| capacity_bytes           | 65536          | L1I-1    | yes     |
| line_bytes               | 64             | L1I-1    |         |
| associativity            | 8              | L1I-1    |         |
| banks                    | 2              | L1I-11   | yes     |
| bank_interleave          | line           | L1I-11   | yes     |
| indexing                 | PIPT           | L1I-3    | yes     |
| read_miss                | allocate       |          |         |
| replacement              | tree_plru      | L1I-7    |         |
| inclusion                | non_inclusive  | L1I-15   | yes     |
| mshrs                    | 16             | L1I-12   | yes     |
| mshr_targets             | 4              | L1I-13   | yes     |
| victim_buffer_entries    | 0              | L1I-17   |         |
| fill_buffer_entries      | 0              | L1I-17   |         |
| beat_order               | critical_first | L1I-16   |         |
| bypass_to_upstream       | true           | L1I-16   |         |
| read_latency_cycles      | 2              | L1I-5    |         |
| tag_compare_stage        | next_cycle     | L1I-5    |         |
| invalidate_line          | true           | L1I-18   |         |
| invalidate_all           | true           | L1I-18   |         |
| flush_line               | false          | L1I-18   |         |
| flush_all                | false          | L1I-18   |         |
| prefetch_arbitration     | demand_first   | L1I-19   | NEW     |

Core link, replacing the `pe_port` shape:

| Field                    | Value | Decision | Changed |
|--------------------------|-------|----------|---------|
| read_width_bits          | 512   | L1I-9    | yes     |
| address_width_bits       | pa_bits | L1I-4  | yes     |
| outstanding_requests     | 8     | L1I-10   | yes     |
| write_width_bits         | 0     | read only| yes     |
| out_of_order_response    | true  | R2       | NEW     |

`pe_port` is shared with the LSU-to-L1D edge in the current
topology. The I-side and D-side core ports are now different
shapes, so either the link is parameterised per edge or a second
link type is declared. TD-L1I-4.

SYSTEM FIELDS. `pa_bits` is a system-level field carried by every
node's package. Changing it is not an l1i-local edit; see L1I-U1.

---

## 10. Open items and technical debt

### 10.1 Open, blocking specification

```
  L1I-U1  pa_bits. Undecided. Sizes the tag array directly, at
          128 * 8 bits per bit of PA in the L1I alone and again in
          every other node.
          RVA23 does NOT fix it: Sv39 sets an upper bound through
          the PTE's PPN field and the implementation chooses how
          much to implement. RECOMMENDATION: 36 bits, which is
          what XiangShan Kunminghu implements under Sv39. The
          current configuration value of 32 is almost certainly
          too small once MMIO is placed alongside DRAM.
          NOT RULED. Jeff's decision.

  L1I-U2  The ITLB. Entries, associativity, page sizes, ASID
          width, and its own latency. Under PIPT it is on the
          fetch path, so 2.4's stated latency is incomplete until
          this is decided.
          RECOMMENDATION, from the survey and from XiangShan: 32
          entries, fully associative, all three Sv39 page sizes,
          ASID tagged, 1-cycle hit. Fully associative removes the
          index-versus-page-size problem that a set-associative
          TLB has with mixed page sizes.
          NOT RULED.

  L1I-U3  The page table walker's position in the pacino
          topology. This is a NODE GRAPH change, not a parameter.
          XiangShan's arrangement, read from its design
          documentation: the MMU is L1 TLBs (ITLB, DTLB), a
          repeater, an L2 TLB, PMP and PMA; the L2 TLB contains
          the page cache, the walker, a last-level walker, a miss
          queue and a prefetcher; walker requests are arbitrated
          and sent over TileLink to the L2 cache, whose 512-bit
          width returns eight PTEs per access. The L1 TLBs are
          NON-BLOCKING: a miss is returned to the requester, which
          reschedules the query until it hits.
          RECOMMENDATION: a shared L2 TLB node containing the
          walker, with a TileLink master edge into l2 alongside
          up_i and up_d, and a non-blocking ITLB that returns miss
          to the IFU for retry.
          NOT RULED. It adds a node and an edge to pacino.

  L1I-U4  PMP and PMA. XiangShan places them in the MMU boundary
          and the walkers check physical addresses before
          accessing memory, with an access fault returned up to
          the L1 TLB, which raises an instruction access fault to
          the request source. Nothing in pacino has a PMP or PMA
          node. Where they sit is undecided and it affects the
          fault path of T2.

  L1I-U5  The IFU line buffer's depth and its redirect behaviour.
          Belongs to ifu_decisions.md and is named here only so
          L1I-14 has an owner.
```

### 10.2 Technical debt

```
  TD-L1I-1  The l2 node declares inclusive while l1i declares
            nine. L1I-15 resolves it for the I-side; the l2 node's
            declaration must be qualified per upstream interface,
            or the schema must carry inclusion on the pair rather
            than on each node. Schema question, not an l1i one.

  TD-L1I-2  cbo.inval reaching the L1I depends on menvcfg.CBIE and
            on the execution environment. Section 7 M2 specifies
            the port; what drives it is unverified. Check against
            the privileged specification before the IFU-side
            maintenance path is built.

  TD-L1I-3  prefetch_arbitration does not exist in the
            configuration schema. Section 8.1 states the policy;
            the schema must gain the field or the policy lives
            only in prose and will drift.

  TD-L1I-4  The core link shape now differs between the I-side and
            the D-side. pe_port is declared once and used on both
            edges. Either parameterise per edge or declare a
            second link type.

  TD-L1I-5  Nothing in the l1i configuration covers parity or ECC
            on the tag or data arrays. Absent from the schema
            rather than declined. A read-only cache can recover
            from a detected error by invalidating and refetching,
            which is cheaper than the D-side case and worth
            taking. Not decided.
```

---

## 11. Consequential edits elsewhere

```
  L1I-2  THE ICACHE IS AN INDEPENDENT MODULE within the front-end
         boundary. It is a SIBLING of the IFU, not instantiated
         inside it, and the IFU exposes the interface to it.
```

Two documents state the superseded position and must be amended,
not deleted:

```
  ftq_decisions.md 0    reads that the ICache is encapsulated
                        behind the IFU. Amend to the sibling
                        relationship. WHAT MUST SURVIVE is the
                        rest of the section: there is still no
                        FTQ-to-ICache interface, and the argument
                        for that is the fanout pressure XiangShan
                        solved with register replication being a
                        PD-phase problem rather than a logical
                        interface carried from the start.
                        Independence changes the module hierarchy;
                        it does not change that.

  PROJECT_CORE.md       repeats the same sentence in its planning
                        inventory. Same amendment.
```

Both are PA-direct edits. Neither is in scope for an IA task.

---

## 12. Document History

```
  2026-08-27  Created, session-068. Geometry, indexing, storage,
              both interfaces, miss handling, maintenance and
              prefetch decided as L1I-1 through L1I-19. PIPT taken
              over VIPT, which makes the 64 KiB 8-way geometry free
              of the alias constraint and removes the multi-set
              invalidate that section 7 would otherwise have
              needed. The L1I is non-inclusive with the L2, so
              TL-UH is correct as configured and there is no
              back-invalidate. Capacity, associativity and MSHR
              count derived from the published survey rather than
              from the initial configuration; the core port
              rewritten from a 32-bit single-outstanding test port
              to a 512-bit line-at-a-time port with eight
              outstanding. pa_bits, the ITLB, the walker topology
              and PMP/PMA are recorded OPEN with recommendations
              and are not decided here.
```

