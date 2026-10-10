# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- the pacino L1I (BP-123), cachegen_decisions.md CG-4, CG-D1
#
# The cachegen emission under tools/cachegen/output/l1i, copied here and
# changed here (CG-D1). Nothing under tools/ is compiled by this file.
#
# TARGETS:
#
#   lint_l1i          the L1I, warnings on
#   sim_l1i_emitted   the emitted unit testbench (tb/l1i_tb.sv, module
#                     l1i_tb), kept as emitted apart from the tie-offs
#                     the BP-123 ports need. It ends with $finish
#                     whether or not a check failed, so the target
#                     reads its summary line and fails on any FAIL
#   sim_l1i           tb/tb_l1i.sv: the BP-123 additions, the
#                     maintenance port (IF-28 to IF-32, IF-42) and the
#                     uncached request (IF-44, L1I-24), with the bound
#                     properties of tb/l1i_assert.sv and
#                     tb/l1i_mshr_assert.sv
#   assert_labels     every property label of those files is in the
#                     sim_l1i model
RVA_ROOT ?= $(abspath ../../../..)
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
VER_OUT  := obj

VER_FLAGS       := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing
SIM_EXTRA_FLAGS := -Wno-DECLFILENAME

# Async rstn with `disable iff (!rstn)` in the bound properties, and
# --assert so the concurrent SVA is elaborated (as the ifu Makefile).
COMMON := -Wno-SYNCASYNCNET --assert

# The L1I, in the order of the emitted filelist (l1i.f). cgen_tl_pkg is
# the one shared emitted package the node imports (l1i_mem_mst and the
# emitted testbench); the other shared packages in l1i.f are imported
# by nothing here.
L1I_SRCS := \
  $(RTL_DIR)/cgen_tl_pkg.sv \
  $(RTL_DIR)/l1i_pkg.sv \
  $(RTL_DIR)/l1i_core_slv.sv \
  $(RTL_DIR)/l1i_mem_mst.sv \
  $(RTL_DIR)/l1i_meta_array.sv \
  $(RTL_DIR)/l1i_data_array.sv \
  $(RTL_DIR)/l1i_ctrl.sv \
  $(RTL_DIR)/l1i_bank.sv \
  $(RTL_DIR)/l1i_mshr.sv \
  $(RTL_DIR)/l1i_maint.sv \
  $(RTL_DIR)/l1i.sv

EMIT_TB_SRCS := $(TB_DIR)/l1i_tb_mem.sv $(TB_DIR)/l1i_tb.sv
ASSERT_SRCS  := $(TB_DIR)/l1i_assert.sv $(TB_DIR)/l1i_mshr_assert.sv
EMIT_DIR     := $(VER_OUT)_l1i_emitted
EMIT_LOG     := $(EMIT_DIR)/sim.log

.PHONY: all clean lint_l1i sim_l1i_emitted sim_l1i assert_labels

all: lint_l1i sim_l1i_emitted sim_l1i assert_labels

lint_l1i:
	@echo "[linting]    l1i"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) \
	  --top-module l1i $(L1I_SRCS) $(VSILENCE)

sim_l1i_emitted:
	@echo "[compiling]  l1i_tb (emitted)"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  +incdir+$(TB_DIR) --top-module l1i_tb --Mdir $(EMIT_DIR) \
	  $(L1I_SRCS) $(EMIT_TB_SRCS) $(VSILENCE)
	@echo "[simulating] $(EMIT_DIR)/Vl1i_tb"
	$(Q)./$(EMIT_DIR)/Vl1i_tb > $(EMIT_LOG) 2>&1; rc=$$?; \
	cat $(EMIT_LOG); \
	if [ $$rc -ne 0 ]; then echo "sim_l1i_emitted: exit $$rc"; exit 1; fi; \
	if grep -q '^FAIL' $(EMIT_LOG); then \
	  echo "sim_l1i_emitted: a check failed"; exit 1; fi; \
	grep -q '^l1i_tb: PASS' $(EMIT_LOG) || \
	  { echo "sim_l1i_emitted: no PASS summary"; exit 1; }

sim_l1i:
	@echo "[compiling]  tb_l1i"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) $(COMMON) \
	  --top-module tb --Mdir $(VER_OUT)_l1i \
	  $(L1I_SRCS) $(ASSERT_SRCS) $(TB_DIR)/tb_l1i.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_l1i/Vtb"
	$(Q)./$(VER_OUT)_l1i/Vtb

LABEL_RE := ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:
LABEL_RE := $(LABEL_RE)[[:space:]]*assert[[:space:]]+property

assert_labels: sim_l1i
	@echo "[checking]   assertion labels in the sim_l1i model"
	$(Q)n=0; m=0; \
	for f in $(ASSERT_SRCS); do \
	  for l in $$(sed -nE 's/$(LABEL_RE).*/\1/p' $$f); do \
	    n=$$((n+1)); \
	    if ! grep -qF ".$$l\"" $(VER_OUT)_l1i/*.cpp; then \
	      echo "MISSING: $$l ($$f)"; m=$$((m+1)); \
	    fi; \
	  done; \
	done; \
	echo "assert_labels: PASS=$$((n-m)) FAIL=$$m"; \
	test $$m -eq 0 && test $$n -gt 0

clean:
	@echo "[cleaning]   icache"
	$(Q)rm -rf $(VER_OUT)*

# -- Regression plumbing (TOOLS-006) ----------------------------------
# Exclusions:
#   all                 - aggregate.
#   clean, regress_list - housekeeping and this plumbing.
REGRESS_TARGETS := lint_l1i sim_l1i_emitted sim_l1i assert_labels
REGRESS_EXCLUDE := all clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
