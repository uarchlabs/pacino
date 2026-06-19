<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
=============================================================
# Task Header
=============================================================
:: HEADER:START ::
| Field       | Value                                        |   |
|-------------|----------------------------------------------|---|
| Task ID     | TOOLS-002                                    |   |
| Date        | 2026-XX-XX                                   |   |
| Module      | tools                                        |   |
| Run time    | 1m.40s                                       |   |
| Ctx%        | not recorded                                 |   |
| Model       | Sonnet 4.6 normal                            |   |
| Resume sha  | 5f754086-690f-45ad-a5fa-7dc6f109e3ac         |   |
| PA session  | 001 | |

Task:   [ ] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [x] testbench       [ ] verification
Mode:   [x] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview

Prove spike-dasm can be used as an oracle regression tool for
ISA implementation verification

2026-05-30: This task file has been retro-fitted with the 
now standard section markers.
:: HEADER:END :
=============================================================
:: DISCUSSION:START ::

# Results Discussion

## Claude.code Console Output
  Results                                                                       

  make spike_oracle - Generated 50 rows, matching the 50 disassembly lines in   
  rva23_insn_ref.disasm.                                                        

  make spike_check - Exit code: 1 (failure)                                     

  Summary: total=50 decoded=49 unknown=1 skipped=0 errors=0                     
   
  ---                                                                           
  UNKNOWN result                                                             

  ┌─────────┬──────────┬─────────────────────┐
  │ address │ encoding │    mnemonic_hint    │                                  
  ├─────────┼──────────┼─────────────────────┤
  │ 0x0068  │ 840140f3 │ .insn 4, 0x840140f3 │                                  
  └─────────┴──────────┴─────────────────────┘                               

## My Assessment
Nothing required
## Claude.ai Assessment

### What Claude got right
- gen_spike_oracle.py and check_spike_decode.py delivered on first run.
- skip mechanism works - skipped rows run and report but do not fail.
- Makefile integration clean, existing targets untouched.
- 49/50 instructions decoded confirming ISA string correct for all
  extensions except Zimop.

### What Claude got wrong or missed
- Suggested rv64gc ISA string during debug despite being told spike
  does not accept the G shortcut. Careless error.
- Zcmop encoding failure not caught until after results reported.
  Should have been flagged as skip=1 in the prompt alongside Zimop.


## Follow-on Actions
- [ ] Determine correct inline asm for mop.r.0 (Zimop) and c.mop.1 (Zcmop)
- [ ] Update rva23_insn_ref.c with correct encodings for both
- [ ] Set skip=1 for 0x0068 and 0x006c in spike_oracle.csv
- [ ] Add zimop and zcmop to ISA string in check_spike_decode.py
- [ ] Re-run make spike_check after CSV edits, confirm exit 0
- [ ] Begin TOOLS-003 decoder regression against spike oracle
## CLAUDE.md Updates
2026-03-24 - spike-dasm ISA string confirmed for RVA23. Zimop spike
disassembler gap documented. Console only output rule established
for all Claude Code prompts.
## Other Planning File Updates
Nothing required
:: DISCUSSION:END ::
=============================================================
# Claude.code Prompt
=============================================================
:: PROMPT:START ::

## Task ID
TOOLS-002

## Hypothesis

spike-dasm with the full RVA23 ISA string can serve as a ground-truth
oracle to verify that every encoding produced by the RVA23 compiler
toolchain is recognized as a valid instruction (not "unknown"). This
provides a third independent verification method for the decoder track,
complementing the existing directed testbenches.

## Scope

- Input:  tools/rva23_insn_ref.disasm (objdump output, already on disk)
- Oracle: tools/spike/install/bin/spike-dasm
- New files to create:
    tools/check_spike_decode.py
    tools/spike_oracle.csv  (generated, not hand-authored)
- Modified file:
    tools/Makefile           (add spike_oracle, spike_check, spike_all)

Do not modify any RTL files. Do not modify any existing testbenches.
Do not modify rva23_insn_ref.c or rva23_ext_test.c.
Do not write results to any .md file. Report all results to the console only.

## ISA String

The spike-dasm ISA string to use in all invocations is exactly:

rv64imafdc_v_h_sscofpmf_sstc_svinval_svnapot_svpbmt_zawrs_zba_zbb_zbc\
_zbs_zfa_zfh_zfhmin_zicbom_zicboz_zicntr_zifencei_zicond_zihintntl\
_zihintpause_zihpm_zkt_zk_zkn_zknd_zkne_zknh_zbkb_zbkc_zbkx_zicbop\
_zcb_zvkb

Pass this as: spike-dasm --isa=<string>

The correct input format for spike-dasm is the DASM() token form:
  echo "DASM(00000013)" | spike-dasm --isa=<string>
Note: hex digits only, no 0x prefix, inside DASM().

---

## Deliverables
### Deliverable 1: tools/check_spike_decode.py

#### Purpose

Read tools/spike_oracle.csv and for each row pipe the encoding through
spike-dasm. Classify each result. Report a summary. Exit non-zero if
any non-skipped instruction returns UNKNOWN.

#### CSV format

The CSV file has a header row and these columns (in order):

  address, encoding, mnemonic_hint, skip

- address:       hex string, e.g. 0x0000 (from objdump, offset in .text)
- encoding:      hex string, e.g. 023100b3 (raw bytes, no 0x prefix)
- mnemonic_hint: string label from objdump disassembly, for reporting
- skip:          integer, 0 = include in pass/fail, 1 = exclude from
                 pass/fail (still runs, still reported, never fails)

#### Algorithm

For each row in the CSV:
1. Format the encoding as DASM(<encoding>) with no 0x prefix.
2. Pipe through spike-dasm with the ISA string above.
3. Capture stdout. Strip whitespace.
4. Classify:
   - DECODED:  output is not empty and does not contain "unknown"
   - UNKNOWN:  output contains "unknown"
   - ERROR:    spike-dasm returned non-zero exit code
5. Record result.

After all rows:
- Print a formatted table: address | encoding | mnemonic_hint |
  spike_output | result | skip_flag
- Print a summary: total / decoded / unknown / skipped / errors
- If any non-skipped row has result UNKNOWN or ERROR: exit 1
- Otherwise: exit 0

#### Implementation notes

- spike-dasm binary path: tools/spike/install/bin/spike-dasm
  Use a path relative to the script location so it works from any
  working directory. Resolve relative to the script's own directory.
- CSV path: tools/spike_oracle.csv, same resolution rule.
- Use subprocess, not os.system.
- Do not hardcode absolute paths.
- Python 3, no dependencies outside stdlib.
- 80 column line width.
- 2 spaces indent.
- ASCII only in all comments.

---

### Deliverable 2: tools/spike_oracle.csv (generated by make target)

This file is generated by parsing tools/rva23_insn_ref.disasm.
It is not hand-authored. See Makefile target spike_oracle below.

The parser must:
1. Find the "Disassembly of section .text:" line.
2. Skip the function label line (the <rva23s64_insn_ref>: line).
3. For each subsequent disassembly line of the form:
     <hex_offset>: <raw_bytes>    <mnemonic...>
   extract:
   - address:       the hex offset field, zero-padded to 4 digits,
                    formatted as 0x%04x
   - encoding:      the raw_bytes field (may be 2 or 4 hex chars for
                    compressed vs normal instructions)
   - mnemonic_hint: everything after the raw bytes, stripped of leading
                    whitespace, truncated to 32 characters max
   - skip:          always 0 in generated output

4. Write the CSV with header:
     address,encoding,mnemonic_hint,skip

Known edge cases in this disasm that the parser must handle:
- Compressed (16-bit) instructions: raw_bytes field is 4 hex chars,
  e.g. "1141". Include these, do not skip.
- The .insn raw encoding line (Zimop): raw_bytes is 8 hex chars,
  e.g. "840140f3". Include, skip=0.
- The c.lui line (Zcmop encoded as c.lui by assembler): include, skip=0.
- Lines with no mnemonic (pure data): skip entirely.

The parser is implemented as a Python script:
  tools/gen_spike_oracle.py

This script is called by the spike_oracle make target. It reads
tools/rva23_insn_ref.disasm and writes tools/spike_oracle.csv.

---

### Deliverable 3: Makefile additions to tools/Makefile

Add to the existing tools/Makefile. Do not remove or modify any
existing targets or variables. Add after the existing targets:

  SPIKE_DASM=spike/install/bin/spike-dasm

  .PHONY: spike_oracle spike_check spike_all

  spike_oracle:
          python3 gen_spike_oracle.py

  spike_check: spike_oracle.csv
          python3 check_spike_decode.py

  spike_all:
          $(MAKE) spike_oracle
          $(MAKE) spike_check

Note: spike_check depends on spike_oracle.csv existing but does not
auto-run spike_oracle. This allows Jeff to hand-edit skip flags in
the CSV and re-run spike_check without regenerating the CSV.

Add spike_oracle.csv to the clean target.

---

## Verification of this tooling

After implementing, run:

  cd tools
  make spike_oracle

Inspect the generated spike_oracle.csv. Verify row count matches
the number of disassembly lines in rva23_insn_ref.disasm (including
prologue/epilogue, excluding the function label line and section
header lines).

Then run:

  make spike_check

Report the full table output and summary line back to claude.ai.
Report the exit code. Report any UNKNOWN or ERROR results, including
the encoding and mnemonic_hint for each.

Do not attempt to fix UNKNOWN results during this session.
Do not modify spike_oracle.csv manually during this session.
Report results as-is.

:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::

### Claude Text Output

  ---                                                                           
  Results                                                                       
                                                                                
  make spike_oracle - Generated 50 rows, matching the 50 disassembly lines in   
  rva23_insn_ref.disasm.                                                        
                                                                                
  make spike_check - Exit code: 1 (failure)                                     
                                                                             
  Summary: total=50 decoded=49 unknown=1 skipped=0 errors=0                     
   
  ---                                                                           
  UNKNOWN result                                                             
                
  ┌─────────┬──────────┬─────────────────────┐
  │ address │ encoding │    mnemonic_hint    │                                  
  ├─────────┼──────────┼─────────────────────┤
  │ 0x0068  │ 840140f3 │ .insn 4, 0x840140f3 │                                  
  └─────────┴──────────┴─────────────────────┘                               
                                                                                
  This is the Zimop raw encoding line — assembled with .insn directive as a raw 
  32-bit encoding. spike-dasm returns unknown for it. This is the only failure. 
                                                                                
  ---                                                                        
  Per the spec: no fix attempted, no manual CSV edits made, results reported
  as-is. The 49 other instructions — including all compressed, vector, crypto,  
  hypervisor, Zicbo, Zfh, Zawrs, Zicond, Svinval, Sstc, and Smstateen
  instructions — all decode successfully.   

### Experiment Header

| Field          | Value |
|----------------|-------|
| Task ID  | TOOLS-002 |
| Date           | 2026-03-24 |
| Module         | tools/ |
| Run time       | 1m.40s |
| Session Link   | claude --resume 5f754086-690f-45ad-a5fa-7dc6f109e3ac |

---
### Output Quality
| Criteria                    | Rating (1-5) | Notes |
|-----------------------------|--------------|-------|
| RVA23 compliance            | 4 | 49/50 verified. Zimop is spike gap not compliance failure. |
| Interface correctness       | 5 | CSV schema, make targets, script interfaces all clean. |
| RTL quality / readability   | N/A | No RTL this experiment. |
| Testbench quality           | 4 | Coarse check appropriate for this stage. skip mechanism works. |
| Verilator compatibility     | N/A | No RTL this experiment. |
| Assumptions stated clearly  | 4 | Zimop/Zcmop edge cases flagged and handled. |

---
### What Claude got right
- gen_spike_oracle.py and check_spike_decode.py delivered on first run.
- skip mechanism works - skipped rows run and report but do not fail.
- Makefile integration clean, existing targets untouched.
- 49/50 instructions decoded confirming ISA string correct for all
  extensions except Zimop.

---
### What Claude got wrong or missed
- Suggested rv64gc ISA string during debug despite being told spike
  does not accept the G shortcut. Careless error.
- Zcmop encoding failure not caught until after results reported.
  Should have been flagged as skip=1 in the prompt alongside Zimop.

---
### RVA23 compliance flags raised by Claude
- Zimop mop.r.0: spike-dasm returns unknown even with zimop in ISA
  string. Spike disassembler gap confirmed by source inspection.
  Not a decoder compliance issue.
- Zcmop: assembler encoded .insn 0x6085 as c.lui x1,1 - incorrect
  encoding. Correct inline asm for both zimop and zcmop is
  unresolved debt.

---
### Interface decisions made - downstream impact
None. Tools experiment only.

---
### Prompt effectiveness observations
Prompt produced the intended experiment cleanly. Split between
gen_spike_oracle.py and check_spike_decode.py was the right call -
allowed manual skip edits without CSV regeneration. Console only
no file output rule should be added to all future Claude Code
prompts as a standing instruction.

---
### Follow-on actions
- [ ] Determine correct inline asm for mop.r.0 (Zimop) and c.mop.1 (Zcmop)
- [ ] Update rva23_insn_ref.c with correct encodings for both
- [ ] Set skip=1 for 0x0068 and 0x006c in spike_oracle.csv
- [ ] Add zimop and zcmop to ISA string in check_spike_decode.py
- [ ] Re-run make spike_check after CSV edits, confirm exit 0
- [ ] Begin TOOLS-003 decoder regression against spike oracle

---
### Graduated to CLAUDE.md
2026-03-24 - spike-dasm ISA string confirmed for RVA23. Zimop spike
disassembler gap documented. Console only output rule established
for all Claude Code prompts.

## Files Modified
Not captured

:: RESULTS:END ::
