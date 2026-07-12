```
 FILE:    resume_20260709.md
 SOURCE:  session capture 2026-07-09
 STATUS:  CONTEXT - resume file, not a design document
 UPDATED: 2026-07-09
 CONTACT: Jeff Nye
```
---

## 0. The Task

### The main task
Write a theory of operation for the front end: the BPU to FTQ path and
the FTQ to BPU path. Predictor internals are out of scope. The RAM
arbitration model is out of scope; its handshakes are in scope.

Current deliverable: `ia_context/planning/arch/fe_theory_of_operation.md`.

It is a live document.

### The current task

The current task is to resolve any inconsistencies within the
fe_theory_of_operation.md document. These are internal inconsistencies
unrelated to inconsistencies with external files.

## 1. Context to load

@ia_context/planning/arch/fe_theory_of_operation.md


@planning/arch/bp_cluster.md      source, reliable with noted gaps
@planning/arch/bp_arb_spec.md     source, contains errors
@rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
                                   bp_ftq_entry_t, bp_ftq_meta_t
```
---

## 2. Document Lineage

The directory structure was changed after this file was output.

### Old files

The files below have been removed or renamed. This list is kept in case
there are uncaught references to these files in the discussion below.


```
  tmp_001.md   WRONG SCOPE. An FTB directory/payload theory of
               operation, derived from fe_TOP_20260708.md. Written
               before the task was understood. Superseded, not merged.

  tmp_002.md   First front-end draft. Reviewed by Jeff with inline
               FIXME markers.

  tmp_003.md   Second draft. Reviewed with inline FIXME markers.
               Final; do not edit.

  tmp_004.md   Current. All tmp_003 annotations applied, plus items
               settled in conversation.
```

`fe_TOP_20260708.md` is an unrelated FTB proposal. It is unmodified and
is not an input to this work.


### Current files

This is the current director tree:

The term IA is short hand for claude code, implementation assistant. IA's
role is modified in these session to also assist in planning because the
reference files for xiangshan (XS) are on disk.

The handoff files are captured at the end of an IA session and are used
to reset context on the start of the next session.

ia_context
   ├── background               temporary and background files
   │   ├── cold_start_v1.md     description of cold start process
   │   ├── cold_start_v2.md     description of cold start process
   │   ├── fe.md                front end spec draft
   │   ├── fe_qaa.md            front end spec draft
   │   └── xs_ifu_ftq.md        XS ifu/ftq summary reference
   ├── ia_handoffs
   │   ├── ia_session_handoff-001.md    
   │   ├── ia_session_handoff-002.md
   │   └── ia_session_handoff-003.md   this document
   └── planning
       └── arch
           └── fe_theory_of_operation.md      current fe planning document
                                              this is a draft

---

## 3. Settled Decisions

These were argued and closed. Do not reopen them.

**Stage labeling is p0/p1/p2/p3.** Labeling is bookkeeping. It never
changes behavior. A rename cannot move a predictor into a different
cycle or turn a mux into a redirect.

**The initial prediction is at p1.** The LP is a one-cycle RAM: index
driven at p0, output valid at p1. The uBTB output is valid at p1. The
FTQ allocates an entry and issues the fetch at p1. `bp_arb_spec.md`'s
predictor table, which puts the uFTB at p0, is wrong; that document's
own 7.2 refers to "the uBTB p1 prediction."

**The LP overrides the uBTB by mux, in the same cycle.** LP output
valid means a loop was detected and the LP prediction is used;
otherwise the uBTB's. The LP is not a redirect source.
`lp_redir_val_p2` does not exist.

**The RAS does not participate in the uBTB/LP selection.** It supplies
a return target. The uBTB and LP supply a next PC for the fetch block.
Different quantities.

**TAGE and SC predict direction, not target.** When either overrides,
the direction selects the redirect target: taken selects the FTB
branch target, not taken selects the fallthrough. Both derive from the
FTB result; the derivation is FTB-internal and out of scope.

Note: the FTB entry stores displacements, not addresses -- a 13-bit
displacement plus 2-bit status for a conditional, `pftAddr` plus carry
for the fallthrough. Address reconstruction does occur. An earlier
draft claimed "no address arithmetic occurs on the redirect path."
That was false.

**There is no override priority chain.** `bp_arb_spec.md`'s
`SC > TAGE > FTB/LP > uFTB/RAS` compares predictors that do not
produce the same quantity and do not contend. Redirects supersede by
stage order.

**RAS and ITTAGE never contend.** Return and indirect are different
branch types. `br_type` selects one. `ITTAGE (p2) > RAS (p0)` is
wrong.

**Updates are post-execute, in resolution order.** This is an
out-of-order machine; resolution order is not program order.
`bp_arb_spec.md` 4.4's "commit" producer and "program-order" claim are
both wrong.

**Update fan-out is determined by `br_type`.**

```
  conditional    uBTB, LP, FTB, TAGE, SC
  indirect       uBTB, FTB, ITTAGE
  return         uBTB, FTB, RAS
  direct unc.    uBTB, FTB
```

A predictor that missed is still updated -- that is the allocation
case. Nothing records which predictors produced a result, and nothing
needs to. A `pred_contrib` bit vector was proposed and rejected for
exactly this reason: "produced a result" and "should be updated" are
different sets.

Evidence from XiangShan, in-repo, primary:
`Composer.scala:76-80` broadcasts the update to every component, each
slicing its own meta. `Tage.scala:610-614` derives `updateValids` from
`update.ftb_entry.brValids(w)`, never from whether TAGE's prediction
survived. A grep for `pred_src`, `predSrc`, `winner` across the whole
XiangShan frontend returns nothing.

**`pred_src` has no functional consumer.** Retained for diagnostics.
TD-FE-4 tracks removal.

**FTQ entry lifetime ends at its own post-execute resolution.** That
is when its metadata is read. Nothing requires it beyond that.

**The RAS commit-side structure is out of scope.** This was settled
three times and reinstated twice. The FTQ-facing facts are two: the
snapshot is checkpointed into the entry, and the RAS is restored from
it on mispredict or flush. Whether a commit stack exists, when it is
written, and what it costs are RAS internals and belong in
`ras_decisions.md`. It is not a correctness matter -- the RAS is a
predictor, and a mispredicted return is redirected by the backend like
any other.

**`NUM_PRED_SLOTS` is the parameter.** `dual_pred_en` is a signal whose
only purpose is to gate the second prediction slot off at runtime, for
debug. It does not change the structure.

**Each prediction slot consumes one FTQ entry.**

**`pc` and `target` stay at 40 bits.** 39 would suffice. Deferred to an
optimization pass. TD-FE-3.

**Terminology: "FTQ entry index," never "slot."** "Slot" survives only
in "prediction slot," which is a different thing.

---

## 4. Source Document Reliability

```
  bp_cluster.md     STABLE rev 1.0. Correct on the uBTB at s1, on the
                    LP mux, on FTQ entry contents, on the update
                    trigger. Its Pipeline Staging section needs the
                    p-numbering transition. Its Dual Prediction Mode
                    section describes two incompatible things at once
                    (see FE-U8).

  bp_arb_spec.md    STABLE rev 1.0, and it contains errors. Every one
                    found is catalogued in tmp_004.md section 12 with
                    a RESOLUTION line. Do not transcribe from it
                    without checking. Its 7.1 and 7.2 contradict each
                    other on the uFTB stage.

  bp_structs_pkg.sv Declares bp_ftq_entry_t and bp_ftq_meta_t.
```

Not read this session, and authoritative for their subjects:
`ras_decisions.md`, `ftb_decisions.md`, `ftb_interfaces.md`,
`ftb_confidence_override_rules.md`.

---

## 5. Open Items in tmp_004.md

Technical debt, local to the document, to be merged into the project
list:

```
  TD-FE-1  IFU interface unspecified.
  TD-FE-2  bp_ftq_meta_t overloading by branch type unsettled.
  TD-FE-3  pc and target at 40 bits; 39 suffice.
  TD-FE-4  pred_src removal.
```

Unresolved:

```
  FE-U1  Return identification before p1. The RAS presents its
         top-of-stack for a return, but br_type does not exist until
         p2. What identifies the return at p1 is stated nowhere.

  FE-U2  Flush handling. Backend mispredict flush to FTQ is open.
         RAS flush behavior is TD #96.

  FE-U3  bp_ftq_entry_t.confidence purpose.
  FE-U4  PHR contribution to hashing.
  FE-U5  Indirect chain update and correction semantics.
  FE-U6  SC CSR enable phrasing.
  FE-U7  FTQ allocation and deallocation policy.

  FE-U8  Fetch block to FTQ entry mapping. bp_ftq_entry_t represents
         one predicted branch; the FTB entry carries br0, br1, and
         jmp for one fetch block. A block with two conditional
         branches has no representation in the FTQ entry.
```

FE-U1 and FE-U8 are the two that bear on the design rather than on
documentation. FE-U8 is a real gap in `bp_cluster.md`'s entry format.

---

## 6. Working Method

Jeff reviews with inline `FIXME: (X)` markers and bracketed spans. He
takes them one at a time. Responses are short and factual.

What was rejected, repeatedly:

- Asides, metaphor, rhetorical suspense, and editorial commentary. No
  "the window is real." No withholding a term for effect. No "and
  nothing needs to."
- Redundancy. A fact stated in a field table does not need a sentence,
  and does not need an invariant restating it a third time.
- Detail that supports no statement in the document. If a fact is
  BPU-internal and nothing in either path depends on it, cut it.
- Post-mortem framing. This is a design document, not an analysis of
  existing RTL. The theory of operation precedes the RTL. Empty RTL
  directories are not evidence of a specification gap.
- Consulting RTL to settle what a design document should say.
- Asserting a fact not derived. "A prediction lookup returns that
  information in three cycles" was invented from three stage labels.
- Reinstating a conceded point in a different section.
- Asking a question the directive already answered.

---

## 7. Next Actions

```
  1  Jeff's review of tmp_004.md. Not yet started.

  2  FE-U1 and FE-U8 need design decisions, not documentation.

  3  Section 12 of tmp_004.md is a work list against bp_arb_spec.md.
     Those corrections belong in that document.

  4  bp_cluster.md Pipeline Staging needs the p-numbering transition.

  5  On acceptance, tmp_004.md gets a real name and a home under
     planning/. Its TD items merge into the project list.
```

---


## 9. Document History

```
  2026-07-09  Session capture. Front end theory of operation taken
              from tmp_001 (wrong scope) through tmp_004 (current).
              Records the decisions settled by direction, the errors
              found in bp_arb_spec.md, and the eight unresolved items.
```
