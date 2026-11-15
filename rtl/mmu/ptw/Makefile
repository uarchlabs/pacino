# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- page table walker (BP-123), mmu_decisions.md
#
# TARGETS:
#
#   lint_ptw        the walker with its PMP / PMA checker (MMU-10a,
#                   MMU-10d)
#   lint_pt_build_pkg  tb/pt_build_pkg.sv, the page-table builder
#                   (BP-146)
#   sim_ptw         tb/tb_ptw.sv, with tb/ptw_assert.sv bound in, at
#                   the knob's mode (PT_MODE, BP-149)
#   assert_labels   every property of tb/ptw_assert.sv is in the sim
#                   model (the itlb Makefile's method)
#   sim_pt_gen      tb/pt_gen.sv, the trace page-table generator of
#                   perf_decisions.md PF-17 (BP-149), run on the
#                   checked-in sample tb/pt_gen_sample.txt; it writes
#                   the image obj_gen/pt_gen_sample.img
#   sim_ptw_img     THE IMAGE CHECK (BP-149): tb_ptw +IMG loads that
#                   image into its memory model, sets satp from its
#                   header and walks every mapped page with the walker,
#                   checking the PA and the leaf against the map lines
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

# pt_build_pkg (BP-146): the page-table builder every BP-146 case uses.
TB_PKG_SRCS := $(CSR_DIR)/tb/csr_tb_pkg.sv $(TB_DIR)/pt_build_pkg.sv

PTW_SRCS := $(PKG_SRCS) $(PMP_DIR)/pmp_pma_chk.sv $(RTL_DIR)/ptw.sv
SIM_SRCS := $(PTW_SRCS) $(TB_DIR)/ptw_assert.sv

.PHONY: all clean assert_labels lint_ptw lint_pt_build_pkg sim_ptw \
        build_ptw build_pt_gen sim_pt_gen sim_ptw_img

all: lint_ptw lint_pt_build_pkg sim_ptw assert_labels sim_ptw_img

lint_ptw:
	@echo "[linting]    ptw"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ptw $(PTW_SRCS) $(VSILENCE)

# Testbench code: SIM_EXTRA_FLAGS, since its classes, pt_image and
# pt_stage, are not named for the file (rtl/CLAUDE.md, DECLFILENAME).
lint_pt_build_pkg:
	@echo "[linting]    pt_build_pkg"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) $(PKG_SRCS) $(TB_DIR)/pt_build_pkg.sv $(VSILENCE)

# THE KNOB (BP-149, PROJECT_CORE.md TRANSLATION MODES): PT_MODE=sv39,
# sv48 or sv57 reaches tb_ptw as +PT_MODE; empty, the testbench's own
# default, sv57. tools/regress.sh passes none; tools/regress_weekly.sh
# runs the weekly targets below at each mode.
PT_MODE ?=
PT_ARG  := $(if $(strip $(PT_MODE)),+PT_MODE=$(strip $(PT_MODE)))

build_ptw:
	@echo "[compiling]  tb_ptw"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ptw \
	  $(SIM_SRCS) $(TB_PKG_SRCS) $(TB_DIR)/tb_ptw.sv $(VSILENCE)

sim_ptw: build_ptw
	@echo "[simulating] $(VER_OUT)_ptw/Vtb $(PT_ARG)"
	$(Q)./$(VER_OUT)_ptw/Vtb $(PT_ARG)

# THE GENERATOR (BP-149, perf_decisions.md PF-17). A testbench program
# on pt_build_pkg; SIM_EXTRA_FLAGS for the package's classes, as
# lint_pt_build_pkg.
GEN_OUT    := $(VER_OUT)_gen
GEN_SAMPLE := $(TB_DIR)/pt_gen_sample.txt
GEN_IMG    := $(GEN_OUT)/pt_gen_sample.img

build_pt_gen:
	@echo "[compiling]  pt_gen"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module pt_gen --Mdir $(GEN_OUT) \
	  $(PKG_SRCS) $(TB_DIR)/pt_build_pkg.sv $(TB_DIR)/pt_gen.sv $(VSILENCE)

sim_pt_gen: build_pt_gen
	@echo "[generating] $(GEN_IMG) from $(GEN_SAMPLE)"
	$(Q)./$(GEN_OUT)/Vpt_gen +IN=$(GEN_SAMPLE) +OUT=$(GEN_IMG)

# THE IMAGE CHECK. The image is Sv57 by PF-17, so the knob does not
# reach it.
sim_ptw_img: build_ptw sim_pt_gen
	@echo "[simulating] $(VER_OUT)_ptw/Vtb +IMG=$(GEN_IMG)"
	$(Q)./$(VER_OUT)_ptw/Vtb +IMG=$(GEN_IMG)

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
#   build_ptw, build_pt_gen - the compile steps the sim targets run
#                         first (BP-149).
#   clean, regress_list - housekeeping and this plumbing.
REGRESS_TARGETS := lint_ptw lint_pt_build_pkg sim_ptw assert_labels \
                   sim_pt_gen sim_ptw_img
REGRESS_EXCLUDE := all build_ptw build_pt_gen clean regress_list
# BP-149: the targets that translate under the knob, which
# tools/regress_weekly.sh runs at every PT_MODE. sim_ptw_img is Sv57 by
# PF-17 and is not one. tools/regress.sh reads only the test: and
# exclude: lines.
REGRESS_WEEKLY  := sim_ptw

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
	@echo "weekly: $(REGRESS_WEEKLY)"
