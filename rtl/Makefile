# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

.PHONY: clean

all:
	$(MAKE) -C lib all
	$(MAKE) -C core/frontend/decode all
	$(MAKE) -C core/frontend/bpu all
	$(MAKE) -C core/frontend/ftq all

cov:
	$(MAKE) -C core/frontend/bpu cov_bpu

clean:
	$(MAKE) -C lib clean
	$(MAKE) -C ./core/frontend/decode clean
	$(MAKE) -C ./core/frontend/bpu clean
	$(MAKE) -C ./core/frontend/ftq clean

# -- Regression plumbing (TOOLS-006) ----------------------------------
# tools/regress.sh runs every REGRESS_TARGETS entry with its own make
# call and fails if a target defined in this file is in neither list.
# This file defines no test target of its own:
#   all, cov, clean - recursion into unit Makefiles. regress.sh finds
#                     and runs every unit Makefile directly, so running
#                     these would run unit targets twice.
#   regress_list    - this plumbing.
REGRESS_TARGETS :=
REGRESS_EXCLUDE := all cov clean regress_list

.PHONY: regress_list
regress_list:
	@echo "test: $(REGRESS_TARGETS)"
	@echo "exclude: $(REGRESS_EXCLUDE)"
