# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# Makefile -- the front-end top at NUM_PRED_SLOTS = 1 (BP-128, TD#1;
# moved here by INFRA-014)
#
# TARGETS:
#
#   <t>_1slot       target <t> of ../Makefile at NUM_PRED_SLOTS = 1, one
#                   per entry of its REGRESS_TARGETS: lint_fe_top_1slot,
#                   sim_fe_top_1slot, assert_labels_1slot,
#                   sim_fe_top_<p>_1slot (program <p> at one slot) and
#                   sim_fe_top_init_walk_1slot
#
# WHY A MAKEFILE OF ITS OWN. tools/regress.sh runs the targets of one
# Makefile in one job, one after another, and Makefiles in parallel.
# Before INFRA-014 the 1-slot targets were in ../Makefile, so they ran
# after the 2-slot ones in the same job. Here they are a job of their
# own. Each keeps its name.
#
# THE RULES ARE ../Makefile's. Each <t>_1slot runs
# `make -f ../Makefile <t>` in this directory (INFRA-015), with
# SLOT_DEFS = SLOT1_DEFS and VER_OUT = obj_1slot, so it builds and runs
# in slot1/obj_1slot_fe_top and writes nothing outside this directory.
# Until INFRA-015 the make ran in ../ (make -C .., VER_OUT =
# slot1/obj_1slot), because tb_fe_top read the RVC oracle by a path
# relative to the directory it ran in; it now reads it by the absolute
# path ../Makefile defines (FE_RVC_ORACLE), and every other path in
# ../Makefile is absolute or under VER_OUT. As in ../,
# sim_fe_top_1slot compiles and the other targets use its binary while
# it is current. This file is passed as FE_EXTRA_MK, so an edit here
# makes the binary stale.
#
# BP_EXPECT_PRED_SLOTS=1 makes the package stop elaboration unless
# NUM_PRED_SLOTS is 1, so a target fails if BP_NUM_PRED_SLOTS does not
# reach it. To see that, build one with the slot macro removed:
#   make lint_fe_top_1slot SLOT1_DEFS=+define+BP_EXPECT_PRED_SLOTS=1
RVA_ROOT ?= $(abspath ../../../../..)
include $(RVA_ROOT)/rtl/Vars.mk
include $(RVA_ROOT)/rtl/core/frontend/fe_top/fe_top_srcs.mk

ifeq ($(VERBOSE),1)
  Q        :=
else
  Q        := @
  MAKEFLAGS := -s --no-print-directory
endif

.DEFAULT_GOAL := all

FE_MAKEFILE := $(FE_TOP)/Makefile
THIS_MK     := $(abspath $(firstword $(MAKEFILE_LIST)))
VER_OUT     := obj_1slot
SLOT1_DEFS  ?= $(FE_SLOT1_DEFS)
PT_MODE     ?=

# THE BASE TARGETS are ../Makefile's REGRESS_TARGETS, read from its
# regress_list, so a target added there gets its twin here with no edit.
# MAKEFLAGS is cleared for that read, so that the flags of this make
# (-B, or tools/regress.sh's -pRrq) do not reach it. An empty read is an
# error: it would leave this Makefile with no regression target.
SLOT1_BASE := $(shell MAKEFLAGS= $(MAKE) -s --no-print-directory \
  -f $(FE_MAKEFILE) RVA_ROOT=$(RVA_ROOT) regress_list | sed -n 's/^test://p')
ifeq ($(strip $(SLOT1_BASE)),)
  $(error slot1: no targets read from $(FE_MAKEFILE) regress_list)
endif
SLOT1_TGTS := $(addsuffix _1slot,$(SLOT1_BASE))

.PHONY: all clean $(SLOT1_TGTS)

# The 1-slot twin of ../Makefile's all.
all: lint_fe_top_1slot sim_fe_top_1slot assert_labels_1slot

$(SLOT1_TGTS): %_1slot:
	$(Q)$(MAKE) -f $(FE_MAKEFILE) $* RVA_ROOT=$(RVA_ROOT) \
	  SLOT_DEFS="$(SLOT1_DEFS)" VER_OUT=$(VER_OUT) \
	  FE_EXTRA_MK=$(THIS_MK) PT_MODE="$(PT_MODE)"

clean:
	@echo "[cleaning]   fe_top slot1"
	$(Q)rm -rf $(VER_OUT)*

# -- Regression plumbing (TOOLS-006) ----------------------------------
# tools/regress.sh runs every REGRESS_TARGETS entry with its own make
# call and fails if a target defined in this file is in neither list.
# Exclusions:
#   all                 - aggregate.
#   clean, regress_list - housekeeping and this plumbing.
REGRESS_TARGETS := $(SLOT1_TGTS)
REGRESS_EXCLUDE := all clean regress_list
# BP-149: sim_fe_top_1slot runs every program at one slot, so
# tools/regress_weekly.sh runs every translated program at each mode at
# one slot as well (../Makefile's weekly line is sim_fe_top).
REGRESS_WEEKLY  := sim_fe_top_1slot

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
	@echo "weekly: $(REGRESS_WEEKLY)"
