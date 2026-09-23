<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

```
TITLE:     "Before the Cluster: Reconciling the Predictors and Their Documents"
FILE:      BLOG_bpu_18_before_the_cluster.md
AUTHOR:    Jeff Nye
DATE:      2026-09-22
STATUS:    REVIEW BEFORE POSTING
COPYRIGHT: "Copyright 2026 Jeff Nye"
```

<!--
---

::SERIES DESCRIPTION::
::BEGIN LINKS::
::END LINKS::
-->

# Before the Cluster: Reconciling the Predictors and Their Documents

## Abstract

The branch prediction cluster, `bp_cluster`, instantiates the seven Pacino
predictors and the history module and connects them to the fetch target queue
(FTQ). It was the planned next step throughout the three sessions covered
here, and three preconditions had to be met before it could start.

TAGE did not elaborate. BP-081 retyped two FIFOs off retired structs, deleted
a dead confidence field, and generated the three-way TAGE confidence decode
and the extended counter the statistical corrector consumes. The decode
narrowed the meaning of an existing signal, `tage_pred_strong`, and the TAGE
update gate that depended on the old meaning was moved to a new signal. All
seven predictors and the history module then passed at the unit level.

The planning documents had not been checked against the RTL they describe,
and the cluster build would treat them as the interface authority. Three
read-only audits compared the documents for each predictor group with the
shipped RTL, testbenches and Makefile. They found 22 discrepancies. Twenty
were stale text. Two needed a design ruling: which predictor owns the target of
an indirect call, and whether ITTAGE's longest-history table has folded
history. The second exposed an RTL gap, in which that table has been indexed
on the PC alone.

One discrepancy was resolved in the wrong direction. The audit corrected a
document to match the RTL's initial value for a TAGE table, and the same
session recorded that RTL value as a defect.

No document defined the boundary between the cluster and the FTQ. Session 062
wrote `fe_decisions.md`, which settled the dual-slot FTQ entry, how redirects
are formed, and the prediction slot model.

## Where the range starts

The previous range closed with the statistical corrector complete and the six
TAGE targets failing to elaborate. Package edits made during SC planning had
retired two structs and a field that `tage.sv` and `tage_cntrl.sv` still used.
A report-only task, BP-080, had scoped the repair.

The plan at that point was to repair TAGE and then build `bp_cluster`, which
had not been started. The cluster build did not start in any of the three
sessions. Session 060 repaired TAGE, as planned. Session 061 was planned as the
cluster build and was redirected to audit the planning documents. Session 062
was again planned as the cluster build and was redirected to specify the FTQ
boundary. Each redirect was made because the cluster build depended on
something that was not yet true.

## Restoring TAGE

BP-081 carried out the repair BP-080 had scoped. `tage.sv` holds an update
queue and a response buffer whose element types were the retired merged
structs. BP-081 retyped them to `tage_upd_inp_t` and `tage_pred_meta_t` and
replaced the per-field writes with whole-struct writes. The fields dropped by
the retype had been written and never read, so the change preserves behavior.
It also deleted the dead `tage_high_conf` logic from `tage_cntrl.sv`.

The plan from the previous session was to tie the SC-facing TAGE fields that
TAGE did not yet generate to zero. I folded their generation into BP-081
instead, which closed TD #87 and TD #88 and required one package edit, the
re-addition of `tage_pred_weak`.

### The confidence decode

TAGE's provider counter is 3 bits. BP-081 decodes it one-hot, after the
selection between the primary and alternative providers. Values 000 and 111
are strong, 011 and 100 are weak, and the remaining four are medium. The
extended counter for the SC is `2*ctr - 7` as a signed 5-bit value, which maps
the eight counter values to the odd numbers from -7 to +7. That is the same
centered form the SC applies to its own counters before summing.

Before this task, `tage_pred_strong` meant "not weak", six of the eight
values. Under the decode it means two of the eight. The name was kept and the
meaning narrowed, so every consumer of the old meaning had to change with it.

One consumer was the TAGE update rule for the use-alternate-on-newly-allocated
(UAON) counters, which acts only when the provider was weak. It had been
written as "if not strong". Keyed on the narrowed signal, that test would also
fire on the four medium values. The IA moved the gate to `tage_pred_weak`,
which reproduces the old behavior on every counter value, and confirmed it
against an existing test in which a medium counter must suppress the UAON
update. The rules document, `tage_cntrl_uaon_update_rules.md`, still defined
strong as not weak. The IA wrote a corrected copy, which I checked and merged
into the canonical document.

### The file the manifest missed

The task manifest listed the TAGE testbenches that BP-080's search had found
referencing the removed field. That search covered only BP-080's own manifest.
`tb_tage_tasks.sv` also referenced the field, was not listed, and did not
compile. The IA stopped and asked before editing a file outside its scope, and
I authorized the two-line deletion. The corrective rule, recorded as BUG-006,
is that the files affected by a deleted or renamed field are the result of
searching the unit for the symbol, not a list written into the task.

### Running every target

The TAGE suite returned green: `sim_tage` 105 of 105, `sim_tage_table` 15 of
15, and `make all` exited cleanly. When I asked whether every Makefile target
had run, the answer was no. `make all` does not include `sim_ittage`,
`sim_tage_manual` or the coverage targets. The IA ran them, and they passed.
That gap is the motivating evidence recorded in TD #99, which asks for a
process that runs every target.

The coverage run reported 73.7% line coverage for `cov_tage` and 79.5% for
`cov_tage_table`, against an earlier stated figure above 90%. Whether that is
under-coverage or a difference in what was counted was not settled in the
range. It is TD #100.[F1]

The range's first session ended with all seven predictors, the uBTB, loop
predictor, FTB, TAGE, SC, ITTAGE and RAS, and the history module complete and
passing at the unit level.

## Auditing the planning documents

The cluster instantiates all seven predictors at once, and the task author
builds it from their interface documents. A wrong port name or a stale field
in any one of them would stop the cluster from elaborating. I redirected
session 061 to check the documents first.

The audit was three read-only IA tasks, one per group: the FTB, then TAGE and
SC, then ITTAGE and RAS. Each compared the group's planning documents with its
RTL, testbenches, packages and Makefile targets, and with the shared documents
where they describe the group. Each reported only discrepancies that would
mislead someone using the documents as the authority, and excluded items
already tracked. The IA did not edit anything. The planning assistant drafted
each correction afterwards and I applied it. A discrepancy that needed a design
decision rather than a text correction came to me.

The first task was allowed to skip a shared document when it judged that the
document's FTB content was already covered by open items, and it skipped all
three. For the second and third groups I required the shared documents to be
read in full, because TAGE, SC and ITTAGE have much more content in them. The
ITTAGE finding described below was a contradiction between shared documents.

### The FTB

INFRA-008 found no discrepancy in the FTB documents. It found two stale
comments in the RTL, recorded as TD #104. It did not run the simulation
targets, because they write build files and the task forbade creating files,
so the FTB's recorded result of 99 passing checks was not re-verified.

### TAGE and SC

INFRA-009 found 12 discrepancies. Two TAGE documents still defined
`tage_pred_strong` as not weak, one session after BP-081 changed it, and
omitted the new medium and extended-counter fields. The TAGE decisions document
gave the base table's index as PC bits 11 to 1; the RTL and the hash-rule
document use bits 12 to 2. The same document summarized four rows of a counter
update table for a case that cannot occur, where the rules document has one
row marked as an assertion.

The SC findings were the ones the previous range left behind. The interface
and hash documents described `br_imli_mode` as a port, which BP-079 had made a
parameter. `sc_interfaces.md` described the SC update queue as functional,
where the unit stubs it. `bp_cluster.md` still gave the SC tables their
original geometry of 256 entries of 24 bits, and described the SC threshold as
fixed at design time. The SC decisions document specifies a dynamic threshold,
so the cluster document contradicted it. `sram_init.md` listed the SC as a
future consumer with the TAGE plusarg. And `sc_tb_decisions.md` implied that
the ST0 table, the one with no folded history, had unit coverage. The unit
testbench instantiates only ST1, so the ST0 path is untested at the unit
level. That gap was documented and not assigned a debt number.

### ITTAGE and RAS

INFRA-010 found 10. The ITTAGE allocation rules gave the fields of the
allocation write in an order different from the entry format and the RTL; a
write assembled from that document would build a corrupt entry. The entry
format document cited the 38-bit target width parameter as the tag width. The
interface documents described one target-write strobe where the RTL has one
for the primary and one for the alternative provider, and one described up to
four counter writes per update where ITTAGE writes one. The arbitration
specification listed a response-buffer depth parameter for a buffer removed
in BP-038b. On the RAS, `ras.sv` declares an input, `ras_pc_p2`,
that no document lists and the module never reads. The document was corrected
to list it, and whether the port is needed is TD #101.

### Two rulings

Two ITTAGE findings were contradictions between documents that described
different designs, and the IA reported them without choosing.

The first was ownership of an indirect call. `bp_cluster.md` placed indirect
calls with ITTAGE, and `ittage_interfaces.md` excluded them and assigned them
to the RAS alone. The two units do different things with the same
instruction. ITTAGE predicts the call's target, which depends on history. The
RAS pushes the return address. I ruled that both are in scope for an indirect
call, each for its own job, and `ittage_interfaces.md` was corrected.

The second was ITTAGE's fifth table, IT5. `bp_history_decisions.md`,
`bp_cluster.md` and `bp_history.sv` treated it as a BrIMLI table with no folded
history. The packages, the ITTAGE interface and hash documents, and an
interface item marked complete all gave it folded history with a 32-bit
depth. The BrIMLI description had been copied from the SC, where ST4 is a
BrIMLI table, and was wrong. The consequence was in the RTL. `bp_history.sv`
does not generate IT5's folds, and `ittage.sv` connects IT5 to outputs that are
never driven and read as zero. IT5 is indexed by the PC alone, so the ITTAGE
table with the longest history contributes no history. This is a loss of
prediction accuracy and not a functional failure. The documents were
corrected, and the RTL fix is TD #102.

### The base table's initial value

The TAGE decisions document said the base table, T0, initializes to 10, weakly
taken. The package sets `TAGE_SRAM_INIT_VALUE` to 0, so T0 comes up strongly
not-taken. INFRA-009 reported the difference, the planning assistant grouped it
with the text corrections, and the document was changed to 00.

In the same session I recorded TD #103, which says the intended initial value
is 10 and the RTL is wrong. The document had been right. The audit corrected it
to match the defect. The document now describes current behavior, and the
status file carries a note that it must be changed back when TD #103 closes.

## Specifying the FTQ boundary

Session 062 was planned to write the interface between the cluster and the
FTQ. No document defined how the two exchange predictions, redirects and
updates, so the session first wrote that as a theory-of-operation document,
`fe_decisions.md`, from an earlier draft. The planning assistant and I
corrected it section by section. It settled six points.

The FTQ entry is dual-slot. The entry splits into fields that describe the
whole prediction block, such as the PC, the history pointers and the RAS
snapshot, and a per-slot array holding each slot's target, branch type,
direction and source. The metadata is carried per slot. This closed FE-U8.

The two prediction slots are the two branch fields of one 32-byte FTB block,
supplied by one FTB lookup. Earlier text assigned the slots to two fixed PC
ranges. That convention comes from how TAGE and ITTAGE split their bundle and
does not govern the FTB, which `ftb_decisions.md` defines. Two resolved items
in the status file, G8 and G17, carried the fixed-range reading and were
identified as stale.

Predictors do not drive redirects. A predictor presents its prediction at its
stage, and the cluster compares it with the earlier prediction and derives
the redirect. No predictor knows that it is overriding another. The RAS
interface already had no redirect port, and the audit in session 061 had
found that the redirect signals named in the arbitration specification did
not exist on the TAGE, SC or ITTAGE RTL.

ITTAGE produces its full target at p2. The earlier text refined a raw p2 target
into a final p3 target, which is a table-plus-offset structure used in other
designs and not in Pacino.

A history checkpoint is the pair of GHR and PHR pointers, one pair per FTQ
entry. The RAS snapshot is a separate field in the entry, restored by the same
redirect but not part of the checkpoint.

An FTQ entry is allocated at p1 for every prediction block, including a block
the p1 predictors miss, because a later predictor can only redirect against an
entry that exists.

The review also corrected a justification. The document said one RAS snapshot
per entry was enough because at most one branch per block is on the executed
path. That is false: a not-taken branch in slot 0 leaves slot 1 on the path.
The correct basis is that a RAS operation is a call or a return, both taken
branches, so a RAS operation in slot 0 ends the block before slot 1. FE-11 was
restated on that basis.[F2]

### The interface file

The interface file itself was not written. It depends on reading all eight
predictor port lists. For most of the session, files attached to the chat
arrived without readable content, and seven of the eight interface documents
could not be read. The session switched to the implementation assistant for
direct access to the repository files. The range ends with `fe_decisions.md` written and the
interface file not started.

## Experiment Summary

| Experiment | Description | Status | Checks | Runtime | Context |
|---|---|---|---|---|---|
| BP-081 | TAGE struct reconciliation; TD #87 confidence decode and TD #88 extended counter generated; UAON gate moved | PASS | sim_tage 105/0, sim_tage_table 15/0, make all exit 0, remaining targets run separately | 36m 29s | 34% |
| INFRA-008 | Read-only audit, FTB documents against RTL | COMPLETE | no discrepancies; 2 stale RTL comments | 3m 35s | 13% |
| INFRA-009 | Read-only audit, TAGE and SC documents against RTL | COMPLETE | 12 discrepancies | 8m 37s | 6% (main thread) |
| INFRA-010 | Read-only audit, ITTAGE and RAS documents against RTL | COMPLETE | 10 discrepancies, 2 escalated | 8m 23s | 6% |

BP-081's run time was recorded before the follow-up run of the targets outside
`make all`, and its context figure after it. INFRA-009 read its roughly 50 files
in three sub-agents with separate context windows, reported at about 350k
tokens combined; the 6% is the main thread only.

## Design Process Notes

### The IA contribution

BP-081 did the most work that its prompt did not state. It worked out that the
narrowed `tage_pred_strong` would change the UAON gate, chose the signal that
preserves the old behavior, and confirmed it against an existing test. It found
that the UAON rules document carried the old definition. It stopped at the
unlisted testbench instead of editing it.

The audits cited file and line for each finding and traced several to their
cause, including the BrIMLI description of IT5 and the split target-write
strobe. INFRA-010 reported the two cross-document contradictions without
picking a side, and noted that the IT5 item was marked complete on the side
the RTL does not implement. INFRA-008 recorded that it had not re-run the FTB
suite and why.

### The PA contribution

The planning assistant wrote the four task files, drafted the document
corrections from the audit findings, and edited `fe_decisions.md` with me.

The BP-081 manifest was built from BP-080's reference list instead of a search
of the unit. The same failure had been recorded one session earlier, and it is
why BUG-006 exists. The assistant grouped the T0 initial value with the text
corrections. In session 062 it asked which of two documents governed the slot
model when the documents in front of it settled the question: `ftb_decisions.md`
was complete, later, and named the status-file items it superseded.

### My contribution

I folded the TD #87 and TD #88 generation into BP-081, asked whether every
target had run, and authorized the out-of-scope testbench edit. I redirected
session 061 to the audit, tightened the shared-document rule after the first
group, and made the two ITTAGE rulings. I recorded TD #103. In session 062 I
supplied the design corrections to `fe_decisions.md`: the single-stage ITTAGE
target, the slot model, the checkpoint definition and the redirect model.

### The generalization

An audit that compares a document with the RTL finds where they disagree. It
does not find which one is wrong.

Twenty of the 22 findings were resolved by changing the document to match the
RTL. For stale names, removed parameters and superseded ports that is correct,
because the RTL is the later artifact and the change was deliberate. The two
findings escalated for a ruling were those where documents disagreed with each
other, so there was no single RTL value to defer to. T0's initial value was
different. It was a value, the document stated the intent, and the RTL did not
implement it. The audit treated it like a stale name.

IT5 shows the same thing from the other side. One set of documents matched the
RTL, and the RTL was missing logic.

For this project, a finding that changes a documented value, as opposed to a
name, a width citation or a cross-reference, needs the owner to state the
intended value before the document is edited toward the RTL. That is the
decision a consistency audit cannot make on its own.

## What comes next

The range closes with all seven predictors and `bp_history` passing at the unit
level, their planning documents checked against the RTL, and the FTQ boundary
written down in `fe_decisions.md`. The cluster has still not been started.

The next session begins with the interface work that session 062 could not
finish: an inventory of every port on the eight top-level modules, then the
FTQ-to-cluster interface file, then the cluster itself.

The debt opened in this range is small RTL work that the cluster does not need
in order to elaborate: the unread RAS input (TD #101), IT5's missing folds (TD
#102), T0's initial value (TD #103) and the two FTB comments (TD #104). The SC
connections that the cluster will make, TD #89 to #92, and the end-to-end fold
check, TD #84, remain as the previous range left them.

## Technical Debt Referenced

The table below reports status as of the close of this range. Later
experiments outside the range have since changed the state of some items.

| # | Item | Resolution path |
|---|---|---|
| 87 | TAGE strong/medium/weak decode. | CLOSED BP-081. One-hot on the post-mux provider CTR: strong {000,111}, weak {011,100}, medium the rest. tage_pred_strong narrowed from NOT WEAK; the UAON update gate moved to tage_pred_weak. |
| 88 | TAGE extended counter generation. | CLOSED BP-081. tage_extd_ctr = 2*ctr - 7, signed 5b, range -7 to +7. tage_provider_ctr remains an internal signal, not a struct field. |
| 94 | bp_arb_spec reconciliation to the standalone SC. | CLOSED BP-081. The two tage.sv FIFOs retyped off the retired cond_pred_* structs. |
| 95 | tage_pred_meta_t changed; TAGE references to reconcile. | CLOSED BP-081. Dead tage_high_conf logic deleted. |
| 99 | Create a PR/CI/CD process. | Motivating evidence (session-060): `make all` silently omits sim_ittage, sim_tage_manual and the cov targets. CI must run every target, not `make all`. |
| 100 | TAGE line coverage below the previously stated >90%. | cov_tage 73.7%, cov_tage_table 79.5% (BP-081). Decide whether this is genuine under-coverage of the new decode logic or an accounting difference; add directed coverage or correct the number. |
| 101 | ras.sv declares input ras_pc_p2, unread in the module. | Undocumented before session-061; ras_interfaces.md now lists it and cites this item. Confirm whether needed at RAS cleanup; if not, remove from ras.sv and tb_ras.sv. |
| 102 | bp_history.sv does not generate IT5 folds. | ittage.sv wires it_t5_idx_fh/tag_fh1/tag_fh2 to outputs that are never driven, permanently 0. IT5 has real history (hist 32, FH 9, FH1 9, FH2 8). Add IT5 fold generation, same pattern as IT1-IT4. |
| 103 | TAGE T0 initial value. | T0 initializes to 00, strongly not-taken. Intended is 10, weakly taken. Impacts TAGE_SRAM_INIT_VALUE with sram_init. When closed, tage_cntrl_decisions.md's T0 line must be updated again; the session-061 correction documented current behavior only. |
| 104 | Two stale FTB RTL comments (INFRA-008). | ftb_cntrl.sv states 107 bits per way where the entry is 105; ftb.sv states ftb_fastpath_en is beyond the interface draft, which now lists it. Comment-only; fold into the first FTB RTL task. |

## References

- The Statistical Corrector: Design Choices at p3 (BLOG_bpu_17), for the
  package edits that broke TAGE and the BP-080 investigation that scoped the
  repair.

- External Anchors: When a Proof and Its Reference Share the Same Error
  (BLOG_bpu_16), for the earlier case of a reference taken from the design
  under test.

## Footnotes

<!-- ticfinder_off -->
[F1] BP-097, in a later range, found that 8,043 of the 8,700 lines counted by
`cov_tage` are testbench lines, and that the DUT-only coverage is near 90%.
TD #100 remains open until a conclusion states its denominator.

[F2] `fe_decisions.md` has been revised substantially since session 062. In
session 064 the RAS top-of-stack read was moved from p1 to p0, and after a
port inventory confirmed that no predictor declares a redirect port, the
redirect section was rewritten to two cluster-level groups named by stage,
`bpu_redir_p2` and `bpu_redir_p3`. In session 071 the 32-byte unit was named
the prediction block, distinct from the 64-byte fetch block the IFU reads.
This post uses the later term.
<!-- ticfinder_on -->

---
<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
