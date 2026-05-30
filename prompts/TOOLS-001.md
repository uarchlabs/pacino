=============================================================
# Task Header
=============================================================
:: HEADER:START ::
| Field       | Value                                        |   |
|-------------|----------------------------------------------|---|
| Task ID     | TOOLS-001                                    |   |
| Date        | 2026-03-22                                   |   |
| Module      | check_rva23_coverage.py                      |   |
| Run time    | 5m.50s                                       |   |
| Ctx%        | not recorded                                 |   |
| Model       | Sonnet 4.6 normal                            |   |
| Resume sha  | 4d86f334-bd1f-4bc9-b278-db243f0e4a92 | |

Task:   [ ] experiment  [x] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Status: [ ] in-progress [x] complete        [ ] abandoned

# Overview of task

Fix check_rva23_coverage.py shared encoding false negatives

2026-05-30: This task file has been retro-fitted with the 
now standard section markers.
:: HEADER:END :
=============================================================
:: DISCUSSION:START ::

# Results Discussion

## Claude.code Console Output

  Changes made — tools/check_rva23_coverage.py only:

  1. Added COVERED_STAR = 'covered*' status constant.
  2. Added KNOWN_SHARED_ENCODINGS table with comments explaining purpose,
  format, how to extend, and TOOLS-001 reference. Entry: c.sext.w -> C.ADDIW
  (shared encoding, imm=0 case).
  3. Added KNOWN_OPCODES_FILE_GAPS table with same comment structure. Entry:
  c.zext.w -> ADD.UW rd,rd,x0 (absent from rv_zcb; safety net, already covered
  via rv64_zcb).
  4. Added _check_exceptions() function that probes both tables after a MISSING
  classification.
  5. Modified classification loop to call _check_exceptions() for any MISSING
  result and populate covered_star_list.
  6. Updated counts and ext_results dict to track covered_star.
  7. Added COVERED*: per-instruction lines in the per-extension report.
  8. Updated SUMMARY to split covered count into direct match vs exception
  table.

  Coverage results:

  ┌────────────┬───────────────┬────────────┐
  │ Extension  │    Before     │   After    │
  ├────────────┼───────────────┼────────────┤
  │ Zcb        │ 12/13 PARTIAL │ 13/13 FULL │
  ├────────────┼───────────────┼────────────┤
  │ All others │ unchanged     │ unchanged  │
  └────────────┴───────────────┴────────────┘

## My Assessment
Nothing required
## Claude.ai Assessment
False fails were corrected.
## Follow-on Actions
Nothing required
## CLAUDE.md Updates
Nothing required
## Other Planning File Updates
Nothing required
:: DISCUSSION:END ::
=============================================================
# Claude.code Prompt
=============================================================
:: PROMPT:START ::

## Task ID
TOOLS-001

## Hypothesis
The coverage script can be updated to handle known shared encodings
without changing its core string-matching approach. A known-exceptions
table mapping instruction mnemonics to their shared encoding equivalents
will eliminate false negatives while remaining easy to extend as new
shared encodings are discovered.

---

## Background
DECODE-003 identified that check_rva23_coverage.py reports Zcb as 12/13
because c.sext.w has no label in rvc_expander.sv. The instruction is
correctly handled via the shared C.ADDIW path (Q1/3'b001, rd!=0, imm=0).
The script has no mechanism to handle this case.

A second known gap in the tools/riscv-opcodes/extensions/rv_zcb file was
also found - c.zext.w is absent from the tools file but is present in the
published Zcb spec and correctly implemented. The script needs to handle
this case too.

## Specific Requirements

1. Read tools/check_rva23_coverage.py in full before making any changes.
   Understand the current matching approach completely.

2. Add a KNOWN_SHARED_ENCODINGS table near the top of the script:
   - Format: dict mapping missing mnemonic to the RTL label that
     handles it
   - When a mnemonic is not found by string match, check this table
   - If the equivalent label IS found in RTL, mark as covered with
     a note: covered via shared encoding <label>
   - Example entry:
       c.sext.w  -> C.ADDIW  (shared encoding, imm=0 case)

3. Add a KNOWN_OPCODES_FILE_GAPS table near the top of the script:
   - Format: dict mapping mnemonic to its expansion and source
   - These are instructions absent from riscv-opcodes files but
     present in the ratified spec and correctly implemented
   - Mark these as covered with a note: covered per spec, absent
     from riscv-opcodes tools file
   - Example entry:
       c.zext.w  -> ADD.UW rd,rd,x0  (absent from rv_zcb tools file)

4. Both tables must have a comment block explaining:
   - Why the table exists
   - How to add new entries
   - Reference to the experiment that identified each entry

5. Re-run the script after changes and confirm:
   - Zcb reports 13/13
   - No other extension coverage numbers change
   - Total coverage numbers update correctly

6. The script must still run with standard Python 3, no extra packages.
   ASCII only in all output - no Unicode characters.

---

## Constraints
- Changes confined to tools/check_rva23_coverage.py only
- Do not change the core string matching approach
- Both tables must be easy to extend - clear format, good comments
- Script output must clearly distinguish between:
    COVERED     - found by direct string match
    COVERED*    - found via shared encoding or spec exception
    MISSING     - genuinely not handled

---

## Deliverables
1. Updated tools/check_rva23_coverage.py with both exception tables
2. Re-run output showing Zcb at 13/13
3. Full coverage summary showing updated totals
4. Note any other false negatives discovered during the fix
5. Confirm no coverage numbers decreased from DECODE-003 baseline

:: PROMPT:END ::

=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::

### Claude Text Output

```
 ---                                                                           
  TOOLS-001 Results                                                             
                                                                                
  Changes made — tools/check_rva23_coverage.py only:        
                                                                                
  1. Added COVERED_STAR = 'covered*' status constant.                           
  2. Added KNOWN_SHARED_ENCODINGS table with comments explaining purpose,       
  format, how to extend, and TOOLS-001 reference. Entry: c.sext.w -> C.ADDIW    
  (shared encoding, imm=0 case).                            
  3. Added KNOWN_OPCODES_FILE_GAPS table with same comment structure. Entry:    
  c.zext.w -> ADD.UW rd,rd,x0 (absent from rv_zcb; safety net, already covered  
  via rv64_zcb).
  4. Added _check_exceptions() function that probes both tables after a MISSING 
  classification.                                                               
  5. Modified classification loop to call _check_exceptions() for any MISSING
  result and populate covered_star_list.                                        
  6. Updated counts and ext_results dict to track covered_star.
  7. Added COVERED*: per-instruction lines in the per-extension report.         
  8. Updated SUMMARY to split covered count into direct match vs exception      
  table.                                                                        
                                                                                
  Coverage results:                                                             
                                                            
  ┌────────────┬───────────────┬────────────┐                                   
  │ Extension  │    Before     │   After    │               
  ├────────────┼───────────────┼────────────┤
  │ Zcb        │ 12/13 PARTIAL │ 13/13 FULL │
  ├────────────┼───────────────┼────────────┤
  │ All others │ unchanged     │ unchanged  │                                   
  └────────────┴───────────────┴────────────┘
                                                                                
  Summary totals (DECODE-003 baseline -> TOOLS-001):                            
  - Total in scope: 709 (unchanged)
  - Covered direct: 165 (unchanged)                                             
  - Covered* exception: 0 -> 1 (c.sext.w)                   
  - Routed: 226 (unchanged)                                                     
  - Missing: 318 -> 317 (-1)                                                    
                                                                                
  No false negatives found beyond the two already documented. c.zext.w is       
  correctly handled via rv64_zcb and the RTL comment in rvc_expander.sv; the    
  KNOWN_OPCODES_FILE_GAPS entry documents the rv_zcb gap as a safety net.       
```

### Experiment Header

| Field          | Value |
|----------------|-------|
| Task ID  | TOOLS-001  |
| Date           | 2026.03.22 |
| Module         | check_rva23_coverage.py |
| Run time       | 5m.50s                  |
| Session Link   | {paste claude.ai URL or note "Claude Code session"} 
                   claude --resume 4d86f334-bd1f-4bc9-b278-db243f0e4a92 |

---

### Output Quality

| Criteria                    | Rating (1-5) | Notes |
|-----------------------------|--------------|-------|
| RVA23 compliance            | 5   | |
| Interface correctness       | n/a | |
| RTL quality / readability   | n/a | |
| Testbench quality           | n/a | |
| Verilator compatibility     | n/a | |
| Assumptions stated clearly  | n/a | |

---

### What Claude got right

Fixed the false fails

---

### What Claude got wrong or missed

Nothing in this run.

---

### RVA23 compliance flags raised by Claude

n/a

---

### Interface decisions made - downstream impact

n/a

---

### Prompt effectiveness observations

Did the prompt produce the intended experiment?
  yes
Was anything ambiguous or missing?
  no

---

### Follow-on actions

- [x] Update README.md status table}

---

### Graduated to CLAUDE.md

n/a

:: RESULTS:END ::
