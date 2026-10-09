# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- fetch target queue
#
# TARGETS. Twelve modules, a lint and a sim for each, plus all and
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
#   lint_ftq_upd_conv    sim_ftq_upd_conv     BP-119, TD#151
#   lint_ftq             sim_ftq              BP-107, the unit
#   assert_labels                             BP-116, TD#144
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

# tb_ftq_ifu group J (BP-116) writes an ftq_entry from ftq_ifu's
# pd_wr_* outputs, so the sim adds that leaf and its properties. The
# lint target stays ftq_ifu alone.
IFU_TB_SRCS := \
  $(IFU_SRCS) \
  $(RTL_DIR)/ftq_entry.sv \
  $(TB_DIR)/ftq_entry_assert.sv

RESOLVE_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ftq_resolve.sv \
  $(TB_DIR)/ftq_resolve_assert.sv

UPD_CONV_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ftq_upd_conv.sv \
  $(TB_DIR)/ftq_upd_conv_assert.sv

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
  $(RTL_DIR)/ftq_upd_conv.sv     $(TB_DIR)/ftq_upd_conv_assert.sv \
  $(RTL_DIR)/ftq_ftb_sched.sv    $(TB_DIR)/ftq_ftb_sched_assert.sv \
  $(RTL_DIR)/ftq.sv              $(TB_DIR)/ftq_assert.sv

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
  lint_ftq_upd_conv  sim_ftq_upd_conv \
  lint_ftq           sim_ftq \
  assert_labels

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
     lint_ftq_upd_conv  sim_ftq_upd_conv \
     lint_ftq           sim_ftq \
     assert_labels

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
	  $(IFU_TB_SRCS) $(TB_DIR)/tb_ftq_ifu.sv $(VSILENCE)
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

# -- The update converter (ftq_upd_conv.sv, BP-119, TD#151).
lint_ftq_upd_conv:
	@echo "[linting]    ftq_upd_conv"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module ftq_upd_conv \
	  $(UPD_CONV_SRCS) $(VSILENCE)

sim_ftq_upd_conv:
	@echo "[compiling]  tb_ftq_upd_conv"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_ftq_upd_conv \
	  $(UPD_CONV_SRCS) $(TB_DIR)/tb_ftq_upd_conv.sv $(VSILENCE)
	@echo "[simulating] $(VER_OUT)_ftq_upd_conv/Vtb"
	$(Q)./$(VER_OUT)_ftq_upd_conv/Vtb

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

# -- Every declared property is in every sim model (BP-116, TD#144).
#    INFRA-013's method. Each sim model is verilated to C++ (--cc, the
#    sim target's flags and sources, no compile) into its own
#    obj_labels_* directory, so the result does not depend on any
#    other target having run. Verilator writes an assertion's full
#    hierarchical path into the C++ as a string, ending ".<label>"; a
#    generate-loop label appears once per iteration. A label declared
#    in an assertion file the model compiles but absent from its C++
#    has been folded to a constant, and the target fails. It also
#    fails on an unlabeled assert property, which this cannot check,
#    and on a tb/*_assert.sv that no model compiles.
#    A kept tautology still passes: this guards removal, not meaning.
LABEL_MODELS := ftq_ftb_sched ftq_ptr ftq_commit ftq_entry ftq_meta \
                ftq_status ftq_shadow ftq_npc ftq_ifu ftq_resolve \
                ftq_upd_conv ftq

LABEL_SRCS_ftq_ftb_sched := $(SCHED_SRCS)
LABEL_SRCS_ftq_ptr       := $(PTR_SRCS)
LABEL_SRCS_ftq_commit    := $(COMMIT_SRCS)
LABEL_SRCS_ftq_entry     := $(ENTRY_SRCS)
LABEL_SRCS_ftq_meta      := $(META_SRCS)
LABEL_SRCS_ftq_status    := $(STATUS_SRCS)
LABEL_SRCS_ftq_shadow    := $(SHADOW_SRCS)
LABEL_SRCS_ftq_npc       := $(NPC_SRCS)
LABEL_SRCS_ftq_ifu       := $(IFU_TB_SRCS)
LABEL_SRCS_ftq_resolve   := $(RESOLVE_SRCS)
LABEL_SRCS_ftq_upd_conv  := $(UPD_CONV_SRCS)
LABEL_SRCS_ftq           := $(FTQ_SRCS)

LABEL_ASSERT_FILES := $(sort $(wildcard $(TB_DIR)/*_assert.sv))
LABEL_UNCOMPILED   := $(filter-out \
  $(foreach m,$(LABEL_MODELS),$(LABEL_SRCS_$(m))),$(LABEL_ASSERT_FILES))

# A labeled assertion: "<label> : assert property".
LABEL_RE := ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:
LABEL_RE := $(LABEL_RE)[[:space:]]*assert[[:space:]]+property

# One model: verilate, then look up each label of each assertion file
# it compiles. $(1) model, $(2) its sources. Shell variables tot, mis
# accumulate across models.
label_sh = $(VERILATOR) --cc $(VER_FLAGS) $(SIM_EXTRA_FLAGS) $(COMMON) \
  --top-module tb --Mdir $(VER_OUT)_labels_$(1) \
  $(2) $(TB_DIR)/tb_$(1).sv > /dev/null || exit 1; \
  n=0; m=0; \
  for f in $(filter %_assert.sv,$(2)); do \
    for l in $$(sed -nE 's/$(LABEL_RE).*/\1/p' $$f); do \
      n=$$((n+1)); \
      if ! grep -qF ".$$l\"" $(VER_OUT)_labels_$(1)/*.cpp; then \
        echo "MISSING: $$l ($$f) is not in the tb_$(1) model"; \
        m=$$((m+1)); \
      fi; \
    done; \
  done; \
  echo "  tb_$(1): $$((n-m)) of $$n labels present"; \
  tot=$$((tot+n)); mis=$$((mis+m));

assert_labels:
	@echo "[checking]   assertion labels in the sim models"
	$(Q)if [ -n "$(strip $(LABEL_UNCOMPILED))" ]; then \
	  echo "UNCOMPILED: $(LABEL_UNCOMPILED)"; exit 1; fi
	$(Q)for f in $(LABEL_ASSERT_FILES); do \
	  a=$$(grep -cE 'assert[[:space:]]+property' $$f); \
	  b=$$(grep -cE '$(LABEL_RE)' $$f); \
	  echo "  $$f: $$b labels: $$(sed -nE 's/$(LABEL_RE).*/\1/p' $$f \
	    | tr '\n' ' ')"; \
	  if [ $$a -ne $$b ]; then \
	    echo "UNLABELED: $$f has $$((a-b)) unlabeled assert property"; \
	    exit 1; fi; \
	done
	$(Q)tot=0; mis=0; \
	$(foreach m,$(LABEL_MODELS),$(call label_sh,$(m),$(LABEL_SRCS_$(m)))) \
	echo "assert_labels: PASS=$$((tot-mis)) FAIL=$$mis"; \
	test $$mis -eq 0

clean:
	@echo "[cleaning]   ftq"
	$(Q)rm -rf $(VER_OUT)*

# -- Regression plumbing (TOOLS-006) ----------------------------------
# tools/regress.sh runs every REGRESS_TARGETS entry with its own make
# call and fails if a target defined in this file is in neither list.
# Exclusions:
#   all                 - aggregate.
#   clean, regress_list - housekeeping and this plumbing.
REGRESS_TARGETS := \
  lint_ftq_ftb_sched sim_ftq_ftb_sched lint_ftq_ptr sim_ftq_ptr \
  lint_ftq_commit sim_ftq_commit lint_ftq_entry sim_ftq_entry \
  lint_ftq_meta sim_ftq_meta lint_ftq_status sim_ftq_status \
  lint_ftq_shadow sim_ftq_shadow lint_ftq_npc sim_ftq_npc \
  lint_ftq_ifu sim_ftq_ifu lint_ftq_resolve sim_ftq_resolve \
  lint_ftq_upd_conv sim_ftq_upd_conv lint_ftq sim_ftq assert_labels
REGRESS_EXCLUDE := all clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
