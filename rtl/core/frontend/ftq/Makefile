# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- fetch target queue
#
# TARGETS. Eleven modules, a lint and a sim for each, plus all and
# clean. `all` is kept complete deliberately, but a run must still
# ENUMERATE the targets rather than assume all covers them:
#
#   lint_ftq_ftb_sched   sim_ftq_ftb_sched    BP-100
#   lint_ftq_ptr         sim_ftq_ptr          BP-106, BP-107
#   lint_ftq_commit      sim_ftq_commit       BP-106, BP-107
#   lint_ftq_entry       sim_ftq_entry        BP-107
#   lint_ftq_meta        sim_ftq_meta         BP-107
#   lint_ftq_status      sim_ftq_status       BP-107
#   lint_ftq_shadow      sim_ftq_shadow       BP-107
#   lint_ftq_npc         sim_ftq_npc          BP-107
#   lint_ftq_ifu         sim_ftq_ifu          BP-107
#   lint_ftq_resolve     sim_ftq_resolve      BP-107
#   lint_ftq             sim_ftq              BP-107, the unit
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

# -Wno-SYNCASYNCNET: rstn is an async reset on the flops of every
# module here and appears synchronously in every property's
# `disable iff (!rstn)`. That combination is structural to any module
# carrying both an async reset and concurrent SVA, not a defect.
# lint_bp_cluster is the precedent; as there, it is applied per
# target rather than added to VER_FLAGS.
#
# --assert is required for the concurrent SVA to be ELABORATED AT
# ALL. Without it Verilator parses the properties and generates
# nothing, so the assertions silently never fire -- the defect class
# this project has shipped twice (TD#109). Every target below carries
# it, lint and sim alike.
#
# The bind statement of each *_assert.sv sits at file scope, outside
# any module, which is what a bind must do. The assertion module is
# reported unused when it is elaborated only through the bind;
# -Wno-UNUSED in VER_FLAGS already covers it.
COMMON := -Wno-SYNCASYNCNET --assert

PKG_SRCS := \
  $(BPU_DIR)/bp_defines_pkg.sv \
  $(BPU_DIR)/bp_structs_pkg.sv

# ASSERTION COLLATERAL LIVES IN tb/, NOT rtl/ (BP-108). rtl/ holds
# only synthesisable RTL; a *_assert.sv module and its bind are
# verification collateral. This matches the bpu unit, whose
# ittage_assert.sv, tage_assert.sv and tage_assert_bind.sv are all
# named as $(TB_DIR)/... The binds are by MODULE NAME (TD#109), so
# the directory a file sits in does not affect what it binds to.
# Every source list below keeps its assertion file, lint and sim
# alike, so the ten files retain lint coverage after the move.

SCHED_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ftq_ftb_sched.sv \
  $(TB_DIR)/ftq_ftb_sched_assert.sv

PTR_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ftq_ptr.sv \
  $(TB_DIR)/ftq_ptr_assert.sv

COMMIT_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ftq_commit.sv \
  $(TB_DIR)/ftq_commit_assert.sv

ENTRY_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ftq_entry.sv \
  $(TB_DIR)/ftq_entry_assert.sv

META_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ftq_meta.sv \
  $(TB_DIR)/ftq_meta_assert.sv

STATUS_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ftq_status.sv \
  $(TB_DIR)/ftq_status_assert.sv

SHADOW_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ftq_shadow.sv \
  $(TB_DIR)/ftq_shadow_assert.sv

NPC_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ftq_npc.sv \
  $(TB_DIR)/ftq_npc_assert.sv

IFU_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ftq_ifu.sv \
  $(TB_DIR)/ftq_ifu_assert.sv

RESOLVE_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ftq_resolve.sv \
  $(TB_DIR)/ftq_resolve_assert.sv

# The unit. Every leaf and every assertion file, plus the structural
# top. The order is packages first, then leaves, then ftq.sv.
FTQ_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ftq_ptr.sv          $(TB_DIR)/ftq_ptr_assert.sv \
  $(RTL_DIR)/ftq_commit.sv       $(TB_DIR)/ftq_commit_assert.sv \
  $(RTL_DIR)/ftq_entry.sv        $(TB_DIR)/ftq_entry_assert.sv \
  $(RTL_DIR)/ftq_meta.sv         $(TB_DIR)/ftq_meta_assert.sv \
  $(RTL_DIR)/ftq_status.sv       $(TB_DIR)/ftq_status_assert.sv \
  $(RTL_DIR)/ftq_shadow.sv       $(TB_DIR)/ftq_shadow_assert.sv \
  $(RTL_DIR)/ftq_npc.sv          $(TB_DIR)/ftq_npc_assert.sv \
  $(RTL_DIR)/ftq_ifu.sv          $(TB_DIR)/ftq_ifu_assert.sv \
  $(RTL_DIR)/ftq_resolve.sv      $(TB_DIR)/ftq_resolve_assert.sv \
  $(RTL_DIR)/ftq_ftb_sched.sv    $(TB_DIR)/ftq_ftb_sched_assert.sv \
  $(RTL_DIR)/ftq.sv

.PHONY: all clean \
  lint_ftq_ftb_sched sim_ftq_ftb_sched \
  lint_ftq_ptr       sim_ftq_ptr \
  lint_ftq_commit    sim_ftq_commit \
  lint_ftq_entry     sim_ftq_entry \
  lint_ftq_meta      sim_ftq_meta \
  lint_ftq_status    sim_ftq_status \
  lint_ftq_shadow    sim_ftq_shadow \
  lint_ftq_npc       sim_ftq_npc \
  lint_ftq_ifu       sim_ftq_ifu \
  lint_ftq_resolve   sim_ftq_resolve \
  lint_ftq           sim_ftq

all: lint_ftq_ftb_sched sim_ftq_ftb_sched \
     lint_ftq_ptr       sim_ftq_ptr \
     lint_ftq_commit    sim_ftq_commit \
     lint_ftq_entry     sim_ftq_entry \
     lint_ftq_meta      sim_ftq_meta \
     lint_ftq_status    sim_ftq_status \
     lint_ftq_shadow    sim_ftq_shadow \
     lint_ftq_npc       sim_ftq_npc \
     lint_ftq_ifu       sim_ftq_ifu \
     lint_ftq_resolve   sim_ftq_resolve \
     lint_ftq           sim_ftq

# -- FTB update scheduler (ftq_ftb_sched.sv, BP-100).
lint_ftq_ftb_sched:
	@echo "[linting]    ftq_ftb_sched"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ftq_ftb_sched \
	  $(SCHED_SRCS) $(VSILENCE)

sim_ftq_ftb_sched:
	@echo "[compiling]  tb_ftq_ftb_sched"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ftq_ftb_sched \
	  $(SCHED_SRCS) $(TB_DIR)/tb_ftq_ftb_sched.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftq_ftb_sched/Vtb"
	$(Q)./$(VER_OUT)_ftq_ftb_sched/Vtb

# -- FTQ head and middle pointers (ftq_ptr.sv, BP-106 / BP-107).
lint_ftq_ptr:
	@echo "[linting]    ftq_ptr"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ftq_ptr \
	  $(PTR_SRCS) $(VSILENCE)

sim_ftq_ptr:
	@echo "[compiling]  tb_ftq_ptr"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ftq_ptr \
	  $(PTR_SRCS) $(TB_DIR)/tb_ftq_ptr.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftq_ptr/Vtb"
	$(Q)./$(VER_OUT)_ftq_ptr/Vtb

# -- FTQ tail pointer and commit walk (ftq_commit.sv).
lint_ftq_commit:
	@echo "[linting]    ftq_commit"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ftq_commit \
	  $(COMMIT_SRCS) $(VSILENCE)

sim_ftq_commit:
	@echo "[compiling]  tb_ftq_commit"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ftq_commit \
	  $(COMMIT_SRCS) $(TB_DIR)/tb_ftq_commit.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftq_commit/Vtb"
	$(Q)./$(VER_OUT)_ftq_commit/Vtb

# -- Fast-path entry array (ftq_entry.sv).
lint_ftq_entry:
	@echo "[linting]    ftq_entry"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ftq_entry \
	  $(ENTRY_SRCS) $(VSILENCE)

sim_ftq_entry:
	@echo "[compiling]  tb_ftq_entry"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ftq_entry \
	  $(ENTRY_SRCS) $(TB_DIR)/tb_ftq_entry.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftq_entry/Vtb"
	$(Q)./$(VER_OUT)_ftq_entry/Vtb

# -- Slow-path metadata array (ftq_meta.sv).
lint_ftq_meta:
	@echo "[linting]    ftq_meta"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ftq_meta \
	  $(META_SRCS) $(VSILENCE)

sim_ftq_meta:
	@echo "[compiling]  tb_ftq_meta"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ftq_meta \
	  $(META_SRCS) $(TB_DIR)/tb_ftq_meta.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftq_meta/Vtb"
	$(Q)./$(VER_OUT)_ftq_meta/Vtb

# -- Per-entry fetch status (ftq_status.sv).
lint_ftq_status:
	@echo "[linting]    ftq_status"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ftq_status \
	  $(STATUS_SRCS) $(VSILENCE)

sim_ftq_status:
	@echo "[compiling]  tb_ftq_status"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ftq_status \
	  $(STATUS_SRCS) $(TB_DIR)/tb_ftq_status.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftq_status/Vtb"
	$(Q)./$(VER_OUT)_ftq_status/Vtb

# -- In-flight response shadow (ftq_shadow.sv).
lint_ftq_shadow:
	@echo "[linting]    ftq_shadow"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ftq_shadow \
	  $(SHADOW_SRCS) $(VSILENCE)

sim_ftq_shadow:
	@echo "[compiling]  tb_ftq_shadow"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ftq_shadow \
	  $(SHADOW_SRCS) $(TB_DIR)/tb_ftq_shadow.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftq_shadow/Vtb"
	$(Q)./$(VER_OUT)_ftq_shadow/Vtb

# -- Next-PC register and redirect arbitration (ftq_npc.sv).
lint_ftq_npc:
	@echo "[linting]    ftq_npc"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ftq_npc \
	  $(NPC_SRCS) $(VSILENCE)

sim_ftq_npc:
	@echo "[compiling]  tb_ftq_npc"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ftq_npc \
	  $(NPC_SRCS) $(TB_DIR)/tb_ftq_npc.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftq_npc/Vtb"
	$(Q)./$(VER_OUT)_ftq_npc/Vtb

# -- IFU boundary (ftq_ifu.sv).
lint_ftq_ifu:
	@echo "[linting]    ftq_ifu"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ftq_ifu \
	  $(IFU_SRCS) $(VSILENCE)

sim_ftq_ifu:
	@echo "[compiling]  tb_ftq_ifu"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ftq_ifu \
	  $(IFU_SRCS) $(TB_DIR)/tb_ftq_ifu.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftq_ifu/Vtb"
	$(Q)./$(VER_OUT)_ftq_ifu/Vtb

# -- Resolution intake and update fan-out (ftq_resolve.sv).
lint_ftq_resolve:
	@echo "[linting]    ftq_resolve"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ftq_resolve \
	  $(RESOLVE_SRCS) $(VSILENCE)

sim_ftq_resolve:
	@echo "[compiling]  tb_ftq_resolve"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ftq_resolve \
	  $(RESOLVE_SRCS) $(TB_DIR)/tb_ftq_resolve.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftq_resolve/Vtb"
	$(Q)./$(VER_OUT)_ftq_resolve/Vtb

# -- The unit (ftq.sv, structural top). Every leaf is elaborated
#    under it and every bound property runs, so this target is also
#    where the properties see the traffic the whole unit produces
#    rather than one module's directed stimulus.
lint_ftq:
	@echo "[linting]    ftq"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ftq \
	  $(FTQ_SRCS) $(VSILENCE)

sim_ftq:
	@echo "[compiling]  tb_ftq"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ftq \
	  $(FTQ_SRCS) $(TB_DIR)/tb_ftq.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftq/Vtb"
	$(Q)./$(VER_OUT)_ftq/Vtb

clean:
	@echo "[cleaning]   ftq"
	$(Q)rm -rf $(VER_OUT)*
