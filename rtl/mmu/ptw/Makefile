# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- page table walker (BP-123), mmu_decisions.md
#
# TARGETS:
#
#   lint_ptw        the walker with its PMP / PMA checker (MMU-10a,
#                   MMU-10d)
#   sim_ptw         tb/tb_ptw.sv, with tb/ptw_assert.sv bound in
#   assert_labels   every property of tb/ptw_assert.sv is in the sim
#                   model (the itlb Makefile's method)
#
# The checker source is the pmp unit's; it is compiled here, not
# copied.
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
BPU_DIR  := ../../core/frontend/bpu/rtl
DEC_DIR  := ../../core/frontend/decode/rtl
CSR_DIR  := ../../core/csr
PMP_DIR  := ../pmp/rtl
VER_OUT  := obj

VER_FLAGS       := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing
SIM_EXTRA_FLAGS := -Wno-DECLFILENAME

# Async rstn with `disable iff (!rstn)` in the bound properties, and
# --assert so the concurrent SVA is elaborated.
COMMON := -Wno-SYNCASYNCNET --assert

# decode_pkg and csr_pkg (SYS-001): the CSR group ports are csr_pkg
# types, and csr_pkg's fe_cfg_t holds decode_pkg's ext_enable_t. The
# testbench drives them from csr_tb_pkg (csr_decisions.md CSR-2).
PKG_SRCS := \
  $(BPU_DIR)/bp_defines_pkg.sv \
  $(BPU_DIR)/bp_structs_pkg.sv \
  $(DEC_DIR)/decode_pkg.sv \
  $(CSR_DIR)/rtl/csr_pkg.sv

TB_PKG_SRCS := $(CSR_DIR)/tb/csr_tb_pkg.sv

PTW_SRCS := $(PKG_SRCS) $(PMP_DIR)/pmp_pma_chk.sv $(RTL_DIR)/ptw.sv
SIM_SRCS := $(PTW_SRCS) $(TB_DIR)/ptw_assert.sv

.PHONY: all clean assert_labels lint_ptw sim_ptw

all: lint_ptw sim_ptw assert_labels

lint_ptw:
	@echo "[linting]    ptw"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ptw $(PTW_SRCS) $(VSILENCE)

sim_ptw:
	@echo "[compiling]  tb_ptw"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ptw \
	  $(SIM_SRCS) $(TB_PKG_SRCS) $(TB_DIR)/tb_ptw.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ptw/Vtb"
	$(Q)./$(VER_OUT)_ptw/Vtb

LABEL_RE := ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:
LABEL_RE := $(LABEL_RE)[[:space:]]*assert[[:space:]]+property

assert_labels: sim_ptw
	@echo "[checking]   assertion labels in the sim model"
	$(Q)n=0; m=0; f=$(TB_DIR)/ptw_assert.sv; \
	for l in $$(sed -nE 's/$(LABEL_RE).*/\1/p' $$f); do \
	  n=$$((n+1)); \
	  if ! grep -qF ".$$l\"" $(VER_OUT)_ptw/*.cpp; then \
	    echo "MISSING: $$l"; m=$$((m+1)); \
	  fi; \
	done; \
	echo "assert_labels: PASS=$$((n-m)) FAIL=$$m"; \
	test $$m -eq 0 && test $$n -gt 0

clean:
	@echo "[cleaning]   ptw"
	$(Q)rm -rf $(VER_OUT)*

# -- Regression plumbing (TOOLS-006) ----------------------------------
# Exclusions:
#   all                 - aggregate.
#   clean, regress_list - housekeeping and this plumbing.
REGRESS_TARGETS := lint_ptw sim_ptw assert_labels
REGRESS_EXCLUDE := all clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
