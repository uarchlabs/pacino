# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- fetch target queue
# Targets: lint_ftq_ftb_sched, sim_ftq_ftb_sched, all (default), clean
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
BPU_DIR  := ../bpu/rtl
VER_OUT  := obj

VER_FLAGS       := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing
SIM_EXTRA_FLAGS := -Wno-DECLFILENAME

# -Wno-SYNCASYNCNET: rstn is an async reset on the scheduler's flops
# and appears synchronously in every property's `disable iff (!rstn)`.
# That combination is structural to any module carrying both an async
# reset and concurrent SVA, not a defect. lint_bp_cluster is the
# precedent; as there, it is applied per target rather than added to
# VER_FLAGS.
#
# The bind statement of ftq_ftb_sched_assert.sv sits at file scope,
# outside any module, which is what a bind must do. Verilator reports
# the assertion module itself as unused when it is elaborated only
# through the bind; -Wno-UNUSED in VER_FLAGS already covers it.
SCHED_SRCS := \
  $(BPU_DIR)/bp_defines_pkg.sv \
  $(BPU_DIR)/bp_structs_pkg.sv \
  $(RTL_DIR)/ftq_ftb_sched.sv \
  $(RTL_DIR)/ftq_ftb_sched_assert.sv

.PHONY: all lint_ftq_ftb_sched sim_ftq_ftb_sched clean

all: lint_ftq_ftb_sched sim_ftq_ftb_sched

# -- FTB update scheduler (ftq_ftb_sched.sv, BP-100).
#    --assert is required for the concurrent SVA to be elaborated at
#    all. Without it Verilator parses the properties and generates
#    nothing, so the assertions would silently never fire -- the
#    defect class this project has hit twice.
lint_ftq_ftb_sched:
	@echo "[linting]    ftq_ftb_sched"
	$(Q)$(VERILATOR) --lint-only \
	  $(VER_FLAGS) \
	  -Wno-SYNCASYNCNET \
	  --assert \
	  --top-module ftq_ftb_sched \
	  $(SCHED_SRCS) $(VSILENCE)

sim_ftq_ftb_sched:
	@echo "[compiling]  tb_ftq_ftb_sched"
	$(Q)$(VERILATOR) --binary \
	  $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  -Wno-SYNCASYNCNET \
	  --assert \
	  --top-module tb \
	  --Mdir $(VER_OUT)_ftq_ftb_sched \
	  $(SCHED_SRCS) \
	  $(TB_DIR)/tb_ftq_ftb_sched.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftq_ftb_sched/Vtb"
	$(Q)./$(VER_OUT)_ftq_ftb_sched/Vtb

clean:
	@echo "[cleaning]   ftq"
	$(Q)rm -rf $(VER_OUT)*
