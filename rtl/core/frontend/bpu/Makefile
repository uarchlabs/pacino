# Makefile -- branch predictor cluster
# Targets: lint, sim, all (default), clean

.DEFAULT_GOAL := all

RTL_DIR  := rtl
TB_DIR   := tb
#COMP_DIR := $(RVA_ROOT)/rtl/lib/rtl
COMP_DIR := ../../../lib/rtl
#VER_OUT  := verilator_out
VER_OUT  := obj

VER_FLAGS     := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing
# DECLFILENAME: tb module name must differ from tb_<dut>.sv filename
SIM_EXTRA_FLAGS := -Wno-DECLFILENAME

.PHONY: all lint sim sim_history sim_ubtb lint_loop_pred sim_loop_pred \
        lint_tage_table sim_tage_table \
        lint_ittage_table sim_ittage_table \
        lint_ittage_cntrl sim_ittage_cntrl \
        lint_tage_cntrl lint_tage \
        sim_tage sim_tage_fast clean

all: lint  \
     lint_loop_pred \
     lint_tage_table \
     lint_ittage_table \
     lint_ittage_cntrl \
     lint_tage_cntrl \
     lint_tage \
     sim \
     sim_history \
     sim_ubtb \
     sim_loop_pred \
     sim_tage_table \
     sim_ittage_table \
     sim_ittage_cntrl \
     sim_tage \
     sim_tage_fast

lint:
	verilator --lint-only \
	  $(VER_FLAGS) \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/bp_history.sv

sim:
	verilator --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT) \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(TB_DIR)/tb_bp_pkg.sv
	./$(VER_OUT)/Vtb


sim_history:
	verilator --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --top-module tb \
	  --Mdir $(VER_OUT)_hist \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/bp_history.sv \
	  $(TB_DIR)/tb_bp_history.sv
	./$(VER_OUT)_hist/Vtb


sim_ubtb:
	verilator --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --top-module tb \
	  --Mdir $(VER_OUT)_ubtb \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ubtb.sv \
	  $(TB_DIR)/tb_ubtb.sv
	./$(VER_OUT)_ubtb/Vtb

lint_loop_pred:
	verilator --lint-only \
	  $(VER_FLAGS) \
	  -Wno-VARHIDDEN \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/loop_pred.sv


sim_loop_pred:
	verilator --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --top-module tb \
	  --Mdir $(VER_OUT)_loop_pred \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/loop_pred.sv \
	  $(TB_DIR)/tb_loop_pred.sv
	./$(VER_OUT)_loop_pred/Vtb

lint_tage_table:
	verilator --lint-only \
	  $(VER_FLAGS) \
	  -Wno-VARHIDDEN \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/tage_table.sv


sim_tage_table:
	verilator --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --top-module tb \
	  --Mdir $(VER_OUT)_tage_table \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/tage_table.sv \
	  $(TB_DIR)/tb_tage_table.sv
	./$(VER_OUT)_tage_table/Vtb

lint_ittage_table:
	verilator --lint-only \
	  $(VER_FLAGS) \
	  -Wno-VARHIDDEN \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/ittage_table.sv


sim_ittage_table:
	verilator --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --top-module tb \
	  --Mdir $(VER_OUT)_ittage_table \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/ittage_table.sv \
	  $(TB_DIR)/tb_ittage_table.sv
	./$(VER_OUT)_ittage_table/Vtb +ITTAGE_FAST_INIT=1


lint_ittage_cntrl:
	verilator --lint-only \
	  $(VER_FLAGS) \
	  -Wno-VARHIDDEN \
	  --top-module ittage_cntrl \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/ittage_table.sv \
	  $(RTL_DIR)/ittage_cntrl.sv


sim_ittage_cntrl:
	verilator --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --top-module tb \
	  --Mdir $(VER_OUT)_ittage_cntrl \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ittage_cntrl.sv \
	  $(TB_DIR)/tb_ittage_cntrl.sv
	./$(VER_OUT)_ittage_cntrl/Vtb


lint_tage_cntrl:
	verilator --lint-only \
	  $(VER_FLAGS) \
	  -Wno-VARHIDDEN \
	  -Wno-UNDRIVEN \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/tage_cntrl.sv

lint_tage:
	verilator --lint-only \
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
	  $(TB_DIR)/tb_tage.sv


sim_tage:
	verilator --binary \
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
	  $(TB_DIR)/tb_tage.sv
	./$(VER_OUT)_tage/Vtb


sim_tage_fast:
	verilator --binary \
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
	  $(TB_DIR)/tb_tage.sv
	./$(VER_OUT)_tage_fast/Vtb +TAGE_FAST_INIT=1

clean:
	rm -rf $(VER_OUT) \
    $(VER_OUT)_hist \
    $(VER_OUT)_ubtb \
	  $(VER_OUT)_loop_pred \
	  $(VER_OUT)_tage_table \
	  $(VER_OUT)_ittage_table \
	  $(VER_OUT)_ittage_cntrl \
    $(VER_OUT)_tage \
	  $(VER_OUT)_tage_fast \
	  obj_dir_cov_history \
    obj_dir_cov_loop_pred \
    obj_dir_cov_tage \
    obj_dir_cov_tage_table \
    obj_dir_cov_ubtb

# -- Coverage infrastructure ----------------------------------------
# cov_* targets: coverage-instrumented builds in separate obj_dirs.
# Do not reuse existing sim obj_dirs -- parallel dirs prevent stomping.

COV_DIR := coverage

.PHONY: cov_tage cov_tage_table cov_loop_pred cov_history cov_ubtb \
        cov_bpu \
        clean_cov_tage clean_cov_tage_table clean_cov_loop_pred \
        clean_cov_history clean_cov_ubtb clean_cov_bpu clean_cov

cov_history:
	verilator --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  --coverage-line \
	  --top-module tb \
	  --Mdir obj_dir_cov_history \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/bp_history.sv \
	  $(TB_DIR)/tb_bp_history.sv
	sed -i '/topp->final/a\    contextp->coveragep()->write("coverage.dat");' \
	  obj_dir_cov_history/Vtb__main.cpp
	make -C obj_dir_cov_history -f Vtb.mk
	mkdir -p $(COV_DIR)/history/html
	cd $(COV_DIR)/history && $(CURDIR)/obj_dir_cov_history/Vtb
	verilator_coverage \
	  --write-info $(COV_DIR)/history/coverage.info \
	  $(COV_DIR)/history/coverage.dat
	genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/history/html \
	  $(COV_DIR)/history/coverage.info
	@echo "cov_history: HTML at $(COV_DIR)/history/html/index.html"

cov_ubtb:
	verilator --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --coverage-line \
	  --top-module tb \
	  --Mdir obj_dir_cov_ubtb \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/ubtb.sv \
	  $(TB_DIR)/tb_ubtb.sv
	sed -i '/topp->final/a\    contextp->coveragep()->write("coverage.dat");' \
	  obj_dir_cov_ubtb/Vtb__main.cpp
	make -C obj_dir_cov_ubtb -f Vtb.mk
	mkdir -p $(COV_DIR)/ubtb/html
	cd $(COV_DIR)/ubtb && $(CURDIR)/obj_dir_cov_ubtb/Vtb
	verilator_coverage \
	  --write-info $(COV_DIR)/ubtb/coverage.info \
	  $(COV_DIR)/ubtb/coverage.dat
	genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/ubtb/html \
	  $(COV_DIR)/ubtb/coverage.info
	@echo "cov_ubtb: HTML at $(COV_DIR)/ubtb/html/index.html"

cov_loop_pred:
	verilator --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --coverage-line \
	  --top-module tb \
	  --Mdir obj_dir_cov_loop_pred \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(RTL_DIR)/loop_pred.sv \
	  $(TB_DIR)/tb_loop_pred.sv
	sed -i '/topp->final/a\    contextp->coveragep()->write("coverage.dat");' \
	  obj_dir_cov_loop_pred/Vtb__main.cpp
	make -C obj_dir_cov_loop_pred -f Vtb.mk
	mkdir -p $(COV_DIR)/loop_pred/html
	cd $(COV_DIR)/loop_pred && $(CURDIR)/obj_dir_cov_loop_pred/Vtb
	verilator_coverage \
	  --write-info $(COV_DIR)/loop_pred/coverage.info \
	  $(COV_DIR)/loop_pred/coverage.dat
	genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/loop_pred/html \
	  $(COV_DIR)/loop_pred/coverage.info
	@echo "cov_loop_pred: HTML at $(COV_DIR)/loop_pred/html/index.html"

cov_tage_table:
	verilator --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-VARHIDDEN \
	  --coverage-line \
	  --top-module tb \
	  --Mdir obj_dir_cov_tage_table \
	  $(RTL_DIR)/bp_defines_pkg.sv \
	  $(RTL_DIR)/bp_structs_pkg.sv \
	  $(COMP_DIR)/bw_ram.sv \
	  $(RTL_DIR)/tage_table.sv \
	  $(TB_DIR)/tb_tage_table.sv
	sed -i '/topp->final/a\    contextp->coveragep()->write("coverage.dat");' \
	  obj_dir_cov_tage_table/Vtb__main.cpp
	make -C obj_dir_cov_tage_table -f Vtb.mk
	mkdir -p $(COV_DIR)/tage_table/html
	cd $(COV_DIR)/tage_table && \
	  $(CURDIR)/obj_dir_cov_tage_table/Vtb +TAGE_FAST_INIT=1
	verilator_coverage \
	  --write-info $(COV_DIR)/tage_table/coverage.info \
	  $(COV_DIR)/tage_table/coverage.dat
	genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/tage_table/html \
	  $(COV_DIR)/tage_table/coverage.info
	@echo "cov_tage_table: HTML at $(COV_DIR)/tage_table/html/index.html"

cov_tage:
	verilator --binary \
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
	  $(TB_DIR)/tb_tage.sv
	sed -i '/topp->final/a\    contextp->coveragep()->write("coverage.dat");' \
	  obj_dir_cov_tage/Vtb__main.cpp
	make -C obj_dir_cov_tage -f Vtb.mk
	mkdir -p $(COV_DIR)/tage/html
	cd $(COV_DIR)/tage && $(CURDIR)/obj_dir_cov_tage/Vtb
	verilator_coverage \
	  --write-info $(COV_DIR)/tage/coverage.info \
	  $(COV_DIR)/tage/coverage.dat
	genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/tage/html \
	  $(COV_DIR)/tage/coverage.info
	@echo "cov_tage: HTML at $(COV_DIR)/tage/html/index.html"

cov_bpu: cov_tage cov_tage_table cov_loop_pred cov_history cov_ubtb
	mkdir -p $(COV_DIR)/bpu/html
	verilator_coverage \
	  --write $(COV_DIR)/bpu/coverage.dat \
	  $(COV_DIR)/tage/coverage.dat \
	  $(COV_DIR)/tage_table/coverage.dat \
	  $(COV_DIR)/loop_pred/coverage.dat \
	  $(COV_DIR)/history/coverage.dat \
	  $(COV_DIR)/ubtb/coverage.dat
	verilator_coverage \
	  --write-info $(COV_DIR)/bpu/coverage.info \
	  $(COV_DIR)/bpu/coverage.dat
	genhtml --prefix $(RVA_ROOT) \
	  --output-directory $(COV_DIR)/bpu/html \
	  $(COV_DIR)/bpu/coverage.info
	@echo "cov_bpu: merged HTML at $(COV_DIR)/bpu/html/index.html"

clean_cov_tage:
	rm -rf obj_dir_cov_tage $(COV_DIR)/tage

clean_cov_tage_table:
	rm -rf obj_dir_cov_tage_table $(COV_DIR)/tage_table

clean_cov_loop_pred:
	rm -rf obj_dir_cov_loop_pred $(COV_DIR)/loop_pred

clean_cov_history:
	rm -rf obj_dir_cov_history $(COV_DIR)/history

clean_cov_ubtb:
	rm -rf obj_dir_cov_ubtb $(COV_DIR)/ubtb

clean_cov_bpu:
	rm -rf $(COV_DIR)/bpu

clean_cov: clean_cov_tage clean_cov_tage_table \
  clean_cov_loop_pred clean_cov_history \
  clean_cov_ubtb clean_cov_bpu
