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

.PHONY: lint lint_dec \
        sim sim_dec sim_all \
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
	$(Q)rm -rf $(OBJ_DEC)

# -- print available targets
help:
	@echo "Targets:"
	@echo "  lint_dec       - lint instr_decoder"
	@echo "  lint           - lint_dec"
	@echo "  sim_dec        - build and run instr_decoder testbench"
	@echo "  sim            - sim_dec"
	@echo "  sim_all        - run sim_dec, coverage"
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
  coverage
REGRESS_EXCLUDE := all lint sim sim_all help clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
