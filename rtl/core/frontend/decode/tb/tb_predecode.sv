// tb_predecode.sv
// Self-checking testbench for predecode.sv.
// Drives raw fetch bundles and verifies predecode_pkt_t annotations.
// Uses a free-running clock for Verilator 5.020 --timing compatibility.
//
// Test coverage:
//   TC01 - All 8 slots valid, no vector -- all flags clear
//   TC02 - Single vsetvli in slot 0 -- is_vsetvl[0]=1
//   TC03 - Single vadd.vv in slot 0 -- needs_vtype[0]=1, no hazard
//   TC04 - vsetvli slot 0, vadd.vv slot 1 -- vtype_hazard[1]=1
//   TC05 - vsetvli slot 3, vadd.vv slot 4 -- vtype_hazard[4]=1 only
//   TC06 - Two vsetvli slots 0 and 2 -- is_vsetvl[0,2]=1
//   TC07 - vsetvli in slot 7 -- no hazard possible (last slot)
//   TC08 - Mixed scalar/vector -- hazard only on vector consumer
//   TC09 - JAL in slot 2 -- may_be_branch[2]=1 only
//   TC10 - BRANCH in slot 5 -- may_be_branch[5]=1 only
//   TC11 - Vector load vle32.v -- needs_vtype[0]=1, not is_vsetvl
//   TC12 - vsetvli then vse32.v -- vtype_hazard[1]=1
//   TC13 - All slots invalid -- all flags clear

`default_nettype none
`timescale 1ns/1ps

/* verilator lint_off IMPORTSTAR */
import decode_pkg::*;
/* verilator lint_on IMPORTSTAR */

module tb;

// ---------------------------------------------------------------------------
// Clock and reset
// ---------------------------------------------------------------------------
logic clk;
logic rstn;

initial clk = 0;
/* verilator lint_off BLKSEQ */
always #5 clk = ~clk;
/* verilator lint_on BLKSEQ */

// ---------------------------------------------------------------------------
// DUT ports
// ---------------------------------------------------------------------------
logic [SLOTS-1:0][31:0]     fetch_bundle;
logic [SLOTS-1:0]           fetch_valid;
predecode_pkt_t [SLOTS-1:0] predecode_bundle;
ext_enable_t                ext_enable;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
predecode dut (
  .clk              (clk),
  .rstn             (rstn),
  .ext_enable       (ext_enable),
  .fetch_bundle     (fetch_bundle),
  .fetch_valid      (fetch_valid),
  .predecode_bundle (predecode_bundle)
);

// ---------------------------------------------------------------------------
// Test infrastructure
// ---------------------------------------------------------------------------
int pass_count;
int fail_count;

// CHECK_PRE: check a single bit field in predecode_bundle[slot]
`define CHECK_PRE(slot, field, expected, tname) \
  if (predecode_bundle[slot].field !== (expected)) begin \
    $display("FAIL [%s] slot=%0d .%s got=%0b exp=%0b", \
             tname, slot, `"field`", \
             predecode_bundle[slot].field, expected); \
    fail_count++; \
  end else begin \
    pass_count++; \
  end

// CHECK_INSTR: verify instr pass-through
`define CHECK_INSTR(slot, expected, tname) \
  if (predecode_bundle[slot].instr !== (expected)) begin \
    $display("FAIL [%s] slot=%0d .instr got=%0h exp=%0h", \
             tname, slot, \
             predecode_bundle[slot].instr, expected); \
    fail_count++; \
  end else begin \
    pass_count++; \
  end

// ---------------------------------------------------------------------------
// Instruction encodings used in tests
//
// VSETVLI: opcode=0x57 funct3=111 rd=5 rs1=10 zimm=0x008
//   Encoding: {1'b0, 11'h008, rs1, funct3, rd, opcode}
// VADD_VV: opcode=0x57 funct3=000 funct6=000000 vd=1 vs1=2 vs2=3 vm=1
//   Encoding: {6'b000000, 1'b1, vs2, vs1, funct3, vd, opcode}
// VLE32: opcode=0x07 funct3=110 vd=1 rs1=10 vm=1 nf=0 mop=00 lumop=0
//   Encoding: {nf,mew,mop,vm,lumop,rs1,funct3,vd,opcode}
// VSE32: opcode=0x27 funct3=110 vs3=1 rs1=10 vm=1 nf=0 mop=00 lumop=0
//   Encoding: {nf,mew,mop,vm,lumop,rs1,funct3,vs3,opcode}
// NOP:    addi x0,x0,0  = 0x00000013
// ADD:    add  x1,x2,x3 = 0x00310033
// JAL:    jal  x1,0     = 0x000000EF
// JALR:   jalr x0,x0,0  = 0x00000067
// BEQ:    beq  x0,x0,0  = 0x00000063
// ---------------------------------------------------------------------------
localparam logic [31:0] VSETVLI =
    {1'b0, 11'h008, 5'd10, 3'b111, 5'd5,  7'b1010111};
localparam logic [31:0] VADD_VV =
    {6'b000000, 1'b1, 5'd3, 5'd2, 3'b000, 5'd1, 7'b1010111};
localparam logic [31:0] VLE32   =
    {3'b000, 1'b0, 2'b00, 1'b1, 5'd0, 5'd10, 3'b110, 5'd1, 7'b0000111};
localparam logic [31:0] VSE32   =
    {3'b000, 1'b0, 2'b00, 1'b1, 5'd0, 5'd10, 3'b110, 5'd1, 7'b0100111};
localparam logic [31:0] NOP     = 32'h00000013;
localparam logic [31:0] ADD     = 32'h00310033;
localparam logic [31:0] JAL_I   = 32'h000000EF;
localparam logic [31:0] JALR_I  = 32'h00000067;
localparam logic [31:0] BEQ_I   = 32'h00000063;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
// clear_bundle: zero all slots.
// Uses explicit per-slot assignment to avoid variable-index issues
// in Verilator's combinational re-evaluation.
task automatic clear_bundle();
  fetch_valid     = 8'h00;
  fetch_bundle[0] = 32'h0; fetch_bundle[1] = 32'h0;
  fetch_bundle[2] = 32'h0; fetch_bundle[3] = 32'h0;
  fetch_bundle[4] = 32'h0; fetch_bundle[5] = 32'h0;
  fetch_bundle[6] = 32'h0; fetch_bundle[7] = 32'h0;
endtask

// drive: set one slot valid with the given instruction.
// Uses a case statement to avoid variable-indexed array writes that
// prevent Verilator from detecting signal changes for sensitivity.
task automatic drive(
  input int          slot,
  input logic [31:0] instr
);
  case (slot)
    0: begin fetch_bundle[0]=instr; fetch_valid[0]=1'b1; end
    1: begin fetch_bundle[1]=instr; fetch_valid[1]=1'b1; end
    2: begin fetch_bundle[2]=instr; fetch_valid[2]=1'b1; end
    3: begin fetch_bundle[3]=instr; fetch_valid[3]=1'b1; end
    4: begin fetch_bundle[4]=instr; fetch_valid[4]=1'b1; end
    5: begin fetch_bundle[5]=instr; fetch_valid[5]=1'b1; end
    6: begin fetch_bundle[6]=instr; fetch_valid[6]=1'b1; end
    7: begin fetch_bundle[7]=instr; fetch_valid[7]=1'b1; end
    default: ;
  endcase
endtask

// Check all 8 slots: is_vsetvl matches expected bitmask
task automatic check_is_vsetvl(
  input logic [SLOTS-1:0] expected,
  input string            tname
);
  int s;
  for (s = 0; s < SLOTS; s++) begin
    if (predecode_bundle[s].is_vsetvl !== expected[s]) begin
      $display(
        "FAIL [%s] slot=%0d is_vsetvl got=%0b exp=%0b",
        tname, s, predecode_bundle[s].is_vsetvl, expected[s]);
      fail_count++;
    end else begin
      pass_count++;
    end
  end
endtask

task automatic check_needs_vtype(
  input logic [SLOTS-1:0] expected,
  input string            tname
);
  int s;
  for (s = 0; s < SLOTS; s++) begin
    if (predecode_bundle[s].needs_vtype !== expected[s]) begin
      $display(
        "FAIL [%s] slot=%0d needs_vtype got=%0b exp=%0b",
        tname, s, predecode_bundle[s].needs_vtype, expected[s]);
      fail_count++;
    end else begin
      pass_count++;
    end
  end
endtask

task automatic check_vtype_hazard(
  input logic [SLOTS-1:0] expected,
  input string            tname
);
  int s;
  for (s = 0; s < SLOTS; s++) begin
    if (predecode_bundle[s].vtype_hazard !== expected[s]) begin
      $display(
        "FAIL [%s] slot=%0d vtype_hazard got=%0b exp=%0b",
        tname, s, predecode_bundle[s].vtype_hazard, expected[s]);
      fail_count++;
    end else begin
      pass_count++;
    end
  end
endtask

task automatic check_may_be_branch(
  input logic [SLOTS-1:0] expected,
  input string            tname
);
  int s;
  for (s = 0; s < SLOTS; s++) begin
    if (predecode_bundle[s].may_be_branch !== expected[s]) begin
      $display(
        "FAIL [%s] slot=%0d may_be_branch got=%0b exp=%0b",
        tname, s, predecode_bundle[s].may_be_branch, expected[s]);
      fail_count++;
    end else begin
      pass_count++;
    end
  end
endtask

// ---------------------------------------------------------------------------
// Main test sequence
// ---------------------------------------------------------------------------
initial begin
  rstn        = 1'b0;
  pass_count  = 0;
  fail_count  = 0;
  ext_enable  = RVA23_ENABLE; // all extensions enabled by default
  clear_bundle();

  @(posedge clk);
  rstn = 1'b1;
  @(posedge clk);

  // -------------------------------------------------------------------------
  // TC01: All 8 slots valid, no vector instructions -- all flags clear
  // -------------------------------------------------------------------------
  clear_bundle();
  for (int s = 0; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00000000, "TC01");
  check_needs_vtype  (8'b00000000, "TC01");
  check_vtype_hazard (8'b00000000, "TC01");
  check_may_be_branch(8'b00000000, "TC01");
  // verify valid and instr pass-through on slot 0
  `CHECK_PRE  (0, valid, 1'b1,  "TC01")
  `CHECK_INSTR(0, NOP,         "TC01")

  // -------------------------------------------------------------------------
  // TC02: Single vsetvli in slot 0 -- is_vsetvl[0]=1, all others clear
  // -------------------------------------------------------------------------
  clear_bundle();
  drive(0, VSETVLI);
  for (int s = 1; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00000001, "TC02");
  check_needs_vtype  (8'b00000000, "TC02");
  check_vtype_hazard (8'b00000000, "TC02");
  `CHECK_INSTR(0, VSETVLI, "TC02")

  // -------------------------------------------------------------------------
  // TC03: Single vadd.vv in slot 0 -- needs_vtype[0]=1, vtype_hazard[0]=0
  // No prior vsetvl exists, so no hazard.
  // -------------------------------------------------------------------------
  clear_bundle();
  drive(0, VADD_VV);
  for (int s = 1; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00000000, "TC03");
  check_needs_vtype  (8'b00000001, "TC03");
  check_vtype_hazard (8'b00000000, "TC03");

  // -------------------------------------------------------------------------
  // TC04: vsetvli slot 0, vadd.vv slot 1 -- vtype_hazard[1]=1
  // -------------------------------------------------------------------------
  clear_bundle();
  drive(0, VSETVLI);
  drive(1, VADD_VV);
  for (int s = 2; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00000001, "TC04");
  check_needs_vtype  (8'b00000010, "TC04");
  check_vtype_hazard (8'b00000010, "TC04");

  // -------------------------------------------------------------------------
  // TC05: vsetvli slot 3, vadd.vv slot 4
  //   vtype_hazard[4]=1; slots 0-3 no hazard
  // -------------------------------------------------------------------------
  clear_bundle();
  drive(0, NOP); drive(1, NOP); drive(2, NOP);
  drive(3, VSETVLI);
  drive(4, VADD_VV);
  drive(5, NOP); drive(6, NOP); drive(7, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00001000, "TC05");
  check_needs_vtype  (8'b00010000, "TC05");
  // hazard on slot 4 only (bit 4 = 1)
  check_vtype_hazard (8'b00010000, "TC05");

  // -------------------------------------------------------------------------
  // TC06: Two vsetvli in slots 0 and 2 -- is_vsetvl[0,2]=1
  // -------------------------------------------------------------------------
  clear_bundle();
  drive(0, VSETVLI);
  drive(1, NOP);
  drive(2, VSETVLI);
  for (int s = 3; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00000101, "TC06");
  check_needs_vtype  (8'b00000000, "TC06");
  check_vtype_hazard (8'b00000000, "TC06");

  // -------------------------------------------------------------------------
  // TC07: vsetvli in slot 7 (last slot) -- no hazard possible after it
  // -------------------------------------------------------------------------
  clear_bundle();
  for (int s = 0; s < 7; s++) drive(s, NOP);
  drive(7, VSETVLI);
  @(posedge clk);
  check_is_vsetvl    (8'b10000000, "TC07");
  check_needs_vtype  (8'b00000000, "TC07");
  check_vtype_hazard (8'b00000000, "TC07");

  // -------------------------------------------------------------------------
  // TC08: vsetvli slot 0, scalar ADD slot 1, vadd.vv slot 2
  //   hazard on slot 2 (vector consumer); slot 1 scalar -- no hazard
  // -------------------------------------------------------------------------
  clear_bundle();
  drive(0, VSETVLI);
  drive(1, ADD);
  drive(2, VADD_VV);
  for (int s = 3; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00000001, "TC08");
  check_needs_vtype  (8'b00000100, "TC08");
  // slot 1 (scalar): no needs_vtype, so no hazard
  // slot 2 (vadd.vv): needs_vtype AND prior vsetvl exists
  check_vtype_hazard (8'b00000100, "TC08");

  // -------------------------------------------------------------------------
  // TC09: JAL in slot 2 -- may_be_branch[2]=1 only
  // -------------------------------------------------------------------------
  clear_bundle();
  drive(0, NOP); drive(1, NOP);
  drive(2, JAL_I);
  for (int s = 3; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_may_be_branch(8'b00000100, "TC09");
  check_is_vsetvl    (8'b00000000, "TC09");
  check_needs_vtype  (8'b00000000, "TC09");

  // -------------------------------------------------------------------------
  // TC10: BRANCH in slot 5 -- may_be_branch[5]=1 only
  // -------------------------------------------------------------------------
  clear_bundle();
  for (int s = 0; s < SLOTS; s++) drive(s, NOP);
  drive(5, BEQ_I);
  @(posedge clk);
  check_may_be_branch(8'b00100000, "TC10");
  check_is_vsetvl    (8'b00000000, "TC10");
  check_needs_vtype  (8'b00000000, "TC10");

  // -------------------------------------------------------------------------
  // TC11: Vector load vle32.v in slot 0 -- needs_vtype[0]=1, is_vsetvl=0
  // -------------------------------------------------------------------------
  clear_bundle();
  drive(0, VLE32);
  for (int s = 1; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00000000, "TC11");
  check_needs_vtype  (8'b00000001, "TC11");
  check_vtype_hazard (8'b00000000, "TC11");
  `CHECK_INSTR(0, VLE32, "TC11")

  // -------------------------------------------------------------------------
  // TC12: vsetvli slot 0, vse32.v slot 1 -- vtype_hazard[1]=1
  // -------------------------------------------------------------------------
  clear_bundle();
  drive(0, VSETVLI);
  drive(1, VSE32);
  for (int s = 2; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00000001, "TC12");
  check_needs_vtype  (8'b00000010, "TC12");
  check_vtype_hazard (8'b00000010, "TC12");

  // -------------------------------------------------------------------------
  // TC13: All slots invalid -- all flags clear
  // -------------------------------------------------------------------------
  clear_bundle();
  // fetch_valid is all 0 after clear_bundle; set some instructions
  // to confirm they don't assert flags when valid=0
  for (int s = 0; s < SLOTS; s++) begin
    fetch_bundle[s] = VSETVLI; // content is vsetvl but invalid
    fetch_valid[s]  = 1'b0;
  end
  @(posedge clk);
  check_is_vsetvl    (8'b00000000, "TC13");
  check_needs_vtype  (8'b00000000, "TC13");
  check_vtype_hazard (8'b00000000, "TC13");
  check_may_be_branch(8'b00000000, "TC13");
  // valid bits must be 0
  for (int s = 0; s < SLOTS; s++) begin
    `CHECK_PRE(s, valid, 1'b0, "TC13")
  end

  // -------------------------------------------------------------------------
  // TC_JALR: JALR in slot 4
  // -------------------------------------------------------------------------
  clear_bundle();
  for (int s = 0; s < SLOTS; s++) drive(s, NOP);
  drive(4, JALR_I);
  @(posedge clk);
  check_may_be_branch(8'b00010000, "TC_JALR");

  // =========================================================================
  // ext_enable tests -- DECODE-011
  // =========================================================================

  // -------------------------------------------------------------------------
  // TC14: en_v=0 -- vsetvli slot 0 -- is_vsetvl[0]=0 (vector disabled)
  // -------------------------------------------------------------------------
  ext_enable         = RVA23_ENABLE;
  ext_enable.en_v    = 1'b0;
  clear_bundle();
  drive(0, VSETVLI);
  for (int s = 1; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00000000, "TC14");
  check_needs_vtype  (8'b00000000, "TC14");
  check_vtype_hazard (8'b00000000, "TC14");
  // may_be_branch not gated on en_v -- vsetvli is not a branch
  check_may_be_branch(8'b00000000, "TC14");

  // -------------------------------------------------------------------------
  // TC15: en_v=0 -- vadd.vv slot 0 -- needs_vtype[0]=0
  // -------------------------------------------------------------------------
  ext_enable         = RVA23_ENABLE;
  ext_enable.en_v    = 1'b0;
  clear_bundle();
  drive(0, VADD_VV);
  for (int s = 1; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00000000, "TC15");
  check_needs_vtype  (8'b00000000, "TC15");
  check_vtype_hazard (8'b00000000, "TC15");

  // -------------------------------------------------------------------------
  // TC16: en_v=0 -- vsetvli slot 0, vadd.vv slot 1
  //   vtype_hazard must be 0 (all vector flags suppressed)
  // -------------------------------------------------------------------------
  ext_enable         = RVA23_ENABLE;
  ext_enable.en_v    = 1'b0;
  clear_bundle();
  drive(0, VSETVLI);
  drive(1, VADD_VV);
  for (int s = 2; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00000000, "TC16");
  check_needs_vtype  (8'b00000000, "TC16");
  check_vtype_hazard (8'b00000000, "TC16");

  // -------------------------------------------------------------------------
  // TC17: en_v=0 -- vle32.v slot 0 -- needs_vtype[0]=0
  // -------------------------------------------------------------------------
  ext_enable         = RVA23_ENABLE;
  ext_enable.en_v    = 1'b0;
  clear_bundle();
  drive(0, VLE32);
  for (int s = 1; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00000000, "TC17");
  check_needs_vtype  (8'b00000000, "TC17");
  check_vtype_hazard (8'b00000000, "TC17");

  // -------------------------------------------------------------------------
  // TC18: en_v=1 regression -- vsetvli slot 0, vadd.vv slot 1
  //   Restores RVA23_ENABLE; existing behavior must be unchanged (TC04)
  // -------------------------------------------------------------------------
  ext_enable = RVA23_ENABLE;
  clear_bundle();
  drive(0, VSETVLI);
  drive(1, VADD_VV);
  for (int s = 2; s < SLOTS; s++) drive(s, NOP);
  @(posedge clk);
  check_is_vsetvl    (8'b00000001, "TC18");
  check_needs_vtype  (8'b00000010, "TC18");
  check_vtype_hazard (8'b00000010, "TC18");

  // -------------------------------------------------------------------------
  // Summary
  // -------------------------------------------------------------------------
  @(posedge clk);
  $display("predecode tb: %0d passed, %0d failed", pass_count, fail_count);
  if (fail_count != 0)
    $display("RESULT: FAIL");
  else
    $display("RESULT: PASS");
  $finish;
end

endmodule

`default_nettype wire
