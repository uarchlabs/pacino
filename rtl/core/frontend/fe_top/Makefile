# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- front-end top (BP-118), fe_decisions.md 15
#
# TARGETS:
#
#   lint_fe_top     the structural top over every front-end unit and
#                   the emitted L1I (FE-21), warnings on
#   sim_fe_top      tb/tb_fe_top.sv: every program, each in its own
#                   simulation, against a memory model, the page table
#                   walker (rtl/mmu/ptw, BP-123) and a backend model,
#                   with every unit's bound properties compiled in
#   sim_fe_top_<p>  one program (+PROG=<p>), one per program of
#                   FE_PROGS (BP-121): each is its own regression
#                   target
#   assert_labels   every property label of every assertion file the
#                   sim model compiles is present in it
#   <t>_1slot       target <t> at NUM_PRED_SLOTS = 1, one per target
#                   above (BP-128)
#
# THE L1I IS THE PACINO COPY in rtl/core/frontend/icache (BP-123,
# cachegen_decisions.md CG-D1): the cachegen emission copied into the
# tree and changed there. Nothing under tools/ is compiled. Its files
# carry their own lint waivers in source and pass -Wall here with
# nothing waived on their behalf.
RVA_ROOT ?= $(abspath ../../../..)
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
FE_DIR   := ..
BPU_DIR  := $(FE_DIR)/bpu/rtl
BPU_TB   := $(FE_DIR)/bpu/tb
FTQ_DIR  := $(FE_DIR)/ftq/rtl
FTQ_TB   := $(FE_DIR)/ftq/tb
IFU_DIR  := $(FE_DIR)/ifu/rtl
IFU_TB   := $(FE_DIR)/ifu/tb
IBUF_DIR := $(FE_DIR)/ibuf/rtl
IBUF_TB  := $(FE_DIR)/ibuf/tb
DEC_DIR  := $(FE_DIR)/decode/rtl
COMP_DIR := $(RVA_ROOT)/rtl/lib/rtl
ITLB_DIR := $(RVA_ROOT)/rtl/mmu/itlb/rtl
ITLB_TB  := $(RVA_ROOT)/rtl/mmu/itlb/tb
PMP_DIR  := $(RVA_ROOT)/rtl/mmu/pmp/rtl
PTW_DIR  := $(RVA_ROOT)/rtl/mmu/ptw/rtl
PTW_TB   := $(RVA_ROOT)/rtl/mmu/ptw/tb
L1I_DIR  := $(FE_DIR)/icache/rtl
L1I_TB   := $(FE_DIR)/icache/tb
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
#   make lint_fe_top_1slot SLOT1_DEFS=+define+BP_EXPECT_PRED_SLOTS=1
SLOT1_DEFS := +define+BP_NUM_PRED_SLOTS=1 +define+BP_EXPECT_PRED_SLOTS=1
SLOT_DEFS  ?=

VER_FLAGS       := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing \
                   $(SLOT_DEFS)
SIM_EXTRA_FLAGS := -Wno-DECLFILENAME

# VARHIDDEN: the loop_pred.sv module parameters LP_TBL_ENTRIES to
# LP_CONF_LEVEL shadow the bp_defines_pkg parameters of the same names
# (as lint_bp_cluster). Until BP-128 this named the tage, sc and ubtb
# NUM_PRED_SLOTS parameters, which BP-128 removed. SYNCASYNCNET: async
# rstn with disable iff in the bound properties, and sram_init.
# --assert so the bound properties are elaborated (TD#109).
COMMON := -Wno-VARHIDDEN -Wno-SYNCASYNCNET --assert

PKG_SRCS := \
  $(BPU_DIR)/bp_defines_pkg.sv \
  $(BPU_DIR)/bp_structs_pkg.sv \
  $(DEC_DIR)/decode_pkg.sv

# The L1I, in the order of the emitted filelist (l1i.f), with the
# BP-123 maintenance control. cgen_tl_pkg is the one shared emitted
# package it imports.
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

UNIT_SRCS := \
  $(BPU_SRCS) \
  $(FTQ_SRCS) \
  $(IFU_SRCS) \
  $(IBUF_DIR)/ibuf.sv \
  $(PMP_DIR)/pmp_pma_chk.sv \
  $(ITLB_DIR)/itlb.sv \
  $(DEC_DIR)/instr_decoder.sv

TOP_SRCS := $(PKG_SRCS) $(L1I_SRCS) $(UNIT_SRCS) $(RTL_DIR)/fe_top.sv

# The walker is outside the top (MMU-1a); tb_fe_top instantiates it.
PTW_SRCS := $(PTW_DIR)/ptw.sv

# Every unit's bound properties, by module name (TD#109), so the
# integration runs under each unit's own rules.
ASSERT_SRCS := \
  $(FTQ_TB)/ftq_ptr_assert.sv \
  $(FTQ_TB)/ftq_commit_assert.sv \
  $(FTQ_TB)/ftq_entry_assert.sv \
  $(FTQ_TB)/ftq_meta_assert.sv \
  $(FTQ_TB)/ftq_status_assert.sv \
  $(FTQ_TB)/ftq_shadow_assert.sv \
  $(FTQ_TB)/ftq_npc_assert.sv \
  $(FTQ_TB)/ftq_ifu_assert.sv \
  $(FTQ_TB)/ftq_resolve_assert.sv \
  $(FTQ_TB)/ftq_upd_conv_assert.sv \
  $(FTQ_TB)/ftq_ftb_sched_assert.sv \
  $(FTQ_TB)/ftq_assert.sv \
  $(BPU_TB)/bp_history_assert.sv \
  $(BPU_TB)/loop_pred_assert.sv \
  $(BPU_TB)/ras_assert.sv \
  $(IFU_TB)/ifu_xlate_assert.sv \
  $(IFU_TB)/ifu_f3_assert.sv \
  $(IFU_TB)/ifu_assert.sv \
  $(IBUF_TB)/ibuf_assert.sv \
  $(ITLB_TB)/itlb_assert.sv \
  $(L1I_TB)/l1i_assert.sv \
  $(L1I_TB)/l1i_mshr_assert.sv \
  $(PTW_TB)/ptw_assert.sv

SIM_SRCS := $(TOP_SRCS) $(PTW_SRCS) $(ASSERT_SRCS)

FE_PLUSARGS := +TAGE_FAST_INIT=1 +ITTAGE_FAST_INIT=1 +SC_FAST_INIT=1

# The tb_fe_top programs (BP-121), each run alone by sim_fe_top_<p>.
# BP-123 added fencei to pt_inv: maintenance, uncached fetch and the
# page table walker in RTL. BP-124 added pt_upriv (MMU-8c, ITLB-10b).
# BP-134 added rec_undo (an undo-pop over a recursion pop, TD#78).
FE_PROGS := bare sv39 loops coro calls lp hist twocond ftbonly nest \
            recur rec_undo deep indir region multistart cross rvc \
            misp_call jals fencei cboinval uc_nc uc_io pt_faults_s \
            pt_faults_h \
            pt_napot_s pt_napot_h pt_rsv_s pt_rsv_h pt_ad_s pt_ad_h pt_inv \
            zstar pt_gonly pt_vsonly pt_upriv
FE_PROG_TGTS := $(addprefix sim_fe_top_,$(FE_PROGS))

.PHONY: all clean assert_labels lint_fe_top sim_fe_top build_fe_top \
        $(FE_PROG_TGTS)

all: lint_fe_top sim_fe_top assert_labels

lint_fe_top:
	@echo "[linting]    fe_top"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module fe_top $(TOP_SRCS) $(VSILENCE)

build_fe_top:
	@echo "[compiling]  tb_fe_top"
	$(Q)$(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
	  $(COMMON) --top-module tb --Mdir $(VER_OUT)_fe_top \
	  $(SIM_SRCS) $(TB_DIR)/tb_fe_top.sv $(VSILENCE)

# Every program in its own simulation (BP-121): in one simulation the
# predictor tables carry from one program into the next, so a program's
# counts would depend on the programs before it. The totals line sums
# the per-program check counts.
sim_fe_top: build_fe_top
	@echo "[simulating] $(VER_OUT)_fe_top/Vtb, each of $(FE_PROGS)"
	$(Q)tp=0; tf=0; bad=0; \
	for g in $(FE_PROGS); do \
	  log=$(VER_OUT)_fe_top/sim_$$g.log; \
	  ./$(VER_OUT)_fe_top/Vtb $(FE_PLUSARGS) +PROG=$$g > $$log 2>&1 \
	    || bad=1; \
	  cat $$log; \
	  m=$$(grep -oE 'PASS=[0-9]+ FAIL=[0-9]+' $$log | tail -1); \
	  if [ -z "$$m" ]; then bad=1; continue; fi; \
	  p=$${m#PASS=}; p=$${p%% *}; f=$${m##*FAIL=}; \
	  tp=$$((tp + p)); tf=$$((tf + f)); \
	done; \
	echo "sim_fe_top: $(words $(FE_PROGS)) programs, one simulation each"; \
	echo "tb_fe_top: PASS=$$tp FAIL=$$tf"; \
	test $$bad -eq 0 && test $$tf -eq 0

$(FE_PROG_TGTS): sim_fe_top_%: build_fe_top
	@echo "[simulating] $(VER_OUT)_fe_top/Vtb +PROG=$*"
	$(Q)./$(VER_OUT)_fe_top/Vtb $(FE_PLUSARGS) +PROG=$*

# Every label of every compiled assertion file must appear in the
# generated model (the ifu Makefile's method, BP-116).
LABEL_RE := ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:
LABEL_RE := $(LABEL_RE)[[:space:]]*assert[[:space:]]+property

# LABELS NOT IN A 1-SLOT MODEL (BP-128). With SLOT_DEFS set (the
# _1slot twin) these are not looked up and are reported as SKIP: the
# ftq properties that need a second slot or channel and sit in a
# generate if (NUM_PRED_SLOTS > 1) block (the ftq Makefile's
# LABEL_1SLOT_GATED). At two slots the list is empty and every label
# is looked up.
LABEL_1SLOT_GATED := a_ports_agree a_slot_ex_bounded_s1 \
  a_slot_tkn_named_s1 a_named_slot_marked_s1 a_slot_older_first \
  a_place_two_slots a_write_kills_above a_rsv_end_kills_above
LABEL_SKIP := $(if $(strip $(SLOT_DEFS)),$(LABEL_1SLOT_GATED))

assert_labels: sim_fe_top
	@echo "[checking]   assertion labels in the tb_fe_top model"
	$(Q)n=0; m=0; \
	for f in $(ASSERT_SRCS); do \
	  for l in $$(sed -nE 's/$(LABEL_RE).*/\1/p' $$f); do \
	    case " $(LABEL_SKIP) " in *" $$l "*) \
	      echo "SKIP: $$l is not in a 1-slot tb_fe_top model"; \
	      continue;; esac; \
	    n=$$((n+1)); \
	    if ! grep -qF ".$$l\"" $(VER_OUT)_fe_top/*.cpp; then \
	      echo "MISSING: $$l ($$f)"; m=$$((m+1)); \
	    fi; \
	  done; \
	done; \
	echo "assert_labels: PASS=$$((n-m)) FAIL=$$m"; \
	test $$m -eq 0

clean:
	@echo "[cleaning]   fe_top"
	$(Q)rm -rf $(VER_OUT)*

# -- 1-slot targets (BP-128, TD#1) -----------------------------------
# One per target of REGRESS_TARGETS, named <target>_1slot: the same
# recipe at NUM_PRED_SLOTS = 1 (see SLOT1_DEFS at the top of the file).
# sim_fe_top_<p>_1slot is program <p> at one slot.
SLOT1_BASE := lint_fe_top sim_fe_top assert_labels $(FE_PROG_TGTS)
SLOT1_TGTS := $(addsuffix _1slot,$(SLOT1_BASE))

.PHONY: $(SLOT1_TGTS)
$(SLOT1_TGTS): %_1slot:
	$(Q)$(MAKE) $* SLOT_DEFS="$(SLOT1_DEFS)" VER_OUT=$(VER_OUT)_1slot

# -- Regression plumbing (TOOLS-006) ----------------------------------
# tools/regress.sh runs every REGRESS_TARGETS entry with its own make
# call and fails if a target defined in this file is in neither list.
# Exclusions:
#   all                 - aggregate.
#   build_fe_top        - the compile step the sim targets run first.
#   clean, regress_list - housekeeping and this plumbing.
REGRESS_TARGETS := lint_fe_top sim_fe_top assert_labels $(FE_PROG_TGTS) \
                   $(SLOT1_TGTS)
REGRESS_EXCLUDE := all build_fe_top clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
