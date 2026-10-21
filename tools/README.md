<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Pacino Tools Directory 

```
| Name | Description |
|------|-------------|
| backfill_prompts.py     | automate maintenance on prompts |
| bin                     | tools install |
| blog_handoff.sh         | automate handoff transfer for blogs |
| cachegen                | uarchlabs cachegen tool |
| check_rva23_coverage.py | RVA23 gap analysis |
| check_spdx.py           | license header check |
| check_spike_decode.py   | use spike_oracle.csv check for decode support |
| cov_table.py            | emits BPU coverage tables |
| create_docs_stubs.sh    | populate empty doc tree |
| gen_sessions.py         | create the sessions.json, err checking |
| gen_spike_oracle.py     | emits spike_oracle.csv |
| get_cntx.sh             | disposable |
| handoff.sh              | cat handoff files |
| hooks                   | git hooks |
| include                 | install headers |
| known_failures.txt      | deprecated |
| lib                     | tools library |
| make_context.sh         | disposable |
| Makefile                | spike build |
| mk_pkg.sh               | disposable |
| prereqs.sh              | required packages |
| README.md               | ... |
| regress.sh              | git hook regression script |
| rename_mcf.py           | disposable |
| riscv-opcodes           | submodule |
| run_tf.sh               | ticfinder util |
| run_time.py             | capture time for runtime in prompts |
| rva23_ext_test          | RVA23 compliance support |
| rva23_ext_test.c        | RVA23 compliance support |
| rva23_ext_test.disasm   | RVA23 compliance support |
| rva23_insn_ref.c        | RVA23 compliance support |
| rva23_insn_ref.disasm   | RVA23 compliance support |
| rva23_insn_ref.o        | RVA23 compliance support |
| setup.sh                | new terminal setup |
| share                   | tools install share |
| spike                   | simulator |
| spike_oracle.csv        | see above |
| ticfinder               | uarchlabs spacy based text analysis |
| validate_and_extract.py | pre-run task file checker |
| verilator               | rtl simulator |


## Usage

## check_rva23_coverage.py

Parses `tools/riscv-opcodes/` extension files and checks coverage against the RTL in
`rtl/core/frontend/decode/rtl/`. Produces a per-extension report with COVERED, ROUTED, and
MISSING categories.

```bash
cd $RVA_ROOT/rtl/core/frontend/decode
make coverage    # exits non-zero if any MISSING instructions found
make sim_all     # runs all testbenches then coverage
```

Known limitations are documented in the script's `KNOWN_SHARED_ENCODINGS` and
`KNOWN_OPCODES_FILE_GAPS` tables.

## riscv-opcodes

Git submodule at `tools/riscv-opcodes/`. Enumerates standard RISC-V instruction
opcodes and CSRs. Used as ground truth for coverage checking and decoder validation.

## spike

Git submodule at `tools/spike/`. Functional ISA simulator; `spike-dasm` is
used as an independent disassembler (TOOLS-002). Installed to `tools/bin/`
(see "Compile and install spike").

spike-dasm input format uses `DASM(hex)` tokens, not raw hex values.
Extensions must be enumerated; there is no `G` shortcut beyond `rv64g`.
The full RVA23 string is `ISA` in `tools/check_spike_decode.py`.

```bash
# disassemble a NOP
echo "DASM(00000013)" | tools/bin/spike-dasm

# disassemble a vector instruction
echo "DASM(00000057)" | tools/bin/spike-dasm --isa rv64gcv
```

