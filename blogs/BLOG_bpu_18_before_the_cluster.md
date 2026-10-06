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

The branch prediction cluster (BPC) instantiates the Pacino predictors and
provides the interface to the fetch target queue (FTQ). These sessions covered
three preconditions necessary before the BPC integration could be performed.

During the statistical corrector (SC) planning phase the requirements from the
TAGE to SC interface had changed requiring a TAGE fix to match the new
package(s).

While planning for the integration I realized the planning documents had been
built in isolation and needed a correlation effort to find inconsistent
statements and any misleading/incomplete information.

Before writing the FTQ interface I decided there needed to be a frontend
planning document that encompassed how the BPC and FTQ would inter-operate.
These decisions are contained in `fe_decisions.md`.

BPC integration was not performed in these sessions but all three of the
preconditions were completed. At this stage the interfaces within the FE were
not fully described. That occurred in the next set of sessions.

The primary methodology finding in these sessions was reinforcement of the role
of the architect in the design process. Document analysis reported the RTL and
planning documents had drifted, either through mistakes or missing
requirements, in a few cases with no single source to defer to. In the Pacino
methodology these decisions are made by the human.

## Reconciling TAGE with SC package changes

In sessions 057 and 058 edits to `bp_structs_pkg.sv` were made as part of SC
planning [1]. `cond_pred_meta_t`, `cond_pred_upd_inp_t` and `tage_high_conf`
were retired.

BP-081 retyped the TAGE update queue and response buffer to the existing
`tage_upd_inp_t` and `tage_pred_meta_t`, and deleted the dead `tage_high_conf`
logic, closing TD #94 and TD #95.

BP-081 also generated the SC-facing fields described in TD #87/#88. These were
the one-hot strong, medium and weak decode of the provider counter and the
extended counter `2*ctr - 7`.

BP-081's only package edit was the re-addition of `tage_pred_weak` for this new
decode. The `tage_pred_strong` definition changed from "not weak" to an
explicit strong encoding, 000 or 111. As part of this the UAON[F1] gate moved
from the old `!tage_pred_strong` to `tage_pred_weak`, 011 or 100.

`tb_tage_tasks.sv` used the removed field but was missing from the task
manifest. The IA stopped and asked before editing outside its scope, and I
authorized the fix. BUG-006 now requires affected files to be found by
searching the unit, not taken from a list in the task.

I asked the IA if it had run all targets in the bpu Makefile. It had run `make
all` but not all targets were covered. The missing targets were run with no
errors. TD #99 was recorded for future work to develop a pre-push regression
scheme.[F2]

The coverage run reported 73.7% line coverage for `cov_tage` and 79.5% for
`cov_tage_table`, against an earlier stated figure above 90%. TD #100 was
recorded for diagnosis.[F3]

Session 060 ended with all seven predictors and `bp_history` passing at the
unit level.

## Auditing the planning documents

Prior to BPC integration I redirected session 061 to audit the documents. The
audit was three read-only IA tasks, FTB, then TAGE/SC and finally ITTAGE/RAS.
Each task compared the planning documents for the group against the group's
testbenches, packages, RTL, Makefile targets, as well as shared files. The task
files reported discrepancies and any information that PA/I thought might be
misleading. The IA audit results were reported to the PA and PA drafted the
planning document updates. A discrepancy that needed a design decision rather
than a text correction came to me.

### Findings by group

INFRA-008 found no discrepancies in the FTB documents, and two stale RTL
comments (TD #104).

INFRA-009 found 12 discrepancies in TAGE and SC. `tage_pred_strong` was
redefined to 000 or 111, from "not weak". The TAGE base table index is PC bits
12 to 2, not 11 to 1. `br_imli_mode` is now an RTL parameter instead of a
port. The SC threshold is dynamic, not fixed, and the SC table geometry had
changed. The SC unit testbench instantiates only ST1, so ST0 has no unit
coverage.

INFRA-010 found 10 discrepancies in ITTAGE [4] and RAS. The ITTAGE
allocation-write field order, MSB to LSB, is TAG, TGT, EPC, USE, CTR, VALID,
incorrectly documented as TAG, EPC, USE, CTR, TGT, VALID. The ITTAGE table tag
width is IT_TBL_TAG, 8 to 11 bits per table, not as documented 38b. Two target
write strobes were present in the RTL, `prm_tgt_wr_u0` and `alt_tgt_wr_u0`, not
a single strobe. The parameter `ITTAGE_RESP_BUF_DEPTH` was marked as
vestigial; the response buffer is no longer in the design.

The remaining minor findings were stale names and descriptions, and an unread
RAS input deferred to TD #101.

The documents were corrected for all findings. The two design discrepancies
are covered in the next section.

### Two rulings

Two ITTAGE findings were contradictions between documents, detected and
reported by the IA. There was confusion as to where indirect calls were
assigned; the documents differed. I made the ruling that ITTAGE predicts the
target, and the RAS manages the return address. This is conventional.

The second contradiction was the description of the longest ITTAGE table, IT5.
A cut and paste error labeled IT5 as a BrIMLI table [5], a transposition from
the SC documents.

This gap was recorded as TD #102 for later resolution. TD #102 will impact both
the ITTAGE and the history module but at present it represents a loss of
prediction accuracy rather than a functional failure.

### The base table's initial value

During audit there was some confusion on the initialization value used by the
TAGE base table (T0). All TAGE tables, T0 included, initialize from
`TAGE_SRAM_INIT_VALUE`, which is 0 (strongly not taken). T0 is intended to
initialize to weakly taken, 10, as the planning document stated. The audit
cleanup mistakenly changed the document to match the RTL. TD #103 now captures
the fix: a T0-specific init value of 10, and restoration of the document.

## Specifying the FTQ boundary

Session 062 developed the `fe_decisions.md` file which defines the cluster
organization and the cluster to FTQ interface with role assignments for
exchanging predictions, redirects and updates. It settled seven points:[F4]

- The FTQ entry is dual-slot: block-level fields (PC, history pointers, RAS
  snapshot) and a per-slot array (target, branch type, direction, source).
- The two slots are the two branch fields of one 32-byte FTB block, from one
  lookup, not two fixed PC ranges.
- Predictors do not drive redirects. Each presents its prediction at its
  stage, and the cluster compares it with the earlier one and derives the
  redirect.
- ITTAGE produces its final target at p2.
- A history checkpoint is the GHR and PHR pointer pair, one per FTQ entry. The
  RAS snapshot is a separate field restored by the same redirect.
- An FTQ entry is allocated at p1 for every prediction block, including a p1
  miss, so a later predictor always has an entry to redirect against.
- At most one RAS operation occurs per prediction block. A call or return is
  a taken branch, so one in slot 0 ends the block before slot 1. Each FTQ
  entry therefore needs only one RAS snapshot.

### The interface file

The interface file was not written in these sessions. The file needed all
eight predictor port lists. Some files shared in the PA session arrived empty
according to the PA. It is likely this was due to the length of the files and
the remaining context available in the PA session. Unfortunately Claude.ai has
no `/context` command and it has no way to report context load, unlike Claude
Code.[F5]

The port inventory moved to the IA, which read the repository directly. In the
next session, `ftq_bpu_interfaces.md` was written from that inventory.

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

BP-081 went furthest beyond its task specification. The IA identified that
narrowing `tage_pred_strong` would change the UAON update condition, gated the
update on `tage_pred_weak` to preserve the prior behavior, and verified the
change against an existing directed test. It also identified that the UAON
rules document still carried the superseded definition. When it found an
affected testbench outside its manifest, it halted and requested authorization
instead of editing the file.

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
session 061 to the audit, required the later audit groups to read the shared
documents in full, and made the two ITTAGE rulings. I recorded TD #103. In
session 062 I supplied the design corrections to `fe_decisions.md`: the
single-stage ITTAGE target, the slot model, the checkpoint definition and the
redirect model.

### The generalization

An audit that compares a document with the RTL finds where they disagree. It
does not find which one is wrong. An earlier case of a reference taken from the
design under test is described in [6].

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

The next session continues the interface work that session 062 could not
finish: the IA's inventory of every port on the eight top-level modules, the
FTQ-to-cluster interface file written from it, then the cluster itself.

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
<!-- ticfinder_off -->

[1] "The Statistical Corrector: Design Choices at p3" (BLOG_bpu_17), for the
package edits that broke TAGE and the BP-080 investigation that scoped the
repair.

[2] Seznec, André, and Pierre Michaud. "A case for (partially) tagged geometric
history length branch prediction." The Journal of Instruction-Level
Parallelism 8 (2006): 23.

[3] Seznec, André. "Tage-sc-l branch predictors." JILP-Championship Branch
Prediction. 2014.

[4] Seznec, André. "A 64-Kbytes ITTAGE indirect branch predictor." JWAC-2:
Championship Branch Prediction. 2011.

[5] Seznec, André, Joshua San Miguel, and Jorge Albericio. "The inner most
loop iteration counter: a new dimension in branch history." Proceedings of the
48th International Symposium on Microarchitecture. 2015.

[6] "External Anchors: When a Proof and Its Reference Share the Same Error"
(BLOG_bpu_16), for the earlier case of a reference taken from the design under
test.
<!-- ticfinder_on -->

## Footnotes

<!-- ticfinder_off -->
[F1] UAON is known in the literature as `USE_ALT_ON_NA`, i.e.
use-alternate-on-newly-allocated. It is a counter that tracks whether the
alternate prediction is more accurate than the primary prediction when the
primary's entry appears newly allocated, i.e. its counter is weak (011 or
100). See [2] and [3].

[F2] TOOLS-006, in a later range, closed TD #99 with `tools/regress.sh`, which
runs every target of every `rtl/` Makefile and is run by a pre-push hook.

[F3] BP-097, in a later range, found that 8,043 of the 8,700 lines counted by
`cov_tage` are testbench lines, and that the DUT-only coverage is near 90%.
TD #100 remains open until a conclusion states its denominator.

[F4] `fe_decisions.md` has been revised substantially since session 062. In
session 064 the RAS top-of-stack read was moved from p1 to p0, and after a
port inventory confirmed that no predictor declares a redirect port, the
redirect section was rewritten to two cluster-level groups named by stage,
`bpu_redir_p2` and `bpu_redir_p3`. In session 071 the 32-byte unit was named
the prediction block, distinct from the 64-byte fetch block the IFU reads.
This post uses the later term.

[F5] Confirmed with the latest Claude.ai.

Q: do you have any method to return your context load, remaining, etc ?

A: No. I have no tool that reports context used or remaining, and no
visibility into token counts. Claude Code shows the IA a "Ctx %", which is
where your task headers get that figure; nothing equivalent exists in this
chat.
<!-- ticfinder_on -->

---
<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry experience
spanning performance modeling, RTL implementation, and architecture for
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,
TI C6x and RISC-V designs, and recently served as sole architect and full-stack
implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue
RVA23 RISC-V processor, from research through timing closure at 2.75 GHz. He
holds +20 issued patents in processor design, architecture, and hardware
virtualization. He is the author of Pacino and the uarchlabs methodology
documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
