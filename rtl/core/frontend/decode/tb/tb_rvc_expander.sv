// tb_rvc_expander.sv
// Self-checking testbench for rvc_expander.
// Uses a free-running clock to drive eval cycles in Verilator 5.020
// with --timing. Inputs are driven combinatorially; checks happen at
// the next posedge after inputs are applied, allowing the always_comb
// logic to settle.
//
// Tests all three quadrants of RVC expansion plus 32-bit passthrough.

`default_nettype none
`timescale 1ns/1ps

/* verilator lint_off IMPORTSTAR */
import decode_pkg::*;
/* verilator lint_on IMPORTSTAR */

module tb;

// ---------------------------------------------------------------------------
// Clock - drives Verilator eval() cycles
// ---------------------------------------------------------------------------
logic clk;
initial clk = 0;
/* verilator lint_off BLKSEQ */
always #5 clk = ~clk;
/* verilator lint_on BLKSEQ */

// ---------------------------------------------------------------------------
// DUT ports
// ---------------------------------------------------------------------------
logic [SLOTS-1:0][31:0]      fetch_bundle;
logic [SLOTS*MASK_BITS-1:0]  fetch_mask;
logic [SLOTS-1:0][31:0]      exp_bundle;
logic [SLOTS-1:0]            exp_valid;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
rvc_expander dut (
    .fetch_bundle (fetch_bundle),
    .fetch_mask   (fetch_mask),
    .exp_bundle   (exp_bundle),
    .exp_valid    (exp_valid)
);

// ---------------------------------------------------------------------------
// Test infrastructure
// ---------------------------------------------------------------------------
int pass_count;
int fail_count;

// Reset all inputs
task automatic clear_all();
    int s;
    for (s = 0; s < SLOTS; s++) begin
        fetch_bundle[s] = 32'h0;
    end
    fetch_mask = '0;
endtask

// Set one slot. valid=1; is_rvc selects 16b expansion.
task automatic set_slot(
    input int          slot,
    input logic [31:0] word,
    input logic        is_rvc
);
    fetch_bundle[slot] = word;
    // [2*slot+1]=valid, [2*slot+0]=is_rvc
    fetch_mask[slot*MASK_BITS + 1] = 1'b1;
    fetch_mask[slot*MASK_BITS + 0] = is_rvc;
endtask

// Check one slot. Call AFTER @(posedge clk) to allow comb settle.
task automatic check(
    input int          slot,
    input logic [31:0] expected,
    input logic        exp_v,
    input string       test_name
);
    if (exp_bundle[slot] !== expected || exp_valid[slot] !== exp_v) begin
        $display("FAIL [%s] slot=%0d  got=%08h valid=%b  exp=%08h valid=%b",
                 test_name, slot,
                 exp_bundle[slot], exp_valid[slot],
                 expected, exp_v);
        fail_count++;
    end else begin
        $display("PASS [%s] slot=%0d  result=%08h",
                 test_name, slot, exp_bundle[slot]);
        pass_count++;
    end
endtask

// ---------------------------------------------------------------------------
// Test cases
// ---------------------------------------------------------------------------
initial begin
    pass_count  = 0;
    fail_count  = 0;
    fetch_bundle = '0;
    fetch_mask   = '0;

    // -----------------------------------------------------------------------
    // T1: All slots invalid - valid=0, output=0
    // -----------------------------------------------------------------------
    @(posedge clk);
    for (int s = 0; s < SLOTS; s++) begin
        if (exp_valid[s] !== 1'b0) begin
            $display("FAIL [T1_invalid] slot=%0d valid!=0", s);
            fail_count++;
        end else
            pass_count++;
    end

    // -----------------------------------------------------------------------
    // T2: 32-bit passthrough
    // ADDI x1, x2, 42 = 0x02A10093
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(0, 32'h02A10093, 1'b0);
    @(posedge clk);
    check(0, 32'h02A10093, 1'b1, "T2_passthrough_ADDI");

    // -----------------------------------------------------------------------
    // T3: C.ADDI4SPN -> ADDI rd', x2, nzuimm
    // rd'=x10, nzuimm=4 -> 16'h0048
    // Expected: ADDI x10, x2, 4 = 0x00410513
    // -----------------------------------------------------------------------
    clear_all();
    // Encoding: funct3=000, c[12:11]=00, c[10:7]=0001, c[6]=0, c[5]=0
    //           c[4:2]=010 (rd'=x10), c[1:0]=00
    // bits: 0000_0000_0100_1000 = 0x0048
    set_slot(1, {16'h0, 16'h0048}, 1'b1);
    @(posedge clk);
    check(1, 32'h00410513, 1'b1, "T3_CADDI4SPN_x10_x2_4");

    // -----------------------------------------------------------------------
    // T4: C.LW -> LW rd', rs1', uimm
    // rd'=x10, rs1'=x10, uimm=4
    // uimm={c[5],c[12:10],c[6],00}: uimm[2]=1->c[6]=1, rest 0
    // [15:13]=010, [12:10]=000, [9:7]=010, [6]=1, [5]=0, [4:2]=010, [1:0]=00
    // bit: 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
    // val:  0  1  0  0  0  0  0  1  0  1  0  0  1  0  0  0 = 0x4148
    // Expected: LW x10, 4(x10) = 0x00452503
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(2, {16'h0, 16'h4148}, 1'b1);
    @(posedge clk);
    check(2, 32'h00452503, 1'b1, "T4_CLW_x10_4_x10");

    // -----------------------------------------------------------------------
    // T5: C.LD -> LD rd', rs1', uimm  (RV64)
    // rd'=x10, rs1'=x10, uimm=8
    // uimm={c[6:5],c[12:10],000}: uimm[3]=1->c[10]=1
    // [15:13]=011, [12]=0, [11:10]=01, [9:7]=010, [6:5]=00, [4:2]=010, [1:0]=00
    // bit: 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
    // val:  0  1  1  0  0  1  0  1  0  0  0  0  1  0  0  0 = 0x6508
    // Expected: LD x10, 8(x10) = 0x00853503
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(3, {16'h0, 16'h6508}, 1'b1);
    @(posedge clk);
    check(3, 32'h00853503, 1'b1, "T5_CLD_x10_8_x10");

    // -----------------------------------------------------------------------
    // T6: C.ADDI -> ADDI x1, x1, -1
    // rd=x1, nzimm=-1 -> c[12]=1, c[6:2]=11111
    // [15:13]=000, [12]=1, [11:7]=00001, [6:2]=11111, [1:0]=01
    // = 0001_0011_1110_0001 = 0x13E1 ... let me recompute:
    // bit15=0,14=0,13=0,12=1,11=0,10=0,9=0,8=0,7=1,6=1,5=1,4=1,3=1,2=0,1=0,0=1
    // = 0001_0000_1111_1001 ... hmm
    // Actually: [15:13]=000, [12]=1, [11:7]=00001, [6:2]=11111, [1:0]=01
    // 0 0 0 1  0 0 0 0 1  1 1 1 1 1  0 1
    // = 0001_0000_1111_1101 = 0x10FD? Let me do it carefully:
    // bit: 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
    // val:  0  0  0  1  0  0  0  0  1  1  1  1  1  1  0  1
    //       =  0000 | 1001 | 1111 | 1101 ... no wait grouping:
    //       bits[15:12] = 0001
    //       bits[11:8]  = 0000
    //       bits[7:4]   = 1111
    //       bits[3:0]   = 1101
    //       = 0x10FD
    // Expected: ADDI x1,x1,-1 = {12'hFFF, x1, 3'b000, x1, 7'b0010011}
    //         = 0xFFF08093
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(4, {16'h0, 16'h10FD}, 1'b1);
    @(posedge clk);
    check(4, 32'hFFF08093, 1'b1, "T6_CADDI_x1_x1_m1");

    // -----------------------------------------------------------------------
    // T7: C.LI -> ADDI x5, x0, 10
    // [15:13]=010, [12]=0, [11:7]=00101(x5), [6:2]=01010, [1:0]=01
    // bit: 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
    // val:  0  1  0  0  0  0  1  0  1  0  1  0  1  0  0  1
    // bits[15:12]=0100, bits[11:8]=0010, bits[7:4]=1010, bits[3:0]=1001
    // = 0x42A9
    // Expected: ADDI x5, x0, 10 = {12'h00A, 5'h0, 3'b000, 5'd5, 7'b0010011}
    //         = 0x00A00293
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(5, {16'h0, 16'h42A9}, 1'b1);
    @(posedge clk);
    check(5, 32'h00A00293, 1'b1, "T7_CLI_x5_10");

    // -----------------------------------------------------------------------
    // T8: C.J -> JAL x0, 8
    // offset=8: offset[3]=1
    // j3=c[5]=1, all other j bits 0
    // [15:13]=101, [12]=0, [11]=0, [10:9]=00, [8]=0, [7]=0, [6]=0
    // [5]=1, [4]=0, [3]=0, [2]=0, [1:0]=01
    // bits: 1  0  1  0  0  0  0  0  0  0  1  0  0  0  0  1
    //       = 1010_0000_0010_0001 = 0xA021
    // Expected: JAL x0, 8 = 0x0080006F
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(6, {16'h0, 16'hA021}, 1'b1);
    @(posedge clk);
    check(6, 32'h0080006F, 1'b1, "T8_CJ_offset8");

    // -----------------------------------------------------------------------
    // T9: C.SLLI -> SLLI x1, x1, 3
    // [15:13]=000, [12]=0, [11:7]=00001(x1), [6:2]=00011(shamt=3), [1:0]=10
    // bits: 0  0  0  0  0  0  0  0  1  0  0  0  1  1  1  0
    //       = 0000_0000_1000_1110 = 0x008E
    // Expected: SLLI x1, x1, 3 = 0x00309093
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(7, {16'h0, 16'h008E}, 1'b1);
    @(posedge clk);
    check(7, 32'h00309093, 1'b1, "T9_CSLLI_x1_3");

    // -----------------------------------------------------------------------
    // T10: All 8 slots simultaneously
    // Slot 0: 32b ADDI x1, x2, 42 = 0x02A10093
    // Slot 1: C.LW x10, 4(x10) = 0x4488
    // Slot 2: 32b LUI x5, 0x12345 = 0x123452B7
    // Slots 3-7: invalid
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(0, 32'h02A10093, 1'b0);
    set_slot(1, {16'h0, 16'h4148}, 1'b1);  // C.LW x10,4(x10)
    set_slot(2, 32'h123452B7, 1'b0);
    @(posedge clk);
    check(0, 32'h02A10093, 1'b1, "T10a_32b_passthrough");
    check(1, 32'h00452503, 1'b1, "T10b_CLW");
    check(2, 32'h123452B7, 1'b1, "T10c_LUI_passthrough");
    for (int s = 3; s < SLOTS; s++) begin
        if (exp_valid[s] !== 1'b0) begin
            $display("FAIL [T10_invalid_slot%0d] valid=%b exp=0",
                     s, exp_valid[s]);
            fail_count++;
        end else
            pass_count++;
    end

    // -----------------------------------------------------------------------
    // T11: C.SW -> SW rs2', rs1', uimm
    // rs2'=x10, rs1'=x10, uimm=4
    // uimm={c[5],c[12:10],c[6],00}: uimm[2]=1->c[6]=1, rest 0
    // [15:13]=110, [12:10]=000, [9:7]=010, [6]=1, [5]=0, [4:2]=010, [1:0]=00
    // bit: 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
    // val:  1  1  0  0  0  0  0  1  0  1  0  0  1  0  0  0 = 0xC148
    // Expected: SW x10, 4(x10) = 0x00A52223
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(0, {16'h0, 16'hC148}, 1'b1);
    @(posedge clk);
    check(0, 32'h00A52223, 1'b1, "T11_CSW_x10_4_x10");

    // -----------------------------------------------------------------------
    // T12: C.MV -> ADD rd, x0, rs2
    // rd=x1, rs2=x2: [15:13]=100,[12]=0,[11:7]=00001,[6:2]=00010,[1:0]=10
    // bits: 1  0  0  0  0  0  0  0  1  0  0  0  1  0  1  0
    //       = 1000_0000_1000_1010 = 0x808A
    // Expected: ADD x1, x0, x2 = 0x002000B3
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(0, {16'h0, 16'h808A}, 1'b1);
    @(posedge clk);
    check(0, 32'h002000B3, 1'b1, "T12_CMV_x1_x2");

    // -----------------------------------------------------------------------
    // T13: C.EBREAK = 0x9002
    // Expected: EBREAK = 0x00100073
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(0, {16'h0, 16'h9002}, 1'b1);
    @(posedge clk);
    check(0, 32'h00100073, 1'b1, "T13_CEBREAK");

    // -----------------------------------------------------------------------
    // T14: C.BEQZ -> BEQ rs1', x0, 4
    // rs1'=x8, offset=4: offset[2]=1 -> c[4]=1
    // [15:13]=110,[12]=0,[11:10]=00,[9:7]=000(x8),[6:5]=00,[4:3]=10,[2]=0
    // [1:0]=01
    // bits: 1  1  0  0  0  0  0  0  0  0  0  1  0  0  0  1
    //       = 1100_0000_0001_0001? no:
    // bit15=1,14=1,13=0,12=0,11=0,10=0,9=0,8=0,7=0,6=0,5=0,4=1,3=0,2=0,1=0,0=1
    //       = 1100_0000_0001_0001 ... hmm
    // bits[15:12]=1100, bits[11:8]=0000, bits[7:4]=0001, bits[3:0]=0001
    // = 0xC011
    // Expected: BEQ x8, x0, 4 = 0x00040263
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(0, {16'h0, 16'hC011}, 1'b1);
    @(posedge clk);
    check(0, 32'h00040263, 1'b1, "T14_CBEQZ_x8_4");

    // -----------------------------------------------------------------------
    // T15: C.SRLI -> SRLI x8, x8, 1
    // rs1'=x8 (c[9:7]=000), shamt=1 (c[6:2]=00001)
    // [15:13]=100, [12]=0, [11:10]=00, [9:7]=000, [6:2]=00001, [1:0]=01
    // shamt=1 -> c[6:2]=00001 -> bit2=1 (not bit3)
    // bit: 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
    // val:  1  0  0  0  0  0  0  0  0  0  0  0  0  1  0  1 = 0x8005
    // Expected: SRLI x8, x8, 1 = {6'b000000, 6'd1, x8, 3'b101, x8, OP_IMM}
    //         = 0x00145413
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(0, {16'h0, 16'h8005}, 1'b1);
    @(posedge clk);
    check(0, 32'h00145413, 1'b1, "T15_CSRLI_x8_1");

    // -----------------------------------------------------------------------
    // T16: C.BNEZ -> BNE rs1', x0, 4
    // [15:13]=111, otherwise same as T14
    // bits: 1  1  1  0  0  0  0  0  0  0  0  1  0  0  0  1
    //       = 1110_0000_0001_0001 = 0xE011
    // Expected: BNE x8, x0, 4 = 0x00041263
    // -----------------------------------------------------------------------
    clear_all();
    set_slot(0, {16'h0, 16'hE011}, 1'b1);
    @(posedge clk);
    check(0, 32'h00041263, 1'b1, "T16_CBNEZ_x8_4");

    // -----------------------------------------------------------------------
    // Zcb directed tests
    // All use slot 0. rd'=rs1'=x10 (c[9:7]=010) for loads/stores,
    // rd'=rs1'=x8 (c[9:7]=000) for integer ops.
    // -----------------------------------------------------------------------

    // T17: c.lbu rd'=x10, rs1'=x10, uimm=0
    // 15..13=100, 12..10=000, 9..7=010, 6=0, 5=0, 4..2=010, 1..0=00
    // = 1000_0100_0000_1000 = 0x8408 ... let me recompute:
    // bit15=1,14=0,13=0,12=0,11=0,10=0,9=0,8=1,7=0,6=0,5=0,4=0,3=1,2=0
    // = 1000_0001_0000_1000 = 0x8108
    // Expected: LBU x10,0(x10) = {12'h000,x10,3'b100,x10,7'b0000011}
    //         = 0x00054503
    clear_all();
    set_slot(0, {16'h0, 16'h8108}, 1'b1);
    @(posedge clk);
    check(0, 32'h00054503, 1'b1, "T17_Zcb_CLBU_x10_0_x10");

    // T18: c.lhu rd'=x10, rs1'=x10, uimm=0 (c[6]=0,c[5]=0)
    // 15..13=100, 12..10=001, 9..7=010, 6=0, 5=0, 4..2=010, 1..0=00
    // bit12=0,bit11=0,bit10=1 -> bits 11..8: 0,1,0,1=0x5 (c[10]=1,c[8]=1)
    // = 1000_0101_0000_1000 = 0x8508
    // Expected: LHU x10,0(x10) = {12'h000,x10,3'b101,x10,7'b0000011}
    //         = 0x00055503
    clear_all();
    set_slot(0, {16'h0, 16'h8508}, 1'b1);
    @(posedge clk);
    check(0, 32'h00055503, 1'b1, "T18_Zcb_CLHU_x10_0_x10");

    // T19: c.lh rd'=x10, rs1'=x10, uimm=0 (c[6]=1,c[5]=0)
    // 15..13=100, 12..10=001, 9..7=010, 6=1, 5=0, 4..2=010, 1..0=00
    // = 1000_0101_0100_1000 = 0x8548
    // Expected: LH x10,0(x10) = {12'h000,x10,3'b001,x10,7'b0000011}
    //         = 0x00051503
    clear_all();
    set_slot(0, {16'h0, 16'h8548}, 1'b1);
    @(posedge clk);
    check(0, 32'h00051503, 1'b1, "T19_Zcb_CLH_x10_0_x10");

    // T20: c.sb rs2'=x10, rs1'=x10, uimm=0
    // 15..13=100, 12..10=010, 9..7=010, 6=0, 5=0, 4..2=010, 1..0=00
    // bit12=0,bit11=1,bit10=0 -> bits 11..8: 1,0,0,1=0x9
    // = 1000_1001_0000_1000 = 0x8908
    // Expected: SB x10,0(x10) = {7'b0,x10,x10,3'b000,5'b0,7'b0100011}
    //         = 0x00A50023
    clear_all();
    set_slot(0, {16'h0, 16'h8908}, 1'b1);
    @(posedge clk);
    check(0, 32'h00A50023, 1'b1, "T20_Zcb_CSB_x10_0_x10");

    // T21: c.sh rs2'=x10, rs1'=x10, uimm=0 (c[6]=0,c[5]=0)
    // 15..13=100, 12..10=011, 9..7=010, 6=0, 5=0, 4..2=010, 1..0=00
    // bit12=0,bit11=1,bit10=1 -> bits 11..8: 1,1,0,1=0xD
    // = 1000_1101_0000_1000 = 0x8D08
    // Expected: SH x10,0(x10) = {7'b0,x10,x10,3'b001,5'b0,7'b0100011}
    //         = 0x00A51023
    clear_all();
    set_slot(0, {16'h0, 16'h8D08}, 1'b1);
    @(posedge clk);
    check(0, 32'h00A51023, 1'b1, "T21_Zcb_CSH_x10_0_x10");

    // T22: c.zext.b rd'=x8
    // 15..13=100,12..10=111,9..7=000,6..5=11,4..2=000,1..0=01
    // = 1001_1100_0110_0001 = 0x9C61
    // Expected: ANDI x8,x8,0xFF = {12'h0FF,x8,3'b111,x8,7'b0010011}
    //         = 0x0FF47413
    clear_all();
    set_slot(0, {16'h0, 16'h9C61}, 1'b1);
    @(posedge clk);
    check(0, 32'h0FF47413, 1'b1, "T22_Zcb_CZEXT_B_x8");

    // T23: c.sext.b rd'=x8
    // 15..13=100,12..10=111,9..7=000,6..5=11,4..2=001,1..0=01
    // = 1001_1100_0110_0101 = 0x9C65
    // Expected: SEXT.B x8,x8 (Zbb)
    //   {7'b0110000,5'b00100,x8,3'b001,x8,7'b0010011} = 0x60441413
    clear_all();
    set_slot(0, {16'h0, 16'h9C65}, 1'b1);
    @(posedge clk);
    check(0, 32'h60441413, 1'b1, "T23_Zcb_CSEXT_B_x8");

    // T24: c.zext.h rd'=x8
    // 15..13=100,12..10=111,9..7=000,6..5=11,4..2=010,1..0=01
    // = 1001_1100_0110_1001 = 0x9C69
    // Expected: ZEXT.H x8,x8 (Zbb, RV64)
    //   {7'b0000100,5'b00000,x8,3'b100,x8,7'b0111011} = 0x0804443B
    clear_all();
    set_slot(0, {16'h0, 16'h9C69}, 1'b1);
    @(posedge clk);
    check(0, 32'h0804443B, 1'b1, "T24_Zcb_CZEXT_H_x8");

    // T25: c.sext.h rd'=x8
    // 15..13=100,12..10=111,9..7=000,6..5=11,4..2=011,1..0=01
    // = 1001_1100_0110_1101 = 0x9C6D
    // Expected: SEXT.H x8,x8 (Zbb)
    //   {7'b0110000,5'b00101,x8,3'b001,x8,7'b0010011} = 0x60541413
    clear_all();
    set_slot(0, {16'h0, 16'h9C6D}, 1'b1);
    @(posedge clk);
    check(0, 32'h60541413, 1'b1, "T25_Zcb_CSEXT_H_x8");

    // T26: c.zext.w rd'=x8  (Zcb/Zba - not in rv_zcb tools file)
    // 15..13=100,12..10=111,9..7=000,6..5=11,4..2=100,1..0=01
    // = 1001_1100_0111_0001 = 0x9C71
    // Expected: ADD.UW x8,x8,x0 (Zba)
    //   {7'b0000100,5'b00000,x8,3'b000,x8,7'b0111011} = 0x0804043B
    clear_all();
    set_slot(0, {16'h0, 16'h9C71}, 1'b1);
    @(posedge clk);
    check(0, 32'h0804043B, 1'b1, "T26_Zcb_CZEXT_W_x8");

    // T27: c.not rd'=x8
    // 15..13=100,12..10=111,9..7=000,6..5=11,4..2=101,1..0=01
    // = 1001_1100_0111_0101 = 0x9C75
    // Expected: XORI x8,x8,-1 = {12'hFFF,x8,3'b100,x8,7'b0010011}
    //         = 0xFFF44413
    clear_all();
    set_slot(0, {16'h0, 16'h9C75}, 1'b1);
    @(posedge clk);
    check(0, 32'hFFF44413, 1'b1, "T27_Zcb_CNOT_x8");

    // T28: c.mul rd'=x8, rs2'=x9
    // 15..13=100,12..10=111,9..7=000,6..5=10,4..2=001,1..0=01
    // = 1001_1100_0100_0101 = 0x9C45
    // crs2={01,001}=01001=x9, crs1={01,000}=x8
    // Expected: MULW x8,x8,x9 (M-ext)
    //   {7'b0000001,x9,x8,3'b000,x8,7'b0111011} = 0x0294043B
    clear_all();
    set_slot(0, {16'h0, 16'h9C45}, 1'b1);
    @(posedge clk);
    check(0, 32'h0294043B, 1'b1, "T28_Zcb_CMUL_x8_x9");

    // T29: c.sext.w rd=x8 (already handled by base C.ADDIW with imm=0)
    // Verify existing path: C.ADDIW x8, x8, 0
    // 15..13=001,12=0,11..7=01000(x8),6..2=00000,1..0=01
    // = 0010_0100_0000_0001 = 0x2401
    // Expected: ADDIW x8,x8,0 = {12'h000,x8,3'b000,x8,7'b0011011}
    //         = 0x0004041B
    clear_all();
    set_slot(0, {16'h0, 16'h2401}, 1'b1);
    @(posedge clk);
    check(0, 32'h0004041B, 1'b1, "T29_Zcb_CSEXT_W_x8_via_ADDIW");

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    $display("");
    $display("====================================================");
    $display("rvc_expander: PASS=%0d  FAIL=%0d", pass_count, fail_count);
    $display("====================================================");
    if (fail_count != 0)
        $display("STATUS: FAIL");
    else
        $display("STATUS: PASS");

    $finish;
end

endmodule

`default_nettype wire
