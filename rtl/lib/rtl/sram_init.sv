// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>

// sram_init.sv
// Parameterized SRAM initializer. State machine:
// PENDING -> (DELAY) -> INIT -> DONE.
// DELAY state is skipped when START_DELAY == 0.
// cs, wr, and active are asserted during INIT only.
// ready is held high after INIT completes.
// No package dependencies.

`default_nettype none

module sram_init #(
  parameter int              NUM_ENTRIES = 16,
  parameter int              ADDR_BITS   = 4,
  parameter int              DATA_WIDTH  = 8,
  parameter [DATA_WIDTH-1:0] INIT_VAL    = '0,
  parameter [7:0]            START_DELAY = 8'h00
) (
  input  logic                   clk,
  input  logic                   rstn,
  output logic                   cs,
  output logic                   wr,
  output logic [ADDR_BITS-1:0]   waddr,
  output logic [DATA_WIDTH-1:0]  wdata,
  output logic                   active,
  output logic                   ready
);

  // State encoding local to this module.
  typedef enum logic [1:0] {
    PENDING = 2'b00,
    DELAY   = 2'b01,
    INIT    = 2'b10,
    DONE    = 2'b11
  } state_t;

  state_t     state;
  logic [7:0] delay_cnt;

  // Inclusive upper address bound for write walk.
  localparam [ADDR_BITS-1:0] LAST_ADDR = ADDR_BITS'(NUM_ENTRIES - 1);

  // State register, address counter, delay counter, ready.
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      state     <= PENDING;
      delay_cnt <= START_DELAY;
      waddr     <= '0;
      ready     <= 1'b0;
    end else begin
      case (state)
        PENDING: begin
          if (START_DELAY == 8'h00)
            state <= INIT;
          else begin
            state     <= DELAY;
            delay_cnt <= START_DELAY;
          end
        end
        DELAY: begin
          delay_cnt <= delay_cnt - 8'h1;
          if (delay_cnt == 8'h1)
            state <= INIT;
        end
        INIT: begin
          if (waddr == LAST_ADDR) begin
            state <= DONE;
            ready <= 1'b1;
          end else
            waddr <= waddr + 1'b1;
        end
        DONE: begin
          // Hold ready asserted until reset.
        end
      endcase
    end
  end

  // Combinatorial outputs - cs, wr, active in INIT state only.
  assign cs     = (state == INIT);
  assign wr     = (state == INIT);
  assign active = (state == INIT);
  assign wdata  = INIT_VAL;

endmodule

`default_nettype wire
