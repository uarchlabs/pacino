# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- instruction buffer (BP-118)
#
# TARGETS:
#
#   lint_ibuf       the module, with its bound properties
#   sim_ibuf        tb/tb_ibuf.sv
#   assert_labels   every property label is in the sim model
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
BPU_DIR  := ../bpu/rtl
VER_OUT  := obj

VER_FLAGS       := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing
SIM_EXTRA_FLAGS := -Wno-DECLFILENAME

# -Wno-SYNCASYNCNET and --assert as in the ifu Makefile: async rstn
# with `disable iff (!rstn)` in the bound properties, and --assert so
# the concurrent SVA is elaborated at all (TD#109).
COMMON := -Wno-SYNCASYNCNET --assert

PKG_SRCS := \
  $(BPU_DIR)/bp_defines_pkg.sv \
  $(BPU_DIR)/bp_structs_pkg.sv

IBUF_SRCS := $(PKG_SRCS) $(RTL_DIR)/ibuf.sv $(TB_DIR)/ibuf_assert.sv

.PHONY: all clean assert_labels lint_ibuf sim_ibuf

all: lint_ibuf sim_ibuf assert_labels

lint_ibuf:
	@echo "[linting]    ibuf"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ibuf $(IBUF_SRCS) $(VSILENCE)

sim_ibuf:
	@echo "[compiling]  tb_ibuf"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ibuf \
	  $(IBUF_SRCS) $(TB_DIR)/tb_ibuf.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ibuf/Vtb"
	$(Q)./$(VER_OUT)_ibuf/Vtb

# -- Every declared property is in the sim model (the ifu Makefile's
#    method, TD#144): verilate to C++ and look up ".<label>" for every
#    label of tb/ibuf_assert.sv. Fails on an absent or unlabeled one.
LABEL_RE := ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:
LABEL_RE := $(LABEL_RE)[[:space:]]*assert[[:space:]]+property
LABEL_FILE := $(TB_DIR)/ibuf_assert.sv

assert_labels:
	@echo "[checking]   assertion labels in the sim model"
	$(Q)a=$$(grep -cE 'assert[[:space:]]+property' $(LABEL_FILE)); \
	b=$$(grep -cE '$(LABEL_RE)' $(LABEL_FILE)); \
	if [ $$a -ne $$b ]; then \
	  echo "UNLABELED: $(LABEL_FILE) has $$((a-b)) unlabeled"; exit 1; fi
	$(Q)$(VERILATOR) --cc $(VER_FLAGS) $(SIM_EXTRA_FLAGS) $(COMMON) \
	  --top-module tb --Mdir $(VER_OUT)_labels_ibuf \
	  $(IBUF_SRCS) $(TB_DIR)/tb_ibuf.sv > /dev/null
	$(Q)n=0; m=0; \
	for l in $$(sed -nE 's/$(LABEL_RE).*/\1/p' $(LABEL_FILE)); do \
	  n=$$((n+1)); \
	  if ! grep -qF ".$$l\"" $(VER_OUT)_labels_ibuf/*.cpp; then \
	    echo "MISSING: $$l is not in the tb_ibuf model"; m=$$((m+1)); \
	  fi; \
	done; \
	echo "assert_labels: PASS=$$((n-m)) FAIL=$$m"; \
	test $$m -eq 0

clean:
	@echo "[cleaning]   ibuf"
	$(Q)rm -rf $(VER_OUT)*

# -- Regression plumbing (TOOLS-006) ----------------------------------
# tools/regress.sh runs every REGRESS_TARGETS entry with its own make
# call and fails if a target defined in this file is in neither list.
# Exclusions:
#   all                 - aggregate.
#   clean, regress_list - housekeeping and this plumbing.
REGRESS_TARGETS := lint_ibuf sim_ibuf assert_labels
REGRESS_EXCLUDE := all clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
