# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- the front-end demonstration testbench (DOC-001, DOC-009),
# planning/testbenches/fe_demo_tb_decisions.md
#
# TARGETS:
#
#   fdNN_<name>   one scenario (FDT-8): builds its model if needed, runs
#                 it, and writes out/fdNN_<name>/fdNN_<name>.fst (the
#                 waveform) and .log (the run's output, ending in its
#                 result line, FDT-10). Exits non-zero on a FAIL. The
#                 names are SCENARIOS below, in FD order
#   scenarios     every scenario in FD order (FDT-9); stops at the
#                 first FAIL. make -k scenarios runs them all
#   build         both simulation models only
#   scenario_list the scenarios, the 2-slot ones and the models, for
#                 tools/regress_demo.sh
#   clean         the models and out/
#   view S=<scenario>
#                 the scenario's waveform in Surfer with its command file
#                 waves/<scenario>.sucl (FDT-9a, FDT-12a): the signals in
#                 groups by unit, names of name type Unique, and the
#                 event markers of docs/<scenario>.md (FDT-12c)
#
# TWO BUILDS (DOC-006, Jeff session-081). The default model, OBJ, is
# built at NUM_PRED_SLOTS = 1; a second model, OBJ2, at the package
# default of 2. Each scenario runs on one of them: SCEN_2S at 2 slots,
# every other scenario at 1. A scenario's output is out/<scenario>/
# whichever model runs it.
#
# view runs the scenario first when its FST is missing or older than
# its model. Surfer is the one supported viewer (FDT-12). The variable
# SURFER names it, default $(RVA_ROOT)/tools/bin/surfer from rtl/Vars.mk,
# and the command line or the environment may set it; for example
# make view S=fd09_tage SURFER=surfer takes the surfer on PATH.
# SURFER_LOG, default warn, is Surfer's log level; SURFER_LOG=info gives
# its full output.
#
# THE DEMONSTRATION REGRESSION (FDT-2, FDT-2a, Jeff session-082). The
# scenarios are checked by tools/regress_demo.sh, not by tools/regress.sh,
# which scans rtl/ only. Run from the repository root, it builds each
# model once from the tree it runs in, runs every scenario of SCENARIOS
# on its model (scenario_list gives it the lists) and exits non-zero on a
# failing scenario not listed in tools/known_failures_demo.txt, which
# Jeff alone edits. It gates no push and records no pass. A DOC task that
# changes examples/fe_demo/ ends by running it; a failing scenario not
# listed blocks its Status: complete. A task that changes rtl/ runs it
# and reports each failing scenario; those do not block that task.
#
# EVENT CHECKS (FDT-10c, DOC-009). Each scenario checks the events of
# its description's Events table in its program, programs/fdNN_*.svh.
# waves/mk_sucl.py --svh writes the tables into each model's directory
# before the compile (EVT_TBL below), so the expected cycles are the
# descriptions'. The result line reports events checked <n> of <m>.
RVA_ROOT ?= $(abspath ../..)
include $(RVA_ROOT)/rtl/Vars.mk

ifeq ($(VERBOSE),1)
  Q        :=
  VSILENCE :=
else
  Q        := @
  VSILENCE := > /dev/null
  MAKEFLAGS := -s --no-print-directory
endif

.DEFAULT_GOAL := help

# -- Sources ----------------------------------------------------------
# THE fe_top SOURCE LIST, its RTL directories and the flags tb_fe_top's
# builds share, from rtl/core/frontend/fe_top/fe_top_srcs.mk (DOC-009),
# the fragment rtl/core/frontend/fe_top/Makefile also includes. The
# demonstration compiles the top and the walker, without tb_fe_top's
# bound properties (a demonstration checks no properties).
include $(RVA_ROOT)/rtl/core/frontend/fe_top/fe_top_srcs.mk

# The shared testbench models (FDT-4).
MODELS   := $(FE_TB_MODELS)

RTL_SRCS := $(FE_TOP_SRCS) $(FE_PTW_SRCS)

TB_TOP   := tb/tb_fe_demo.sv
# The runtime's $finish without its message (FDT-10a): see the file.
TB_CPP   := tb/fe_demo_finish.cpp
TB_INCS  := $(wildcard tb/*.svh) $(wildcard programs/*.svh) \
            $(wildcard $(MODELS)/*.svh)

# -- Flags --------------------------------------------------------------
# As tb_fe_top's, from fe_top_srcs.mk: FE_VER_FLAGS (-Wall less UNUSED
# and IMPORTSTAR, --timing), FE_SIM_FLAGS (DECLFILENAME for module tb)
# and FE_WAIVERS (VARHIDDEN for the loop_pred.sv parameters,
# SYNCASYNCNET for sram_init).
# --trace-fst for the waveform (FDT-11), --trace-structs so struct
# members appear by name. VL_USER_FINISH: the runtime's vl_finish is
# replaced by tb/fe_demo_finish.cpp's, which prints nothing (FDT-10a).
VER_FLAGS := $(FE_VER_FLAGS) $(FE_SIM_FLAGS) $(FE_WAIVERS) \
             --trace-fst --trace-structs -CFLAGS -DVL_USER_FINISH

# The two models. OBJ, the default, at one prediction slot: the macros
# tb_fe_top's _1slot targets pass, FE_SLOT1_DEFS (fe_top_srcs.mk);
# BP_EXPECT_PRED_SLOTS makes bp_defines_pkg check the count it builds.
# OBJ2 at two, the package default, with no macro.
SLOT1_FLAGS := $(FE_SLOT1_DEFS)
OBJ       := obj_fe_demo
OBJ2      := obj_fe_demo_2slot
VTB       := $(OBJ)/Vtb
VTB2      := $(OBJ2)/Vtb

FAST_INIT := $(FE_FAST_INIT)
# The runtime's end-of-run report off (FDT-10a).
QUIET     := +verilator+quiet

# The scenarios in FD order (fe_demo_scenarios.md FD-1 to FD-24).
SCENARIOS := fd01_reset_init fd02_steady fd03_two_branch \
             fd04_p2_override fd05_p3_override fd06_loop_pred \
             fd07_calls_returns fd08_indirect fd09_tage \
             fd10_pd_redirect fd11_be_mispredict fd12_training fd13_l1i \
             fd14_translation fd15_faults fd16_page_cross fd17_rvc \
             fd18_uncached fd19_fencei_cbo fd20_backpressure fd21_commit \
             fd22_sc_slot1 fd23_jump_cut fd24_call_slot1

# The scenarios that run on the 2-slot model, OBJ2 (Jeff, session-081):
# FD-3 and the three dual-slot scenarios. Every other scenario runs on
# OBJ, at one slot.
SCEN_2S   := fd03_two_branch fd22_sc_slot1 fd23_jump_cut fd24_call_slot1
SCEN_1S   := $(filter-out $(SCEN_2S),$(SCENARIOS))

# The model of scenario $(1).
vtb_of = $(if $(filter $(1),$(SCEN_2S)),$(VTB2),$(VTB))

# FD-1 runs the full init walk (FDT-7); every other scenario the fast
# init.
plusargs = $(if $(filter fd01_reset_init,$(1)),,$(FAST_INIT))

.PHONY: help build scenarios clean view scenario_list $(SCENARIOS)

help:
	@echo "make <scenario>   run one scenario on its model; out/<scenario>/"
	@echo "                  holds its waveform (.fst) and log"
	@echo "make scenarios    run all of them in FD order"
	@echo "make build        build both models only"
	@echo "make clean        remove the models and out/"
	@echo "make scenario_list"
	@echo "                  the scenarios, the 2-slot ones and the models,"
	@echo "                  for tools/regress_demo.sh"
	@echo "make view S=<scenario>"
	@echo "                  open the scenario's waveform in Surfer"
	@echo "                  (runs the scenario first if its FST is"
	@echo "                  missing or older than its model;"
	@echo "                  SURFER=$(SURFER) SURFER_LOG=$(SURFER_LOG))"
	@echo "scenarios (slots of the model each runs on):"
	@for s in $(SCENARIOS); do \
	  case " $(SCEN_2S) " in *" $$s "*) n=2;; *) n=1;; esac; \
	  printf "  %-20s %s\n" $$s $$n; done

build: $(VTB) $(VTB2)

DEPS := $(RTL_SRCS) $(TB_PKG_SRCS) $(TB_TOP) $(TB_INCS) $(TB_CPP)

# THE EVENT TABLE (FDT-10c, DOC-009). waves/mk_sucl.py --svh reads the
# Events table of every description and writes fe_demo_evt_tbl.svh, the
# expected cycle of each event check, into the model's directory, which
# the compile adds to its include path. A changed description rebuilds
# both models; one mk_sucl.py cannot read stops the build with the file
# and line.
EVT_TBL  := fe_demo_evt_tbl.svh
MK_SUCL  := waves/mk_sucl.py
EVT_DOCS := $(wildcard docs/fd[0-9][0-9]_*.md)

$(OBJ)/$(EVT_TBL) $(OBJ2)/$(EVT_TBL): $(EVT_DOCS) $(MK_SUCL)
	$(Q)mkdir -p $(@D)
	$(Q)python3 $(MK_SUCL) --svh $@

# One compile recipe for both models: $(1) the Mdir, $(2) the extra
# flags, $(3) the slot count for the message.
define compile
	@echo "[compiling]  tb_fe_demo, $(3) prediction slot(s)"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(2) --top-module tb --Mdir $(1) \
	  +incdir+$(MODELS) +incdir+tb +incdir+programs +incdir+$(1) \
	  $(RTL_SRCS) $(TB_PKG_SRCS) $(TB_TOP) $(abspath $(TB_CPP)) $(VSILENCE)
endef

$(VTB): $(DEPS) $(OBJ)/$(EVT_TBL)
	$(call compile,$(OBJ),$(SLOT1_FLAGS),1)

$(VTB2): $(DEPS) $(OBJ2)/$(EVT_TBL)
	$(call compile,$(OBJ2),,2)

# One scenario, on its model. The log keeps the run's whole output; the
# result line (FDT-10), with its continuation lines, is also printed
# here. The exit status is the simulation's.
define run_scen
	@echo "[running]    $@"
	$(Q)mkdir -p out/$@
	$(Q)./$(call vtb_of,$@) $(QUIET) $(call plusargs,$@) +SCEN=$@ \
	  +FST=out/$@/$@.fst > out/$@/$@.log 2>&1; rc=$$?; \
	  awk '/^-[IE]: $@: (PASS|FAIL),/ {p = 1; print; next} \
	       p && /^    / {print; next} {p = 0}' out/$@/$@.log; \
	  exit $$rc
endef

$(SCEN_1S): $(VTB)
	$(run_scen)

$(SCEN_2S): $(VTB2)
	$(run_scen)

# The scenarios are its prerequisites, run in FD order; make stops at
# the first FAIL, and make -k scenarios runs every one.
scenarios: $(SCENARIOS)

# For tools/regress_demo.sh (FDT-2): the scenarios in FD order, those on
# the 2-slot model, and the two models, one line each, so the script
# keeps no list of its own.
scenario_list:
	@echo "scenarios: $(SCENARIOS)"
	@echo "two_slot: $(SCEN_2S)"
	@echo "models: $(VTB) $(VTB2)"

clean:
	@echo "[cleaning]   fe_demo"
	$(Q)rm -rf $(OBJ) $(OBJ2) out

# -- Viewer (FDT-9a) ----------------------------------------------------
# view opens Surfer with the command file (FDT-12a, FDT-12c). It checks
# S, brings the scenario's model up to date, runs the scenario when its
# FST is missing or older than that model, then opens Surfer. A run that ends in
# a FAIL still writes its FST, so Surfer opens on it with a note.
# SURFER comes from rtl/Vars.mk, set there with ?= (FDT-9a); this
# Makefile does not set it.

# Surfer's log level, through RUST_LOG. Its default prints INFO lines
# (decoder and mapping search paths) on every start; warn keeps the
# warnings, e.g. a command in the .sucl it does not understand. Set
# SURFER_LOG=info for the full output. ?= lets the command line or the
# environment set it.
SURFER_LOG ?= warn
SLOG        = RUST_LOG=$(SURFER_LOG)

view_fst = out/$(S)/$(S).fst
view_vtb = $(call vtb_of,$(S))

view:
	@if [ -z "$(S)" ]; then \
	  echo "usage: make $@ S=<scenario>   (make help lists the scenarios)"; \
	  exit 1; \
	fi
	@if [ "$(words $(S))" != 1 ] || [ -z "$(filter $(S),$(SCENARIOS))" ]; \
	then \
	  echo "$(S) is not a scenario; the scenarios are:"; \
	  for s in $(SCENARIOS); do echo "  $$s"; done; \
	  exit 1; \
	fi
	$(Q)$(MAKE) $(view_vtb)
	@if [ ! -f $(view_fst) ] || [ $(view_fst) -ot $(view_vtb) ]; then \
	  $(MAKE) $(S) || echo "[note]       $(S) did not pass; opening its FST"; \
	fi
	@test -f $(view_fst) || { echo "no waveform $(view_fst)"; exit 1; }
	@echo "[viewing]    $(S) in $(SURFER)"
	$(Q)$(SLOG) $(SURFER) $(view_fst) -c waves/$(S).sucl
