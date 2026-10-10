# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- PMP and PMA checker (BP-118)
#
# TARGETS:
#
#   lint_pmp_pma_chk     the checker, mmu_decisions.md MMU-10a
#   sim_pmp_pma_chk      tb/tb_pmp_pma_chk.sv
#   lint_neg_pma         MMU-15b (BP-123): the checker elaborated with a
#                        region table whose one region is executable
#                        and not idempotent. Passes ONLY when verilator
#                        FAILS with the MMU-15b message
#   lint_neg_pma_dflt    the same for the default attributes
#
# The checker is combinational and holds no state, so it has no bound
# property file: its testbench compares every output directly.
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
VER_OUT  := obj

VER_FLAGS       := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing
SIM_EXTRA_FLAGS := -Wno-DECLFILENAME

PKG_SRCS := \
  $(BPU_DIR)/bp_defines_pkg.sv \
  $(BPU_DIR)/bp_structs_pkg.sv

CHK_SRCS := $(PKG_SRCS) $(RTL_DIR)/pmp_pma_chk.sv

.PHONY: all clean lint_pmp_pma_chk sim_pmp_pma_chk lint_neg_pma \
        lint_neg_pma_dflt

all: lint_pmp_pma_chk sim_pmp_pma_chk lint_neg_pma lint_neg_pma_dflt

lint_pmp_pma_chk:
	@echo "[linting]    pmp_pma_chk"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) \
	  --top-module pmp_pma_chk $(CHK_SRCS) $(VSILENCE)

sim_pmp_pma_chk:
	@echo "[compiling]  tb_pmp_pma_chk"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb --Mdir $(VER_OUT)_pmp_pma_chk \
	  $(CHK_SRCS) $(TB_DIR)/tb_pmp_pma_chk.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_pmp_pma_chk/Vtb"
	$(Q)./$(VER_OUT)_pmp_pma_chk/Vtb

# MMU-15b negative lints. $(1) target, $(2) the -G override. NEG_MSG is
# the text the log must carry.
NEG_MSG := MMU-15b

define neg_rule
$(1):
	@echo "[linting]    pmp_pma_chk $(2), must fail"
	$$(Q)mkdir -p $$(VER_OUT)_$(1)
	$$(Q)if $$(VERILATOR) --lint-only $$(VER_FLAGS) $(2) \
	      --top-module pmp_pma_chk $$(CHK_SRCS) \
	      > $$(VER_OUT)_$(1)/verilator.log 2>&1; then \
	  echo "$(1): FAIL - verilator exited 0"; exit 1; \
	elif grep -qF '$$(NEG_MSG)' $$(VER_OUT)_$(1)/verilator.log; then \
	  echo "$(1): PASS - rejected with the MMU-15b message"; \
	else \
	  echo "$(1): FAIL - no MMU-15b message"; exit 1; \
	fi
endef

# Region attributes [3] idempotent [2] executable [1] coherent
# [0] cacheable: 4'b0111 is executable and not idempotent.
$(eval $(call neg_rule,lint_neg_pma,-GPMA_ATTR=4\'b0111))
$(eval $(call neg_rule,lint_neg_pma_dflt,-GPMA_DFLT=4\'b0100))

clean:
	@echo "[cleaning]   pmp"
	$(Q)rm -rf $(VER_OUT)*

# -- Regression plumbing (TOOLS-006) ----------------------------------
# Exclusions:
#   all                 - aggregate.
#   clean, regress_list - housekeeping and this plumbing.
REGRESS_TARGETS := lint_pmp_pma_chk sim_pmp_pma_chk lint_neg_pma \
                   lint_neg_pma_dflt
REGRESS_EXCLUDE := all clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
