# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- CSR packages (SYS-001), csr_decisions.md CSR-1, CSR-2
#
# TARGETS:
#
#   lint_csr_pkg        rtl/csr_pkg.sv, the CSR layouts and the group
#                       structs (CSR-1), warnings on
#   lint_csr_tb_pkg     tb/csr_tb_pkg.sv, the testbench CSR shadow
#                       (CSR-2), over csr_pkg
#   sim_csr_tb_pkg      tb/tb_csr_tb_pkg.sv: the CSR-5 write rules,
#                       the named setters, set_ext_enable and the pack
#                       functions
#
# csr_pkg declares ext_enable as decode_pkg::ext_enable_t (CSR-4) and
# sizes its members from bp_defines_pkg, so both are compiled first.
RVA_ROOT ?= $(abspath ../../..)
include $(RVA_ROOT)/rtl/Vars.mk

ifeq ($(VERBOSE),1)
  Q        :=
  VSILENCE :=
else
  Q        := @
  VSILENCE := > /dev/null
  MAKEFLAGS := -s --no-print-directory
endif

.DEFAULT_GOAL := all

RTL_DIR  := rtl
TB_DIR   := tb
BPU_DIR  := ../frontend/bpu/rtl
DEC_DIR  := ../frontend/decode/rtl
VER_OUT  := obj

VER_FLAGS       := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing
SIM_EXTRA_FLAGS := -Wno-DECLFILENAME

PKG_SRCS := \
  $(BPU_DIR)/bp_defines_pkg.sv \
  $(BPU_DIR)/bp_structs_pkg.sv \
  $(DEC_DIR)/decode_pkg.sv

CSR_SRCS    := $(PKG_SRCS) $(RTL_DIR)/csr_pkg.sv
CSR_TB_SRCS := $(CSR_SRCS) $(TB_DIR)/csr_tb_pkg.sv

.PHONY: all clean lint_csr_pkg lint_csr_tb_pkg sim_csr_tb_pkg

all: lint_csr_pkg lint_csr_tb_pkg sim_csr_tb_pkg

lint_csr_pkg:
	@echo "[linting]    csr_pkg"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(CSR_SRCS) $(VSILENCE)

# csr_tb_pkg is testbench code: its class csr_shadow is not named after
# the file, so it takes the sim targets' -Wno-DECLFILENAME.
lint_csr_tb_pkg:
	@echo "[linting]    csr_tb_pkg"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(CSR_TB_SRCS) $(VSILENCE)

sim_csr_tb_pkg:
	@echo "[compiling]  tb_csr_tb_pkg"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb --Mdir $(VER_OUT)_csr_tb_pkg \
	  $(CSR_TB_SRCS) $(TB_DIR)/tb_csr_tb_pkg.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_csr_tb_pkg/Vtb"
	$(Q)./$(VER_OUT)_csr_tb_pkg/Vtb

clean:
	@echo "[cleaning]   csr"
	$(Q)rm -rf $(VER_OUT)*

# -- Regression plumbing (TOOLS-006) ----------------------------------
# Exclusions:
#   all                 - aggregate.
#   clean, regress_list - housekeeping and this plumbing.
REGRESS_TARGETS := lint_csr_pkg lint_csr_tb_pkg sim_csr_tb_pkg
REGRESS_EXCLUDE := all clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
