# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

.PHONY: clean

all:
	$(MAKE) -C lib all
	$(MAKE) -C core/frontend/decode all
	$(MAKE) -C core/frontend/bpu all

cov:
	$(MAKE) -C core/frontend/bpu cov_bpu

clean:
	$(MAKE) -C lib clean
	$(MAKE) -C ./core/frontend/decode clean
	$(MAKE) -C ./core/frontend/bpu clean
