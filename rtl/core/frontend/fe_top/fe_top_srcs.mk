# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# fe_top_srcs.mk -- THE fe_top SOURCE LIST, and the defines and flags its
# builds share (DOC-009)
#
# Included by rtl/core/frontend/fe_top/Makefile (lint_fe_top, tb_fe_top)
# and examples/fe_demo/Makefile (the demonstration, FDT-4), after each
# has set RVA_ROOT and included rtl/Vars.mk. Before DOC-009 the
# demonstration kept its own copy of the list, kept in step by hand.
# Every path is absolute, from RVA_ROOT, so the list reads the same from
# either directory. A testbench's own files (tb_fe_top, its bound
# properties, tb_fe_demo) stay in its Makefile.
#
# Order matters: the packages first, then the L1I in the order of its
# emitted filelist, then the units, then the top. FE_TOP_SRCS is what
# lint_fe_top elaborates; the walker, outside the top (MMU-1a), is
# FE_PTW_SRCS, instantiated beside it by both testbenches.

FE_DIR   := $(RVA_ROOT)/rtl/core/frontend
FE_TOP   := $(FE_DIR)/fe_top
BPU_DIR  := $(FE_DIR)/bpu/rtl
FTQ_DIR  := $(FE_DIR)/ftq/rtl
IFU_DIR  := $(FE_DIR)/ifu/rtl
IBUF_DIR := $(FE_DIR)/ibuf/rtl
DEC_DIR  := $(FE_DIR)/decode/rtl
L1I_DIR  := $(FE_DIR)/icache/rtl
COMP_DIR := $(RVA_ROOT)/rtl/lib/rtl
ITLB_DIR := $(RVA_ROOT)/rtl/mmu/itlb/rtl
PMP_DIR  := $(RVA_ROOT)/rtl/mmu/pmp/rtl
PTW_DIR  := $(RVA_ROOT)/rtl/mmu/ptw/rtl
CSR_DIR  := $(RVA_ROOT)/rtl/core/csr

# The shared testbench models (fe_demo_tb_decisions.md FDT-4).
FE_TB_MODELS := $(FE_TOP)/tb/models

# csr_pkg (SYS-001): fe_top, the ITLB, its checker and the walker take
# the CSR groups as csr_pkg types; the testbenches drive them from
# csr_tb_pkg (csr_decisions.md CSR-2).
PKG_SRCS := \
  $(BPU_DIR)/bp_defines_pkg.sv \
  $(BPU_DIR)/bp_structs_pkg.sv \
  $(DEC_DIR)/decode_pkg.sv \
  $(CSR_DIR)/rtl/csr_pkg.sv

TB_PKG_SRCS := $(CSR_DIR)/tb/csr_tb_pkg.sv

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

FE_TOP_SRCS := $(PKG_SRCS) $(L1I_SRCS) $(UNIT_SRCS) $(FE_TOP)/rtl/fe_top.sv

# The walker is outside the top (MMU-1a); each testbench instantiates
# it.
FE_PTW_SRCS := $(PTW_DIR)/ptw.sv

# -- Defines and flags ------------------------------------------------
# FE_VER_FLAGS: -Wall less UNUSED and IMPORTSTAR (CLAUDE.md), --timing.
# FE_WAIVERS: VARHIDDEN for the loop_pred.sv module parameters
# LP_TBL_ENTRIES to LP_CONF_LEVEL, which shadow the bp_defines_pkg
# parameters of the same names (as lint_bp_cluster); SYNCASYNCNET for
# sram_init and the async rstn with disable iff in bound properties.
# FE_SIM_FLAGS: DECLFILENAME, module tb in tb_<dut>.sv (CLAUDE.md).
FE_VER_FLAGS := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing
FE_WAIVERS   := -Wno-VARHIDDEN -Wno-SYNCASYNCNET
FE_SIM_FLAGS := -Wno-DECLFILENAME

# NUM_PRED_SLOTS = 1 (BP-128, TD#1). NUM_PRED_SLOTS is set in
# bp_defines_pkg.sv from BP_NUM_PRED_SLOTS, 2 when it is not defined;
# BP_EXPECT_PRED_SLOTS=1 makes the package stop elaboration unless the
# count it builds is 1.
FE_SLOT1_DEFS := +define+BP_NUM_PRED_SLOTS=1 +define+BP_EXPECT_PRED_SLOTS=1

# The fast SRAM init of the TAGE, ITTAGE and SC tables (BP-137): every
# run but the init-walk ones passes it.
FE_FAST_INIT := +TAGE_FAST_INIT=1 +ITTAGE_FAST_INIT=1 +SC_FAST_INIT=1
