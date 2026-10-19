# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- branch predictor cluster
# Targets: lint, sim, all (default), clean
include $(RVA_ROOT)/rtl/Vars.mk

##VERILATOR=/usr/local/bin/verilator
#VERILATOR=/home/jeff/Development/jeffnye-gh/pacino/tools/bin/verilator

ifeq ($(VERBOSE),1)
  Q        :=
  VSILENCE :=
else
  Q        := @
  VSILENCE := > /dev/null
  MAKEFLAGS := -s --no-print-directory
endif

JOBS ?= 1

# BP-122: no target leaves a file outside an obj_* build directory.
# sim builds into $(VER_OUT) and removes it after the run (the obj_*
# directories of the other targets are kept for incremental builds).
# sim_tage_manual writes waves.fst, which surf.sh opens, only when
# asked: make sim_tage_manual FST=1.
FST ?= 0

.DEFAULT_GOAL := all

RTL_DIR  := rtl
TB_DIR   := tb
COMP_DIR := ../../../lib/rtl
# SYS-001: the testbenches of modules with config ports (sc, ittage,
# ittage_cntrl, tage, ftb, bp_cluster) drive them from csr_tb_pkg
# (csr_decisions.md CSR-2), over csr_pkg and the decode_pkg it uses.
CSR_TB_SRCS := ../decode/rtl/decode_pkg.sv ../../csr/rtl/csr_pkg.sv \
               ../../csr/tb/csr_tb_pkg.sv
VER_OUT  := obj

# -- Slot count (BP-128, TD#1) -------------------------------------
# NUM_PRED_SLOTS is set in bp_defines_pkg.sv from the macro
# BP_NUM_PRED_SLOTS, 2 when it is not defined. SLOT_DEFS is empty for
# every target below, so each builds at 2. Each <target>_1slot (end of
# file) runs <target> in a sub-make with SLOT_DEFS = SLOT1_DEFS and
# VER_OUT = $(VER_OUT)_1slot, so a 1-slot build never shares an object
# directory with a 2-slot one. BP_EXPECT_PRED_SLOTS=1 makes the package
# stop elaboration unless NUM_PRED_SLOTS is 1, so a 1-slot target fails
# if BP_NUM_PRED_SLOTS does not reach it. To see that, build one with
# the slot macro removed:
#   make lint_bp_cluster_1slot SLOT1_DEFS=+define+BP_EXPECT_PRED_SLOTS=1
SLOT1_DEFS := +define+BP_NUM_PRED_SLOTS=1 +define+BP_EXPECT_PRED_SLOTS=1
SLOT_DEFS  ?=

VER_FLAGS       := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing \
                   $(SLOT_DEFS)
SIM_EXTRA_FLAGS := -Wno-DECLFILENAME

.PHONY: all lint sim sim_history sim_ubtb lint_loop_pred sim_loop_pred \
        lint_tage_table sim_tage_table \
        lint_sc_table sim_sc_table sim_sc_table_fast \
        lint_sc_brimli sim_sc_brimli sim_sc_brimli_fast \
        lint_sc_cntrl sim_sc_cntrl \
        lint_sc sim_sc sim_sc_fast \
        lint_ittage_table sim_ittage_table \
        lint_ittage_cntrl sim_ittage_cntrl \
        lint_ittage_arb lint_ittage sim_ittage sim_ittage_fast \
        lint_tage_cntrl lint_tage_arb lint_tage \
        lint_ras sim_ras \
        lint_ftb_array \
        lint_ftb_plru \
        lint_ftb_cntrl \
        lint_ftb \
        sim_ftb \
        lint_bp_cluster \
        sim_bp_cluster sim_bp_cluster_init \
        sim_tage sim_tage_fast sim_tage_tasks sim_tage_manual clean

all: lint  \
     lint_loop_pred \
     lint_tage_table \
     lint_sc_table \
     sim_sc_table \
     sim_sc_table_fast \
     lint_sc_brimli \
     sim_sc_brimli \
     sim_sc_brimli_fast \
     lint_sc_cntrl \
     sim_sc_cntrl \
     lint_sc \
     sim_sc \
     sim_sc_fast \
     lint_ittage_table \
     lint_ittage_cntrl \
     lint_ittage_arb \
     lint_ittage \
     lint_tage_cntrl \
     lint_tage_arb \
     lint_tage \
     lint_ras \
     lint_ftb_array \
     lint_ftb_plru \
     lint_ftb_cntrl \
     lint_ftb \
     lint_bp_cluster \
     sim_bp_cluster \
     sim \
     sim_history \
     sim_ubtb \
     sim_loop_pred \
     sim_tage_table \
     sim_ittage_table \
     sim_ittage_cntrl \
     sim_tage \
     sim_tage_fast \
     sim_tage_tasks \
     sim_ras \
     sim_ftb

lint:
	@echo "[linting]    bp_history"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/bp_history.sv $(VSILENCE)

sim:
	@echo "[compiling]  tb_bp_pkg"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT) \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(TB_DIR)/tb_bp_pkg.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)/Vtb"
	$(Q)./$(VER_OUT)/Vtb; rc=$$?; rm -rf $(VER_OUT); exit $$rc

sim_history:
	@echo "[compiling]  tb_bp_history"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  -Wno-SYNCASYNCNET --assert \
	  --Mdir $(VER_OUT)_hist \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/bp_history.sv \
	  $(TB_DIR)/bp_history_assert.sv \
	  $(TB_DIR)/tb_bp_history.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_hist/Vtb"
	$(Q)./$(VER_OUT)_hist/Vtb

sim_ubtb:
	@echo "[compiling]  tb_ubtb"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT)_ubtb \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ubtb.sv \
	  $(TB_DIR)/tb_ubtb.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ubtb/Vtb"
	$(Q)./$(VER_OUT)_ubtb/Vtb

# VARHIDDEN (BP-128): loop_pred.sv declares module parameters LP_TBL_ENTRIES
#   to LP_CONF_LEVEL with the names of bp_defines_pkg parameters. That is
#   its only remaining cause; no module shadows NUM_PRED_SLOTS.
lint_loop_pred:
	@echo "[linting]    loop_pred"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  -Wno-VARHIDDEN \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/loop_pred.sv $(VSILENCE)

# VARHIDDEN (BP-128): loop_pred.sv declares module parameters LP_TBL_ENTRIES
#   to LP_CONF_LEVEL with the names of bp_defines_pkg parameters. That is
#   its only remaining cause; no module shadows NUM_PRED_SLOTS.
sim_loop_pred:
	@echo "[compiling]  tb_loop_pred"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --top-module tb \
	  -Wno-SYNCASYNCNET --assert \
	  --Mdir $(VER_OUT)_loop_pred \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/loop_pred.sv \
	  $(TB_DIR)/loop_pred_assert.sv \
	  $(TB_DIR)/tb_loop_pred.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_loop_pred/Vtb"
	$(Q)./$(VER_OUT)_loop_pred/Vtb

lint_tage_table:
	@echo "[linting]    tage_table"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/tage_table.sv $(VSILENCE)

sim_tage_table:
	@echo "[compiling]  tb_tage_table"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT)_tage_table \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/tage_table.sv \
	  $(TB_DIR)/tb_tage_table.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_tage_table/Vtb"
	$(Q)./$(VER_OUT)_tage_table/Vtb

lint_sc_table:
	@echo "[linting]    sc_table"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/sc_table.sv $(VSILENCE)

sim_sc_table:
	@echo "[compiling]  tb_sc_table"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT)_sc_table \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/sc_table.sv \
	  $(TB_DIR)/tb_sc_table.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_sc_table/Vtb"
	$(Q)./$(VER_OUT)_sc_table/Vtb

sim_sc_table_fast:
	@echo "[compiling]  tb_sc_table (fast init)"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT)_sc_table_fast \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/sc_table.sv \
	  $(TB_DIR)/tb_sc_table.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_sc_table_fast/Vtb"
	$(Q)./$(VER_OUT)_sc_table_fast/Vtb +SC_FAST_INIT=1

lint_sc_brimli:
	@echo "[linting]    sc_brimli"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/sc_brimli.sv $(VSILENCE)

sim_sc_brimli:
	@echo "[compiling]  tb_sc_brimli"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT)_sc_brimli \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/sc_brimli.sv \
	  $(TB_DIR)/tb_sc_brimli.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_sc_brimli/Vtb"
	$(Q)./$(VER_OUT)_sc_brimli/Vtb

sim_sc_brimli_fast:
	@echo "[compiling]  tb_sc_brimli (fast init)"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT)_sc_brimli_fast \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/sc_brimli.sv \
	  $(TB_DIR)/tb_sc_brimli.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_sc_brimli_fast/Vtb"
	$(Q)./$(VER_OUT)_sc_brimli_fast/Vtb +SC_FAST_INIT=1

lint_sc_cntrl:
	@echo "[linting]    sc_cntrl"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/sc_cntrl.sv $(VSILENCE)

sim_sc_cntrl:
	@echo "[compiling]  tb_sc_cntrl"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT)_sc_cntrl \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/sc_cntrl.sv \
	  $(TB_DIR)/tb_sc_cntrl.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_sc_cntrl/Vtb"
	$(Q)./$(VER_OUT)_sc_cntrl/Vtb

# -- SC structural top (sc.sv). SYNCASYNCNET: sram_init async reset +
#    sync flops. VARHIDDEN removed in BP-128: its cause was the sc,
#    sc_cntrl, sc_table and sc_brimli NUM_PRED_SLOTS parameters.
lint_sc:
	@echo "[linting]    sc"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  -Wno-SYNCASYNCNET \
	  --top-module sc \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/sc_table.sv \
	  $(RTL_DIR)/sc_brimli.sv \
	  $(RTL_DIR)/sc_cntrl.sv \
	  $(RTL_DIR)/sc.sv $(VSILENCE)

sim_sc:
	@echo "[compiling]  tb_sc"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-SYNCASYNCNET \
	  --top-module tb \
	  --Mdir $(VER_OUT)_sc \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/sc_table.sv \
	  $(RTL_DIR)/sc_brimli.sv \
	  $(RTL_DIR)/sc_cntrl.sv \
	  $(RTL_DIR)/sc.sv \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_sc.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_sc/Vtb"
	$(Q)./$(VER_OUT)_sc/Vtb

sim_sc_fast:
	@echo "[compiling]  tb_sc (fast init)"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-SYNCASYNCNET \
	  --top-module tb \
	  --Mdir $(VER_OUT)_sc_fast \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/sc_table.sv \
	  $(RTL_DIR)/sc_brimli.sv \
	  $(RTL_DIR)/sc_cntrl.sv \
	  $(RTL_DIR)/sc.sv \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_sc.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_sc_fast/Vtb"
	$(Q)./$(VER_OUT)_sc_fast/Vtb +SC_FAST_INIT=1

lint_ittage_table:
	@echo "[linting]    ittage_table"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/ittage_table.sv $(VSILENCE)

sim_ittage_table:
	@echo "[compiling]  tb_ittage_table"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT)_ittage_table \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/ittage_table.sv \
	  $(TB_DIR)/tb_ittage_table.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ittage_table/Vtb"
	$(Q)./$(VER_OUT)_ittage_table/Vtb +ITTAGE_FAST_INIT=1

lint_ittage_cntrl:
	@echo "[linting]    ittage_cntrl"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  --top-module ittage_cntrl \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/ittage_table.sv \
	  $(RTL_DIR)/ittage_cntrl.sv $(VSILENCE)

sim_ittage_cntrl:
	@echo "[compiling]  tb_ittage_cntrl"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT)_ittage_cntrl \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ittage_cntrl.sv \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_ittage_cntrl.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ittage_cntrl/Vtb"
	$(Q)./$(VER_OUT)_ittage_cntrl/Vtb

# The ITTAGE arbitration layer (BP-132, TD#52), moved out of ittage.sv.
lint_ittage_arb:
	@echo "[linting]    ittage_arb"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  --top-module ittage_arb \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ittage_arb.sv $(VSILENCE)

lint_ittage:
	@echo "[linting]    ittage"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  -Wno-SYNCASYNCNET \
	  --top-module ittage \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/ittage_table.sv \
	  $(RTL_DIR)/ittage_cntrl.sv \
	  $(RTL_DIR)/ittage_arb.sv \
	  $(RTL_DIR)/ittage.sv $(VSILENCE)

# sim_ittage runs the real sram_init walk, no plusarg, as sim_tage
# does; sim_ittage_fast is the +ITTAGE_FAST_INIT=1 twin, as
# sim_tage_fast is for tage (BP-126, TD#68, TD#75). Before BP-126
# sim_ittage ran fast-init and no target ran the ITTAGE walk.
sim_ittage:
	@echo "[compiling]  tb_ittage"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-SYNCASYNCNET \
	  --top-module tb \
	  --Mdir $(VER_OUT)_ittage \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/ittage_table.sv \
	  $(RTL_DIR)/ittage_cntrl.sv \
	  $(RTL_DIR)/ittage_arb.sv \
	  $(RTL_DIR)/ittage.sv \
	  $(TB_DIR)/ittage_assert.sv \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_ittage.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ittage/Vtb"
	$(Q)./$(VER_OUT)_ittage/Vtb

sim_ittage_fast:
	@echo "[compiling]  tb_ittage (fast init)"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-SYNCASYNCNET \
	  --top-module tb \
	  --Mdir $(VER_OUT)_ittage_fast \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/ittage_table.sv \
	  $(RTL_DIR)/ittage_cntrl.sv \
	  $(RTL_DIR)/ittage_arb.sv \
	  $(RTL_DIR)/ittage.sv \
	  $(TB_DIR)/ittage_assert.sv \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_ittage.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ittage_fast/Vtb"
	$(Q)./$(VER_OUT)_ittage_fast/Vtb +ITTAGE_FAST_INIT=1

lint_tage_cntrl:
	@echo "[linting]    tage_cntrl"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  -Wno-UNDRIVEN \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/tage_cntrl.sv $(VSILENCE)

# The TAGE arbitration layer (BP-132, TD#52), moved out of tage.sv.
lint_tage_arb:
	@echo "[linting]    tage_arb"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  --top-module tage_arb \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/tage_arb.sv $(VSILENCE)

# VARHIDDEN (BP-128): tb_tage.sv tasks declare an argument named verbose,
#   which shadows the module variable of that name. That is its only
#   remaining cause; no module shadows NUM_PRED_SLOTS.
lint_tage:
	@echo "[linting]    tage"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  -Wno-UNDRIVEN \
	  -Wno-SYNCASYNCNET \
	  -Wno-PINMISSING \
	  --top-module tb \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/tage_bim.sv \
	  $(RTL_DIR)/tage_table.sv \
	  $(RTL_DIR)/tage_cntrl.sv \
	  $(RTL_DIR)/tage_arb.sv \
	  $(RTL_DIR)/tage.sv \
	  $(TB_DIR)/tage_assert.sv \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_tage.sv $(VSILENCE)

lint_ras:
	@echo "[linting]    ras"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ras.sv $(VSILENCE)

lint_ftb_array:
	@echo "[linting]    ftb_array"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ftb_array.sv $(VSILENCE)

lint_ftb_plru:
	@echo "[linting]    ftb_plru"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ftb_plru.sv $(VSILENCE)

lint_ftb_cntrl:
	@echo "[linting]    ftb_cntrl"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  --top-module ftb_cntrl \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ftb_cntrl.sv $(VSILENCE)

lint_ftb:
	@echo "[linting]    ftb"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  --top-module ftb \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ftb_array.sv \
	  $(RTL_DIR)/ftb_plru.sv \
	  $(RTL_DIR)/ftb_cntrl.sv \
	  $(RTL_DIR)/ftb.sv $(VSILENCE)

# -- BP cluster top (bp_cluster.sv, BP-085).
#    VARHIDDEN:    loop_pred.sv module parameters LP_TBL_ENTRIES to
#                  LP_CONF_LEVEL shadow the bp_defines_pkg parameters
#                  of the same names. Until BP-128 the comment named
#                  the tage/sc/ubtb NUM_PRED_SLOTS parameters; BP-128
#                  removed those (ubtb's is renamed N_SLOTS).
#    SYNCASYNCNET: sram_init async reset + sync flops in the tage,
#                  ittage and sc leaf logic (same as lint_tage).
#    UNDRIVEN removed in BP-085: the section 4 p1 prediction outputs
#    and the section 6 redirect outputs now have producers.
lint_bp_cluster:
	@echo "[linting]    bp_cluster"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  -Wno-VARHIDDEN \
	  -Wno-SYNCASYNCNET \
	  --top-module bp_cluster \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/bp_history.sv \
	  $(RTL_DIR)/ubtb.sv \
	  $(RTL_DIR)/loop_pred.sv \
	  $(RTL_DIR)/ftb_array.sv \
	  $(RTL_DIR)/ftb_plru.sv \
	  $(RTL_DIR)/ftb_cntrl.sv \
	  $(RTL_DIR)/ftb.sv \
	  $(RTL_DIR)/tage_bim.sv \
	  $(RTL_DIR)/tage_table.sv \
	  $(RTL_DIR)/tage_cntrl.sv \
	  $(RTL_DIR)/tage_arb.sv \
	  $(RTL_DIR)/tage.sv \
	  $(RTL_DIR)/ittage_table.sv \
	  $(RTL_DIR)/ittage_cntrl.sv \
	  $(RTL_DIR)/ittage_arb.sv \
	  $(RTL_DIR)/ittage.sv \
	  $(RTL_DIR)/sc_table.sv \
	  $(RTL_DIR)/sc_brimli.sv \
	  $(RTL_DIR)/sc_cntrl.sv \
	  $(RTL_DIR)/sc.sv \
	  $(RTL_DIR)/ras.sv \
	  $(RTL_DIR)/bp_cluster.sv $(VSILENCE)

# -- BP cluster testbench (tb_bp_cluster.sv, BP-093).
#    Same suppression set as lint_bp_cluster. The three fast-init
#    plusargs strap the tage, ittage and sc RAM init so the run stays
#    inside the CLAUDE.md sanity-time budget; the init walk itself is
#    covered by the per-predictor suites.
BP_CLUSTER_SRCS := \
  $(RTL_DIR)/bp_defines_pkg.sv \
  $(RTL_DIR)/bp_structs_pkg.sv \
  $(COMP_DIR)/bw_ram.sv \
  $(COMP_DIR)/sram_init.sv \
  $(RTL_DIR)/bp_history.sv \
  $(RTL_DIR)/ubtb.sv \
  $(RTL_DIR)/loop_pred.sv \
  $(RTL_DIR)/ftb_array.sv \
  $(RTL_DIR)/ftb_plru.sv \
  $(RTL_DIR)/ftb_cntrl.sv \
  $(RTL_DIR)/ftb.sv \
  $(RTL_DIR)/tage_bim.sv \
  $(RTL_DIR)/tage_table.sv \
  $(RTL_DIR)/tage_cntrl.sv \
  $(RTL_DIR)/tage_arb.sv \
  $(RTL_DIR)/tage.sv \
  $(RTL_DIR)/ittage_table.sv \
  $(RTL_DIR)/ittage_cntrl.sv \
  $(RTL_DIR)/ittage_arb.sv \
  $(RTL_DIR)/ittage.sv \
  $(RTL_DIR)/sc_table.sv \
  $(RTL_DIR)/sc_brimli.sv \
  $(RTL_DIR)/sc_cntrl.sv \
  $(RTL_DIR)/sc.sv \
  $(RTL_DIR)/ras.sv \
  $(RTL_DIR)/bp_cluster.sv

# The property files of the cluster's leaves that have one (BP-122,
# TD#170), elaborated by sim_bp_cluster with --assert, and since BP-139
# the cluster's own (bp_cluster_assert.sv, CL1); since BP-140 the FTB's
# (ftb_assert.sv, FA1).
BP_CLUSTER_ASSERT := \
  $(TB_DIR)/bp_history_assert.sv \
  $(TB_DIR)/loop_pred_assert.sv \
  $(TB_DIR)/ras_assert.sv \
  $(TB_DIR)/bp_cluster_assert.sv \
  $(TB_DIR)/ftb_assert.sv

BP_CLUSTER_PLUSARGS := \
  +TAGE_FAST_INIT=1 +ITTAGE_FAST_INIT=1 +SC_FAST_INIT=1

sim_bp_cluster:
	@echo "[compiling]  tb_bp_cluster"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  -Wno-SYNCASYNCNET \
	  --top-module tb \
	  --assert \
	  --Mdir $(VER_OUT)_bp_cluster \
	  $(BP_CLUSTER_SRCS) \
	  $(BP_CLUSTER_ASSERT) \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_bp_cluster.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_bp_cluster/Vtb"
	$(Q)./$(VER_OUT)_bp_cluster/Vtb $(BP_CLUSTER_PLUSARGS)

# The same testbench with no fast-init plusarg (BP-126, TD#67, TD#68):
# every TAGE, ITTAGE and SC table is initialised by its sram_init walk
# after every reset, and the first reset checks T0, IT5 and ST0 against
# their sram_init.md values before the first prediction.
sim_bp_cluster_init:
	@echo "[compiling]  tb_bp_cluster (sram_init walk)"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  -Wno-SYNCASYNCNET \
	  --top-module tb \
	  --assert \
	  --Mdir $(VER_OUT)_bp_cluster_init \
	  $(BP_CLUSTER_SRCS) \
	  $(BP_CLUSTER_ASSERT) \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_bp_cluster.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_bp_cluster_init/Vtb"
	$(Q)./$(VER_OUT)_bp_cluster_init/Vtb

sim_ras:
	@echo "[compiling]  tb_ras"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  -Wno-SYNCASYNCNET --assert \
	  --Mdir $(VER_OUT)_ras \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ras.sv \
	  $(TB_DIR)/ras_assert.sv \
	  $(TB_DIR)/tb_ras.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ras/Vtb"
	$(Q)./$(VER_OUT)_ras/Vtb

# BP-140: with --assert and the FTB's bound property file (FA1, the
# split at update).
sim_ftb:
	@echo "[compiling]  tb_ftb"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --assert \
	  --Mdir $(VER_OUT)_ftb \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ftb_array.sv \
	  $(RTL_DIR)/ftb_plru.sv \
	  $(RTL_DIR)/ftb_cntrl.sv \
	  $(RTL_DIR)/ftb.sv \
	  $(TB_DIR)/ftb_assert.sv \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_ftb.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftb/Vtb"
	$(Q)./$(VER_OUT)_ftb/Vtb

# VARHIDDEN (BP-128): tb_tage.sv tasks declare an argument named verbose,
#   which shadows the module variable of that name. That is its only
#   remaining cause; no module shadows NUM_PRED_SLOTS.
sim_tage:
	@echo "[compiling]  tb_tage"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  -Wno-UNDRIVEN \
	  -Wno-SYNCASYNCNET \
	  -Wno-PINMISSING \
	  --top-module tb \
	  --Mdir $(VER_OUT)_tage \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/tage_bim.sv \
	  $(RTL_DIR)/tage_table.sv \
	  $(RTL_DIR)/tage_cntrl.sv \
	  $(RTL_DIR)/tage_arb.sv \
	  $(RTL_DIR)/tage.sv \
	  $(TB_DIR)/tage_assert.sv \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_tage.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_tage/Vtb"
	$(Q)./$(VER_OUT)_tage/Vtb

# VARHIDDEN (BP-128): tb_tage.sv tasks declare an argument named verbose,
#   which shadows the module variable of that name. That is its only
#   remaining cause; no module shadows NUM_PRED_SLOTS.
sim_tage_fast:
	@echo "[compiling]  tb_tage (fast init)"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  -Wno-UNDRIVEN \
	  -Wno-SYNCASYNCNET \
	  -Wno-PINMISSING \
	  --top-module tb \
	  --Mdir $(VER_OUT)_tage_fast \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/tage_bim.sv \
	  $(RTL_DIR)/tage_table.sv \
	  $(RTL_DIR)/tage_cntrl.sv \
	  $(RTL_DIR)/tage_arb.sv \
	  $(RTL_DIR)/tage.sv \
	  $(TB_DIR)/tage_assert.sv \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_tage.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_tage_fast/Vtb"
	$(Q)./$(VER_OUT)_tage_fast/Vtb +TAGE_FAST_INIT=1

sim_tage_tasks:
	@echo "[compiling]  tb_tage_tasks"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-UNDRIVEN \
	  -Wno-SYNCASYNCNET \
	  -Wno-WIDTHTRUNC \
	  --top-module tb \
	  --Mdir $(VER_OUT)_tage_tasks \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/tage_bim.sv \
	  $(RTL_DIR)/tage_table.sv \
	  $(RTL_DIR)/tage_cntrl.sv \
	  $(RTL_DIR)/tage_arb.sv \
	  $(RTL_DIR)/tage.sv \
	  $(TB_DIR)/tage_assert.sv \
	  $(TB_DIR)/tage_assert_bind.sv \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_tage_tasks.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_tage_tasks/Vtb"
	$(Q)./$(VER_OUT)_tage_tasks/Vtb +TAGE_FAST_INIT=1

sim_tage_manual:
	@echo "[compiling]  tb_tage_manual"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-UNDRIVEN \
	  -Wno-SYNCASYNCNET \
	  -Wno-PINMISSING \
	  -Wno-WIDTHTRUNC \
	  --trace-fst \
	  --build-jobs $(JOBS) \
	  -I$(TB_DIR) \
	  --top-module tb \
	  --Mdir $(VER_OUT)_tage_manual \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/tage_bim.sv \
	  $(RTL_DIR)/tage_table.sv \
	  $(RTL_DIR)/tage_cntrl.sv \
	  $(RTL_DIR)/tage_arb.sv \
	  $(RTL_DIR)/tage.sv \
	  $(TB_DIR)/tage_assert.sv \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_tage_manual.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_tage_manual/Vtb"
	$(Q)./$(VER_OUT)_tage_manual/Vtb +TAGE_FAST_INIT=1 +EN_FST=$(FST)

clean:
	$(Q)rm -rf $(VER_OUT) \
	  $(VER_OUT)_1slot* \
	  $(VER_OUT)_hist \
	  $(VER_OUT)_ubtb \
	  $(VER_OUT)_loop_pred \
	  $(VER_OUT)_tage_table \
	  $(VER_OUT)_sc_table \
	  $(VER_OUT)_sc_table_fast \
	  $(VER_OUT)_sc_brimli \
	  $(VER_OUT)_sc_brimli_fast \
	  $(VER_OUT)_sc_cntrl \
	  $(VER_OUT)_sc \
	  $(VER_OUT)_sc_fast \
	  $(VER_OUT)_ittage_table \
	  $(VER_OUT)_ittage_cntrl \
	  $(VER_OUT)_ittage \
	  $(VER_OUT)_tage \
	  $(VER_OUT)_tage_fast \
	  $(VER_OUT)_tage_tasks \
	  $(VER_OUT)_tage_manual \
	  $(VER_OUT)_ras \
	  $(VER_OUT)_ftb \
	  $(VER_OUT)_bp_cluster \
	  obj_dir_cov_history \
	  obj_dir_cov_bp_cluster \
	  obj_dir_cov_loop_pred \
	  obj_dir_cov_tage \
	  obj_dir_cov_tage_table \
	  obj_dir_cov_ubtb

# -- Coverage infrastructure ----------------------------------------
COV_DIR := coverage

.PHONY: cov_tage cov_tage_table cov_loop_pred cov_history cov_ubtb \
        cov_bp_cluster \
        cov_bpu \
        clean_cov_tage clean_cov_tage_table clean_cov_loop_pred \
        clean_cov_history clean_cov_ubtb clean_cov_bp_cluster \
        clean_cov_bpu clean_cov

cov_history:
	@echo "[compiling]  cov tb_bp_history"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --coverage-line \
	  --top-module tb \
	  -Wno-SYNCASYNCNET --assert \
	  --Mdir obj_dir_cov_history \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/bp_history.sv \
	  $(TB_DIR)/bp_history_assert.sv \
	  $(TB_DIR)/tb_bp_history.sv $(VSILENCE)
	$(Q)sed -i '/topp->final/a\    contextp->coveragep()->write("coverage.dat");' \
	  obj_dir_cov_history/Vtb__main.cpp
	$(Q)make -C obj_dir_cov_history -f Vtb.mk
	$(Q)mkdir -p $(COV_DIR)/history/html
	@echo "[simulating] cov_history"
	$(Q)cd $(COV_DIR)/history && $(CURDIR)/obj_dir_cov_history/Vtb
	$(Q)verilator_coverage \
	  --write-info $(COV_DIR)/history/coverage.info \
	  $(COV_DIR)/history/coverage.dat
	$(Q)genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/history/html \
	  $(COV_DIR)/history/coverage.info
	@echo "[coverage]   history HTML at $(COV_DIR)/history/html/index.html"

cov_ubtb:
	@echo "[compiling]  cov tb_ubtb"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --coverage-line \
	  --top-module tb \
	  --Mdir obj_dir_cov_ubtb \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ubtb.sv \
	  $(TB_DIR)/tb_ubtb.sv $(VSILENCE)
	$(Q)sed -i '/topp->final/a\    contextp->coveragep()->write("coverage.dat");' \
	  obj_dir_cov_ubtb/Vtb__main.cpp
	$(Q)make -C obj_dir_cov_ubtb -f Vtb.mk
	$(Q)mkdir -p $(COV_DIR)/ubtb/html
	@echo "[simulating] cov_ubtb"
	$(Q)cd $(COV_DIR)/ubtb && $(CURDIR)/obj_dir_cov_ubtb/Vtb
	$(Q)verilator_coverage \
	  --write-info $(COV_DIR)/ubtb/coverage.info \
	  $(COV_DIR)/ubtb/coverage.dat
	$(Q)genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/ubtb/html \
	  $(COV_DIR)/ubtb/coverage.info
	@echo "[coverage]   ubtb HTML at $(COV_DIR)/ubtb/html/index.html"

# VARHIDDEN (BP-128): loop_pred.sv declares module parameters LP_TBL_ENTRIES
#   to LP_CONF_LEVEL with the names of bp_defines_pkg parameters. That is
#   its only remaining cause; no module shadows NUM_PRED_SLOTS.
cov_loop_pred:
	@echo "[compiling]  cov tb_loop_pred"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --coverage-line \
	  --top-module tb \
	  -Wno-SYNCASYNCNET --assert \
	  --Mdir obj_dir_cov_loop_pred \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/loop_pred.sv \
	  $(TB_DIR)/loop_pred_assert.sv \
	  $(TB_DIR)/tb_loop_pred.sv $(VSILENCE)
	$(Q)sed -i '/topp->final/a\    contextp->coveragep()->write("coverage.dat");' \
	  obj_dir_cov_loop_pred/Vtb__main.cpp
	$(Q)make -C obj_dir_cov_loop_pred -f Vtb.mk
	$(Q)mkdir -p $(COV_DIR)/loop_pred/html
	@echo "[simulating] cov_loop_pred"
	$(Q)cd $(COV_DIR)/loop_pred && $(CURDIR)/obj_dir_cov_loop_pred/Vtb
	$(Q)verilator_coverage \
	  --write-info $(COV_DIR)/loop_pred/coverage.info \
	  $(COV_DIR)/loop_pred/coverage.dat
	$(Q)genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/loop_pred/html \
	  $(COV_DIR)/loop_pred/coverage.info
	@echo "[coverage]   loop_pred HTML at $(COV_DIR)/loop_pred/html/index.html"

cov_tage_table:
	@echo "[compiling]  cov tb_tage_table"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --coverage-line \
	  --top-module tb \
	  --Mdir obj_dir_cov_tage_table \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/tage_table.sv \
	  $(TB_DIR)/tb_tage_table.sv $(VSILENCE)
	$(Q)sed -i '/topp->final/a\    contextp->coveragep()->write("coverage.dat");' \
	  obj_dir_cov_tage_table/Vtb__main.cpp
	$(Q)make -C obj_dir_cov_tage_table -f Vtb.mk
	$(Q)mkdir -p $(COV_DIR)/tage_table/html
	@echo "[simulating] cov_tage_table"
	$(Q)cd $(COV_DIR)/tage_table && \
	  $(CURDIR)/obj_dir_cov_tage_table/Vtb +TAGE_FAST_INIT=1
	$(Q)verilator_coverage \
	  --write-info $(COV_DIR)/tage_table/coverage.info \
	  $(COV_DIR)/tage_table/coverage.dat
	$(Q)genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/tage_table/html \
	  $(COV_DIR)/tage_table/coverage.info
	@echo "[coverage]   tage_table HTML at $(COV_DIR)/tage_table/html/index.html"

# cov_tage runs tb_tage twice, on the sram_init walk and on the fast
# init, and merges the two, so the fast-init blocks of tage_bim and
# tage_table are measured too (BP-126, TD#100).
# VARHIDDEN (BP-128): tb_tage.sv tasks declare an argument named verbose,
#   which shadows the module variable of that name. That is its only
#   remaining cause; no module shadows NUM_PRED_SLOTS.
cov_tage:
	@echo "[compiling]  cov tb_tage"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  -Wno-UNDRIVEN \
	  -Wno-SYNCASYNCNET \
	  -Wno-PINMISSING \
	  --coverage-line \
	  --top-module tb \
	  --Mdir obj_dir_cov_tage \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/tage_bim.sv \
	  $(RTL_DIR)/tage_table.sv \
	  $(RTL_DIR)/tage_cntrl.sv \
	  $(RTL_DIR)/tage_arb.sv \
	  $(RTL_DIR)/tage.sv \
	  $(TB_DIR)/tage_assert.sv \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_tage.sv $(VSILENCE)
	$(Q)sed -i '/topp->final/a\    contextp->coveragep()->write("coverage.dat");' \
	  obj_dir_cov_tage/Vtb__main.cpp
	$(Q)make -C obj_dir_cov_tage -f Vtb.mk
	$(Q)mkdir -p $(COV_DIR)/tage/html $(COV_DIR)/tage/walk \
	  $(COV_DIR)/tage/fast
	@echo "[simulating] cov_tage (sram_init walk, then +TAGE_FAST_INIT=1)"
	$(Q)cd $(COV_DIR)/tage/walk && $(CURDIR)/obj_dir_cov_tage/Vtb
	$(Q)cd $(COV_DIR)/tage/fast && \
	  $(CURDIR)/obj_dir_cov_tage/Vtb +TAGE_FAST_INIT=1
	$(Q)verilator_coverage --write $(COV_DIR)/tage/coverage.dat \
	  $(COV_DIR)/tage/walk/coverage.dat $(COV_DIR)/tage/fast/coverage.dat
	$(Q)verilator_coverage \
	  --write-info $(COV_DIR)/tage/coverage.info \
	  $(COV_DIR)/tage/coverage.dat
	$(Q)genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/tage/html \
	  $(COV_DIR)/tage/coverage.info
	@echo "[coverage]   tage HTML at $(COV_DIR)/tage/html/index.html"

# VARHIDDEN (BP-128): loop_pred.sv declares module parameters LP_TBL_ENTRIES
#   to LP_CONF_LEVEL with the names of bp_defines_pkg parameters. That is
#   its only remaining cause; no module shadows NUM_PRED_SLOTS.
cov_bp_cluster:
	@echo "[compiling]  cov tb_bp_cluster"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  -Wno-SYNCASYNCNET \
	  --coverage-line \
	  --top-module tb \
	  --Mdir obj_dir_cov_bp_cluster \
	  $(BP_CLUSTER_SRCS) \
	  $(CSR_TB_SRCS) \
	  $(TB_DIR)/tb_bp_cluster.sv $(VSILENCE)
	$(Q)sed -i '/topp->final/a\    contextp->coveragep()->write("coverage.dat");' \
	  obj_dir_cov_bp_cluster/Vtb__main.cpp
	$(Q)make -C obj_dir_cov_bp_cluster -f Vtb.mk
	$(Q)mkdir -p $(COV_DIR)/bp_cluster/html
	@echo "[simulating] cov_bp_cluster"
	$(Q)cd $(COV_DIR)/bp_cluster && \
	  $(CURDIR)/obj_dir_cov_bp_cluster/Vtb $(BP_CLUSTER_PLUSARGS)
	$(Q)verilator_coverage \
	  --write-info $(COV_DIR)/bp_cluster/coverage.info \
	  $(COV_DIR)/bp_cluster/coverage.dat
	$(Q)genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/bp_cluster/html \
	  $(COV_DIR)/bp_cluster/coverage.info
	@echo "[coverage]   bp_cluster HTML at $(COV_DIR)/bp_cluster/html/index.html"

cov_bpu: cov_tage cov_tage_table cov_loop_pred cov_history cov_ubtb
	$(Q)mkdir -p $(COV_DIR)/bpu/html
	$(Q)verilator_coverage \
	  --write $(COV_DIR)/bpu/coverage.dat \
	  $(COV_DIR)/tage/coverage.dat \
	  $(COV_DIR)/tage_table/coverage.dat \
	  $(COV_DIR)/loop_pred/coverage.dat \
	  $(COV_DIR)/history/coverage.dat \
	  $(COV_DIR)/ubtb/coverage.dat
	$(Q)verilator_coverage \
	  --write-info $(COV_DIR)/bpu/coverage.info \
	  $(COV_DIR)/bpu/coverage.dat
	$(Q)genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/bpu/html \
	  $(COV_DIR)/bpu/coverage.info
	@echo "[coverage]   bpu merged HTML at $(COV_DIR)/bpu/html/index.html"

clean_cov_tage:
	$(Q)rm -rf obj_dir_cov_tage $(COV_DIR)/tage

clean_cov_tage_table:
	$(Q)rm -rf obj_dir_cov_tage_table $(COV_DIR)/tage_table

clean_cov_loop_pred:
	$(Q)rm -rf obj_dir_cov_loop_pred $(COV_DIR)/loop_pred

clean_cov_history:
	$(Q)rm -rf obj_dir_cov_history $(COV_DIR)/history

clean_cov_ubtb:
	$(Q)rm -rf obj_dir_cov_ubtb $(COV_DIR)/ubtb

clean_cov_bp_cluster:
	$(Q)rm -rf obj_dir_cov_bp_cluster $(COV_DIR)/bp_cluster

clean_cov_bpu:
	$(Q)rm -rf $(COV_DIR)/bpu

clean_cov: clean_cov_tage clean_cov_tage_table \
  clean_cov_loop_pred clean_cov_history \
  clean_cov_ubtb clean_cov_bp_cluster clean_cov_bpu

# -- 1-slot targets (BP-128, TD#1) -----------------------------------
# One per lint and sim target, named <target>_1slot: the same recipe at
# NUM_PRED_SLOTS = 1 (see SLOT1_DEFS at the top of the file). The cov_*
# targets stay at 2 and have none.
SLOT1_BASE := \
  lint lint_loop_pred lint_tage_table lint_sc_table lint_sc_brimli \
  lint_sc_cntrl lint_sc lint_ittage_table lint_ittage_cntrl lint_ittage_arb \
  lint_ittage lint_tage_cntrl lint_tage_arb lint_tage lint_ras lint_ftb_array \
  lint_ftb_plru \
  lint_ftb_cntrl lint_ftb lint_bp_cluster \
  sim sim_history sim_ubtb sim_loop_pred sim_tage_table sim_sc_table \
  sim_sc_table_fast sim_sc_brimli sim_sc_brimli_fast sim_sc_cntrl sim_sc \
  sim_sc_fast sim_ittage_table sim_ittage_cntrl sim_ittage sim_ittage_fast \
  sim_bp_cluster sim_bp_cluster_init sim_ras sim_ftb sim_tage sim_tage_fast \
  sim_tage_tasks sim_tage_manual
SLOT1_TGTS := $(addsuffix _1slot,$(SLOT1_BASE))

.PHONY: $(SLOT1_TGTS)
$(SLOT1_TGTS): %_1slot:
	$(Q)$(MAKE) $* SLOT_DEFS="$(SLOT1_DEFS)" VER_OUT=$(VER_OUT)_1slot

# -- Regression plumbing (TOOLS-006) ----------------------------------
# tools/regress.sh runs every REGRESS_TARGETS entry with its own make
# call and fails if a target defined in this file is in neither list.
# `all` omits sim_ittage, sim_tage_manual and every cov_* target; this
# list does not. cov_bpu re-runs five cov_* targets and then merges
# them; it is kept because the merge step is its own.
# Exclusions:
#   all                 - aggregate.
#   clean, clean_cov*   - housekeeping.
#   regress_list        - this plumbing.
REGRESS_TARGETS := \
  lint lint_loop_pred lint_tage_table lint_sc_table lint_sc_brimli \
  lint_sc_cntrl lint_sc lint_ittage_table lint_ittage_cntrl lint_ittage_arb \
  lint_ittage lint_tage_cntrl lint_tage_arb lint_tage lint_ras lint_ftb_array \
  lint_ftb_plru \
  lint_ftb_cntrl lint_ftb lint_bp_cluster \
  sim sim_history sim_ubtb sim_loop_pred sim_tage_table sim_sc_table \
  sim_sc_table_fast sim_sc_brimli sim_sc_brimli_fast sim_sc_cntrl sim_sc \
  sim_sc_fast sim_ittage_table sim_ittage_cntrl sim_ittage sim_ittage_fast \
  sim_bp_cluster sim_bp_cluster_init sim_ras sim_ftb sim_tage sim_tage_fast \
  sim_tage_tasks sim_tage_manual \
  cov_history cov_ubtb cov_loop_pred cov_tage_table cov_tage \
  cov_bp_cluster cov_bpu \
  $(SLOT1_TGTS)
REGRESS_EXCLUDE := \
  all clean clean_cov clean_cov_tage clean_cov_tage_table \
  clean_cov_loop_pred clean_cov_history clean_cov_ubtb \
  clean_cov_bp_cluster clean_cov_bpu regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
