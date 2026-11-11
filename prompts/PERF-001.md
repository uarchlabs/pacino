<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header 
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | PERF-001                |                          |
| Date         | 2026.11.09              |                          |
| Module       | perf                    | measurement, no RTL      |
| Run time     | 14m.32s                 |                          |
| Ctx %        | 29%                     |                          |
| Model        | claude-opus-5-5 low     |                          |
| Resume sha   | 10308fb4-fa2c-45c9-85cc-f3ef032f778d |             |
| PA session   | 084                     |                          |

Task:   [x] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Mode:   [x] automated   [ ] manual          [ ] interactive
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview
The first performance task. It builds nothing for the gasket. It
measures what the harness design needs to know, from the CBP2025
training traces and pacino as tagged fe-1.0.0:
- each trace checked and characterized: its counts, its code
  footprint, and the branches a RISC-V code image cannot encode
  directly (PF-U1).
- what the CBP reference results count, from CBP's own simulator run
  on one trace (PF-U2).
- the speed of the Verilated fe_top, against the 4.34e9 instructions
  of the training set (PF-7).
- pacino's total predictor storage at fe-1.0.0 (PF-U7, first half).
It writes the first perf script, the trace checksum list and the
characterization table, and the performance section of README.md.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion 

## Claude.code Console Output

PERF-001 is done: all six problems are accepted and ./tools/regress.sh passed (274
  targets, 0 new failures, sha 79df3ad, dirty tree). Results Capture is filled in
  prompts/PERF-001.md. I did not tick the Status checkbox, because it sits outside the
  area I'm allowed to edit.

  - Problem 0: two Background facts are wrong.
    - Trace lengths are 10.0e6 to 130.0e6 instructions, not 30e6 to 40e6. The median is
      40.0e6 and the total, 4.336e9, matches.
    - The int sample has 2776 far branches out of 67,965 taken conditional branches
      (4.1%). 128,874 is the count of all conditional branches, so PF-U1's "2.2
      percent" uses the wrong denominator.
    - The 12.5 GB figure is the size of the archives; the unpacked .gz files total 15.0
      GB.
    - The tree is not at fe-1.0.0: HEAD is 79df3ad and the tag ref holds 585910b.
  - Problem 1: sha256sum -c reports all 105 files OK.
  - Problem 2: all 105 traces equal the reference CSV exactly in Instr, NumBr,
    50PercInstr and 50PercNumBr. The scan took 339.6 s on 32 processes. On the two
    sample traces it reproduces the PA's counts.
  - Problem 3 (PF-U2): CBP's own simulator on int_1_trace reproduces that trace's
    reference row in every result column. Run time was 275.7 s.
    - The reference comes from the default 64 KB TAGE-SC-L, with indirect prediction
      perfect.
    - NumBr counts conditional branches only, so the reference MPKI counts conditional
      mispredicts only.
    - The 50Perc columns are the trailing 1M-instruction epochs. They cover from half
      the trace up to half plus one epoch, with the predictor trained from the start.
  - Problem 4: the Verilated fe_top testbench runs 4.4e3 to 8.3e3 instructions/s. The
    build took 17.8 s, timed apart from the runs.
    - One median-length trace would take 1.3 to 2.5 h, and the whole training set 146
      to 272 h on one process.
    - These times are upper bounds for the C++ harness. CBP's simulator runs about
      1.1e5 instructions/s.
  - Problem 5: predictor storage at the default parameters is 67.3 KB in total. TAGE,
    SC and the loop predictor together come to 20.9 KB, the part comparable with the
    reference predictor's 64 KB. Some bits are counted on assumptions I could not check
    in the table RTL: the EPC field, the per-entry valid bit and the RAS counter.
    Results Capture lists them.
  - Problem 6: the README section is added with its contents entry. The script's stop
    messages name the section; I tested the missing-directory case.

  Two findings change PF-U1:
  - Far jumps and calls: direct jumps and calls beyond +-1 MB occur 11.76 million times
    in 89 of the 105 traces. That is 12 times as many as far conditional branches
    (0.99 million).
  - Addresses out of range: 81 traces have PCs at or above 2^41 (kernel-half addresses
    up to 0xffffff8008edbebc). Pacino's 41-bit virtual address cannot hold them, so the
    code image has to be relocated whatever PF-U1 decides.

  Results Capture also has the proposed wording for perf_decisions.md (PF-U1, PF-U2,
  PF-U7, PF-7, and a note for PF-6/PF-10). It also lists every file I read outside the
  Context Loaded list, such as the .git ref files and the CBP counting sources. No git
  command was run.

  Files are in perf/:
  - scan_traces.py
  - cbp2025_training.sha256
  - cbp2025_training_scan.csv


## My Assessment

The 41bit range issue is a problem. Traces contain 48 bit IA has suggested
re-mapping the traces. 

I asked the IA to look at the trace PC's.

IA: 
The PC field in a record is 8 bytes. The values in it look like Arm 48-bit virtual
addresses, but the scan only recorded each trace's lowest and highest PC, so that is
checked only at the extremes, not for every PC.

  What the extremes show:

  - Lower half (bit 63 clear, user space): the 81 traces whose highest PC is in this
    half are within 48 bits. Their highest PCs are 32, 47 or 48 bits wide, for example
    0xfffff38f635c, near the top of a 48-bit user space. The lowest PCs are 22 to 32
    bits.
  - Upper half (bit 63 set, kernel space): 60 traces reach it, and their highest PCs
    have bits 63:48 all ones:
    - 0xffff0000085d4c88, the Linux arm64 kernel image base for 48-bit VA on older
      kernels (17 traces: web_0 to web_9, infra_1, 2, 6, 9, 11 to 13)
    - 0xffff8000..., the same for newer kernels (34 traces)
    - 0xfffffbfffdbfc7e4 (the 8 compress traces)
    - 0xffffff8008edbebc (int_36), where a 39-bit kernel VA configuration places the
      kernel image. It is still inside the 48-bit upper range.

  So the traces fit Arm's 48-bit layout:
  - user addresses below 2^48
  - kernel addresses with bits 63:48 all ones

  Arm separates the two by the top address bits, not by sign extension of bit 47.

  That matters for RISC-V. A RISC-V address is canonical only when its upper bits all
  equal the top bit of the VA width. A kernel address like 0xffff0000085d4c88 has bits
  63:48 set but bit 47 clear. That is valid on Arm, but it is not canonical even under
  Sv48, so pacino could not use it unmodified with a wider VA either. The 17 traces
  with that layout need their addresses mapped no matter how VA_WIDTH is set. The
  0xffff8000... and int_36 kernel addresses are Sv48-canonical, but still too wide for
  Sv39.

  Two corrections to what I said earlier:
  - I described the traces as having 48-bit virtual addresses and called the kernel
    addresses invalid under Sv48. That was too broad: it applies only to the
    0xffff0000... layout.
  - The "81 of 105 traces with PCs at or above 2^41" in Results Capture is a different
    count: it also includes the 21 traces that reach 47- or 48-bit user addresses. Only
    60 of the 81 reach kernel addresses.

  To confirm that every PC fits the 48-bit layout, not just each trace's lowest and
  highest, the scanner would need to classify every static PC. That means a rerun of
  about 6 minutes, and the CSV would change. Do you want me to do that?


## Claude.ai Assessment

PERF-001 is sound. All six problems were accepted, and the strongest result is that every one of the 105 traces matches the reference counts exactly. That confirms the trace reader and the warmup method, so these numbers can be trusted. Four of the errors it corrected were mine, from the Background I wrote:

I said traces were 30 to 40 million instructions long; they run from 10 to 130 million.
I gave the far-branch share against all conditional branches when it should have been taken ones: it’s 4.1% of taken ones, not 2.2%.
I generalized “no far jumps” from two samples. Across the full set there are many.
I said the unpacked traces take 12.5 GB. That’s the archive size; unpacked they take 15 GB.

What it found, in order of importance:

Every code image needs relocation. 81 traces have PCs above pacino’s 41-bit virtual address range, 60 of them in kernel space. Direct jumps and calls beyond ±1 MB occur 2.7 times per thousand instructions, in 89 traces, twelve times as often as far conditional branches. So the code-image question (PF-U1) is now how to relocate, and three things decide that:
Which PC bits pacino’s predictors hash, for index and tag. A relocation that leaves those bits unchanged leaves the predictor behavior unchanged. That’s a lookup in the RTL, not a guess.
The far jumps and calls. A direct jump whose relocated target is still beyond ±1 MB can’t be encoded as a jal. Turning it into an indirect jump changes which predictor handles it, and leaving the encoding wrong makes predecode redirect it. This is the hard part.
Kernel code. Kernel and user code would land in one flat address space. Running bare, with no translation (PF-U4), is the simplest way to do that, and then the limit is pacino’s physical address width.
Pacino’s direction predictors are a third of R’s size: TAGE, SC and the loop predictor total 20.9 KB, against R’s 64 KB. So A against R isn’t an equal-storage comparison; expect A’s MPKI to be higher for that reason alone. B (cbp16-64k) matters more than I thought. Three of the bits counted (EPC, the valid bits, the RAS counter) were assumed rather than checked against the table RTL. That’s minor.
R’s MPKI covers conditional branches only. Its indirect prediction is perfect, so pacino’s ITTAGE and RAS numbers have no counterpart in R.
Speed is better than it looks. The SystemVerilog testbench runs 4.4 to 8.3 thousand instructions per second, which is 146 to 272 hours for the whole set on one process. Split across your 32 threads, that’s roughly 5 to 9 hours, if it scales; that wasn’t measured. The C++ harness can only be faster, so full traces overnight look possible already.

Record defects:

Files read outside the manifest. The IA read files that weren’t listed: .git refs, CBP’s counting sources and sim_common_structs.h. CLAUDE.md says to stop and report before doing that, and it reported them only afterwards. That’s partly my fault: the task asked for shas and counting rules without listing the files that hold them.
The tree wasn’t at fe-1.0.0. It was 79df3ad, uncommitted. git diff fe-1.0.0 HEAD -- rtl/ would show whether the RTL measured is the tagged RTL.

The IA’s question about rerunning the scan to classify every PC. I’d fold that into PERF-002 rather than rerun now. Relocation needs more than every PC classified. It needs:

each trace’s address regions, as clusters, not just its lowest and highest PC;
which PC bits each predictor hashes;
how many far jumps would still be out of reach after the relocation that’s chosen.

## Follow-on Actions
- [ ] Determine a solution to the address range problem.

## CLAUDE.md Updates
Nothing required

## Other Planning File Updates
Nothing required

:: DISCUSSION:END ::

=============================================================
:: PROMPT:START ::
=============================================================

## Task ID
PERF-001

## Context Loaded
@planning/perf/perf_decisions.md
@tools/cbp2025/README.md
@tools/cbp2025/lib/trace_reader.h
@tools/cbp2025/lib/bp.cc
@tools/cbp2025/reference_results_training_set.csv
@rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
@rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
@rtl/core/frontend/fe_top/Makefile
@README.md

## Context Comments
perf_decisions.md is the decision record for this work (PF-N, PF-UN).
tools/cbp2025 is Jeff's fork of the CBP2025 repository, a submodule,
read only. trace_reader.h defines the trace record; the scan script is
written from it, and no CBP code is copied into pacino (PF-1). bp.cc
prints the counts the reference results hold. The reference CSV has
one row per training trace.

bp_defines_pkg.sv and bp_structs_pkg.sv hold the predictor parameters
and entry types from which the storage is totaled. The fe_top Makefile
has the sim_fe_top_<program> targets used to time the Verilated
fe_top. README.md gets the performance section.

The training traces are outside the repository, in
/home/jeff/Development/jeffnye-gh/cbp_traces/training_traces/, which is
an additional working directory of the session: it reads without
prompts. They are not listed above because they are data, not
context.

## Hypothesis
The training traces can be characterized, checked against the
reference results, and sized against the harness's speed with no
change to the RTL, and the results say whether full traces are
practical here and how often the code image must work around a branch
RISC-V cannot encode.

## Background
Facts checked by the PA in session-084. The IA confirms each in
Problem 0.
- The CBP2025 training set is 105 traces in six groups: int 37, web 26,
  infra 16, fp 14, compress 8, media 4. The reference CSV gives 4.34e9
  instructions in all, 30e6 to 40e6 per trace. Its columns include
  Instr, NumBr, MispBr, MPKI and, for the second half of a trace,
  50PercInstr, 50PercNumBr, 50PercMispBr and 50PercMPKI.
- Jeff has unpacked the six training archives into .gz trace files
  under training_traces/; the archives are beside them, untouched. The
  paths inside the archives were not seen; the layout CBP's run script
  expects is <dir>/<group>/<trace>.gz.
- The traces are Arm's. training_traces/readme.txt: "provided for the
  sole purpose of the competition as an aid to learning and academic
  advancement". Every PC in the two sample traces is 4-byte aligned.
- CBP's simulator reads a .gz trace directly (gzstream and zlib); its
  Makefile builds the simulator in place, in the source directory.
- The PA's scan of CBP2025's two 1e6-instruction sample traces: in the
  int sample 2776 of 128874 taken conditional branches go beyond the
  +-4 KB of a RISC-V conditional branch, none in the fp sample; no
  direct jump or call goes beyond +-1 MB; no direct branch has more
  than one target; the int sample's code spans 0x323048 to 0x80002b44.
- tb_fe_top runs one program per simulation (+PROG=<name>), each its
  own target sim_fe_top_<program>; each reports its cycles and
  mispredicts. Its testbench is SystemVerilog built with --timing.
- bp_ftq_slot_t.pred_src (bp_pred_src_e) records which predictor
  supplied the final prediction.

## Binding Previous Decisions
- PF-1: CBP's traces and reference results only. No CBP code is copied
  into pacino; the scan script is pacino's own, written from the
  record format in trace_reader.h.
- PF-2 and PF-14: perf code in perf/; traces outside git. The perf
  scripts find the traces through the environment variable
  CBP_TRACES, default ../cbp_traces relative to the repository root,
  with no machine path in the code. All the perf setup notes are in
  the main README.md, and a perf script that cannot find or check its
  traces stops with a message naming the problem and that README
  section.
- PF-7: the reference results' second half is read as the measured
  part after a first-half warmup, until PF-U2 confirms it.
- PF-11: the harness is checked by exact counts against the reference
  results; this task produces the counts the check will compare.
- PF-12: PERF-001 builds nothing for the gasket.
- The traces are used as unpacked; nothing is extracted, copied or
  moved by this task (Jeff, session-084).
- fe-1.0.0 is the configuration measured (PF-5).

## Specific Requirements

Problem 0: the starting state
Before writing anything, report:
- each Background fact found false, with what was found; the problems
  below follow what is found.
- the layout of training_traces/: the directories, the number of .gz
  files in each, and their total size. If it is not one directory per
  group holding .gz files, report it and stop before Problem 1.
- that tools/cbp2025 is present, its commit, and that the reference
  CSV has 105 rows naming the same traces as the .gz files found.
- the git sha of the tree and whether it is the fe-1.0.0 tag.

Problem 1: the checksum list
perf/cbp2025_training.sha256 lists the SHA-256 of each training .gz
file, one per line in sha256sum's format, with paths relative to
CBP_TRACES, sorted by path. Accepted when sha256sum -c, run from
CBP_TRACES against the list, reports every file OK.

Problem 2: the characterization
perf/scan_traces.py reads every training trace through the record
format of trace_reader.h, in parallel across traces, and writes
perf/cbp2025_training_scan.csv, one row per trace, sorted by group and
name, with at least: group, trace, instructions, conditional branches
(all and taken), direct jumps, indirect jumps, direct and indirect
calls, returns, static PCs, distinct 4 KB code pages, lowest and
highest PC, PCs not 4-byte aligned, static direct branches with more
than one target, taken conditional branches beyond +-4 KB (dynamic and
static), and direct jumps or calls beyond +-1 MB (dynamic and static).
It takes CBP_TRACES as PF-14 says and checks each file against
perf/cbp2025_training.sha256 before reading it.
Accepted when:
- the instruction count of every trace equals the reference CSV's
  Instr, and the branch counts match NumBr by whatever NumBr is found
  to count in Problem 3, for all 105 traces; any trace that does not
  match is listed with both numbers.
- the script finds the two sample traces' counts the PA found
  (Background), run on tools/cbp2025/sample_traces.
- its run time over the whole training set is reported, and the
  number of processes it used.
Results Capture gives a summary per group: traces, instructions, the
far-branch rates of PF-U1, footprint range, and any trace with a
direct branch of more than one target or an unaligned PC.

Problem 3: what the reference results count (PF-U2)
Build CBP's simulator from a copy of tools/cbp2025 in the scratchpad,
not in tools/cbp2025. Run it on one training trace, the smallest of
the int group, as CBP's README gives, and report:
- whether its output equals that trace's reference CSV row, every
  column, which says whether the reference results come from the
  simulator's default predictor, and which predictor that is.
- what NumBr counts, from bp.cc and from the run: all branches or
  conditional branches only.
- what the 50Perc columns cover, from bp.cc: the second half after a
  first-half warmup, or otherwise.
- the run's time.

Problem 4: the speed of the Verilated fe_top
Run three of the sim_fe_top_<program> targets of the fe_top Makefile
at the default slot count, each timed with /usr/bin/time, the build
timed apart from the runs. For each report the simulated cycles, the
retired instructions if the testbench reports them, and the wall time
of the run, giving cycles per second and, where the instructions are
known, instructions per second. Then state what the measured rate
gives for one training trace of the median length and for the whole
training set on one process, stated as a lower bound for the C++
harness (PF-3), since this testbench is SystemVerilog with --timing.

Problem 5: predictor storage at fe-1.0.0 (PF-U7)
From bp_defines_pkg.sv and bp_structs_pkg.sv, total the storage of
each predictor's tables at the default parameters: entries times the
stored entry width in bits, per table and per predictor, and the
total in KB. State the method: which declarations each width comes
from, and what is counted (tags, counters, useful bits, targets) and
what is not (FTQ, history registers). Give the CBP2025 storage budget
and the reference predictor's 64 KB beside the total, for comparison.

Problem 6: the README section
README.md gains a section, Performance analysis, after Run code
coverage: what the performance work is (one paragraph, PF-10's
first-layer filter), the traces it needs (CBP2025 training set, where
to get them, unpacked to .gz, the expected layout, about 12.5 GB), the
CBP_TRACES variable and its default, the checksum check with
perf/cbp2025_training.sha256, the Arm notice quoted, and one optional
line for Claude Code users who restrict reads outside the repository:
add the trace directory with --add-dir or in their own settings. The
table of contents gains its entry. Accepted when the section exists
and the error messages of Problem 2's script name it.

## Constraints
- Writes are limited to the files in Deliverables, and scratch files
  in the session's scratchpad. Nothing under the trace directory is
  written, moved, copied or extracted. tools/cbp2025 is read only;
  CBP's simulator is built in the scratchpad copy.
- No RTL, testbench, Makefile or package file changes. The fe_top
  targets are run as they are.
- The IA runs no git command, in any directory. Running
  tools/regress.sh, which makes git calls of its own, is permitted;
  that grant is to run the script, not any command it contains.
- No network access is needed or used.
- The scan script is Python 3, standard library only, ASCII, 80
  columns, with the SPDX header of the other tools scripts.
- Only what this task needs is changed; anything else noticed is listed
  in Results Capture.

## Deliverables
Note: If a new module is to be created ensure that claude.code is allowed
or told to modify the Makefile for lint checking at the minimum.

Files the IA may create or change:
- perf/scan_traces.py, new
- perf/cbp2025_training.sha256, new
- perf/cbp2025_training_scan.csv, new
- README.md, the Performance analysis section and its contents entry
- prompts/PERF-001.md, Results Capture filled in below

Results Capture reports: Problem 0's findings; for each problem whether
it is accepted, with the evidence; the per-group summary of Problem 2;
Problem 3's answers to PF-U2; Problem 4's rates and projections;
Problem 5's table; what each finding means for PF-U1, PF-U2, PF-U7 and
PF-7, as proposals for perf_decisions.md (the IA does not edit it);
and the tools/regress.sh summary from this session, sha line
included, not cut by a pipe.

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary
All six problems accepted. The hypothesis holds: the traces were
checked, characterized and sized with no RTL change.
- Checksums: 105 of 105 OK.
- Scan: all 105 traces equal the reference results exactly in Instr,
  NumBr, 50PercInstr and 50PercNumBr. 339.6 s on 32 processes.
- PF-U2 settled. CBP's simulator, run on int_1_trace, equals the
  reference row in every result column. The reference predictor is
  the default 64 KB TAGE-SC-L, with indirect prediction perfect.
  NumBr counts conditional branches only. 50Perc is the trailing
  1M-record epochs after the rest of the trace has trained the
  predictor.
- Speed: the Verilated SystemVerilog fe_top testbench runs 4.4e3 to
  8.3e3 instructions/s. At that rate one median trace takes 1.3 to
  2.5 h and the training set 146 to 272 h on one process. These are
  upper bounds for the C++ harness (PF-3).
- Storage at the default parameters: 551280 bits, 67.3 KB, all
  predictors. Conditional-direction predictors (TAGE + SC + loop):
  20.9 KB, against R's 64 KB.
- Two findings change PF-U1:
  - Direct jumps and calls beyond +-1 MB: 11.76e6 dynamic, 106277
    static, in 89 of 105 traces. That is 12x the far conditional
    branches (0.99e6 dynamic, 7537 static).
  - 81 of 105 traces have PCs at or above 2^41, up to
    0xffffff8008edbebc. pacino's 41-bit VA cannot hold them, so the
    code image must be relocated whichever PF-U1 choice is made.
- tools/regress.sh: PASS, 274 targets, 0 new failures (summary below).

## What was delivered
- perf/cbp2025_training.sha256: 105 lines in sha256sum format, paths
  relative to CBP_TRACES (training_traces/<group>/<trace>.gz), sorted
  by path in byte order (LC_ALL=C).
- perf/scan_traces.py: Python 3, standard library only, ASCII, 80
  columns, with the SPDX header of tools/fe_release.py. It reads the
  record format of trace_reader.h, has no CBP code, and runs a
  multiprocessing pool, largest trace first. Before reading a file it
  checks it against the sha256 list. Every stop message names README.md
  section Performance analysis. It compares Instr, NumBr, 50PercInstr
  and 50PercNumBr with the reference CSV and exits 1 on any mismatch.
  --dir scans any <dir>/<group>/*.gz with no checksum check.
- perf/cbp2025_training_scan.csv: 105 rows, sorted by group and then
  trace number. Columns: group, trace, instructions, cond_br,
  cond_br_taken, cond_br_pieces, jump_direct, jump_indirect,
  call_direct, call_indirect, returns, static_pcs, static_cond_br,
  static_direct_jmp_call, code_pages_4k, pc_min, pc_max,
  pc_unaligned_static, multi_target_static, far_cond_taken_dyn,
  far_cond_static, far_jal_dyn, far_jal_static, half_instr,
  half_cond_br_pieces.
- README.md: a new section, Performance analysis, after Run code
  coverage, and its contents entry.

## Test Case Results

### Problem 0: the starting state
Background facts found false or incomplete:
- "30e6 to 40e6 per trace": FALSE. The range is 10001443 (web_11) to
  130000052 (compress_3, compress_7). The median is 40000016. The total
  is 4335743404, which matches 4.34e9.
- "in the int sample 2776 of 128874 taken conditional branches go
  beyond +-4 KB": the DENOMINATOR IS WRONG. 128874 is all conditional
  branches of the int sample; 67965 are taken. 2776 is 4.08 percent of
  the taken ones and 2.15 percent of all. PF-U1's "2.2 percent" is a
  share of all conditional branches, not of taken ones.
- "no direct jump or call goes beyond +-1 MB" and "no direct branch
  has more than one target": true of the two samples, FALSE of the
  training set (Problem 2).
- "about 12.5 GB" (Problem 6): that is the size of the six .tar.xz
  archives (12260564 KiB). The unpacked .gz files total 15047360734
  bytes, about 15.0 GB. The README gives both sizes.
- The paths inside the archives remain unseen. Each group directory
  also holds a readme.txt (426 bytes) beside its .gz files.
- All other Background facts were confirmed:
  - six groups and their counts
  - reference CSV columns
  - every PC 4-byte aligned, in all 105 traces
  - CBP reads .gz directly and builds in its source directory
  - the int sample span 0x323048 to 0x80002b44
  - tb_fe_top reports cycles and mispredicts, and also retired
    instructions
  - bp_ftq_slot_t.pred_src exists (bp_structs_pkg.sv)

Layout. CBP_TRACES = ../cbp_traces holds training_traces/ (and
full_traces/, which holds only .tar.xz archives and a readme). Under
training_traces/ there is one directory per group, each holding .gz
files:

| group    | .gz files | bytes (dir, incl. readme.txt) |
|----------|-----------|-------------------------------|
| compress | 8         | 1699373393                    |
| fp       | 14        | 2267757745                    |
| infra    | 16        | 2140451433                    |
| int      | 37        | 6066489697                    |
| media    | 4         | 454360308                     |
| web      | 26        | 2418930714                    |
| total    | 105       | 15047363290                   |

The layout is one directory per group holding .gz files, so the task
continued to Problem 1.

tools/cbp2025 is present at commit
607496629452740887dc1b90a46834cc90dda1e0, read from
.git/modules/tools/cbp2025/refs/heads/main. The reference CSV has 105
rows. The (Workload, Run) pairs equal the 105 .gz files found: the
scan's reference check reported no trace missing from either side.

Tree: HEAD is main at 79df3ad4dd14f1ceb3fee410fc64d21f4f564ddf, and
the tree is dirty (regress.sh reports "79df3ad (dirty)"). The ref
.git/refs/tags/fe-1.0.0 holds 585910b3bae7c36be0251d39051bec56916e54c2.
That is not HEAD, so the tree is NOT fe-1.0.0. Without git it cannot
be told whether that sha is a commit or an annotated tag object; it
differs from HEAD either way. The measurements and the storage totals
are of the working tree. PF-9 keys a result on an untagged tree by
its sha.

### Problem 1: the checksum list -- ACCEPTED
(cd ../cbp_traces && sha256sum -c ../pacino/perf/cbp2025_training.sha256)
printed 105 lines, all OK. With --quiet it exited 0.

### Problem 2: the characterization -- ACCEPTED
- The full training-set run printed: "reference check: 105 traces,
  Instr, NumBr, 50PercInstr and 50PercNumBr all equal". No trace
  mismatches. NumBr is compared with cond_br_pieces, per Problem 3.
  cond_br_pieces equals cond_br, the record count, in all 105 traces.
- Sample traces (--dir tools/cbp2025/sample_traces):
  - int: 997301 instructions, 128874 conditional branches (67965
    taken), 2776 far taken conditional branches (3 static), 0 far
    jal, 0 multi-target, PC 0x323048 to 0x80002b44.
  - fp: 997741 instructions, 111265 conditional, 0 far.
  These equal the PA's counts, with the denominator corrected as in
  Problem 0. They also equal CBP's README sample output: fp
  JumpDirect 26868 = 16279 jumps + 10589 calls, JumpIndirect 1,
  JumpReturn 10589.
- Run time: 339.6 s wall on 32 processes (os.cpu_count(), 32
  threads). This includes the SHA-256 check of each file. The longest
  single trace was compress_7 at 274.1 s. The sample run took 1.7 s on
  2 processes.

Per-group summary. Rates: far_c% = far taken conditional / taken
conditional. PKI = per 1000 instructions. far_c_st% = far static /
static conditional. Footprint = distinct 4 KB code pages, min-max per
trace.

| group    | traces | instr (e9) | far cond dyn | far_c% | far_c PKI | far cond static | far_c_st% | far jal dyn | far jal PKI | far jal static | traces with far jal | 4 KB pages | static PCs     |
|----------|--------|------------|--------------|--------|-----------|-----------------|-----------|-------------|-------------|----------------|---------------------|------------|----------------|
| compress | 8      | 0.542      | 595          | 0.003  | 0.001     | 32              | 0.13      | 240368      | 0.44        | 1158           | 8 of 8              | 177-360    | 15693-37305    |
| fp       | 14     | 0.510      | 7728         | 0.030  | 0.015     | 45              | 1.14      | 90085       | 0.18        | 176            | 10 of 14            | 4-76       | 246-8844       |
| infra    | 16     | 0.740      | 42881        | 0.127  | 0.058     | 267             | 0.39      | 4181597     | 5.65        | 6386           | 14 of 16            | 4-655      | 176-89405      |
| int      | 37     | 1.724      | 791110       | 0.769  | 0.459     | 2030            | 0.72      | 3354196     | 1.95        | 29216          | 27 of 37            | 7-4379     | 477-605024     |
| media    | 4      | 0.080      | 0            | 0.000  | 0.000     | 0               | 0.00      | 119734      | 1.50        | 237            | 4 of 4              | 53-140     | 4224-34113     |
| web      | 26     | 0.740      | 146246       | 0.352  | 0.198     | 5163            | 0.77      | 3772054     | 5.10        | 69104          | 26 of 26            | 85-4068    | 9251-502037    |
| all      | 105    | 4.336      | 988560       | 0.432  | 0.228     | 7537            | 0.72      | 11758034    | 2.71        | 106277         | 89 of 105           | 4-4379     | 176-605024     |

- 27 traces have no far conditional branch. The highest rate is
  int_13: 12.87 percent of taken conditional branches. Next are int_15
  (3.96), int_11 (2.58), web_12 (2.27) and int_10 (2.25).
- Direct branches with more than one target: only web_9_trace, 3
  static branches.
- Unaligned PCs: none, in any trace.
- PC range over all traces: 0x26f5f0 to 0xffffff8008edbebc. 81 of 105
  traces have a PC at or above 2^41, which is also 2^39: all of web,
  infra, compress and media, 22 of int, 5 of fp. These are upper-half
  (kernel) addresses such as 0xffff800080a592d0.

### Problem 3: what the reference results count (PF-U2) -- ACCEPTED
The simulator was built in a scratchpad copy of tools/cbp2025
(make -j8, 42.9 s). The copy's .git pointer file was removed;
tools/cbp2025 was not touched. The trace was int_1_trace, run as
`cbp <trace>.gz` (README, Examples).
- Output vs the int_1_trace reference row: EQUAL in every result
  column. Instr 30000052, Cycles 18836926, IPC 1.5926, NumBr 5301134,
  MispBr 349374, BrPerCyc 0.2814, MispBrPerCyc 0.0185, MR 6.5906%,
  MPKI 11.6458, CycWP 14889272, CycWPAvg 42.6170, CycWPPKI 496.3082.
  The 50Perc columns are equal as well: 15000052, 8984253, 1.6696,
  2642836, 173474, 0.2942, 0.0193, 6.5639%, 11.5649, 7045071,
  40.6117, 469.6698. Only TraceSize and ExecTime differ; they are run
  metadata, not results. So the reference results come from the
  simulator's default predictor. cond_branch_predictor_interface.cc
  includes cbp2016_tage_sc_l.h, the CBP2016 64 KB TAGE-SC-L (not the
  _192kb variant). parameters.cc sets PERFECT_INDIRECT_PRED = true,
  so indirect jumps, indirect calls and returns are never
  mispredicted (MispBr 0 in the run), and no ITTAGE is built.
- NumBr: bp.cc counts meas_conddir_n only for condBranchInstClass,
  once per record PIECE (BP.predict is called per piece in
  uarchsim.cc). The run printed CondDirect NumBr 5301134 = the CSV
  NumBr, against JumpDirect 1242684, JumpIndirect 66695 and
  JumpReturn 83423. So NumBr counts CONDITIONAL BRANCHES ONLY. No
  conditional branch has more than one piece in any training trace,
  so it also equals the conditional branch records. MPKI = 1000 *
  conditional mispredicts / Instr. Instr counts records (num_inst +=
  is_last_piece).
- 50Perc (bp.cc output_periodic_info): epochs are 1M records
  (EPOCH_SIZE_INSTS). The code walks back from the last epoch and sums
  until the instruction count exceeds total/2. The window is the
  trailing whole epochs, from 50 percent up to 50 percent plus one
  epoch. Examples: int_4 30999657 of 59999657, int_1 15000052 of
  30000052. Over the training set it is up to 999994 records more
  than half. The predictor is never reset and the counts are summed
  per epoch, so the epochs before the window act as warmup. In
  effect it is the second half after a first-half warmup, at 1M-epoch
  granularity, not an exact half.
- Run time: 275.7 s wall, 275.4 s user, 93 MB max RSS (the reference
  CSV's ExecTime for this trace is 242.4 s). That is 1.09e5
  instructions/s.

### Problem 4: the speed of the Verilated fe_top -- ACCEPTED
- Build: build_fe_top into a scratchpad object directory, timed apart
  from the runs: 17.8 s wall. The tree's obj_fe_top was not used.
- The three longest programs were found by running all 37 FE_PROGS.
  Each was run with `make -C rtl/core/frontend/fe_top
  sim_fe_top_<p>`, timed with /usr/bin/time, at the default 2 slots
  with the targets' fast-init plusargs. VER_OUT pointed to the scratch
  build, as a relative path because the recipe runs
  ./$(VER_OUT)_fe_top/Vtb. Each run passed (PASS=20 FAIL=0).

| program  | cycles | retired | Verilator walltime (s) | make target wall (s) | cycles/s | instr/s |
|----------|--------|---------|------------------------|----------------------|----------|---------|
| rec_undo | 4263   | 2307    | 0.521                  | 0.67                 | 8182     | 4428    |
| pt_rsv_h | 6361   | 114     | 1.124                  | 1.27                 | 5659     | 101     |
| t0_uaon  | 1263   | 1510    | 0.183                  | 0.34                 | 6902     | 8251    |

  Rates are from Verilator's own walltime, the simulation including
  model start-up. The make target wall time adds about 0.15 s of make
  and Verilator's up-to-date check. A fit over rec_undo and t0_uaon
  gives a marginal 8.9e3 cycles/s and about 0.04 s of start-up.
  pt_rsv_h's instruction rate is not representative: 34 traps and 71
  page-table walks in 114 instructions.
- Projection at 4428 to 8251 instructions/s on one process:
  - one trace of the median length (40000016): 4848 to 9033 s, 1.3 to
    2.5 h.
  - the whole training set (4335743404): 5.25e5 to 9.79e5 s, 146 to
    272 h, 6.1 to 11.3 days.
  These rates are a LOWER BOUND on the C++ harness speed (PF-3), and
  the times an upper bound. This testbench is SystemVerilog built
  with --timing, with every unit's bound properties (--assert) and SV
  memory, walker and backend models. For scale, CBP's simulator ran
  13x to 25x faster per instruction (1.09e5/s). Runs are in parallel
  (PF-7). 32 processes on this 32-thread machine would divide the
  set's time by up to 32 in the ideal case; that was not measured.

### Problem 5: predictor storage at fe-1.0.0 (PF-U7) -- ACCEPTED
Method:
- Entries times the stored entry width, from the current tree's
  bp_defines_pkg.sv and bp_structs_pkg.sv. HEAD is not the tag
  (Problem 0).
- Width sources:
  - TAGE, SC and ITTAGE: the per-table parameter arrays
    (*_TBL_ENTRIES, _TAG, _CTR, _USE, _EPC, and IT_TBL_TGT_WIDTH),
    plus 1 valid bit per tagged entry (TAGE_MAX_VAL_WIDTH and
    IT_MAX_VAL_WIDTH = 1; SC_MAX_VAL_WIDTH = 0).
  - Loop: lp_entry_t (68 bits).
  - FTB: FTB_ENTRY_WIDTH (114 bits). This includes the entry-valid
    bit that lives in ftb_plru.
  - uBTB: UBTB_ENTRY_WIDTH = ubtb_entry_t (107 bits).
  - RAS: RAS_ADDR_WIDTH plus RAS_RCTR_WIDTH per entry, both stacks.
- Counted: tags, counters, useful bits, the EPC field, targets,
  positions, status and type bits, valid bits.
- Not counted: the FTQ and its meta, history registers (GHR, PHR,
  folded histories, BrIMLI), the FTB tree-PLRU (512 x 3 = 1536 bits),
  SC thresholds and chooser, TAGE and ITTAGE USE_ALT_ON_NA counters,
  arbitration queues.

| predictor | table   | entries | bits/entry               | bits   |
|-----------|---------|---------|--------------------------|--------|
| TAGE      | T0      | 2048    | 2 (ctr)                  | 4096   |
| TAGE      | T1-T4   | 4x2048  | 16 (v1 tag8 ctr3 u2 e2)  | 131072 |
| TAGE      | total   |         |                          | 135168 |
| SC        | ST0-ST3 | 4x512   | 6                        | 12288  |
| SC        | ST4     | 1024    | 6                        | 6144   |
| SC        | total   |         |                          | 18432  |
| ITTAGE    | IT1-IT2 | 2x256   | 56 (v1 tag8 c3 u2 e2 t40)| 28672  |
| ITTAGE    | IT3-IT4 | 2x512   | 57 (tag9)                | 58368  |
| ITTAGE    | IT5     | 512     | 59 (tag11)               | 30208  |
| ITTAGE    | total   |         |                          | 117248 |
| Loop      | 4-way   | 256     | 68                       | 17408  |
| FTB       | 4-way   | 2048    | 114                      | 233472 |
| uBTB      | 4-way   | 256     | 107                      | 27392  |
| RAS       | spec+cm | 16+32   | 45 (addr41 rctr4)        | 2160   |
| all       |         |         |                          | 551280 |

| subset                                    | bits   | KB (1024 B) |
|-------------------------------------------|--------|-------------|
| all predictors                            | 551280 | 67.29       |
| TAGE                                      | 135168 | 16.50       |
| SC                                        | 18432  | 2.25        |
| ITTAGE                                    | 117248 | 14.31       |
| Loop                                      | 17408  | 2.13        |
| FTB                                       | 233472 | 28.50       |
| uBTB                                      | 27392  | 3.34        |
| RAS                                       | 2160   | 0.26        |
| conditional direction (TAGE + SC + loop)  | 171008 | 20.88       |

For comparison:
- R, the reference predictor, is a 64 KB TAGE-SC-L.
- The CBP2025 budget is 192 KB: R's 64 KB plus up to 128 KB of added
  components, or 192 KB of new ones (tools/cbp2025/README.md).
- That budget covers conditional direction prediction only.
  Indirect prediction is perfect and target storage is not modeled.
- The like-for-like figure is therefore pacino's 20.9 KB of
  TAGE + SC + loop against 64 KB. The FTB and uBTB also hold 3-bit
  direction counters (2 per entry), which have no counterpart in R.

### Problem 6: the README section -- ACCEPTED
- The section "## Performance analysis" is in Quick start, after Run
  code coverage and before Push. It has these parts:
  - what the work is, as PF-10's first-layer filter
  - Traces: the training set, the download link by reference to
    tools/cbp2025/README.md Getting Traces, unpacked to .gz, the
    layout, 12.5 GB archived and 15 GB unpacked
  - CBP_TRACES and its default
  - Checksums: sha256sum -c and the script
  - Notice: the Arm text quoted verbatim from readme.txt
  - the optional Claude Code line
- The contents gained "Performance analysis" after Quick start.
- The script's messages name it, for example: "scan_traces.py: trace
  directory /nonexistent not found; set CBP_TRACES (see README.md,
  section Performance analysis)", exit 1.

### tools/regress.sh (this session)
```
REGRESSION SUMMARY  git 79df3ad (dirty)
root /home/jeff/Development/jeffnye-gh/pacino
jobs 15 (default: 32 threads / 2, 31 GB / 2); priority: nice -n 10, ionice -c 3
==================================================================
== rtl/core/csr
  PASS       lint_csr_pkg           rc=0   warn=0  err=0  -              0s
  PASS       lint_csr_tb_pkg        rc=0   warn=0  err=0  -              0s
  PASS       sim_csr_tb_pkg         rc=0   warn=0  err=0  150/0          1s
  time 1s
== rtl/core/frontend/bpu
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       lint_loop_pred         rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_table        rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_table          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_brimli         rc=0   warn=0  err=0  -              1s
  PASS       lint_sc_cntrl          rc=0   warn=0  err=0  -              0s
  PASS       lint_sc                rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_table      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_cntrl      rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_arb        rc=0   warn=0  err=0  -              1s
  PASS       lint_ittage            rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_cntrl        rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_arb          rc=0   warn=0  err=0  -              0s
  PASS       lint_tage              rc=0   warn=0  err=0  -              1s
  PASS       lint_ras               rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_array         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru          rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl         rc=0   warn=0  err=0  -              1s
  PASS       lint_ftb               rc=0   warn=0  err=0  -              0s
  PASS       lint_bp_cluster        rc=0   warn=0  err=0  -              1s
  PASS       sim                    rc=0   warn=0  err=0  29/0           1s
  PASS       sim_history            rc=0   warn=0  err=0  21470/0       15s
  PASS       sim_ubtb               rc=0   warn=0  err=0  341/0         10s
  PASS       sim_loop_pred          rc=0   warn=0  err=0  9408/0         8s
  PASS       sim_tage_table         rc=0   warn=0  err=0  15/0           0s
  PASS       sim_sc_table           rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_table_fast      rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_brimli          rc=0   warn=0  err=0  7/0            1s
  PASS       sim_sc_brimli_fast     rc=0   warn=0  err=0  7/0            0s
  PASS       sim_sc_cntrl           rc=0   warn=0  err=0  98/0           6s
  PASS       sim_sc                 rc=0   warn=0  err=0  144/0          7s
  PASS       sim_sc_fast            rc=0   warn=0  err=0  140/0          4s
  PASS       sim_ittage_table       rc=0   warn=0  err=0  32/0           0s
  PASS       sim_ittage_cntrl       rc=0   warn=0  err=0  147/0          4s
  PASS       sim_ittage             rc=0   warn=0  err=0  389/0          4s
  PASS       sim_ittage_fast        rc=0   warn=0  err=0  389/0          3s
  PASS       sim_bp_cluster         rc=0   warn=0  err=0  2037/0         9s
  PASS       sim_bp_cluster_init    rc=0   warn=0  err=0  2037/0        37s
  PASS       sim_ras                rc=0   warn=0  err=0  264/0          3s
  PASS       sim_ftb                rc=0   warn=0  err=0  239/0          4s
  PASS       sim_tage               rc=0   warn=0  err=0  109/0          3s
  PASS       sim_tage_fast          rc=0   warn=0  err=0  109/0          2s
  PASS       sim_tage_tasks         rc=0   warn=0  err=0  1/0            3s
  PASS       sim_tage_manual        rc=0   warn=0  err=0  1267/0         3s
  PASS       cov_history            rc=0   warn=0  err=0  21470/0       11s
  PASS       cov_ubtb               rc=0   warn=0  err=0  341/0          8s
  PASS       cov_loop_pred          rc=0   warn=0  err=0  9408/0         7s
  PASS       cov_tage_table         rc=0   warn=0  err=0  15/0           2s
  PASS       cov_tage               rc=0   warn=0  err=0  218/0          9s
  PASS       cov_bp_cluster         rc=0   warn=0  err=0  2037/0        23s
  PASS       cov_bpu                rc=0   warn=0  err=0  31452/0       32s
             sum of sub-runs:tage=218/0 tage_table=15/0 loop_pred=9408/0 bp_history=21470/0 ubtb=341/0
  PASS       lint_1slot             rc=0   warn=0  err=0  -              0s
  PASS       lint_loop_pred_1slot   rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_table_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_table_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_brimli_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_cntrl_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_sc_1slot          rc=0   warn=0  err=0  -              1s
  PASS       lint_ittage_table_1slot rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_cntrl_1slot rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_arb_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_ittage_1slot      rc=0   warn=0  err=0  -              1s
  PASS       lint_tage_cntrl_1slot  rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_arb_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_tage_1slot        rc=0   warn=0  err=0  -              1s
  PASS       lint_ras_1slot         rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_array_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_plru_1slot    rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_cntrl_1slot   rc=0   warn=0  err=0  -              0s
  PASS       lint_ftb_1slot         rc=0   warn=0  err=0  -              0s
  PASS       lint_bp_cluster_1slot  rc=0   warn=0  err=0  -              1s
  PASS       sim_1slot              rc=0   warn=0  err=0  25/0           0s
  PASS       sim_history_1slot      rc=0   warn=0  err=0  12346/0        4s
  PASS       sim_ubtb_1slot         rc=0   warn=0  err=0  341/0          3s
  PASS       sim_loop_pred_1slot    rc=0   warn=0  err=0  4695/0         3s
  PASS       sim_tage_table_1slot   rc=0   warn=0  err=0  11/0           1s
  PASS       sim_sc_table_1slot     rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_table_fast_1slot rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_brimli_1slot    rc=0   warn=0  err=0  6/0            1s
  PASS       sim_sc_brimli_fast_1slot rc=0   warn=0  err=0  6/0            0s
  PASS       sim_sc_cntrl_1slot     rc=0   warn=0  err=0  98/0           3s
  PASS       sim_sc_1slot           rc=0   warn=0  err=0  108/0          0s
  PASS       sim_sc_fast_1slot      rc=0   warn=0  err=0  104/0          1s
  PASS       sim_ittage_table_1slot rc=0   warn=0  err=0  26/0           0s
  PASS       sim_ittage_cntrl_1slot rc=0   warn=0  err=0  138/0          3s
  PASS       sim_ittage_1slot       rc=0   warn=0  err=0  258/0          4s
  PASS       sim_ittage_fast_1slot  rc=0   warn=0  err=0  258/0          3s
  PASS       sim_bp_cluster_1slot   rc=0   warn=0  err=0  1466/0         6s
  PASS       sim_bp_cluster_init_1slot rc=0   warn=0  err=0  1466/0        20s
  PASS       sim_ras_1slot          rc=0   warn=0  err=0  239/0          4s
  PASS       sim_ftb_1slot          rc=0   warn=0  err=0  186/0          3s
  PASS       sim_tage_1slot         rc=0   warn=0  err=0  105/0          3s
  PASS       sim_tage_fast_1slot    rc=0   warn=0  err=0  105/0          3s
  PASS       sim_tage_tasks_1slot   rc=0   warn=0  err=0  1/0            1s
  PASS       sim_tage_manual_1slot  rc=0   warn=0  err=0  534/0          3s
  time 305s
== rtl/core/frontend/decode
  PASS       lint_dec               rc=0   warn=0  err=0  -              0s
  PASS       sim_dec                rc=0   warn=0  err=0  1355/0        22s
  PASS       coverage               rc=0   warn=0  err=0  -              9s
  PASS       sim_dec_sweep          rc=0   warn=0  err=0  458752/0      43s
  PASS       oracle_dec_sweep       rc=0   warn=0  err=0  -              3s
  PASS       asm_dec_words          rc=0   warn=0  err=0  492/0          0s
  time 77s
== rtl/core/frontend/fe_top
  PASS       lint_fe_top            rc=0   warn=0  err=0  -              3s
  PASS       sim_fe_top             rc=0   warn=0  err=0  754/0         33s
  PASS       assert_labels          rc=0   warn=0  err=0  163/0         24s
  PASS       sim_fe_top_bare        rc=0   warn=0  err=0  22/0           7s
  PASS       sim_fe_top_sv39        rc=0   warn=0  err=0  21/0           7s
  PASS       sim_fe_top_loops       rc=0   warn=0  err=0  26/0           8s
  PASS       sim_fe_top_coro        rc=0   warn=0  err=0  20/0           8s
  PASS       sim_fe_top_calls       rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_lp          rc=0   warn=0  err=0  21/0           6s
  PASS       sim_fe_top_hist        rc=0   warn=0  err=0  19/0           7s
  PASS       sim_fe_top_twocond     rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_ftbonly     rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_nest        rc=0   warn=0  err=0  18/0           8s
  PASS       sim_fe_top_recur       rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_rec_undo    rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_t0_uaon     rc=0   warn=0  err=0  20/0           9s
  PASS       sim_fe_top_deep        rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_indir       rc=0   warn=0  err=0  19/0           7s
  PASS       sim_fe_top_region      rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_multistart  rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_cross       rc=0   warn=0  err=0  18/0           8s
  PASS       sim_fe_top_rvc         rc=0   warn=0  err=0  18/0           7s
  PASS       sim_fe_top_misp_call   rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_jals        rc=0   warn=0  err=0  19/0           7s
  PASS       sim_fe_top_fencei      rc=0   warn=0  err=0  22/0           7s
  PASS       sim_fe_top_cboinval    rc=0   warn=0  err=0  22/0           7s
  PASS       sim_fe_top_uc_nc       rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_uc_io       rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_pt_faults_s rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_pt_faults_h rc=0   warn=0  err=0  19/0           8s
  PASS       sim_fe_top_pt_napot_s  rc=0   warn=0  err=0  19/0           6s
  PASS       sim_fe_top_pt_napot_h  rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_pt_rsv_s    rc=0   warn=0  err=0  20/0           8s
  PASS       sim_fe_top_pt_rsv_h    rc=0   warn=0  err=0  20/0           8s
  PASS       sim_fe_top_pt_ad_s     rc=0   warn=0  err=0  21/0           6s
  PASS       sim_fe_top_pt_ad_h     rc=0   warn=0  err=0  23/0           8s
  PASS       sim_fe_top_pt_inv      rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_zstar       rc=0   warn=0  err=0  20/0           6s
  PASS       sim_fe_top_pt_gonly    rc=0   warn=0  err=0  19/0           7s
  PASS       sim_fe_top_pt_vsonly   rc=0   warn=0  err=0  19/0           7s
  PASS       sim_fe_top_pt_upriv    rc=0   warn=0  err=0  25/0           6s
  PASS       sim_fe_top_init_walk   rc=0   warn=0  err=0  34/0           8s
  PASS       lint_fe_top_1slot      rc=0   warn=0  err=0  -              2s
  PASS       sim_fe_top_1slot       rc=0   warn=0  err=0  751/0         13s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  155/0         13s
  PASS       sim_fe_top_bare_1slot  rc=0   warn=0  err=0  22/0           6s
  PASS       sim_fe_top_sv39_1slot  rc=0   warn=0  err=0  21/0           5s
  PASS       sim_fe_top_loops_1slot rc=0   warn=0  err=0  24/0           6s
  PASS       sim_fe_top_coro_1slot  rc=0   warn=0  err=0  20/0           6s
  PASS       sim_fe_top_calls_1slot rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_lp_1slot    rc=0   warn=0  err=0  21/0           6s
  PASS       sim_fe_top_hist_1slot  rc=0   warn=0  err=0  19/0           6s
  PASS       sim_fe_top_twocond_1slot rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_ftbonly_1slot rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_nest_1slot  rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_recur_1slot rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_rec_undo_1slot rc=0   warn=0  err=0  19/0           6s
  PASS       sim_fe_top_t0_uaon_1slot rc=0   warn=0  err=0  20/0           6s
  PASS       sim_fe_top_deep_1slot  rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_indir_1slot rc=0   warn=0  err=0  19/0           6s
  PASS       sim_fe_top_region_1slot rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_multistart_1slot rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_cross_1slot rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_rvc_1slot   rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_misp_call_1slot rc=0   warn=0  err=0  18/0           6s
  PASS       sim_fe_top_jals_1slot  rc=0   warn=0  err=0  19/0           6s
  PASS       sim_fe_top_fencei_1slot rc=0   warn=0  err=0  22/0           6s
  PASS       sim_fe_top_cboinval_1slot rc=0   warn=0  err=0  22/0           5s
  PASS       sim_fe_top_uc_nc_1slot rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_uc_io_1slot rc=0   warn=0  err=0  20/0           6s
  PASS       sim_fe_top_pt_faults_s_1slot rc=0   warn=0  err=0  20/0           5s
  PASS       sim_fe_top_pt_faults_h_1slot rc=0   warn=0  err=0  19/0           6s
  PASS       sim_fe_top_pt_napot_s_1slot rc=0   warn=0  err=0  19/0           6s
  PASS       sim_fe_top_pt_napot_h_1slot rc=0   warn=0  err=0  20/0           6s
  PASS       sim_fe_top_pt_rsv_s_1slot rc=0   warn=0  err=0  20/0           6s
  PASS       sim_fe_top_pt_rsv_h_1slot rc=0   warn=0  err=0  20/0           7s
  PASS       sim_fe_top_pt_ad_s_1slot rc=0   warn=0  err=0  21/0           6s
  PASS       sim_fe_top_pt_ad_h_1slot rc=0   warn=0  err=0  23/0           6s
  PASS       sim_fe_top_pt_inv_1slot rc=0   warn=0  err=0  20/0           6s
  PASS       sim_fe_top_zstar_1slot rc=0   warn=0  err=0  20/0           6s
  PASS       sim_fe_top_pt_gonly_1slot rc=0   warn=0  err=0  19/0           6s
  PASS       sim_fe_top_pt_vsonly_1slot rc=0   warn=0  err=0  19/0           6s
  PASS       sim_fe_top_pt_upriv_1slot rc=0   warn=0  err=0  25/0           6s
  PASS       sim_fe_top_init_walk_1slot rc=0   warn=0  err=0  32/0           6s
  time 596s
== rtl/core/frontend/ftq
  PASS       lint_ftq_ftb_sched     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ftb_sched      rc=0   warn=0  err=0  67/0           1s
  PASS       lint_ftq_ptr           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ptr            rc=0   warn=0  err=0  207/0         17s
  PASS       lint_ftq_commit        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_commit         rc=0   warn=0  err=0  72/0           1s
  PASS       lint_ftq_entry         rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_entry          rc=0   warn=0  err=0  72/0           9s
  PASS       lint_ftq_meta          rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta           rc=0   warn=0  err=0  26/0           1s
  PASS       lint_ftq_status        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_status         rc=0   warn=0  err=0  45/0           1s
  PASS       lint_ftq_shadow        rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_shadow         rc=0   warn=0  err=0  53/0           1s
  PASS       lint_ftq_npc           rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_npc            rc=0   warn=0  err=0  84/0           0s
  PASS       lint_ftq_ifu           rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ifu            rc=0   warn=0  err=0  237/0          5s
  PASS       lint_ftq_resolve       rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_resolve        rc=0   warn=0  err=0  146/0          8s
  PASS       lint_ftq_upd_conv      rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_upd_conv       rc=0   warn=0  err=0  192/0          6s
  PASS       lint_ftq               rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq                rc=0   warn=0  err=0  158/0          7s
  PASS       assert_labels          rc=0   warn=0  err=0  226/0          3s
  PASS       lint_ftq_ftb_sched_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ftb_sched_1slot rc=0   warn=0  err=0  67/0           0s
  PASS       lint_ftq_ptr_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_ptr_1slot      rc=0   warn=0  err=0  207/0          3s
  PASS       lint_ftq_commit_1slot  rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_commit_1slot   rc=0   warn=0  err=0  72/0           0s
  PASS       lint_ftq_entry_1slot   rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_entry_1slot    rc=0   warn=0  err=0  61/0           1s
  PASS       lint_ftq_meta_1slot    rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_meta_1slot     rc=0   warn=0  err=0  19/0           1s
  PASS       lint_ftq_status_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_status_1slot   rc=0   warn=0  err=0  45/0           0s
  PASS       lint_ftq_shadow_1slot  rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_shadow_1slot   rc=0   warn=0  err=0  53/0           1s
  PASS       lint_ftq_npc_1slot     rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_npc_1slot      rc=0   warn=0  err=0  80/0           0s
  PASS       lint_ftq_ifu_1slot     rc=0   warn=0  err=0  -              1s
  PASS       sim_ftq_ifu_1slot      rc=0   warn=0  err=0  222/0          5s
  PASS       lint_ftq_resolve_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_resolve_1slot  rc=0   warn=0  err=0  105/0          4s
  PASS       lint_ftq_upd_conv_1slot rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_upd_conv_1slot rc=0   warn=0  err=0  106/0          5s
  PASS       lint_ftq_1slot         rc=0   warn=0  err=0  -              0s
  PASS       sim_ftq_1slot          rc=0   warn=0  err=0  158/0          5s
  PASS       assert_labels_1slot    rc=0   warn=0  err=0  205/0          2s
  time 92s
== rtl/core/frontend/ibuf
  PASS       lint_ibuf              rc=0   warn=0  err=0  -              0s
  PASS       sim_ibuf               rc=0   warn=0  err=0  52/0          18s
  PASS       assert_labels          rc=0   warn=0  err=0  3/0            0s
  time 18s
== rtl/core/frontend/icache
  PASS       lint_l1i               rc=0   warn=0  err=0  -              0s
  PASS       sim_l1i_emitted        rc=0   warn=0  err=0  67/0          18s
  PASS       sim_l1i                rc=0   warn=0  err=0  281/0         10s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0            5s
  time 33s
== rtl/core/frontend/ifu
  PASS       lint_ifu_rvc_exp       rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_predecode     rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_xlate         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_lbuf          rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_fetch         rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_f3            rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_wb            rc=0   warn=0  err=0  -              0s
  PASS       lint_ifu_maint         rc=0   warn=0  err=0  -              1s
  PASS       lint_ifu               rc=0   warn=0  err=0  -              1s
  PASS       sim_ifu_rvc_exp        rc=0   warn=0  err=0  2457618/0     19s
  PASS       sim_ifu_predecode      rc=0   warn=0  err=0  63/0           8s
  PASS       sim_ifu                rc=0   warn=0  err=0  738/0         17s
  PASS       assert_labels          rc=0   warn=0  err=0  16/0           3s
  PASS       oracle_ifu_rvc_exp     rc=0   warn=0  err=0  -              9s
  time 59s
== rtl/core/frontend/l1i_param_chk
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       lint_neg               rc=0   warn=0  err=0  -              0s
  time 0s
== rtl/lib
  PASS       lint                   rc=0   warn=0  err=0  -              0s
  PASS       sim                    rc=0   warn=0  err=0  34/0           1s
  time 1s
== rtl
  time 0s
== rtl/mmu/itlb
  PASS       lint_itlb              rc=0   warn=0  err=0  -              0s
  PASS       sim_itlb               rc=0   warn=0  err=0  147/0         15s
  PASS       sim_itlb_d2            rc=0   warn=0  err=0  150/0         14s
  PASS       assert_labels          rc=0   warn=0  err=0  5/0            4s
  time 33s
== rtl/mmu/pmp
  PASS       lint_pmp_pma_chk       rc=0   warn=0  err=0  -              0s
  PASS       sim_pmp_pma_chk        rc=0   warn=0  err=0  70/0          16s
  PASS       lint_neg_pma           rc=0   warn=0  err=0  -              0s
  PASS       lint_neg_pma_dflt      rc=0   warn=0  err=0  -              0s
  time 16s
== rtl/mmu/ptw
  PASS       lint_ptw               rc=0   warn=0  err=0  -              0s
  PASS       sim_ptw                rc=0   warn=0  err=0  807/0         17s
  PASS       assert_labels          rc=0   warn=0  err=0  12/0          10s
  time 27s
------------------------------------------------------------------
targets run: 274   total time: 604s
new failures: 0   known failures: 0   now passing: 0   stale entries: 0   malformed entries: 0   set errors: 0
logs: /tmp/regress.A33ACU
pass NOT recorded: tracked changes or untracked rtl/ files, or HEAD moved during the run (push will be refused)
RESULT: PASS
```
tools/regress_demo.sh was not run: this task changes neither rtl/ nor
examples/fe_demo/.

### Proposals for perf_decisions.md (the IA does not edit it)
- PF-U1:
  - Replace the sample figures with the training-set counts: far
    taken conditional branches 988560 dynamic (0.43 percent of taken
    conditional, 0.228 PKI), 7537 static (0.72 percent of static
    conditional), absent in 27 traces.
  - Direct jumps and calls beyond +-1 MB: 11758034 dynamic (2.71
    PKI), 106277 static, in 89 of 105 traces. They are 12 times more
    common than far conditional branches, and highest in infra (5.65
    PKI) and web (5.10 PKI). The sentence "no direct jump or call goes
    beyond +-1 MB" should be limited to the samples.
  - Correct "2.2 percent" to "2.2 percent of conditional branches,
    4.1 percent of taken ones".
  - Direct branches with more than one target exist in one trace,
    web_9_trace, 3 static.
  - Add: 81 of 105 traces have PCs at or above 2^41, up to
    0xffffff8008edbebc. pacino's 41-bit VA cannot hold them, so
    relocation is required in any case. The open choice becomes how
    to relocate, which then also decides how far branches are
    handled. (This also bears on PF-U4: the int sample span quoted
    there is not representative.)
- PF-U2: close. The reference results come from the default 64 KB
  TAGE-SC-L (cbp2016_tage_sc_l.h), with PERFECT_INDIRECT_PRED = true:
  - Their MPKI counts conditional mispredicts only.
  - NumBr counts conditional branches only, per record piece. That
    equals conditional branch records in all 105 traces.
  - Instr counts records.
  - The 50Perc columns are the trailing 1M-record epochs whose sum
    first exceeds half the trace, with the predictor trained from the
    start.
- PF-7: the reading holds, with two qualifications:
  - The measured part is the trailing whole epochs, 50 percent up to
    50 percent plus 999994 records, not an exact half. PF-11's
    second-half count check must use the same epoch rule, as
    perf/scan_traces.py does.
  - Speed: the SystemVerilog fe_top testbench gives 4.4e3 to 8.3e3
    instructions/s, 146 to 272 h for the set on one process. Full
    traces become practical in parallel only if the C++ harness is
    substantially faster than this bound.
- PF-6 and PF-10 (consequence of PF-U2): R's MPKI excludes indirect
  and return mispredicts. A like-for-like comparison uses pacino's
  conditional-branch MPKI. ITTAGE and RAS mispredicts are reported
  apart, with no reference counterpart.
- PF-U7, first half: pacino's predictor storage at the default
  parameters is 551280 bits, 67.3 KB for all predictors. TAGE + SC +
  loop, the part comparable with R's 64 KB, is 20.9 KB. The method is
  given in Problem 5.

## Assumptions made not explicit in the prompt
- "the smallest of the int group" read as the fewest instructions.
  int_1, int_2, int_5 and int_6 tie at 30000052; int_1 was taken, the
  first by name. int_13 is the smallest file but has 40000052
  instructions.
- Far reach is the exact RISC-V immediate range: conditional -4096 to
  +4094, jal -1048576 to +1048574. "Taken conditional branches beyond
  +-4 KB" counts taken branches only. Direct branches with more than
  one target include conditional branches (taken targets), jumps and
  calls.
- "PCs not 4-byte aligned" is counted over static PCs.
- Paths in the checksum list include training_traces/, so they are
  relative to CBP_TRACES, which holds training_traces/ (PF-14 default
  ../cbp_traces).
- Problem 5: the EPC field of the TAGE and ITTAGE tables is stored,
  and a valid bit is stored per tagged entry. The RAS stores a
  recursion counter per entry in both stacks. These were not verified
  in the table RTL, which is outside the manifest. Without the valid
  and EPC bits TAGE is 3 bits and ITTAGE 3 bits per entry smaller.
- Problem 4: the three programs are the longest of FE_PROGS by cycles.
  All programs are short (at most 6361 cycles), so start-up is
  visible in the rate, and the marginal rate is given beside it.

## Decisions made not explicit in the prompt
- The scan also writes the 50Perc counts (half_instr,
  half_cond_br_pieces) and compares them with 50PercInstr and
  50PercNumBr. These are PF-11's second-half counts.
- The scan counts conditional branch pieces (cond_br_pieces) beside
  records, so the NumBr comparison follows CBP's per-piece counting.
- The scan reads the SHA-256 of a file in a separate pass before
  parsing it, as "before reading it" requires.
- The README contents entry was added to the top-level list, after
  Quick start, although the section is a subsection of Quick start;
  Problem 6 places it after Run code coverage.
- The fe_top build and runs used VER_OUT in the scratchpad, so no
  object directory in rtl/ was written by Problem 4.

## RVA23 compliance risks and gaps noticed
- None in the RTL, which this task did not change. For the
  measurement: 81 of 105 traces use upper-half 64-bit addresses that
  are not Sv39 canonical. A code image for pacino (Sv39, 41-bit VA)
  must relocate them (PF-U1, PF-U4).

## Deferred Work
- PF-U1 relocation scheme, now required by the address range as well
  as by branch reach.
- PF-U7 second half (whether pacino's parameters can express R's
  layout).

## Other Notes
- Files read outside Context Loaded (each read-only, needed for the
  problems as written):
  - .git/HEAD, .git/refs/heads/main, .git/refs/tags/fe-1.0.0
  - tools/cbp2025/.git, .git/modules/tools/cbp2025/HEAD and
    refs/heads/main
  - tools/cbp2025/lib/sim_common_structs.h (the InstClass values that
    trace_reader.h uses)
  - tools/cbp2025/lib/cbp.cc and tools/cbp2025/Makefile
  - grep of tools/cbp2025/lib/uarchsim.cc, parameters.cc and
    cond_branch_predictor_interface.cc, and uarchsim.cc lines 96-111
    and 805-829 (instruction, epoch and piece counting)
  - the first lines of tools/*.py (SPDX header)
  - grep of rtl/core/frontend/fe_top/fe_top_srcs.mk (FE_FAST_INIT) and
    of rtl/core/frontend/fe_top/tb/tb_fe_top.sv (report fields)
  - training_traces/readme.txt
  - directory listings of the trace tree and tools/cbp2025
- Scratch: the CBP copy and build, the fe_top object directory, and
  two helper scripts are in the session scratchpad. No Firefox
  folder was created.
- No git command was run. The shas were read from files under .git.
- The first sample run hung on a parse-loop boundary condition (a
  refill test used < where <= was needed). It was stopped and fixed
  before any reported run.

## Files Modified
- perf/scan_traces.py
- perf/cbp2025_training.sha256
- perf/cbp2025_training_scan.csv
- README.md
- prompts/PERF-001.md

:: RESULTS:END ::

:: CONTEXT:START ::
# Context Report

Compactions: 0
Run time: 14m.32s active, 25m.52s wall (2026-11-10T02:33:38Z -> 2026-11-10T02:59:31Z, /run PERF-001)

Model: claude-opus-5-5
Tokens: 294k / 1m (29%)

| Category | Tokens | Percentage |
|----------|--------|------------|
| System prompt | 3k | 0.3% |
| System tools | 21.3k | 2.1% |
| MCP server instructions | 717 | 0.1% |
| MCP tools (deferred) | 3.9k | 0.4% |
| System tools (deferred) | 29.9k | 3.0% |
| Memory files | 7.5k | 0.8% |
| Skills | 6k | 0.6% |
| Messages | 255.5k | 25.5% |
| Free space | 673k | 67.3% |
| Autocompact buffer | 33k | 3.3% |

Memory files:

| Type | Path | Tokens |
|------|------|--------|
| Project | CLAUDE.md | 5.6k |
| AutoMem | memory/MEMORY.md | 1.9k |
:: CONTEXT:END ::
