// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    ftb_plru.sv
// DATE:    2026-06-25
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// FTB entry-valid and tree-PLRU state store (BP-065a).
//
// Flop storage parallel to ftb_array. Holds, per set, the FTB_WAYS
// entry-valid bits and the PLRU_BITS tree-PLRU replacement state. It
// is the resettable companion to the pure-RAM ftb_array: reset clears
// the entry-valid bits, which is the FTB cold init -- the FTB has NO
// sram_init mechanism (IC-FTB-12).
//
// This module is STORAGE ONLY (IC-FTB-12). It does NOT compute the
// PLRU victim, the next PLRU state, or the way-match. ftb_cntrl reads
// the valid vector and the PLRU state, computes victim / next-state /
// way-match, and drives the write ports here (BP-066).
//
// Enables are ACTIVE LOW, matching the BPU array convention used by
// tage_table.sv (wen_n) -- the "_n" token. rd_en_n / val_we_n /
// plru_we_n. Reset is rstn (active low).
//
// Separate valid and PLRU write ports: an allocate both sets a way's
// valid and marks it used, so the two writes target the same set in
// one cycle (ftb_decisions.md 5.3, ftb_interfaces.md 3a).
//
// Read-old-on-collision (IC-FTB-14): the read is COMBINATIONAL over
// the flop storage and the writes are synchronous (NBA), so a
// same-cycle read vs same-set valid/PLRU write returns the OLD
// contents. Together with ftb_array, the prediction read sees a
// coherent pre-update snapshot of data + validity/replacement.
// ===================================================================
`ifndef FTB_PLRU_SV
`define FTB_PLRU_SV

import bp_defines_pkg::*;

module ftb_plru (
  input  logic                      clk,
  input  logic                      rstn,

  // -- read port (prediction; combinational); active-low enable
  input  logic                      rd_en_n,
  input  logic [FTB_IDX_BITS-1:0]   rd_addr,
  output logic [FTB_WAYS-1:0]       rd_valid,
  output logic [PLRU_BITS-1:0]      rd_plru,

  // -- valid write port (synchronous); active-low enable.
  //    val_way one-hot selects the way; val_set sets (1) or clears (0)
  //    that way's entry-valid bit.
  input  logic                      val_we_n,
  input  logic [FTB_IDX_BITS-1:0]   val_addr,
  input  logic [FTB_WAYS-1:0]       val_way,
  input  logic                      val_set,

  // -- PLRU write port (synchronous); active-low enable.
  //    plru_wdata is the next PLRU state computed by ftb_cntrl.
  input  logic                      plru_we_n,
  input  logic [FTB_IDX_BITS-1:0]   plru_addr,
  input  logic [PLRU_BITS-1:0]      plru_wdata
);

  // ----------------------------------------------------------------
  // Storage. Per-set entry-valid vector and tree-PLRU state, in
  // flops. FTB_SETS * (FTB_WAYS valid + PLRU_BITS) total.
  // ----------------------------------------------------------------
  logic [FTB_WAYS-1:0]  valid_mem [FTB_SETS];
  logic [PLRU_BITS-1:0] plru_mem  [FTB_SETS];

  // ----------------------------------------------------------------
  // Combinational reads. Outputs return the addressed set when
  // rd_en_n is asserted (low), else zero. The reads see stored
  // (pre-write) contents, giving read-old-on-collision against a
  // same-cycle synchronous write to the same set.
  // ----------------------------------------------------------------
  assign rd_valid = !rd_en_n ? valid_mem[rd_addr] : '0;
  assign rd_plru  = !rd_en_n ? plru_mem[rd_addr]  : '0;

  // ----------------------------------------------------------------
  // Synchronous valid write. Reset clears all entry-valid bits (FTB
  // cold init). On a write (val_we_n low), set or clear the single
  // way selected by the one-hot val_way to val_set. The way is
  // selected by a loop over FTB_WAYS (no hand-unroll); ftb_cntrl
  // guarantees one-hotness.
  // ----------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rstn) begin
      for (int unsigned s = 0; s < FTB_SETS; s++) begin
        valid_mem[s] <= '0;
      end
    end else if (!val_we_n) begin
      for (int unsigned w = 0; w < FTB_WAYS; w++) begin
        if (val_way[w]) begin
          valid_mem[val_addr][w] <= val_set;
        end
      end
    end
  end

  // ----------------------------------------------------------------
  // Synchronous PLRU write. Reset clears all PLRU state. ftb_cntrl
  // supplies the next-state bits; this module only stores them.
  // ----------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rstn) begin
      for (int unsigned s = 0; s < FTB_SETS; s++) begin
        plru_mem[s] <= '0;
      end
    end else if (!plru_we_n) begin
      plru_mem[plru_addr] <= plru_wdata;
    end
  end

endmodule : ftb_plru

`endif // FTB_PLRU_SV
