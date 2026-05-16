// bw_ram.sv
// Behavioral bit-write-enable RAM with multiple banks.
//
// SRAM SUBSTITUTION BOUNDARY
// -----------------------------------------------------------
// This module is a behavioral model to be replaced by a real
// SRAM macro at synthesis. The substitution boundary is:
//   - memory array declaration (logic [WIDTH-1:0] mem ...)
//   - write always_ff block
//   - read-address always_ff block
//   - dout continuous assign
// Replace those constructs with the macro instantiation.
// The port interface does not change at the boundary.
// -----------------------------------------------------------
//
// Parameters:
//   ENTRIES   - number of rows per bank
//   WIDTH     - data width in bits per row
//   BANKS     - number of independent banks
//
// Derived (do not override):
//   ADDR_BITS = $clog2(ENTRIES)
//   BANK_BITS = $clog2(BANKS)
//
// Write path (1-cycle latency):
//   Present addr, bank_addr, wen_n, bweb_n, din before posedge.
//   Write is sampled and committed directly at the rising edge.
//   wen_n and bweb_n are active-low. bweb_n[i]=0 enables bit i.
//   Only the bank selected by bank_addr is written.
//
// Read path (1-cycle latency):
//   addr and bank_addr are flopped into raddr_q/rbank_q at posedge.
//   dout is driven combinationally from the flopped address.
//   No read enable.
//
// Read-write conflict: undefined. Caller guarantees no conflict.
// Reset: none. Array is 'x at simulation start.

`default_nettype none

module bw_ram #(
  parameter int ENTRIES   = 16,
  parameter int WIDTH     = 8,
  parameter int BANKS     = 2,
  // Derived - do not override
  parameter int ADDR_BITS = $clog2(ENTRIES),
  parameter int BANK_BITS = $clog2(BANKS)
) (
  input  logic                 clk,
  input  logic [ADDR_BITS-1:0] addr,
  input  logic [BANK_BITS-1:0] bank_addr,
  input  logic                 wen_n,
  input  logic [WIDTH-1:0]     bweb_n,
  input  logic [WIDTH-1:0]     din,
  output logic [WIDTH-1:0]     dout
);

  // --- SRAM substitution boundary: begin ---

  // Memory array. No reset. 'x at simulation start.
  logic [WIDTH-1:0] mem [BANKS][ENTRIES];

  // Registered read-path address
  logic [ADDR_BITS-1:0] raddr_q;
  logic [BANK_BITS-1:0] rbank_q;

  // Write path: sample current inputs directly at the clock edge.
  // No pre-flop stage. bweb_n[i]=0 enables write to bit i.
  // Only the bank selected by bank_addr is written.
  always_ff @(posedge clk) begin
    if (!wen_n) begin
      for (int i = 0; i < WIDTH; i++) begin
        if (!bweb_n[i])
          mem[bank_addr][addr][i] <= din[i];
      end
    end
  end

  // Read-address flop: one-cycle read latency.
  always_ff @(posedge clk) begin
    raddr_q <= addr;
    rbank_q <= bank_addr;
  end

  // Combinational output from flopped read address.
  assign dout = mem[rbank_q][raddr_q];

  // --- SRAM substitution boundary: end ---

endmodule

`default_nettype wire
