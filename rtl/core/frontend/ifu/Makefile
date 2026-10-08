# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- instruction fetch unit (BP-116)
#
# TARGETS. A lint for every module, a sim for every testbench, the
# assertion label guard, plus all and clean:
#
#   lint_ifu_rvc_exp     sim_ifu_rvc_exp      the 17-position expander
#   lint_ifu_predecode   sim_ifu_predecode    the predecoder
#   lint_ifu_xlate                            translation pipeline
#   lint_ifu_lbuf                             line buffer, id free list
#   lint_ifu_fetch                            F0 to F2
#   lint_ifu_f3                               F3
#   lint_ifu_wb                               WB
#   lint_ifu             sim_ifu              the unit
#   assert_labels                             BP-116, TD#144
#   oracle_ifu_rvc_exp                        BP-117, the expander oracle
#
# The xlate, lbuf, fetch, f3 and wb modules have no testbench of their
# own: BP-116 B5 names three testbenches, and tb_ifu drives all four
# boundaries with those modules and their bound properties inside.
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
DEC_DIR  := ../decode/rtl
VER_OUT  := obj

VER_FLAGS       := --sv -Wall -Wno-UNUSED -Wno-IMPORTSTAR --timing
SIM_EXTRA_FLAGS := -Wno-DECLFILENAME

# -Wno-SYNCASYNCNET and --assert as in the ftq Makefile: async rstn
# with `disable iff (!rstn)` in the bound properties, and --assert so
# the concurrent SVA is elaborated at all (TD#109).
COMMON := -Wno-SYNCASYNCNET --assert

PKG_SRCS := \
  $(BPU_DIR)/bp_defines_pkg.sv \
  $(BPU_DIR)/bp_structs_pkg.sv

# decode's rvc_expander was the expander testbench's reference. BP-119
# (TD#143) removed it; the LLVM oracle (oracle_ifu_rvc_exp) remains.

EXP_SRCS   := $(PKG_SRCS) $(RTL_DIR)/ifu_rvc_exp.sv
PD_SRCS    := $(PKG_SRCS) $(RTL_DIR)/ifu_predecode.sv
XLATE_SRCS := $(PKG_SRCS) $(RTL_DIR)/ifu_xlate.sv \
              $(TB_DIR)/ifu_xlate_assert.sv
LBUF_SRCS  := $(PKG_SRCS) $(RTL_DIR)/ifu_lbuf.sv
FETCH_SRCS := $(PKG_SRCS) $(RTL_DIR)/ifu_fetch.sv
F3_SRCS    := $(PKG_SRCS) $(RTL_DIR)/ifu_f3.sv \
              $(TB_DIR)/ifu_f3_assert.sv
WB_SRCS    := $(PKG_SRCS) $(RTL_DIR)/ifu_wb.sv

# The unit: packages, every leaf and assertion file, then the top.
IFU_SRCS := \
  $(PKG_SRCS) \
  $(RTL_DIR)/ifu_xlate.sv      $(TB_DIR)/ifu_xlate_assert.sv \
  $(RTL_DIR)/ifu_lbuf.sv \
  $(RTL_DIR)/ifu_fetch.sv \
  $(RTL_DIR)/ifu_rvc_exp.sv \
  $(RTL_DIR)/ifu_predecode.sv \
  $(RTL_DIR)/ifu_f3.sv         $(TB_DIR)/ifu_f3_assert.sv \
  $(RTL_DIR)/ifu_wb.sv \
  $(RTL_DIR)/ifu.sv            $(TB_DIR)/ifu_assert.sv

.PHONY: all clean assert_labels oracle_ifu_rvc_exp \
  lint_ifu_rvc_exp lint_ifu_predecode lint_ifu_xlate lint_ifu_lbuf \
  lint_ifu_fetch lint_ifu_f3 lint_ifu_wb lint_ifu \
  sim_ifu_rvc_exp sim_ifu_predecode sim_ifu

all: lint_ifu_rvc_exp lint_ifu_predecode lint_ifu_xlate lint_ifu_lbuf \
     lint_ifu_fetch lint_ifu_f3 lint_ifu_wb lint_ifu \
     sim_ifu_rvc_exp sim_ifu_predecode sim_ifu assert_labels \
     oracle_ifu_rvc_exp

# One lint per module: $(1) module, $(2) sources.
define lint_rule
lint_$(1):
	@echo "[linting]    $(1)"
	$$(Q)$$(VERILATOR) --lint-only $$(VER_FLAGS) $$(COMMON) \
	  --top-module $(1) $(2) $$(VSILENCE)
endef

$(eval $(call lint_rule,ifu_rvc_exp,$(EXP_SRCS)))
$(eval $(call lint_rule,ifu_predecode,$(PD_SRCS)))
$(eval $(call lint_rule,ifu_xlate,$(XLATE_SRCS)))
$(eval $(call lint_rule,ifu_lbuf,$(LBUF_SRCS)))
$(eval $(call lint_rule,ifu_fetch,$(FETCH_SRCS)))
$(eval $(call lint_rule,ifu_f3,$(F3_SRCS)))
$(eval $(call lint_rule,ifu_wb,$(WB_SRCS)))
$(eval $(call lint_rule,ifu,$(IFU_SRCS)))

SIM_SRCS_ifu_rvc_exp   := $(EXP_SRCS)
SIM_SRCS_ifu_predecode := $(PD_SRCS)
SIM_SRCS_ifu           := $(IFU_SRCS)

# One sim per testbench: $(1) the DUT name, tb/tb_$(1).sv.
define sim_rule
sim_$(1):
	@echo "[compiling]  tb_$(1)"
	$$(Q)$$(VERILATOR) --binary $$(VER_FLAGS) $$(SIM_EXTRA_FLAGS) \
	  $$(COMMON) --top-module tb --Mdir $$(VER_OUT)_$(1) \
	  $$(SIM_SRCS_$(1)) $$(TB_DIR)/tb_$(1).sv $$(VSILENCE)
	@echo "[simulating] $$(VER_OUT)_$(1)/Vtb"
	$$(Q)./$$(VER_OUT)_$(1)/Vtb
endef

$(eval $(call sim_rule,ifu_rvc_exp))
$(eval $(call sim_rule,ifu_predecode))
$(eval $(call sim_rule,ifu))

# -- The independent expander oracle (BP-117 Problem 4).
#    tb_ifu_rvc_exp reads tb/ifu_rvc_exp_oracle.hex, LLVM's expansion
#    of every 16-bit encoding (see tb/gen_ifu_rvc_exp_oracle.py). This
#    target REGENERATES it from the toolchain and fails if the result
#    differs from the checked-in file, so the vectors stay what the
#    toolchain says and are not a one-off. The regenerated copy goes in
#    the expander's sim directory, $(VER_OUT)_ifu_rvc_exp. RVC_ORACLE_TC is the
#    toolchain bin directory; the generator fails if it is absent.
RVC_ORACLE_TC ?= /usr/local/riscv-embecosm-embedded-ubuntu2204-20250309/bin
ORACLE_HEX    := $(TB_DIR)/ifu_rvc_exp_oracle.hex

oracle_ifu_rvc_exp:
	@echo "[generating] ifu_rvc_exp oracle"
	$(Q)mkdir -p $(VER_OUT)_ifu_rvc_exp
	$(Q)python3 -I $(TB_DIR)/gen_ifu_rvc_exp_oracle.py $(RVC_ORACLE_TC) \
	  $(VER_OUT)_ifu_rvc_exp/oracle_regen.hex
	$(Q)cmp $(ORACLE_HEX) $(VER_OUT)_ifu_rvc_exp/oracle_regen.hex
	@echo "oracle_ifu_rvc_exp: PASS, $(ORACLE_HEX) matches the toolchain"

# -- Every declared property is in every sim model (BP-116, TD#144).
#    The ftq Makefile's method, unchanged: verilate each sim model to
#    C++ into obj_labels_*, and look up ".<label>" in it for every
#    label of every assertion file the model compiles. Fails on an
#    absent label, an unlabeled assert property, or a tb/*_assert.sv
#    no model compiles.
LABEL_MODELS := ifu_rvc_exp ifu_predecode ifu

LABEL_ASSERT_FILES := $(sort $(wildcard $(TB_DIR)/*_assert.sv))
LABEL_UNCOMPILED   := $(filter-out \
  $(foreach m,$(LABEL_MODELS),$(SIM_SRCS_$(m))),$(LABEL_ASSERT_FILES))

LABEL_RE := ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:
LABEL_RE := $(LABEL_RE)[[:space:]]*assert[[:space:]]+property

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
	$(foreach m,$(LABEL_MODELS),$(call label_sh,$(m),$(SIM_SRCS_$(m)))) \
	echo "assert_labels: PASS=$$((tot-mis)) FAIL=$$mis"; \
	test $$mis -eq 0

clean:
	@echo "[cleaning]   ifu"
	$(Q)rm -rf $(VER_OUT)*

# -- Regression plumbing (TOOLS-006) ----------------------------------
# tools/regress.sh runs every REGRESS_TARGETS entry with its own make
# call and fails if a target defined in this file is in neither list.
# Exclusions:
#   all                 - aggregate.
#   clean, regress_list - housekeeping and this plumbing.
REGRESS_TARGETS := \
  lint_ifu_rvc_exp lint_ifu_predecode lint_ifu_xlate lint_ifu_lbuf \
  lint_ifu_fetch lint_ifu_f3 lint_ifu_wb lint_ifu \
  sim_ifu_rvc_exp sim_ifu_predecode sim_ifu assert_labels \
  oracle_ifu_rvc_exp
REGRESS_EXCLUDE := all clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
