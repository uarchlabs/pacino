// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// instr_decoder.sv
// 8-wide parallel instruction decoder for RVA23 / RV64GC.
//
// Receives an ifu_pd_pkt_t bundle (8 slots) from the ibuf read port
// (ibuf_decisions.md IBUF-9, IBUF-10). Decodes the expanded 32-bit
// instr of each slot. Produces one decode_pkt_t and one
// vec_decode_pkt_t per slot, plus vtype_hazard per slot.
//
// Decode boundary rules, dcd_decisions.md 10a (TD#143, BP-118):
//   DCD-17  vtype_hazard is computed here, per slot: an earlier valid
//           slot of this bundle is a vsetvl form and this slot needs
//           vtype. The two facts come from decode's own vector
//           classification (vec_decode_bundle), not from the
//           is_vsetvl / needs_vtype bits of ifu_pd_pkt_t: decode's
//           are exact and the IFU's needs_vtype over-marks the
//           whole-register forms (DCD-16). Those two input bits have
//           no reader here (TD#148).
//   DCD-18  pd_bundle is passed through to pd_out unchanged, beside
//           the decode packets. The PC, FTQ index, position, fault
//           fields and is_rvc reach rename this way.
//   DCD-19  a slot whose fault_cause is not IFU_FAULT_NONE is not
//           decoded. Its instr bits are meaningless and the fetch
//           fault outranks an illegal instruction exception, so its
//           decode packet is zero except valid and instr, is_illegal
//           is clear, and its vector packet is zero. The fault itself
//           travels in pd_out.
//   DCD-20  C and Zcb are always enabled. The IFU expands every
//           compressed instruction before the ibuf (IFU-1), so decode
//           sees only 32-bit encodings and cannot tell which
//           compressed extension one came from. The per-extension
//           compressed gating that lived in decode_one is deleted,
//           and ext_enable has no C or Zcb enable (BP-120, TD#155).
//
// BP-123 (Problem 5). Zba, Zbb and Zbs are decoded in full, each to its
// own operation and gated by en_zba, en_zbb and en_zbs; four Zcb
// instructions expand to Zbb and Zba forms (c.sext.b, c.sext.h, c.zext.h
// -> sext.b, sext.h, zext.h; c.zext.w -> add.uw). Zicond czero.eqz /
// czero.nez are decoded (mandatory in RVA23U64, no enable). ORI with
// rd = x0 is legal whatever en_zicbop says: it is the encoding of the
// Zicbop prefetches and, without Zicbop, an ORI HINT.
//
// BP-124, dcd_decisions.md section 10b (DCD-21 to DCD-35). decode hands
// rename a complete representation:
//   - alu_op names every scalar operation exactly (DCD-21, DCD-22): the
//     FP operations, Zfa, LR/SC and the AMOs, FENCE.I, the CBOs, the
//     SYSTEM fences, Svinval, HFENCE/HINVAL, WRS.NTO/STO and the six CSR
//     operations each have their own value. Every vector instruction is
//     ALU_VEC and v_op_class names it. HLV, HLVX and HSV keep the
//     width-exact load and store operations with is_hlsv, and is_hlvx
//     for HLVX (DCD-30)
//   - fp_fmt and fp_src_fmt give the precision (DCD-23); rd_is_fp,
//     rs1_is_fp and rs2_is_fp the register files, and uses_rd .. rs3 are
//     exact per operation (DCD-24); for a vector instruction they
//     describe its scalar operands only
//   - imm carries the immediates that sit in register fields (DCD-25)
//   - legality (DCD-26 to DCD-32): F, D, Zfhmin and Zfa's .S/.D forms
//     by their enables, every other .H form, Zfa's .H forms, FMVH.X.D,
//     FMVP.D.X and every Q form illegal; a static rm of 101 or 110
//     illegal; FCVTMOD.W.D only with rm 001; the AMOs of A only (W and
//     D, LR with rs2 x0); MISC-MEM funct3 000 is FENCE whatever its
//     fields, 001 FENCE.I, 010 the four CBOs with rd x0, the rest
//     illegal; the SYSTEM forms with rd (and rs1) x0 as DCD-31 lists;
//     a vector encoding that decodes to VOTHER or to the VMEM default,
//     or a store with lumop 10000, is illegal
//   - Zvbb is decoded, gated by en_v (DCD-33)
// An illegal instruction is ALU_ILL with no register, no immediate and
// no is_* flag, and its vector packet is zero.
//
// Downstream interface note:
//   - decode_bundle[8] connects directly to rename/dispatch stage
//   - vec_decode_bundle[8] carries vector decode alongside decode_bundle
//   - pd_out[8] carries the fetch-side packet to rename
//   - vtype_hazard[8] flags the intra-bundle vtype dependency; the
//     policy is rename's (CLAUDE.md)
//   - Slots with valid=0 carry zeroed decode packets; rename should skip
//   - is_illegal=1 slots should cause a precise exception in dispatch
// ===================================================================

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;
import decode_pkg::*;

/* verilator lint_off UNUSEDPARAM */
module instr_decoder (
    // --- extension enable/disable control ---
    input  ext_enable_t                 ext_enable,

    // --- bundle from the ibuf read port, 8 slots from the head ---
    // Unpacked [0:SLOTS-1], the shape of the ibuf read port, so the
    // front-end top wires it with no conversion.
    input  ifu_pd_pkt_t                 pd_bundle [0:SLOTS-1],

    // --- scalar decoded output bundle to rename/dispatch ---
    output decode_pkt_t     [SLOTS-1:0] decode_bundle,

    // --- vector decoded output bundle (parallel to decode_bundle) ---
    // Populated for OP_VECTOR (0x57) slots; zero for all others.
    // Rename/dispatch uses is_vector to steer to the vector unit.
    output vec_decode_pkt_t [SLOTS-1:0] vec_decode_bundle,
    output logic            [SLOTS-1:0] is_vector,

    // --- fetch-side packet pass-through to rename (DCD-18) ---
    output ifu_pd_pkt_t                 pd_out [0:SLOTS-1],

    // --- intra-bundle vtype dependency per slot (DCD-17) ---
    output logic            [SLOTS-1:0] vtype_hazard
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
// Returns a vec_decode_pkt_t for one instruction slot: OP_VECTOR (0x57)
// and the vector forms of LOAD-FP / STORE-FP (0x07 / 0x27, DECODE-008)
// produce a packet; every other word a zero one.
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

    // Whole-register load / store: unit-stride with lumop / sumop 01000.
    // nf encodes the register count less one (vl1r..vl8r, vs1r..vs8r),
    // so this is decided BEFORE the segment test below. BP-124: with nf
    // not 0 these were classed as segment operations (vl2re8.v decoded
    // as vlseg2e8.v), found by the oracle sweep. They transfer whole
    // registers whatever vtype holds: no vtype dependency.
    if ((mop == 2'b00) && (inst[24:20] == 5'b01000)) begin
        pkt.v_op_class  = is_store ? VOP_VSWHOLE : VOP_VLWHOLE;
        pkt.needs_vtype = 1'b0;
        return pkt;
    end

    // A unit-stride store with sumop 10000 is reserved (there is no
    // fault-only-first store): the VMEM default, illegal (DCD-32),
    // segment or not.
    if (is_store && (mop == 2'b00) && (inst[24:20] == 5'b10000)) begin
        pkt.v_op_class = VMEM;
        return pkt;
    end

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
                // 5'b01000 whole-register and a store's 5'b10000 are
                // decided above
                5'b10000: // vle*ff fault-only-first (load only)
                    pkt.v_op_class = VOP_VLFF;
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
                    // 0x12: vzext/vsext, even sub->vzext, odd sub->vsext;
                    // Zvbb's unary forms at 0x08 to 0x0e (BP-124)
                    6'h12: begin
                        case (inst[19:15])
                            5'd2, 5'd4, 5'd6:
                                pkt.v_op_class = VOP_VZEXT;
                            5'd3, 5'd5, 5'd7:
                                pkt.v_op_class = VOP_VSEXT;
                            5'h08: pkt.v_op_class = VOP_VBREV8;
                            5'h09: pkt.v_op_class = VOP_VREV8;
                            5'h0a: pkt.v_op_class = VOP_VBREV;
                            5'h0c: pkt.v_op_class = VOP_VCLZ;
                            5'h0d: pkt.v_op_class = VOP_VCTZ;
                            5'h0e: pkt.v_op_class = VOP_VCPOP_V;
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
                    6'h01: pkt.v_op_class = VOP_VANDN;       // Zvbb
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
                    6'h14: pkt.v_op_class = VOP_VROR;        // Zvbb
                    6'h15: pkt.v_op_class = VOP_VROL;        // Zvbb
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
                    6'h35: pkt.v_op_class = VOP_VWSLL;       // Zvbb
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
                    6'h01: pkt.v_op_class = VOP_VANDN;       // Zvbb
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
                    6'h14: pkt.v_op_class = VOP_VROR;        // Zvbb
                    6'h15: pkt.v_op_class = VOP_VROL;        // Zvbb
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
                    6'h35: pkt.v_op_class = VOP_VWSLL;       // Zvbb
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
                    // Zvbb vror.vi: funct6 0x14 and 0x15, bit 26 is
                    // the immediate's bit 5
                    6'h14, 6'h15: pkt.v_op_class = VOP_VROR;
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
                    6'h35: pkt.v_op_class = VOP_VWSLL;       // Zvbb
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
// Scalar decode helpers (BP-124, dcd_decisions.md 10b)
// ---------------------------------------------------------------------------

// The precision encodings of fmt (instruction bits 26:25) and of
// fp_fmt / fp_src_fmt (DCD-23): 2'b00 S, 2'b01 D, 2'b10 H, 2'b11 Q in
// the instruction and unused in the packet.
localparam logic [1:0] FP_S = 2'b00;
localparam logic [1:0] FP_D = 2'b01;
localparam logic [1:0] FP_H = 2'b10;

// A static rounding mode of 101 or 110 is reserved (DCD-27). 111 is
// dynamic; an invalid frm is raised at execute, not here.
function automatic logic rm_bad(input logic [2:0] rm);
    return (rm == 3'b101) || (rm == 3'b110);
endfunction

// An F or D operation of the base extensions at precision fmt: S needs
// en_f, D needs en_d. H is Zfh's, which is not implemented, and Q is
// not implemented (DCD-26).
/* verilator lint_off VARHIDDEN */
function automatic logic fp_base_ok(input logic [1:0]  fmt,
                                    input ext_enable_t ext_enable);
    return ((fmt == FP_S) && ext_enable.en_f) ||
           ((fmt == FP_D) && ext_enable.en_d);
endfunction

// A Zfa operation at precision fmt: .S needs en_zfa, .D also en_d; the
// .H forms need Zfh and are illegal (DCD-26).
function automatic logic fp_zfa_ok(input logic [1:0]  fmt,
                                   input ext_enable_t ext_enable);
    return ((fmt == FP_S) && ext_enable.en_zfa) ||
           ((fmt == FP_D) && ext_enable.en_zfa && ext_enable.en_d);
endfunction

// ---------------------------------------------------------------------------
// The four FMA opcodes (R4-type). DCD-22, DCD-23, DCD-26, DCD-27.
// ---------------------------------------------------------------------------
/* verilator lint_off UNUSEDSIGNAL */
function automatic decode_pkt_t dec_fma(input decode_pkt_t p,
                                        input logic [31:0]  inst,
                                        input ext_enable_t  ext_enable);
    decode_pkt_t pkt;
    pkt          = p;
    pkt.fmt      = FMT_R;               // R4 is encoded similarly
    pkt.is_fp    = 1'b1;
    pkt.uses_rd  = 1'b1;
    pkt.uses_rs1 = 1'b1;
    pkt.uses_rs2 = 1'b1;
    pkt.uses_rs3 = 1'b1;
    pkt.rd_is_fp  = 1'b1;
    pkt.rs1_is_fp = 1'b1;
    pkt.rs2_is_fp = 1'b1;
    pkt.fp_fmt   = inst[26:25];
    case (inst[6:0])
        OP_MADD:  pkt.alu_op = ALU_FMADD;
        OP_MSUB:  pkt.alu_op = ALU_FMSUB;
        OP_NMSUB: pkt.alu_op = ALU_FNMSUB;
        default:  pkt.alu_op = ALU_FNMADD;
    endcase
    if (!fp_base_ok(inst[26:25], ext_enable) || rm_bad(inst[14:12]))
        pkt.is_illegal = 1'b1;
    return pkt;
endfunction

// ---------------------------------------------------------------------------
// OP-FP. DCD-22 to DCD-27. funct5 [31:27], fmt [26:25], rs2 [24:20]
// (a selector for the unary forms), rm / funct3 [14:12].
// ---------------------------------------------------------------------------
function automatic decode_pkt_t dec_opfp(input decode_pkt_t p,
                                         input logic [31:0]  inst,
                                         input ext_enable_t  ext_enable);
    decode_pkt_t pkt;
    logic [4:0]  f5;
    logic [1:0]  fmt;
    logic [4:0]  sel;       // the rs2 field
    logic [2:0]  f3;
    logic        ok;        // legal encoding and enabled
    logic        has_rm;    // the encoding has an rm field (DCD-27)
    pkt  = p;
    f5   = inst[31:27];
    fmt  = inst[26:25];
    sel  = inst[24:20];
    f3   = inst[14:12];
    ok   = 1'b0;
    has_rm = 1'b0;
    pkt.fmt    = FMT_R;
    pkt.is_fp  = 1'b1;
    pkt.fp_fmt = fmt;
    // Most forms: FP destination and FP sources rs1, rs2.
    pkt.uses_rd   = 1'b1;
    pkt.uses_rs1  = 1'b1;
    pkt.rd_is_fp  = 1'b1;
    pkt.rs1_is_fp = 1'b1;
    unique case (f5)
        5'b00000, 5'b00001, 5'b00010, 5'b00011: begin
            case (f5[1:0])
                2'b00:   pkt.alu_op = ALU_FADD;
                2'b01:   pkt.alu_op = ALU_FSUB;
                2'b10:   pkt.alu_op = ALU_FMUL;
                default: pkt.alu_op = ALU_FDIV;
            endcase
            pkt.uses_rs2  = 1'b1;
            pkt.rs2_is_fp = 1'b1;
            has_rm = 1'b1;
            ok = fp_base_ok(fmt, ext_enable);
        end
        5'b01011: begin                          // FSQRT, unary
            pkt.alu_op = ALU_FSQRT;
            has_rm = 1'b1;
            ok = fp_base_ok(fmt, ext_enable) && (sel == 5'd0);
        end
        5'b00100: begin                          // FSGNJ, FSGNJN, FSGNJX
            pkt.uses_rs2  = 1'b1;
            pkt.rs2_is_fp = 1'b1;
            case (f3)
                3'b000:  pkt.alu_op = ALU_FSGNJ;
                3'b001:  pkt.alu_op = ALU_FSGNJN;
                default: pkt.alu_op = ALU_FSGNJX;
            endcase
            ok = fp_base_ok(fmt, ext_enable) && (f3 <= 3'b010);
        end
        5'b00101: begin                          // FMIN, FMAX; Zfa M forms
            pkt.uses_rs2  = 1'b1;
            pkt.rs2_is_fp = 1'b1;
            case (f3)
                3'b000:  pkt.alu_op = ALU_FMIN;
                3'b001:  pkt.alu_op = ALU_FMAX;
                3'b010:  pkt.alu_op = ALU_FMINM;
                default: pkt.alu_op = ALU_FMAXM;
            endcase
            ok = (f3 <= 3'b001) ? fp_base_ok(fmt, ext_enable) :
                 (f3 <= 3'b011) ? fp_zfa_ok(fmt, ext_enable)  : 1'b0;
        end
        5'b01000: begin                          // FCVT.fmt.fmt, FROUND*
            has_rm = 1'b1;
            if (sel == 5'b00100 || sel == 5'b00101) begin
                pkt.alu_op = (sel[0]) ? ALU_FROUNDNX : ALU_FROUND;
                ok = fp_zfa_ok(fmt, ext_enable);
            end else begin
                // fmt is the destination, rs2[1:0] the source (DCD-23).
                // The pairs F, D and Zfhmin define; Q and same-precision
                // conversions are not defined (DCD-26).
                pkt.alu_op     = ALU_FCVT_FF;
                pkt.fp_src_fmt = sel[1:0];
                unique case ({fmt, sel})
                    {FP_S, 5'd1}, {FP_D, 5'd0}:          // S<->D
                        ok = ext_enable.en_d;
                    {FP_S, 5'd2}, {FP_H, 5'd0}:          // S<->H
                        ok = ext_enable.en_zfhmin;
                    {FP_D, 5'd2}, {FP_H, 5'd1}:          // D<->H
                        ok = ext_enable.en_zfhmin && ext_enable.en_d;
                    default: ok = 1'b0;
                endcase
            end
        end
        5'b10100: begin                          // compares; Zfa quiet
            pkt.uses_rs2  = 1'b1;
            pkt.rs2_is_fp = 1'b1;
            pkt.rd_is_fp  = 1'b0;
            case (f3)
                3'b000:  pkt.alu_op = ALU_FLE;
                3'b001:  pkt.alu_op = ALU_FLT;
                3'b010:  pkt.alu_op = ALU_FEQ;
                3'b100:  pkt.alu_op = ALU_FLEQ;
                default: pkt.alu_op = ALU_FLTQ;
            endcase
            ok = (f3 <= 3'b010) ? fp_base_ok(fmt, ext_enable) :
                 (f3 == 3'b100 || f3 == 3'b101) ?
                     fp_zfa_ok(fmt, ext_enable) : 1'b0;
        end
        5'b11000: begin                          // FP -> integer
            pkt.rd_is_fp = 1'b0;
            if (sel == 5'b01000) begin
                // FCVTMOD.W.D: D only, rm 001 (RTZ); zfa.adoc reserves
                // every other rm (DCD-26).
                pkt.alu_op = ALU_FCVTMOD_W_D;
                ok = (fmt == FP_D) && ext_enable.en_zfa && ext_enable.en_d &&
                     (f3 == 3'b001);
            end else begin
                has_rm = 1'b1;
                case (sel[1:0])
                    2'b00:   pkt.alu_op = ALU_FCVT_W;
                    2'b01:   pkt.alu_op = ALU_FCVT_WU;
                    2'b10:   pkt.alu_op = ALU_FCVT_L;
                    default: pkt.alu_op = ALU_FCVT_LU;
                endcase
                ok = fp_base_ok(fmt, ext_enable) && (sel[4:2] == 3'b000);
            end
        end
        5'b11010: begin                          // integer -> FP
            pkt.rs1_is_fp = 1'b0;
            has_rm = 1'b1;
            case (sel[1:0])
                2'b00:   pkt.alu_op = ALU_FCVT_FW;
                2'b01:   pkt.alu_op = ALU_FCVT_FWU;
                2'b10:   pkt.alu_op = ALU_FCVT_FL;
                default: pkt.alu_op = ALU_FCVT_FLU;
            endcase
            ok = fp_base_ok(fmt, ext_enable) && (sel[4:2] == 3'b000);
        end
        5'b11100: begin                          // FMV.X.fmt, FCLASS
            pkt.rd_is_fp = 1'b0;
            if (f3 == 3'b000) begin
                // FMV.X.W, FMV.X.D, and FMV.X.H (Zfhmin). FMVH.X.D
                // (rs2 1) is RV32 only (DCD-26).
                pkt.alu_op = ALU_FMV_XF;
                ok = (sel == 5'd0) &&
                     (fp_base_ok(fmt, ext_enable) ||
                      ((fmt == FP_H) && ext_enable.en_zfhmin));
            end else begin
                pkt.alu_op = ALU_FCLASS;
                ok = (f3 == 3'b001) && (sel == 5'd0) &&
                     fp_base_ok(fmt, ext_enable);
            end
        end
        5'b11110: begin                          // FMV.fmt.X, FLI
            if (sel == 5'd1) begin
                // FLI: the constant index is the rs1 field; no source
                // register (DCD-24, DCD-25).
                pkt.alu_op    = ALU_FLI;
                pkt.uses_rs1  = 1'b0;
                pkt.rs1_is_fp = 1'b0;
                pkt.imm       = {27'd0, inst[19:15]};
                ok = (f3 == 3'b000) && fp_zfa_ok(fmt, ext_enable);
            end else begin
                pkt.alu_op    = ALU_FMV_FX;
                pkt.rs1_is_fp = 1'b0;
                ok = (f3 == 3'b000) && (sel == 5'd0) &&
                     (fp_base_ok(fmt, ext_enable) ||
                      ((fmt == FP_H) && ext_enable.en_zfhmin));
            end
        end
        default: ok = 1'b0;                      // FMVP.D.X (RV32) and
                                                 // every other funct5
    endcase
    if (!ok || (has_rm && rm_bad(f3)))
        pkt.is_illegal = 1'b1;
    return pkt;
endfunction

// ---------------------------------------------------------------------------
// AMO. DCD-28: W and D, the eleven A operations; LR needs rs2 = x0.
// Zabha's widths and Zacas's AMOCAS are illegal. aq and rl travel in
// funct7. LR reads memory, SC writes it, an AMO does both.
// ---------------------------------------------------------------------------
function automatic decode_pkt_t dec_amo(input decode_pkt_t p,
                                       input logic [31:0]  inst,
                                       input ext_enable_t  ext_enable);
    decode_pkt_t pkt;
    logic        d;
    logic        ok;
    pkt = p;
    pkt.fmt      = FMT_R;
    pkt.uses_rd  = 1'b1;
    pkt.uses_rs1 = 1'b1;
    pkt.uses_rs2 = 1'b1;
    pkt.is_load  = 1'b1;
    pkt.is_store = 1'b1;
    d  = inst[12];
    ok = ext_enable.en_a &&
         ((inst[14:12] == 3'b010) || (inst[14:12] == 3'b011));
    unique case (inst[31:27])
        5'b00010: begin
            pkt.alu_op   = d ? ALU_LR_D : ALU_LR_W;
            pkt.uses_rs2 = 1'b0;
            pkt.is_store = 1'b0;
            ok = ok && (inst[24:20] == 5'd0);
        end
        5'b00011: begin
            pkt.alu_op  = d ? ALU_SC_D : ALU_SC_W;
            pkt.is_load = 1'b0;
        end
        5'b00001: pkt.alu_op = d ? ALU_AMOSWAP_D : ALU_AMOSWAP_W;
        5'b00000: pkt.alu_op = d ? ALU_AMOADD_D  : ALU_AMOADD_W;
        5'b00100: pkt.alu_op = d ? ALU_AMOXOR_D  : ALU_AMOXOR_W;
        5'b01100: pkt.alu_op = d ? ALU_AMOAND_D  : ALU_AMOAND_W;
        5'b01000: pkt.alu_op = d ? ALU_AMOOR_D   : ALU_AMOOR_W;
        5'b10000: pkt.alu_op = d ? ALU_AMOMIN_D  : ALU_AMOMIN_W;
        5'b10100: pkt.alu_op = d ? ALU_AMOMAX_D  : ALU_AMOMAX_W;
        5'b11000: pkt.alu_op = d ? ALU_AMOMINU_D : ALU_AMOMINU_W;
        5'b11100: pkt.alu_op = d ? ALU_AMOMAXU_D : ALU_AMOMAXU_W;
        default:  ok = 1'b0;
    endcase
    if (!ok) pkt.is_illegal = 1'b1;
    return pkt;
endfunction

// ---------------------------------------------------------------------------
// MISC-MEM. DCD-29: funct3 000 is FENCE for every fm, pred, succ, rs1
// and rd (a reserved configuration is treated as FENCE, RV32I); fm,
// pred and succ travel in imm[11:0], zero-extended. 001 is FENCE.I,
// its imm, rs1 and rd ignored (Zifencei). 010 is the CBO of imm (0
// inval, 1 clean, 2 flush, 4 zero) with rd = x0 (DCD-31); 011 to 111
// are illegal.
// ---------------------------------------------------------------------------
function automatic decode_pkt_t dec_misc_mem(input decode_pkt_t p,
                                             input logic [31:0]  inst,
                                             input ext_enable_t  ext_enable);
    decode_pkt_t pkt;
    logic        ok;
    pkt = p;
    pkt.fmt = FMT_I;
    ok  = 1'b1;
    unique case (inst[14:12])
        3'b000: begin
            // fm, pred and succ are fields, not a number: zero-extended,
            // as DCD-25 places a CSR address (BP-124).
            pkt.alu_op = ALU_FENCE;
            pkt.imm    = {20'd0, inst[31:20]};
        end
        3'b001: pkt.alu_op = ALU_FENCE_I;
        3'b010: begin
            pkt.uses_rs1 = 1'b1;
            unique case (inst[31:20])
                12'd0: begin
                    pkt.alu_op = ALU_CBO_INVAL;
                    ok = ext_enable.en_zicbom;
                end
                12'd1: begin
                    pkt.alu_op = ALU_CBO_CLEAN;
                    ok = ext_enable.en_zicbom;
                end
                12'd2: begin
                    pkt.alu_op = ALU_CBO_FLUSH;
                    ok = ext_enable.en_zicbom;
                end
                12'd4: begin
                    pkt.alu_op = ALU_CBO_ZERO;
                    ok = ext_enable.en_zicboz;
                end
                default: ok = 1'b0;
            endcase
            if (inst[11:7] != 5'd0) ok = 1'b0;   // DCD-31
        end
        default: ok = 1'b0;
    endcase
    if (!ok) pkt.is_illegal = 1'b1;
    return pkt;
endfunction

// ---------------------------------------------------------------------------
// SYSTEM. DCD-29 to DCD-31.
//   funct3 000  ECALL, EBREAK, SRET, MRET, WFI, WRS.NTO, WRS.STO (rd and
//               rs1 x0); SFENCE.VMA, SINVAL.VMA, and with en_h
//               HFENCE.VVMA, HFENCE.GVMA, HINVAL.VVMA, HINVAL.GVMA (rd
//               x0); SFENCE.W.INVAL, SFENCE.INVAL.IR (rd and rs1 x0)
//   funct3 100  HLV, HLVX, HSV (en_h): the width-exact load and store
//               operations with is_hlsv, and is_hlvx for HLVX (DCD-30);
//               Zimop MOP.R.n and MOP.RR.n
//   otherwise   the six CSR operations (en_zicsr); the CSR address in
//               imm[11:0] zero-extended, the CSRRxI zimm in imm[16:12]
//               (DCD-25)
// Every other encoding is illegal.
// ---------------------------------------------------------------------------
function automatic decode_pkt_t dec_system(input decode_pkt_t p,
                                           input logic [31:0]  inst,
                                           input ext_enable_t  ext_enable);
    decode_pkt_t pkt;
    logic        ok;
    logic        rd0;
    logic        rs10;
    logic [6:0]  f7;
    logic [4:0]  r2;
    pkt  = p;
    pkt.fmt = FMT_I;
    ok   = 1'b1;
    rd0  = (inst[11:7]  == 5'd0);
    rs10 = (inst[19:15] == 5'd0);
    f7   = inst[31:25];
    r2   = inst[24:20];
    if (inst[14:12] == 3'b000) begin
        unique casez ({f7, r2})
            12'h000: begin pkt.alu_op = ALU_ECALL;  pkt.is_csr = 1'b1; end
            12'h001: begin pkt.alu_op = ALU_EBREAK; pkt.is_csr = 1'b1; end
            12'h102: begin pkt.alu_op = ALU_SRET;   pkt.is_csr = 1'b1; end
            12'h302: begin pkt.alu_op = ALU_MRET;   pkt.is_csr = 1'b1; end
            12'h105: begin pkt.alu_op = ALU_WFI;    pkt.is_csr = 1'b1; end
            12'h00D: pkt.alu_op = ALU_WRS_NTO;
            12'h01D: pkt.alu_op = ALU_WRS_STO;
            12'b0001001_?????, 12'b0001011_?????,
            12'b0010001_?????, 12'b0110001_?????,
            12'b0010011_?????, 12'b0110011_?????: begin
                pkt.uses_rs1 = 1'b1;
                pkt.uses_rs2 = 1'b1;
                unique case (f7)
                    7'b0001001: pkt.alu_op = ALU_SFENCE_VMA;
                    7'b0001011: pkt.alu_op = ALU_SINVAL_VMA;
                    7'b0010001: pkt.alu_op = ALU_HFENCE_VVMA;
                    7'b0110001: pkt.alu_op = ALU_HFENCE_GVMA;
                    7'b0010011: pkt.alu_op = ALU_HINVAL_VVMA;
                    default:    pkt.alu_op = ALU_HINVAL_GVMA;
                endcase
                // The H forms need en_h (f7[5] or f7[4] set).
                if ((f7[5] || f7[4]) && !ext_enable.en_h) ok = 1'b0;
            end
            12'b0001100_00000: pkt.alu_op = ALU_SFENCE_W_INVAL;
            12'b0001100_00001: pkt.alu_op = ALU_SFENCE_INVAL_IR;
            default: ok = 1'b0;
        endcase
        // DCD-31: rd x0 for every funct3 000 form; rs1 x0 except for
        // the forms that read rs1 (the SFENCE, SINVAL, HFENCE and
        // HINVAL address forms).
        if (!rd0) ok = 1'b0;
        if (!pkt.uses_rs1 && !rs10) ok = 1'b0;
    end else if (inst[14:12] == 3'b100) begin
        if (f7[6]) begin
            // Zimop. MOP.R.n: 1 n4 00 n3 n2 0111 n1 n0 rs1 100 rd;
            // MOP.RR.n: 1 n2 00 n1 n0 1 rs2 rs1 100 rd. Both write zero
            // to rd and read nothing: no extension this design implements
            // redefines them; Zicfiss, an RVA23 option not implemented,
            // redefines some.
            pkt.alu_op  = ALU_MOP;
            pkt.uses_rd = 1'b1;
            ok = (f7[4:3] == 2'b00) &&            // bits 29:28
                 (f7[0] || (inst[25:22] == 4'b0111));
        end else begin
            pkt.is_hlsv  = 1'b1;
            pkt.uses_rs1 = 1'b1;
            ok = ext_enable.en_h && (f7[6:3] == 4'b0110);
            if (!f7[0]) begin
                // HLV.B/BU 0110000, HLV.H/HU/HLVX.HU 0110010,
                // HLV.W/WU/HLVX.WU 0110100, HLV.D 0110110; rs2 selects
                // 0 signed, 1 unsigned, 3 HLVX.
                pkt.is_load = 1'b1;
                pkt.uses_rd = 1'b1;
                pkt.is_hlvx = (r2 == 5'd3);
                unique case ({f7[2:1], r2})
                    {2'b00, 5'd0}: pkt.alu_op = ALU_LB;
                    {2'b00, 5'd1}: pkt.alu_op = ALU_LBU;
                    {2'b01, 5'd0}: pkt.alu_op = ALU_LH;
                    {2'b01, 5'd1},
                    {2'b01, 5'd3}: pkt.alu_op = ALU_LHU;
                    {2'b10, 5'd0}: pkt.alu_op = ALU_LW;
                    {2'b10, 5'd1},
                    {2'b10, 5'd3}: pkt.alu_op = ALU_LWU;
                    {2'b11, 5'd0}: pkt.alu_op = ALU_LD;
                    default:       ok = 1'b0;
                endcase
            end else begin
                // HSV.B/H/W/D 0110001/0110011/0110101/0110111, rd x0.
                pkt.is_store = 1'b1;
                pkt.uses_rs2 = 1'b1;
                case (f7[2:1])
                    2'b00:   pkt.alu_op = ALU_SB;
                    2'b01:   pkt.alu_op = ALU_SH;
                    2'b10:   pkt.alu_op = ALU_SW;
                    default: pkt.alu_op = ALU_SD;
                endcase
                if (!rd0) ok = 1'b0;
            end
        end
    end else begin
        // Zicsr. funct3 001/010/011 read rs1, 101/110/111 the zimm.
        pkt.is_csr  = 1'b1;
        pkt.uses_rd = 1'b1;
        pkt.uses_rs1 = !inst[14];
        pkt.imm = {15'd0, inst[14] ? inst[19:15] : 5'd0, inst[31:20]};
        case (inst[14:12])
            3'b001:  pkt.alu_op = ALU_CSRRW;
            3'b010:  pkt.alu_op = ALU_CSRRS;
            3'b011:  pkt.alu_op = ALU_CSRRC;
            3'b101:  pkt.alu_op = ALU_CSRRWI;
            3'b110:  pkt.alu_op = ALU_CSRRSI;
            default: pkt.alu_op = ALU_CSRRCI;
        endcase
        ok = ext_enable.en_zicsr;
    end
    if (!ok) pkt.is_illegal = 1'b1;
    return pkt;
endfunction

// ---------------------------------------------------------------------------
// A vector instruction's scalar packet. DCD-21, DCD-24, DCD-25, DCD-32.
// v is decode_vec_one's packet for the same word. alu_op is ALU_VEC and
// v_op_class names the operation. Only the SCALAR register operands
// are described here:
//   OPIVX, OPMVX         GPR rs1
//   OPFVF                FPR rs1
//   vmv.x.s, vcpop.m,    GPR rd
//   vfirst.m
//   vfmv.f.s             FPR rd
//   vsetvl               GPR rd, rs1, rs2; vsetvli GPR rd, rs1;
//                        vsetivli GPR rd
//   loads, stores        GPR rs1, and GPR rs2 when strided
// is_load / is_store mark a vector load / store; is_fp is clear. An
// encoding that decodes to VOTHER or to the VMEM default is illegal
// (DCD-32), as is every vector encoding with en_v clear.
// ---------------------------------------------------------------------------
function automatic decode_pkt_t dec_vec(input decode_pkt_t     p,
                                        input logic [31:0]      inst,
                                        input ext_enable_t      ext_enable,
                                        input vec_decode_pkt_t  v);
    decode_pkt_t pkt;
    logic [5:0]  f6;
    pkt = p;
    f6  = inst[31:26];
    pkt.fmt    = FMT_R;
    pkt.alu_op = ALU_VEC;
    if (!ext_enable.en_v || !v.is_vector ||
        (v.v_op_class == VOTHER) || (v.v_op_class == VMEM)) begin
        pkt.is_illegal = 1'b1;
        return pkt;
    end
    if (inst[6:0] != OP_VECTOR) begin
        // LOAD-FP / STORE-FP vector forms. mop 10 is strided.
        pkt.is_load  = (inst[6:0] == OP_LOAD_FP);
        pkt.is_store = (inst[6:0] == OP_STORE_FP);
        pkt.uses_rs1 = 1'b1;
        pkt.uses_rs2 = (inst[27:26] == 2'b10);
        return pkt;
    end
    unique case (inst[14:12])
        3'b111: begin                            // OPCFG
            pkt.uses_rd = 1'b1;
            if (!inst[31]) begin
                // vsetvli: zimm[10:0] in imm[10:0], reserved bits
                // included, so vill can be formed downstream (DCD-25).
                pkt.uses_rs1 = 1'b1;
                pkt.imm      = {21'd0, inst[30:20]};
            end else if (inst[30]) begin
                // vsetivli: zimm[9:0] in imm[10:0], the AVL uimm[4:0]
                // in imm[20:16]; no source register.
                pkt.imm = {11'd0, inst[19:15], 6'd0, inst[29:20]};
            end else begin
                pkt.uses_rs1 = 1'b1;                 // vsetvl
                pkt.uses_rs2 = 1'b1;
            end
        end
        3'b100, 3'b110: pkt.uses_rs1 = 1'b1;     // OPIVX, OPMVX
        3'b101: begin                            // OPFVF
            pkt.uses_rs1  = 1'b1;
            pkt.rs1_is_fp = 1'b1;
        end
        3'b010: begin                            // OPMVV
            if (v.v_op_class inside {VOP_VMV_XS, VOP_VCPOP, VOP_VFIRST})
                pkt.uses_rd = 1'b1;
        end
        3'b001: begin                            // OPFVV
            if (v.v_op_class == VOP_VFMV_FS) begin
                pkt.uses_rd  = 1'b1;
                pkt.rd_is_fp = 1'b1;
            end
        end
        3'b011: begin                            // OPIVI, DCD-25
            if (f6[5:1] == 5'b01010)
                // vror.vi: six bits, bit 5 is instruction bit 26.
                pkt.imm = {26'd0, inst[26], inst[19:15]};
            else if (f6 inside {6'h0c, 6'h0e, 6'h0f, 6'h25, 6'h27, 6'h28,
                                6'h29, 6'h2a, 6'h2b, 6'h2c, 6'h2d, 6'h2e,
                                6'h2f, 6'h35})
                // zimm5: vrgather, vslideup, vslidedown, the shifts and
                // narrowing clips, vwsll; vmv<nr>r's field (0 to 7)
                pkt.imm = {27'd0, inst[19:15]};
            else
                // simm5: every other OPIVI instruction
                pkt.imm = {{27{inst[19]}}, inst[19:15]};
        end
        default: ;                               // OPIVV: no scalar
    endcase
    return pkt;
endfunction
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on VARHIDDEN */

// ---------------------------------------------------------------------------
// Single-slot decode function
// v is decode_vec_one's packet for the same word (dec_vec reads it).
// ---------------------------------------------------------------------------
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off VARHIDDEN */
function automatic decode_pkt_t decode_one(
    input logic [31:0]      inst,
    input logic             valid,
    input ext_enable_t      ext_enable,
    input vec_decode_pkt_t  v
);
    decode_pkt_t pkt;
    logic [6:0] op;
    logic [2:0] f3;
    logic [6:0] f7;
    logic       vmem;   // LOAD-FP / STORE-FP with a vector width

    // Zero out to avoid latches
    pkt          = '0;
    pkt.valid    = valid;
    pkt.instr    = inst;

    if (!valid) return pkt;

    op  = inst[6:0];
    f3  = inst[14:12];
    f7  = inst[31:25];
    vmem = (f3 == 3'b000) || (f3 == 3'b101) ||
           (f3 == 3'b110) || (f3 == 3'b111);

    pkt.opcode  = op;
    pkt.rd      = inst[11:7];
    pkt.rs1     = inst[19:15];
    pkt.rs2     = inst[24:20];
    pkt.rs3     = inst[31:27]; // zeroed below unless uses_rs3
    pkt.funct3  = f3;
    pkt.funct7  = f7;

    // No compressed-extension gating here: DCD-20. The IFU expands
    // every compressed instruction before the ibuf, so a 16-bit
    // encoding never reaches decode, and C and Zcb are mandatory.

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
                default: pkt.is_illegal = 1'b1;
            endcase
        end

        // ------------------------------------------------------------------
        // LOAD-FP: a vector load (width 000/101/110/111, DECODE-008) or
        // FLH (001, en_zfhmin), FLW (010, en_f), FLD (011, en_d). FLQ
        // (100) is not implemented. ALU_FLOAD; fp_fmt is the datum's
        // width (DCD-23); rd is an FP register, rs1 a GPR (DCD-24).
        // ------------------------------------------------------------------
        OP_LOAD_FP: begin
            if (vmem) begin
                pkt = dec_vec(pkt, inst, ext_enable, v);
            end else begin
                pkt.fmt      = FMT_I;
                pkt.imm      = imm_i(inst);
                pkt.alu_op   = ALU_FLOAD;
                pkt.is_load  = 1'b1;
                pkt.uses_rd  = 1'b1;
                pkt.uses_rs1 = 1'b1;
                pkt.rd_is_fp = 1'b1;
                unique case (f3)
                    3'b001: begin
                        pkt.fp_fmt = FP_H;
                        if (!ext_enable.en_zfhmin) pkt.is_illegal = 1'b1;
                    end
                    3'b010: begin
                        pkt.fp_fmt = FP_S;
                        if (!ext_enable.en_f) pkt.is_illegal = 1'b1;
                    end
                    3'b011: begin
                        pkt.fp_fmt = FP_D;
                        if (!ext_enable.en_d) pkt.is_illegal = 1'b1;
                    end
                    default: pkt.is_illegal = 1'b1;
                endcase
            end
        end

        // ------------------------------------------------------------------
        // MISC-MEM  (FENCE / FENCE.I / CBO), DCD-29
        // ------------------------------------------------------------------
        OP_MISC_MEM: pkt = dec_misc_mem(pkt, inst, ext_enable);

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
                    // SLLI - shamt in [25:20], funct7[6:1]=000000;
                    // Zbb unary ops and Zbs immediate forms (BP-123)
                    pkt.imm = imm_shamt(inst);
                    if (f7[6:1] == 6'b000000)
                        pkt.alu_op = ALU_SLLI;
                    else if ({f7, inst[24:20]} == 12'b0110000_00000)
                        pkt.alu_op = ALU_CLZ;
                    else if ({f7, inst[24:20]} == 12'b0110000_00001)
                        pkt.alu_op = ALU_CTZ;
                    else if ({f7, inst[24:20]} == 12'b0110000_00010)
                        pkt.alu_op = ALU_CPOP;
                    else if ({f7, inst[24:20]} == 12'b0110000_00100)
                        pkt.alu_op = ALU_SEXTB;
                    else if ({f7, inst[24:20]} == 12'b0110000_00101)
                        pkt.alu_op = ALU_SEXTH;
                    else if (f7[6:1] == 6'b010010)
                        pkt.alu_op = ALU_BCLRI;
                    else if (f7[6:1] == 6'b001010)
                        pkt.alu_op = ALU_BSETI;
                    else if (f7[6:1] == 6'b011010)
                        pkt.alu_op = ALU_BINVI;
                    else
                        pkt.is_illegal = 1'b1;
                end
                3'b010: begin pkt.alu_op = ALU_SLT;  pkt.imm = imm_i(inst); end
                3'b011: begin pkt.alu_op = ALU_SLTU; pkt.imm = imm_i(inst); end
                3'b100: begin pkt.alu_op = ALU_XOR;  pkt.imm = imm_i(inst); end
                3'b101: begin
                    // SRLI / SRAI - distinguished by funct7[5]; Zbb
                    // rori, orc.b, rev8 and Zbs bexti (BP-123)
                    pkt.imm = imm_shamt(inst);
                    if (f7[6:1] == 6'b000000)
                        pkt.alu_op = ALU_SRLI;
                    else if (f7[6:1] == 6'b010000)
                        pkt.alu_op = ALU_SRAI;
                    else if (f7[6:1] == 6'b011000)
                        pkt.alu_op = ALU_RORI;
                    else if ({f7, inst[24:20]} == 12'b0010100_00111)
                        pkt.alu_op = ALU_ORCB;
                    else if ({f7, inst[24:20]} == 12'b0110101_11000)
                        pkt.alu_op = ALU_REV8;
                    else if (f7[6:1] == 6'b010010)
                        pkt.alu_op = ALU_BEXTI;
                    else
                        pkt.is_illegal = 1'b1;
                end
                3'b110: begin
                    // ORI. With rd = x0 it is the encoding of the
                    // Zicbop prefetches, and without Zicbop an ORI HINT
                    // that executes as a no-op: legal either way
                    // (BP-123; it was illegal with en_zicbop clear).
                    pkt.alu_op = ALU_OR;
                    pkt.imm    = imm_i(inst);
                end
                3'b111: begin pkt.alu_op = ALU_ANDI; pkt.imm = imm_i(inst); end
                default: pkt.is_illegal = 1'b1;
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
                    // SLLIW; Zba slli.uw (6-bit shamt), Zbb clzw, ctzw,
                    // cpopw (BP-123)
                    pkt.imm = imm_shamt(inst);
                    if (f7 == 7'b0000000)
                        pkt.alu_op = ALU_SLLW;
                    else if (f7[6:1] == 6'b000010)
                        pkt.alu_op = ALU_SLLIUW;
                    else if ({f7, inst[24:20]} == 12'b0110000_00000)
                        pkt.alu_op = ALU_CLZW;
                    else if ({f7, inst[24:20]} == 12'b0110000_00001)
                        pkt.alu_op = ALU_CTZW;
                    else if ({f7, inst[24:20]} == 12'b0110000_00010)
                        pkt.alu_op = ALU_CPOPW;
                    else
                        pkt.is_illegal = 1'b1;
                end
                3'b101: begin
                    pkt.imm = imm_shamt(inst);
                    if (f7 == 7'b0000000)
                        pkt.alu_op = ALU_SRLW;
                    else if (f7 == 7'b0100000)
                        pkt.alu_op = ALU_SRAW;
                    else if (f7 == 7'b0110000)
                        pkt.alu_op = ALU_RORIW;          // Zbb, BP-123
                    else
                        pkt.is_illegal = 1'b1;
                end
                default: pkt.is_illegal = 1'b1;
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
                default: pkt.is_illegal = 1'b1;
            endcase
        end

        // ------------------------------------------------------------------
        // STORE-FP: a vector store, or FSH / FSW / FSD as LOAD-FP.
        // ALU_FSTORE; rs2 is an FP register, rs1 a GPR (DCD-24).
        // ------------------------------------------------------------------
        OP_STORE_FP: begin
            if (vmem) begin
                pkt = dec_vec(pkt, inst, ext_enable, v);
            end else begin
                pkt.fmt       = FMT_S;
                pkt.imm       = imm_s(inst);
                pkt.alu_op    = ALU_FSTORE;
                pkt.is_store  = 1'b1;
                pkt.uses_rs1  = 1'b1;
                pkt.uses_rs2  = 1'b1;
                pkt.rs2_is_fp = 1'b1;
                unique case (f3)
                    3'b001: begin
                        pkt.fp_fmt = FP_H;
                        if (!ext_enable.en_zfhmin) pkt.is_illegal = 1'b1;
                    end
                    3'b010: begin
                        pkt.fp_fmt = FP_S;
                        if (!ext_enable.en_f) pkt.is_illegal = 1'b1;
                    end
                    3'b011: begin
                        pkt.fp_fmt = FP_D;
                        if (!ext_enable.en_d) pkt.is_illegal = 1'b1;
                    end
                    default: pkt.is_illegal = 1'b1;
                endcase
            end
        end

        // ------------------------------------------------------------------
        // OP  (R-type): ADD/SUB, SLL, SLT, SLTU, XOR, SRL/SRA, OR, AND,
        //               MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU,
        //               Zba, Zbb, Zbs, Zicond
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
                // Zba (BP-123: sh1add was ALU_ADD, a placeholder)
                10'b0010000_010: pkt.alu_op = ALU_SH1ADD;
                10'b0010000_100: pkt.alu_op = ALU_SH2ADD;
                10'b0010000_110: pkt.alu_op = ALU_SH3ADD;
                // Zbb (BP-123)
                10'b0100000_111: pkt.alu_op = ALU_ANDN;
                10'b0100000_110: pkt.alu_op = ALU_ORN;
                10'b0100000_100: pkt.alu_op = ALU_XNOR;
                10'b0000101_110: pkt.alu_op = ALU_MAX;
                10'b0000101_111: pkt.alu_op = ALU_MAXU;
                10'b0000101_100: pkt.alu_op = ALU_MIN;
                10'b0000101_101: pkt.alu_op = ALU_MINU;
                10'b0110000_001: pkt.alu_op = ALU_ROL;
                10'b0110000_101: pkt.alu_op = ALU_ROR;
                // Zbs (BP-123)
                10'b0100100_001: pkt.alu_op = ALU_BCLR;
                10'b0100100_101: pkt.alu_op = ALU_BEXT;
                10'b0110100_001: pkt.alu_op = ALU_BINV;
                10'b0010100_001: pkt.alu_op = ALU_BSET;
                // Zicond (BP-123)
                10'b0000111_101: pkt.alu_op = ALU_CZEROEQZ;
                10'b0000111_111: pkt.alu_op = ALU_CZERONEZ;
                default: pkt.is_illegal = 1'b1;
            endcase
            // M extension gating: funct7=0000001 covers all M-ext ops
            if (f7 == 7'b0000001 && !ext_enable.en_m) pkt.is_illegal = 1'b1;
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
                // Zba (BP-123)
                10'b0000100_000: pkt.alu_op = ALU_ADDUW;
                10'b0010000_010: pkt.alu_op = ALU_SH1ADDUW;
                10'b0010000_100: pkt.alu_op = ALU_SH2ADDUW;
                10'b0010000_110: pkt.alu_op = ALU_SH3ADDUW;
                // Zbb (BP-123): zext.h (rs2 = 0), rolw, rorw
                10'b0000100_100: begin
                    if (inst[24:20] == 5'b00000)
                        pkt.alu_op = ALU_ZEXTH;
                    else
                        pkt.is_illegal = 1'b1;
                end
                10'b0110000_001: pkt.alu_op = ALU_ROLW;
                10'b0110000_101: pkt.alu_op = ALU_RORW;
                default: pkt.is_illegal = 1'b1;
            endcase
            // M extension gating: funct7=0000001 covers all 32-bit M ops
            if (f7 == 7'b0000001 && !ext_enable.en_m) pkt.is_illegal = 1'b1;
        end

        // ------------------------------------------------------------------
        // FP fused multiply-add (R4-type): FMADD, FMSUB, FNMSUB, FNMADD
        // ------------------------------------------------------------------
        OP_MADD, OP_MSUB, OP_NMSUB, OP_NMADD:
            pkt = dec_fma(pkt, inst, ext_enable);

        // ------------------------------------------------------------------
        // OP-FP  (R-type, FP ALU), DCD-22 to DCD-27
        // ------------------------------------------------------------------
        OP_FP: pkt = dec_opfp(pkt, inst, ext_enable);

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
                default: pkt.is_illegal = 1'b1;
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
            if (f3 != 3'b000) pkt.is_illegal = 1'b1;
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
        // SYSTEM, DCD-29 to DCD-31
        // ------------------------------------------------------------------
        OP_SYSTEM: pkt = dec_system(pkt, inst, ext_enable);

        // ------------------------------------------------------------------
        // OP-V  (opcode 0x57), DCD-21, DCD-24, DCD-25, DCD-32
        // ------------------------------------------------------------------
        OP_VECTOR: pkt = dec_vec(pkt, inst, ext_enable, v);

        // ------------------------------------------------------------------
        // AMO  (R-type), DCD-28
        // ------------------------------------------------------------------
        OP_AMO: pkt = dec_amo(pkt, inst, ext_enable);

        // ------------------------------------------------------------------
        // Illegal / unknown opcode
        // ------------------------------------------------------------------
        default: begin
            pkt.fmt        = FMT_ILL;
            pkt.is_illegal = 1'b1;
        end
    endcase

    // BP-123: the bitmanip extensions' gates. Each operation is decoded
    // above and made illegal here when its extension is disabled.
    if (((pkt.alu_op inside {ALU_SH1ADD, ALU_SH2ADD, ALU_SH3ADD, ALU_ADDUW,
                             ALU_SH1ADDUW, ALU_SH2ADDUW, ALU_SH3ADDUW,
                             ALU_SLLIUW}) && !ext_enable.en_zba) ||
        ((pkt.alu_op inside {ALU_ANDN, ALU_ORN, ALU_XNOR, ALU_CLZ, ALU_CLZW,
                             ALU_CTZ, ALU_CTZW, ALU_CPOP, ALU_CPOPW,
                             ALU_MAX, ALU_MAXU, ALU_MIN, ALU_MINU,
                             ALU_SEXTB, ALU_SEXTH, ALU_ZEXTH, ALU_ROL,
                             ALU_ROLW, ALU_ROR, ALU_RORI, ALU_RORIW,
                             ALU_RORW, ALU_ORCB, ALU_REV8}) &&
         !ext_enable.en_zbb) ||
        ((pkt.alu_op inside {ALU_BCLR, ALU_BCLRI, ALU_BEXT, ALU_BEXTI,
                             ALU_BINV, ALU_BINVI, ALU_BSET, ALU_BSETI}) &&
         !ext_enable.en_zbs))
        pkt.is_illegal = 1'b1;
    // The unary forms read rs1 only.
    if (pkt.alu_op inside {ALU_CLZ, ALU_CLZW, ALU_CTZ, ALU_CTZW, ALU_CPOP,
                           ALU_CPOPW, ALU_SEXTB, ALU_SEXTH, ALU_ZEXTH,
                           ALU_ORCB, ALU_REV8})
        pkt.uses_rs2 = 1'b0;

    // An illegal instruction is one operation, ALU_ILL: it uses no
    // register, carries no immediate and sets no is_* flag, so rename
    // and dispatch see only the trap (BP-124).
    if (pkt.is_illegal) begin
        pkt.alu_op     = ALU_ILL;
        pkt.imm        = '0;
        pkt.is_branch  = 1'b0;
        pkt.is_jump    = 1'b0;
        pkt.is_load    = 1'b0;
        pkt.is_store   = 1'b0;
        pkt.is_csr     = 1'b0;
        pkt.is_fp      = 1'b0;
        pkt.uses_rd    = 1'b0;
        pkt.uses_rs1   = 1'b0;
        pkt.uses_rs2   = 1'b0;
        pkt.uses_rs3   = 1'b0;
        pkt.fp_fmt     = '0;
        pkt.fp_src_fmt = '0;
        pkt.rd_is_fp   = 1'b0;
        pkt.rs1_is_fp  = 1'b0;
        pkt.rs2_is_fp  = 1'b0;
        pkt.is_hlsv    = 1'b0;
        pkt.is_hlvx    = 1'b0;
    end

    // Zero unused register fields so rename sees clean operands. rs3 is
    // zero for every operation but the four FMAs (decode_pkt_t).
    if (!pkt.uses_rd)  pkt.rd  = 5'h0;
    if (!pkt.uses_rs1) pkt.rs1 = 5'h0;
    if (!pkt.uses_rs2) pkt.rs2 = 5'h0;
    if (!pkt.uses_rs3) pkt.rs3 = 5'h0;

    return pkt;
endfunction
/* verilator lint_on VARHIDDEN */
/* verilator lint_on UNUSEDSIGNAL */

// ---------------------------------------------------------------------------
// Parallel decode and the intra-bundle vtype scan
// Every slot decodes independently. The only cross-slot term is
// vtype_hazard, a prefix OR of is_vsetvl over the earlier slots, so
// the whole bundle is one always_comb evaluated in slot order rather
// than a chain of continuous assigns (CLAUDE.md).
// ---------------------------------------------------------------------------
always_comb begin : decode_comb
    logic seen_vsetvl; // an earlier valid slot of this bundle is vsetvl

    seen_vsetvl = 1'b0;
    for (int s = 0; s < SLOTS; s++) begin
        pd_out[s] = pd_bundle[s];

        if (pd_bundle[s].valid &&
            (pd_bundle[s].fault_cause != IFU_FAULT_NONE)) begin
            // DCD-19: fetch fault. Not decoded, never illegal.
            decode_bundle[s]       = '0;
            decode_bundle[s].valid = 1'b1;
            decode_bundle[s].instr = pd_bundle[s].instr;
            vec_decode_bundle[s]   = '0;
        end else begin
            vec_decode_bundle[s] = decode_vec_one(pd_bundle[s].instr,
                                                  pd_bundle[s].valid,
                                                  ext_enable);
            decode_bundle[s]     = decode_one(pd_bundle[s].instr,
                                              pd_bundle[s].valid,
                                              ext_enable,
                                              vec_decode_bundle[s]);
            // DCD-32: an illegal vector encoding has no vector packet,
            // so it is not steered to the vector unit and neither
            // raises nor seeds a vtype hazard (BP-124).
            if (decode_bundle[s].is_illegal) vec_decode_bundle[s] = '0;
        end

        is_vector[s] = vec_decode_bundle[s].is_vector;

        // DCD-17. An invalid or faulting slot has a zero vector packet,
        // so it neither raises nor seeds a hazard.
        vtype_hazard[s] = seen_vsetvl & vec_decode_bundle[s].needs_vtype;
        seen_vsetvl     = seen_vsetvl | vec_decode_bundle[s].is_vsetvl;
    end
end

endmodule

`default_nettype wire
