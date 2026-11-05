<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Status Decisions
```
 FILE:    status_decisions.md
 SOURCE:  web presence plan
 STATUS:  FUTURE
 UPDATED: 2026-11-04
 CONTACT: Jeff Nye
```

Owns the ST-N and ST-UN registries.

FUTURE. Nothing reads this document yet, and no block has a recorded
stage. It is kept so the stage definitions are settled before they are
used. When adopted, each block's stage is recorded in
`tools/doc_status.yaml`, and `docs/microarchitecture.html` shows it as two
badges per block beside the existing done, active and planned status.

Defines the design and verification stages a block can be at, and the
rules for moving a block between them.

---

## 1. Scope

ST-1   A block is a unit with its own RTL directory and decision
       document (BPU, FTQ, IFU, L1I, ITLB, PTW, PMP/PMA, IBuf, Decode,
       and the backend blocks as they are added), as shown in
       `docs/microarchitecture.html`.

ST-2   Each block has three states, recorded independently:
         - RTL state: done, active or planned
         - design stage: D0 to D3 (section 2)
         - verification stage: V0 to V3 (section 3)
       A planned block has no design or verification stage.

ST-3   Stages are recorded per release. The docs show the stages
       recorded at the latest `fe-*` tag, the same state the Showcase
       and the published waveforms describe.

---

## 2. Design stages

One row per stage, the stage in the first column, so a script can
read the table when the stages are adopted.

| Stage | Name              | Entry criteria |
|-------|-------------------|----------------|
| D0    | In development    | RTL is being written; it is not functional. |
| D1    | Functional        | The block passes its unit testbench. Its interfaces, as written in its interface documents, are frozen for the release. |
| D2    | Feature complete  | Every feature its decision document rules in for the release is implemented, and the block is integrated in its top (for the frontend, `fe_top`). |
| D3    | Design complete   | Lint clean, with every waiver reviewed. No open U-item in its decision document applies to the release. |

---

## 3. Verification stages

One row per stage, the stage in the first column, so a script can
read the table when the stages are adopted.

| Stage | Name              | Entry criteria |
|-------|-------------------|----------------|
| V0    | In development    | The testbench is being written. |
| V1    | Directed tests    | Directed tests pass in `tools/regress.sh`, with expected values derived independently of the RTL under test. |
| V2    | Coverage met      | Every test in the block's test plan is written and passing, and its coverage targets are met. |
| V3    | Coverage closed   | Coverage is closed, with every waiver reviewed, and at least one independent check (formal, an external test suite, or mutation testing) has been run and its results recorded. |

---

## 4. Moving between stages

ST-4   A stage changes only by Jeff's decision, recorded as a one-line
       change to the block's entry in `tools/doc_status.yaml`. The IA
       never changes a recorded stage; it may report that a block
       meets the criteria for the next one.

ST-5   A stage change names its evidence in the block's `note:` or in
       the commit message: the IA task, the regression run, or the
       coverage report that shows the criteria are met.

ST-6   A block can move down a stage. A regression in RTL or tests
       that breaks a stage's criteria moves the block back at the
       next release.

---

## 5. Open

ST-U1  OPEN. Coverage targets for V2: which coverage kinds (line,
       toggle, functional) and what thresholds, per block or for all.
ST-U2  OPEN. Whether a block's test plan lives in its decision
       document or in its own file.
ST-U3  OPEN. When the stages are adopted, and which release first
       records them.

---

## 6. Document History

```
  2026-11-04  First draft, marked FUTURE. Stage definitions adapted
              from OpenTitan's hardware development stages, narrowed to
              what Pacino records. A separate status dashboard page was
              considered and dropped: most of its content is already on
              other pages. When adopted, the stages are shown in
              docs/microarchitecture.html.
```
