# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

# BP-132 (TD#129): the top-level test targets are RETIRED in favour of
# tools/regress.sh, which finds every unit Makefile under rtl/ and runs
# every target of each, so it cannot fall behind a new unit or target
# the way the hand-written lists here did (`cov` reached only bpu
# cov_bpu, so cov_bp_cluster was unreachable from here). `all` and
# `cov` now say where to go and exit non-zero, so a script calling them
# does not take them for a pass. `clean` is kept and runs `clean` in
# every unit Makefile under rtl/, found the same way regress.sh finds
# them.

UNIT_DIRS := $(sort $(patsubst %/Makefile,%,\
               $(shell find . -mindepth 2 -name Makefile)))

.PHONY: all cov clean

all cov:
	@echo "rtl/Makefile: '$@' is retired (BP-132, TD#129). Run the"
	@echo "regression from the repo root instead: ./tools/regress.sh"
	@echo "One unit's targets: make -C rtl/<unit path> <target>"
	@exit 1

clean:
	@for d in $(UNIT_DIRS); do \
	  echo "[cleaning]   $$d"; \
	  $(MAKE) --no-print-directory -C $$d clean || exit 1; \
	done

# -- Regression plumbing (TOOLS-006) ----------------------------------
# tools/regress.sh runs every REGRESS_TARGETS entry with its own make
# call and fails if a target defined in this file is in neither list.
# This file defines no test target of its own:
#   all, cov     - retired (BP-132); they print the way to the
#                  regression and exit 1.
#   clean        - recursion into every unit Makefile's clean.
#   regress_list - this plumbing.
REGRESS_TARGETS :=
REGRESS_EXCLUDE := all cov clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
