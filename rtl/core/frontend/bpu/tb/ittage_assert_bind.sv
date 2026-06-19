// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ---------------------------------------------------------------------------
// FILE: ittage_assert_bind.sv
// Include in sim Makefile only. Not for synthesis.
// ===================================================================
bind ittage ittage_assert #(
  .NUM_PRED_SLOTS (NUM_PRED_SLOTS)
) u_tage_assert (
  .clk                (clk),
  .rstn               (rstn),
  .ittage_pred_rdy_p2 (ittage_pred_rdy_p2),
  .ittage_pred_meta_p2(ittage_pred_meta_p2),
  .ittage_upd_val_u0  (ittage_upd_val_u0),
  .ittage_upd_inp_u0  (ittage_upd_inp_u0)
);

