# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- L1 instruction TLB (BP-118)
#
# TARGETS:
#
#   lint_itlb       the ITLB with its PMP / PMA checker (MMU-10a)
#   sim_itlb        tb/tb_itlb.sv at the default WALK_DEPTH 1
#   sim_itlb_d2     the same testbench at WALK_DEPTH 2 (ITLB-15)
#   assert_labels   every property of tb/itlb_assert.sv is in both
#                   sim models (the ifu Makefile's method)
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
PMP_DIR  := ../pmp/rtl
VER_OUT  := obj

VER_FLAGS       := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing
SIM_EXTRA_FLAGS := -Wno-DECLFILENAME

# Async rstn with `disable iff (!rstn)` in the bound properties, and
# --assert so the concurrent SVA is elaborated (as the ifu Makefile).
COMMON := -Wno-SYNCASYNCNET --assert

PKG_SRCS := \
  $(BPU_DIR)/bp_defines_pkg.sv \
  $(BPU_DIR)/bp_structs_pkg.sv

ITLB_SRCS := $(PKG_SRCS) $(PMP_DIR)/pmp_pma_chk.sv $(RTL_DIR)/itlb.sv
SIM_SRCS  := $(ITLB_SRCS) $(TB_DIR)/itlb_assert.sv

.PHONY: all clean assert_labels lint_itlb sim_itlb sim_itlb_d2

all: lint_itlb sim_itlb sim_itlb_d2 assert_labels

lint_itlb:
	@echo "[linting]    itlb"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module itlb $(SIM_SRCS) $(VSILENCE)

# $(1) target suffix, $(2) WALK_DEPTH.
define sim_rule
sim_itlb$(1):
	@echo "[compiling]  tb_itlb WALK_DEPTH=$(2)"
	$$(Q)$$(VERILATOR) --binary $$(VER_FLAGS) $$(SIM_EXTRA_FLAGS) \
	  $$(COMMON) --top-module tb -GWALK_DEPTH=$(2) \
	  --Mdir $$(VER_OUT)_itlb$(1) \
	  $$(SIM_SRCS) $$(TB_DIR)/tb_itlb.sv $$(VSILENCE)
	@echo "[simulating] $$(VER_OUT)_itlb$(1)/Vtb"
	$$(Q)./$$(VER_OUT)_itlb$(1)/Vtb
endef

$(eval $(call sim_rule,,1))
$(eval $(call sim_rule,_d2,2))

LABEL_RE := ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:
LABEL_RE := $(LABEL_RE)[[:space:]]*assert[[:space:]]+property

assert_labels:
	@echo "[checking]   assertion labels in the sim model"
	$(Q)f=$(TB_DIR)/itlb_assert.sv; \
	a=$$(grep -cE 'assert[[:space:]]+property' $$f); \
	b=$$(grep -cE '$(LABEL_RE)' $$f); \
	if [ $$a -ne $$b ]; then echo "UNLABELED in $$f"; exit 1; fi; \
	$(VERILATOR) --cc $(VER_FLAGS) $(SIM_EXTRA_FLAGS) $(COMMON) \
	  --top-module tb --Mdir $(VER_OUT)_labels \
	  $(SIM_SRCS) $(TB_DIR)/tb_itlb.sv > /dev/null || exit 1; \
	n=0; m=0; \
	for l in $$(sed -nE 's/$(LABEL_RE).*/\1/p' $$f); do \
	  n=$$((n+1)); \
	  if ! grep -qF ".$$l\"" $(VER_OUT)_labels/*.cpp; then \
	    echo "MISSING: $$l"; m=$$((m+1)); fi; \
	done; \
	echo "assert_labels: PASS=$$((n-m)) FAIL=$$m"; \
	test $$m -eq 0

clean:
	@echo "[cleaning]   itlb"
	$(Q)rm -rf $(VER_OUT)*

# -- Regression plumbing (TOOLS-006) ----------------------------------
# Exclusions:
#   all                 - aggregate.
#   clean, regress_list - housekeeping and this plumbing.
REGRESS_TARGETS := lint_itlb sim_itlb sim_itlb_d2 assert_labels
REGRESS_EXCLUDE := all clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
