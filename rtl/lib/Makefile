# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# rtl/lib/Makefile
include $(RVA_ROOT)/rtl/Vars.mk

ifeq ($(VERBOSE),1)
  Q :=
else
  Q :=
  MAKEFLAGS := -s --no-print-directory
endif

RTL_FILES = \
  ./rtl/bw_ram.sv \
  ./rtl/sat_alu.sv \
  ./rtl/dual_lm1.sv \
  ./rtl/sram_init.sv
TB_FILE  = tb/tb_components.sv
ALL_SV   = $(RTL_FILES) $(TB_FILE)
SIM_DIR  = obj_dir
VER_FLAGS = -Wall -Wno-DECLFILENAME -Wno-IMPORTSTAR -Wno-UNUSED \
  --timing

.PHONY: all sim lint clean

all: lint sim

sim: $(SIM_DIR)/Vtb
	@echo "[simulating] $(SIM_DIR)/Vtb"
	$(Q)$(SIM_DIR)/Vtb

$(SIM_DIR)/Vtb: $(ALL_SV)
	@for f in $(ALL_SV); do echo "[compiling]  $$f"; done
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) \
	  -Mdir $(SIM_DIR) \
	  $(ALL_SV) \
	  --top-module tb

lint:
	@for f in $(ALL_SV); do echo "[linting]    $$f"; done
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) \
	  $(ALL_SV) \
	  --top-module tb

clean:
	$(Q)rm -rf $(SIM_DIR) simv simv.daidir csrc \
	  *.log *.vpd *.vcd

# -- Regression plumbing (TOOLS-006) ----------------------------------
# tools/regress.sh runs every REGRESS_TARGETS entry with its own make
# call and fails if a target defined in this file is in neither list.
# Exclusions:
#   all                - aggregate of lint and sim.
#   $(SIM_DIR)/Vtb     - build helper, run through sim.
#   clean, regress_list - housekeeping and this plumbing.
REGRESS_TARGETS := lint sim
REGRESS_EXCLUDE := all $(SIM_DIR)/Vtb clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
