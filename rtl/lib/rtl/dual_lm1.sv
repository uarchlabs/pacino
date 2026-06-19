// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

// dual_lm1.sv
// Dual leftmost-1 finder: reports positions of the two highest-index
// set bits in the input vector.
//
// Parameters:
//   WIDTH    - input vector width. 2 <= WIDTH <= 32.
//
// Derived:
//   OUT_BITS = $clog2(WIDTH+1)
//   Encodes positions 0..WIDTH. 0 means "not found".
//
// Ports:
//   vec  - input bit vector
//   lm1  - 1-based position of the highest-index set bit (MSB = WIDTH)
//   lm2  - 1-based position of the second highest-index set bit
//
// Fully combinational. No clock or reset.
//
// Positions are 1-based:
//   bit WIDTH-1 (MSB) = position WIDTH
//   bit 0       (LSB) = position 1
//
// lm1 is the highest-index set bit.
// lm2 is the next highest-index set bit after lm1.
// If fewer than two bits are set, missing output(s) are 0.
//
// Implementation: single-pass generate carry chain with two state
// bits (f0 = zero found, f1 = exactly one found). lm1 captures on
// f0->f1 transition; lm2 captures on f1->f2 transition. No cross-
// chain signal dependencies; each chain is a strict DAG from
// index WIDTH down to index 0.

`default_nettype none

module dual_lm1 #(
  parameter int WIDTH    = 8,
  // Derived - do not override
  parameter int OUT_BITS = $clog2(WIDTH + 1)
) (
  input  logic [WIDTH-1:0]    vec,
  output logic [OUT_BITS-1:0] lm1,
  output logic [OUT_BITS-1:0] lm2
);

  // Carry chains, indexed WIDTH (seed) down to 0 (result).
  //
  // f0[i]: true  -> zero set bits found in vec[WIDTH-1:i]
  // f1[i]: true  -> exactly one set bit found in vec[WIDTH-1:i]
  // (both false) -> two or more set bits found
  //
  // lm1_w[i]: 1-based position of the 1st set bit found so far.
  //           0 while still in f0 state.
  //
  // lm2_w[i]: 1-based position of the 2nd set bit found so far.
  //           0 while in f0 or f1 state.

  // split_var: ask Verilator to track each element separately so it
  // can prove the DAG ordering (arr[i] <- arr[i+1]) is acyclic.
  logic                f0    [0:WIDTH] /* verilator split_var */;
  logic                f1    [0:WIDTH] /* verilator split_var */;
  logic [OUT_BITS-1:0] lm1_w [0:WIDTH] /* verilator split_var */;
  logic [OUT_BITS-1:0] lm2_w [0:WIDTH] /* verilator split_var */;

  // Seed: nothing examined yet.
  assign f0[WIDTH]    = 1'b1;
  assign f1[WIDTH]    = 1'b0;
  assign lm1_w[WIDTH] = '0;
  assign lm2_w[WIDTH] = '0;

  genvar i;
  generate
    for (i = WIDTH - 1; i >= 0; i--) begin : g_scan

      // State transitions.
      // f0->f0: was f0, current bit clear.
      // f0->f1: was f0, current bit set  -> lm1 transition.
      // f1->f1: was f1, current bit clear.
      // f1->f2: was f1, current bit set  -> lm2 transition.
      assign f0[i] = f0[i+1] & ~vec[i];
      assign f1[i] = (f0[i+1] &  vec[i]) |
                     (f1[i+1] & ~vec[i]);

      // lm1: capture on f0->f1 transition; propagate otherwise.
      assign lm1_w[i] = f0[i+1] ? (vec[i] ? OUT_BITS'(i + 1) : '0)
                                 : lm1_w[i+1];

      // lm2: capture on f1->f2 transition; propagate otherwise.
      assign lm2_w[i] = f1[i+1] ? (vec[i] ? OUT_BITS'(i + 1) : '0)
                                 : lm2_w[i+1];

    end
  endgenerate

  assign lm1 = lm1_w[0];
  assign lm2 = lm2_w[0];

endmodule

`default_nettype wire
