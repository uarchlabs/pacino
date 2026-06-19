// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ---------------------------------------------------------------------------
// decode_pkg.sv
// Shared types for the 8-issue OOO decoder pipeline.
// RVA23 / RV64GC compliant.
//
// Instruction format and per-slot decode packet definitions.
// Imported by rvc_expander and instr_decoder.
// ===================================================================

package decode_pkg;

// Number of decode slots
localparam int SLOTS = 8;

// Boundary mask bits per slot (2 bits each in fetch_mask)
//   [1] valid   - slot contains a valid instruction start
//   [0] is_rvc  - original instruction was 16-bit RVC (0 = 32-bit)
// MASK_BITS is used only by rvc_expander; suppress UNUSEDPARAM for modules
// that import this package but do not use this localparam.
/* verilator lint_off UNUSEDPARAM */
localparam int MASK_BITS = 2;
/* verilator lint_on UNUSEDPARAM */

// Instruction format encoding (RISC-V base formats)
typedef enum logic [2:0] {
    FMT_R   = 3'd0,
    FMT_I   = 3'd1,
    FMT_S   = 3'd2,
    FMT_B   = 3'd3,
    FMT_U   = 3'd4,
    FMT_J   = 3'd5,
    FMT_ILL = 3'd7
} instr_fmt_t;

// Functional unit operation codes
// Passed to rename/dispatch to route to correct execution unit.
// Width is 6 bits to fit in packed struct without waste.
typedef enum logic [5:0] {
    ALU_ADD    = 6'd0,
    ALU_SUB    = 6'd1,
    ALU_SLL    = 6'd2,
    ALU_SRL    = 6'd3,
    ALU_SRA    = 6'd4,
    ALU_AND    = 6'd5,
    ALU_OR     = 6'd6,
    ALU_XOR    = 6'd7,
    ALU_SLT    = 6'd8,
    ALU_SLTU   = 6'd9,
    ALU_ADDW   = 6'd10,
    ALU_SUBW   = 6'd11,
    ALU_SLLW   = 6'd12,
    ALU_SRLW   = 6'd13,
    ALU_SRAW   = 6'd14,
    ALU_LUI    = 6'd15,
    ALU_AUIPC  = 6'd16,
    ALU_JAL    = 6'd17,
    ALU_JALR   = 6'd18,
    ALU_BEQ    = 6'd19,
    ALU_BNE    = 6'd20,
    ALU_BLT    = 6'd21,
    ALU_BGE    = 6'd22,
    ALU_BLTU   = 6'd23,
    ALU_BGEU   = 6'd24,
    ALU_LB     = 6'd25,
    ALU_LH     = 6'd26,
    ALU_LW     = 6'd27,
    ALU_LD     = 6'd28,
    ALU_LBU    = 6'd29,
    ALU_LHU    = 6'd30,
    ALU_LWU    = 6'd31,
    ALU_SB     = 6'd32,
    ALU_SH     = 6'd33,
    ALU_SW     = 6'd34,
    ALU_SD     = 6'd35,
    ALU_MUL    = 6'd36,
    ALU_MULH   = 6'd37,
    ALU_MULHSU = 6'd38,
    ALU_MULHU  = 6'd39,
    ALU_DIV    = 6'd40,
    ALU_DIVU   = 6'd41,
    ALU_REM    = 6'd42,
    ALU_REMU   = 6'd43,
    ALU_MULW   = 6'd44,
    ALU_DIVW   = 6'd45,
    ALU_DIVUW  = 6'd46,
    ALU_REMW   = 6'd47,
    ALU_REMUW  = 6'd48,
    ALU_CSR    = 6'd49,
    ALU_ECALL  = 6'd50,
    ALU_EBREAK = 6'd51,
    ALU_MRET   = 6'd52,
    ALU_SRET   = 6'd53,
    ALU_WFI    = 6'd54,
    ALU_FENCE  = 6'd55,
    ALU_FLD    = 6'd56,
    ALU_FSD    = 6'd57,
    ALU_FMADD  = 6'd58,
    ALU_SLLI   = 6'd59,
    ALU_SRLI   = 6'd60,
    ALU_SRAI   = 6'd61,
    ALU_ANDI   = 6'd62,
    ALU_ILL    = 6'd63
} alu_op_t;

// Per-instruction decode packet.
// Passed as an 8-element array from instr_decoder to rename/dispatch.
//
// Downstream interface impact:
//   - rename stage reads uses_rd/rs1/rs2/rs3 to perform register renaming
//   - dispatch reads alu_op and is_* flags to route to functional units
//   - rs3 is non-zero only for FMA-class FP instructions
//   - imm is already sign-extended to 32 bits; rename widens to 64 bits
//   - is_illegal should cause a trap in the dispatch stage
typedef struct packed {
    logic        valid;      // slot contains a valid decoded instruction
    logic [31:0] instr;      // expanded 32b instruction word (post-RVC)
    logic [6:0]  opcode;
    logic [4:0]  rd;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rs3;        // FMADD/FMSUB only; zero for all others
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [31:0] imm;        // sign-extended immediate
    instr_fmt_t  fmt;
    alu_op_t     alu_op;
    logic        is_branch;
    logic        is_jump;
    logic        is_load;
    logic        is_store;
    logic        is_csr;
    logic        is_fp;
    logic        uses_rd;
    logic        uses_rs1;
    logic        uses_rs2;
    logic        uses_rs3;
    logic        is_illegal;
} decode_pkt_t;


// ---------------------------------------------------------------------------
// Vector operation class - expanded through DECODE-007.
//
// Coarse placeholders (0-7):
//   8'd0  VCFG   : vsetvl/vsetvli/vsetivli
//   8'd1  reserved (was VALU_INT, removed in DECODE-007)
//   8'd2  reserved (was VALU_FP,  removed in DECODE-006)
//   8'd3  VMEM   : vector loads/stores 0x07/0x27 (DECODE-008)
//   8'd4-7: legacy coarse codes retained, superseded by VOP_* entries
//
// VOP_* entries (8-167) are per-instruction opcodes:
//   OPIVV/OPIVX/OPIVI (DECODE-005): VOP_VADD..VOP_VWREDSUM (8-51)
//   OPMVV/OPMVX widening/MAC wired (DECODE-007):
//     VOP_VWADDU..VOP_VNMSUB (52-70)
//   OPFVV/OPFVF (DECODE-006): VOP_VFADD..VOP_VFWNMSAC (71-123)
//   DECODE-007 additions: VOP_VFMV_FS..VOP_VSLIDE1DOWN_X (124-167)
//
// Width is 8 bits to accommodate 168 entries (0-167).
//
// OPMVX operand note (funct3=3'b110):
//   vs1 is set to zero in vec_decode_pkt_t for all OPMVX instructions.
//   Scalar GPR source rs1=inst[19:15] lives in scalar decode_pkt_t.rs1.
//   Dispatch must inspect v_op_class to identify OPMVX scalar sources.
//
// Subfunct disambiguation (DECODE-006):
//   funct6=0x12 OPFVV: inst[19:15] selects vfcvt/vfwcvt/vfncvt subgroup
//     0x0C -> VOP_VFWCVT_FF (Zvfhmin), 0x14 -> VOP_VFNCVT_FF (Zvfhmin)
//     inst[19:18]=2'b00 -> VOP_VFCVT
//     inst[19:18]=2'b01 -> VOP_VFWCVT
//     inst[19:18]=2'b10 -> VOP_VFNCVT
//   funct6=0x13 OPFVV: inst[19:15] selects sqrt/class operation
// ---------------------------------------------------------------------------
typedef enum logic [7:0] {
    // -- coarse placeholders --
    VCFG         = 8'd0,  // vsetvl/vsetvli/vsetivli
    // 8'd1 reserved (was VALU_INT, removed DECODE-007)
    // 8'd2 reserved (was VALU_FP,  removed DECODE-006)
    VMEM         = 8'd3,  // vector memory (DECODE-008)
    VMASK        = 8'd4,  // mask ops (legacy coarse, superseded)
    VPERM        = 8'd5,  // permute/slide (legacy coarse, superseded)
    VREDUCE      = 8'd6,  // reduction (legacy coarse, superseded)
    VOTHER       = 8'd7,  // unclassified or potentially illegal
    // -- OPIVV/OPIVX/OPIVI per-instruction opcodes (DECODE-005) --
    VOP_VADD        = 8'd8,   // vadd.vv/vx/vi  funct6=0x00
    VOP_VSUB        = 8'd9,   // vsub.vv/vx     funct6=0x02
    VOP_VRSUB       = 8'd10,  // vrsub.vx/vi    funct6=0x03
    VOP_VMINU       = 8'd11,  // vminu.vv/vx    funct6=0x04
    VOP_VMIN        = 8'd12,  // vmin.vv/vx     funct6=0x05
    VOP_VMAXU       = 8'd13,  // vmaxu.vv/vx    funct6=0x06
    VOP_VMAX        = 8'd14,  // vmax.vv/vx     funct6=0x07
    VOP_VAND        = 8'd15,  // vand.vv/vx/vi  funct6=0x09
    VOP_VOR         = 8'd16,  // vor.vv/vx/vi   funct6=0x0a
    VOP_VXOR        = 8'd17,  // vxor.vv/vx/vi  funct6=0x0b
    VOP_VRGATHER    = 8'd18,  // vrgather.vv/vx/vi funct6=0x0c
    VOP_VSLIDEUP    = 8'd19,  // vslideup.vx/vi funct6=0x0e OPIVX/OPIVI
    VOP_VRGATHEREI16 = 8'd20, // vrgatherei16.vv funct6=0x0e OPIVV only
    VOP_VSLIDEDOWN  = 8'd21,  // vslidedown.vx/vi funct6=0x0f
    VOP_VADC        = 8'd22,  // vadc.vv/vx/vi  funct6=0x10
    VOP_VMADC       = 8'd23,  // vmadc.*        funct6=0x11
    VOP_VSBC        = 8'd24,  // vsbc.vv/vx     funct6=0x12
    VOP_VMSBC       = 8'd25,  // vmsbc.*        funct6=0x13
    VOP_VMERGE      = 8'd26,  // vmerge.* (vm=0) funct6=0x17
    VOP_VMV         = 8'd27,  // vmv.v.* (vm=1) funct6=0x17
    VOP_VMSEQ       = 8'd28,  // vmseq.*        funct6=0x18
    VOP_VMSNE       = 8'd29,  // vmsne.*        funct6=0x19
    VOP_VMSLTU      = 8'd30,  // vmsltu.vv/vx   funct6=0x1a
    VOP_VMSLT       = 8'd31,  // vmslt.vv/vx    funct6=0x1b
    VOP_VMSLEU      = 8'd32,  // vmsleu.*       funct6=0x1c
    VOP_VMSLE       = 8'd33,  // vmsle.*        funct6=0x1d
    VOP_VMSGTU      = 8'd34,  // vmsgtu.vx/vi   funct6=0x1e
    VOP_VMSGT       = 8'd35,  // vmsgt.vx/vi    funct6=0x1f
    VOP_VSADDU      = 8'd36,  // vsaddu.*       funct6=0x20
    VOP_VSADD       = 8'd37,  // vsadd.*        funct6=0x21
    VOP_VSSUBU      = 8'd38,  // vssubu.vv/vx   funct6=0x22
    VOP_VSSUB       = 8'd39,  // vssub.vv/vx    funct6=0x23
    VOP_VSLL        = 8'd40,  // vsll.*         funct6=0x25
    VOP_VSMUL       = 8'd41,  // vsmul.vv/vx    funct6=0x27 OPIVV/OPIVX
    VOP_VSRL        = 8'd42,  // vsrl.*         funct6=0x28
    VOP_VSRA        = 8'd43,  // vsra.*         funct6=0x29
    VOP_VSSRL       = 8'd44,  // vssrl.*        funct6=0x2a
    VOP_VSSRA       = 8'd45,  // vssra.*        funct6=0x2b
    VOP_VNSRL       = 8'd46,  // vnsrl.*        funct6=0x2c (narrowing)
    VOP_VNSRA       = 8'd47,  // vnsra.*        funct6=0x2d (narrowing)
    VOP_VNCLIPU     = 8'd48,  // vnclipu.*      funct6=0x2e (narrowing)
    VOP_VNCLIP      = 8'd49,  // vnclip.*       funct6=0x2f (narrowing)
    VOP_VWREDSUMU   = 8'd50,  // vwredsumu.vs   funct6=0x30 OPIVV
    VOP_VWREDSUM    = 8'd51,  // vwredsum.vs    funct6=0x31 OPIVV
    // -- OPMVV/OPMVX widening/MAC (stubs wired in DECODE-007) --
    VOP_VWADDU      = 8'd52,  // vwaddu.vv/vx   funct6=0x30
    VOP_VWADD       = 8'd53,  // vwadd.vv/vx    funct6=0x31
    VOP_VWSUBU      = 8'd54,  // vwsubu.vv/vx   funct6=0x32
    VOP_VWSUB       = 8'd55,  // vwsub.vv/vx    funct6=0x33
    VOP_VWADDU_W    = 8'd56,  // vwaddu.wv/wx   funct6=0x34
    VOP_VWADD_W     = 8'd57,  // vwadd.wv/wx    funct6=0x35
    VOP_VWSUBU_W    = 8'd58,  // vwsubu.wv/wx   funct6=0x36
    VOP_VWSUB_W     = 8'd59,  // vwsub.wv/wx    funct6=0x37
    VOP_VWMULU      = 8'd60,  // vwmulu.vv/vx   funct6=0x38
    VOP_VWMULSU     = 8'd61,  // vwmulsu.vv/vx  funct6=0x3a
    VOP_VWMUL       = 8'd62,  // vwmul.vv/vx    funct6=0x3b
    VOP_VWMACCU     = 8'd63,  // vwmaccu.vv/vx  funct6=0x3c
    VOP_VWMACC      = 8'd64,  // vwmacc.vv/vx   funct6=0x3d
    VOP_VWMACCUS    = 8'd65,  // vwmaccus.vx    funct6=0x3e OPMVX only
    VOP_VWMACCSU    = 8'd66,  // vwmaccsu.vv/vx funct6=0x3f
    VOP_VMACC       = 8'd67,  // vmacc.vv/vx    funct6=0x2d
    VOP_VNMSAC      = 8'd68,  // vnmsac.vv/vx   funct6=0x2f
    VOP_VMADD       = 8'd69,  // vmadd.vv/vx    funct6=0x29
    VOP_VNMSUB      = 8'd70,  // vnmsub.vv/vx   funct6=0x2b
    // -- OPFVV/OPFVF per-instruction opcodes (DECODE-006) --
    // Shared funct6 values appear under OPFVV; OPFVF uses same VOP_* codes.
    VOP_VFADD       = 8'd71,  // vfadd.vv/vf    funct6=0x00
    VOP_VFSUB       = 8'd72,  // vfsub.vv/vf    funct6=0x02
    VOP_VFREDUSUM   = 8'd73,  // vfredusum.vs   funct6=0x01 OPFVV only
    VOP_VFREDOSUM   = 8'd74,  // vfredosum.vs   funct6=0x03 OPFVV only
    VOP_VFMIN       = 8'd75,  // vfmin.vv/vf    funct6=0x04
    VOP_VFREDMIN    = 8'd76,  // vfredmin.vs    funct6=0x05 OPFVV only
    VOP_VFMAX       = 8'd77,  // vfmax.vv/vf    funct6=0x06
    VOP_VFREDMAX    = 8'd78,  // vfredmax.vs    funct6=0x07 OPFVV only
    VOP_VFSGNJ      = 8'd79,  // vfsgnj.vv/vf   funct6=0x08
    VOP_VFSGNJN     = 8'd80,  // vfsgnjn.vv/vf  funct6=0x09
    VOP_VFSGNJX     = 8'd81,  // vfsgnjx.vv/vf  funct6=0x0a
    VOP_VFSLIDE1UP  = 8'd82,  // vfslide1up.vf  funct6=0x0e OPFVF only
    VOP_VFSLIDE1DOWN = 8'd83, // vfslide1down.vf funct6=0x0f OPFVF only
    // VOP_VFMV: vfmv.s.f/vfmv.v.f funct6=0x10/0x17 OPFVF
    // vfmv.f.s (OPFVV funct6=0x10) uses VOP_VFMV_FS (8'd124).
    VOP_VFMV        = 8'd84,  // vfmv.s.f/vfmv.v.f OPFVF funct6=0x10/0x17
    VOP_VFMERGE     = 8'd85,  // vfmerge.vfm    funct6=0x17 vm=0 OPFVF
    // funct6=0x12: cvt group, subfunct at inst[19:15]
    VOP_VFCVT       = 8'd86,  // vfcvt.*        sub[4:3]=2'b00
    VOP_VFWCVT      = 8'd87,  // vfwcvt.*       sub[4:3]=2'b01 (not 0x0c)
    VOP_VFWCVT_FF   = 8'd88,  // vfwcvt.f.f.v   sub=0x0c Zvfhmin
    VOP_VFNCVT      = 8'd89,  // vfncvt.*       sub[4:3]=2'b10 (not 0x14)
    VOP_VFNCVT_FF   = 8'd90,  // vfncvt.f.f.w   sub=0x14 Zvfhmin
    // funct6=0x13: sqrt/class group, subfunct at inst[19:15]
    VOP_VFSQRT      = 8'd91,  // vfsqrt.v       sub=0x00
    VOP_VFRSQRT7    = 8'd92,  // vfrsqrt7.v     sub=0x04
    VOP_VFREC7      = 8'd93,  // vfrec7.v       sub=0x05
    VOP_VFCLASS     = 8'd94,  // vfclass.v      sub=0x10
    // FP compare
    VOP_VMFEQ       = 8'd95,  // vmfeq.vv/vf    funct6=0x18
    VOP_VMFLE       = 8'd96,  // vmfle.vv/vf    funct6=0x19
    VOP_VMFLT       = 8'd97,  // vmflt.vv/vf    funct6=0x1b
    VOP_VMFNE       = 8'd98,  // vmfne.vv/vf    funct6=0x1c
    VOP_VMFGT       = 8'd99,  // vmfgt.vf       funct6=0x1d OPFVF only
    VOP_VMFGE       = 8'd100, // vmfge.vf       funct6=0x1f OPFVF only
    // FP div/mul
    VOP_VFDIV       = 8'd101, // vfdiv.vv/vf    funct6=0x20
    VOP_VFRDIV      = 8'd102, // vfrdiv.vf      funct6=0x21 OPFVF only
    VOP_VFMUL       = 8'd103, // vfmul.vv/vf    funct6=0x24
    VOP_VFRSUB      = 8'd104, // vfrsub.vf      funct6=0x27 OPFVF only
    // FP FMA
    VOP_VFMADD      = 8'd105, // vfmadd.vv/vf   funct6=0x28
    VOP_VFNMADD     = 8'd106, // vfnmadd.vv/vf  funct6=0x29
    VOP_VFMSUB      = 8'd107, // vfmsub.vv/vf   funct6=0x2a
    VOP_VFNMSUB     = 8'd108, // vfnmsub.vv/vf  funct6=0x2b
    VOP_VFMACC      = 8'd109, // vfmacc.vv/vf   funct6=0x2c
    VOP_VFNMACC     = 8'd110, // vfnmacc.vv/vf  funct6=0x2d
    VOP_VFMSAC      = 8'd111, // vfmsac.vv/vf   funct6=0x2e
    VOP_VFNMSAC     = 8'd112, // vfnmsac.vv/vf  funct6=0x2f
    // FP widening
    VOP_VFWADD      = 8'd113, // vfwadd.vv/vf   funct6=0x30
    VOP_VFWREDUSUM  = 8'd114, // vfwredusum.vs  funct6=0x31 OPFVV only
    VOP_VFWSUB      = 8'd115, // vfwsub.vv/vf   funct6=0x32
    VOP_VFWREDOSUM  = 8'd116, // vfwredosum.vs  funct6=0x33 OPFVV only
    VOP_VFWADD_W    = 8'd117, // vfwadd.wv/wf   funct6=0x34
    VOP_VFWSUB_W    = 8'd118, // vfwsub.wv/wf   funct6=0x36
    VOP_VFWMUL      = 8'd119, // vfwmul.vv/vf   funct6=0x38
    VOP_VFWMACC     = 8'd120, // vfwmacc.vv/vf  funct6=0x3c
    VOP_VFWNMACC    = 8'd121, // vfwnmacc.vv/vf funct6=0x3d
    VOP_VFWMSAC     = 8'd122, // vfwmsac.vv/vf  funct6=0x3e
    VOP_VFWNMSAC    = 8'd123, // vfwnmsac.vv/vf funct6=0x3f
    // -- DECODE-007: vfmv.f.s tech debt fix (was shared with VOP_VFMV) --
    // VOP_VFMV_FS is OPFVV only: funct6=0x10, dest is scalar FP rd.
    // Dispatch must route to FP scalar output path.
    VOP_VFMV_FS     = 8'd124, // vfmv.f.s OPFVV funct6=0x10
    // -- DECODE-007: vmvNr whole-register move (OPIVI funct6=0x27 vm=1) --
    // vs1=0 field encodes N-1 (0->vmv1r, 1->vmv2r, 3->vmv4r, 7->vmv8r).
    VOP_VMVNR       = 8'd125, // vmv1r/2r/4r/8r.v OPIVI 0x27 vm=1
    // -- DECODE-007: OPMVV integer reduction (funct6=0x00-0x07) --
    VOP_VREDSUM     = 8'd126, // vredsum.vs  funct6=0x00 OPMVV
    VOP_VREDAND     = 8'd127, // vredand.vs  funct6=0x01 OPMVV
    VOP_VREDOR      = 8'd128, // vredor.vs   funct6=0x02 OPMVV
    VOP_VREDXOR     = 8'd129, // vredxor.vs  funct6=0x03 OPMVV
    VOP_VREDMINU    = 8'd130, // vredminu.vs funct6=0x04 OPMVV
    VOP_VREDMIN     = 8'd131, // vredmin.vs  funct6=0x05 OPMVV
    VOP_VREDMAXU    = 8'd132, // vredmaxu.vs funct6=0x06 OPMVV
    VOP_VREDMAX     = 8'd133, // vredmax.vs  funct6=0x07 OPMVV
    // -- DECODE-007: average arithmetic OPMVV/OPMVX funct6=0x08-0x0b --
    VOP_VAADDU      = 8'd134, // vaaddu.vv/vx funct6=0x08
    VOP_VAADD       = 8'd135, // vaadd.vv/vx  funct6=0x09
    VOP_VASUBU      = 8'd136, // vasubu.vv/vx funct6=0x0a
    VOP_VASUB       = 8'd137, // vasub.vv/vx  funct6=0x0b
    // -- DECODE-007: scalar GPR moves (OPMVV/OPMVX funct6=0x10) --
    // VMV_XS: GPR dest rd; vs2 is source vector; OPMVV sub=0x00.
    // VMV_SX: vd[0] dest; GPR src rs1=inst[19:15]; OPMVX.
    // VCPOP/VFIRST: GPR dest rd; OPMVV sub=0x10/0x11.
    // Downstream dispatch must handle GPR source/dest for all four.
    VOP_VMV_XS      = 8'd138, // vmv.x.s GPR dest, OPMVV 0x10 sub=0x00
    VOP_VMV_SX      = 8'd139, // vmv.s.x GPR src,  OPMVX 0x10
    VOP_VCPOP       = 8'd140, // vcpop.m GPR dest, OPMVV 0x10 sub=0x10
    VOP_VFIRST      = 8'd141, // vfirst.m GPR dest,OPMVV 0x10 sub=0x11
    // -- DECODE-007: integer extension OPMVV funct6=0x12 --
    // Extension factor (vf2/vf4/vf8) encoded in inst[19:15]:
    //   even sub -> vzext, odd sub -> vsext
    VOP_VZEXT       = 8'd142, // vzext.vf{2,4,8} OPMVV 0x12 even sub
    VOP_VSEXT       = 8'd143, // vsext.vf{2,4,8} OPMVV 0x12 odd sub
    // -- DECODE-007: mask set/predict OPMVV funct6=0x14 --
    VOP_VMSBF       = 8'd144, // vmsbf.m  OPMVV 0x14 sub=0x01
    VOP_VMSOF       = 8'd145, // vmsof.m  OPMVV 0x14 sub=0x02
    VOP_VMSIF       = 8'd146, // vmsif.m  OPMVV 0x14 sub=0x03
    VOP_VIOTA       = 8'd147, // viota.m  OPMVV 0x14 sub=0x10
    VOP_VID         = 8'd148, // vid.v    OPMVV 0x14 sub=0x11; no vs2
    // -- DECODE-007: vcompress.vm OPMVV funct6=0x17 --
    VOP_VCOMPRESS   = 8'd149, // vcompress.vm OPMVV 0x17
    // -- DECODE-007: mask logical OPMVV funct6=0x18-0x1f --
    // vm=1 always; these operate directly on mask registers.
    // No tail/mask agnostic policy; vd/vs1/vs2 are all mask regs.
    VOP_VMANDN      = 8'd150, // vmandn.mm funct6=0x18 OPMVV
    VOP_VMAND       = 8'd151, // vmand.mm  funct6=0x19 OPMVV
    VOP_VMOR        = 8'd152, // vmor.mm   funct6=0x1a OPMVV
    VOP_VMXOR       = 8'd153, // vmxor.mm  funct6=0x1b OPMVV
    VOP_VMORN       = 8'd154, // vmorn.mm  funct6=0x1c OPMVV
    VOP_VMNAND      = 8'd155, // vmnand.mm funct6=0x1d OPMVV
    VOP_VMNOR       = 8'd156, // vmnor.mm  funct6=0x1e OPMVV
    VOP_VMXNOR      = 8'd157, // vmxnor.mm funct6=0x1f OPMVV
    // -- DECODE-007: integer div/rem OPMVV/OPMVX funct6=0x20-0x23 --
    VOP_VDIVU       = 8'd158, // vdivu.vv/vx  funct6=0x20
    VOP_VDIV        = 8'd159, // vdiv.vv/vx   funct6=0x21
    VOP_VREMU       = 8'd160, // vremu.vv/vx  funct6=0x22
    VOP_VREM        = 8'd161, // vrem.vv/vx   funct6=0x23
    // -- DECODE-007: integer multiply OPMVV/OPMVX funct6=0x24-0x27 --
    VOP_VMULHU      = 8'd162, // vmulhu.vv/vx  funct6=0x24
    VOP_VMUL        = 8'd163, // vmul.vv/vx    funct6=0x25
    VOP_VMULHSU     = 8'd164, // vmulhsu.vv/vx funct6=0x26
    VOP_VMULH       = 8'd165, // vmulh.vv/vx   funct6=0x27
    // -- DECODE-007: OPMVX-only slide1 (funct6=0x0e/0x0f) --
    // GPR rs1 is slide amount; vs1 zeroed in packet.
    VOP_VSLIDE1UP_X   = 8'd166, // vslide1up.vx  OPMVX 0x0e
    VOP_VSLIDE1DOWN_X = 8'd167, // vslide1down.vx OPMVX 0x0f
    // -- DECODE-008: vector memory per-instruction opcodes --
    // Opcodes 0x07 (OP_LOAD_FP) / 0x27 (OP_STORE_FP); VMEM class.
    // EEW encoded in eew field (raw width bits 3'b000/101/110/111).
    // Non-segment ops (nf==3'b000):
    VOP_VLE        = 8'd168, // unit-stride load  vle8/16/32/64.v
    VOP_VSE        = 8'd169, // unit-stride store vse8/16/32/64.v
    VOP_VLSE       = 8'd170, // strided load  vlse8/16/32/64.v
    VOP_VSSE       = 8'd171, // strided store vsse8/16/32/64.v
    VOP_VLUXE      = 8'd172, // unordered indexed load  vluxei*.v
    VOP_VSUXE      = 8'd173, // unordered indexed store vsuxei*.v
    VOP_VLOXE      = 8'd174, // ordered indexed load  vloxei*.v
    VOP_VSOXE      = 8'd175, // ordered indexed store vsoxei*.v
    VOP_VLM        = 8'd176, // mask load  vlm.v
    VOP_VSM        = 8'd177, // mask store vsm.v
    VOP_VLWHOLE    = 8'd178, // whole-register load  vl1r/2r/4r/8r.v
    VOP_VSWHOLE    = 8'd179, // whole-register store vs1r/2r/4r/8r.v
    VOP_VLFF       = 8'd180, // fault-only-first load vle8/16/32/64ff.v
    // Segment ops (nf>0): fully decoded in DECODE-009
    // nf field (inst[31:29]) preserved in pkt.nf for LSU
    VOP_VLSEG      = 8'd181, // unit-stride segment load
    VOP_VSSEG      = 8'd182, // unit-stride segment store
    VOP_VLSSEG     = 8'd183, // strided segment load
    VOP_VSSSEG     = 8'd184, // strided segment store
    VOP_VLUXSEG    = 8'd185, // unordered indexed segment load
    VOP_VSUXSEG    = 8'd186, // unordered indexed segment store
    VOP_VLOXSEG    = 8'd187, // ordered indexed segment load
    VOP_VSOXSEG    = 8'd188  // ordered indexed segment store
} v_op_class_t;

// Extension enable/disable control.
// Driven from misa fields by the CSR unit; decoder sees only the
// current enable state. Dependency enforcement (D requires F, etc.)
// is a software/driver responsibility - not checked in RTL.
// All bits are 1 at reset for the RVA23 profile.
typedef struct packed {
  logic en_m;       // M   multiply/divide
  logic en_a;       // A   atomics
  logic en_f;       // F   single precision float
  logic en_d;       // D   double precision float
  logic en_c;       // C   compressed (base)
  logic en_zcb;     // Zcb additional compressed
  logic en_zba;     // Zba bitmanip address gen
  logic en_zbb;     // Zbb bitmanip basic
  logic en_zbs;     // Zbs bitmanip single bit
  logic en_zfhmin;  // Zfhmin half precision float
  logic en_zfa;     // Zfa additional FP ops
  logic en_zicsr;   // Zicsr CSR instructions
  logic en_zicbom;  // Zicbom cache block management
  logic en_zicbop;  // Zicbop cache block prefetch
  logic en_zicboz;  // Zicboz cache block zero
  logic en_v;       // V   vector
  logic en_zvfhmin; // Zvfhmin vector half precision
  logic en_h;       // H   hypervisor
} ext_enable_t;

// RVA23 default: all extensions enabled (all bits 1).
/* verilator lint_off UNUSEDPARAM */
parameter ext_enable_t RVA23_ENABLE = '{default: 1'b1};
/* verilator lint_on UNUSEDPARAM */

// Per-slot pre-decode packet.
// Produced by predecode.sv; consumed by instr_decoder.sv.
// Carries the raw (or RVC-expanded) instruction with early annotations
// for vtype dependency and a conservative branch hint.
//
// vtype_hazard is informational: rename resolves the actual policy.
// may_be_branch is conservative: full decode remains in instr_decoder.
// See CLAUDE.md microarchitectural implications.
typedef struct packed {
  // instruction validity
  logic        valid;          // slot contains a valid instruction

  // raw instruction (post RVC expansion if present, else raw)
  logic [31:0] instr;          // instruction bits passed to decoder

  // vtype annotation fields
  logic        is_vsetvl;      // slot is vsetvl/vsetvli/vsetivli
  logic        needs_vtype;    // slot consumes current vtype
  logic        vtype_hazard;   // vsetvl precedes a needs_vtype in
                               // the same bundle -- intra-bundle
                               // dependency detected

  // early branch hint (placeholder for DECODE-011)
  logic        may_be_branch;  // conservative early branch detect
                               // set if opcode is JAL/JALR/BRANCH
                               // full resolution deferred to decode
} predecode_pkt_t;

// Per-instruction vector decode packet.
// Travels in parallel with decode_pkt_t through the pipeline.
// Populated when opcode == OP_VECTOR (0x57) or when a vector memory
// instruction is detected at OP_LOAD_FP (0x07) / OP_STORE_FP (0x27).
// DECODE-008: vector memory disambiguated by inst[14:12] width field.
// Rename reads is_vsetvl/needs_vtype to resolve vtype dependency.
//
// Intra-bundle vtype dependency policy is TBD at rename/dispatch.
// Decoder sets is_vsetvl and needs_vtype correctly; rename resolves.
// See CLAUDE.md microarchitectural implications.
typedef struct packed {
    // -- instruction class --
    logic        is_vector;   // this is a vector instruction
    logic        is_vsetvl;   // this instruction sets vtype/vl
    logic        needs_vtype; // this instruction consumes vtype

    // -- vtype fields - populated by vsetvl/vsetvli/vsetivli only --
    logic [2:0]  vsew;        // selected element width encoding
    logic [2:0]  vlmul;       // vector register grouping encoding
    logic        vta;         // tail agnostic policy
    logic        vma;         // mask agnostic policy

    // -- vector register operands --
    logic [4:0]  vd;          // destination vector register
    logic [4:0]  vs1;         // source vector register 1
    logic [4:0]  vs2;         // source vector register 2
    logic [4:0]  vs3;         // source vector register 3 (stores)
    logic        vm;          // mask enable (0=masked, 1=unmasked)

    // -- memory/segment fields --
    logic [2:0]  nf;          // number of fields (segment ops)
    logic [2:0]  eew;         // effective element width (memory ops)

    // -- operation type --
    // Coarse: VCFG, VMEM, VMASK, VPERM, VREDUCE, VOTHER (0,3-7)
    // OPIVV/OPIVX/OPIVI (DECODE-005): VOP_VADD..VOP_VWREDSUM (8-51)
    // OPMVV/OPMVX wired (DECODE-007): VOP_VWADDU..VOP_VNMSUB (52-70)
    // OPFVV/OPFVF (DECODE-006): VOP_VFADD..VOP_VFWNMSAC (71-123)
    //   VOP_VFWCVT_FF (88) = vfwcvt.f.f.v  Zvfhmin
    //   VOP_VFNCVT_FF (90) = vfncvt.f.f.w  Zvfhmin
    // DECODE-007 new: VOP_VFMV_FS..VOP_VSLIDE1DOWN_X (124-167)
    //   VOP_VFMV_FS (124) = vfmv.f.s  OPFVV tech-debt fix
    // DECODE-008/009: vector memory VOP_VLE..VOP_VSOXSEG (168-188)
    //   From opcode 0x07/0x27; VMEM class; segment ops complete
    v_op_class_t v_op_class;
} vec_decode_pkt_t;

endpackage
