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
#                build/<NAME>_s<SLOTS>/perf_fe, from the RTL under
#                SRC_ROOT
#   digest       print the build stamp of the trees as they stand (the
#                sha, the dirty mark, the input digest), building nothing
#   clean        remove build/
#
# THE REVISION (PF-5, PF-10). SRC_ROOT is the source root whose RTL is
# built: the repository itself by default (head), or the checkout of a
# release tag, or any copy of the tree. NAME names the build directory
# (default head).
#
# THE BUILD STAMP (PERF-004, TD#210; src/stamp.py). Every make of the
# harness writes build/<NAME>_s<SLOTS>/perf_stamp.h, the header the
# harness includes, and perf_inputs.txt beside it, each only when its
# text changes; the binary depends on the header. It holds:
#   - the sha of SRC_ROOT (git -C SRC_ROOT rev-parse HEAD), or
#     "unversioned";
#   - the dirty mark: "clean", or "dirty:" and the areas with tracked
#     changes or untracked files, rtl (SRC_ROOT's rtl/) and perf (this
#     tree's perf/), from git status --porcelain;
#   - THE INPUT DIGEST, the SHA-256 over every build input in a fixed
#     order (H_INPUTS: the harness sources, the wrapper, every RTL file
#     and package Verilated, this Makefile and the makefiles it reads),
#     the make variables that reach the build (STAMP_VARS) and the tool
#     versions. perf_inputs.txt is the manifest it is taken over.
# These are the build's only git calls, both read-only. Each run writes
# the three to its CSV row (PF-9). make digest prints them for the trees
# as they stand, so that a tree's digest can be compared with a
# baseline's rows without a build.
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
# BP-153: RAS_COMMIT_ENTRIES of the SRC_ROOT tree, for the RAS
# classification's commit-stack model (ras_class.h). 64 at head since
# BP-153.
RAS_COMMIT ?= 64
# BP-153: and its RAS_SPEC_ENTRIES (16 at head: BP-153's 32, RC11, was
# reverted by BP-154).
RAS_SPEC   ?= 16
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
.PHONY: all tools pt_gen harness twin digest clean FORCE

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

HDIR      := $(BUILD)/$(NAME)_s$(SLOTS)
HBIN      := $(HDIR)/perf_fe
HSRC      := $(PERFSRC)/harness
SLOT_DEFS := $(if $(filter 1,$(SLOTS)),$(FE_SLOT1_DEFS))
H_VFLAGS  := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --no-timing \
             $(FE_WAIVERS) $(FE_SIM_FLAGS) $(SLOT_DEFS) -O3 \
             --x-assign fast --x-initial fast
# The sha, the dirty mark and the digest come from the stamp header in
# HDIR (THE BUILD STAMP), not from a define.
H_COPT    := -O2 -std=c++17
H_CFLAGS  := $(H_COPT) -DPERF_SRC_ROOT=\\\"$(SRC_ROOT)\\\" \
             -DPERF_BUILD_NAME=\\\"$(NAME)\\\" -DPERF_SLOTS=$(SLOTS) \
             -DPERF_RAS_COMMIT=$(RAS_COMMIT) -DPERF_RAS_SPEC=$(RAS_SPEC)
H_CXX     := $(abspath $(HSRC)/perf_fe.cc) $(abspath $(HSRC)/supply.cc) \
             $(abspath $(PERFSRC)/cbp_trace.cc)
# The SystemVerilog the build Verilates, in command-line order.
H_SV      := sv/perf.vlt $(FE_TOP_SRCS) $(FE_PTW_SRCS) \
             $(CSR_DIR)/tb/csr_tb_pkg.sv sv/perf_top.sv
# PERF-004: csr_tb_pkg.sv is Verilated and was not a dependency, so a
# change to it rebuilt nothing; it is now (in H_SV).
H_DEPS    := $(sort $(wildcard $(HSRC)/*.cc $(HSRC)/*.h $(HSRC)/*.vlt)) \
             $(TOOL_COMMON) $(TOOL_HDRS) $(H_SV)

# ---- THE BUILD STAMP (PERF-004, TD#210; see the header) ---------------
STAMP_PY  := $(PERFSRC)/stamp.py
STAMP_H   := $(HDIR)/perf_stamp.h
STAMP_MAN := $(HDIR)/perf_inputs.txt
# Every input, in the order the digest takes them: H_DEPS, then the
# makefiles that set the build (this one, rtl/Vars.mk, SRC_ROOT's
# fe_top_srcs.mk) and the stamp script itself.
H_INPUTS  := $(H_DEPS) Makefile $(PERF_ROOT)/rtl/Vars.mk \
             $(SRC_ROOT)/rtl/core/frontend/fe_top/fe_top_srcs.mk $(STAMP_PY)
# The make variables that reach the build, and the tools.
STAMP_VARS := --var "SLOTS=$(SLOTS)" --var "RAS_SPEC=$(RAS_SPEC)" \
              --var "RAS_COMMIT=$(RAS_COMMIT)" --var "H_VFLAGS=$(H_VFLAGS)" \
              --var "H_COPT=$(H_COPT)" --var "LDFLAGS=-lz" \
              --tool "verilator=$(VERILATOR) --version" \
              --tool "cxx=$(CXX) --version"
STAMP_RUN := python3 $(STAMP_PY) --src-root $(SRC_ROOT) \
             --perf-root $(PERF_ROOT) $(STAMP_VARS)

harness: $(HBIN)

# Rewritten only when the stamp changes (stamp.py), so FORCE runs the
# script every time and the binary rebuilds only on a change.
$(STAMP_H): FORCE
	@mkdir -p $(HDIR)
	$(Q)$(STAMP_RUN) --header $@ --manifest $(STAMP_MAN) $(H_INPUTS)

FORCE:

$(HBIN): $(H_DEPS) $(STAMP_H)
	@echo "[compiling]  $(HBIN) from $(SRC_ROOT)"
	$(Q)$(VERILATOR) --cc --exe --build -j $(JOBS) $(H_VFLAGS) \
	  --top-module perf_top --Mdir $(HDIR) -o perf_fe \
	  -CFLAGS "$(H_CFLAGS) -I$(abspath $(PERFSRC)) -I$(abspath $(HDIR))" \
	  -LDFLAGS -lz $(H_SV) $(H_CXX) $(VSILENCE)
	$(Q)$(HBIN) --stamp

# ---- THE TWIN (PERF-005 Phase 4) --------------------------------------
# pacino's TAGE alone as a CBP2025 predictor (perf/src/twin). Built from
# a COPY of tools/cbp2025's framework (lib, scripts, Makefile, cbp.h) in
# build/twin_cbp, never in the submodule: bin/cbp.pacino_twin there.
TWIN_DIR := $(BUILD)/twin_cbp
TWIN_CBP := $(RVA_ROOT)/tools/cbp2025
twin:
	@mkdir -p $(TWIN_DIR)/entries/pacino_twin
	$(Q)rsync -a --exclude '*.o' --exclude '*.a' $(TWIN_CBP)/lib \
	  $(TWIN_CBP)/scripts $(TWIN_CBP)/Makefile $(TWIN_CBP)/cbp.h $(TWIN_DIR)/
	$(Q)cp $(PERFSRC)/twin/cond_branch_predictor_interface.cc \
	  $(PERFSRC)/twin/sources.mk $(TWIN_DIR)/entries/pacino_twin/
	$(Q)$(MAKE) -C $(TWIN_DIR) ENTRY=pacino_twin \
	  TWIN_INC="-I$(abspath $(PERFSRC)/twin) -I$(abspath $(HSRC))"

# The stamp of the trees as they stand, with no build (TD#210): compare
# it with a baseline row's sha, dirty and input_digest.
digest:
	$(Q)$(STAMP_RUN) --print $(H_INPUTS)

clean:
	@echo "[cleaning]   perf"
	$(Q)rm -rf $(BUILD)
