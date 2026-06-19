// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

// sat_alu.sv
// Saturating unsigned ALU: add or subtract with clamping.
//
// Parameters:
//   WIDTH - operand and result width in bits. 2 <= WIDTH <= 32.
//           WIDTH=1 is out of scope; behavior is undefined.
//
// Ports:
//   a      - operand A
//   b      - operand B
//   sub    - operation select: 0=add, 1=subtract
//   result - saturated result
//   sat    - 1 when saturation was applied
//
// Fully combinational. No clock or reset.
//
// Add:  true result computed in WIDTH+1 bits.
//       Saturates at {WIDTH{1'b1}} on overflow.
// Sub:  true result computed in WIDTH+1 bits (signed extension).
//       Saturates at {WIDTH{1'b0}} on underflow (borrow).
//
// sat is asserted whenever the true arithmetic result falls
// outside the range [0, 2^WIDTH - 1].

`default_nettype none

module sat_alu #(
  parameter int WIDTH = 4
) (
  input  logic [WIDTH-1:0] a,
  input  logic [WIDTH-1:0] b,
  input  logic             sub,
  output logic [WIDTH-1:0] result,
  output logic             sat
);

  // WIDTH+1 internal result detects overflow/underflow.
  // For subtraction, treat as unsigned with borrow in MSB.
  logic [WIDTH:0] full;

  always_comb begin
    if (sub) begin
      // Subtract: zero-extend a and b to WIDTH+1, subtract.
      // Borrow is indicated by the MSB (sign) of full being 1.
      full   = {1'b0, a} - {1'b0, b};
      if (full[WIDTH]) begin
        // Underflow (borrow): clamp to zero
        result = {WIDTH{1'b0}};
        sat    = 1'b1;
      end else begin
        result = full[WIDTH-1:0];
        sat    = 1'b0;
      end
    end else begin
      // Add: zero-extend both operands, sum in WIDTH+1 bits.
      // Carry-out in MSB indicates overflow.
      full   = {1'b0, a} + {1'b0, b};
      if (full[WIDTH]) begin
        // Overflow: clamp to all-ones
        result = {WIDTH{1'b1}};
        sat    = 1'b1;
      end else begin
        result = full[WIDTH-1:0];
        sat    = 1'b0;
      end
    end
  end

endmodule

`default_nettype wire
