# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile - decoder unit
# Requires Verilator 5.048 ($(VERILATOR) from rtl/Vars.mk)
#
# Targets:
#   lint_dec        - lint instr_decoder
#   lint            - lint_dec
#   sim_dec         - build and run instr_decoder testbench
#   sim             - sim_dec
#   sim_all         - run sim_dec and coverage
#   sim_dec_sweep   - BP-124 (DCD-34): the decoder against the spike-dasm
#                     oracle tb/dec_dasm_oracle.txt. dec_sweep_expect.py
#                     turns each oracle line into the expected decode
#                     (its mnemonic table and the rules that resolve
#                     each disagreement with spike-dasm), and
#                     tb_instr_decoder's +SWEEP mode decodes every
#                     encoding and compares
#   oracle_dec_sweep - BP-124: gen_dec_dasm_oracle.py regenerates the
#                     oracle into the build directory with tools/bin's
#                     spike-dasm and compares it with the committed file
#   asm_dec_words   - BP-124: every directed test word in
#                     tb_instr_decoder.sv is assembled with clang -c and
#                     disassembled with spike-dasm, and must match the
#                     word and the mnemonic the test names
#
# BP-119 (TD#143): rvc_expander.sv, its testbench and the lint_exp and
# sim_exp targets are deleted. Compressed expansion is the IFU's
# (ifu_rvc_exp.sv), checked against the LLVM oracle by the ifu
# Makefile's sim_ifu_rvc_exp; the coverage target credits C and Zcb
# from ifu_rvc_exp.sv.
#
# BP-118 (TD#143): predecode.sv, its testbench and its two targets are
# deleted. instr_decoder takes ifu_pd_pkt_t from bp_structs_pkg, so the
# decoder targets compile the two bp packages first, defines then
# structs, ahead of decode_pkg.
#   coverage        - run RVA23 coverage check script
#   clean           - remove build artifacts

include $(RVA_ROOT)/rtl/Vars.mk

ifeq ($(VERBOSE),1)
  Q :=
else
  Q :=
  MAKEFLAGS := -s --no-print-directory
endif

# -Wno-DECLFILENAME: testbench files named tb_<dut>.sv contain module 'tb'
# -Wno-TIMESCALEMOD: package files cannot carry timescale directives
# -Wno-IMPORTSTAR, -Wno-UNUSED: project-wide (CLAUDE.md), added for the
#   decoder targets by BP-118 with the file-scope bp package imports
VERILATOR_FLAGS = --cc --exe --build --sv -Wall \
                  -Wno-DECLFILENAME -Wno-TIMESCALEMOD --timing
DEC_WFLAGS      = -Wno-IMPORTSTAR -Wno-UNUSED
TOOLS           = ../../../../tools
BPU_DIR         = ../bpu/rtl
BP_PKG          = $(BPU_DIR)/bp_defines_pkg.sv $(BPU_DIR)/bp_structs_pkg.sv
PKG             = rtl/decode_pkg.sv
RTL_DEC         = rtl/instr_decoder.sv
TB_DEC          = tb/tb_instr_decoder.sv
SIM_MAIN_DEC    = verilator/sim_main.cpp
OBJ_DEC         = obj_dir_dec
# BP-124: the oracle sweep and the directed-word check.
SPIKE_DASM      = $(abspath $(TOOLS))/bin/spike-dasm
SWEEP_ORACLE    = tb/dec_dasm_oracle.txt
OBJ_SWEEP       = obj_dir_sweep
OBJ_ORACLE      = obj_dir_oracle
OBJ_WORDS       = obj_dir_words

.PHONY: lint lint_dec \
        sim sim_dec sim_all sim_dec_sweep oracle_dec_sweep asm_dec_words \
        coverage clean help

all: lint sim sim_all

# -- lint only
lint_dec:
	@echo "[linting]    $(BP_PKG) $(PKG) $(RTL_DEC)"
	$(Q)$(VERILATOR) --lint-only --sv -Wall $(DEC_WFLAGS) \
	    $(BP_PKG) $(PKG) $(RTL_DEC)

lint: lint_dec

# -- build and run instr_decoder simulation
sim_dec:
	@echo "[compiling]  $(PKG) $(TB_DEC) $(RTL_DEC)"
	$(Q)mkdir -p $(OBJ_DEC)
	$(Q)$(VERILATOR) $(VERILATOR_FLAGS) $(DEC_WFLAGS) \
	    --top-module tb \
	    --Mdir $(OBJ_DEC) \
	    $(BP_PKG) $(PKG) $(TB_DEC) $(RTL_DEC) \
	    $(SIM_MAIN_DEC) \
	    -o sim_dec
	@echo "[simulating] $(OBJ_DEC)/sim_dec"
	$(Q)./$(OBJ_DEC)/sim_dec

# -- the oracle sweep (BP-124 Problem 4, DCD-34): expectation, build
#    into its own directory, run in +SWEEP mode
sim_dec_sweep:
	@echo "[expecting]  $(SWEEP_ORACLE)"
	$(Q)mkdir -p $(OBJ_SWEEP)
	$(Q)python3 -I -B tb/dec_sweep_expect.py $(SPIKE_DASM) $(PKG) \
	    $(SWEEP_ORACLE) $(OBJ_SWEEP)/dec_sweep_exp.hex \
	    --report $(OBJ_SWEEP)/dec_sweep_report.txt
	@echo "[compiling]  $(PKG) $(TB_DEC) $(RTL_DEC) (sweep)"
	$(Q)$(VERILATOR) $(VERILATOR_FLAGS) $(DEC_WFLAGS) \
	    --top-module tb \
	    --Mdir $(OBJ_SWEEP) \
	    $(BP_PKG) $(PKG) $(TB_DEC) $(RTL_DEC) \
	    $(SIM_MAIN_DEC) \
	    -o sim_dec
	@echo "[simulating] $(OBJ_SWEEP)/sim_dec +SWEEP"
	$(Q)./$(OBJ_SWEEP)/sim_dec +SWEEP=$(OBJ_SWEEP)/dec_sweep_exp.hex

# -- the oracle regenerated and compared with the committed file
oracle_dec_sweep:
	@echo "[generating] decoder sweep oracle"
	$(Q)mkdir -p $(OBJ_ORACLE)
	$(Q)python3 -I -B tb/gen_dec_dasm_oracle.py $(SPIKE_DASM) \
	    $(OBJ_ORACLE)/dec_dasm_oracle.txt
	$(Q)cmp $(SWEEP_ORACLE) $(OBJ_ORACLE)/dec_dasm_oracle.txt
	@echo "oracle_dec_sweep: PASS, $(SWEEP_ORACLE) matches spike-dasm"

# -- the directed test words, assembled and disassembled (BP-124).
#    clang is the one out-of-repo tool, from $(RVA_EXT_TOOLS)
#    (rtl/Vars.mk, BP-132, TD#176); the target fails naming the
#    variable if it is absent.
asm_dec_words:
	@echo "[assembling] tb_instr_decoder directed words"
	$(Q)$(call need_ext_tool,asm_dec_words,clang)
	$(Q)mkdir -p $(OBJ_WORDS)
	$(Q)python3 -I -B tb/chk_dec_words.py $(RVA_EXT_TOOLS)/clang \
	    $(SPIKE_DASM) \
	    $(TB_DEC) $(OBJ_WORDS)

# -- run sim_dec (combined target kept for its callers)
sim: sim_dec

# -- run the instr_decoder testbench and the coverage check
sim_all: sim_dec coverage

# -- run RVA23 coverage check (exit 1 if any MISSING instructions found)
coverage:
	@python3 $(TOOLS)/check_rva23_coverage.py; \
	rc=$$?; \
	if [ $$rc -eq 0 ]; then \
	  echo "[coverage]   PASS (no MISSING instructions)"; \
	else \
	  echo "[coverage]   FAIL (MISSING instructions found)"; \
	  exit 1; \
	fi

# -- remove build artifacts
clean:
	$(Q)rm -rf $(OBJ_DEC) $(OBJ_SWEEP) $(OBJ_ORACLE) $(OBJ_WORDS)

# -- print available targets
help:
	@echo "Targets:"
	@echo "  lint_dec       - lint instr_decoder"
	@echo "  lint           - lint_dec"
	@echo "  sim_dec        - build and run instr_decoder testbench"
	@echo "  sim            - sim_dec"
	@echo "  sim_all        - run sim_dec, coverage"
	@echo "  sim_dec_sweep  - the decoder against the spike-dasm oracle"
	@echo "  oracle_dec_sweep - regenerate and compare the oracle"
	@echo "  asm_dec_words  - assemble and disassemble the test words"
	@echo "  coverage       - run RVA23 coverage check script"
	@echo "  clean          - remove build artifacts"

# -- Regression plumbing (TOOLS-006) ----------------------------------
# tools/regress.sh runs every REGRESS_TARGETS entry with its own make
# call and fails if a target defined in this file is in neither list.
# Exclusions:
#   all, lint, sim, sim_all - aggregates; their recipes only run the
#                             targets listed in REGRESS_TARGETS.
#   help                    - prints the target list.
#   clean, regress_list     - housekeeping and this plumbing.
REGRESS_TARGETS := \
  lint_dec \
  sim_dec \
  coverage \
  sim_dec_sweep \
  oracle_dec_sweep \
  asm_dec_words
REGRESS_EXCLUDE := all lint sim sim_all help clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
