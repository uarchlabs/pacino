# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- the performance harness and its trace tools (PERF-002,
# planning/perf/perf_decisions.md PF-2 to PF-20). Run from the
# repository root as make -C perf <target>.
#
# TARGETS:
#   all          the trace tools, pt_gen and the harness at head
#   tools        build/trace_count, build/veneer
#   pt_gen       build/pt_gen/Vpt_gen, the PF-17 generator
#                (rtl/mmu/ptw/tb/pt_gen.sv), built here so that no
#                build output lands under rtl/
#   harness      the Verilated wrapper and the C++ gasket,
#                build/<NAME>/perf_fe, from the RTL under SRC_ROOT
#   clean        remove build/
#
# THE REVISION (PF-5, PF-10). SRC_ROOT is the source root whose RTL is
# built: the repository itself by default (head), or the checkout of a
# release tag, or any copy of the tree. NAME names the build directory
# (default head). The build records SRC_ROOT and its git sha, read by
# one read-only call, git -C SRC_ROOT rev-parse HEAD, or "unversioned"
# when SRC_ROOT is not a git work tree. Each run writes them to its
# CSV row (PF-9).
#
# NUM_PRED_SLOTS (BP-128): SLOTS=2 (default) or 1, the
# bp_defines_pkg build knob BP_NUM_PRED_SLOTS.
#
# A performance run gates no push (PF-9): nothing here is in
# tools/regress.sh, which reads only Makefiles under rtl/.

RVA_ROOT ?= $(abspath ..)
include $(RVA_ROOT)/rtl/Vars.mk

SRC_ROOT ?= $(RVA_ROOT)
NAME     ?= head
SLOTS    ?= 2
# The build's -j: 75% of the hardware threads, at least 1 (PF-22).
JOBS     ?= $(shell n=$$(( $$(nproc) * 3 / 4 )); [ $$n -ge 1 ] || n=1; \
              echo $$n)

ifeq ($(VERBOSE),1)
  Q        :=
  VSILENCE :=
else
  Q        := @
  VSILENCE := > /dev/null
  MAKEFLAGS += -s --no-print-directory
endif

BUILD   := build
CXX     ?= g++
CXXOPT  := -O2 -std=c++17 -Wall -Wextra
PERFSRC := src

.DEFAULT_GOAL := all
.PHONY: all tools pt_gen harness clean

all: tools pt_gen harness

# -- the trace tools ----------------------------------------------------
TOOL_COMMON := $(PERFSRC)/cbp_trace.cc
TOOL_HDRS   := $(PERFSRC)/cbp_trace.h $(PERFSRC)/perf_util.h

tools: $(BUILD)/trace_count $(BUILD)/veneer

$(BUILD)/trace_count: $(PERFSRC)/trace_count.cc $(TOOL_COMMON) $(TOOL_HDRS)
	@mkdir -p $(BUILD)
	@echo "[compiling]  $@"
	$(Q)$(CXX) $(CXXOPT) -o $@ $(PERFSRC)/trace_count.cc $(TOOL_COMMON) \
	  -lz -pthread

$(BUILD)/veneer: $(PERFSRC)/veneer.cc $(TOOL_COMMON) $(TOOL_HDRS)
	@mkdir -p $(BUILD)
	@echo "[compiling]  $@"
	$(Q)$(CXX) $(CXXOPT) -o $@ $(PERFSRC)/veneer.cc $(TOOL_COMMON) \
	  -lz -pthread

# -- pt_gen (PF-17), the rtl/mmu/ptw build_pt_gen recipe into build/ ----
PTW_TB   := $(RVA_ROOT)/rtl/mmu/ptw/tb
PKG_SRCS := \
  $(RVA_ROOT)/rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv \
  $(RVA_ROOT)/rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv \
  $(RVA_ROOT)/rtl/core/frontend/decode/rtl/decode_pkg.sv \
  $(RVA_ROOT)/rtl/core/csr/rtl/csr_pkg.sv
GEN_FLAGS := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing \
             -Wno-DECLFILENAME -Wno-SYNCASYNCNET

pt_gen: $(BUILD)/pt_gen/Vpt_gen

$(BUILD)/pt_gen/Vpt_gen: $(PTW_TB)/pt_gen.sv $(PTW_TB)/pt_build_pkg.sv
	@echo "[compiling]  pt_gen"
	$(Q)$(VERILATOR) --binary $(GEN_FLAGS) --top-module pt_gen \
	  --Mdir $(BUILD)/pt_gen $(PKG_SRCS) $(PTW_TB)/pt_build_pkg.sv \
	  $(PTW_TB)/pt_gen.sv $(VSILENCE)

# -- the harness (PF-3) -------------------------------------------------
# The RTL source list is SRC_ROOT's own fe_top_srcs.mk, read with
# RVA_ROOT set to SRC_ROOT, so that a revision builds from its own tree.
PERF_ROOT  := $(RVA_ROOT)
RVA_ROOT   := $(SRC_ROOT)
include $(SRC_ROOT)/rtl/core/frontend/fe_top/fe_top_srcs.mk
RVA_ROOT   := $(PERF_ROOT)

# The one read-only git call of the build: the revision's sha.
SRC_SHA := $(shell git -C $(SRC_ROOT) rev-parse HEAD 2>/dev/null || \
             echo unversioned)

HDIR      := $(BUILD)/$(NAME)_s$(SLOTS)
HBIN      := $(HDIR)/perf_fe
HSRC      := $(PERFSRC)/harness
SLOT_DEFS := $(if $(filter 1,$(SLOTS)),$(FE_SLOT1_DEFS))
H_VFLAGS  := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --no-timing \
             $(FE_WAIVERS) $(FE_SIM_FLAGS) $(SLOT_DEFS) -O3 \
             --x-assign fast --x-initial fast
H_CFLAGS  := -O2 -std=c++17 -DPERF_SRC_ROOT=\\\"$(SRC_ROOT)\\\" \
             -DPERF_SRC_SHA=\\\"$(SRC_SHA)\\\" \
             -DPERF_BUILD_NAME=\\\"$(NAME)\\\" -DPERF_SLOTS=$(SLOTS)
H_CXX     := $(abspath $(HSRC)/perf_fe.cc) $(abspath $(HSRC)/supply.cc) \
             $(abspath $(PERFSRC)/cbp_trace.cc)
H_DEPS    := $(wildcard $(HSRC)/*.cc $(HSRC)/*.h $(HSRC)/*.vlt) \
             $(TOOL_COMMON) $(TOOL_HDRS) sv/perf_top.sv sv/perf.vlt \
             $(FE_TOP_SRCS) $(FE_PTW_SRCS)

harness: $(HBIN)

$(HBIN): $(H_DEPS)
	@echo "[compiling]  $(HBIN) from $(SRC_ROOT) ($(SRC_SHA))"
	$(Q)$(VERILATOR) --cc --exe --build -j $(JOBS) $(H_VFLAGS) \
	  --top-module perf_top --Mdir $(HDIR) -o perf_fe \
	  -CFLAGS "$(H_CFLAGS) -I$(abspath $(PERFSRC))" -LDFLAGS -lz \
	  sv/perf.vlt $(FE_TOP_SRCS) $(FE_PTW_SRCS) $(CSR_DIR)/tb/csr_tb_pkg.sv \
	  sv/perf_top.sv $(H_CXX) $(VSILENCE)

clean:
	@echo "[cleaning]   perf"
	$(Q)rm -rf $(BUILD)
