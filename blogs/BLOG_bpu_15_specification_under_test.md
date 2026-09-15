<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->

```
TITLE:     "The RAS and the FTB: Design Choices at p2"
FILE:      BLOG_bpu_15_specification_under_test.md
AUTHOR:    Jeff Nye
DATE:      2026-09-04
STATUS:    REVIEWED
COPYRIGHT: "Copyright 2026 Jeff Nye"
```

<!--
---

::SERIES DESCRIPTION::
::BEGIN LINKS::
::END LINKS::
-->

# The RAS and the FTB: Design Choices at p2

EDITED: 2026-09-14, ticfinder/clarity/length

## Abstract

The return address stack (RAS) and fetch target buffer (FTB) were
completed in these sessions in 10 implementation tasks. The RAS completed
unit testing with 87 directed tests. The FTB completed with 99 directed
tests. The RTL and the planning documents were reconciled.

In the RAS design a pop moves the read pointer leaving the popped entry
data on the stack until over-written. This allows a mispredict recovery
to simply restore the three pointers, `tosr`, `tosw` and `bos`, 12 total
bits stored in the relevant fetch target queue (FTQ) entry. With intact
stale entries no replay mechanism is required to restore past values.

There is one slot in the RAS held as a permanent sentinel. This keeps the
write pointer monotonic. Each entry includes a recursion counter to
reduce consumption of RAS entries for recursion.

The FTB storage is split into two arrays, one RAM based, with the valid
and the tree PLRU bits stored in a flop array. The FTB entry contains a
3-bit bimodal direction counter.

The FTB entry stores a branch's in-block position in 4 bits, at the
2-byte granularity the C extension requires, and the conditional and jump
target displacements in 13 and 21 bits. The fall-through address is a
5-bit `pftAddr`, an offset from the block start plus a carry bit, from
which the full address reconstructs as block-start + `pftAddr` + carry.
And an update borrows the prediction read ports, at the cost of a bubble
the FTB already pays as a p2 override.

There was a process change confirmation in this session. The RAS
operation enumeration table mis-labeled an undo-pop operation as a push.
The IA implemented the push. A directed test showed the failure and was
reported by the IA. This process exercised the new 'report failures and
quote planning document' instructions. The RTL and planning documents
were resolved.  The test was written as TC-17 (test case) of BP-063.
The RTL was corrected.

## Design state

`ras.sv` is a single self-contained module. Its testbench closes at 87
directed checks.

The FTB is four modules, `ftb_array`, `ftb_plru`, `ftb_cntrl` and the
structural top `ftb`. The FTB closes at 99 directed checks.

The planning documents: `ras_decisions.md`, `ras_interfaces.md`,
`ftb_decisions.md` and `ftb_interfaces.md` were reconciled to the RTL.

## The RAS: pointer-only recovery

The RAS is two independent arrays. The 16-entry speculative stack covers
call depth in flight between fetch and commit; the 32-entry commit stack
covers the committed call nest. A unified 48-entry pool was considered and
rejected: the static partition confines mispredict restore to the
speculative array and commit advancement to the commit array, keeps
overflow detection at fixed limits on each, and at a 48-entry total budget
a shared pool offers no flexibility worth the pointer arithmetic.

The two arrays meet at two points. When a call-containing block commits
from the FTQ its return address is pushed onto the commit stack, and `bos`
advances to the committing entry's post-operation `tosr` to mark the new
committed boundary; a restore in the same cycle takes priority over the
commit. When the speculative stack is empty, `tosr == bos`, a pop returns
the commit stack top without consuming it.

Three pointers index the speculative buffer. `tosr`, the top-of-stack
read pointer, sources predictions. `tosw` is the next free allocation
slot. `bos` is the committed boundary. A push writes the return address
and recursion count at `tosw` and sets `tosr` to the slot just written. A
pop presents the `tosr` entry and decrements `tosr`. `tosw` does not
move.

Because `tosw` never retreats, entries stay valid until overwritten, and past
values are still in the array when a misprediction resolves. Misprediction
recovery is then a write of three pointers, `tosr`, `tosw` and `bos`, 12 bits
snapshotted per FTQ entry.  No replay is required to restore past values. 

A flush takes the same path as a mispredict redirect, because there is nothing
a flush needs to do to the RAS that a redirect does not already do. The
alternative considered was a linked speculative structure, which was rejected
on the grounds that the complexity is not repaid: pointer-only recovery is what
the buffer already supports, and the fallback for detected corruption is the
commit stack.

### The sentinel slot

The `bos` index is a permanent sentinel. A push that would place `tosw` on
`bos` allocates at `bos+1` instead, which occurs only at cold start or on a
full wrap.

The sentinel exists because without it a stack holding one entry is
indistinguishable from an empty one. Reset zeros all three pointers, so a
single push leaves `tosr` and `bos` both at 0 and the emptiness test `tosr ==
bos` reports empty with a live entry present. The entry is then invisible to
the p0 top-of-stack read, a subsequent pop falls through to the commit stack,
and the bottom-most speculative entry can never be popped.

The sentinel costs one entry of usable depth, 15 live entries in 16 physical
slots, and preserves the monotonic `tosw` on which pointer-only restore
depends. The alternative, taking `tosw == bos` as the emptiness test, requires
the pop to decrement `tosw`. A non-monotonic `tosw` admits a wrong-path pop
followed by a push that overwrites a still-live entry, which a later restore
re-exposes as valid data.

On a wrap the allocation is at `bos+1`, so `tosr` becomes `bos+1` and reachable
depth collapses to one entry in a single push. The older entries remain
resident and become unreachable; the next pop meets `tosr == bos` and takes the
commit stack fallback. Degradation is bounded by that fallback, not gradual.

### The recursion counter

Each RAS entry carries a 4-bit recursion counter with the conventional
semantics. A push whose return address matches the entry at `tosr` increments
the entry's counter.  Recursive chains occupy one slot.  The counter saturates
at 15, and a pop decrements it without moving `tosr` until it reaches zero.

The purpose is to protect the depth budget. A 15-entry usable speculative
stack covers in-flight call depth between fetch and commit, and a
recursive chain that allocated one slot per call would exhaust it on a
workload where the true call nest is shallow.

## The FTB storage partitioning

`ftb_array` is 4-way over 512 sets, with a combinational read and a
synchronous write. That gives read-old-on-collision with no state
element, which is what the Pacino specification requires and which leaves a
registered 1R1W SRAM a valid substitute.

The array holds entry data. The `ftb_plru` module holds the four
entry-valid bits and three tree-PLRU bits per set in flops,
3,584 flops in total. `ftb_cntrl` contains the logic and drives both
storage peers. FTB valid and plru state is initialized on reset.

Both storage modules return old contents on a same-cycle read against a
write to the same set, so a prediction issued in the same cycle as an
update sees data and validity from a single point in time, both from
before the update.

## The FTB entry

### Entry field widths

The position field holds the in-block position of a branch instruction and
supports 2-byte granularity, per the C extension requirement of RVA23S64. The
block is 32 bytes the position field is 4 bits. The `pftAddr`field, the stored 
partial fall-through address, is 5 bits.

`pftAddr` is the block's end address, the fall-through address, stored
compactly. The entry stores the offset from the block start, plus
one carry bit for when the end crosses the block boundary. The full
address is reconstructed as block-start + `pftAddr` + carry. The five
bits are four to name a 2-byte unit within the 32-byte block, plus the
carry bit. See [F1].

The target displacement fields hold branch reach. A B-type immediate
reaches plus or minus 4 KB and a J-type plus or minus 1 MB, 12 and 20
bits as encoded. Pacino expands RVC instructions to 32 bits before the
FTB, so a given reach spans twice the bytes and each field gains one bit:
13 and 21.

The tag is a full 26-bit upper-VA tag. Two PCs cannot alias to one entry, so a
hit is always the correct entry for the looked-up PC, and the `pftAddr`
reconstruction is used unconditionally with no validation. The FTB does no
self-checking; a corrupt entry is an upstream state defect, not a designed-for
event.

### FTB override suppression mechanism

A 3-bit saturating bimodal counter per conditional branch carries the FTB's
direction prediction. Its most significant bit is the predicted direction; its
magnitude is the strength of that prediction.  The FTB always submits a
direction for a valid conditional.

The FTB fast path is a latency optimization for certain branch sequences.  An
FTB prediction can typically be overridden by a later TAGE or SC prediction.
However when the FTB confidence counter is saturated any override from TAGE or
SC is suppressed. This is the FTB 'fast path', which saves a cycle in those
cases where the FTB confidence is very high. If the FTB is incorrect the
confidence counter will natively train to less confidence and the system will
correct itself towards high prediction accuracy.

The two saturated states, 111 and 000, enable the fast path mechanism.  In
every other state the submitted FTB prediction can be overridden in favor of
the later prediction which tend to be more accurate.

There is a required global enable for the fast path mechanism, ftb_fastpath_en,
which must be set for the override suppression to be available.

## Sharing the read ports

`ftb_array` and `ftb_plru` are single-ported, and an update is
read-modify-write on the carried entry's confidence and target and on the
set's PLRU state. Update takes the port and a coincident prediction is
dropped; the FTB already costs a bubble as a p2 override, so the drop is
not a new cost. The update addresses by the carried set index and does not
re-look-up the tag, the way and hit are determined at the prediction read
and carried through the FTQ.

## Correcting a mislabeled operation in the RAS enumeration table

An earlier post in this series described a transposition error in the
TAGE and ITTAGE counter tables, and made the general point that an error
in a planning file usually ends up in the RTL and in the test vectors,
since both are written from the same document. That case ended well: the
implementation assistant built the specification as written and then
reported that the rules diverged from conventional bimodal counter
practice, and the error surfaced from its own extrapolation. The RAS
produced the same error class with the opposite ending.

The p3 operation enumeration table, IC-RAS-11, labels two different
repairs "push". One is a missed push, where p2 did nothing and p3
resolves a call: no entry exists, so allocating one at the frontier from
the registered fallthrough is correct. The other is an undo-pop, where p2
popped and p3 disagrees. There the entry that was consumed is still in
the array, because a pop leaves it there, so the repair is to move `tosr`
back and reload the address and recursion count from the array. No entry
is created, and the registered fallthrough is not a call return address.
In that table "push" means restoration of stack height over a
still-resident entry, and only the missed-push row allocates and writes.
The implementation read the word and built the allocate path for both
rows. Nothing else in the document contradicted it loudly enough to stop
that, and the assistant did not flag it.

A directed test found it instead. TC-17 seeded one entry at index 1,
popped it, and forced p3 to disagree, expecting `tosr=1` with the top
reading `0x9000`. It observed `tosr=2`, `tosw=3`, and a top of `0x0000`.
The fix splits the repair on the registered p2 operation: when p2 was a
pop, the repair is a `tosr`-only re-expose with no array write and `tosw`
held; when p2 was a no-op against a resolved call, the frontier
allocation is kept. The instruction that came with the fix was to correct
the table's wording as well, because repairing only the RTL would leave
the next reader of IC-RAS-11 free to make the same reading.

## Items left open for cluster integration.

Four items are open across the two units. All four are deferred to bp_cluster
or FTQ integration.

**The p3 repair does not reverse a recursion-decrement pop (TD #78).** A
pop that only decremented a recursion counter cannot be undone; the
pre-pop count is not recoverable from post-pop state. The fix is a
pre-operation count carried per in-flight entry, which is not justified
until such a repair is needed. TC-21 pins the current behavior.

**The commit stack does not preserve recursion depth (TD #79).** The
recursion field on a commit entry is write-only, so a recursive call that
commits reads back from the fallback as a single entry. The effect is a
degraded fallback prediction, not a functional break. A fix needs a
recursion-count source on the commit interface, which is an FTQ decision.

**Confidence-override interaction with the TAGE update and metadata path
(FTB-2).** The fast path suppresses TAGE and SC use but not their
training. Who owns that obligation, and what the metadata path does under
a suppressed override, is a cluster question.

**Update-channel arbitration (FTB-3).** The FTB exposes one update port.
How multiple resolved branches are scheduled onto it belongs to the FTQ.

Two smaller items are in the debt table: confidence hysteresis tuning,
where `FTB_CONF_WIDTH` is the knob and the trigger is cluster SPEC
numbers, and a br0 coverage skew in `tb_ftb`.


## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| BP-062 | ras.sv implemented; RAS parameter block replaced; authorized tb_bp_pkg.sv width fix | PASS | 9 lint / 12 sim green | 15m 8s+ | 15% (understated) |
| BP-063 | tb_ras.sv, 20 directed cases; two ras.sv defects found and fixed under authorization | PASS | 79/0, 22/22 targets | 21m 12s | 22.4% |
| BP-064 | RAS verification and reconciliation round; TC-21 pins TD #78; no RTL change | PASS | 87/0, 22/22 targets | 8m 16s | 15% |
| BP-065 | ftb_array; FTB parameter block found broken and rewritten | PASS | 10 lint / 13 sim green | 6m 57s | 10% |
| BP-065a | Storage split finalized; ftb_array to pure RAM, ftb_plru created | PASS | 11 lint / 13 sim green | 4m 51s | 10% |
| BP-066 | ftb_cntrl, all FTB logic; shared read-port borrow; position gap reported | PASS | 11 lint / 13 sim green | 14m 11s | 18% |
| BP-066a | Confidence redefined to bimodal direction; always_taken removed | PASS | 13 lint / 13 sim green | 7m 8s | 12% |
| BP-066b | In-block position sourced and sunk, FTB-4 closed | PASS | 26/26 targets | 5m 3s | 9% |
| BP-067 | ftb structural top; later revised by BP-066a and BP-066b | PASS | 26/26 targets | 2m 57s | 9% |
| BP-068 | tb_ftb self-checking directed suite against the top | PASS | 99/0, 27/27 targets | 18m 13s | 22% |

## Design Process Notes

The RAS testbench found the emptiness defect on its first run, at 10 passing
and 6 failing. The implementation assistant stopped, reported, and offered
three fixes. After consulting the planning assistant, I accepted the
recommendation, changing the emptiness test to `tosw == bos`, on the stated
grounds that it was the smallest RTL change.

That recommendation was a mistake the planning assistant was focused on minimal
changes to the RTL, and the implementation assistant said so before writing any
code. A pop decrements only `tosr`. `tosw` is monotonic by design, and
`ras_decisions.md` section 3.2 states the reason directly: no data is
overwritten on pop. With a monotonic `tosw`, an emptied stack still has `tosw`
at the frontier and `bos` at the floor, so `tosw == bos` would report non-empty
when the stack is empty. Making that test correct requires the pop to decrement
`tosw` as well, which surrenders pointer-only restore.

The key points the bad option came from the same assistant that caught it, so
the proposal and the catch were not independent events.  And the selection
criterion was size of change, which carries no information about correctness.
The chosen option would have passed every directed test in the suite while
leaving the corruption path open.

I took a fourth path. Re-base allocation keeps the correct emptiness test,
keeps `tosw` monotonic, and pays one entry of speculative depth. This is in the
current design.

## Technical Debt Referenced

The table below reports status as of the close of this range. Later
experiments outside the range have since changed the state of some items
carried alongside these.

| # | Item | Resolution path |
|---|---|---|
| 78 | RAS p3 undo-pop repair does not reverse a recursion-decrement pop. | PINNED by tb_ras TC-21 (BP-064). The pre-pop recursion count is not recoverable from post-pop working state. Left as-is deliberately; the test locks the limitation open. Revisit at bp_cluster integration if a p2/p3 repair over a recursion pop is ever required. Related: #79. |
| 79 | RAS commit-stack recursion depth not preserved. | DEFER. The field is write-only and never read by any output path, so a wrong value degrades the fallback prediction only. A real fix needs a recursion-count source on the commit interface. Decide at FTQ integration. Re-scoped from a fix to a deferral in BP-064. |
| 80 | FTB confidence hysteresis tuning. | FTB_CONF_WIDTH is the knob. Revisit at bp_cluster SPEC numbers. The entry's wording predates the BP-066a confidence redefinition and still describes threshold suppression; the mechanism is now the saturated-endpoint fast path. |
| 81 | tb_ftb coverage skews to br0. | Optional symmetric br1 augment. The br1 direction and confidence init are exercised once, through the free-field write; the second fast-path bit and a br1 saturation path are not directly exercised. The fast path is generated per field in a loop sharing logic with the tested bit, so the risk is bounded. Not a blocker; sim_ftb 99/0. |

## Next steps

Most of what remains waits on the cluster and the FTQ. On the FTB: the
flush protocol, which has no definition yet; the fast path's interaction
with TAGE and SC metadata; update-channel arbitration; the FTQ round trip
for the carried way; and the source of the fast-path enable. On the RAS,
TD #79 waits on a recursion-count source on the commit interface.

Two items are unit work. TD #78 would be repaired in `ras.sv` by carrying
a pre-operation recursion count, should cluster integration show that a p3
repair over a recursion pop is required. TD #81 is a coverage gap in
`tb_ftb`.

That leaves `bp_history`, which the cluster work needs before it can
start, and the statistical corrector, which was the last unbuilt predictor
at the time of these sessions.

---

## References

- Contradiction Detection: When the Planning Document Is the Defect
  (BLOG_bpu_13), for the earlier case of a planning-file error reaching
  both the RTL and the tests.

---

## Footnotes

[F1] The position field was 3 bits at the close of this set of sessions,
addressing the expanded-instruction granularity, and `pftAddr` was 4 bits. In
later sessions BP-099 widened the position field to 4 bits so that it resolves
to 2 bytes, which the RVA23 C extension requires, and `pftAddr` followed to 5.
`POS_OFFSET_BITS` is derived as `FTB_OFFSET_BITS - FTB_BR_POS_BITS`, so it
rescaled from 2 to 1 without a separate edit. The widths given above are the
current ones; 3 bits was the design at the time this work closed.

---

<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry
experience spanning performance modeling, RTL implementation, and
architecture for high-performance OOO processors. He has contributed RTL
to Pentium 4, Arm v7, TI C6x and RISC-V designs, and recently served as
sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE
branch prediction cluster in an 8-issue RVA23 RISC-V processor, from
research through timing closure at 2.75 GHz. He holds more than 20
issued patents in processor design, architecture, and hardware
virtualization. He is the author of Pacino and the uarchlabs methodology
documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
