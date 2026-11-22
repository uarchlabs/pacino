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
#   sim_fe_top_init_walk
#                   program init_walk WITHOUT the fast-init plusargs
#                   (BP-137): the TAGE, ITTAGE and SC init walks run,
#                   and the first p0 request must follow the last
#                   ready. Not in FE_PROGS, which run with fast init
#   assert_labels   every property label of every assertion file the
#                   sim model compiles is present in it
#
# <t>_1slot, target <t> at NUM_PRED_SLOTS = 1 (BP-128), one per target
# above, is in slot1/Makefile (INFRA-014): its own Makefile, so that
# tools/regress.sh runs the 1-slot half as a job of its own, in parallel
# with this one. It runs this file's rules in its own directory.
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

# THE SOURCE LIST, the RTL directories and the flags this Makefile
# shares with examples/fe_demo (DOC-009): fe_top_srcs.mk. Its paths are
# absolute; the testbench directories below are built on its FE_DIR.
include $(RVA_ROOT)/rtl/core/frontend/fe_top/fe_top_srcs.mk

RTL_DIR  := rtl
# Absolute (INFRA-014), as fe_top_srcs.mk's paths, so the build's
# dependency file (FE_VERD, below) names every file by its full path.
TB_DIR   := $(FE_TOP)/tb
BPU_TB   := $(FE_DIR)/bpu/tb
FTQ_TB   := $(FE_DIR)/ftq/tb
IFU_TB   := $(FE_DIR)/ifu/tb
IBUF_TB  := $(FE_DIR)/ibuf/tb
ITLB_TB  := $(RVA_ROOT)/rtl/mmu/itlb/tb
PTW_TB   := $(RVA_ROOT)/rtl/mmu/ptw/tb
L1I_TB   := $(FE_DIR)/icache/tb
VER_OUT  := obj

# -- Slot count (BP-128, TD#1) -------------------------------------
# NUM_PRED_SLOTS is set in bp_defines_pkg.sv from the macro
# BP_NUM_PRED_SLOTS, 2 when it is not defined. SLOT_DEFS is empty here,
# so every target builds at 2. slot1/Makefile runs each target with
# SLOT_DEFS = FE_SLOT1_DEFS and VER_OUT = obj_1slot, in slot1/, so a
# 1-slot build never shares an object directory with a 2-slot one.
# BP_EXPECT_PRED_SLOTS=1 makes the package stop elaboration unless
# NUM_PRED_SLOTS is 1, so a 1-slot target fails if BP_NUM_PRED_SLOTS
# does not reach it. To see that, build one with the slot macro removed:
#   make -C slot1 lint_fe_top_1slot SLOT1_DEFS=+define+BP_EXPECT_PRED_SLOTS=1
SLOT_DEFS  ?=

VER_FLAGS       := $(FE_VER_FLAGS) $(SLOT_DEFS)

# THE BUILD JOBS (INFRA-015): the C++ of tb_fe_top is compiled with one
# job per hardware thread (--build-jobs 0); without it the compiles run
# one at a time. Here, not in fe_top_srcs.mk: it was measured on
# tb_fe_top only, and the examples/fe_demo build does not need it.
FE_BUILD_JOBS := --build-jobs 0

# THE RVC ORACLE (INFRA-015): program zstar reads the LLVM expansion
# oracle by the absolute path in FE_RVC_ORACLE, so tb_fe_top runs from
# any directory. Before, it read ../ifu/tb/ifu_rvc_exp_oracle.hex, from
# fe_top/ only.
FE_RVC_ORACLE := $(IFU_TB)/ifu_rvc_exp_oracle.hex
FE_TB_DEFS    := +define+FE_RVC_ORACLE=\"$(FE_RVC_ORACLE)\"

SIM_EXTRA_FLAGS := $(FE_SIM_FLAGS) $(FE_BUILD_JOBS) $(FE_TB_DEFS)

# FE_WAIVERS (fe_top_srcs.mk): VARHIDDEN for the loop_pred.sv
# parameters, SYNCASYNCNET for the bound properties and sram_init. Until
# BP-128 VARHIDDEN named the tage, sc and ubtb NUM_PRED_SLOTS
# parameters, which BP-128 removed. --assert so the bound properties
# are elaborated (TD#109).
COMMON := $(FE_WAIVERS) --assert

# The sources are fe_top_srcs.mk's: TOP_SRCS the top and every unit,
# PTW_SRCS the walker beside it.
TOP_SRCS := $(FE_TOP_SRCS)
PTW_SRCS := $(FE_PTW_SRCS)

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
  $(BPU_TB)/bp_cluster_assert.sv \
  $(BPU_TB)/ftb_assert.sv \
  $(IFU_TB)/ifu_xlate_assert.sv \
  $(IFU_TB)/ifu_f3_assert.sv \
  $(IFU_TB)/ifu_assert.sv \
  $(IBUF_TB)/ibuf_assert.sv \
  $(ITLB_TB)/itlb_assert.sv \
  $(L1I_TB)/l1i_assert.sv \
  $(L1I_TB)/l1i_mshr_assert.sv \
  $(PTW_TB)/ptw_assert.sv \
  $(TB_DIR)/fe_top_assert.sv

SIM_SRCS := $(TOP_SRCS) $(PTW_SRCS) $(ASSERT_SRCS)

FE_PLUSARGS := $(FE_FAST_INIT)

# THE KNOB (BP-149, PROJECT_CORE.md TRANSLATION MODES): PT_MODE=sv39,
# sv48 or sv57 reaches tb_fe_top as +PT_MODE, on every sim target;
# empty, the testbench's own default, sv57. tools/regress.sh passes
# none; tools/regress_weekly.sh runs the weekly targets below at each
# mode. A program that names its modes (sv39, sv48, sv57, h57,
# pt_gonly_x4) ignores it.
PT_MODE ?=
PT_ARG  := $(if $(strip $(PT_MODE)),+PT_MODE=$(strip $(PT_MODE)))

# The tb_fe_top programs (BP-121), each run alone by sim_fe_top_<p>.
# BP-123 added fencei to pt_inv: maintenance, uncached fetch and the
# page table walker in RTL. BP-124 added pt_upriv (MMU-8c, ITLB-10b).
# BP-134 added rec_undo (an undo-pop over a recursion pop, TD#78);
# BP-143 removed it: its case is not reached by construction (BP-142),
# so its check could not fail, and tb_bp_cluster CB2-RP4 checks the
# rule. BP-135 added t0_uaon (T0 updated as the use_alt_on_na
# provider, CTR rows 19.1-19.8). BP-148 added sv48, sv57 and h57 (Sv48,
# Sv57 and Sv57 / Sv57x4, the 512 GiB and 256 TiB pages, ITLB-18).
# BP-149 added pt_gonly_x4 (G-stage only under Sv57x4, the x4 root's
# entries at 0x100 and above). BP-150 added sc_nored (an SC reversal at
# p3 that raises no redirect, TD#205). BP-151 added ras_fbstale and
# ras_pdcall as expected fails (FE_XPROGS, TD#207); BP-152 fixed both
# (A1, C1) and moved them here, removing FE_XPROGS, and added rsv_twores
# and rsv_trapcall (TD#211 b and a: the commit walk commits only what
# executed). BP-153 added ras_bkicall and ras_bkret (an indirect call
# and a return the FTB does not hold, applied on the backend redirect's
# restore, TD#207), and ras_offpop (the undo of a block's off-path pop).
# PERF-004 added ftq_full (the FTQ filled with commit held: every
# allocated entry is still translated, fetched and delivered, TD#206).
FE_PROGS := bare sv39 loops coro calls lp hist twocond ftbonly nest \
            recur t0_uaon deep indir region multistart cross rvc \
            misp_call sc_nored jals fencei cboinval uc_nc uc_io pt_faults_s \
            pt_faults_h \
            pt_napot_s pt_napot_h pt_rsv_s pt_rsv_h pt_ad_s pt_ad_h pt_inv \
            zstar pt_gonly pt_vsonly pt_upriv sv48 sv57 h57 pt_gonly_x4 \
            ras_fbstale ras_pdcall rsv_twores rsv_trapcall ras_bkicall \
            ras_bkret ras_offpop ftq_full
FE_PROG_TGTS := $(addprefix sim_fe_top_,$(FE_PROGS))

.PHONY: all clean assert_labels lint_fe_top sim_fe_top build_fe_top \
        fe_top_bin $(FE_PROG_TGTS) sim_fe_top_init_walk

# The targets share one object directory: build_fe_top and fe_top_bin
# must never run together under make -j.
.NOTPARALLEL:

all: lint_fe_top sim_fe_top assert_labels

lint_fe_top:
	@echo "[linting]    fe_top"
	$(Q)$(VERILATOR) --lint-only $(VER_FLAGS) $(COMMON) \
	  --top-module fe_top $(TOP_SRCS) $(VSILENCE)

# DOC-001: tb_fe_top includes its models from tb/models (FDT-4), the
# directory examples/fe_demo shares.
TB_MODELS := $(TB_DIR)/models

# -- The binary (INFRA-014) -----------------------------------------
# ONE BUILD PER SLOT COUNT. tools/regress.sh runs every target with
# make -B, which remakes every prerequisite, so a prerequisite that
# compiles would compile once per target. Two targets get the binary:
#   build_fe_top  always compiles. sim_fe_top runs it, so a regress.sh
#                 run compiles tb_fe_top once at each slot count.
#   fe_top_bin    compiles only when the binary is not current, and
#                 otherwise uses it. The per-program targets,
#                 sim_fe_top_init_walk and assert_labels run it.
# NEVER A STALE BINARY. The test is in fe_top_bin's recipe, not in make's
# prerequisites, so -B does not change it. The binary is current when
# FE_STAMP, written after a build that succeeded, holds the flags of
# this build (FE_BUILD_KEY) and no file is newer than it: no file
# Verilator read for the build (its dependency file FE_VERD, which
# lists every source, `include file and the Verilator binary), and no
# Makefile this make read (MAKEFILE_LIST) or FE_EXTRA_MK (slot1/Makefile
# names itself there). A missing file fails the test too. Run alone in
# a clean object directory or after a source edit, a target compiles
# first; it never runs a binary older than its sources.
FE_OBJ       := $(VER_OUT)_fe_top
FE_BIN       := $(FE_OBJ)/Vtb
FE_VERD      := $(FE_OBJ)/Vtb__ver.d
FE_STAMP     := $(FE_OBJ)/fe_top_bin.stamp
FE_EXTRA_MK  ?=
FE_MK_DEPS    = $(abspath $(MAKEFILE_LIST)) $(FE_EXTRA_MK)
FE_BUILD_KEY := $(strip $(VERILATOR) $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
                  $(COMMON))

# The compile, one shell command: the stamp is removed first and written
# only when Verilator succeeds.
FE_BUILD = rm -f $(FE_STAMP) && \
  $(VERILATOR) --binary $(VER_FLAGS) $(SIM_EXTRA_FLAGS) \
  $(COMMON) --top-module tb --Mdir $(FE_OBJ) \
  +incdir+$(TB_MODELS) \
  $(SIM_SRCS) $(TB_PKG_SRCS) $(TB_DIR)/tb_fe_top.sv \
  $(VSILENCE) && echo '$(FE_BUILD_KEY)' > $(FE_STAMP)

# The currency test, a shell condition. fe_new lists the newer files.
FE_FRESH = test -x $(FE_BIN) && test -f $(FE_VERD) && test -f $(FE_STAMP) \
  && test "$$(cat $(FE_STAMP))" = '$(FE_BUILD_KEY)' \
  && fe_new=$$(find $$(sed -e 's/^.* : //' $(FE_VERD)) $(FE_MK_DEPS) \
       -newer $(FE_STAMP) -print) && test -z "$$fe_new"

build_fe_top:
	@echo "[compiling]  tb_fe_top"
	$(Q)$(FE_BUILD)

fe_top_bin:
	$(Q)fe_new=; if $(FE_FRESH); then \
	  echo "[reusing]    $(FE_BIN), current: no build"; \
	else \
	  echo "[compiling]  tb_fe_top: $(FE_BIN) missing, stale or built" \
	    "with other flags"; \
	  test -z "$$fe_new" || echo "  newer than the binary: $$fe_new"; \
	  $(FE_BUILD); \
	fi

# Every program in its own simulation (BP-121): in one simulation the
# predictor tables carry from one program into the next, so a program's
# counts would depend on the programs before it. The totals line sums
# the per-program check counts.
sim_fe_top: build_fe_top
	@echo "[simulating] $(FE_BIN) $(PT_ARG), each of $(FE_PROGS)"
	$(Q)tp=0; tf=0; bad=0; \
	for g in $(FE_PROGS); do \
	  log=$(FE_OBJ)/sim_$$g.log; \
	  ./$(FE_BIN) $(FE_PLUSARGS) $(PT_ARG) +PROG=$$g \
	    > $$log 2>&1 || bad=1; \
	  cat $$log; \
	  m=$$(grep -oE 'PASS=[0-9]+ FAIL=[0-9]+' $$log | tail -1); \
	  if [ -z "$$m" ]; then bad=1; continue; fi; \
	  p=$${m#PASS=}; p=$${p%% *}; f=$${m##*FAIL=}; \
	  tp=$$((tp + p)); tf=$$((tf + f)); \
	done; \
	echo "sim_fe_top: $(words $(FE_PROGS)) programs, one simulation each"; \
	echo "tb_fe_top: PASS=$$tp FAIL=$$tf"; \
	test $$bad -eq 0 && test $$tf -eq 0

# Each program alone, on sim_fe_top's binary when it is current
# (fe_top_bin, INFRA-014).
$(FE_PROG_TGTS): sim_fe_top_%: fe_top_bin
	@echo "[simulating] $(FE_BIN) $(PT_ARG) +PROG=$*"
	$(Q)./$(FE_BIN) $(FE_PLUSARGS) $(PT_ARG) +PROG=$*

# BP-137: the one program run without FE_PLUSARGS, so the predictor
# tables are initialised by their sram_init walks.
sim_fe_top_init_walk: fe_top_bin
	@echo "[simulating] $(FE_BIN) +PROG=init_walk, no fast init"
	$(Q)./$(FE_BIN) $(PT_ARG) +PROG=init_walk

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

# The model only, not the programs (INFRA-014): fe_top_bin, not
# sim_fe_top, so the labels are looked up in a current model and no
# program runs.
assert_labels: fe_top_bin
	@echo "[checking]   assertion labels in the tb_fe_top model"
	$(Q)n=0; m=0; \
	for f in $(ASSERT_SRCS); do \
	  for l in $$(sed -nE 's/$(LABEL_RE).*/\1/p' $$f); do \
	    case " $(LABEL_SKIP) " in *" $$l "*) \
	      echo "SKIP: $$l is not in a 1-slot tb_fe_top model"; \
	      continue;; esac; \
	    n=$$((n+1)); \
	    if ! grep -qF ".$$l\"" $(FE_OBJ)/*.cpp; then \
	      echo "MISSING: $$l ($$f)"; m=$$((m+1)); \
	    fi; \
	  done; \
	done; \
	echo "assert_labels: PASS=$$((n-m)) FAIL=$$m"; \
	test $$m -eq 0

clean:
	@echo "[cleaning]   fe_top"
	$(Q)rm -rf $(VER_OUT)*

# -- Regression plumbing (TOOLS-006) ----------------------------------
# tools/regress.sh runs every REGRESS_TARGETS entry with its own make
# call and fails if a target defined in this file is in neither list.
# slot1/Makefile reads the test: line below and runs each entry at one
# slot as <target>_1slot (INFRA-014).
# Exclusions:
#   all                 - aggregate.
#   build_fe_top, fe_top_bin
#                       - the compile steps the sim targets run first.
#   clean, regress_list - housekeeping and this plumbing.
REGRESS_TARGETS := lint_fe_top sim_fe_top assert_labels $(FE_PROG_TGTS) \
                   sim_fe_top_init_walk
REGRESS_EXCLUDE := all build_fe_top fe_top_bin clean regress_list
# BP-149: the targets tools/regress_weekly.sh runs at every PT_MODE.
# sim_fe_top runs every program, each in its own simulation, so every
# translated program runs at each mode; the per-program targets run the
# same programs one by one. Its 1-slot twin is slot1/Makefile's weekly
# target (INFRA-014). tools/regress.sh reads only the test: and exclude:
# lines.
REGRESS_WEEKLY  := sim_fe_top

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
	@echo "weekly: $(REGRESS_WEEKLY)"
