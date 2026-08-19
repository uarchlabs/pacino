# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

.PHONY: clean sessions

# Update the sessions json file
sessions:
	./tools/gen_sessions.py

clean:
	$(MAKE) -C rtl clean
	
