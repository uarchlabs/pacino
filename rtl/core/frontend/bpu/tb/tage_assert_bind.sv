// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE: tage_assert_bind.sv
// Include in sim Makefile only. Not for synthesis.
// ===================================================================
bind tage tage_assert #(
  .NUM_PRED_SLOTS (NUM_PRED_SLOTS)
) u_tage_assert (
  .clk               (clk),
  .rstn              (rstn),
  .tage_pred_rdy_p2  (tage_pred_rdy_p2),
  .tage_pred_meta_p2 (tage_pred_meta_p2),
  .tage_upd_val_u0   (tage_upd_val_u0),
  .tage_upd_inp_u0   (tage_upd_inp_u0),
  .assert_inhibit    (1'b0)
);
