# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- the front-end demonstration testbench (DOC-001),
# planning/testbenches/fe_demo_tb_decisions.md
#
# TARGETS:
#
#   fdNN_<name>   one scenario (FDT-8): builds if needed, runs it, and
#                 writes out/fdNN_<name>/fdNN_<name>.fst (the waveform)
#                 and .log (the run's output, ending in its result line,
#                 FDT-10). Exits non-zero on a FAIL. The names are
#                 SCENARIOS below, in FD order
#   scenarios     every scenario in FD order (FDT-9); stops at the
#                 first FAIL. make -k scenarios runs them all
#   build         the simulation model only
#   clean         the model and out/
#   view S=<scenario>
#                 the scenario's waveform in Surfer with its command file
#                 waves/<scenario>.sucl (FDT-9a, FDT-12a): the signals in
#                 groups by unit, names of name type Unique, and the
#                 event markers of docs/<scenario>.md (FDT-12c)
#
# view runs the scenario first when its FST is missing or older than the
# model. Surfer is the one supported viewer (FDT-12). The variable SURFER
# names it, default $(HOME)/.cargo/bin/surfer from rtl/Vars.mk, and the
# command line or the environment may set it; for example
# make view S=fd09_tage SURFER=surfer takes the surfer on PATH.
# SURFER_LOG, default warn, is Surfer's log level; SURFER_LOG=info gives
# its full output.
#
# NOT A REGRESSION (FDT-2): tools/regress.sh scans rtl/ only, and
# nothing here is in it.
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
# THE fe_top SOURCE LIST, as rtl/core/frontend/fe_top/Makefile gives it
# for tb_fe_top less the bound properties (a demonstration checks no
# properties). Kept in step with that Makefile by hand.
FE_DIR   := $(RVA_ROOT)/rtl/core/frontend
FE_TOP   := $(FE_DIR)/fe_top
BPU_DIR  := $(FE_DIR)/bpu/rtl
FTQ_DIR  := $(FE_DIR)/ftq/rtl
IFU_DIR  := $(FE_DIR)/ifu/rtl
IBUF_DIR := $(FE_DIR)/ibuf/rtl
DEC_DIR  := $(FE_DIR)/decode/rtl
L1I_DIR  := $(FE_DIR)/icache/rtl
COMP_DIR := $(RVA_ROOT)/rtl/lib/rtl
ITLB_DIR := $(RVA_ROOT)/rtl/mmu/itlb/rtl
PMP_DIR  := $(RVA_ROOT)/rtl/mmu/pmp/rtl
PTW_DIR  := $(RVA_ROOT)/rtl/mmu/ptw/rtl
CSR_DIR  := $(RVA_ROOT)/rtl/core/csr

# The shared testbench models (FDT-4).
MODELS   := $(FE_TOP)/tb/models

PKG_SRCS := \
  $(BPU_DIR)/bp_defines_pkg.sv \
  $(BPU_DIR)/bp_structs_pkg.sv \
  $(DEC_DIR)/decode_pkg.sv \
  $(CSR_DIR)/rtl/csr_pkg.sv

TB_PKG_SRCS := $(CSR_DIR)/tb/csr_tb_pkg.sv

L1I_SRCS := \
  $(L1I_DIR)/cgen_tl_pkg.sv \
  $(L1I_DIR)/l1i_pkg.sv \
  $(L1I_DIR)/l1i_core_slv.sv \
  $(L1I_DIR)/l1i_mem_mst.sv \
  $(L1I_DIR)/l1i_meta_array.sv \
  $(L1I_DIR)/l1i_data_array.sv \
  $(L1I_DIR)/l1i_ctrl.sv \
  $(L1I_DIR)/l1i_bank.sv \
  $(L1I_DIR)/l1i_mshr.sv \
  $(L1I_DIR)/l1i_maint.sv \
  $(L1I_DIR)/l1i.sv

BPU_SRCS := \
  $(COMP_DIR)/bw_ram.sv \
  $(COMP_DIR)/sram_init.sv \
  $(BPU_DIR)/bp_history.sv \
  $(BPU_DIR)/ubtb.sv \
  $(BPU_DIR)/loop_pred.sv \
  $(BPU_DIR)/ftb_array.sv \
  $(BPU_DIR)/ftb_plru.sv \
  $(BPU_DIR)/ftb_cntrl.sv \
  $(BPU_DIR)/ftb.sv \
  $(BPU_DIR)/tage_bim.sv \
  $(BPU_DIR)/tage_table.sv \
  $(BPU_DIR)/tage_cntrl.sv \
  $(BPU_DIR)/tage_arb.sv \
  $(BPU_DIR)/tage.sv \
  $(BPU_DIR)/ittage_table.sv \
  $(BPU_DIR)/ittage_cntrl.sv \
  $(BPU_DIR)/ittage_arb.sv \
  $(BPU_DIR)/ittage.sv \
  $(BPU_DIR)/sc_table.sv \
  $(BPU_DIR)/sc_brimli.sv \
  $(BPU_DIR)/sc_cntrl.sv \
  $(BPU_DIR)/sc.sv \
  $(BPU_DIR)/ras.sv \
  $(BPU_DIR)/bp_cluster.sv

FTQ_SRCS := \
  $(FTQ_DIR)/ftq_ptr.sv \
  $(FTQ_DIR)/ftq_commit.sv \
  $(FTQ_DIR)/ftq_entry.sv \
  $(FTQ_DIR)/ftq_meta.sv \
  $(FTQ_DIR)/ftq_status.sv \
  $(FTQ_DIR)/ftq_shadow.sv \
  $(FTQ_DIR)/ftq_npc.sv \
  $(FTQ_DIR)/ftq_ifu.sv \
  $(FTQ_DIR)/ftq_resolve.sv \
  $(FTQ_DIR)/ftq_upd_conv.sv \
  $(FTQ_DIR)/ftq_ftb_sched.sv \
  $(FTQ_DIR)/ftq.sv

IFU_SRCS := \
  $(IFU_DIR)/ifu_xlate.sv \
  $(IFU_DIR)/ifu_lbuf.sv \
  $(IFU_DIR)/ifu_fetch.sv \
  $(IFU_DIR)/ifu_rvc_exp.sv \
  $(IFU_DIR)/ifu_predecode.sv \
  $(IFU_DIR)/ifu_f3.sv \
  $(IFU_DIR)/ifu_wb.sv \
  $(IFU_DIR)/ifu_maint.sv \
  $(IFU_DIR)/ifu.sv

RTL_SRCS := $(PKG_SRCS) $(L1I_SRCS) $(BPU_SRCS) $(FTQ_SRCS) $(IFU_SRCS) \
            $(IBUF_DIR)/ibuf.sv $(PMP_DIR)/pmp_pma_chk.sv \
            $(ITLB_DIR)/itlb.sv $(DEC_DIR)/instr_decoder.sv \
            $(FE_TOP)/rtl/fe_top.sv $(PTW_DIR)/ptw.sv

TB_TOP   := tb/tb_fe_demo.sv
# The runtime's $finish without its message (FDT-10a): see the file.
TB_CPP   := tb/fe_demo_finish.cpp
TB_INCS  := $(wildcard tb/*.svh) $(wildcard programs/*.svh) \
            $(wildcard $(MODELS)/*.svh)

# -- Flags --------------------------------------------------------------
# As tb_fe_top's (rtl/core/frontend/fe_top/Makefile): -Wall less
# UNUSED and IMPORTSTAR, DECLFILENAME for module tb, VARHIDDEN for the
# loop_pred.sv parameters, SYNCASYNCNET for sram_init. NUM_PRED_SLOTS
# is 2, the package default; there is no 1-slot build (FDT-5).
# --trace-fst for the waveform (FDT-11), --trace-structs so struct
# members appear by name. VL_USER_FINISH: the runtime's vl_finish is
# replaced by tb/fe_demo_finish.cpp's, which prints nothing (FDT-10a).
VER_FLAGS := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR -Wno-DECLFILENAME \
             -Wno-VARHIDDEN -Wno-SYNCASYNCNET --timing \
             --trace-fst --trace-structs -CFLAGS -DVL_USER_FINISH
OBJ       := obj_fe_demo
VTB       := $(OBJ)/Vtb

FAST_INIT := +TAGE_FAST_INIT=1 +ITTAGE_FAST_INIT=1 +SC_FAST_INIT=1
# The runtime's end-of-run report off (FDT-10a).
QUIET     := +verilator+quiet

# The scenarios in FD order (fe_demo_scenarios.md FD-1 to FD-21).
SCENARIOS := fd01_reset_init fd02_steady fd03_two_branch \
             fd04_p2_override fd05_p3_override fd06_loop_pred \
             fd07_calls_returns fd08_indirect fd09_tage \
             fd10_pd_redirect fd11_be_mispredict fd12_training fd13_l1i \
             fd14_translation fd15_faults fd16_page_cross fd17_rvc \
             fd18_uncached fd19_fencei_cbo fd20_backpressure fd21_commit

# FD-1 runs the full init walk (FDT-7); every other scenario the fast
# init.
plusargs = $(if $(filter fd01_reset_init,$(1)),,$(FAST_INIT))

.PHONY: help build scenarios clean view $(SCENARIOS)

help:
	@echo "make <scenario>   run one scenario; out/<scenario>/ holds its"
	@echo "                  waveform (.fst) and log"
	@echo "make scenarios    run all of them in FD order"
	@echo "make build        build the model only"
	@echo "make clean        remove the model and out/"
	@echo "make view S=<scenario>"
	@echo "                  open the scenario's waveform in Surfer"
	@echo "                  (runs the scenario first if its FST is"
	@echo "                  missing or older than the model;"
	@echo "                  SURFER=$(SURFER) SURFER_LOG=$(SURFER_LOG))"
	@echo "scenarios:"
	@for s in $(SCENARIOS); do echo "  $$s"; done

build: $(VTB)

$(VTB): $(RTL_SRCS) $(TB_PKG_SRCS) $(TB_TOP) $(TB_INCS) $(TB_CPP)
	@echo "[compiling]  tb_fe_demo"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) --top-module tb --Mdir $(OBJ) \
	  +incdir+$(MODELS) +incdir+tb +incdir+programs \
	  $(RTL_SRCS) $(TB_PKG_SRCS) $(TB_TOP) $(abspath $(TB_CPP)) $(VSILENCE)

# One scenario. The log keeps the run's whole output; the result line
# (FDT-10), with its continuation lines, is also printed here. The exit
# status is the simulation's.
$(SCENARIOS): $(VTB)
	@echo "[running]    $@"
	$(Q)mkdir -p out/$@
	$(Q)./$(VTB) $(QUIET) $(call plusargs,$@) +SCEN=$@ \
	  +FST=out/$@/$@.fst > out/$@/$@.log 2>&1; rc=$$?; \
	  awk '/^-[IE]: $@: (PASS|FAIL),/ {p = 1; print; next} \
	       p && /^    / {print; next} {p = 0}' out/$@/$@.log; \
	  exit $$rc

# The scenarios are its prerequisites, run in FD order; make stops at
# the first FAIL, and make -k scenarios runs every one.
scenarios: $(SCENARIOS)

clean:
	@echo "[cleaning]   fe_demo"
	$(Q)rm -rf $(OBJ) out

# -- Viewer (FDT-9a) ----------------------------------------------------
# view opens Surfer with the command file (FDT-12a, FDT-12c). It checks
# S, brings the model up to date, runs the scenario when its FST is
# missing or older than the model, then opens Surfer. A run that ends in
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
	$(Q)$(MAKE) build
	@if [ ! -f $(view_fst) ] || [ $(view_fst) -ot $(VTB) ]; then \
	  $(MAKE) $(S) || echo "[note]       $(S) did not pass; opening its FST"; \
	fi
	@test -f $(view_fst) || { echo "no waveform $(view_fst)"; exit 1; }
	@echo "[viewing]    $(S) in $(SURFER)"
	$(Q)$(SLOG) $(SURFER) $(view_fst) -c waves/$(S).sucl
