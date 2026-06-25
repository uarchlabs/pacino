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

.DEFAULT_GOAL := all

RTL_DIR  := rtl
TB_DIR   := tb
COMP_DIR := ../../../lib/rtl
VER_OUT  := obj

VER_FLAGS       := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing
SIM_EXTRA_FLAGS := -Wno-DECLFILENAME

.PHONY: all lint sim sim_history sim_ubtb lint_loop_pred sim_loop_pred \
        lint_tage_table sim_tage_table \
        lint_ittage_table sim_ittage_table \
        lint_ittage_cntrl sim_ittage_cntrl \
        lint_ittage sim_ittage \
        lint_tage_cntrl lint_tage \
        lint_ras sim_ras \
        lint_ftb_array \
        lint_ftb_plru \
        sim_tage sim_tage_fast sim_tage_tasks sim_tage_manual clean

all: lint  \
     lint_loop_pred \
     lint_tage_table \
     lint_ittage_table \
     lint_ittage_cntrl \
     lint_ittage \
     lint_tage_cntrl \
     lint_tage \
     lint_ras \
     lint_ftb_array \
     lint_ftb_plru \
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
     sim_ras

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
	$(Q)./$(VER_OUT)/Vtb

sim_history:
	@echo "[compiling]  tb_bp_history"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT)_hist \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/bp_history.sv \
	  $(TB_DIR)/tb_bp_history.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_hist/Vtb"
	$(Q)./$(VER_OUT)_hist/Vtb

sim_ubtb:
	@echo "[compiling]  tb_ubtb"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --top-module tb \
	  --Mdir $(VER_OUT)_ubtb \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ubtb.sv \
	  $(TB_DIR)/tb_ubtb.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ubtb/Vtb"
	$(Q)./$(VER_OUT)_ubtb/Vtb

lint_loop_pred:
	@echo "[linting]    loop_pred"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  -Wno-VARHIDDEN \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/loop_pred.sv $(VSILENCE)

sim_loop_pred:
	@echo "[compiling]  tb_loop_pred"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --top-module tb \
	  --Mdir $(VER_OUT)_loop_pred \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/loop_pred.sv \
	  $(TB_DIR)/tb_loop_pred.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_loop_pred/Vtb"
	$(Q)./$(VER_OUT)_loop_pred/Vtb

lint_tage_table:
	@echo "[linting]    tage_table"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  -Wno-VARHIDDEN \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/tage_table.sv $(VSILENCE)

sim_tage_table:
	@echo "[compiling]  tb_tage_table"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --top-module tb \
	  --Mdir $(VER_OUT)_tage_table \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/tage_table.sv \
	  $(TB_DIR)/tb_tage_table.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_tage_table/Vtb"
	$(Q)./$(VER_OUT)_tage_table/Vtb

lint_ittage_table:
	@echo "[linting]    ittage_table"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  -Wno-VARHIDDEN \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/ittage_table.sv $(VSILENCE)

sim_ittage_table:
	@echo "[compiling]  tb_ittage_table"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
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
	  -Wno-VARHIDDEN \
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
	  -Wno-VARHIDDEN \
	  --top-module tb \
	  --Mdir $(VER_OUT)_ittage_cntrl \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ittage_cntrl.sv \
	  $(TB_DIR)/tb_ittage_cntrl.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ittage_cntrl/Vtb"
	$(Q)./$(VER_OUT)_ittage_cntrl/Vtb

lint_ittage:
	@echo "[linting]    ittage"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  -Wno-VARHIDDEN \
	  -Wno-SYNCASYNCNET \
	  --top-module ittage \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/ittage_table.sv \
	  $(RTL_DIR)/ittage_cntrl.sv \
	  $(RTL_DIR)/ittage.sv $(VSILENCE)

sim_ittage:
	@echo "[compiling]  tb_ittage"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  -Wno-SYNCASYNCNET \
	  --top-module tb \
	  --Mdir $(VER_OUT)_ittage \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(COMP_DIR)/sram_init.sv \
	  $(RTL_DIR)/ittage_table.sv \
	  $(RTL_DIR)/ittage_cntrl.sv \
	  $(RTL_DIR)/ittage.sv \
	  $(TB_DIR)/ittage_assert.sv \
	  $(TB_DIR)/tb_ittage.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ittage/Vtb"
	$(Q)./$(VER_OUT)_ittage/Vtb +ITTAGE_FAST_INIT=1

lint_tage_cntrl:
	@echo "[linting]    tage_cntrl"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  -Wno-VARHIDDEN \
	  -Wno-UNDRIVEN \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/tage_cntrl.sv $(VSILENCE)

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
	  $(RTL_DIR)/tage.sv \
	  $(TB_DIR)/tage_assert.sv \
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

sim_ras:
	@echo "[compiling]  tb_ras"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT)_ras \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ras.sv \
	  $(TB_DIR)/tb_ras.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ras/Vtb"
	$(Q)./$(VER_OUT)_ras/Vtb

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
	  $(RTL_DIR)/tage.sv \
	  $(TB_DIR)/tage_assert.sv \
	  $(TB_DIR)/tb_tage.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_tage/Vtb"
	$(Q)./$(VER_OUT)_tage/Vtb

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
	  $(RTL_DIR)/tage.sv \
	  $(TB_DIR)/tage_assert.sv \
	  $(TB_DIR)/tb_tage.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_tage_fast/Vtb"
	$(Q)./$(VER_OUT)_tage_fast/Vtb +TAGE_FAST_INIT=1

sim_tage_tasks:
	@echo "[compiling]  tb_tage_tasks"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
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
	  $(RTL_DIR)/tage.sv \
	  $(TB_DIR)/tage_assert.sv \
	  $(TB_DIR)/tage_assert_bind.sv \
	  $(TB_DIR)/tb_tage_tasks.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_tage_tasks/Vtb"
	$(Q)./$(VER_OUT)_tage_tasks/Vtb +TAGE_FAST_INIT=1

sim_tage_manual:
	@echo "[compiling]  tb_tage_manual"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
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
	  $(RTL_DIR)/tage.sv \
	  $(TB_DIR)/tage_assert.sv \
	  $(TB_DIR)/tb_tage_manual.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_tage_manual/Vtb"
	$(Q)./$(VER_OUT)_tage_manual/Vtb +TAGE_FAST_INIT=1 +EN_FST=1

clean:
	$(Q)rm -rf $(VER_OUT) \
	  $(VER_OUT)_hist \
	  $(VER_OUT)_ubtb \
	  $(VER_OUT)_loop_pred \
	  $(VER_OUT)_tage_table \
	  $(VER_OUT)_ittage_table \
	  $(VER_OUT)_ittage_cntrl \
	  $(VER_OUT)_ittage \
	  $(VER_OUT)_tage \
	  $(VER_OUT)_tage_fast \
	  $(VER_OUT)_tage_tasks \
	  $(VER_OUT)_tage_manual \
	  $(VER_OUT)_ras \
	  obj_dir_cov_history \
	  obj_dir_cov_loop_pred \
	  obj_dir_cov_tage \
	  obj_dir_cov_tage_table \
	  obj_dir_cov_ubtb

# -- Coverage infrastructure ----------------------------------------
COV_DIR := coverage

.PHONY: cov_tage cov_tage_table cov_loop_pred cov_history cov_ubtb \
        cov_bpu \
        clean_cov_tage clean_cov_tage_table clean_cov_loop_pred \
        clean_cov_history clean_cov_ubtb clean_cov_bpu clean_cov

cov_history:
	@echo "[compiling]  cov tb_bp_history"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --coverage-line \
	  --top-module tb \
	  --Mdir obj_dir_cov_history \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/bp_history.sv \
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
	  -Wno-VARHIDDEN \
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

cov_loop_pred:
	@echo "[compiling]  cov tb_loop_pred"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --coverage-line \
	  --top-module tb \
	  --Mdir obj_dir_cov_loop_pred \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/loop_pred.sv \
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
	  -Wno-VARHIDDEN \
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
	  $(RTL_DIR)/tage.sv \
	  $(TB_DIR)/tb_tage.sv $(VSILENCE)
	$(Q)sed -i '/topp->final/a\    contextp->coveragep()->write("coverage.dat");' \
	  obj_dir_cov_tage/Vtb__main.cpp
	$(Q)make -C obj_dir_cov_tage -f Vtb.mk
	$(Q)mkdir -p $(COV_DIR)/tage/html
	@echo "[simulating] cov_tage"
	$(Q)cd $(COV_DIR)/tage && $(CURDIR)/obj_dir_cov_tage/Vtb
	$(Q)verilator_coverage \
	  --write-info $(COV_DIR)/tage/coverage.info \
	  $(COV_DIR)/tage/coverage.dat
	$(Q)genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/tage/html \
	  $(COV_DIR)/tage/coverage.info
	@echo "[coverage]   tage HTML at $(COV_DIR)/tage/html/index.html"

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

clean_cov_bpu:
	$(Q)rm -rf $(COV_DIR)/bpu

clean_cov: clean_cov_tage clean_cov_tage_table \
  clean_cov_loop_pred clean_cov_history \
  clean_cov_ubtb clean_cov_bpu
