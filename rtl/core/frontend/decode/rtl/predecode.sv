// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// predecode.sv
// 8-slot pre-decode module for RVA23 / RV64GC fetch bundles.
//
// Purely combinational: annotates each fetch slot with vtype
// dependency information (is_vsetvl, needs_vtype, vtype_hazard)
// and a conservative early branch hint (may_be_branch).
// No registered state. clk/rstn are present for pipeline interface
// consistency and are unused in this combinational module.
//
// Sits between the fetch stage and instr_decoder. The annotated
// predecode_pkt_t bundle becomes the input to instr_decoder, which
// extracts instr/valid internally.
//
// vtype_hazard policy:
//   Informational only. Flags any slot where a prior valid slot in
//   the same bundle is a vsetvl AND this slot consumes vtype.
//   Rename resolves the actual dependency. Policy is TBD per CLAUDE.md.
//
// may_be_branch:
//   Conservative hint. Set for JAL (1101111), JALR (1100111), and
//   BRANCH (1100011) opcodes. Full branch decode (target, direction,
//   type) remains in instr_decoder.sv. False positives are expected
//   and acceptable -- see notes at end of file.
//
// All 8 slots are decoded in parallel using generate blocks.
// No sequential inter-slot dependency except the prefix-OR used to
// propagate vtype_hazard forward through the bundle.
// ===================================================================

`default_nettype none

/* verilator lint_off IMPORTSTAR */
/* verilator lint_off UNUSEDPARAM */
import decode_pkg::*;
/* verilator lint_on UNUSEDPARAM */
/* verilator lint_on IMPORTSTAR */

module predecode (
  input  logic                        clk,
  input  logic                        rstn,
  input  ext_enable_t                 ext_enable,
  input  logic  [SLOTS-1:0][31:0]     fetch_bundle,
  input  logic  [SLOTS-1:0]           fetch_valid,
  output predecode_pkt_t [SLOTS-1:0]  predecode_bundle
);

// ---------------------------------------------------------------------------
// Suppress: clk and rstn unused -- purely combinational module
// ext_enable bits other than en_v are not used in predecode; only
// en_v gates vector flag outputs. All other fields pass through to
// instr_decoder downstream.
// ---------------------------------------------------------------------------
/* verilator lint_off UNUSEDSIGNAL */
wire unused_clk_rstn = clk ^ rstn;
wire unused_ext_bits = ^{
  ext_enable.en_m, ext_enable.en_a,
  ext_enable.en_f, ext_enable.en_d,
  ext_enable.en_c, ext_enable.en_zcb,
  ext_enable.en_zba, ext_enable.en_zbb,
  ext_enable.en_zbs, ext_enable.en_zfhmin,
  ext_enable.en_zfa, ext_enable.en_zicsr,
  ext_enable.en_zicbom, ext_enable.en_zicbop,
  ext_enable.en_zicboz, ext_enable.en_zvfhmin,
  ext_enable.en_h
};
/* verilator lint_on UNUSEDSIGNAL */

// ---------------------------------------------------------------------------
// Opcode constants (bits [6:0])
// ---------------------------------------------------------------------------
localparam logic [6:0] OPC_VECTOR   = 7'b1010111; // 0x57 OP_VECTOR
localparam logic [6:0] OPC_LOAD_FP  = 7'b0000111; // 0x07 OP_LOAD_FP
localparam logic [6:0] OPC_STORE_FP = 7'b0100111; // 0x27 OP_STORE_FP
localparam logic [6:0] OPC_JAL      = 7'b1101111; // 0x6f
localparam logic [6:0] OPC_JALR     = 7'b1100111; // 0x67
localparam logic [6:0] OPC_BRANCH   = 7'b1100011; // 0x63

// ---------------------------------------------------------------------------
// Per-slot intermediate signals
//   w_is_vsetvl[i]    -- slot i is a valid vsetvl/vsetvli/vsetivli
//   w_needs_vtype[i]  -- slot i is a valid vtype consumer
//   w_may_be_branch[i]-- slot i has JAL/JALR/BRANCH opcode (conservative)
//   w_prior_vsetvl[i] -- any valid vsetvl exists in slots [i-1:0]
// ---------------------------------------------------------------------------
logic [SLOTS-1:0] w_is_vsetvl;
logic [SLOTS-1:0] w_needs_vtype;
logic [SLOTS-1:0] w_may_be_branch;
// UNOPTFLAT suppressed: prefix-OR chain is acyclic; each bit depends
// only on bits at strictly lower indices. Array analysis is conservative.
/* verilator lint_off UNOPTFLAT */
logic [SLOTS-1:0] w_prior_vsetvl;
/* verilator lint_on UNOPTFLAT */

// ---------------------------------------------------------------------------
// Per-slot decode -- each slot driven by its own continuous assign.
// Explicit unroll across all 8 slots; no for-loop or generate needed.
//
// is_vsetvl: opcode == OPC_VECTOR AND funct3 == 3'b111
// needs_vtype: OP_VECTOR (non-vsetvl), or vector LD/ST (EEW width)
//   EEW width: inst[14:12] in {000,101,110,111}
//   Excludes scalar FP: 001=FLH/FSH  010=FLW/FSW  011=FLD/FSD  100=FLQ
// may_be_branch: JAL/JALR/BRANCH opcode (conservative; false positives OK)
// ---------------------------------------------------------------------------

// Slot 0
assign w_is_vsetvl[0] =
  ext_enable.en_v
  & fetch_valid[0] & (fetch_bundle[0][6:0] == OPC_VECTOR)
                   & (fetch_bundle[0][14:12] == 3'b111);
assign w_needs_vtype[0] = ext_enable.en_v & fetch_valid[0] & (
  ((fetch_bundle[0][6:0] == OPC_VECTOR)
      & (fetch_bundle[0][14:12] != 3'b111)) |
  ((fetch_bundle[0][6:0] == OPC_LOAD_FP)
      & ((fetch_bundle[0][14:12] == 3'b000)
         | (fetch_bundle[0][14:12] == 3'b101)
         | (fetch_bundle[0][14:12] == 3'b110)
         | (fetch_bundle[0][14:12] == 3'b111))) |
  ((fetch_bundle[0][6:0] == OPC_STORE_FP)
      & ((fetch_bundle[0][14:12] == 3'b000)
         | (fetch_bundle[0][14:12] == 3'b101)
         | (fetch_bundle[0][14:12] == 3'b110)
         | (fetch_bundle[0][14:12] == 3'b111))));
assign w_may_be_branch[0] = fetch_valid[0] & (
  (fetch_bundle[0][6:0] == OPC_JAL)
  | (fetch_bundle[0][6:0] == OPC_JALR)
  | (fetch_bundle[0][6:0] == OPC_BRANCH));

// Slot 1
assign w_is_vsetvl[1] =
  ext_enable.en_v
  & fetch_valid[1] & (fetch_bundle[1][6:0] == OPC_VECTOR)
                   & (fetch_bundle[1][14:12] == 3'b111);
assign w_needs_vtype[1] = ext_enable.en_v & fetch_valid[1] & (
  ((fetch_bundle[1][6:0] == OPC_VECTOR)
      & (fetch_bundle[1][14:12] != 3'b111)) |
  ((fetch_bundle[1][6:0] == OPC_LOAD_FP)
      & ((fetch_bundle[1][14:12] == 3'b000)
         | (fetch_bundle[1][14:12] == 3'b101)
         | (fetch_bundle[1][14:12] == 3'b110)
         | (fetch_bundle[1][14:12] == 3'b111))) |
  ((fetch_bundle[1][6:0] == OPC_STORE_FP)
      & ((fetch_bundle[1][14:12] == 3'b000)
         | (fetch_bundle[1][14:12] == 3'b101)
         | (fetch_bundle[1][14:12] == 3'b110)
         | (fetch_bundle[1][14:12] == 3'b111))));
assign w_may_be_branch[1] = fetch_valid[1] & (
  (fetch_bundle[1][6:0] == OPC_JAL)
  | (fetch_bundle[1][6:0] == OPC_JALR)
  | (fetch_bundle[1][6:0] == OPC_BRANCH));

// Slot 2
assign w_is_vsetvl[2] =
  ext_enable.en_v
  & fetch_valid[2] & (fetch_bundle[2][6:0] == OPC_VECTOR)
                   & (fetch_bundle[2][14:12] == 3'b111);
assign w_needs_vtype[2] = ext_enable.en_v & fetch_valid[2] & (
  ((fetch_bundle[2][6:0] == OPC_VECTOR)
      & (fetch_bundle[2][14:12] != 3'b111)) |
  ((fetch_bundle[2][6:0] == OPC_LOAD_FP)
      & ((fetch_bundle[2][14:12] == 3'b000)
         | (fetch_bundle[2][14:12] == 3'b101)
         | (fetch_bundle[2][14:12] == 3'b110)
         | (fetch_bundle[2][14:12] == 3'b111))) |
  ((fetch_bundle[2][6:0] == OPC_STORE_FP)
      & ((fetch_bundle[2][14:12] == 3'b000)
         | (fetch_bundle[2][14:12] == 3'b101)
         | (fetch_bundle[2][14:12] == 3'b110)
         | (fetch_bundle[2][14:12] == 3'b111))));
assign w_may_be_branch[2] = fetch_valid[2] & (
  (fetch_bundle[2][6:0] == OPC_JAL)
  | (fetch_bundle[2][6:0] == OPC_JALR)
  | (fetch_bundle[2][6:0] == OPC_BRANCH));

// Slot 3
assign w_is_vsetvl[3] =
  ext_enable.en_v
  & fetch_valid[3] & (fetch_bundle[3][6:0] == OPC_VECTOR)
                   & (fetch_bundle[3][14:12] == 3'b111);
assign w_needs_vtype[3] = ext_enable.en_v & fetch_valid[3] & (
  ((fetch_bundle[3][6:0] == OPC_VECTOR)
      & (fetch_bundle[3][14:12] != 3'b111)) |
  ((fetch_bundle[3][6:0] == OPC_LOAD_FP)
      & ((fetch_bundle[3][14:12] == 3'b000)
         | (fetch_bundle[3][14:12] == 3'b101)
         | (fetch_bundle[3][14:12] == 3'b110)
         | (fetch_bundle[3][14:12] == 3'b111))) |
  ((fetch_bundle[3][6:0] == OPC_STORE_FP)
      & ((fetch_bundle[3][14:12] == 3'b000)
         | (fetch_bundle[3][14:12] == 3'b101)
         | (fetch_bundle[3][14:12] == 3'b110)
         | (fetch_bundle[3][14:12] == 3'b111))));
assign w_may_be_branch[3] = fetch_valid[3] & (
  (fetch_bundle[3][6:0] == OPC_JAL)
  | (fetch_bundle[3][6:0] == OPC_JALR)
  | (fetch_bundle[3][6:0] == OPC_BRANCH));

// Slot 4
assign w_is_vsetvl[4] =
  ext_enable.en_v
  & fetch_valid[4] & (fetch_bundle[4][6:0] == OPC_VECTOR)
                   & (fetch_bundle[4][14:12] == 3'b111);
assign w_needs_vtype[4] = ext_enable.en_v & fetch_valid[4] & (
  ((fetch_bundle[4][6:0] == OPC_VECTOR)
      & (fetch_bundle[4][14:12] != 3'b111)) |
  ((fetch_bundle[4][6:0] == OPC_LOAD_FP)
      & ((fetch_bundle[4][14:12] == 3'b000)
         | (fetch_bundle[4][14:12] == 3'b101)
         | (fetch_bundle[4][14:12] == 3'b110)
         | (fetch_bundle[4][14:12] == 3'b111))) |
  ((fetch_bundle[4][6:0] == OPC_STORE_FP)
      & ((fetch_bundle[4][14:12] == 3'b000)
         | (fetch_bundle[4][14:12] == 3'b101)
         | (fetch_bundle[4][14:12] == 3'b110)
         | (fetch_bundle[4][14:12] == 3'b111))));
assign w_may_be_branch[4] = fetch_valid[4] & (
  (fetch_bundle[4][6:0] == OPC_JAL)
  | (fetch_bundle[4][6:0] == OPC_JALR)
  | (fetch_bundle[4][6:0] == OPC_BRANCH));

// Slot 5
assign w_is_vsetvl[5] =
  ext_enable.en_v
  & fetch_valid[5] & (fetch_bundle[5][6:0] == OPC_VECTOR)
                   & (fetch_bundle[5][14:12] == 3'b111);
assign w_needs_vtype[5] = ext_enable.en_v & fetch_valid[5] & (
  ((fetch_bundle[5][6:0] == OPC_VECTOR)
      & (fetch_bundle[5][14:12] != 3'b111)) |
  ((fetch_bundle[5][6:0] == OPC_LOAD_FP)
      & ((fetch_bundle[5][14:12] == 3'b000)
         | (fetch_bundle[5][14:12] == 3'b101)
         | (fetch_bundle[5][14:12] == 3'b110)
         | (fetch_bundle[5][14:12] == 3'b111))) |
  ((fetch_bundle[5][6:0] == OPC_STORE_FP)
      & ((fetch_bundle[5][14:12] == 3'b000)
         | (fetch_bundle[5][14:12] == 3'b101)
         | (fetch_bundle[5][14:12] == 3'b110)
         | (fetch_bundle[5][14:12] == 3'b111))));
assign w_may_be_branch[5] = fetch_valid[5] & (
  (fetch_bundle[5][6:0] == OPC_JAL)
  | (fetch_bundle[5][6:0] == OPC_JALR)
  | (fetch_bundle[5][6:0] == OPC_BRANCH));

// Slot 6
assign w_is_vsetvl[6] =
  ext_enable.en_v
  & fetch_valid[6] & (fetch_bundle[6][6:0] == OPC_VECTOR)
                   & (fetch_bundle[6][14:12] == 3'b111);
assign w_needs_vtype[6] = ext_enable.en_v & fetch_valid[6] & (
  ((fetch_bundle[6][6:0] == OPC_VECTOR)
      & (fetch_bundle[6][14:12] != 3'b111)) |
  ((fetch_bundle[6][6:0] == OPC_LOAD_FP)
      & ((fetch_bundle[6][14:12] == 3'b000)
         | (fetch_bundle[6][14:12] == 3'b101)
         | (fetch_bundle[6][14:12] == 3'b110)
         | (fetch_bundle[6][14:12] == 3'b111))) |
  ((fetch_bundle[6][6:0] == OPC_STORE_FP)
      & ((fetch_bundle[6][14:12] == 3'b000)
         | (fetch_bundle[6][14:12] == 3'b101)
         | (fetch_bundle[6][14:12] == 3'b110)
         | (fetch_bundle[6][14:12] == 3'b111))));
assign w_may_be_branch[6] = fetch_valid[6] & (
  (fetch_bundle[6][6:0] == OPC_JAL)
  | (fetch_bundle[6][6:0] == OPC_JALR)
  | (fetch_bundle[6][6:0] == OPC_BRANCH));

// Slot 7
assign w_is_vsetvl[7] =
  ext_enable.en_v
  & fetch_valid[7] & (fetch_bundle[7][6:0] == OPC_VECTOR)
                   & (fetch_bundle[7][14:12] == 3'b111);
assign w_needs_vtype[7] = ext_enable.en_v & fetch_valid[7] & (
  ((fetch_bundle[7][6:0] == OPC_VECTOR)
      & (fetch_bundle[7][14:12] != 3'b111)) |
  ((fetch_bundle[7][6:0] == OPC_LOAD_FP)
      & ((fetch_bundle[7][14:12] == 3'b000)
         | (fetch_bundle[7][14:12] == 3'b101)
         | (fetch_bundle[7][14:12] == 3'b110)
         | (fetch_bundle[7][14:12] == 3'b111))) |
  ((fetch_bundle[7][6:0] == OPC_STORE_FP)
      & ((fetch_bundle[7][14:12] == 3'b000)
         | (fetch_bundle[7][14:12] == 3'b101)
         | (fetch_bundle[7][14:12] == 3'b110)
         | (fetch_bundle[7][14:12] == 3'b111))));
assign w_may_be_branch[7] = fetch_valid[7] & (
  (fetch_bundle[7][6:0] == OPC_JAL)
  | (fetch_bundle[7][6:0] == OPC_JALR)
  | (fetch_bundle[7][6:0] == OPC_BRANCH));

// ---------------------------------------------------------------------------
// Prefix-OR: w_prior_vsetvl[i] -- any valid vsetvl in slots [0..i-1]
// Slot 0 has no predecessors; its prior_vsetvl is hardwired to 0.
// Each subsequent slot accumulates from the slot before it.
// w_is_vsetvl already incorporates fetch_valid, so no separate AND needed.
//
// UNOPTFLAT note: the prefix chain reads and writes w_prior_vsetvl
// at different indices; array-level dependency analysis conservatively
// flags this as circular. The logic is provably acyclic -- each bit i
// depends only on bit i-1 of w_prior_vsetvl and bit i-1 of w_is_vsetvl.
// lint_off suppression is safe here.
// ---------------------------------------------------------------------------
assign w_prior_vsetvl[0] = 1'b0;
assign w_prior_vsetvl[1] = w_is_vsetvl[0];
assign w_prior_vsetvl[2] = w_prior_vsetvl[1] | w_is_vsetvl[1];
assign w_prior_vsetvl[3] = w_prior_vsetvl[2] | w_is_vsetvl[2];
assign w_prior_vsetvl[4] = w_prior_vsetvl[3] | w_is_vsetvl[3];
assign w_prior_vsetvl[5] = w_prior_vsetvl[4] | w_is_vsetvl[4];
assign w_prior_vsetvl[6] = w_prior_vsetvl[5] | w_is_vsetvl[5];
assign w_prior_vsetvl[7] = w_prior_vsetvl[6] | w_is_vsetvl[6];

// ---------------------------------------------------------------------------
// Assemble output predecode_bundle -- all slots in parallel
// Each slot assigned as a complete packed struct value in one assign.
// Packed field order (MSB to LSB): valid, instr, is_vsetvl, needs_vtype,
//   vtype_hazard, may_be_branch.
// ---------------------------------------------------------------------------
assign predecode_bundle[0] = {
  fetch_valid[0], fetch_bundle[0],
  w_is_vsetvl[0], w_needs_vtype[0],
  w_needs_vtype[0] & w_prior_vsetvl[0],
  w_may_be_branch[0]
};
assign predecode_bundle[1] = {
  fetch_valid[1], fetch_bundle[1],
  w_is_vsetvl[1], w_needs_vtype[1],
  w_needs_vtype[1] & w_prior_vsetvl[1],
  w_may_be_branch[1]
};
assign predecode_bundle[2] = {
  fetch_valid[2], fetch_bundle[2],
  w_is_vsetvl[2], w_needs_vtype[2],
  w_needs_vtype[2] & w_prior_vsetvl[2],
  w_may_be_branch[2]
};
assign predecode_bundle[3] = {
  fetch_valid[3], fetch_bundle[3],
  w_is_vsetvl[3], w_needs_vtype[3],
  w_needs_vtype[3] & w_prior_vsetvl[3],
  w_may_be_branch[3]
};
assign predecode_bundle[4] = {
  fetch_valid[4], fetch_bundle[4],
  w_is_vsetvl[4], w_needs_vtype[4],
  w_needs_vtype[4] & w_prior_vsetvl[4],
  w_may_be_branch[4]
};
assign predecode_bundle[5] = {
  fetch_valid[5], fetch_bundle[5],
  w_is_vsetvl[5], w_needs_vtype[5],
  w_needs_vtype[5] & w_prior_vsetvl[5],
  w_may_be_branch[5]
};
assign predecode_bundle[6] = {
  fetch_valid[6], fetch_bundle[6],
  w_is_vsetvl[6], w_needs_vtype[6],
  w_needs_vtype[6] & w_prior_vsetvl[6],
  w_may_be_branch[6]
};
assign predecode_bundle[7] = {
  fetch_valid[7], fetch_bundle[7],
  w_is_vsetvl[7], w_needs_vtype[7],
  w_needs_vtype[7] & w_prior_vsetvl[7],
  w_may_be_branch[7]
};

endmodule

`default_nettype wire

// ---------------------------------------------------------------------------
// Notes on may_be_branch false positives:
//
// This module sets may_be_branch for any instruction whose opcode field
// matches JAL (1101111), JALR (1100111), or BRANCH (1100011). Because
// only the 7-bit opcode is checked, the following cases produce false
// positives that are benign and expected:
//
// - JALR with funct3 != 3'b000: technically illegal per RVA23 but the
//   pre-decode hint is conservative, and decode will mark is_illegal.
//
// - Any custom extension or reserved encoding that happens to reuse
//   these opcode values would also set may_be_branch=1. This is
//   acceptable because downstream decode resolves the true type.
//
// No false negatives for standard JAL/JALR/BRANCH instructions exist
// in this implementation.
// ---------------------------------------------------------------------------
