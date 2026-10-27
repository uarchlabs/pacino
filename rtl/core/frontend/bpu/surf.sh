# ==============================================================
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
# ==============================================================
# Open waves.fst (make sim_tage_manual) in Surfer. SURFER is read from
# rtl/Vars.mk; a SURFER in the environment overrides it, as for make.
SURFER=$(make -s -f "$RVA_ROOT/rtl/Vars.mk" \
           --eval '_print_var: ; @echo $(SURFER)' _print_var) || exit 1
"$SURFER" --state-file waves.surf.ron waves.fst
