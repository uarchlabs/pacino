// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    sc_table.sv
// DATE:    2026-07-01
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Parameterized Statistical Corrector (SC) counter table for ST0-ST3.
// Wraps one bw_ram instance per prediction slot, g_slot[s].u_ram for
// slot s (NUM_PRED_SLOTS, 1 or 2). Selection is structural.
// Instantiate once per SC table (ST0-ST3) with per-table params. ST4
// (BrIMLI) is a separate module, sc_brimli.
//
// Entry layout:
//   The SC entry is a single signed confidence counter of width
//   THIS_CTR_WIDTH. There is no tag, no USE, no EPC, no valid bit,
//   and no allocation. ALLOC_DATA_WIDTH == the counter width.
//
// Prediction pipeline: index applied at p2, counter out at p3
//   (bw_ram one-cycle read latency). Prediction is a RAM read only.
// Update: single counter write at upd_index_u0, gated by
//   sc_upd_val_u0 & ctr_wr_u0. Update is a RAM write only.
// Prediction and update phases are mutually exclusive by design;
//   no read-modify-write, no read-during-write forwarding.
// tbl_ri_active + tbl_ri_wr: RAM-init path overrides all writes.
//
// Index hash: sc_idx_hash (planning/arch/sc_table_hash_rules.md).
//   hashed_index = THIS_INDEX_BITS'(inp_pc_p2[s] ^ fh_idx_ext)
//   inp_pc_p2 is the block start PC[VA_WIDTH-1:1], so the PC term of a
//   9-bit index is PC[9:1]; only the instruction offset PC[0] is
//   dropped (PD-17, BP-127). The SC does not use PC_HASH_SHIFT.
//   fh_idx_ext is idx_fh_p2 for ST1-ST3; ST0 ties idx_fh_p2 to zero
//   at the instance. No re-hash on the update path.
//
// ===================================================================

`ifndef SC_TABLE_SV
`define SC_TABLE_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module sc_table #(
  parameter  int THIS_TABLE      = 0,
  parameter  int THIS_INDEX_BITS = SC_TBL_IDX[0],
  parameter  int THIS_CTR_WIDTH  = SC_TBL_CTR[0],
  parameter  int THIS_ENTRIES    = SC_TBL_ENTRIES[0],
  parameter  int THIS_FH         = SC_TBL_FH[0],
  // Derived - do not override
  // The SC entry holds the counter only; no tag/USE/EPC/valid.
  // CNTRL_BITS_WIDTH and ALLOC_DATA_WIDTH both equal the counter
  // width at the declared geometry (SC_MAX_*_WIDTH are 0 except CTR).
  localparam int CNTRL_BITS_WIDTH = SC_MAX_VAL_WIDTH
                                  + SC_MAX_CTR_WIDTH
                                  + SC_MAX_USE_WIDTH
                                  + SC_MAX_EPC_WIDTH,
  localparam int ALLOC_DATA_WIDTH = CNTRL_BITS_WIDTH
                                  + SC_MAX_TAG_WIDTH
) (
  // -- prediction outputs
  output logic [THIS_CTR_WIDTH-1:0]   ctr_p3[0:NUM_PRED_SLOTS-1],
  output logic [THIS_INDEX_BITS-1:0]  idx_hash_p2[0:NUM_PRED_SLOTS-1],
  // -- prediction inputs
  input  logic [NUM_PRED_SLOTS-1:0]   sc_pred_val_p2,
  input  logic [VA_WIDTH-1:1]         inp_pc_p2[0:NUM_PRED_SLOTS-1],
  input  logic [SC_MAX_FH-1:0]        idx_fh_p2,
  // -- update inputs
  input  logic [NUM_PRED_SLOTS-1:0]   sc_upd_val_u0,
  input  logic [THIS_CTR_WIDTH-1:0]   ctr_wd_u0[0:NUM_PRED_SLOTS-1],
  input  logic [NUM_PRED_SLOTS-1:0]   ctr_wr_u0,
  input  logic [THIS_INDEX_BITS-1:0]  upd_index_u0[0:NUM_PRED_SLOTS-1],
  // -- RAM initialization (sram_init override path)
  input  logic                        tbl_ri_active,
  input  logic                        tbl_ri_wr,
  input  logic [THIS_INDEX_BITS-1:0]  tbl_ri_wa,
  input  logic [ALLOC_DATA_WIDTH-1:0] tbl_ri_wd,
  // -- clock and reset
  input  logic                        rstn,
  input  logic                        clk
);

  // Two banks per RAM; index MSB selects bank, lower bits the row.
  localparam int NUM_BANKS   = 2;
  localparam int RAM_ENTRIES = THIS_ENTRIES / NUM_BANKS;

  // sc_pred_val_p2 is defined by the interface to enable the read.
  // bw_ram has no read enable; reads are harmless every cycle and the
  // prediction result is consumed downstream only when valid. The
  // port is retained for interface completeness.

  // ============================================================
  // Index hash (combinational, p2). sc_idx_hash for ST0-ST3.
  //   fh_idx_ext selected by THIS_TABLE:
  //     ST0 -> 0 (SC_TBL_FH[0]=0, unhashed PC slice)
  //     ST1-ST3 -> idx_fh_p2 (per-table fold selected in sc.sv)
  //   hashed_index = THIS_INDEX_BITS'(inp_pc_p2[s] ^ fh_ext)
  // inp_pc_p2 starts at PC[1]; it is not shifted (PD-17). Both slots
  // carry the same block start PC; their RAMs separate them.
  // ============================================================
  logic [SC_MAX_FH-1:0]       fh_idx_ext;
  logic [THIS_INDEX_BITS-1:0] idx_hash[0:NUM_PRED_SLOTS-1];

  always_comb begin : idx_hash_comb
    // Per-table fold selection. sc_table is instantiated only for
    // THIS_TABLE 0-3; ST4 uses sc_brimli and get_br_imli_idx.
    case (THIS_TABLE)
      0: fh_idx_ext = '0;
      1: fh_idx_ext = idx_fh_p2;
      2: fh_idx_ext = idx_fh_p2;
      3: fh_idx_ext = idx_fh_p2;
      default: begin
        fh_idx_ext = '0;
        // Defensive: unreachable by construction for a valid
        // instantiation. sc_table covers THIS_TABLE 0-3 only.
        assert (THIS_TABLE <= 3)
          else $error("sc_table: THIS_TABLE %0d out of range 0-3",
                      THIS_TABLE);
      end
    endcase
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      // Widen the PC to the fold width before the XOR so both
      // operands share the SC_MAX_FH context. Result truncated to
      // THIS_INDEX_BITS by the cast.
      idx_hash[s] = THIS_INDEX_BITS'(
        SC_MAX_FH'(inp_pc_p2[s]) ^ fh_idx_ext);
    end
  end

  // Shared RAM-init write enable. Every slot sees the same tbl_ri
  // signals. When active it overrides all normal write controls.
  logic ri_we;
  assign ri_we = tbl_ri_active & tbl_ri_wr;

  // ============================================================
  // One RAM per slot (BP-128: the slot 0 and slot 1 blocks were two
  // copies; the loop follows NUM_PRED_SLOTS). g_slot[s].u_ram is slot
  // s; before BP-128 it was u_ram_s0 / u_ram_s1.
  // ============================================================
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_slot
    logic [THIS_INDEX_BITS-1:0]  ram_addr;
    logic [ALLOC_DATA_WIDTH-1:0] ram_din;
    logic [ALLOC_DATA_WIDTH-1:0] ram_bweb_n;
    logic                        ram_wen_n;
    logic [ALLOC_DATA_WIDTH-1:0] ram_dout;
    logic                        ctr_we;

    // Fast init: write the bw_ram mem array at time zero via
    // hierarchical reference. Active only when +SC_FAST_INIT=1. bw_ram
    // mem is 2D: mem[BANKS][ENTRIES]. Loop covers both banks.
    initial begin
      int fast_init;
      fast_init = 0;
      void'($value$plusargs("SC_FAST_INIT=%d", fast_init));
      if (fast_init != 0) begin
        for (int b = 0; b < NUM_BANKS; b++) begin
          for (int i = 0; i < RAM_ENTRIES; i++) begin
            u_ram.mem[b][i] = ALLOC_DATA_WIDTH'(SC_SRAM_INIT_VALUE);
          end
        end
      end
    end

    // Expose the index output (p2). Consumed by sc_cntrl to populate
    // sc_upd_idx in the prediction meta.
    assign idx_hash_p2[s] = idx_hash[s];

    // Counter write enable: gated by update-valid and the counter
    // strobe. No table-select gate here -- ctr_wr_u0 is gated by
    // THIS_TABLE membership in sc_cntrl.
    assign ctr_we    = sc_upd_val_u0[s] & ctr_wr_u0[s];
    assign ram_wen_n = ~(ctr_we | ri_we);

    always_comb begin : addr_mux
      if (tbl_ri_active)
        ram_addr = tbl_ri_wa;         // init overrides all
      else if (ctr_we)
        ram_addr = upd_index_u0[s];   // update write address
      else
        ram_addr = idx_hash[s];       // prediction read address
    end

    always_comb begin : din_mux
      if (tbl_ri_active)
        ram_din = tbl_ri_wd;
      else
        ram_din = ALLOC_DATA_WIDTH'(ctr_wd_u0[s]);
    end

    // The SC entry is a whole-word counter; every write is full-word.
    // bweb_n all-zero enables all bits. wen_n controls whether the
    // write commits.
    assign ram_bweb_n = {ALLOC_DATA_WIDTH{1'b0}};

    bw_ram #(
      .ENTRIES(RAM_ENTRIES),
      .WIDTH  (ALLOC_DATA_WIDTH),
      .BANKS  (NUM_BANKS)
    ) u_ram (
      .clk      (clk),
      .addr     (ram_addr[THIS_INDEX_BITS-2:0]),
      .bank_addr(ram_addr[THIS_INDEX_BITS-1]),
      .wen_n    (ram_wen_n),
      .bweb_n   (ram_bweb_n),
      .din      (ram_din),
      .dout     (ram_dout)
    );

    // bw_ram read is one-cycle: address at p2, dout at p3.
    assign ctr_p3[s] = ram_dout[THIS_CTR_WIDTH-1:0];
  end

endmodule : sc_table

`endif // SC_TABLE_SV

`default_nettype wire
