// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// instr_decoder.sv
// 8-wide parallel instruction decoder for RVA23 / RV64GC.
//
// Receives a predecode_pkt_t bundle (8 slots) from predecode.sv.
// Extracts instr[31:0] and valid from each slot internally.
// Produces one decode_pkt_t and one vec_decode_pkt_t per slot.
// All slots decode simultaneously; no sequential dependency.
//
// The predecode_bundle input is passed through unchanged to the output
// predecode_out so rename can read vtype_hazard and other pre-decode
// annotations without re-reading the fetch stage.
//   predecode_pkt_t.vtype_hazard is available to rename via
//   predecode_out -- policy TBD per CLAUDE.md.
//
// Downstream interface note:
//   - decode_bundle[8] connects directly to rename/dispatch stage
//   - vec_decode_bundle[8] carries vector decode alongside decode_bundle
//   - predecode_out[8] passes pre-decode annotations to rename
//   - Slots with valid=0 carry zeroed decode packets; rename should skip
//   - is_illegal=1 slots should cause a precise exception in dispatch
// ===================================================================

`default_nettype none

/* verilator lint_off IMPORTSTAR */
/* verilator lint_off UNUSEDPARAM */
import decode_pkg::*;
/* verilator lint_on UNUSEDPARAM */
/* verilator lint_on IMPORTSTAR */

/* verilator lint_off UNUSEDPARAM */
module instr_decoder (
    // --- extension enable/disable control ---
    input  ext_enable_t                 ext_enable,

    // --- pre-decoded bundle from predecode.sv ---
    // instr[31:0] and valid are extracted internally from each slot.
    input  predecode_pkt_t  [SLOTS-1:0] predecode_bundle,

    // --- scalar decoded output bundle to rename/dispatch ---
    output decode_pkt_t     [SLOTS-1:0] decode_bundle,

    // --- vector decoded output bundle (parallel to decode_bundle) ---
    // Populated for OP_VECTOR (0x57) slots; zero for all others.
    // Rename/dispatch uses is_vector to steer to the vector unit.
    output vec_decode_pkt_t [SLOTS-1:0] vec_decode_bundle,
    output logic            [SLOTS-1:0] is_vector,

    // --- pre-decode pass-through to rename ---
    // predecode_pkt_t.vtype_hazard is available to rename via this
    // output -- policy TBD per CLAUDE.md.
    output predecode_pkt_t  [SLOTS-1:0] predecode_out
);

// ---------------------------------------------------------------------------
// Standard 7-bit opcode values
// ---------------------------------------------------------------------------
localparam logic [6:0] OP_LOAD     = 7'b0000011;
localparam logic [6:0] OP_LOAD_FP  = 7'b0000111;
localparam logic [6:0] OP_MISC_MEM = 7'b0001111;
localparam logic [6:0] OP_IMM      = 7'b0010011;
localparam logic [6:0] OP_AUIPC    = 7'b0010111;
localparam logic [6:0] OP_IMM_32   = 7'b0011011;
localparam logic [6:0] OP_STORE    = 7'b0100011;
localparam logic [6:0] OP_STORE_FP = 7'b0100111;
localparam logic [6:0] OP_AMO      = 7'b0101111;
localparam logic [6:0] OP_REG      = 7'b0110011;
localparam logic [6:0] OP_LUI      = 7'b0110111;
localparam logic [6:0] OP_REG_32   = 7'b0111011;
localparam logic [6:0] OP_MADD     = 7'b1000011;
localparam logic [6:0] OP_MSUB     = 7'b1000111;
localparam logic [6:0] OP_NMSUB    = 7'b1001011;
localparam logic [6:0] OP_NMADD    = 7'b1001111;
localparam logic [6:0] OP_FP       = 7'b1010011;
localparam logic [6:0] OP_BRANCH   = 7'b1100011;
localparam logic [6:0] OP_JALR     = 7'b1100111;
localparam logic [6:0] OP_JAL      = 7'b1101111;
localparam logic [6:0] OP_SYSTEM   = 7'b1110011;
localparam logic [6:0] OP_VECTOR   = 7'b1010111; // RVV opcode 0x57

// ---------------------------------------------------------------------------
// Immediate extraction helpers (all return 32-bit sign-extended values)
// Each helper uses only the relevant instruction bits; others are intentionally
// ignored - suppress UNUSEDSIGNAL for the function-local inst parameter.
// ---------------------------------------------------------------------------

/* verilator lint_off UNUSEDSIGNAL */

function automatic logic [31:0] imm_i(input logic [31:0] inst);
    return {{20{inst[31]}}, inst[31:20]};
endfunction

function automatic logic [31:0] imm_s(input logic [31:0] inst);
    return {{20{inst[31]}}, inst[31:25], inst[11:7]};
endfunction

function automatic logic [31:0] imm_b(input logic [31:0] inst);
    return {{19{inst[31]}}, inst[31], inst[7],
            inst[30:25], inst[11:8], 1'b0};
endfunction

function automatic logic [31:0] imm_u(input logic [31:0] inst);
    return {inst[31:12], 12'b0};
endfunction

function automatic logic [31:0] imm_j(input logic [31:0] inst);
    return {{11{inst[31]}}, inst[31], inst[19:12],
            inst[20], inst[30:21], 1'b0};
endfunction

function automatic logic [31:0] imm_shamt(input logic [31:0] inst);
    // 6-bit shift amount for RV64: inst[25:20]
    return {26'b0, inst[25:20]};
endfunction

/* verilator lint_on UNUSEDSIGNAL */

// ---------------------------------------------------------------------------
// Single-slot vector decode function
// Returns a vec_decode_pkt_t for one instruction slot.
// Only OP_VECTOR (0x57) instructions produce a non-zero packet.
// Vector memory instructions (vle*/vse* etc.) use opcodes 0x07/0x27 and
// are currently misidentified as FP loads/stores. Fix is in DECODE-008.
//
// RVV field positions (all OP_VECTOR instructions):
//   vd    = inst[11:7]   vs1   = inst[19:15]
//   vs2   = inst[24:20]  vs3   = inst[11:7]  (same bits as vd, stores only)
//   vm    = inst[25]     funct3 = inst[14:12]
//   nf    = inst[31:29]  funct6 = inst[31:26]
//
// vtype immediate layout (vsetvli / vsetivli):
//   inst[22:20] = vlmul[2:0]   inst[25:23] = vsew[2:0]
//   inst[26]    = vta           inst[27]    = vma
//
// Intra-bundle vtype dependency policy is TBD at rename/dispatch.
// Decoder sets is_vsetvl and needs_vtype correctly; rename resolves.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Vector memory decode helper (DECODE-008)
// Called from decode_vec_one when opcode 0x07/0x27 AND width[14:12] is
// in {3'b000, 3'b101, 3'b110, 3'b111} (EEW=8/16/32/64 vector widths).
// Scalar FP uses width 3'b011 (FLD/FSD) which does NOT reach this path.
//
// RVV memory field layout:
//   inst[31:29] = nf    (nf>0 -> segment op, deferred to DECODE-009)
//   inst[27:26] = mop   (00=unit-stride, 01=unord-idx, 10=stride, 11=ord-idx)
//   inst[25]    = vm    (mask enable: 1=unmasked, 0=masked)
//   inst[24:20] = lumr  (depends on mop: special/vs2/rs2)
//   inst[19:15] = rs1   (base GPR; always present in scalar decode_pkt_t)
//   inst[14:12] = width (EEW encoding, stored verbatim in eew field)
//   inst[11:7]  = vd (load) or vs3 (store)
//
// Addressing mode notes for downstream LSU:
//   unit-stride (mop=00): rs1=base GPR; inst[24:20] is sub-variant code
//   strided     (mop=10): rs1=base GPR, rs2=stride GPR
//     - scalar decode_pkt_t.uses_rs2 set by decode_one; pkt.vs2 = 0
//   unord-idx   (mop=01): rs1=base GPR, vs2=index vector (inst[24:20])
//   ord-idx     (mop=11): rs1=base GPR, vs2=index vector (inst[24:20])
// ---------------------------------------------------------------------------
/* verilator lint_off UNUSEDSIGNAL */
function automatic vec_decode_pkt_t decode_vec_mem_one(
    input logic [31:0] inst,
    input logic        is_store
);
    vec_decode_pkt_t pkt;
    logic [2:0]      nf;
    logic [1:0]      mop;

    pkt             = '0;
    pkt.is_vector   = 1'b1;
    pkt.needs_vtype = 1'b1;
    pkt.vm          = inst[25];
    pkt.nf          = inst[31:29];
    // Store raw width bits; 000/101/110/111 -> EEW 8/16/32/64
    pkt.eew         = inst[14:12];

    nf  = inst[31:29];
    mop = inst[27:26];

    if (!is_store)
        pkt.vd  = inst[11:7];  // destination vector register (load)
    else
        pkt.vs3 = inst[11:7];  // source data vector register (store)

    // Segment ops: nf>0 selects VOP_*SEG variant by addressing mode.
    // nf is stored as nfields-1 in inst[31:29]; nf=0 is non-segment,
    // nf=1 means 2 fields, nf=7 means 8 fields. LSU reads pkt.nf
    // to determine fields-per-segment at issue time.
    if (nf != 3'b000) begin
        case (mop)
            2'b00: pkt.v_op_class =
                       is_store ? VOP_VSSEG   : VOP_VLSEG;
            2'b10: pkt.v_op_class =
                       is_store ? VOP_VSSSEG  : VOP_VLSSEG;
            2'b01: pkt.v_op_class =
                       is_store ? VOP_VSUXSEG : VOP_VLUXSEG;
            2'b11: pkt.v_op_class =
                       is_store ? VOP_VSOXSEG : VOP_VLOXSEG;
            default: pkt.v_op_class = VMEM;
        endcase
        return pkt;
    end

    // Non-segment: decode by addressing mode
    case (mop)
        2'b00: begin
            // Unit-stride: inst[24:20] selects sub-variant
            case (inst[24:20])
                5'b00000: // vle*/vse* normal unit-stride
                    pkt.v_op_class = is_store ? VOP_VSE     : VOP_VLE;
                5'b01011: // vlm.v / vsm.v  (mask; vm=1 always)
                    pkt.v_op_class = is_store ? VOP_VSM     : VOP_VLM;
                5'b01000: // vl1r..8r / vs1r..8r whole-register
                    pkt.v_op_class = is_store ? VOP_VSWHOLE : VOP_VLWHOLE;
                5'b10000: // vle*ff fault-only-first (load only)
                    pkt.v_op_class = is_store ? VOP_VSE     : VOP_VLFF;
                default: pkt.v_op_class = VMEM;
            endcase
        end
        2'b01: begin
            // Unordered indexed: vs2 = index vector register
            pkt.vs2        = inst[24:20];
            pkt.v_op_class = is_store ? VOP_VSUXE : VOP_VLUXE;
        end
        2'b10: begin
            // Strided: rs2=stride GPR; uses_rs2 set in scalar decode_one
            pkt.v_op_class = is_store ? VOP_VSSE  : VOP_VLSE;
        end
        2'b11: begin
            // Ordered indexed: vs2 = index vector register
            pkt.vs2        = inst[24:20];
            pkt.v_op_class = is_store ? VOP_VSOXE : VOP_VLOXE;
        end
        default: pkt.v_op_class = VMEM;
    endcase

    // Whole-register ops transfer nreg x VLEN/8 bytes regardless of
    // vtype state: no SEW, LMUL, or vl dependency. Clear needs_vtype
    // here after the MOP decode has assigned v_op_class.
    if (pkt.v_op_class == VOP_VLWHOLE ||
        pkt.v_op_class == VOP_VSWHOLE) begin
        pkt.needs_vtype = 1'b0;
    end

    return pkt;
endfunction
/* verilator lint_on UNUSEDSIGNAL */

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off VARHIDDEN */
function automatic vec_decode_pkt_t decode_vec_one(
    input logic [31:0]  inst,
    input logic         valid,
    input ext_enable_t  ext_enable
);
    vec_decode_pkt_t pkt;
    logic [6:0] op;
    logic [2:0] f3;
    logic [5:0] f6;

    pkt = '0;
    if (!valid) return pkt;
    // Vector disabled: return empty packet (is_illegal set in decode_one)
    if (!ext_enable.en_v) return pkt;

    op = inst[6:0];
    f3 = inst[14:12];
    f6 = inst[31:26];

    // DECODE-008: vector memory uses OP_LOAD_FP (0x07) / OP_STORE_FP (0x27)
    // Width values 3'b000/101/110/111 are EEW8/16/32/64 (vector only).
    // Scalar FP uses 3'b011 (FLD/FSD); no overlap.
    if (op == OP_LOAD_FP || op == OP_STORE_FP) begin
        if (f3 == 3'b000 || f3 == 3'b101 ||
            f3 == 3'b110 || f3 == 3'b111) begin
            return decode_vec_mem_one(inst, op == OP_STORE_FP);
        end
        return pkt; // scalar FP load/store: not vector
    end

    if (op != OP_VECTOR) return pkt;

    // Common fields for all OP_VECTOR instructions
    pkt.is_vector = 1'b1;
    pkt.vd        = inst[11:7];
    pkt.vs1       = inst[19:15];
    pkt.vs2       = inst[24:20];
    pkt.vs3       = inst[11:7];   // alias for vd position; valid for stores
    pkt.vm        = inst[25];
    pkt.nf        = inst[31:29];

    if (f3 == 3'b111) begin
        // vsetvl / vsetvli / vsetivli  (funct3 = OPCFG)
        // Distinguish by inst[31:30]:
        //   2'b0x -> vsetvli  (31=0): zimm11 in inst[30:20]
        //   2'b11 -> vsetivli (31:30=11): zimm10 in inst[29:20]
        //   2'b10 -> vsetvl   (31:30=10): vtype from rs2 register
        pkt.is_vsetvl  = 1'b1;
        pkt.v_op_class = VCFG;

        if (!inst[31] || inst[30]) begin
            // vsetvli or vsetivli: vtype encoded in immediate
            // Both forms share the same bit positions for vtype subfields
            pkt.vlmul = inst[22:20]; // vlmul[2:0]
            pkt.vsew  = inst[25:23]; // vsew[2:0]
            pkt.vta   = inst[26];    // tail agnostic
            pkt.vma   = inst[27];    // mask agnostic
        end
        // else vsetvl: vtype comes from rs2 at runtime; leave fields at 0

    end else begin
        // All non-CFG vector instructions consume vtype from vtype CSR.
        pkt.needs_vtype = 1'b1;

        // Outer case on funct3 selects the encoding group.
        //   3'b001 = OPFVV  FP vector-vector   (DECODE-006)
        //   3'b101 = OPFVF  FP vector-scalar   (DECODE-006)
        //   3'b010 = OPMVV  int/mask/reduce vv  (DECODE-007)
        //   3'b110 = OPMVX  int/mask/reduce vx  (DECODE-007)
        //   3'b000 = OPIVV  int vector-vector  (DECODE-005)
        //   3'b100 = OPIVX  int vector-scalar  (DECODE-005)
        //   3'b011 = OPIVI  int vector-imm     (DECODE-005)
        case (f3)

            // ----------------------------------------------------------
            // OPFVV - FP vector-vector (funct3=3'b001)
            // funct6 values from rv_v OPFVV section.
            // funct6=0x12: cvt group, disambiguated by inst[19:15]:
            //   0x0c -> vfwcvt.f.f.v (Zvfhmin), 0x14 -> vfncvt.f.f.w
            //   inst[19:18]=2'b00 -> vfcvt, 2'b01 -> vfwcvt, 2'b10 -> vfncvt
            // funct6=0x13: sqrt/class group, disambiguated by inst[19:15].
            // ----------------------------------------------------------
            3'b001: begin
                case (f6)
                    6'h00: pkt.v_op_class = VOP_VFADD;
                    6'h01: pkt.v_op_class = VOP_VFREDUSUM;
                    6'h02: pkt.v_op_class = VOP_VFSUB;
                    6'h03: pkt.v_op_class = VOP_VFREDOSUM;
                    6'h04: pkt.v_op_class = VOP_VFMIN;
                    6'h05: pkt.v_op_class = VOP_VFREDMIN;
                    6'h06: pkt.v_op_class = VOP_VFMAX;
                    6'h07: pkt.v_op_class = VOP_VFREDMAX;
                    6'h08: pkt.v_op_class = VOP_VFSGNJ;
                    6'h09: pkt.v_op_class = VOP_VFSGNJN;
                    6'h0a: pkt.v_op_class = VOP_VFSGNJX;
                    // 0x10: vfmv.f.s (vm=1, vs1=0, dest is scalar FP rd)
                    // VOP_VFMV_FS is distinct from VOP_VFMV (OPFVF vfmv.s.f)
                    // so dispatch can route to FP scalar output without
                    // inspecting funct3.
                    6'h10: pkt.v_op_class = VOP_VFMV_FS;
                    // 0x12: vfcvt/vfwcvt/vfncvt, subfunct at inst[19:15]
                    6'h12: begin
                        case (inst[19:15])
                            5'h0c: pkt.v_op_class = VOP_VFWCVT_FF;
                            5'h14: pkt.v_op_class = VOP_VFNCVT_FF;
                            default: begin
                                case (inst[19:18])
                                    2'b00: pkt.v_op_class = VOP_VFCVT;
                                    2'b01: pkt.v_op_class = VOP_VFWCVT;
                                    2'b10: pkt.v_op_class = VOP_VFNCVT;
                                    default: pkt.v_op_class = VOTHER;
                                endcase
                            end
                        endcase
                    end
                    // 0x13: vfsqrt/vfrsqrt7/vfrec7/vfclass
                    6'h13: begin
                        case (inst[19:15])
                            5'h00: pkt.v_op_class = VOP_VFSQRT;
                            5'h04: pkt.v_op_class = VOP_VFRSQRT7;
                            5'h05: pkt.v_op_class = VOP_VFREC7;
                            5'h10: pkt.v_op_class = VOP_VFCLASS;
                            default: pkt.v_op_class = VOTHER;
                        endcase
                    end
                    6'h18: pkt.v_op_class = VOP_VMFEQ;
                    6'h19: pkt.v_op_class = VOP_VMFLE;
                    6'h1b: pkt.v_op_class = VOP_VMFLT;
                    6'h1c: pkt.v_op_class = VOP_VMFNE;
                    6'h20: pkt.v_op_class = VOP_VFDIV;
                    6'h24: pkt.v_op_class = VOP_VFMUL;
                    6'h28: pkt.v_op_class = VOP_VFMADD;
                    6'h29: pkt.v_op_class = VOP_VFNMADD;
                    6'h2a: pkt.v_op_class = VOP_VFMSUB;
                    6'h2b: pkt.v_op_class = VOP_VFNMSUB;
                    6'h2c: pkt.v_op_class = VOP_VFMACC;
                    6'h2d: pkt.v_op_class = VOP_VFNMACC;
                    6'h2e: pkt.v_op_class = VOP_VFMSAC;
                    6'h2f: pkt.v_op_class = VOP_VFNMSAC;
                    6'h30: pkt.v_op_class = VOP_VFWADD;
                    6'h31: pkt.v_op_class = VOP_VFWREDUSUM;
                    6'h32: pkt.v_op_class = VOP_VFWSUB;
                    6'h33: pkt.v_op_class = VOP_VFWREDOSUM;
                    6'h34: pkt.v_op_class = VOP_VFWADD_W;
                    6'h36: pkt.v_op_class = VOP_VFWSUB_W;
                    6'h38: pkt.v_op_class = VOP_VFWMUL;
                    6'h3c: pkt.v_op_class = VOP_VFWMACC;
                    6'h3d: pkt.v_op_class = VOP_VFWNMACC;
                    6'h3e: pkt.v_op_class = VOP_VFWMSAC;
                    6'h3f: pkt.v_op_class = VOP_VFWNMSAC;
                    default: pkt.v_op_class = VOTHER;
                endcase
            end

            // ----------------------------------------------------------
            // OPFVF - FP vector-scalar (funct3=3'b101)
            // funct6 values from rv_v OPFVF section.
            // 0x17: vfmerge (vm=0) vs vfmv.v.f (vm=1).
            // No cvt or sqrt group; those are OPFVV only.
            // ----------------------------------------------------------
            3'b101: begin
                case (f6)
                    6'h00: pkt.v_op_class = VOP_VFADD;
                    6'h02: pkt.v_op_class = VOP_VFSUB;
                    6'h04: pkt.v_op_class = VOP_VFMIN;
                    6'h06: pkt.v_op_class = VOP_VFMAX;
                    6'h08: pkt.v_op_class = VOP_VFSGNJ;
                    6'h09: pkt.v_op_class = VOP_VFSGNJN;
                    6'h0a: pkt.v_op_class = VOP_VFSGNJX;
                    6'h0e: pkt.v_op_class = VOP_VFSLIDE1UP;
                    6'h0f: pkt.v_op_class = VOP_VFSLIDE1DOWN;
                    // 0x10: vfmv.s.f (vm=1, vs2=0, src is scalar rs1)
                    6'h10: pkt.v_op_class = VOP_VFMV;
                    // 0x17: vfmerge (vm=0) vs vfmv.v.f (vm=1)
                    6'h17: pkt.v_op_class =
                               inst[25] ? VOP_VFMV : VOP_VFMERGE;
                    6'h18: pkt.v_op_class = VOP_VMFEQ;
                    6'h19: pkt.v_op_class = VOP_VMFLE;
                    6'h1b: pkt.v_op_class = VOP_VMFLT;
                    6'h1c: pkt.v_op_class = VOP_VMFNE;
                    6'h1d: pkt.v_op_class = VOP_VMFGT;
                    6'h1f: pkt.v_op_class = VOP_VMFGE;
                    6'h20: pkt.v_op_class = VOP_VFDIV;
                    6'h21: pkt.v_op_class = VOP_VFRDIV;
                    6'h24: pkt.v_op_class = VOP_VFMUL;
                    6'h27: pkt.v_op_class = VOP_VFRSUB;
                    6'h28: pkt.v_op_class = VOP_VFMADD;
                    6'h29: pkt.v_op_class = VOP_VFNMADD;
                    6'h2a: pkt.v_op_class = VOP_VFMSUB;
                    6'h2b: pkt.v_op_class = VOP_VFNMSUB;
                    6'h2c: pkt.v_op_class = VOP_VFMACC;
                    6'h2d: pkt.v_op_class = VOP_VFNMACC;
                    6'h2e: pkt.v_op_class = VOP_VFMSAC;
                    6'h2f: pkt.v_op_class = VOP_VFNMSAC;
                    6'h30: pkt.v_op_class = VOP_VFWADD;
                    6'h32: pkt.v_op_class = VOP_VFWSUB;
                    6'h34: pkt.v_op_class = VOP_VFWADD_W;
                    6'h36: pkt.v_op_class = VOP_VFWSUB_W;
                    6'h38: pkt.v_op_class = VOP_VFWMUL;
                    6'h3c: pkt.v_op_class = VOP_VFWMACC;
                    6'h3d: pkt.v_op_class = VOP_VFWNMACC;
                    6'h3e: pkt.v_op_class = VOP_VFWMSAC;
                    6'h3f: pkt.v_op_class = VOP_VFWNMSAC;
                    default: pkt.v_op_class = VOTHER;
                endcase
            end

            // ----------------------------------------------------------
            // OPMVV - integer/mask/reduce/permute vv (funct3=3'b010)
            // funct6 values from rv_v OPMVV section.
            // funct6=0x10: subfunct at inst[19:15]:
            //   0x00 -> vmv.x.s (VOP_VMV_XS, GPR dest rd)
            //   0x10 -> vcpop.m (VOP_VCPOP,  GPR dest rd)
            //   0x11 -> vfirst.m (VOP_VFIRST, GPR dest rd)
            //   Downstream dispatch must handle GPR destination for all.
            // funct6=0x12: vzext/vsext, subfunct at inst[19:15]:
            //   even -> vzext, odd -> vsext
            // funct6=0x14: vmsbf/vmsof/vmsif/viota/vid, subfunct at
            //   inst[19:15]
            // funct6=0x18-0x1f: mask logical group; vm=1 always.
            //   These operate on mask registers, not data registers.
            // funct6 values not listed below return VOTHER.
            // ----------------------------------------------------------
            3'b010: begin
                case (f6)
                    6'h00: pkt.v_op_class = VOP_VREDSUM;
                    6'h01: pkt.v_op_class = VOP_VREDAND;
                    6'h02: pkt.v_op_class = VOP_VREDOR;
                    6'h03: pkt.v_op_class = VOP_VREDXOR;
                    6'h04: pkt.v_op_class = VOP_VREDMINU;
                    6'h05: pkt.v_op_class = VOP_VREDMIN;
                    6'h06: pkt.v_op_class = VOP_VREDMAXU;
                    6'h07: pkt.v_op_class = VOP_VREDMAX;
                    6'h08: pkt.v_op_class = VOP_VAADDU;
                    6'h09: pkt.v_op_class = VOP_VAADD;
                    6'h0a: pkt.v_op_class = VOP_VASUBU;
                    6'h0b: pkt.v_op_class = VOP_VASUB;
                    // 0x10: vmv.x.s/vcpop.m/vfirst.m sub at inst[19:15]
                    6'h10: begin
                        case (inst[19:15])
                            5'h00: pkt.v_op_class = VOP_VMV_XS;
                            5'h10: pkt.v_op_class = VOP_VCPOP;
                            5'h11: pkt.v_op_class = VOP_VFIRST;
                            default: pkt.v_op_class = VOTHER;
                        endcase
                    end
                    // 0x12: vzext/vsext, even sub->vzext, odd sub->vsext
                    6'h12: begin
                        case (inst[19:15])
                            5'd2, 5'd4, 5'd6:
                                pkt.v_op_class = VOP_VZEXT;
                            5'd3, 5'd5, 5'd7:
                                pkt.v_op_class = VOP_VSEXT;
                            default: pkt.v_op_class = VOTHER;
                        endcase
                    end
                    // 0x14: vmsbf/vmsof/vmsif/viota/vid sub at inst[19:15]
                    6'h14: begin
                        case (inst[19:15])
                            5'h01: pkt.v_op_class = VOP_VMSBF;
                            5'h02: pkt.v_op_class = VOP_VMSOF;
                            5'h03: pkt.v_op_class = VOP_VMSIF;
                            5'h10: pkt.v_op_class = VOP_VIOTA;
                            5'h11: pkt.v_op_class = VOP_VID;
                            default: pkt.v_op_class = VOTHER;
                        endcase
                    end
                    6'h17: pkt.v_op_class = VOP_VCOMPRESS;
                    // mask logical: vm=1 always (mask register operands)
                    6'h18: pkt.v_op_class = VOP_VMANDN;
                    6'h19: pkt.v_op_class = VOP_VMAND;
                    6'h1a: pkt.v_op_class = VOP_VMOR;
                    6'h1b: pkt.v_op_class = VOP_VMXOR;
                    6'h1c: pkt.v_op_class = VOP_VMORN;
                    6'h1d: pkt.v_op_class = VOP_VMNAND;
                    6'h1e: pkt.v_op_class = VOP_VMNOR;
                    6'h1f: pkt.v_op_class = VOP_VMXNOR;
                    6'h20: pkt.v_op_class = VOP_VDIVU;
                    6'h21: pkt.v_op_class = VOP_VDIV;
                    6'h22: pkt.v_op_class = VOP_VREMU;
                    6'h23: pkt.v_op_class = VOP_VREM;
                    6'h24: pkt.v_op_class = VOP_VMULHU;
                    6'h25: pkt.v_op_class = VOP_VMUL;
                    6'h26: pkt.v_op_class = VOP_VMULHSU;
                    6'h27: pkt.v_op_class = VOP_VMULH;
                    6'h29: pkt.v_op_class = VOP_VMADD;
                    6'h2b: pkt.v_op_class = VOP_VNMSUB;
                    6'h2d: pkt.v_op_class = VOP_VMACC;
                    6'h2f: pkt.v_op_class = VOP_VNMSAC;
                    6'h30: pkt.v_op_class = VOP_VWADDU;
                    6'h31: pkt.v_op_class = VOP_VWADD;
                    6'h32: pkt.v_op_class = VOP_VWSUBU;
                    6'h33: pkt.v_op_class = VOP_VWSUB;
                    6'h34: pkt.v_op_class = VOP_VWADDU_W;
                    6'h35: pkt.v_op_class = VOP_VWADD_W;
                    6'h36: pkt.v_op_class = VOP_VWSUBU_W;
                    6'h37: pkt.v_op_class = VOP_VWSUB_W;
                    6'h38: pkt.v_op_class = VOP_VWMULU;
                    6'h3a: pkt.v_op_class = VOP_VWMULSU;
                    6'h3b: pkt.v_op_class = VOP_VWMUL;
                    6'h3c: pkt.v_op_class = VOP_VWMACCU;
                    6'h3d: pkt.v_op_class = VOP_VWMACC;
                    // 0x3e not in OPMVV (vwmaccus is OPMVX only)
                    6'h3f: pkt.v_op_class = VOP_VWMACCSU;
                    default: pkt.v_op_class = VOTHER;
                endcase
            end

            // ----------------------------------------------------------
            // OPMVX - integer/mask/multiply vx (funct3=3'b110)
            // funct6 values from rv_v OPMVX section.
            //
            // SCALAR SOURCE: inst[19:15] = GPR rs1, NOT vs1.
            // vs1 is forced to zero in this packet; downstream reads
            // the GPR from scalar decode_pkt_t.rs1 = inst[19:15].
            //
            // funct6=0x10: vmv.s.x; vd[0] <- GPR rs1; vs2 unused (0).
            //   Downstream dispatch: GPR source, vector destination.
            // funct6=0x0e/0x0f: vslide1up/down.vx; GPR rs1 is amount.
            // funct6=0x3e: vwmaccus.vx is OPMVX only (not OPMVV).
            // funct6 values not listed below return VOTHER.
            // ----------------------------------------------------------
            3'b110: begin
                // Zero vs1: no vector register vs1 for OPMVX.
                // GPR rs1 is in scalar decode_pkt_t.rs1.
                pkt.vs1 = 5'b0;
                case (f6)
                    6'h08: pkt.v_op_class = VOP_VAADDU;
                    6'h09: pkt.v_op_class = VOP_VAADD;
                    6'h0a: pkt.v_op_class = VOP_VASUBU;
                    6'h0b: pkt.v_op_class = VOP_VASUB;
                    // GPR rs1 is slide amount
                    6'h0e: pkt.v_op_class = VOP_VSLIDE1UP_X;
                    6'h0f: pkt.v_op_class = VOP_VSLIDE1DOWN_X;
                    // GPR rs1 -> vd[0]; vs2=0 (field unused)
                    6'h10: pkt.v_op_class = VOP_VMV_SX;
                    6'h20: pkt.v_op_class = VOP_VDIVU;
                    6'h21: pkt.v_op_class = VOP_VDIV;
                    6'h22: pkt.v_op_class = VOP_VREMU;
                    6'h23: pkt.v_op_class = VOP_VREM;
                    6'h24: pkt.v_op_class = VOP_VMULHU;
                    6'h25: pkt.v_op_class = VOP_VMUL;
                    6'h26: pkt.v_op_class = VOP_VMULHSU;
                    6'h27: pkt.v_op_class = VOP_VMULH;
                    6'h29: pkt.v_op_class = VOP_VMADD;
                    6'h2b: pkt.v_op_class = VOP_VNMSUB;
                    6'h2d: pkt.v_op_class = VOP_VMACC;
                    6'h2f: pkt.v_op_class = VOP_VNMSAC;
                    6'h30: pkt.v_op_class = VOP_VWADDU;
                    6'h31: pkt.v_op_class = VOP_VWADD;
                    6'h32: pkt.v_op_class = VOP_VWSUBU;
                    6'h33: pkt.v_op_class = VOP_VWSUB;
                    6'h34: pkt.v_op_class = VOP_VWADDU_W;
                    6'h35: pkt.v_op_class = VOP_VWADD_W;
                    6'h36: pkt.v_op_class = VOP_VWSUBU_W;
                    6'h37: pkt.v_op_class = VOP_VWSUB_W;
                    6'h38: pkt.v_op_class = VOP_VWMULU;
                    6'h3a: pkt.v_op_class = VOP_VWMULSU;
                    6'h3b: pkt.v_op_class = VOP_VWMUL;
                    6'h3c: pkt.v_op_class = VOP_VWMACCU;
                    6'h3d: pkt.v_op_class = VOP_VWMACC;
                    // vwmaccus.vx: OPMVX only, unsigned scalar source
                    6'h3e: pkt.v_op_class = VOP_VWMACCUS;
                    6'h3f: pkt.v_op_class = VOP_VWMACCSU;
                    default: pkt.v_op_class = VOTHER;
                endcase
            end

            // ----------------------------------------------------------
            // OPIVV - integer vector-vector (funct3=3'b000)
            // funct6 values from rv_v OPIVV section.
            // funct6=0x17 encodes vmerge (vm=0) and vmv.v.v (vm=1).
            // ----------------------------------------------------------
            3'b000: begin
                case (f6)
                    6'h00: pkt.v_op_class = VOP_VADD;
                    6'h02: pkt.v_op_class = VOP_VSUB;
                    6'h04: pkt.v_op_class = VOP_VMINU;
                    6'h05: pkt.v_op_class = VOP_VMIN;
                    6'h06: pkt.v_op_class = VOP_VMAXU;
                    6'h07: pkt.v_op_class = VOP_VMAX;
                    6'h09: pkt.v_op_class = VOP_VAND;
                    6'h0a: pkt.v_op_class = VOP_VOR;
                    6'h0b: pkt.v_op_class = VOP_VXOR;
                    6'h0c: pkt.v_op_class = VOP_VRGATHER;
                    // 0x0e in OPIVV is vrgatherei16, NOT vslideup
                    6'h0e: pkt.v_op_class = VOP_VRGATHEREI16;
                    6'h10: pkt.v_op_class = VOP_VADC;
                    // 0x11: vmadc.vvm (vm=0) and vmadc.vv (vm=1)
                    6'h11: pkt.v_op_class = VOP_VMADC;
                    6'h12: pkt.v_op_class = VOP_VSBC;
                    // 0x13: vmsbc.vvm (vm=0) and vmsbc.vv (vm=1)
                    6'h13: pkt.v_op_class = VOP_VMSBC;
                    // 0x17: vmerge (vm=0) vs vmv.v.v (vm=1)
                    6'h17: pkt.v_op_class =
                               inst[25] ? VOP_VMV : VOP_VMERGE;
                    6'h18: pkt.v_op_class = VOP_VMSEQ;
                    6'h19: pkt.v_op_class = VOP_VMSNE;
                    6'h1a: pkt.v_op_class = VOP_VMSLTU;
                    6'h1b: pkt.v_op_class = VOP_VMSLT;
                    6'h1c: pkt.v_op_class = VOP_VMSLEU;
                    6'h1d: pkt.v_op_class = VOP_VMSLE;
                    // 0x1e/0x1f (vmsgtu/vmsgt) not in OPIVV
                    6'h20: pkt.v_op_class = VOP_VSADDU;
                    6'h21: pkt.v_op_class = VOP_VSADD;
                    6'h22: pkt.v_op_class = VOP_VSSUBU;
                    6'h23: pkt.v_op_class = VOP_VSSUB;
                    6'h25: pkt.v_op_class = VOP_VSLL;
                    6'h27: pkt.v_op_class = VOP_VSMUL;
                    6'h28: pkt.v_op_class = VOP_VSRL;
                    6'h29: pkt.v_op_class = VOP_VSRA;
                    6'h2a: pkt.v_op_class = VOP_VSSRL;
                    6'h2b: pkt.v_op_class = VOP_VSSRA;
                    6'h2c: pkt.v_op_class = VOP_VNSRL;
                    6'h2d: pkt.v_op_class = VOP_VNSRA;
                    6'h2e: pkt.v_op_class = VOP_VNCLIPU;
                    6'h2f: pkt.v_op_class = VOP_VNCLIP;
                    6'h30: pkt.v_op_class = VOP_VWREDSUMU;
                    6'h31: pkt.v_op_class = VOP_VWREDSUM;
                    default: pkt.v_op_class = VOTHER;
                endcase
            end

            // ----------------------------------------------------------
            // OPIVX - integer vector-scalar (funct3=3'b100)
            // funct6 values from rv_v OPIVX section.
            // 0x0e in OPIVX is vslideup (not vrgatherei16).
            // ----------------------------------------------------------
            3'b100: begin
                case (f6)
                    6'h00: pkt.v_op_class = VOP_VADD;
                    6'h02: pkt.v_op_class = VOP_VSUB;
                    6'h03: pkt.v_op_class = VOP_VRSUB;
                    6'h04: pkt.v_op_class = VOP_VMINU;
                    6'h05: pkt.v_op_class = VOP_VMIN;
                    6'h06: pkt.v_op_class = VOP_VMAXU;
                    6'h07: pkt.v_op_class = VOP_VMAX;
                    6'h09: pkt.v_op_class = VOP_VAND;
                    6'h0a: pkt.v_op_class = VOP_VOR;
                    6'h0b: pkt.v_op_class = VOP_VXOR;
                    6'h0c: pkt.v_op_class = VOP_VRGATHER;
                    6'h0e: pkt.v_op_class = VOP_VSLIDEUP;
                    6'h0f: pkt.v_op_class = VOP_VSLIDEDOWN;
                    6'h10: pkt.v_op_class = VOP_VADC;
                    // 0x11: vmadc.vxm (vm=0) and vmadc.vx (vm=1)
                    6'h11: pkt.v_op_class = VOP_VMADC;
                    6'h12: pkt.v_op_class = VOP_VSBC;
                    // 0x13: vmsbc.vxm (vm=0) and vmsbc.vx (vm=1)
                    6'h13: pkt.v_op_class = VOP_VMSBC;
                    // 0x17: vmerge.vxm (vm=0) vs vmv.v.x (vm=1)
                    6'h17: pkt.v_op_class =
                               inst[25] ? VOP_VMV : VOP_VMERGE;
                    6'h18: pkt.v_op_class = VOP_VMSEQ;
                    6'h19: pkt.v_op_class = VOP_VMSNE;
                    6'h1a: pkt.v_op_class = VOP_VMSLTU;
                    6'h1b: pkt.v_op_class = VOP_VMSLT;
                    6'h1c: pkt.v_op_class = VOP_VMSLEU;
                    6'h1d: pkt.v_op_class = VOP_VMSLE;
                    6'h1e: pkt.v_op_class = VOP_VMSGTU;
                    6'h1f: pkt.v_op_class = VOP_VMSGT;
                    6'h20: pkt.v_op_class = VOP_VSADDU;
                    6'h21: pkt.v_op_class = VOP_VSADD;
                    6'h22: pkt.v_op_class = VOP_VSSUBU;
                    6'h23: pkt.v_op_class = VOP_VSSUB;
                    6'h25: pkt.v_op_class = VOP_VSLL;
                    6'h27: pkt.v_op_class = VOP_VSMUL;
                    6'h28: pkt.v_op_class = VOP_VSRL;
                    6'h29: pkt.v_op_class = VOP_VSRA;
                    6'h2a: pkt.v_op_class = VOP_VSSRL;
                    6'h2b: pkt.v_op_class = VOP_VSSRA;
                    6'h2c: pkt.v_op_class = VOP_VNSRL;
                    6'h2d: pkt.v_op_class = VOP_VNSRA;
                    6'h2e: pkt.v_op_class = VOP_VNCLIPU;
                    6'h2f: pkt.v_op_class = VOP_VNCLIP;
                    // 0x30/0x31 (vwredsumu/vwredsum) not in OPIVX
                    default: pkt.v_op_class = VOTHER;
                endcase
            end

            // ----------------------------------------------------------
            // OPIVI - integer vector-immediate (funct3=3'b011)
            // funct6 values from rv_v OPIVI section.
            // 0x27 in OPIVI encodes vmvNr.v (vm=1), not vsmul.
            // No vsub/vsbc/vmsbc/vmsltu/vmslt/vssubu/vssub in OPIVI.
            // ----------------------------------------------------------
            3'b011: begin
                case (f6)
                    6'h00: pkt.v_op_class = VOP_VADD;
                    6'h03: pkt.v_op_class = VOP_VRSUB;
                    6'h09: pkt.v_op_class = VOP_VAND;
                    6'h0a: pkt.v_op_class = VOP_VOR;
                    6'h0b: pkt.v_op_class = VOP_VXOR;
                    6'h0c: pkt.v_op_class = VOP_VRGATHER;
                    6'h0e: pkt.v_op_class = VOP_VSLIDEUP;
                    6'h0f: pkt.v_op_class = VOP_VSLIDEDOWN;
                    6'h10: pkt.v_op_class = VOP_VADC;
                    // 0x11: vmadc.vim (vm=0) and vmadc.vi (vm=1)
                    6'h11: pkt.v_op_class = VOP_VMADC;
                    // 0x17: vmerge.vim (vm=0) vs vmv.v.i (vm=1)
                    6'h17: pkt.v_op_class =
                               inst[25] ? VOP_VMV : VOP_VMERGE;
                    6'h18: pkt.v_op_class = VOP_VMSEQ;
                    6'h19: pkt.v_op_class = VOP_VMSNE;
                    // 0x1a/0x1b (vmsltu/vmslt) not in OPIVI
                    6'h1c: pkt.v_op_class = VOP_VMSLEU;
                    6'h1d: pkt.v_op_class = VOP_VMSLE;
                    6'h1e: pkt.v_op_class = VOP_VMSGTU;
                    6'h1f: pkt.v_op_class = VOP_VMSGT;
                    6'h20: pkt.v_op_class = VOP_VSADDU;
                    6'h21: pkt.v_op_class = VOP_VSADD;
                    // 0x22/0x23 (vssubu/vssub) not in OPIVI
                    6'h25: pkt.v_op_class = VOP_VSLL;
                    // 0x27 in OPIVI: vmvNr.v (vm=1, vs1 encodes N-1)
                    // N: 0->vmv1r, 1->vmv2r, 3->vmv4r, 7->vmv8r
                    6'h27: pkt.v_op_class = VOP_VMVNR;
                    6'h28: pkt.v_op_class = VOP_VSRL;
                    6'h29: pkt.v_op_class = VOP_VSRA;
                    6'h2a: pkt.v_op_class = VOP_VSSRL;
                    6'h2b: pkt.v_op_class = VOP_VSSRA;
                    6'h2c: pkt.v_op_class = VOP_VNSRL;
                    6'h2d: pkt.v_op_class = VOP_VNSRA;
                    6'h2e: pkt.v_op_class = VOP_VNCLIPU;
                    6'h2f: pkt.v_op_class = VOP_VNCLIP;
                    default: pkt.v_op_class = VOTHER;
                endcase
            end

            default: pkt.v_op_class = VOTHER;

        endcase
    end

    return pkt;
endfunction
/* verilator lint_on VARHIDDEN */
/* verilator lint_on UNUSEDSIGNAL */

// ---------------------------------------------------------------------------
// Single-slot decode function
// ---------------------------------------------------------------------------
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off VARHIDDEN */
function automatic decode_pkt_t decode_one(
    input logic [31:0]  inst,
    input logic         valid,
    input ext_enable_t  ext_enable
);
    decode_pkt_t pkt;
    logic [6:0] op;
    logic [2:0] f3;
    logic [6:0] f7;
    logic        w_is_16b; // 16-bit instruction (C extension encoding)
    logic        w_is_zcb; // Zcb-specific sub-encoding within C ext

    // Zero out to avoid latches
    pkt          = '0;
    pkt.valid    = valid;
    pkt.instr    = inst;

    if (!valid) return pkt;

    op  = inst[6:0];
    f3  = inst[14:12];
    f7  = inst[31:25];

    pkt.opcode  = op;
    pkt.rd      = inst[11:7];
    pkt.rs1     = inst[19:15];
    pkt.rs2     = inst[24:20];
    pkt.rs3     = inst[31:27]; // FMA only, others ignore
    pkt.funct3  = f3;
    pkt.funct7  = f7;

    // ------------------------------------------------------------------
    // C / Zcb extension gating
    // inst[1:0] != 2'b11 identifies a 16-bit instruction (pre-expansion
    // path; rvc_expander runs first in the pipeline but the testbench
    // may drive raw 16-bit encodings directly).
    //
    // Zcb Q0: bits[1:0]=00, bits[15:13]=100
    //   c.lbu, c.lhu, c.lh, c.sb, c.sh
    // Zcb Q1: bits[1:0]=01, bits[15:13]=100, bits[11:10]=11,
    //   bit[12]=1, bits[6:5] in {10,11}
    //   c.mul, c.zext.b/h/w, c.sext.b/h, c.not
    // ------------------------------------------------------------------
    w_is_16b = (inst[1:0] != 2'b11);
    w_is_zcb = ((inst[1:0] == 2'b00) && (inst[15:13] == 3'b100)) ||
               ((inst[1:0] == 2'b01) && (inst[15:13] == 3'b100) &&
                (inst[11:10] == 2'b11) && inst[12] &&
                ((inst[6:5] == 2'b10) || (inst[6:5] == 2'b11)));
    if (w_is_16b && !ext_enable.en_c) begin
        pkt.alu_op    = ALU_ILL;
        pkt.is_illegal = 1'b1;
        return pkt;
    end
    if (w_is_16b && !ext_enable.en_zcb && w_is_zcb) begin
        pkt.alu_op    = ALU_ILL;
        pkt.is_illegal = 1'b1;
        return pkt;
    end

    unique casez (op)

        // ------------------------------------------------------------------
        // LOAD  (I-type)
        // ------------------------------------------------------------------
        OP_LOAD: begin
            pkt.fmt      = FMT_I;
            pkt.imm      = imm_i(inst);
            pkt.is_load  = 1'b1;
            pkt.uses_rd  = 1'b1;
            pkt.uses_rs1 = 1'b1;
            unique casez (f3)
                3'b000: pkt.alu_op = ALU_LB;
                3'b001: pkt.alu_op = ALU_LH;
                3'b010: pkt.alu_op = ALU_LW;
                3'b011: pkt.alu_op = ALU_LD;
                3'b100: pkt.alu_op = ALU_LBU;
                3'b101: pkt.alu_op = ALU_LHU;
                3'b110: pkt.alu_op = ALU_LWU;
                default: begin
                    pkt.alu_op    = ALU_ILL;
                    pkt.is_illegal = 1'b1;
                end
            endcase
        end

        // ------------------------------------------------------------------
        // LOAD-FP  (I-type) - FLD/FLW scalar FP, or vector load
        // DECODE-008: width 3'b000/101/110/111 -> vector memory load
        // Width 3'b011 -> FLD (D ext); width 3'b010 -> FLW (F ext)
        // ------------------------------------------------------------------
        OP_LOAD_FP: begin
            if (f3 == 3'b000 || f3 == 3'b101 ||
                f3 == 3'b110 || f3 == 3'b111) begin
                // Vector memory load; vec_decode_bundle carries full detail
                // rs1=base GPR; rs2=stride GPR for strided mode (mop=2'b10)
                if (!ext_enable.en_v) begin
                    pkt.alu_op    = ALU_ILL;
                    pkt.is_illegal = 1'b1;
                end else begin
                    pkt.is_load  = 1'b1;
                    pkt.uses_rs1 = 1'b1;
                    pkt.uses_rs2 = (inst[27:26] == 2'b10);
                    pkt.alu_op   = ALU_ADD; // placeholder; LSU reads vec pkt
                end
            end else begin
                // Scalar FP load
                pkt.fmt      = FMT_I;
                pkt.imm      = imm_i(inst);
                pkt.is_load  = 1'b1;
                pkt.is_fp    = 1'b1;
                pkt.uses_rd  = 1'b1;
                pkt.uses_rs1 = 1'b1;
                if (f3 == 3'b011) begin // FLD (D extension)
                    if (!ext_enable.en_d) begin
                        pkt.alu_op    = ALU_ILL;
                        pkt.is_illegal = 1'b1;
                    end else
                        pkt.alu_op = ALU_FLD;
                end else if (f3 == 3'b010) begin // FLW (F extension)
                    if (!ext_enable.en_f) begin
                        pkt.alu_op    = ALU_ILL;
                        pkt.is_illegal = 1'b1;
                    end else
                        pkt.alu_op = ALU_FLD; // placeholder
                end else begin
                    pkt.alu_op     = ALU_ILL;
                    pkt.is_illegal = 1'b1;
                end
            end
        end

        // ------------------------------------------------------------------
        // MISC-MEM  (FENCE / FENCE.I / CBO)
        // funct3=010 selects CBO instructions; inst[24:20] selects op:
        //   0=cbo.inval  1=cbo.clean  2=cbo.flush  (Zicbom)
        //   4=cbo.zero                               (Zicboz)
        // ------------------------------------------------------------------
        OP_MISC_MEM: begin
            pkt.fmt = FMT_I;
            if (f3 == 3'b010) begin
                // CBO instructions: rs1=base address, no destination
                pkt.uses_rs1 = 1'b1;
                case (inst[24:20])
                    5'b00000: begin // cbo.inval
                        if (!ext_enable.en_zicbom) begin
                            pkt.alu_op    = ALU_ILL;
                            pkt.is_illegal = 1'b1;
                        end else
                            pkt.alu_op = ALU_FENCE;
                    end
                    5'b00001: begin // cbo.clean
                        if (!ext_enable.en_zicbom) begin
                            pkt.alu_op    = ALU_ILL;
                            pkt.is_illegal = 1'b1;
                        end else
                            pkt.alu_op = ALU_FENCE;
                    end
                    5'b00010: begin // cbo.flush
                        if (!ext_enable.en_zicbom) begin
                            pkt.alu_op    = ALU_ILL;
                            pkt.is_illegal = 1'b1;
                        end else
                            pkt.alu_op = ALU_FENCE;
                    end
                    5'b00100: begin // cbo.zero
                        if (!ext_enable.en_zicboz) begin
                            pkt.alu_op    = ALU_ILL;
                            pkt.is_illegal = 1'b1;
                        end else
                            pkt.alu_op = ALU_FENCE;
                    end
                    default: begin
                        pkt.alu_op    = ALU_ILL;
                        pkt.is_illegal = 1'b1;
                    end
                endcase
            end else begin
                // FENCE / FENCE.I: base ISA, never ILLEGAL
                pkt.alu_op = ALU_FENCE;
            end
        end

        // ------------------------------------------------------------------
        // OP-IMM  (I-type): ADDI, SLTI, SLTIU, XORI, ORI, ANDI,
        //                    SLLI, SRLI, SRAI
        // ------------------------------------------------------------------
        OP_IMM: begin
            pkt.fmt      = FMT_I;
            pkt.uses_rd  = 1'b1;
            pkt.uses_rs1 = 1'b1;
            unique casez (f3)
                3'b000: begin pkt.alu_op = ALU_ADD;  pkt.imm = imm_i(inst); end
                3'b001: begin
                    // SLLI - shamt in [25:20], funct7[6:1]=000000
                    pkt.alu_op = ALU_SLLI;
                    pkt.imm    = imm_shamt(inst);
                    if (f7[6:1] != 6'b000000) begin
                        pkt.alu_op    = ALU_ILL;
                        pkt.is_illegal = 1'b1;
                    end
                end
                3'b010: begin pkt.alu_op = ALU_SLT;  pkt.imm = imm_i(inst); end
                3'b011: begin pkt.alu_op = ALU_SLTU; pkt.imm = imm_i(inst); end
                3'b100: begin pkt.alu_op = ALU_XOR;  pkt.imm = imm_i(inst); end
                3'b101: begin
                    // SRLI / SRAI - distinguished by funct7[5]
                    pkt.imm = imm_shamt(inst);
                    if (f7[6:1] == 6'b000000)
                        pkt.alu_op = ALU_SRLI;
                    else if (f7[6:1] == 6'b010000)
                        pkt.alu_op = ALU_SRAI;
                    else begin
                        pkt.alu_op    = ALU_ILL;
                        pkt.is_illegal = 1'b1;
                    end
                end
                3'b110: begin
                    pkt.alu_op = ALU_OR;
                    pkt.imm    = imm_i(inst);
                    // prefetch.* hint: ORI with rd=0 is Zicbop
                    if (inst[11:7] == 5'b0 && !ext_enable.en_zicbop) begin
                        pkt.alu_op    = ALU_ILL;
                        pkt.is_illegal = 1'b1;
                    end
                end
                3'b111: begin pkt.alu_op = ALU_ANDI; pkt.imm = imm_i(inst); end
                default: begin
                    pkt.alu_op    = ALU_ILL;
                    pkt.is_illegal = 1'b1;
                end
            endcase
        end

        // ------------------------------------------------------------------
        // AUIPC  (U-type)
        // ------------------------------------------------------------------
        OP_AUIPC: begin
            pkt.fmt     = FMT_U;
            pkt.imm     = imm_u(inst);
            pkt.alu_op  = ALU_AUIPC;
            pkt.uses_rd = 1'b1;
        end

        // ------------------------------------------------------------------
        // OP-IMM-32  (I-type, RV64): ADDIW, SLLIW, SRLIW, SRAIW
        // ------------------------------------------------------------------
        OP_IMM_32: begin
            pkt.fmt      = FMT_I;
            pkt.uses_rd  = 1'b1;
            pkt.uses_rs1 = 1'b1;
            unique casez (f3)
                3'b000: begin pkt.alu_op = ALU_ADDW; pkt.imm = imm_i(inst); end
                3'b001: begin
                    pkt.alu_op = ALU_SLLW;
                    pkt.imm    = imm_shamt(inst);
                    if (f7 != 7'b0000000) begin
                        pkt.alu_op    = ALU_ILL;
                        pkt.is_illegal = 1'b1;
                    end
                end
                3'b101: begin
                    pkt.imm = imm_shamt(inst);
                    if (f7 == 7'b0000000)
                        pkt.alu_op = ALU_SRLW;
                    else if (f7 == 7'b0100000)
                        pkt.alu_op = ALU_SRAW;
                    else begin
                        pkt.alu_op    = ALU_ILL;
                        pkt.is_illegal = 1'b1;
                    end
                end
                default: begin
                    pkt.alu_op    = ALU_ILL;
                    pkt.is_illegal = 1'b1;
                end
            endcase
        end

        // ------------------------------------------------------------------
        // STORE  (S-type)
        // ------------------------------------------------------------------
        OP_STORE: begin
            pkt.fmt      = FMT_S;
            pkt.imm      = imm_s(inst);
            pkt.is_store = 1'b1;
            pkt.uses_rs1 = 1'b1;
            pkt.uses_rs2 = 1'b1;
            unique casez (f3)
                3'b000: pkt.alu_op = ALU_SB;
                3'b001: pkt.alu_op = ALU_SH;
                3'b010: pkt.alu_op = ALU_SW;
                3'b011: pkt.alu_op = ALU_SD;
                default: begin
                    pkt.alu_op    = ALU_ILL;
                    pkt.is_illegal = 1'b1;
                end
            endcase
        end

        // ------------------------------------------------------------------
        // STORE-FP  (S-type) - FSD/FSW scalar FP, or vector store
        // DECODE-008: width 3'b000/101/110/111 -> vector memory store
        // Width 3'b011 -> FSD (D ext); width 3'b010 -> FSW (F ext)
        // ------------------------------------------------------------------
        OP_STORE_FP: begin
            if (f3 == 3'b000 || f3 == 3'b101 ||
                f3 == 3'b110 || f3 == 3'b111) begin
                // Vector memory store; vec_decode_bundle carries full detail
                // rs1=base GPR; rs2=stride GPR for strided mode (mop=2'b10)
                if (!ext_enable.en_v) begin
                    pkt.alu_op    = ALU_ILL;
                    pkt.is_illegal = 1'b1;
                end else begin
                    pkt.is_store = 1'b1;
                    pkt.uses_rs1 = 1'b1;
                    pkt.uses_rs2 = (inst[27:26] == 2'b10);
                    pkt.alu_op   = ALU_ADD; // placeholder; LSU reads vec pkt
                end
            end else begin
                // Scalar FP store
                pkt.fmt      = FMT_S;
                pkt.imm      = imm_s(inst);
                pkt.is_store = 1'b1;
                pkt.is_fp    = 1'b1;
                pkt.uses_rs1 = 1'b1;
                pkt.uses_rs2 = 1'b1;
                if (f3 == 3'b011) begin // FSD (D extension)
                    if (!ext_enable.en_d) begin
                        pkt.alu_op    = ALU_ILL;
                        pkt.is_illegal = 1'b1;
                    end else
                        pkt.alu_op = ALU_FSD;
                end else if (f3 == 3'b010) begin // FSW (F extension)
                    if (!ext_enable.en_f) begin
                        pkt.alu_op    = ALU_ILL;
                        pkt.is_illegal = 1'b1;
                    end else
                        pkt.alu_op = ALU_FSD; // placeholder
                end else begin
                    pkt.alu_op     = ALU_ILL;
                    pkt.is_illegal = 1'b1;
                end
            end
        end

        // ------------------------------------------------------------------
        // OP  (R-type): ADD/SUB, SLL, SLT, SLTU, XOR, SRL/SRA, OR, AND,
        //               MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU,
        //               sh1add (Zba)
        // ------------------------------------------------------------------
        OP_REG: begin
            pkt.fmt      = FMT_R;
            pkt.uses_rd  = 1'b1;
            pkt.uses_rs1 = 1'b1;
            pkt.uses_rs2 = 1'b1;
            unique casez ({f7, f3})
                10'b0000000_000: pkt.alu_op = ALU_ADD;
                10'b0100000_000: pkt.alu_op = ALU_SUB;
                10'b0000000_001: pkt.alu_op = ALU_SLL;
                10'b0000000_010: pkt.alu_op = ALU_SLT;
                10'b0000000_011: pkt.alu_op = ALU_SLTU;
                10'b0000000_100: pkt.alu_op = ALU_XOR;
                10'b0000000_101: pkt.alu_op = ALU_SRL;
                10'b0100000_101: pkt.alu_op = ALU_SRA;
                10'b0000000_110: pkt.alu_op = ALU_OR;
                10'b0000000_111: pkt.alu_op = ALU_AND;
                // M extension (funct7=0000001)
                10'b0000001_000: pkt.alu_op = ALU_MUL;
                10'b0000001_001: pkt.alu_op = ALU_MULH;
                10'b0000001_010: pkt.alu_op = ALU_MULHSU;
                10'b0000001_011: pkt.alu_op = ALU_MULHU;
                10'b0000001_100: pkt.alu_op = ALU_DIV;
                10'b0000001_101: pkt.alu_op = ALU_DIVU;
                10'b0000001_110: pkt.alu_op = ALU_REM;
                10'b0000001_111: pkt.alu_op = ALU_REMU;
                // Zba: sh1add (funct7=0010000, funct3=010)
                10'b0010000_010: begin
                    if (!ext_enable.en_zba) begin
                        pkt.alu_op    = ALU_ILL;
                        pkt.is_illegal = 1'b1;
                    end else
                        pkt.alu_op = ALU_ADD; // placeholder
                end
                default: begin
                    pkt.alu_op    = ALU_ILL;
                    pkt.is_illegal = 1'b1;
                end
            endcase
            // M extension gating: funct7=0000001 covers all M-ext ops
            if (f7 == 7'b0000001 && !ext_enable.en_m) begin
                pkt.alu_op    = ALU_ILL;
                pkt.is_illegal = 1'b1;
            end
        end

        // ------------------------------------------------------------------
        // LUI  (U-type)
        // ------------------------------------------------------------------
        OP_LUI: begin
            pkt.fmt     = FMT_U;
            pkt.imm     = imm_u(inst);
            pkt.alu_op  = ALU_LUI;
            pkt.uses_rd = 1'b1;
        end

        // ------------------------------------------------------------------
        // OP-32  (R-type, RV64): ADDW/SUBW/SLLW/SRLW/SRAW + M-ext 32-bit
        // ------------------------------------------------------------------
        OP_REG_32: begin
            pkt.fmt      = FMT_R;
            pkt.uses_rd  = 1'b1;
            pkt.uses_rs1 = 1'b1;
            pkt.uses_rs2 = 1'b1;
            unique casez ({f7, f3})
                10'b0000000_000: pkt.alu_op = ALU_ADDW;
                10'b0100000_000: pkt.alu_op = ALU_SUBW;
                10'b0000000_001: pkt.alu_op = ALU_SLLW;
                10'b0000000_101: pkt.alu_op = ALU_SRLW;
                10'b0100000_101: pkt.alu_op = ALU_SRAW;
                10'b0000001_000: pkt.alu_op = ALU_MULW;
                10'b0000001_100: pkt.alu_op = ALU_DIVW;
                10'b0000001_101: pkt.alu_op = ALU_DIVUW;
                10'b0000001_110: pkt.alu_op = ALU_REMW;
                10'b0000001_111: pkt.alu_op = ALU_REMUW;
                default: begin
                    pkt.alu_op    = ALU_ILL;
                    pkt.is_illegal = 1'b1;
                end
            endcase
            // M extension gating: funct7=0000001 covers all 32-bit M ops
            if (f7 == 7'b0000001 && !ext_enable.en_m) begin
                pkt.alu_op    = ALU_ILL;
                pkt.is_illegal = 1'b1;
            end
        end

        // ------------------------------------------------------------------
        // FP fused multiply-add (R4-type): FMADD, FMSUB, FNMSUB, FNMADD
        // inst[26:25] fmt: 00=S (F extension), 01=D (D extension)
        // ------------------------------------------------------------------
        OP_MADD, OP_MSUB, OP_NMSUB, OP_NMADD: begin
            pkt.fmt      = FMT_R; // R4 is encoded similarly
            pkt.imm      = 32'b0;
            pkt.alu_op   = ALU_FMADD;
            pkt.is_fp    = 1'b1;
            pkt.uses_rd  = 1'b1;
            pkt.uses_rs1 = 1'b1;
            pkt.uses_rs2 = 1'b1;
            pkt.uses_rs3 = 1'b1;
            if (inst[26:25] > 2'b01) begin
                pkt.alu_op    = ALU_ILL;
                pkt.is_illegal = 1'b1;
            end else if (inst[26:25] == 2'b00 && !ext_enable.en_f) begin
                pkt.alu_op    = ALU_ILL;
                pkt.is_illegal = 1'b1;
            end else if (inst[26:25] == 2'b01 && !ext_enable.en_d) begin
                pkt.alu_op    = ALU_ILL;
                pkt.is_illegal = 1'b1;
            end
        end

        // ------------------------------------------------------------------
        // OP-FP  (R-type, FP ALU)
        // Decode only funct7 - full FP decode is a separate FP unit concern
        // Gate: ILLEGAL if neither F nor D extension is enabled
        // ------------------------------------------------------------------
        OP_FP: begin
            if (!ext_enable.en_f && !ext_enable.en_d) begin
                pkt.alu_op    = ALU_ILL;
                pkt.is_illegal = 1'b1;
            end else begin
                pkt.fmt   = FMT_R;
                pkt.is_fp = 1'b1;
                // Flag as FP; route to FP unit for full decode
                // uses_rs1/rs2/rd depend on specific op - mark conservatively
                pkt.uses_rd  = 1'b1;
                pkt.uses_rs1 = 1'b1;
                pkt.uses_rs2 = 1'b1;
                pkt.alu_op   = ALU_FLD; // placeholder; FP unit re-decodes
            end
        end

        // ------------------------------------------------------------------
        // BRANCH  (B-type)
        // ------------------------------------------------------------------
        OP_BRANCH: begin
            pkt.fmt       = FMT_B;
            pkt.imm       = imm_b(inst);
            pkt.is_branch = 1'b1;
            pkt.uses_rs1  = 1'b1;
            pkt.uses_rs2  = 1'b1;
            unique casez (f3)
                3'b000: pkt.alu_op = ALU_BEQ;
                3'b001: pkt.alu_op = ALU_BNE;
                3'b100: pkt.alu_op = ALU_BLT;
                3'b101: pkt.alu_op = ALU_BGE;
                3'b110: pkt.alu_op = ALU_BLTU;
                3'b111: pkt.alu_op = ALU_BGEU;
                default: begin
                    pkt.alu_op    = ALU_ILL;
                    pkt.is_illegal = 1'b1;
                end
            endcase
        end

        // ------------------------------------------------------------------
        // JALR  (I-type)
        // ------------------------------------------------------------------
        OP_JALR: begin
            pkt.fmt      = FMT_I;
            pkt.imm      = imm_i(inst);
            pkt.alu_op   = ALU_JALR;
            pkt.is_jump  = 1'b1;
            pkt.uses_rd  = 1'b1;
            pkt.uses_rs1 = 1'b1;
            if (f3 != 3'b000) begin
                pkt.alu_op    = ALU_ILL;
                pkt.is_illegal = 1'b1;
            end
        end

        // ------------------------------------------------------------------
        // JAL  (J-type)
        // ------------------------------------------------------------------
        OP_JAL: begin
            pkt.fmt     = FMT_J;
            pkt.imm     = imm_j(inst);
            pkt.alu_op  = ALU_JAL;
            pkt.is_jump = 1'b1;
            pkt.uses_rd = 1'b1;
        end

        // ------------------------------------------------------------------
        // SYSTEM  (I-type): ECALL, EBREAK, CSR*, MRET, SRET, WFI
        // ------------------------------------------------------------------
        OP_SYSTEM: begin
            pkt.fmt    = FMT_I;
            pkt.is_csr = 1'b1;
            // Include inst[24:20] in key to distinguish ECALL from EBREAK:
            // ECALL  0x00000073: inst[24:20]=00000, inst[19:15]=00000
            // EBREAK 0x00100073: inst[24:20]=00001, inst[19:15]=00000
            unique casez ({f7, inst[24:20], inst[19:15], f3})
                // ECALL
                20'b0000000_00000_00000_000: begin
                    pkt.alu_op = ALU_ECALL;
                end
                // EBREAK
                20'b0000000_00001_00000_000: begin
                    pkt.alu_op = ALU_EBREAK;
                end
                // MRET
                20'b0011000_00010_00000_000: begin
                    pkt.alu_op = ALU_MRET;
                end
                // SRET
                20'b0001000_00010_00000_000: begin
                    pkt.alu_op = ALU_SRET;
                end
                // WFI
                20'b0001000_00101_00000_000: begin
                    pkt.alu_op = ALU_WFI;
                end
                // HFENCE.VVMA (H extension): funct7=0100001, funct3=000
                20'b0100001_?????_?????_000: begin
                    if (!ext_enable.en_h) begin
                        pkt.alu_op    = ALU_ILL;
                        pkt.is_illegal = 1'b1;
                    end else
                        pkt.alu_op = ALU_FENCE; // placeholder
                end
                // CSR instructions (funct3 != 0) - Zicsr extension
                20'b???????_?????_?????_001,
                20'b???????_?????_?????_010,
                20'b???????_?????_?????_011,
                20'b???????_?????_?????_101,
                20'b???????_?????_?????_110,
                20'b???????_?????_?????_111: begin
                    if (!ext_enable.en_zicsr) begin
                        pkt.alu_op    = ALU_ILL;
                        pkt.is_illegal = 1'b1;
                    end else begin
                        pkt.alu_op   = ALU_CSR;
                        pkt.imm      = imm_i(inst); // CSR address in imm[11:0]
                        pkt.uses_rd  = 1'b1;
                        pkt.uses_rs1 = (f3[2] == 1'b0); // CSRRx uses rs1
                        // CSRRXI (funct3[2]=1) uses zimm, not rs1
                    end
                end
                default: begin
                    pkt.alu_op    = ALU_ILL;
                    pkt.is_illegal = 1'b1;
                end
            endcase
        end

        // ------------------------------------------------------------------
        // OP-V  (opcode 0x57) - RVV vector instructions
        // Scalar packet provides opcode and raw register fields only.
        // Full vector decode is in vec_decode_bundle via decode_vec_one().
        // alu_op is a placeholder; the vector unit ignores it and uses
        // vec_decode_bundle exclusively.
        // vsetvl/vsetvli/vsetivli write a scalar rd - uses_rd is set.
        // For vector arithmetic, uses_rd is set conservatively; rename
        // will see is_vector and route to the vector unit instead.
        // ------------------------------------------------------------------
        OP_VECTOR: begin
            if (!ext_enable.en_v) begin
                pkt.alu_op    = ALU_ILL;
                pkt.is_illegal = 1'b1;
            end else begin
                pkt.fmt      = FMT_R;
                pkt.uses_rd  = 1'b1;
                pkt.uses_rs1 = 1'b1;
                pkt.uses_rs2 = 1'b1;
                pkt.alu_op   = ALU_ADD; // placeholder; VU reads vec pkt
            end
        end

        // ------------------------------------------------------------------
        // AMO  (R-type) - A extension required by RVA23
        // Route to load-store unit; full AMO decode done there
        // ------------------------------------------------------------------
        OP_AMO: begin
            if (!ext_enable.en_a) begin
                pkt.alu_op    = ALU_ILL;
                pkt.is_illegal = 1'b1;
            end else begin
                pkt.fmt      = FMT_R;
                pkt.is_load  = 1'b1;  // consumes data from memory
                pkt.is_store = 1'b1;  // writes result to memory
                pkt.uses_rd  = 1'b1;
                pkt.uses_rs1 = 1'b1;
                pkt.uses_rs2 = 1'b1;
                pkt.alu_op   = ALU_ADD; // placeholder; AMO unit re-decodes f7
            end
        end

        // ------------------------------------------------------------------
        // Illegal / unknown opcode
        // ------------------------------------------------------------------
        default: begin
            pkt.alu_op    = ALU_ILL;
            pkt.fmt       = FMT_ILL;
            pkt.is_illegal = 1'b1;
        end
    endcase

    // Zero unused register fields so rename sees clean operands
    if (!pkt.uses_rd)  pkt.rd  = 5'h0;
    if (!pkt.uses_rs1) pkt.rs1 = 5'h0;
    if (!pkt.uses_rs2) pkt.rs2 = 5'h0;

    return pkt;
endfunction
/* verilator lint_on VARHIDDEN */
/* verilator lint_on UNUSEDSIGNAL */

// ---------------------------------------------------------------------------
// Parallel decode - one decode_one() and decode_vec_one() per slot
// All slots decode simultaneously with no inter-slot dependency.
// Instruction bits and validity are extracted from predecode_bundle.
// predecode_out is a direct pass-through for rename to read annotations.
// ---------------------------------------------------------------------------
genvar i;
generate
    for (i = 0; i < SLOTS; i++) begin : g_decode
        always_comb begin
            decode_bundle[i]     = decode_one(
                predecode_bundle[i].instr,
                predecode_bundle[i].valid,
                ext_enable);
            vec_decode_bundle[i] = decode_vec_one(
                predecode_bundle[i].instr,
                predecode_bundle[i].valid,
                ext_enable);
            is_vector[i]         = vec_decode_bundle[i].is_vector;
            predecode_out[i]     = predecode_bundle[i];
        end
    end
endgenerate

endmodule

`default_nettype wire
