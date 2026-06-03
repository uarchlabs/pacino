=============================================================
# Task Header 
=============================================================
:: HEADER:START ::
| Field       | Value                                        |   |
|-------------|----------------------------------------------|---|
| Task ID     | DECODE-001                                   |   |
| Date        | 2026-03-22                                   |   |
| Module      | pre decode                                   |   |
| Run time    | 51m.14s                                      |   |
| Ctx%        | not recorded                                 |   |
| Model       | Sonnet 4.6 normal                            |   |
| Resume sha  | f0ed975b-4d79-4550-91c2-154433d41093         |   |
| PA session  | 001 | |

Task:   [x] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Mode:   [x] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview

Not captured at time, this task is one of the first.

2026-05-30: Manually adding overview: This task creates a predecode 
module that takes advantage of the RISC-V ISA natural expansion of
all compressed instructions to their 32b equivalent. There is some
operand encoding matchins and opcode expansion. The purpose of this
module is to simplify downstream logic.

Additionally this task file has been retro-fitted with the now standard
section markers.
:: HEADER:END :
=============================================================
:: DISCUSSION:START ::

# Results Discussion

## Claude.code Console Output
Not captured, this task predates the fully standardized prompting
scheme.

## My Assessment
Nothing required
## Claude.ai Assessment
Nothing required
## Follow-on Actions
- [x] Run Verilator and confirm clean compile
- [ ] Compare against DECODE-002 when available
- [x] Update CLAUDE.md if interface decisions confirmed
- [ ] Update README.md status table
- [ ] Define DECODE-002 to implement an independent verification method using
      riscv-opcodes

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
DECODE-001

## SESSION PROMPT

Module: Instruction Decoder

Experiment: DECODE-001 - Pre-decode expansion approach for mixed 16b/32b fetch
bundle

---

## Hypothesis 
Expand all 16b (RVC) instructions to 32b immediately after fetch, before the
main decode stage. The fetch bundle presents as 8x32b to the decoder,
accompanied by a boundary mask that identifies valid instruction starts and
original instruction widths.

## Specific Requirements

Specific requirements for this experiment:
- Fetch bundle input: 8x32b words plus a boundary mask
- Boundary mask encodes: valid slot, original width (16b or 32b), alignment
- RVC expansion happens in a pre-decode stage, separate from the main decoder
- Main decoder sees only 32b instructions - no knowledge of original widths
- Output bundle: up to 8 decoded instructions, each with full decode fields
  sized for 8-issue OOO dispatch

## Constraints

Constraints for this experiment:
- Pre-decode expansion must be fully combinational - no latency
- Use a parallel expansion approach, not iterative or loop-based
- All 8 slots must be expandable simultaneously

## Deliverables

Deliverables:
1. Pre-decode expansion module (RTL + testbench)
2. Instruction decoder module (RTL + testbench)
3. Brief note on any RVA23 compliance assumptions made
4. Flag any interface decisions that will affect downstream rename/dispatch

:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::

### Experiment Header

| Field          | Value               |
|----------------|---------------------|
| Task ID        | DECODE-001          |
| Date           | 2026.03.22          |
| Module         | Instruction Decoder |
| Run time       | 51m.14s             |
| Session Link   | claude --resume f0ed975b-4d79-4550-91c2-154433d41093 |

---

### Output Quality

| Criteria                  | Rating(1-5) | Notes                            |
|---------------------------|-------------|----------------------------------|
| RVA23 compliance          | 4 | V extension not handled |
| Interface correctness     | 5 | visually inspected future tests needed |
| RTL quality / readability | 5 | readable |
| Testbench quality         | 3 | test benches are not exhaustive this was caused by not specifying this in the prompt |
| Verilator compatibility   | 5 | no issues discoverted|
| Assumptions stated clearly| 1l| unclear where the assumptions were expressed|

---

### What Claude got right

Created a decoder_pkg.sv to marshall parameters and structs
Fixed the verilator lint warnings automatically

Results from DECODE-002 (compliance checking) show better than expected
coverage. +99% complete for scalar section.

(see DECODE-002.md starting at BEGIN_SESSION_PARTIAL_OUTPUT)

Claude made an architectural decision with the concept of 'ROUTED'. Low level
decoding is deferred to the functional unit. This is fine for this point
in the design process but this will need to be reassessed when 
considering fusion, uop/trace caching, etc. This low level decoding will
occur before the 'functional unit', again this is find for now.

---

### What Claude got wrong or missed

Seems some RVA23 required extensions are missing. It did not recognize 
this as a flaw on it's own, silently returned results

Vector instructions are missing.

Zihpm/Zvfhmin support is debated. Not a clean right or wrong. Zihpm is
covered by routing to CSRRS. Zvfhmin are part of vector so technically missing
along with the other Vector instructions

Zcb (13 instructions) are missing.

The guidance prompt instructed the tool to expand 16b instructions to 32b
before decoding. However there is no indication that the original opcode was
compressed. This should be a bit in decode_pkt_t in order to know if it
is PC+2 or PC+4. Calling this a miss in terms of getting it right/wrong is
not completely accurate. There was no guidance in DECODE-001 prompt.

---

### RVA23 compliance flags raised by Claude

None. This was a problem, the reports of missing compliance came in DECODE-002
after the fact.

---

### Interface decisions made - downstream impact

To early to tell.

---

### Prompt effectiveness observations

The prompt was written by Claude.ai

Forcing all tb modules to be called tb and not tb_<module>.sv created a minor issue. Keeping this for now.

It's possible just saying RVA23 was not sufficient. It might have improved by explicitly listing the requirements, or stating that ALL extensions are required,  more strongly.

A useful feature would be some method with minimal LLM interaction for
independent verification. This will be the next experiment: how much help
can the LLM provide for this independent verification method without 
compromising the usefulness of the check.

The prompt left some potential holes due to completeness of the prompt. To
early to tell but:

- There might be issues with PC increment +2 opr +4.
- There might be a need for an additional pre-decode to find branches early.

---

### Follow-on actions

- [x] Run Verilator and confirm clean compile
- [ ] Compare against DECODE-002 when available
- [x] Update CLAUDE.md if interface decisions confirmed
- [ ] Update README.md status table
- [ ] Define DECODE-002 to implement an independent verification method using
      riscv-opcodes

---

### Graduated to CLAUDE.md

{date} - {what was added, or "nothing" if no decisions confirmed}

## Files Modified
Not captured

:: RESULTS:END ::
