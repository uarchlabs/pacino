// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    ftb_array.sv
// DATE:    2026-06-25
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// FTB data storage array (BP-065a).
//
// Single discrete 1R1W DATA array for the Fetch Target Buffer. One
// read port for prediction, one write port for update/allocate, with
// independent read and write addresses usable in the same cycle.
//
// This module is PURE DATA RAM (IC-FTB-12). It holds NO entry-valid
// bit and NO PLRU state -- those live in ftb_plru. It is field-
// agnostic: it does not decode tag/br/jump, does not compute a way
// match, and does not compute the PLRU victim or PLRU next-state. It
// stores and returns raw bits. The one-hot wr_way arrives already
// decoded from ftb_cntrl; the array applies it. Field semantics, way
// match, and PLRU compute live in ftb_cntrl (BP-066).
//
// No reset. A real 1R1W SRAM macro cannot be reset, so the data array
// has clk only. Cold validity is owned entirely by ftb_plru
// (ftb_interfaces.md 3, IC-FTB-13). Do not rely on array power-up
// contents -- ftb_cntrl never reads a way as valid until ftb_plru
// reports it valid.
//
// Enables are ACTIVE LOW, matching the BPU array convention used by
// tage_table.sv (wen_n) -- the "_n" token. rd_en_n / wr_en_n.
//
// Substitution invariant: a 1R1W SRAM or register file may replace
// ftb_array without touching ftb_cntrl. The port list is the storage
// contract (ftb_interfaces.md 3, ftb_decisions.md 2.4).
//
// Read-old-on-collision (F19, IC-FTB-14): a read and a write to the
// same set in the same cycle return the OLD (pre-write) set contents
// on rd_data.
//
// Read timing: the read is COMBINATIONAL over the storage. The read
// returns the currently stored set; the write is synchronous (NBA),
// so a same-cycle write to the read set does not affect rd_data until
// the next clock edge, which gives read-old-on-collision for free. A
// registered (one-cycle) SRAM read is an equally valid substitute --
// the external p0->p2 prediction contract is satisfied by the FTB top
// (BP-067), so the array's internal read latency is unconstrained
// here. Combinational was chosen as the cleaner, smaller substitutable
// primitive that makes the read-old rule explicit.
// ===================================================================
`ifndef FTB_ARRAY_SV
`define FTB_ARRAY_SV

import bp_defines_pkg::*;

module ftb_array (
  input  logic                          clk,

  // -- read port (prediction); active-low enable
  input  logic                          rd_en_n,
  input  logic [FTB_IDX_BITS-1:0]       rd_addr,
  output logic [FTB_RAM_SET_WIDTH-1:0]  rd_data,

  // -- write port (update / allocate); active-low enable.
  //    wr_way is one-hot from ftb_cntrl.
  input  logic                          wr_en_n,
  input  logic [FTB_IDX_BITS-1:0]       wr_addr,
  input  logic [FTB_WAYS-1:0]           wr_way,
  input  logic [FTB_RAM_ENTRY_WIDTH-1:0] wr_data
);

  // ----------------------------------------------------------------
  // Storage. Whole-set data entries. The set holds FTB_WAYS ways
  // packed FTB_RAM_ENTRY_WIDTH bits each (way 0 in the low slice).
  // The array does not interpret the contents and holds no
  // entry-valid bit (that is in ftb_plru).
  // ----------------------------------------------------------------
  logic [FTB_RAM_SET_WIDTH-1:0] mem [FTB_SETS];

  // ----------------------------------------------------------------
  // Combinational read. rd_data returns the addressed set when
  // rd_en_n is asserted (low), else zero. The read sees stored
  // (pre-write) contents, giving read-old-on-collision against a
  // same-cycle synchronous write to the same set.
  // ----------------------------------------------------------------
  assign rd_data = !rd_en_n ? mem[rd_addr] : '0;

  // ----------------------------------------------------------------
  // Synchronous data write. No reset (pure RAM). On a write (wr_en_n
  // low), apply wr_data to the single way selected by the one-hot
  // wr_way. The way is selected by a loop over FTB_WAYS (no
  // hand-unroll); the array does not validate one-hotness -- ftb_cntrl
  // guarantees it.
  // ----------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!wr_en_n) begin
      for (int unsigned w = 0; w < FTB_WAYS; w++) begin
        if (wr_way[w]) begin
          mem[wr_addr][w*FTB_RAM_ENTRY_WIDTH +: FTB_RAM_ENTRY_WIDTH]
            <= wr_data;
        end
      end
    end
  end

endmodule : ftb_array

`endif // FTB_ARRAY_SV
