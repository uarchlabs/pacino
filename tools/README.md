<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Pacino Tools Directory 

```
| Name | Description |
|------|-------------|
| apt-requirements.txt    | required packages, grouped by tool |
| backfill_prompts.py     | automate maintenance on prompts |
| bin                     | tools install |
| blog_handoff.sh         | automate handoff transfer for blogs |
| build_tools.sh          | check and build verilator, spike, surfer, lcov, fst2vcd; locate or install embecosm |
| cachegen                | uarchlabs cachegen tool |
| check_embecosm.sh       | check/locate/install embecosm RISC-V toolchain |
| check_fst2vcd.sh        | check/build fst2vcd (GTKWave helper only) |
| check_lcov.sh           | check/install lcov (genhtml) |
| check_lib.sh            | shared code for check_<tool>.sh |
| check_rva23_coverage.py | RVA23 gap analysis |
| check_spdx.py           | license header check |
| check_spike.sh          | check/build spike |
| check_spike_decode.py   | use spike_oracle.csv check for decode support |
| check_surfer.sh         | check/build surfer; installs Rust into rust/ |
| check_verilator.sh      | check/build verilator |
| cov_table.py            | emits BPU coverage tables |
| create_docs_stubs.sh    | populate empty doc tree |
| etc                     | tools install etc (lcovrc) |
| gen_sessions.py         | create the sessions.json, err checking |
| gen_spike_oracle.py     | emits spike_oracle.csv |
| get_cntx.sh             | disposable |
| gtkwave                 | GTKWave source, cloned by check_fst2vcd.sh |
| handoff.sh              | cat handoff files |
| hooks                   | git hooks |
| include                 | install headers |
| known_failures.txt      | deprecated |
| lcov                    | lcov source, cloned by check_lcov.sh |
| lib                     | tools library |
| local.mk                | not tracked; EMBECOSM_BIN saved by check_embecosm.sh |
| make_context.sh         | disposable |
| Makefile                | rva23_insn_ref/rva23_ext_test with Embecosm riscv32 gcc; spike_all decode check |
| mk_pkg.sh               | disposable |
| README.md               | ... |
| regress.sh              | git hook regression script |
| requirements.txt        | required Python packages (pip) |
| rename_mcf.py           | disposable |
| riscv-embecosm-embedded-ubuntu2204-20250309 | not tracked; Embecosm toolchain, when installed into tools/ |
| riscv-opcodes           | submodule |
| run_tf.sh               | ticfinder util |
| rust                    | not tracked; Rust for the Surfer build, installed by check_surfer.sh |
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
| surfer                  | waveform viewer source, cloned by check_surfer.sh |
| ticfinder               | uarchlabs spacy based text analysis |
| validate_and_extract.py | pre-run task file checker |
| verilator               | rtl simulator |


## Usage

## build_tools.sh

Checks Verilator 5.048, Spike 1.1.1-dev, Surfer v0.7.0, lcov v1.15 and
fst2vcd (GTKWave v3.3.104) in `tools/bin` and builds any that is missing
or at the wrong version. It also checks the Embecosm toolchain in
`EMBECOSM_BIN` (`rtl/Vars.mk`). When that is missing it asks for the bin
directory of an existing install, or downloads the release into
`tools/`, and saves the answer in `tools/local.mk`. It checks everything
and asks that one question first, in a few seconds, then builds
unattended. It installs no system packages: when one is missing it stops
before any build and prints one apt command for all of them. Rust, for
Surfer, it installs into `tools/rust`. See "Build the tools" in the
top-level README.md.

Every run is logged to `logs/pacino_setup_YYYY-MM-DD_N.log` (N counts
the runs that day): a header with the date, user, host, OS, git branch
and commit and the options, then all the output. `logs/` is not
tracked.

```bash
tools/build_tools.sh                  # check, build what is needed
tools/build_tools.sh --check          # phase 1 only, asks nothing
tools/build_tools.sh spike            # one tool
tools/check_spike.sh [--build]        # the per-tool script it runs
tools/check_embecosm.sh --ask         # ask and save only (phase 1)
tools/check_embecosm.sh --install     # install without asking (phase 2)
```

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
by `build_tools.sh` (see "Build the tools" in the top-level README.md).

spike-dasm input format uses `DASM(hex)` tokens, not raw hex values.
Extensions must be enumerated; there is no `G` shortcut beyond `rv64g`.
The full RVA23 string is `ISA` in `tools/check_spike_decode.py`.

```bash
# disassemble a NOP
echo "DASM(00000013)" | tools/bin/spike-dasm

# disassemble a vector instruction
echo "DASM(00000057)" | tools/bin/spike-dasm --isa rv64gcv
```

