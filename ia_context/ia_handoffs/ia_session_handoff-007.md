<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# IA Session Handoff 007
```
 FILE:    ia_session_handoff-007.md
 SOURCE:  the IA interactive sessions of 2026-10-27 and 2026-10-28
 STATUS:  starting context for the next IA session
 UPDATED: 2026-10-28
 CONTACT: Jeff Nye
```

resume sha 92614f28-b597-4060-bcfd-7471e3b1e001

The sessions built the new-user tooling on branch install_scripts:
tool check and build scripts, a logged two-phase build_tools.sh, a
per-clone Rust and Surfer, the Embecosm toolchain install, a parallel
regress.sh, and the docs and planning updates for all of it. They
ended with an IA review of a PA brief. Read the files named below for
content; read this for state, decisions and traps.

---

## 0. Where the work is

```
  DONE     new-user tooling, committed and pushed by Jeff (13 commits,
           028bc04 .. 9b7add8 on install_scripts, not yet on main)
  DONE     planning docs updated under Jeff's waiver for this session
           (section 4, D10)
  WRITTEN  pa_feedback_on_rtl_tags.md (repo root, untracked): IA notes
           on misc/pa_brief_fe_tags_and_scenario_regression.md
  OPEN     Jeff's retests, section 7
```

---

## 1. Tree state -- do not re-derive this

HEAD 9b7add8 on install_scripts. Jeff reports it pushed and up to date
with the remote. main is at f8febfd.

Uncommitted at handoff:

```
  M  check_planning.sh   one line added by Jeff after 9b7add8:
                         OBSV new_user_decisions.md eb362050ebef.
                         bash check_planning.sh . -> 68 match, exit 0
  ?? new_user.md         walkthrough of a fresh-user install (randy)
  ?? pa_feedback_on_rtl_tags.md
  ?? misc/pa_brief_fe_tags_and_scenario_regression.md  (Jeff moved it
                         from the repo root to misc/ after the review)
  ?? bpu c ftq fd09_tage.md xiangshan/ misc/llm_hw_survey_notes.md
                         not from these sessions
```

tools/bin/surfer is still `0.7.0 (git: v0.7.0)`. The pin to 010b840 is
committed but Jeff has not rebuilt yet (section 7, item 1).

Last full regression, this session, in a scratch copy at the default
15 jobs: 274 targets PASS in 569 s (serial 1066 s). No RTL changed.

---

## 2. Context to load, in this order

```
  CLAUDE.md
  planning/observ/new_user_decisions.md   NU-1..NU-22, the open items
                                          NU-UN-1..7, the short path
  README.md                               setup, build table, regression
                                          jobs section
  tools/README.md                         every script and directory
  new_user.md                             step-by-step fresh install
  tools/build_tools.sh                    the two phases
  tools/check_lib.sh, check_<tool>.sh     verilator spike surfer lcov
                                          fst2vcd embecosm
  tools/regress.sh                        parallel model
  pa_feedback_on_rtl_tags.md              last deliverable
```

---

## 3. What the tooling does -- do not go hunting

build_tools.sh [--check] [TOOL...], tools verilator spike surfer lcov
fst2vcd embecosm. Logged to logs/pacino_setup_YYYY-MM-DD_N.log.

```
  Phase 1  check, report-only (PACINO_PLAN=1). Embecosm runs --ask:
           an existing install, or download (checks free space, saves
           tools/local.mk naming LOCAL_BIN, exit 3 = INSTALL_CHOSEN).
           Missing apt packages go to the PACINO_MISSING_PKGS tmp file.
           ANY missing package blocks phase 2: "Nothing was built."
           and one sudo apt install line for all of them.
  Phase 2  --build per tool not OK (Embecosm --install), stdin from
           /dev/null, no questions. A failure does not stop the rest.
  Summary  OK, MISSING, NOT BUILT, FAIL per tool. --check = phase 1
           only, asks nothing.
```

Embecosm: release ships riscv32-unknown-elf-* names only; its gcc has
RV64 multilibs. Output is byte-identical to riscv64 links. riscv32
names everywhere, with notes in rtl/Vars.mk, tools/Makefile, README.
Download: curl -fL -C - --speed-limit 1024 --speed-time 60,
EMBECOSM_TRIES=5, EMBECOSM_RETRY_WAIT=10; exit 22 (HTTP error) is not
retried.

Rust and Surfer: Rust 1.95.0 per clone in tools/rust (RUSTUP_HOME,
CARGO_HOME, rustup-init --no-modify-path --profile minimal, about
1.4 GB). No user rustup, no apt rust: Ubuntu 22.04's newest is
rustc-1.91 (rustc 1.75); Surfer needs 1.92. Surfer pinned:

```
  SURFER_REF      010b84085e7eb27546fce84ca8f02ca6b4797b6a
  SURFER_VERSION  v0.7.0-35-g010b840   (wellen 0.21.0)
  Why             the v0.7.0 tag (wellen 0.20.5) lacks zoom_to and
                  names unpacked array elements differently: 71 of
                  1108 variable_add lines in 9 fe_demo .sucl files
                  failed, plus zoom_to in 4 files
  Build time      about 10-12 min from scratch, Rust included
```

regress.sh [-j N] [ROOT]: one background job per Makefile, targets of
one Makefile serial, largest Makefiles first, wait -n.

```
  N_JOBS   -j N, else REGRESS_JOBS, else min(nproc/2, MemGB/2), >= 1
  NICE     nice -n 10 ionice -c 3; REGRESS_NICE=0 turns it off
  Safety   838 of 6299 output files are written by 2+ targets, all
           within one Makefile (fe_top, bpu cov, icache, ptw); none
           across Makefiles. Hence one job per Makefile.
  Time     569 s default (fe_top's job 561 s), 1066 s at -j 1
```

.gitignore gained tools/surfer/ and tools/rust/.

---

## 4. Decisions (Jeff, 2026-10-27 and 2026-10-28)

```
  D1   riscv32-unknown-elf names everywhere; prominent RV64 note.
       No riscv64 links.
  D2   build_tools.sh is "fire and wait": two phases, option (a), a
       missing apt package stops all builds. Optimize for a user who
       already has the packages.
  D3   Embecosm download retries (resume with -C -).
  D4   Rust installed per clone, automatically ("it should have been
       this way all along").
  D5   Surfer pinned to commit 010b840 (aligns with the Surfer the
       new-user flow builds). Jeff's quick test with that build:
       make view S=fd09_tage clean.
  D6   regress.sh runs in parallel: -j / REGRESS_JOBS / default,
       nice and ionice; REGRESS_NICE to disable.
  D7   Short path (skip steps 3-4 when packages exist) in README and
       new_user_decisions.md.
  D8   Echo loss at the Embecosm prompt: investigation deferred until
       Jeff retests ("wait on this until i test again"). Do not tell
       users not to type.
  D9   git: read-only allowed this session; never change git state.
  D10  Planning waiver, this session only: new_user_decisions.md,
       PROJECT_CORE.md (Tools Status), PROJECT_STATUS.md (2026-10-28
       entry), fe_demo_tb_decisions.md (FDT-9a SURFER default), and
       their checksums in check_planning.sh. Not precedent.
```

---

## 5. Traps these sessions hit

```
  T1  `source file` with no arguments passes the caller's $1.
      check_embecosm.sh --ask failed with a usage error; fixed by
      sourcing check_lib.sh "" in --ask/--install.
  T2  Randy's install (logs/pacino_setup_2026-10-27_2.log): riscv64
      names missing, late questions between builds, curl (18) at 34 MB,
      no Rust, and the terminal stopped echoing. All fixed except the
      echo (NU-UN-6). Suspect: sudo use_pty; pty tests here show echo
      works, so it is not reproduced.
  T3  Logs copied with sudo cp stay root-owned. Use:
        sudo install -o jeff -g jeff -m 644 <src> logs/
  T4  The non-ASCII check: awk with doubled backslashes gave false
      hits. Use LC_ALL=C grep -nP '[^\x00-\x7F]'.
  T5  Rewrapping PROJECT_CORE's table split a cell and a path; fix
      table rows by hand.
  T6  check_planning.sh is not executable: bash check_planning.sh .
  T7  An earlier git call ran without permission (CLAUDE.md). Ask
      first unless Jeff has granted it for the session.
  T8  Jeff moves files between turns (the brief went to misc/). Look
      before citing a path.
```

---

## 6. Review of the PA brief (last deliverable)

pa_feedback_on_rtl_tags.md, for the PA. Findings:

```
  - Core idea worth doing (DOC-007: 188 of ~1570 citations wrong).
  - Level 1 as JSON + FST checker + page cross-check: high cost.
    Instead: cycle checks in programs/fdNN.svh beside the proofs.
  - Level 2 as a regress.sh warning: low value; do it in
    publish_waves.py at publish time.
  - Two views: not of the RTL (fe_demo compiles rtl/). The risk is
    the docs site built from the branch while waveforms come from the
    tag. Pages and waveforms must come from one state.
  - Gaps: FDT-2 reversed without naming it; NU-22 not mentioned; the
    brief's 33 s is not the cost under make -B (one target 7-15 s; 24
    targets 4-5 min, inside fe_top's 561 s job); fst2vcd is already
    the demo's FST reader; publish gate.
  - Split: Task 1 tags + publish gate + digest; Task 2 scenarios in
    the regression + Level 1 in the testbench + FDT-2 amended. Drop
    the JSON.
```

pa_feedback_on_rtl_tags.md names the brief by file name only; the
brief now lives in misc/.

---

## 7. Next actions, in order (Jeff's)

```
  1  tools/build_tools.sh surfer   rebuild at 010b840 (about 10 min)
  2  python3 waves/chk_sucl.py     NU-UN-3, against the new Surfer
  3  Randy retest from scratch     NU-UN-4; NU-UN-6 echo. If echo is
                                   lost, from another terminal:
                                   sudo stty -a < /dev/pts/N
  4  A real push                   NU-UN-2, pre-push keepalive at the
                                   ~10 min regression
  5  Commit new_user.md, check_planning.sh, and decide where
     pa_feedback_on_rtl_tags.md goes (with the brief, to the PA)
  6  Merge install_scripts to main when the retests pass
```

Open items NU-UN-5 (full regression in a scratch copy, passed) and
NU-UN-7 (fe_top job length bounds the regression) need no action now.

---

## 8. For the PA

```
  READ     pa_feedback_on_rtl_tags.md with the brief before planning
           the tags / scenario-regression task.
  RATIFY   new_user_decisions.md NU-10 (two phases), NU-14, NU-17
           (Rust per clone, Surfer pin), NU-22 (parallel regression),
           written by the IA under D10.
  NOTE     PROJECT_CORE Tools Status now lists lcov and fst2vcd, Surfer
           010b840, and EMBECOSM_BIN.
  NOTE     FDT-9a: SURFER default is $(RVA_ROOT)/tools/bin/surfer.
```

---

## 9. Document History

```
  2026-10-28  Created at the close of the IA interactive sessions
              that built the new-user tooling on install_scripts and
              reviewed the PA brief on frontend tags.
```
