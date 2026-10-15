<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Front-End Trace Decisions
```
 FILE:    fe_trace_decisions.md
 SOURCE:  session-080
 STATUS:  DRAFT
 UPDATED: 2026-10-14
 CONTACT: Jeff Nye
```

Owns the TR-N and TR-UN registries.

The front-end trace: the events it records, how an operation is
identified through the pipeline, and the text format. The trace is the
input to a later pipeline (waterfall) viewer and to correlation with a
later performance model.

---

## 1. Source

TR-1   The trace is written by the testbench. It observes fe_top and the
       walker through hierarchical references or bound modules. The RTL
       has no trace or counter logic and none is added for the trace.
TR-2   One trace file per run, plain text, written to the run directory
       as <program>.trc beside the FST waveform.
TR-3   Every value in the trace is taken from an RTL signal at a clock
       edge. The trace never infers an event the RTL does not show.

---

## 2. Operations and identity

TR-4   An operation is a unit of work the trace follows through the
       pipeline. There are two kinds:
         block        a prediction block, one FTQ entry, from p0 to
                      the IFU writeback
         instruction  one instruction, from the IBUF write to retire,
                      or to the point it is killed
TR-5   Every operation gets a trace id when it begins, unique within
       the run and never reused: b<n> for a block, i<n> for an
       instruction, n counting from 0 in order of beginning. The FTQ
       index and the generation bit are fields of a block, not its
       identity, because the FTQ reuses its indices.
TR-6   An instruction record names its parent block id and its
       position in the block. A block can be followed to every
       instruction it produced, and an instruction back to its block.
TR-7   An operation ends exactly once: END when it completes (a block
       at commit, an instruction at retire), KILL with a cause when it
       is squashed. A block that is written back and later committed
       ends at commit.

---

## 3. Record format

TR-8   One record per line. Fields are separated by one space. The
       first three fields are fixed:
         <cycle> <record> <id>
       cycle   decimal clock count from the end of reset
       record  the record name, upper case (section 4)
       id      the operation id, or - for a record that belongs to no
               operation
       The fields after them are key=value pairs. A PC or address is
       hex with 0x; a count, index or slot is decimal; a flag is 0 or
       1. Keys are lower case.
TR-9   The first line of a file is the header:
         # FETRACE v<version> slots=<n> program=<name>
       Lines beginning with # are comments. The version changes with
       any change to sections 3 to 5. The format is expected to change
       while it settles; a reader checks the version.
TR-10  Records are written in cycle order. Records of one cycle are in
       no defined order.

Example, two blocks of one loop, the second squashed by a p2 redirect:

```
# FETRACE v0 slots=2 program=fd04_p2_override
120 BEGIN b41 kind=blk pc=0x80001040 ftq=9 gen=1
120 STAGE b41 st=P0
121 STAGE b41 st=P1
121 UBTB b41 hit=1 s0=br s1=-
121 BEGIN b42 kind=blk pc=0x80001060 ftq=10 gen=1
121 STAGE b42 st=P0
122 STAGE b41 st=P2
122 STAGE b42 st=P1
122 FTB b41 hit=1 way=2
122 REDIR b41 src=p2 tgt=0x80001000
122 KILL b42 cause=p2
```

---

## 4. Record names

Lifecycle records:

```
  BEGIN   an operation begins. Block: kind=blk pc ftq gen.
          Instruction: kind=ins blk pos pc rvc
  STAGE   an operation enters a stage: st=<stage>. It stays in that
          stage until its next STAGE, END or KILL
  STALL   an operation is held in its stage this cycle: why=<cause>
  END     an operation completes
  KILL    an operation is squashed: cause=<cause>
```

Stage names. Block: P0 P1 P2 P3 XL (translation) F0 F1 F2 F3 WB.
Instruction: IB (IBUF write) DC (decode) BE (backend accept) RS
(resolve, branches only) RT (retire).

Event records. Each names the operation it belongs to:

```
  prediction   UBTB FTB LP TAGE SC ITTAGE RAS REDIR
  FTQ          FTQFULL SQUASH COMMIT
  translation  ITLB WALK WALKEND ADUPD FAULT
  fetch        L1I MSHR FILL UNCACHED MAINT XPAGE
  IFU          PDREDIR FLUSH
  IBUF/decode  IBFULL DELIV ILLEGAL
  backend      RESOLVE MISP RETIRE
  training     UPD FTBUPD FTBDROP ALLOC UBTBFILL
```

The fields of each event record are given in section 5.

---

## 5. Event fields

```
  UBTB     hit, s0, s1 (slot branch type or -)
  FTB      hit, way, fast (fast path fired)
  LP       slot, trusted, exit
  TAGE     slot, prm (provider table), alt, uaon (use_alt_on_na used)
  SC       slot, rev (direction reversed)
  ITTAGE   slot, hit, tgt
  RAS      op=push|pop|repair|restore, ptr
  REDIR    src=p2|p3|pd|be, tgt
  FTQFULL  (id -)
  SQUASH   from (first squashed block id), n
  COMMIT   ftq
  ITLB     hit, vpn
  WALK     stages=1|2, root
  WALKEND  levels, size, fault
  ADUPD    stage=vs|g|s, addr
  FAULT    cause, gpa, kind
  L1I      hit, line, id
  MSHR     op=alloc|merge, id
  FILL     line, id
  UNCACHED pc
  MAINT    op=fencei|cboinval, phase=drain|clear|done
  XPAGE    (the block crosses a page)
  PDREDIR  cls=M1|M2|M3|M4, pos, tgt
  FLUSH    idx
  IBFULL   (id -)
  DELIV    n (instructions delivered to decode this cycle; id -)
  ILLEGAL  (instruction)
  RESOLVE  taken, tgt, mis
  MISP     type=cond|ind|ret|call|jmp
  RETIRE   (instruction)
  UPD      pred=tage|sc|ittage|lp|ras, slot
  FTBUPD   value=high|low
  FTBDROP  (a low-value FTB update dropped)
  ALLOC    pred=tage|ittage, tbl
  UBTBFILL slot
```

---

## 6. Open

TR-U1  Whether an instruction begins at the IBUF write or earlier, at
       the IFU predecode slots, so that wrong-path instructions killed
       inside the IFU appear as instructions.
TR-U2  Whether a page walk and an L1I miss are operations of their
       own (w<n>, m<n>) with their own lifecycle, or events of the
       block that caused them. A walk or a fill can serve more than one
       block.
TR-U3  Whether STALL is written every cycle an operation is held, or
       only on the first cycle with the cause, the viewer filling the
       rest.
TR-U4  The cause vocabularies of KILL and STALL.

---

## 7. Document History

```
  2026-10-14  session-080. Created.
```
