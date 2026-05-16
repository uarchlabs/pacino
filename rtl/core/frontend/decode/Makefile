# Makefile - decoder unit
# Requires Verilator 5.020
#
# Targets:
#   lint_exp        - lint rvc_expander only
#   lint_dec        - lint instr_decoder only
#   lint_predecode  - lint predecode only
#   lint            - lint all three modules
#   sim_exp         - build and run rvc_expander testbench
#   sim_dec         - build and run instr_decoder testbench
#   sim_predecode   - build and run predecode testbench
#   sim             - run sim_exp and sim_dec (existing targets)
#   sim_all         - run sim_predecode, sim_dec, and coverage
#   coverage        - run RVA23 coverage check script
#   clean           - remove build artifacts

VERILATOR       = verilator
# -Wno-DECLFILENAME: testbench files named tb_<dut>.sv contain module 'tb'
# -Wno-TIMESCALEMOD: package files cannot carry timescale directives
VERILATOR_FLAGS = --cc --exe --build --sv -Wall \
                  -Wno-DECLFILENAME -Wno-TIMESCALEMOD --timing

TOOLS           = ../../../../tools

PKG             = rtl/decode_pkg.sv

RTL_EXP         = rtl/rvc_expander.sv
RTL_DEC         = rtl/instr_decoder.sv
RTL_PRE         = rtl/predecode.sv

TB_EXP          = tb/tb_rvc_expander.sv
TB_DEC          = tb/tb_instr_decoder.sv
TB_PRE          = tb/tb_predecode.sv

SIM_MAIN_EXP    = verilator/sim_main_exp.cpp
SIM_MAIN_DEC    = verilator/sim_main.cpp
SIM_MAIN_PRE    = verilator/sim_main_predecode.cpp

OBJ_EXP         = obj_dir_exp
OBJ_DEC         = obj_dir_dec
OBJ_PRE         = obj_dir_pre

.PHONY: lint lint_exp lint_dec lint_predecode \
        sim sim_exp sim_dec sim_predecode sim_all \
        coverage clean help

all: lint sim sim_all

# -- lint only
lint_exp:
	$(VERILATOR) --lint-only --sv -Wall $(PKG) $(RTL_EXP)

lint_dec:
	$(VERILATOR) --lint-only --sv -Wall $(PKG) $(RTL_DEC)

lint_predecode:
	$(VERILATOR) --lint-only --sv -Wall $(PKG) $(RTL_PRE)

lint: lint_exp lint_dec lint_predecode

# -- build and run rvc_expander simulation
sim_exp:
	mkdir -p $(OBJ_EXP)
	$(VERILATOR) $(VERILATOR_FLAGS) \
	    --top-module tb \
	    --Mdir $(OBJ_EXP) \
	    $(PKG) $(TB_EXP) $(RTL_EXP) \
	    $(SIM_MAIN_EXP) \
	    -o sim_exp
	./$(OBJ_EXP)/sim_exp

# -- build and run instr_decoder simulation
sim_dec:
	mkdir -p $(OBJ_DEC)
	$(VERILATOR) $(VERILATOR_FLAGS) \
	    --top-module tb \
	    --Mdir $(OBJ_DEC) \
	    $(PKG) $(TB_DEC) $(RTL_DEC) \
	    $(SIM_MAIN_DEC) \
	    -o sim_dec
	./$(OBJ_DEC)/sim_dec

# -- build and run predecode simulation
sim_predecode:
	mkdir -p $(OBJ_PRE)
	$(VERILATOR) $(VERILATOR_FLAGS) \
	    --top-module tb \
	    --Mdir $(OBJ_PRE) \
	    $(PKG) $(TB_PRE) $(RTL_PRE) \
	    $(SIM_MAIN_PRE) \
	    -o sim_predecode
	./$(OBJ_PRE)/sim_predecode

# -- run sim_exp and sim_dec (existing combined target)
sim: sim_exp sim_dec

# -- run predecode and instr_decoder testbenches
sim_all: sim_predecode sim_dec coverage

# -- run RVA23 coverage check (exit 1 if any MISSING instructions found)
coverage:
	@python3 $(TOOLS)/check_rva23_coverage.py; \
	rc=$$?; \
	if [ $$rc -eq 0 ]; then \
	  echo "coverage: PASS (no MISSING instructions)"; \
	else \
	  echo "coverage: FAIL (MISSING instructions found)"; \
	  exit 1; \
	fi

# -- remove build artifacts
clean:
	rm -rf $(OBJ_EXP) $(OBJ_DEC) $(OBJ_PRE)

# -- print available targets
help:
	@echo "Targets:"
	@echo "  lint_exp       - lint rvc_expander"
	@echo "  lint_dec       - lint instr_decoder"
	@echo "  lint_predecode - lint predecode"
	@echo "  lint           - lint all three modules"
	@echo "  sim_exp        - build and run rvc_expander testbench"
	@echo "  sim_dec        - build and run instr_decoder testbench"
	@echo "  sim_predecode  - build and run predecode testbench"
	@echo "  sim            - run sim_exp and sim_dec"
	@echo "  sim_all        - run sim_predecode, sim_dec, coverage"
	@echo "  coverage       - run RVA23 coverage check script"
	@echo "  clean          - remove build artifacts"
