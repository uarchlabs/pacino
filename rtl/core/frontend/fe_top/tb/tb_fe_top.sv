// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for fe_top (BP-118 Problem 8, BP-119). The front end runs
// programs end to end against models of everything outside its
// boundary (fe_decisions.md FE-17, FE-20):
//
//   memory    one byte array. It answers the L1I's l2-side TileLink
//             link (Get, two 256-bit AccessAckData beats per 64-byte
//             line) and the page table walker's memory port (8-byte
//             READ and CAS, ptw_mem_interfaces.md) from the one image
//             (WM-10), with a PTE change before a CAS (WM-11), an error
//             on a chosen access (WM-12) and variable ready and latency
//             (WM-13)
//   walker    BP-123: the RTL page table walker, rtl/mmu/ptw,
//             instantiated beside the front-end top (MMU-1a) and
//             connected on the itlb_l2t_* group; its CSR group is driven
//             here (MMU-24a). This was a behavioural Sv39 walk with a
//             fixed latency
//   backend   takes decode's output whenever the ibuf presents it,
//             compares it in order against the program's executed
//             stream, resolves every control transfer it retires,
//             redirects on a mispredict (RC_MISPREDICT, _self clear)
//             and on an ecall or a fetch fault (RC_TRAP, _self set,
//             to the program's handler), and commits by watermark
//
// THE EXECUTED STREAM IS BUILT BY THE PROGRAM WRITER, not computed by
// an instruction-set model. Every instruction is written into memory
// and, when it lies on the path the program takes, appended to the
// expected stream with its PC, its 32-bit (expanded) encoding, its
// length, its branch type, the next PC and, for a trap or a fault,
// the handler. Conditions are constant (beq x0,x0 is always taken,
// bne x0,x0 never), and a return's target is the call's link, which
// the writer knows. So no register file is modelled.
//
// WHAT A RETIRED INSTRUCTION IS CHECKED FOR: its PC is the next
// expected one; is_rvc; the expanded instruction; decode raises no
// illegal; the fault cause and faulting VA when one is expected; and
// its FTQ index and position name the block the FTQ fetched for it:
// the start PC the FTQ presented on its fetch port for that index,
// plus two bytes per position, is the instruction's PC.
//
// NOTHING EXTRA, NOTHING MISSING. A delivered PC that is not the next
// expected one is legal only right after a retired conditional branch
// or return: the front end predicted its direction or target wrongly
// and the backend redirects. Not after a JAL: predecode truncates the
// bundle at one (M1, M3, IB-2), so a JAL's successor is its target. A
// mismatch anywhere else is a stream error, a duplicated, skipped or
// invented instruction, and fails the run.
//
// BP-119. Every update path is connected (TD#151), so the predictors
// train. Two programs are added: loops (nested counted loops with a
// conditional, an indirect jump and an indirect call in the body, so
// the uBTB, LP, TAGE, SC and ITTAGE all receive updates and then
// predict trained) and coro (two coroutines switching by return-call,
// jalr x1, 0(x5) and jalr x5, 0(x1), TD#152, in a loop). A loop is
// written to memory once and its execution appended to the expected
// stream once per iteration (rep_iter); the loop branch's direction
// per iteration is known to the writer, as every other outcome is.
// Each program reports, per predictor, the cycles in which it received
// an update at the cluster (the valids after the cluster's own type
// and ready gates), and the backend mispredict, predecode redirect and
// p2 / p3 BPU redirect counts.
//
// BP-120. A fifth program, calls: main calls f, f calls g then h in
// sequence and returns, in a loop (TD#159, the RAS link). Each program
// also reports its RAS mispredicts (backend mispredicts of a RETURN or
// RETURN_CALL) and how often the FTB jump field was trained by a jump
// at a different position from the stored one (TD#156: two jumps of
// one region taking turns in the one field).
//
// BP-121. Programs covering every predictor path the planning
// documents describe (the program list is in run_prog below). One
// program runs per simulation, named by +PROG=<name>; each is its own
// regression target. BP-122 removed the mode that ran every program in
// one simulation without +PROG: the predictor tables carried from one
// program into the next, so the counts of every program after the
// first depended on the order. sim_fe_top runs each program in its own
// simulation. Every count
// stops at the last retirement (TD#167): the 200-cycle drain after it
// is not measured. Each program reports its cycles, its mispredicts,
// the mispredicts after warm-up by branch type and by PC (a program
// sets warm_e, the first expected entry after warm-up), and per
// predictor the updates it received and the predictions of it the FTQ
// used. THE RAS COMMIT IS CHECKED against the executed stream: every
// retired call, return and return-call is queued with its link
// address, and each ras_commit the cluster performs must be the next
// one, in order, with the same type and, for a push, the same address.
// A loop body whose path differs per iteration is emitted once per
// iteration by the same emitter calls; re-emitting rewrites the same
// bytes, and dry mode writes memory without appending to the stream.
// +define+BASE_RTL compiles this file against the tree as BP-121
// received it (no ftq_resolve_t.is_rvc, no ftb_cntrl upd_hit, no
// corrected-history nets), for the before column of its measurements.
//
// BP-123. Programs for maintenance (fencei, cboinval), uncached fetch
// (uc_nc, uc_io), the walker (pt_*) and the RVA23 extensions that reach
// fetch and decode (zstar). The backend model gained: memory patches a
// store applies when it retires (self-modifying code); the commit
// stage's FENCE.I / cbo.inval handshake, holding the restart until the
// IFU's ack (l1i_ifu_interfaces.md 11, A1); a CSR write that changes
// the walker's envcfg bits and restarts; the GPA and its kind on a
// guest-page fault; decode's operation and predecode's class per
// instruction where a program names them; and an EAGER commit mode for
// the uncached programs, which commits the entry of the last retired
// instruction as soon as nothing is in flight to the backend and
// resolves a block-ending branch against the block the FTQ fetched after
// it. Every program checks, every cycle, that no uncached request is
// presented before every older instruction has committed or off the
// path, that no uncached line is written into the L1I, and that an
// uncached instruction is delivered alone.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;
import decode_pkg::*;

module tb;

  localparam int MAXE    = 32768;
  localparam int TL_LAT  = 6;      // memory latency, request to beat 0

  logic clk;
  logic rstn;
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ---- DUT ports ------------------------------------------------------
  decode_pkt_t     [SLOTS-1:0] decode_bundle;
  vec_decode_pkt_t [SLOTS-1:0] vec_decode_bundle;
  logic            [SLOTS-1:0] is_vector;
  ifu_pd_pkt_t                 pd_out [0:SLOTS-1];
  logic            [SLOTS-1:0] vtype_hazard;
  logic                        dec_ibuf_rdy;
  logic [NUM_RESOLVE_PORTS-1:0] bkend_ftq_rsv_val;
  ftq_resolve_t                bkend_ftq_rsv [0:NUM_RESOLVE_PORTS-1];
  logic [NUM_RESOLVE_PORTS-1:0] ftq_bkend_rsv_rdy;
  logic                        bkend_ftq_redir_val;
  logic [FTQ_IDX_BITS-1:0]     bkend_ftq_redir_idx;
  logic [FTB_BR_POS_BITS-1:0]  bkend_ftq_redir_pos;
  logic [VA_WIDTH-1:0]         bkend_ftq_redir_pc;
  logic                        bkend_ftq_redir_self;
  ftq_redir_cause_e            bkend_ftq_redir_cause;
  logic                        bkend_ftq_redir_taken;   // BP-121
  logic                        bkend_ftq_commit_val;
  logic [FTQ_PTR_BITS-1:0]     bkend_ftq_commit_idx;
  logic                        itlb_l2t_req_val;
  logic                        itlb_l2t_req_rdy;
  logic [VA_WIDTH-13:0]        itlb_l2t_vpn;
  logic [ASID_WIDTH-1:0]       itlb_l2t_asid;
  logic [VMID_WIDTH-1:0]       itlb_l2t_vmid;
  logic                        itlb_l2t_v;
  logic [1:0]                  itlb_l2t_tag;
  logic                        l2t_itlb_rsp_val;
  logic [1:0]                  l2t_itlb_tag;
  logic [1:0]                  l2t_itlb_status;
  logic [PPN_WIDTH-1:0]        l2t_itlb_ppn;
  logic [2:0]                  l2t_itlb_size;   // IL-7
  logic [PERM_WIDTH-1:0]       l2t_itlb_perm;
  logic [1:0]                  l2t_itlb_pbmt;
  logic [CAUSE_WIDTH-1:0]      l2t_itlb_cause;
  logic [FAULT_GPA_WIDTH-1:0]  l2t_itlb_gpa;     // MMU-23, BP-124
  logic [1:0]                  l2t_itlb_gpa_imp;      // BP-123
  logic                        cmt_ifu_maint_val;     // BP-123
  logic                        cmt_ifu_maint_rdy;
  logic                        cmt_ifu_maint_op;
  logic [PA_WIDTH-1:0]         cmt_ifu_maint_paddr;
  logic                        ifu_cmt_maint_ack;
  logic                        l1i_mem_a_valid;
  logic                        l1i_mem_a_ready;
  logic [2:0]                  l1i_mem_a_opcode;
  logic [2:0]                  l1i_mem_a_param;
  logic [2:0]                  l1i_mem_a_size;
  logic [3:0]                  l1i_mem_a_source;
  logic [PA_WIDTH-1:0]         l1i_mem_a_address;
  logic [31:0]                 l1i_mem_a_mask;
  logic [255:0]                l1i_mem_a_data;
  logic                        l1i_mem_a_corrupt;
  logic                        l1i_mem_d_valid;
  logic                        l1i_mem_d_ready;
  logic [2:0]                  l1i_mem_d_opcode;
  logic [2:0]                  l1i_mem_d_param;
  logic [2:0]                  l1i_mem_d_size;
  logic [3:0]                  l1i_mem_d_source;
  logic [1:0]                  l1i_mem_d_sink;
  logic                        l1i_mem_d_denied;
  logic [255:0]                l1i_mem_d_data;
  logic                        l1i_mem_d_corrupt;
  logic                        csr_itlb_v;
  logic [1:0]                  csr_itlb_priv;
  logic [3:0]                  csr_itlb_satp_mode;
  logic [ASID_WIDTH-1:0]       csr_itlb_satp_asid;
  logic [3:0]                  csr_itlb_vsatp_mode;
  logic [ASID_WIDTH-1:0]       csr_itlb_vsatp_asid;
  logic [3:0]                  csr_itlb_hgatp_mode;
  logic [VMID_WIDTH-1:0]       csr_itlb_hgatp_vmid;
  logic [15:0][7:0]            csr_itlb_pmpcfg;
  logic [15:0][PA_WIDTH-3:0]   csr_itlb_pmpaddr;
  logic                        sc_enable;
  logic                        ftb_fastpath_en;
  logic                        tage_enable_aging;
  logic [31:0]                 tage_aging_interval;
  logic                        ittage_enable_aging;
  logic [31:0]                 ittage_aging_interval;
  ext_enable_t                 ext_enable;
  logic                        bkend_itlb_inv_val;
  logic [1:0]                  bkend_itlb_inv_op;
  logic                        bkend_itlb_inv_rs1_nz;
  logic                        bkend_itlb_inv_rs2_nz;
  logic [VA_WIDTH-13:0]        bkend_itlb_inv_vpn;
  logic [ASID_WIDTH-1:0]       bkend_itlb_inv_asid;
  logic [VMID_WIDTH-1:0]       bkend_itlb_inv_vmid;
  logic                        ftq_full;
  logic                        ftq_empty;

  fe_top dut (.*);

  // ---- the page table walker, beside the top (MMU-1a, BP-123) -------
  // itlb_l2t_acc and itlb_l2t_priv are the ITLB's (IL-3d), carried by
  // fe_top (BP-124); BP-123 tied the access type here.
  logic [1:0]                  itlb_l2t_acc;
  logic [1:0]                  itlb_l2t_priv;
  logic                        ptw_mem_req_val;
  logic                        ptw_mem_req_rdy;
  logic                        ptw_mem_req_op;
  logic [PA_WIDTH-1:0]         ptw_mem_req_paddr;
  logic [63:0]                 ptw_mem_req_cmp;
  logic [63:0]                 ptw_mem_req_swap;
  logic                        mem_ptw_rsp_val;
  logic [63:0]                 mem_ptw_rsp_data;
  logic                        mem_ptw_rsp_err;
  logic [3:0]                  csr_ptw_satp_mode;
  logic [PPN_WIDTH-1:0]        csr_ptw_satp_ppn;
  logic [3:0]                  csr_ptw_vsatp_mode;
  logic [GPA_WIDTH-13:0]       csr_ptw_vsatp_ppn;
  logic [3:0]                  csr_ptw_hgatp_mode;
  logic [PPN_WIDTH-1:0]        csr_ptw_hgatp_ppn;
  logic                        csr_ptw_menvcfg_adue;
  logic                        csr_ptw_henvcfg_adue;
  logic                        csr_ptw_menvcfg_pbmte;
  logic                        csr_ptw_henvcfg_pbmte;
  logic [15:0][7:0]            csr_ptw_pmpcfg;
  logic [15:0][PA_WIDTH-3:0]   csr_ptw_pmpaddr;

  ptw u_ptw (.*);

  // The walker reads the same PMP registers the ITLB does: one CSR
  // file, two inputs (MMU-11a, MMU-24a).
  assign csr_ptw_pmpcfg  = csr_itlb_pmpcfg;
  assign csr_ptw_pmpaddr = csr_itlb_pmpaddr;

  // ---- bookkeeping ----------------------------------------------------
  int    pass_cnt;
  int    fail_cnt;
  string tname;
  int    cyc;

  always @(posedge clk) cyc <= rstn ? cyc + 1 : 0;

  // BP-121: the RAS commit check. ras_exp holds the RAS operations of
  // the retired stream, in program order, with the link address a
  // push writes; ras_got holds the commits the cluster performed.
  typedef struct {
    bp_br_type_e         t;
    logic [VA_WIDTH-1:0] ra;
    logic [VA_WIDTH-1:0] pc;
  } rasev_t;
  rasev_t                  ras_exp [$];
  rasev_t                  ras_got [$];
  int                      n_ras_ok;
  int                      n_ras_bad;

  task automatic chk(input string nm, input logic ok);
    if (ok) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: [%s] %s", tname, nm);
    end
  endtask

  localparam logic [7:0] PTE_LEAF = 8'hCB;
  localparam logic [7:0] PTE_PTR  = 8'h01;
  typedef struct {
    logic [VA_WIDTH-1:0] pc;
    logic [31:0]         instr;      // expanded
    logic                rvc;
    bp_br_type_e         btype;      // NO_BRANCH for none
    logic                taken;
    logic [VA_WIDTH-1:0] target;     // CFI target, or the handler
    logic                trap;       // ecall: trap to target
    ifu_fault_e          fault;      // fetch fault: trap to target
    logic [VA_WIDTH-1:0] fva;
    // BP-123.
    logic [FAULT_GPA_WIDTH-1:0] fgpa; // cause 20: the faulting GPA
    logic [1:0]          fimp;       // and its implicit-access kind
    int                  maint;      // 1 FENCE.I, 2 cbo.inval, at commit
    logic [PA_WIDTH-1:0] mpa;        // cbo.inval's physical address
    int                  p0;         // memory patches applied when it
    int                  pn;         //   retires: [p0, p0 + pn)
    int                  aluop;      // decode's alu_op, -1 unchecked
    // BP-124: the privilege after it retires and redirects (a trap
    // taken to S, or an xRET), -1 unchanged.
    int                  npriv;
  } ex_t;
  localparam logic [31:0] ADDI_T0 = 32'h0012_8293;   // addi t0,t0,1
  localparam logic [15:0] CADDI   = 16'h0505;        // c.addi a0,1
  localparam logic [31:0] CADDI_X = 32'h0015_0513;   // its expansion
  localparam logic [31:0] RET     = 32'h0000_8067;   // jalr x0,0(ra)
  localparam logic [31:0] ECALL   = 32'h0000_0073;
  localparam logic [31:0] SRET    = 32'h1020_0073;   // BP-124, pt_upriv
  // BP-123.
  localparam logic [31:0] FENCEI  = 32'h0000_100F;   // fence.i
  localparam logic [31:0] SW_A0   = 32'h0005_2023;   // sw x0, 0(a0)
  localparam logic [15:0] CNOP    = 16'h0001;        // c.nop
  localparam logic [31:0] CNOP_X  = 32'h0000_0013;   // addi x0, x0, 0
  localparam logic [31:0] ADDI_T1 = 32'h0013_0313;   // addi t1,t1,1
  // PTE flag bytes, D A G U X W R V.
  localparam logic [7:0] F_URWXAD = 8'hDF;           // a G-stage leaf

  // =================================================================
  // The program writer (BP-121: a class, so its methods compile as
  // functions of their own rather than inline at every call: with
  // nineteen programs the inlined form produced an 18 MB C++ file).
  // It owns the memory image, the address map and the expected
  // stream; the module reads them through W.
  // =================================================================
  class pw_c;
    // The members the module sets through W are given values here as
    // well, so each has a driver inside the class (lint).
    function new();
      sv39      = 1'b0;
      satp_root = '0;
      pt_next   = '0;
      ne        = 0;
      dry       = 1'b0;
      wp        = '0;
      lfsr      = 16'h1;
      for (int k = 0; k < 32; k++) fnv[k] = '0;
      h2        = 1'b0;
      g_bare    = 1'b0;
      hg_root   = '0;
      vs_root   = '0;
      gpt_next  = '0;
      patching  = 1'b0;
      nowrite   = 1'b0;
    endfunction

    // =================================================================
    // Memory: bytes, physical.
    // =================================================================
    logic [7:0] mem [logic [PA_WIDTH-1:0]];

    function logic [7:0] rd8(input logic [PA_WIDTH-1:0] a);
      return mem.exists(a) ? mem[a] : 8'h00;
    endfunction

    function logic [63:0] rd64(input logic [PA_WIDTH-1:0] a);
      logic [63:0] d;
      for (int i = 0; i < 8; i++) d[8*i +: 8] = rd8(a + PA_WIDTH'(i));
      return d;
    endfunction

    function void wr64(input logic [PA_WIDTH-1:0] a,
                                 input logic [63:0] d);
      for (int i = 0; i < 8; i++) mem[a + PA_WIDTH'(i)] = d[8*i +: 8];
    endfunction

    // =================================================================
    // The address map the program writer uses. Bare: identity. Sv39:
    // a table of 4 KiB pages this file also writes as PTEs.
    // =================================================================
    logic                  sv39;
    logic [PA_WIDTH-1:0]   satp_root;
    logic [PA_WIDTH-1:0]   pt_next;
    logic [PPN_WIDTH-1:0]  vmap [logic [VA_WIDTH-13:0]];

    function logic [PA_WIDTH-1:0] va2pa(input logic [VA_WIDTH-1:0] va);
      logic [VA_WIDTH-13:0] v;
      if (!sv39 && !h2) return va[PA_WIDTH-1:0];
      v = va[VA_WIDTH-1:12];
      if (!vmap.exists(v)) begin
        $display("tb_fe_top: write to an unmapped VA %011h", va);
        return '0;
      end
      return {vmap[v], va[11:0]};
    endfunction

    // A page table page, zeroed, from the bump allocator.
    function logic [PA_WIDTH-1:0] pt_alloc();
      logic [PA_WIDTH-1:0] p;
      p       = pt_next;
      pt_next = pt_next + PA_WIDTH'('h1000);
      for (int i = 0; i < 512; i++) wr64(p + PA_WIDTH'(8 * i), '0);
      return p;
    endfunction

    // Map one 4 KiB page, V R X A D, supervisor (U clear).

    task map4k(input logic [VA_WIDTH-1:0] va,
                         input logic [PA_WIDTH-1:0] pa);
      logic [PA_WIDTH-1:0] t;
      logic [63:0]         pte;
      logic [8:0]          vpn [0:2];
      vpn[2] = va[38:30];
      vpn[1] = va[29:21];
      vpn[0] = va[20:12];
      t = satp_root;
      for (int l = 2; l > 0; l--) begin
        pte = rd64(t + PA_WIDTH'(8 * vpn[l]));
        if (!pte[0]) begin
          logic [PA_WIDTH-1:0] n;
          n   = pt_alloc();
          pte = {10'd0, 44'(n >> 12), 2'b00, PTE_PTR};
          wr64(t + PA_WIDTH'(8 * vpn[l]), pte);
        end
        t = PA_WIDTH'(pte[53:10]) << 12;
      end
      wr64(t + PA_WIDTH'(8 * vpn[0]),
           {10'd0, 44'(pa >> 12), 2'b00, PTE_LEAF});
      vmap[va[VA_WIDTH-1:12]] = pa[PA_WIDTH-1:12];
    endtask

    // =================================================================
    // The program writer and the expected stream.
    // =================================================================

    ex_t  ex [0:MAXE-1];
    int   ne;
    // Dry mode (BP-121): the emitters write memory and append nothing,
    // for code that lies off this iteration's path.
    logic dry;

    task put_hw(input logic [VA_WIDTH-1:0] va,
                          input logic [15:0] h);
      logic [PA_WIDTH-1:0] pa;
      if (nowrite) return;                  // BP-123, see below
      pa = va2pa(va);
      if (patching) begin
        pat_a.push_back(pa);
        pat_h.push_back(h);
        return;
      end
      mem[pa]                 = h[7:0];
      mem[pa + PA_WIDTH'(1)]  = h[15:8];
    endtask

    task add_ex(input logic [VA_WIDTH-1:0] pc,
                          input logic [31:0] w, input logic rvc,
                          input bp_br_type_e bt, input logic tk,
                          input logic [VA_WIDTH-1:0] tgt);
      if (dry) return;
      if (ne >= MAXE) $fatal(1, "tb_fe_top: expected stream over MAXE");
      ex[ne].pc     = pc;
      ex[ne].instr  = w;
      ex[ne].rvc    = rvc;
      ex[ne].btype  = bt;
      ex[ne].taken  = tk;
      ex[ne].target = tgt;
      ex[ne].trap   = 1'b0;
      ex[ne].fault  = IFU_FAULT_NONE;
      ex[ne].fva    = '0;
      ex[ne].fgpa   = '0;
      ex[ne].fimp   = '0;
      ex[ne].maint  = 0;
      ex[ne].mpa    = '0;
      ex[ne].p0     = 0;
      ex[ne].pn     = 0;
      ex[ne].aluop  = -1;
      ex[ne].npriv  = -1;
      ne++;
    endtask

    // Encoders.
    function logic [31:0] enc_jal(input logic [4:0] rd,
                                            input int imm);
      logic [20:0] o;
      o = 21'(imm);
      return {o[20], o[10:1], o[11], o[19:12], rd, 7'b1101111};
    endfunction

    function logic [31:0] enc_br(input logic [2:0] f3,
                                           input int imm);
      logic [12:0] o;
      o = 13'(imm);
      return {o[12], o[10:5], 5'd0, 5'd0, f3, o[4:1], o[11], 7'b1100011};
    endfunction


    // The write cursor and the instructions it emits. Each one is
    // written and appended as executed.
    logic [VA_WIDTH-1:0] wp;

    task i32(input logic [31:0] w);
      put_hw(wp, w[15:0]);
      put_hw(wp + VA_WIDTH'(2), w[31:16]);
      add_ex(wp, w, 1'b0, NO_BRANCH, 1'b0, '0);
      wp = wp + VA_WIDTH'(4);
    endtask

    task i16();
      put_hw(wp, CADDI);
      add_ex(wp, CADDI_X, 1'b1, NO_BRANCH, 1'b0, '0);
      wp = wp + VA_WIDTH'(2);
    endtask

    // n instructions of mixed length, a fixed pattern.
    task mixed(input int n);
      for (int k = 0; k < n; k++) begin
        if ((k % 3) == 1) i32(ADDI_T0);
        else              i16();
      end
    endtask

    // A conditional, beq x0,x0 (taken) or bne x0,x0 (not taken).
    task cond(input logic tk, input logic [VA_WIDTH-1:0] tgt);
      logic [31:0] w;
      w = enc_br(tk ? 3'b000 : 3'b001, int'(tgt - wp));
      put_hw(wp, w[15:0]);
      put_hw(wp + VA_WIDTH'(2), w[31:16]);
      add_ex(wp, w, 1'b0, COND, tk, tk ? tgt : wp + VA_WIDTH'(4));
      wp = tk ? tgt : wp + VA_WIDTH'(4);
    endtask

    // jal rd, tgt. rd = x1 is a call.
    task jal(input logic [4:0] rd, input logic [VA_WIDTH-1:0] tgt);
      logic [31:0] w;
      w = enc_jal(rd, int'(tgt - wp));
      put_hw(wp, w[15:0]);
      put_hw(wp + VA_WIDTH'(2), w[31:16]);
      add_ex(wp, w, 1'b0, ((rd == 5'd1) || (rd == 5'd5)) ? DIRECT_CALL
                                                         : DIRECT_UNC,
             1'b1, tgt);
      wp = tgt;
    endtask

    // ret to the address the matching call linked.
    task ret(input logic [VA_WIDTH-1:0] link);
      put_hw(wp, RET[15:0]);
      put_hw(wp + VA_WIDTH'(2), RET[31:16]);
      add_ex(wp, RET, 1'b0, RETURN, 1'b1, link);
      wp = link;
    endtask

    // ecall, trapping to the handler.
    task ecall(input logic [VA_WIDTH-1:0] handler);
      put_hw(wp, ECALL[15:0]);
      put_hw(wp + VA_WIDTH'(2), ECALL[31:16]);
      add_ex(wp, ECALL, 1'b0, NO_BRANCH, 1'b0, handler);
      ex[ne-1].trap  = 1'b1;
      ex[ne-1].aluop = int'(ALU_ECALL);
      wp = handler;
    endtask

    // BP-124. sret to tgt at privilege p (sepc and sstatus.SPP as the
    // program needs them; no register file is modelled). The backend
    // takes it like a trap: at retirement it sets csr_itlb_priv and
    // redirects to tgt. The front end sees a non-CFI and runs on
    // sequentially until then.
    task sret_to(input logic [VA_WIDTH-1:0] tgt, input logic [1:0] p);
      put_hw(wp, SRET[15:0]);
      put_hw(wp + VA_WIDTH'(2), SRET[31:16]);
      add_ex(wp, SRET, 1'b0, NO_BRANCH, 1'b0, tgt);
      ex[ne-1].trap  = 1'b1;
      ex[ne-1].npriv = int'(p);
      ex[ne-1].aluop = int'(ALU_SRET);
      wp = tgt;
    endtask

    // jal x0 to an address whose fetch faults: the JAL, then the
    // faulting fetch, which traps to the handler. Nothing is written
    // at the target.
    task jal_fault(input logic [VA_WIDTH-1:0] tgt,
                             input ifu_fault_e f,
                             input logic [VA_WIDTH-1:0] handler);
      jal(5'd0, tgt);
      add_ex(tgt, '0, 1'b0, NO_BRANCH, 1'b0, handler);
      ex[ne-1].fault = f;
      ex[ne-1].fva   = tgt;
      wp = handler;
    endtask

    // The end: jal x0, 0. Appended once; the backend stops comparing
    // after it.
    task halt();
      logic [31:0] w;
      w = enc_jal(5'd0, 0);
      put_hw(wp, w[15:0]);
      put_hw(wp + VA_WIDTH'(2), w[31:16]);
      add_ex(wp, w, 1'b0, DIRECT_UNC, 1'b1, wp);
    endtask

    // ---- BP-119 additions ---------------------------------------------
    // A conditional on a register, bne rs1, x0 (the loop branch). Its
    // outcome is the writer's: tk is this execution's direction.
    function logic [31:0] enc_bner(input logic [4:0] rs1,
                                             input int imm);
      logic [12:0] o;
      o = 13'(imm);
      return {o[12], o[10:5], 5'd0, rs1, 3'b001, o[4:1], o[11], 7'b1100011};
    endfunction

    function logic [31:0] enc_jalr(input logic [4:0] rd,
                                             input logic [4:0] rs1);
      return {12'd0, rs1, 3'b000, rd, 7'b1100111};
    endfunction

    // The loop branch at the end of a loop body, written taken back to
    // the body start; rep_iter appends the other iterations.
    task loop_br(input logic [VA_WIDTH-1:0] top);
      logic [31:0] w;
      w = enc_bner(5'd6, int'(top - wp));
      put_hw(wp, w[15:0]);
      put_hw(wp + VA_WIDTH'(2), w[31:16]);
      add_ex(wp, w, 1'b0, COND, 1'b1, top);
    endtask

    // Append iterations 2..n of the loop whose first iteration is the
    // expected-stream range [e0, ne), its last entry the loop branch.
    // Every iteration but the last takes the branch; the last falls
    // through, and the write cursor continues after the branch.
    task rep_iter(input int e0, input int n);
      int e1;
      int eb;
      e1 = ne;
      eb = e1 - 1;
      for (int it = 1; it < n; it++) begin
        for (int e = e0; e < e1; e++) begin
          ex[ne] = ex[e];
          ne++;
        end
      end
      // The final execution of the loop branch is not taken.
      ex[ne-1].taken  = 1'b0;
      ex[ne-1].target = ex[eb].pc + VA_WIDTH'(4);
      if (n == 1) begin
        ex[eb].taken  = 1'b0;
        ex[eb].target = ex[eb].pc + VA_WIDTH'(4);
      end
      wp = ex[eb].pc + VA_WIDTH'(4);
    endtask

    // An indirect jump or call through a register the writer has set:
    // jalr rd, 0(rs1) to tgt. The type follows the RAS hint table
    // (ras_decisions.md 2): rd and rs1 both link and unequal is
    // RETURN_CALL; rd link alone a call; rs1 link alone a return.
    task jalr_to(input logic [4:0] rd, input logic [4:0] rs1,
                           input logic [VA_WIDTH-1:0] tgt);
      logic [31:0] w;
      logic        rdl;
      logic        rsl;
      bp_br_type_e bt;
      w   = enc_jalr(rd, rs1);
      rdl = (rd == 5'd1) || (rd == 5'd5);
      rsl = (rs1 == 5'd1) || (rs1 == 5'd5);
      if (rdl && rsl && (rd != rs1)) bt = RETURN_CALL;
      else if (rdl)                  bt = INDIRECT_CALL;
      else if (rsl)                  bt = RETURN;
      else                           bt = INDIRECT_NONRET;
      put_hw(wp, w[15:0]);
      put_hw(wp + VA_WIDTH'(2), w[31:16]);
      add_ex(wp, w, 1'b0, bt, 1'b1, tgt);
      wp = tgt;
    endtask

    // ---- BP-121 additions ---------------------------------------------
    // A conditional whose outcome is this execution's: bne x6, x0, tgt
    // written at wp, taken or not as tk says. Not taken continues at
    // wp + 4; the bytes it skips when taken are the caller's to write.
    task bcc(input logic tk, input logic [VA_WIDTH-1:0] tgt);
      logic [31:0] w;
      w = enc_bner(5'd6, int'(tgt - wp));
      put_hw(wp, w[15:0]);
      put_hw(wp + VA_WIDTH'(2), w[31:16]);
      add_ex(wp, w, 1'b0, COND, tk, tk ? tgt : wp + VA_WIDTH'(4));
      wp = tk ? tgt : wp + VA_WIDTH'(4);
    endtask

    // Fill [wp, to) with c.addi, dry: code the path skips this time.
    // Written without the dry flag: c.addi halfwords, nothing appended.
    task fill_dry(input logic [VA_WIDTH-1:0] to);
      while (wp < to) begin
        put_hw(wp, CADDI);
        wp = wp + VA_WIDTH'(2);
      end
    endtask

    // Pad with c.addi up to (not past) an address, appended.
    task pad_to(input logic [VA_WIDTH-1:0] to);
      while (wp < to) i16();
    endtask

    // Compressed control transfers (RVC). Each is written as its 16-bit
    // encoding and appended with its 32-bit expansion, which is what
    // decode delivers (s.instr). Encodings per the RVC quadrant 1 and 2
    // formats; expansions: c.j -> jal x0; c.beqz / c.bnez rs1' -> beq /
    // bne x(8+rs1'), x0; c.jr rs1 -> jalr x0, 0(rs1); c.jalr rs1 ->
    // jalr x1, 0(rs1).
    function logic [31:0] enc_brr(input logic [2:0] f3,
                                            input logic [4:0] rs1,
                                            input int imm);
      logic [12:0] o;
      o = 13'(imm);
      return {o[12], o[10:5], 5'd0, rs1, f3, o[4:1], o[11], 7'b1100011};
    endfunction

    task cj(input logic [VA_WIDTH-1:0] tgt);
      logic [11:0] o;
      logic [15:0] h;
      o = 12'(int'(tgt - wp));
      h = {3'b101, o[11], o[4], o[9:8], o[10], o[6], o[7], o[3:1], o[5],
           2'b01};
      put_hw(wp, h);
      add_ex(wp, enc_jal(5'd0, int'(tgt - wp)), 1'b1, DIRECT_UNC, 1'b1, tgt);
      wp = tgt;
    endtask

    // c.bnez x8 (nz) or c.beqz x8, outcome tk.
    task cbz(input logic nz, input logic tk,
                       input logic [VA_WIDTH-1:0] tgt);
      logic [8:0]  o;
      logic [15:0] h;
      o = 9'(int'(tgt - wp));
      h = {nz ? 3'b111 : 3'b110, o[8], o[4:3], 3'b000, o[7:6], o[2:1], o[5],
           2'b01};
      put_hw(wp, h);
      add_ex(wp, enc_brr(nz ? 3'b001 : 3'b000, 5'd8, int'(tgt - wp)), 1'b1,
             COND, tk, tk ? tgt : wp + VA_WIDTH'(2));
      wp = tk ? tgt : wp + VA_WIDTH'(2);
    endtask

    // c.jr rs1 to tgt: RETURN when rs1 links, else INDIRECT_NONRET.
    task cjr(input logic [4:0] rs1, input logic [VA_WIDTH-1:0] tgt);
      logic rsl;
      rsl = (rs1 == 5'd1) || (rs1 == 5'd5);
      put_hw(wp, {4'b1000, rs1, 5'd0, 2'b10});
      add_ex(wp, enc_jalr(5'd0, rs1), 1'b1, rsl ? RETURN : INDIRECT_NONRET,
             1'b1, tgt);
      wp = tgt;
    endtask

    // c.jalr rs1 to tgt (rd = x1): RETURN_CALL when rs1 is x5, else a
    // push-only call (ras_decisions.md 2).
    task cjalr(input logic [4:0] rs1, input logic [VA_WIDTH-1:0] tgt);
      put_hw(wp, {4'b1001, rs1, 5'd0, 2'b10});
      add_ex(wp, enc_jalr(5'd1, rs1), 1'b1,
             (rs1 == 5'd5) ? RETURN_CALL : INDIRECT_CALL, 1'b1, tgt);
      wp = tgt;
    endtask

    // Bytes mixed(n) emits.
    function int mixed_bytes(input int n);
      int b;
      b = 0;
      for (int k = 0; k < n; k++) b += ((k % 3) == 1) ? 4 : 2;
      return b;
    endfunction

    // A conditional at wp that, taken, skips the mixed(n) after it.
    task cskip(input logic tk, input int n);
      logic [VA_WIDTH-1:0] b;
      logic [VA_WIDTH-1:0] e;
      logic                d;
      b = wp;
      e = b + VA_WIDTH'(4 + mixed_bytes(n));
      bcc(tk, e);
      if (tk) begin
        d   = dry;
        dry = 1'b1;
        wp  = b + VA_WIDTH'(4);
        mixed(n);
        dry = d;
        wp  = e;
      end else begin
        mixed(n);
      end
    endtask
    // A pseudo-random bit sequence (16-bit Galois LFSR), for a branch
    // the predictors cannot learn.
    logic [15:0] lfsr;
    function logic lfsr_bit();
      logic b;
      b    = lfsr[0];
      lfsr = {1'b0, lfsr[15:1]} ^ (b ? 16'hB400 : 16'h0000);
      return b;
    endfunction
    // The back-edge JAL of ftbonly, written but off the path.
    task d_jal_fill();
      logic                d;
      logic [VA_WIDTH-1:0] w;
      w   = wp;
      d   = dry;
      dry = 1'b1;
      wp  = w - VA_WIDTH'(4);
      jal(5'd0, RESET_VECTOR + VA_WIDTH'('h1000));
      dry = d;
      wp  = w;
    endtask
    logic [VA_WIDTH-1:0] fnv [0:31];

    task emit_nest(input int k, input int depth,
                             input logic [VA_WIDTH-1:0] link);
      logic [VA_WIDTH-1:0] l;
      wp = fnv[k];
      mixed(2);
      if (k < depth) begin
        l = wp + VA_WIDTH'(4);
        jal(5'd1, fnv[k+1]);
        emit_nest(k + 1, depth, l);
        mixed(1);
      end
      ret(link);
    endtask
    task emit_rec(input logic [VA_WIDTH-1:0] f, input int n,
                            input logic [VA_WIDTH-1:0] link);
      wp = f;
      mixed(2);
      bcc(n == 0, f + VA_WIDTH'(16));
      if (n > 0) begin
        jal(5'd1, f);
        emit_rec(f, n - 1, f + VA_WIDTH'(14));
        i16();
      end
      ret(link);
    endtask
    // A loop exit: a conditional, taken on the last pass, over a JAL
    // back to top. The JAL is written dry on the last pass.
    task exit_or_jal(input logic last,
                               input logic [VA_WIDTH-1:0] top);
      logic [VA_WIDTH-1:0] b;
      logic                d;
      b = wp;
      bcc(last, b + VA_WIDTH'(8));
      if (!last) begin
        jal(5'd0, top);
      end else begin
        d   = dry;
        dry = 1'b1;
        wp  = b + VA_WIDTH'(4);
        jal(5'd0, top);
        dry = d;
        wp  = b + VA_WIDTH'(8);
      end
    endtask
    // Write n bytes of c.addi at a, dry, keeping wp.
    task fill_dry_at(input logic [VA_WIDTH-1:0] a, input int n);
      logic [VA_WIDTH-1:0] w;
      w  = wp;
      wp = a;
      fill_dry(a + VA_WIDTH'(n));
      wp = w;
    endtask

    // =================================================================
    // BP-123 additions.
    // =================================================================
    // SELF-MODIFYING CODE. A store's memory effect is a list of
    // halfword patches applied when the store retires. patching: the
    // emitters' writes are collected into the list instead of memory.
    // nowrite: the emitters append to the stream and write nothing, for
    // the new code as it executes after the fence (memory holds the old
    // code until the store retires).
    logic                patching;
    logic                nowrite;
    logic [PA_WIDTH-1:0] pat_a [$];
    logic [15:0]         pat_h [$];

    // A store, sw x0, 0(a0): retiring it applies the patches written
    // between store() and store_end().
    int st_e;
    task store();
      i32(SW_A0);
      st_e           = ne - 1;
      ex[st_e].p0    = pat_a.size();
      patching       = 1'b1;
    endtask
    task store_end();
      patching       = 1'b0;
      ex[st_e].pn    = pat_a.size() - ex[st_e].p0;
    endtask

    // FENCE.I and cbo.inval: the backend drives the commit-stage
    // maintenance port when one retires and restarts after the ack.
    // BP-124: each names decode's operation (DCD-22), which the
    // backend checks as it retires.
    task fence_i();
      i32(FENCEI);
      ex[ne-1].maint = 1;
      ex[ne-1].aluop = int'(ALU_FENCE_I);
    endtask
    // A CSR write that changes the walker's envcfg bits when it
    // retires; fetch then restarts after it, as after a FENCE.I, so no
    // younger walk runs under the old value. csrrw x0, menvcfg, t0.
    // act_* hold the new values, indexed by the entry's p0.
    logic act_madue [$];
    logic act_hadue [$];
    logic act_mpbmte [$];
    logic act_hpbmte [$];
    task csr_env(input logic madue, input logic hadue,
                 input logic mpbmte, input logic hpbmte);
      i32({12'h30A, 5'd5, 3'b001, 5'd0, 7'b1110011});
      ex[ne-1].maint = 3;
      ex[ne-1].aluop = int'(ALU_CSRRW);
      ex[ne-1].p0    = act_madue.size();
      act_madue.push_back(madue);
      act_hadue.push_back(hadue);
      act_mpbmte.push_back(mpbmte);
      act_hpbmte.push_back(hpbmte);
    endtask

    task cbo_inval(input logic [4:0] rs1, input logic [PA_WIDTH-1:0] pa);
      i32({12'h000, rs1, 3'b010, 5'b00000, 7'b0001111});
      ex[ne-1].maint = 2;
      ex[ne-1].aluop = int'(ALU_CBO_INVAL);
      ex[ne-1].mpa   = pa;
    endtask

    // An indirect jump, jalr x0, 0(t2), to an address whose fetch
    // faults: reaches any target, where jal_fault reaches +-1 MiB.
    task jr_fault(input logic [VA_WIDTH-1:0] tgt, input ifu_fault_e f,
                  input logic [VA_WIDTH-1:0] handler);
      jalr_to(5'd0, 5'd7, tgt);
      add_ex(tgt, '0, 1'b0, NO_BRANCH, 1'b0, handler);
      ex[ne-1].fault = f;
      ex[ne-1].fva   = tgt;
      wp = handler;
    endtask
    task jr_gfault(input logic [VA_WIDTH-1:0] tgt,
                   input logic [FAULT_GPA_WIDTH-1:0] gpa,
                   input logic [1:0] imp,
                   input logic [VA_WIDTH-1:0] handler);
      jr_fault(tgt, IFU_FAULT_GUEST_PAGE, handler);
      ex[ne-1].fgpa = gpa;
      ex[ne-1].fimp = imp;
    endtask

    // A fetch fault with its guest physical address and kind.
    task jal_gfault(input logic [VA_WIDTH-1:0] tgt,
                    input logic [FAULT_GPA_WIDTH-1:0] gpa,
                    input logic [1:0] imp,
                    input logic [VA_WIDTH-1:0] handler);
      jal_fault(tgt, IFU_FAULT_GUEST_PAGE, handler);
      ex[ne-1].fgpa = gpa;
      ex[ne-1].fimp = imp;
    endtask

    // ---- PTEs ----------------------------------------------------------
    function logic [63:0] mk_pte(input logic [43:0] ppn,
                                 input logic [7:0] f,
                                 input logic [1:0] pbmt, input logic n);
      return {n, pbmt, 7'd0, ppn, 2'b00, f};
    endfunction

    // The PA of the single-stage PTE for va at a level, creating the
    // non-leaf tables above it. A non-leaf already present is followed.
    function logic [PA_WIDTH-1:0] s_slot(input logic [VA_WIDTH-1:0] va,
                                         input int lvl);
      logic [PA_WIDTH-1:0] t;
      logic [63:0]         pte;
      logic [8:0]          vi;
      t = satp_root;
      for (int l = 2; l > lvl; l--) begin
        vi  = va[12 + 9*l +: 9];
        pte = rd64(t + PA_WIDTH'(8 * vi));
        if (!pte[0]) begin
          logic [PA_WIDTH-1:0] n;
          n   = pt_alloc();
          pte = {10'd0, 44'(n >> 12), 2'b00, PTE_PTR};
          wr64(t + PA_WIDTH'(8 * vi), pte);
        end
        t = PA_WIDTH'(pte[53:10]) << 12;
      end
      vi = va[12 + 9*lvl +: 9];
      return t + PA_WIDTH'(8 * vi);
    endfunction

    // UNCACHED PAGES (PBMT NC or IO): their PPNs, for the allocation
    // check, and their VA pages, for the delivery check.
    logic uc_ppn [logic [PPN_WIDTH-1:0]];
    logic uc_vpn [logic [VA_WIDTH-13:0]];

    // A 4 KiB single-stage page with a PBMT.
    task map4k_pbmt(input logic [VA_WIDTH-1:0] va,
                    input logic [PA_WIDTH-1:0] pa, input logic [1:0] pbmt);
      wr64(s_slot(va, 0), mk_pte(44'(pa >> 12), PTE_LEAF, pbmt, 1'b0));
      vmap[va[VA_WIDTH-1:12]] = pa[PA_WIDTH-1:12];
      if (pbmt != 2'b00) begin
        uc_ppn[pa[PA_WIDTH-1:12]]   = 1'b1;
        uc_vpn[va[VA_WIDTH-1:12]]   = 1'b1;
      end
    endtask

    // ---- two-stage (V=1, vsatp Sv39, hgatp Sv39x4) ---------------------
    // The G-stage root is 16 KiB at hg_root. VS-stage tables live in
    // guest physical memory: each has a GPA from gpt_next and an SPA
    // from pt_alloc, mapped by a G-stage leaf. gmap is GPA page -> SPA
    // page; vmap is VA page -> SPA page, for writing code.
    logic                  h2;
    logic [PA_WIDTH-1:0]   hg_root;
    logic [GPA_WIDTH-1:0]  vs_root;       // GPA of the VS root
    logic [GPA_WIDTH-1:0]  gpt_next;
    logic [PPN_WIDTH-1:0]  gmap [logic [GPA_WIDTH-13:0]];

    // The PA of the G-stage PTE for a guest page at a level.
    function logic [PA_WIDTH-1:0] g_slot(input logic [GPA_WIDTH-13:0] gp,
                                         input int lvl);
      logic [PA_WIDTH-1:0] t;
      logic [63:0]         pte;
      logic [10:0]         gi;
      t = hg_root;
      for (int l = 2; l > lvl; l--) begin
        gi  = (l == 2) ? gp[28:18] : {2'b00, gp[9*l +: 9]};
        pte = rd64(t + PA_WIDTH'(8 * gi));
        if (!pte[0]) begin
          logic [PA_WIDTH-1:0] n;
          n   = pt_alloc();
          pte = {10'd0, 44'(n >> 12), 2'b00, PTE_PTR};
          wr64(t + PA_WIDTH'(8 * gi), pte);
        end
        t = PA_WIDTH'(pte[53:10]) << 12;
      end
      gi = (lvl == 2) ? gp[28:18] : {2'b00, gp[9*lvl +: 9]};
      return t + PA_WIDTH'(8 * gi);
    endfunction

    // A 4 KiB G-stage leaf, U R W X A D unless told otherwise.
    function void g_map(input logic [GPA_WIDTH-13:0] gp,
                        input logic [PA_WIDTH-1:0] spa,
                        input logic [63:0] leaf);
      wr64(g_slot(gp, 0), leaf);
      gmap[gp] = spa[PA_WIDTH-1:12];
    endfunction

    // hgatp Bare (VS-stage only): a GPA is the SPA, and no G-stage
    // leaf is written.
    logic                  g_bare;

    // A VS-stage table page: a GPA, an SPA, and the G-stage leaf.
    function logic [GPA_WIDTH-1:0] vs_alloc();
      logic [GPA_WIDTH-1:0] g;
      logic [PA_WIDTH-1:0]  p;
      if (g_bare) begin
        p = pt_alloc();
        gmap[(GPA_WIDTH-12)'(p[PA_WIDTH-1:12])] = p[PA_WIDTH-1:12];
        return GPA_WIDTH'(p);
      end
      g        = gpt_next;
      gpt_next = gpt_next + GPA_WIDTH'('h1000);
      p        = pt_alloc();
      g_map(g[GPA_WIDTH-1:12], p,
            mk_pte(44'(p >> 12), F_URWXAD, 2'b00, 1'b0));
      return g;
    endfunction

    function logic [PA_WIDTH-1:0] g2s(input logic [GPA_WIDTH-1:0] g);
      return {gmap[g[GPA_WIDTH-1:12]], g[11:0]};
    endfunction

    // The SPA of the VS-stage PTE for va at a level.
    function logic [PA_WIDTH-1:0] vs_slot(input logic [VA_WIDTH-1:0] va,
                                          input int lvl);
      logic [GPA_WIDTH-1:0] t;
      logic [63:0]          pte;
      logic [8:0]           vi;
      t = vs_root;
      for (int l = 2; l > lvl; l--) begin
        vi  = va[12 + 9*l +: 9];
        pte = rd64(g2s(t + GPA_WIDTH'(8 * vi)));
        if (!pte[0]) begin
          logic [GPA_WIDTH-1:0] n;
          n   = vs_alloc();
          pte = {10'd0, 44'(n >> 12), 2'b00, PTE_PTR};
          wr64(g2s(t + GPA_WIDTH'(8 * vi)), pte);
        end
        t = GPA_WIDTH'(pte[53:10]) << 12;
      end
      vi = va[12 + 9*lvl +: 9];
      return g2s(t + GPA_WIDTH'(8 * vi));
    endfunction

    // A two-stage 4 KiB mapping VA -> GPA -> SPA, both leaves ordinary.
    task h_map4k(input logic [VA_WIDTH-1:0] va,
                 input logic [GPA_WIDTH-1:0] gpa,
                 input logic [PA_WIDTH-1:0] spa);
      g_map(gpa[GPA_WIDTH-1:12], spa,
            mk_pte(44'(spa >> 12), F_URWXAD, 2'b00, 1'b0));
      wr64(vs_slot(va, 0), mk_pte(44'(gpa >> 12), PTE_LEAF, 2'b00, 1'b0));
      vmap[va[VA_WIDTH-1:12]] = spa[PA_WIDTH-1:12];
    endtask

  endclass

  pw_c W = new;

  // The warm-up boundary: mispredicts of expected entries from warm_e
  // on are reported as after warm-up. Programs set it.
  int warm_e;

  // =================================================================
  // The memory model: the L1I's l2-side link (FE-21).
  // =================================================================
  logic                q_val  [0:15];
  logic [PA_WIDTH-1:0] q_addr [0:15];
  int                  q_due  [0:15];
  logic                d_busy;
  logic [3:0]          d_src;
  logic                d_beat;
  int                  n_fills;

  assign l1i_mem_a_ready = rstn;

  initial begin : tl_mem
    logic                s_a;
    logic [3:0]          s_src;
    logic [PA_WIDTH-1:0] s_addr;
    logic                s_d;
    int                  pick;
    l1i_mem_d_valid   = 1'b0;
    l1i_mem_d_opcode  = 3'd1;            // AccessAckData
    l1i_mem_d_param   = '0;
    l1i_mem_d_size    = 3'd6;            // 64 bytes
    l1i_mem_d_source  = '0;
    l1i_mem_d_sink    = '0;
    l1i_mem_d_denied  = 1'b0;
    l1i_mem_d_data    = '0;
    l1i_mem_d_corrupt = 1'b0;
    d_busy            = 1'b0;
    d_src             = '0;
    d_beat            = 1'b0;
    for (int i = 0; i < 16; i++) q_val[i] = 1'b0;
    forever begin
      @(posedge clk);
      s_a    = rstn && l1i_mem_a_valid && l1i_mem_a_ready;
      s_src  = l1i_mem_a_source;
      s_addr = l1i_mem_a_address;
      s_d    = l1i_mem_d_valid && l1i_mem_d_ready;
      #1;
      if (!rstn) begin
        for (int i = 0; i < 16; i++) q_val[i] = 1'b0;
        d_busy          = 1'b0;
        l1i_mem_d_valid = 1'b0;
      end else begin
        if (s_d) begin
          if (d_beat) begin
            d_busy       = 1'b0;
            q_val[d_src] = 1'b0;
          end
          d_beat = !d_beat;
        end
        if (s_a) begin
          if (q_val[s_src]) $display("tb_fe_top: source %0d reused", s_src);
          if (l1i_mem_a_opcode != 3'd4)
            $display("tb_fe_top: L1I opcode %0d is not a Get",
                     l1i_mem_a_opcode);
          q_val[s_src]  = 1'b1;
          q_addr[s_src] = s_addr;
          q_due[s_src]  = cyc + TL_LAT;
          n_fills++;
        end
        if (!d_busy) begin
          pick = -1;
          for (int i = 0; i < 16; i++)
            if (q_val[i] && (q_due[i] <= cyc) && (pick < 0)) pick = i;
          if (pick >= 0) begin
            d_busy = 1'b1;
            d_src  = 4'(pick);
            d_beat = 1'b0;
          end
        end
        l1i_mem_d_valid  = d_busy;
        l1i_mem_d_source = d_src;
        for (int b = 0; b < 32; b++) begin
          l1i_mem_d_data[8*b +: 8] =
            W.rd8(q_addr[d_src] + PA_WIDTH'(32 * int'(d_beat) + b));
        end
      end
    end
  end

  // =================================================================
  // The walker's memory port (ptw_mem_interfaces.md, BP-123). It reads
  // and writes the same image as the L1I's link above (WM-10). WM-11:
  // the PTE at chg_pa is overwritten with chg_val just before the next
  // CAS to it. WM-12: a read or CAS of err_pa is answered with
  // mem_ptw_rsp_err, once. WM-13: ready falls on a pattern and the
  // latency varies over [pw_lat_min, pw_lat_max].
  // =================================================================
  int                  n_walks;
  int                  n_pw_acc;
  int                  n_pw_cas;
  int                  n_pw_err;
  int                  n_pw_chg;
  int                  pw_lat_min;
  int                  pw_lat_max;
  int                  pw_rdy_pat;
  logic                err_arm;
  logic [PA_WIDTH-1:0] err_pa;
  logic                chg_arm;
  logic [PA_WIDTH-1:0] chg_pa;
  logic [63:0]         chg_val;
  int                  n_pw_bad;     // WM-1, WM-3 seen broken

  // Walks whose VPN lies in [walk_lo, walk_hi), for the NAPOT and
  // invalidate programs; and the invalidate-during-a-walk trigger: the
  // first walk for inv_vpn arms an ITLB invalidate (all, ITLB-14) four
  // cycles later, and the cycle it fires records whether the walker was
  // still walking.
  logic [VA_WIDTH-13:0] walk_lo;
  logic [VA_WIDTH-13:0] walk_hi;
  int                   n_walk_rng;
  logic [VA_WIDTH-13:0] walk2_lo;
  logic [VA_WIDTH-13:0] walk2_hi;
  int                   n_walk_rng2;
  logic                 inv_watch;
  logic [VA_WIDTH-13:0] inv_vpn;
  int                   inv_at;
  int                   n_inv_fired;
  int                   n_inv_busy;

  always @(posedge clk) begin : walk_count
    if (rstn && itlb_l2t_req_val && itlb_l2t_req_rdy) begin
      n_walks <= n_walks + 1;
      if ((itlb_l2t_vpn >= walk_lo) && (itlb_l2t_vpn < walk_hi))
        n_walk_rng <= n_walk_rng + 1;
      if ((itlb_l2t_vpn >= walk2_lo) && (itlb_l2t_vpn < walk2_hi))
        n_walk_rng2 <= n_walk_rng2 + 1;
    end
  end

  initial begin : ptw_mem
    logic                s_acc;
    logic                s_op;
    logic [PA_WIDTH-1:0] s_pa;
    logic [63:0]         s_cmp;
    logic [63:0]         s_swap;
    logic                o_val;
    int                  o_due;
    logic                o_op;
    logic [PA_WIDTH-1:0] o_pa;
    logic [63:0]         o_cmp;
    logic [63:0]         o_swap;
    logic [63:0]         old;
    int                  rc;
    ptw_mem_req_rdy  = 1'b0;
    mem_ptw_rsp_val  = 1'b0;
    mem_ptw_rsp_data = '0;
    mem_ptw_rsp_err  = 1'b0;
    o_val            = 1'b0;
    rc               = 0;
    forever begin
      @(posedge clk);
      s_acc  = rstn && ptw_mem_req_val && ptw_mem_req_rdy;
      s_op   = ptw_mem_req_op;
      s_pa   = ptw_mem_req_paddr;
      s_cmp  = ptw_mem_req_cmp;
      s_swap = ptw_mem_req_swap;
      #1;
      mem_ptw_rsp_val = 1'b0;
      mem_ptw_rsp_err = 1'b0;
      if (!rstn) begin
        o_val = 1'b0;
      end else begin
        if (o_val && (o_due <= cyc)) begin
          o_val           = 1'b0;
          mem_ptw_rsp_val = 1'b1;
          if (err_arm && (o_pa == err_pa)) begin
            err_arm          = 1'b0;
            mem_ptw_rsp_err  = 1'b1;
            mem_ptw_rsp_data = 64'hBAD0_BAD0_BAD0_BAD0;
            n_pw_err++;
          end else begin
            if (o_op && chg_arm && (o_pa == chg_pa)) begin
              chg_arm = 1'b0;
              W.wr64(o_pa, chg_val);
              n_pw_chg++;
            end
            old              = W.rd64(o_pa);
            mem_ptw_rsp_data = old;
            if (o_op && (old == o_cmp)) W.wr64(o_pa, o_swap);
          end
        end
        if (s_acc) begin
          if (s_pa[2:0] != 3'b000) n_pw_bad++;          // WM-1
          if (o_val) n_pw_bad++;                         // WM-3
          o_val  = 1'b1;
          o_op   = s_op;
          o_pa   = s_pa;
          o_cmp  = s_cmp;
          o_swap = s_swap;
          o_due  = cyc + pw_lat_min +
                   ((pw_lat_max > pw_lat_min)
                      ? int'($urandom % (pw_lat_max - pw_lat_min + 1)) : 0);
          n_pw_acc++;
          if (s_op) n_pw_cas++;
        end
      end
      // WM-13: ready from a counter, never from the request (WM-2).
      rc++;
      ptw_mem_req_rdy = rstn && ((pw_rdy_pat == 0) || ((rc % pw_rdy_pat) == 0));
    end
  end

  // =================================================================
  // The FTQ fetch log: the block start the FTQ presented for each
  // index, taken from the FTQ-to-IFU fetch handshake inside the top.
  // =================================================================
  logic [VA_WIDTH-1:0] fstart [0:FTQ_DEPTH-1];
  int                  n_pd_redir;
  // BP-121, TD#167: the measurement window. Set by the backend after
  // every edge; high while a program runs and has not yet retired its
  // last expected instruction, so no count includes the drain.
  logic                meas;

  // BP-123: per index, a fetch of it since the last flush that covered
  // it (fseen), and the IFU's writeback of it since then (wbseen). The
  // eager backend resolves a branch from them; see the backend model.
  logic [FTQ_DEPTH-1:0] fseen;
  logic [FTQ_DEPTH-1:0] wbseen;

  function automatic logic fl_covers(input logic [FTQ_IDX_BITS-1:0] i);
    return FTQ_IDX_BITS'(i - dut.ftq_ifu_commit_ptr) >=
           FTQ_IDX_BITS'(dut.ftq_ifu_flush_idx - dut.ftq_ifu_commit_ptr);
  endfunction

  always @(posedge clk) begin : fetch_log
    if (rstn && dut.ftq_ifu_req_val && dut.ftq_ifu_req_rdy &&
        !dut.ftq_ifu_flush_val)
      fstart[dut.ftq_ifu_idx] <= dut.ftq_ifu_start_pc;
    if (meas && dut.u_ftq.w_pd_redir_val && !bkend_ftq_redir_val)
      n_pd_redir <= n_pd_redir + 1;
    if (!rstn) begin
      fseen  <= '0;
      wbseen <= '0;
    end else begin
      for (int i = 0; i < FTQ_DEPTH; i++) begin
        if (dut.ftq_ifu_flush_val && fl_covers(FTQ_IDX_BITS'(i))) begin
          fseen[i]  <= 1'b0;
          wbseen[i] <= 1'b0;
        end else begin
          if (dut.ftq_ifu_req_val && dut.ftq_ifu_req_rdy &&
              (dut.ftq_ifu_idx == FTQ_IDX_BITS'(i))) begin
            fseen[i]  <= 1'b1;
            wbseen[i] <= 1'b0;
          end
          if (dut.ifu_ftq_pdwb_val &&
              (dut.ifu_ftq_pdwb_idx == FTQ_IDX_BITS'(i)))
            wbseen[i] <= 1'b1;
        end
      end
    end
  end

  // =================================================================
  // BP-119: what the predictors received, and the BPU redirects. The
  // counts are the valids AFTER the cluster's own gates (type and
  // queue ready), i.e. updates the predictor accepted, one per slot
  // per cycle.
  // =================================================================
  int n_u_ubtb;
  int n_u_lp;
  int n_u_tage;
  int n_u_ittage;
  int n_u_sc;
  int n_u_ras;
  int n_rc_p2;
  int n_rc_commit;
  int n_redir_p2;
  int n_redir_p3;
  int n_nomap;
  int n_jmp_swap;
  // BP-121: predictions the FTQ used, per predictor. Each counts the
  // slots (or blocks) of a group the FTQ accepted (the shadow's ok_*,
  // so a group for a squashed entry is not counted) whose recorded
  // source is that predictor:
  //   uBTB    p1 blocks the uBTB hit
  //   LP      p1 slots whose direction the LP supplied, and (BP-122)
  //           p2 slots whose direction the LP supplied (n_use_lp2),
  //           the direction the entry keeps: SC does not override it
  //   FTB     p2 groups the FTB answered (bpu_slot_val_p2)
  //   TAGE    p2 conditional slots whose direction TAGE supplied
  //   SC      p3 conditional slots SC answered (n_use_sc), and those
  //           whose direction SC changed (n_sc_flip)
  //   ITTAGE  p2 indirect slots whose target ITTAGE supplied
  //   RAS     p1 and p2 return slots whose target the RAS supplied
  int n_use_ubtb;
  int n_use_lp;
  // BP-122: p2 conditional slots whose direction the loop predictor
  // supplied (the LP wins at p2 and p3 when trusted, ruled by Jeff).
  int n_use_lp2;
  int n_use_ftb;
  int n_use_tage;
  int n_use_sc;
  int n_sc_flip;
  int n_use_ittage;
  int n_use_ras;
  int n_u_ftb;
  // BP-121: responses of the queued predictors at the stage the
  // cluster reads them, for the p2 (TAGE, ITTAGE) or p3 (SC) block:
  // on time (branch_id is the block's) or late (an older block's).
  int n_tage_ok;
  int n_tage_late;
  int n_it_ok;
  int n_it_late;
  int n_sc_ok;
  int n_sc_late;

  // BP-121: p2 blocks whose history bundle (the branches on the path
  // and their directions) differs from the bundle p1 wrote, with no p2
  // redirect to correct it; and p2 redirects.
  int          n_hist_mis;
  logic [1:0]  p1_nb  [0:FTQ_DEPTH-1];
  logic [1:0]  p1_tkn [0:FTQ_DEPTH-1];
  always @(posedge clk) begin : hist_log
    if (rstn && dut.u_bpu.r_val_p1) begin
      p1_nb[dut.u_bpu.r_idx_p1]  <= dut.u_bpu.w_hist_num_branches;
      p1_tkn[dut.u_bpu.r_idx_p1] <= dut.u_bpu.w_hist_pred_taken &
                                    {dut.u_bpu.w_hist_num_branches >= 2'd2,
                                     dut.u_bpu.w_hist_num_branches >= 2'd1};
    end
`ifndef BASE_RTL
    if (meas && dut.u_bpu.r_val_p2 && dut.u_ftq.w_ok_blk_p2 &&
        dut.u_bpu.w_ftb_valid_p2 && !dut.u_bpu.w_any_redir_p2 &&
        ((p1_nb[dut.u_bpu.r_idx_p2] != dut.u_bpu.w_c2_n) ||
         (p1_tkn[dut.u_bpu.r_idx_p2] != (dut.u_bpu.w_c2_tkn &
            {dut.u_bpu.w_c2_n >= 2'd2, dut.u_bpu.w_c2_n >= 2'd1}))))
      n_hist_mis <= n_hist_mis + 1;
`endif
  end

  // BP-121, TD#161: a p3 slot write for an entry whose p2 slot group
  // was not written this allocation (the FTB did not answer it), which
  // overwrote the p1 slots with an empty view. Per index, whether the
  // p2 group was written since the entry's p1 allocation.
  logic p2_wr_seen [0:FTQ_DEPTH-1];
  int   n_p3_no_p2;
  always @(posedge clk) begin : p3_log
    if (rstn && dut.u_ftq.w_ok_pred_p1) p2_wr_seen[dut.bpu_pred_idx_p1] <= 1'b0;
    if (rstn && dut.u_ftq.w_ok_slot_p2) p2_wr_seen[dut.bpu_slot_idx_p2] <= 1'b1;
    if (meas && dut.u_ftq.w_ok_slot_p3 && !p2_wr_seen[dut.bpu_slot_idx_p3])
      n_p3_no_p2 <= n_p3_no_p2 + 1;
  end

  // BP-121: the cluster's own p2 redirect keeps the redirecting block's
  // RAS operation (the restore is not applied to it). The cycle after a
  // p2 redirect the FTQ took for a block that operated on the RAS, the
  // RAS top must be the block's post-op snapshot (bpu_blk_ras_p2).
  logic                    own_chk;
  logic [RAS_PTR_BITS-1:0] own_tosr;
  int                      n_own_ok;
  int                      n_own_bad;
  always @(posedge clk) begin : own_log
    if (rstn && own_chk) begin
      if (dut.u_bpu.u_ras.tosr == own_tosr) n_own_ok  <= n_own_ok + 1;
      else                                  n_own_bad <= n_own_bad + 1;
    end
`ifndef BASE_RTL
    own_chk  <= rstn && meas && dut.u_bpu.w_own_p2 &&
                (dut.u_bpu.w_ras_pred_val_p2[0] ||
                 dut.u_bpu.w_ras_pred_val_p2[1]);
`else
    own_chk  <= rstn && meas && dut.u_ftq.w_arm_win[4] &&
                (dut.u_bpu.w_ras_pred_val_p2[0] ||
                 dut.u_bpu.w_ras_pred_val_p2[1]);
`endif
    own_tosr <= dut.bpu_blk_ras_p2.tosr;
  end

  // BP-121, TD#149 measured: p3 repairs (the p3 RAS view of a block
  // differs from its p2 operation), and backend restores that name an
  // entry a p3 repair changed (its snapshot, written at p2, predates
  // the repair).
  logic p3_rep [0:FTQ_DEPTH-1];
  int   n_p3_rep;
  int   n_rest_rep;
  always @(posedge clk) begin : rep_log
    if (rstn && dut.u_ftq.w_ok_pred_p1) p3_rep[dut.bpu_pred_idx_p1] <= 1'b0;
`ifndef BASE_RTL
    if (rstn && dut.u_bpu.r_val_p3 &&
        (((dut.u_bpu.w_ras_pred_val_p3[0] != dut.u_bpu.r_ras_val_p3[0]) &&
          (dut.u_bpu.w_ras_br_type_p3[0] inside {DIRECT_CALL, INDIRECT_CALL,
                                                 RETURN, RETURN_CALL})) ||
         ((dut.u_bpu.w_ras_pred_val_p3[1] != dut.u_bpu.r_ras_val_p3[1]) &&
          (dut.u_bpu.w_ras_br_type_p3[1] inside {DIRECT_CALL, INDIRECT_CALL,
                                                 RETURN, RETURN_CALL})))) begin
      p3_rep[dut.u_bpu.r_idx_p3] <= 1'b1;
      if (meas) n_p3_rep <= n_p3_rep + 1;
    end
`endif
    if (meas && dut.u_ftq.w_arm_win[1] && dut.ras_restore_val &&
        p3_rep[dut.ftq_rollback_idx])
      n_rest_rep <= n_rest_rep + 1;
  end

  // BP-122 (ruled by Jeff: the LP wins at p2 and p3): a slot whose p2
  // direction the loop predictor supplied keeps it at p3. Per index,
  // the LP slots of the p2 group the FTQ accepted and their direction;
  // the p3 group of the same index must agree and must not name SC.
  logic [NUM_PRED_SLOTS-1:0] lp2_src [0:FTQ_DEPTH-1];
  logic [NUM_PRED_SLOTS-1:0] lp2_tkn [0:FTQ_DEPTH-1];
  int                        n_lp_kept;
  int                        n_lp_bad;
  always @(posedge clk) begin : lp_keep_log
    if (rstn && dut.u_ftq.w_ok_pred_p1) lp2_src[dut.bpu_pred_idx_p1] <= '0;
    if (rstn && dut.u_ftq.w_ok_slot_p2) begin
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        lp2_src[dut.bpu_slot_idx_p2][s] <=
          dut.bpu_slot_p2[s].slot_valid &&
          (dut.bpu_slot_p2[s].pred_src == PRED_LOOP);
        lp2_tkn[dut.bpu_slot_idx_p2][s] <= dut.bpu_slot_p2[s].taken;
      end
    end
    if (meas && dut.u_ftq.w_ok_slot_p3) begin
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        if (lp2_src[dut.bpu_slot_idx_p3][s]) begin
          if ((dut.bpu_slot_p3[s].taken == lp2_tkn[dut.bpu_slot_idx_p3][s])
              && (dut.bpu_slot_p3[s].pred_src != PRED_SC))
            n_lp_kept <= n_lp_kept + 1;
          else
            n_lp_bad  <= n_lp_bad + 1;
        end
      end
    end
  end

  int n_p2_blk;
  // BP-121: FTB lookups an update took the read port from (TD#162),
  // and p2 cycles in which a block the FTQ squashed still operated on
  // the RAS (FE-14).
  int n_ftb_drop;
  int n_ras_sq;
  always @(posedge clk) begin : resp_log
    if (meas) begin
      if (dut.u_bpu.r_val_p2) n_p2_blk <= n_p2_blk + 1;
      if (dut.u_bpu.u_ftb.u_ftb_cntrl.valid_p1 &&
          dut.u_bpu.u_ftb.u_ftb_cntrl.upd_active)
        n_ftb_drop <= n_ftb_drop + 1;
      if (dut.u_bpu.r_val_p2 && !dut.u_ftq.w_ok_blk_p2 &&
          (dut.u_bpu.w_ras_pred_val_p2[0] || dut.u_bpu.w_ras_pred_val_p2[1]))
        n_ras_sq <= n_ras_sq + 1;
      if (dut.u_bpu.r_val_p2 && dut.u_bpu.w_tage_pred_rdy_p2[0]) begin
        if (dut.u_bpu.w_tage_pred_meta_p2[0].branch_id == dut.u_bpu.r_idx_p2)
          n_tage_ok <= n_tage_ok + 1;
        else
          n_tage_late <= n_tage_late + 1;
      end
      if (dut.u_bpu.r_val_p2 && dut.u_bpu.w_ittage_pred_rdy_p2[0]) begin
        if (dut.u_bpu.w_ittage_pred_meta_p2[0].branch_id == dut.u_bpu.r_idx_p2)
          n_it_ok <= n_it_ok + 1;
        else
          n_it_late <= n_it_late + 1;
      end
      if (dut.u_bpu.r_val_p3 && dut.u_bpu.w_sc_pred_rdy_p3[0]) begin
        if (dut.u_bpu.w_sc_pred_meta_p3[0].branch_id == dut.u_bpu.r_idx_p3)
          n_sc_ok <= n_sc_ok + 1;
        else
          n_sc_late <= n_sc_late + 1;
      end
    end
  end

  always @(posedge clk) begin : use_log
    int lp;
    int lp2;
    int ras;
    int tg;
    int it;
    int sc;
    int fl;
    lp  = 0;
    lp2 = 0;
    ras = 0;
    tg  = 0;
    it  = 0;
    sc  = 0;
    fl  = 0;
    if (meas) begin
      if (dut.u_ftq.w_ok_pred_p1 && dut.u_bpu.r_ubtb_blk_p1.hit)
        n_use_ubtb <= n_use_ubtb + 1;
      if (dut.u_ftq.w_ok_slot_p2) n_use_ftb <= n_use_ftb + 1;
      if (dut.u_bpu.w_ftb_upd_val_u0) n_u_ftb <= n_u_ftb + 1;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        if (dut.u_ftq.w_ok_pred_p1 && dut.bpu_pred_slot_p1[s].slot_valid) begin
          if (dut.bpu_pred_slot_p1[s].pred_src == PRED_LOOP) lp++;
          if (dut.bpu_pred_slot_p1[s].pred_src == PRED_RAS)  ras++;
        end
        if (dut.u_ftq.w_ok_slot_p2 && dut.bpu_slot_p2[s].slot_valid) begin
          if (dut.bpu_slot_p2[s].pred_src == PRED_TAGE)   tg++;
          if (dut.bpu_slot_p2[s].pred_src == PRED_LOOP)   lp2++;
          if (dut.bpu_slot_p2[s].pred_src == PRED_ITTAGE) it++;
          if (dut.bpu_slot_p2[s].pred_src == PRED_RAS)    ras++;
        end
        if (dut.u_ftq.w_ok_slot_p3 && dut.bpu_slot_p3[s].slot_valid &&
            (dut.bpu_slot_p3[s].br_type == COND)) begin
          if (dut.u_bpu.w_sc_hit_p3[s])                  sc++;
          if (dut.bpu_slot_p3[s].pred_src == PRED_SC)    fl++;
        end
      end
      n_use_lp     <= n_use_lp     + lp;
      n_use_lp2    <= n_use_lp2    + lp2;
      n_use_ras    <= n_use_ras    + ras;
      n_use_tage   <= n_use_tage   + tg;
      n_use_ittage <= n_use_ittage + it;
      n_use_sc     <= n_use_sc     + sc;
      n_sc_flip    <= n_sc_flip    + fl;
    end
  end

  // BP-121: a cycle trace for diagnosis, +TRACE. One line per event:
  // the p0 request, the p1 slots, the p2 and p3 groups the FTQ
  // accepted, the redirect that won, the fetch request, the predecode
  // redirect and the backend's redirect.
  logic trace;
  initial trace = $test$plusargs("TRACE");
  // Per FTQ index, the last TAGE p2 view of the watched block.
  logic [14:0] tg_prm [0:FTQ_DEPTH-1];
  logic        tg_tkn [0:FTQ_DEPTH-1];
  logic [11:0] tg_alc [0:FTQ_DEPTH-1];
  logic [7:0]  tg_ghr [0:FTQ_DEPTH-1];
  logic [1:0]  tg_sc  [0:FTQ_DEPTH-1];   // {SC answered, SC direction}
  // The block start whose TAGE view the trace prints (+WATCH=<hex>).
  logic [15:0] watch16;
  initial begin
    watch16 = '1;
    void'($value$plusargs("WATCH=%h", watch16));
  end

  // The 8 newest history bits below the pointer, newest first.
  function automatic logic [7:0] ghr_window(input logic [GHR_WIDTH-1:0] g,
                                            input logic [GHIST_PTR_BITS-1:0] p);
    logic [7:0] w;
    for (int k = 0; k < 8; k++)
      w[7-k] = g[(int'(p) - 1 - k + GHR_WIDTH) % GHR_WIDTH];
    return w;
  endfunction

  function automatic string slot_str(input bp_ftq_slot_t s);
    if (!s.slot_valid) return "-";
    return $sformatf("%0d/p%0d/%s/%0h/s%0d", s.br_type, s.pos,
                     s.taken ? "T" : "N", s.target[15:0], s.pred_src);
  endfunction

  always @(posedge clk) begin : trace_log
    if (trace && rstn) begin
      if (dut.ftq_pred_val_p0)
        $display("%0d P0 pc %0h idx %0d", cyc, dut.ftq_pred_pc_p0[15:0],
                 dut.ftq_pred_idx_p0);
      if (dut.bpu_pred_val_p1)
        $display("%0d P1 idx %0d ok %0d hit %0d pft %0h s0 %s s1 %s", cyc,
                 dut.bpu_pred_idx_p1, dut.u_ftq.w_ok_pred_p1,
                 dut.u_bpu.r_ubtb_blk_p1.hit, dut.bpu_pred_pft_p1[15:0],
                 slot_str(dut.bpu_pred_slot_p1[0]),
                 slot_str(dut.bpu_pred_slot_p1[1]));
      if (dut.u_bpu.r_val_p2)
        $display({"%0d P2 idx %0d ok %0d ftb %0d pft %0h s0 %s s1 %s",
                  " r %0d/%0h %0d/%0h ras t%0d w%0d b%0d"}, cyc,
                 dut.bpu_slot_idx_p2, dut.u_ftq.w_ok_blk_p2,
                 dut.bpu_slot_val_p2, dut.bpu_blk_pft_p2[15:0],
                 slot_str(dut.bpu_slot_p2[0]), slot_str(dut.bpu_slot_p2[1]),
                 dut.bpu_redir_p2[0].valid,
                 dut.bpu_redir_p2[0].target_pc[15:0],
                 dut.bpu_redir_p2[1].valid,
                 dut.bpu_redir_p2[1].target_pc[15:0],
                 dut.bpu_blk_ras_p2.tosr, dut.bpu_blk_ras_p2.tosw,
                 dut.bpu_blk_ras_p2.bos);
      if (dut.u_bpu.r_val_p3)
        $display("%0d P3 idx %0d ok %0d s0 %s s1 %s r %0d/%0h %0d/%0h", cyc,
                 dut.bpu_slot_idx_p3, dut.u_ftq.w_ok_slot_p3,
                 slot_str(dut.bpu_slot_p3[0]), slot_str(dut.bpu_slot_p3[1]),
                 dut.bpu_redir_p3[0].valid,
                 dut.bpu_redir_p3[0].target_pc[15:0],
                 dut.bpu_redir_p3[1].valid,
                 dut.bpu_redir_p3[1].target_pc[15:0]);
      if (dut.u_ftq.w_redir_val)
        $display({"%0d REDIR arm %b idx %0d self %0d pc %0h rb %0d/%0d",
                  " ras %0d/%0d/%0d"}, cyc,
                 dut.u_ftq.w_arm_win, dut.u_ftq.w_redir_idx,
                 dut.u_ftq.w_redir_self, dut.ftq_pred_pc_p0[15:0],
                 dut.ftq_rollback_val, dut.ftq_rollback_idx,
                 dut.ras_restore_snapshot.tosr,
                 dut.ras_restore_snapshot.tosw,
                 dut.ras_restore_snapshot.bos);
      if (dut.ftq_ifu_req_val && dut.ftq_ifu_req_rdy)
        $display("%0d FETCH idx %0d start %0h next %0h tk %0d/%0d", cyc,
                 dut.ftq_ifu_idx, dut.ftq_ifu_start_pc[15:0],
                 dut.ftq_ifu_next_pc[15:0], dut.ftq_ifu_taken_val,
                 dut.ftq_ifu_taken_pos);
      if (dut.ftb_upd_valid_u0)
        $display({"%0d FTBUPD pc %0h hit %0d way %0d br %0d/%0d tk %0d pos %0d",
                  " jmp %0d c%0d r%0d j%0d pft %0h tgt %0h"}, cyc,
                 dut.ftb_upd_pc_u0[15:0], dut.ftb_upd_hit_u0,
                 dut.ftb_upd_way_u0, dut.ftb_upd_is_br_u0,
                 dut.ftb_upd_br_idx_u0, dut.ftb_upd_taken_u0,
                 dut.ftb_upd_pos_u0, dut.ftb_upd_is_jmp_u0,
                 dut.ftb_upd_is_call_u0,
                 dut.ftb_upd_is_ret_u0, dut.ftb_upd_is_jalr_u0,
                 dut.ftb_upd_pft_addr_u0[15:0],
                 dut.ftb_upd_jmp_target_u0[15:0]);
      if (dut.ras_commit_val)
        $display("%0d RASCOMMIT %0d ret %0h", cyc, dut.ras_commit_br_type,
                 dut.ras_commit_ret_addr[15:0]);
      for (int t = 0; t < NUM_PRED_SLOTS; t++) begin
        if (dut.u_bpu.w_ittage_upd_val_u0[t])
          $display({"%0d ITUPD s%0d hit %0d prm %0d/%0h alc %0d/%0h/%0h",
                    " mis %0d tgt %0h ptgt %0h"}, cyc, t,
                   dut.ittage_upd_inp_u0[t].ittage_pred_meta.ittage_hit,
                   dut.ittage_upd_inp_u0[t].ittage_pred_meta.ittage_prm_comp,
                   dut.ittage_upd_inp_u0[t].ittage_pred_meta.ittage_prm_idx,
                   dut.ittage_upd_inp_u0[t].ittage_pred_meta.ittage_alc_comp,
                   dut.ittage_upd_inp_u0[t].ittage_pred_meta.ittage_alc_idx,
                   dut.ittage_upd_inp_u0[t].ittage_pred_meta.ittage_alc_tag,
                   dut.ittage_upd_inp_u0[t].indir_mispredict,
                   {dut.ittage_upd_inp_u0[t].resolved_target[14:0], 1'b0},
                   {dut.ittage_upd_inp_u0[t].ittage_pred_meta
                      .ittage_prm_tgt[14:0], 1'b0});
      end
      $display({"%0d TG p0v %0d p2v %0d idx2 %0d trdy %0d tbid %0d cr %0d",
                " scgu %0d pqnf %0d scr %0d"}, cyc,
               dut.u_bpu.w_req_val_p0, dut.u_bpu.r_val_p2, dut.u_bpu.r_idx_p2,
               dut.u_bpu.w_tage_pred_rdy_p2[0],
               dut.u_bpu.w_tage_pred_meta_p2[0].branch_id,
               dut.u_bpu.w_tage_consumer_ready, dut.u_bpu.w_sc_grant_upd,
               dut.u_bpu.tage_pq_not_full, dut.u_bpu.sc_ready);
      if (dut.u_bpu.r_val_p2 && (dut.u_bpu.r_pc_p2[15:0] == watch16))
        $display({"%0d TGP2 idx %0d rdy %0d bid %0d prm %0d/%0h alt %0d/%0h",
                  " ctr %0d tkn %0d alc %0d/%0h use_prm %0d ghp %0d ghr %b"},
                 cyc,
                 dut.u_bpu.r_idx_p2, dut.u_bpu.w_tage_pred_rdy_p2[0],
                 dut.u_bpu.w_tage_pred_meta_p2[0].branch_id,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_prm_comp,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_prm_idx,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_alt_comp,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_alt_idx,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_prm_ctr,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_pred_tkn,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_alc_comp,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_alc_idx,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_using_primary,
                 dut.bpu_ghist_ptr,
                 ghr_window(dut.bpu_ghr_buf, dut.bpu_ghist_ptr));
      if (dut.u_bpu.r_val_p2 && (dut.u_bpu.r_pc_p2[15:0] == watch16)) begin
        tg_prm[dut.u_bpu.r_idx_p2] <=
          {dut.u_bpu.w_tage_pred_meta_p2[0].tage_prm_comp,
           12'(dut.u_bpu.w_tage_pred_meta_p2[0].tage_prm_idx)};
        tg_tkn[dut.u_bpu.r_idx_p2] <=
          dut.u_bpu.w_tage_pred_meta_p2[0].tage_pred_tkn;
        tg_alc[dut.u_bpu.r_idx_p2] <=
          12'(dut.u_bpu.w_tage_pred_meta_p2[0].tage_alc_idx);
        tg_ghr[dut.u_bpu.r_idx_p2] <=
          ghr_window(dut.bpu_ghr_buf, dut.bpu_ghist_ptr);
      end
      if (dut.u_bpu.r_val_p3)
        tg_sc[dut.u_bpu.r_idx_p3] <= {dut.u_bpu.w_sc_hit_p3[0],
                                      dut.u_bpu.w_taken_p3[0]};
      for (int t = 0; t < NUM_PRED_SLOTS; t++) begin
        if (dut.u_bpu.w_tage_upd_val_u0[t])
          $display({"%0d TGUPD s%0d bid %0d prm %0d/%0h alc %0d/%0h tkn %0d",
                    " mis %0d"}, cyc, t,
                   dut.tage_upd_inp_u0[t].tage_pred_meta.branch_id,
                   dut.tage_upd_inp_u0[t].tage_pred_meta.tage_prm_comp,
                   dut.tage_upd_inp_u0[t].tage_pred_meta.tage_prm_idx,
                   dut.tage_upd_inp_u0[t].tage_pred_meta.tage_alc_comp,
                   dut.tage_upd_inp_u0[t].tage_pred_meta.tage_alc_idx,
                   dut.tage_upd_inp_u0[t].resolved_taken,
                   dut.tage_upd_inp_u0[t].cond_mispredict);
      end
      if (dut.u_bpu.r_val_p2 && dut.u_bpu.w_ittage_pred_rdy_p2[0])
        $display("%0d ITP2 idx %0d bid %0d hit %0d prm %0d/%0h alc %0d/%0h/%0h",
                 cyc, dut.u_bpu.r_idx_p2,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].branch_id,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].ittage_hit,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].ittage_prm_comp,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].ittage_prm_idx,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].ittage_alc_comp,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].ittage_alc_idx,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].ittage_alc_tag);
    end
  end

  // BP-121: every RAS commit the cluster performs (after its type
  // qualification), compared in order with the retired stream by the
  // backend below.
  always @(posedge clk) begin : ras_commit_log
    if (rstn && dut.u_bpu.w_ras_commit_val) begin
      rasev_t g;
      g.t  = dut.ras_commit_br_type;
      g.ra = dut.ras_commit_ret_addr;
      g.pc = '0;
      ras_got.push_back(g);
    end
  end

  always @(posedge clk) begin : upd_log
    if (meas) begin
      n_u_ubtb   <= n_u_ubtb
                  + $countones({dut.u_bpu.w_ubtb_upd_u0[1].valid,
                                dut.u_bpu.w_ubtb_upd_u0[0].valid});
      n_u_lp     <= n_u_lp     + $countones(dut.u_bpu.w_lp_upd_val_p0);
      n_u_tage   <= n_u_tage   + $countones(dut.u_bpu.w_tage_upd_val_u0);
      n_u_ittage <= n_u_ittage + $countones(dut.u_bpu.w_ittage_upd_val_u0);
      n_u_sc     <= n_u_sc     + $countones(dut.u_bpu.w_sc_upd_val_u0);
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        if (dut.u_bpu.w_ras_pred_val_p2[s] &&
            (dut.u_bpu.w_br_type_p2[s] == RETURN_CALL))
          n_rc_p2 <= n_rc_p2 + 1;
      end
      if (dut.u_bpu.w_ras_commit_val) n_u_ras <= n_u_ras + 1;
      if (dut.u_bpu.w_ras_commit_val &&
          (dut.ras_commit_br_type == RETURN_CALL))
        n_rc_commit <= n_rc_commit + 1;
      // A p2 or p3 redirect the FTQ accepted: the stage group is
      // live (w_ok_redir_*) and a slot of it redirects.
      if (dut.u_ftq.w_ok_redir_p2 &&
          (dut.bpu_redir_p2[0].valid || dut.bpu_redir_p2[1].valid))
        n_redir_p2 <= n_redir_p2 + 1;
      if (dut.u_ftq.w_ok_redir_p3 &&
          (dut.bpu_redir_p3[0].valid || dut.bpu_redir_p3[1].valid))
        n_redir_p3 <= n_redir_p3 + 1;
      // A resolution whose position names no slot of its entry
      // (ftq_resolve rsv_nomap): it forms no update of any kind.
      if (dut.u_ftq.w_rsv_nomap[0] && ftq_bkend_rsv_rdy[0])
        n_nomap <= n_nomap + 1;
      // BP-120, TD#156: an FTB jump update that hits an entry whose
      // jump field holds a jump at a different region position. Since
      // BP-120 the field is replaced; before, it kept the stored
      // position. Read from ftb_cntrl's update decode: the carried
      // way's readback and the update's region position.
      if (dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_upd_valid_u0 &&
          dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_upd_is_jmp_u0 &&
`ifdef BASE_RTL
          dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_upd_hit_u0 &&
`else
          dut.u_bpu.u_ftb.u_ftb_cntrl.upd_hit &&
`endif
          dut.u_bpu.u_ftb.u_ftb_cntrl.upd_old.jmp.valid &&
          (dut.u_bpu.u_ftb.u_ftb_cntrl.upd_old.jmp.pos !=
           dut.u_bpu.u_ftb.u_ftb_cntrl.upd_rpos))
        n_jmp_swap <= n_jmp_swap + 1;
    end
  end

  // =================================================================
  // The backend model.
  // =================================================================
  int                      ep;          // next expected entry
  logic                    run_be;      // take decode's output
  logic                    cfi_pend;    // last retired is a CFI
  int                      cfi_e;
  logic [FTQ_IDX_BITS-1:0] cfi_idx;
  logic [3:0]              cfi_pos;
  logic                    after_redir; // next retired starts an entry
  logic [FTQ_PTR_BITS-1:0] redir_next;  // its pointer
  logic                    cur_val;
  logic [FTQ_PTR_BITS-1:0] cur_ptr;
  logic                    wm_val;
  logic [FTQ_PTR_BITS-1:0] wm;
  int                      n_retired;
  int                      n_mispred;
  int                      n_trap;
  int                      n_err;
  int                      n_fault_ok;
  // BP-120: backend mispredicts of a return or a return-call, and of
  // the instruction at watch_pc (a program sets it; zero matches none).
  int                      n_mis_ras;
  int                      n_mis_watch;
  logic [VA_WIDTH-1:0]     watch_pc;
  // BP-121: mispredicts after warm-up, by branch type (indexed by the
  // bp_br_type_e encoding) and by PC; the PC's type is kept for the
  // report.
  int                      n_mis_warm;
  int                      n_mis_type [0:7];
  int                      mis_pc  [logic [VA_WIDTH-1:0]];
  bp_br_type_e             mis_typ [logic [VA_WIDTH-1:0]];
  // A resolution queue, presented on port 0.
  ftq_resolve_t            rq [0:255];
  int                      rq_hd;
  int                      rq_tl;
  // The redirect to present next cycle.
  logic                    rd_pend;
  logic [FTQ_IDX_BITS-1:0] rd_idx;
  logic [3:0]              rd_pos;
  logic [VA_WIDTH-1:0]     rd_pc;
  logic                    rd_self;
  ftq_redir_cause_e        rd_cause;
  logic                    rd_taken;
  // BP-121, the corrected history: a backend mispredict redirect of a
  // conditional was driven last cycle (h_chk), with its direction.
  // After the rollback the newest history bit must be that direction.
  logic                    rd_cond;
  logic                    h_chk;
  logic                    h_dir;
  int                      n_hist_ok;
  int                      n_hist_bad;
  // BP-123. The commit stage's maintenance: an operation retired and
  // waiting for its ack (mt_pend), presented and not yet taken
  // (mt_req), and the restart it holds. Delivery is not taken while
  // one is pending: the restart follows the ack (A1).
  logic                    mt_pend;
  logic                    mt_req;
  int                      mt_e;
  logic [FTQ_IDX_BITS-1:0] mt_idx;
  logic [3:0]              mt_pos;
  int                      n_maint;
  int                      n_maint_drain;   // L1I busy when it took one
  // Eager commit: commit the entry of the last retired instruction as
  // soon as nothing is in flight to the backend, and resolve a branch
  // that ended its block without waiting for the next instruction.
  // Uncached fetch needs it (IFU-22: an entry waits for every older one
  // to commit). Off for the BP-121 programs, so their timing is
  // unchanged.
  logic                    eager;
  logic                    cm_all;      // every retired entry committed
  int                      n_eager_res;
  int                      n_patch;
  int                      n_csrw;
  // BP-124, pt_upriv: the page up_vpn's walks and the ITLB's ITLB-10b
  // drop of a held fault for it.
  logic [VA_WIDTH-13:0]    up_vpn;
  logic                    up_wval;     // a walk for up_vpn in progress
  logic [1:0]              up_wpriv;    //   its privilege
  int                      n_up_wu_flt; // walks at U answered fault
  int                      n_up_ws_hit; // walks at S answered hit
  int                      n_up_drop;   // held faults dropped (ITLB-10b)

  // =================================================================
  // BP-124, pt_upriv. The walks for up_vpn by privilege, from the walk
  // port (one walk at a time, MMU-U2, so the next answer that is not a
  // retry is this walk's), and the ITLB's drop of a held fault for it:
  // a re-request answered miss while a fault held for up_vpn at another
  // privilege or V is dropped (itlb.sv w_rq_miss, w_flt_drop).
  // =================================================================
  always @(posedge clk) begin
    if (rstn && itlb_l2t_req_val && itlb_l2t_req_rdy &&
        (itlb_l2t_vpn == up_vpn)) begin
      up_wval  <= 1'b1;
      up_wpriv <= itlb_l2t_priv;
    end
    if (rstn && up_wval && l2t_itlb_rsp_val && (l2t_itlb_status != 2'b10))
    begin
      up_wval <= 1'b0;
      if ((up_wpriv == 2'd0) && (l2t_itlb_status == 2'b01))
        n_up_wu_flt <= n_up_wu_flt + 1;
      if ((up_wpriv == 2'd1) && (l2t_itlb_status == 2'b00))
        n_up_ws_hit <= n_up_ws_hit + 1;
    end
    if (rstn && dut.u_itlb.w_rq_miss && (dut.u_itlb.w_flt_drop != '0) &&
        (dut.u_itlb.r_rq_vpn == up_vpn))
      n_up_drop <= n_up_drop + 1;
  end

  // =================================================================
  // BP-123, Problem 4. Every cycle of every program:
  //   - an uncached L1I request is presented only when every retired
  //     instruction's entry has been committed, and only for the line
  //     of the next instruction to retire, or the line after it
  //     (IFU-22: nothing older is uncommitted; nothing off the path)
  //   - no fill is written into the L1I array for a line on an NC or
  //     IO page (L1I-24, MMU-14)
  //   - an ibuf transfer holding an instruction from an NC or IO page
  //     holds that one instruction alone (IFU-23), and every retired
  //     instruction's entry has committed
  // The sources are the testbench's own: its retirement and commit
  // state, its page attributes and its expected stream.
  // =================================================================
  int n_uc_req;
  int n_uc_bad;
  int n_uc_fill_bad;
  int n_uc_dlv;
  int n_uc_dlv_bad;

  function automatic logic [PA_WIDTH-1:L1I_OFFSET_BITS] va_line(
      input logic [VA_WIDTH-1:0] va);
    logic [VA_WIDTH-13:0] v;
    logic [PA_WIDTH-1:0]  pa;
    v = va[VA_WIDTH-1:12];
    if ((W.sv39 || W.h2) && !W.vmap.exists(v)) return '1;
    pa = W.va2pa(va);
    return pa[PA_WIDTH-1:L1I_OFFSET_BITS];
  endfunction

  initial begin : uc_checks
    logic [PA_WIDTH-1:L1I_OFFSET_BITS] rl;
    logic [VA_WIDTH-1:0]               pc;
    int                                n;
    logic                              uc;
    forever begin
    @(posedge clk);
    if (rstn && run_be) begin
      if (dut.ifu_l1i_req_val && dut.ifu_l1i_req_uncached) begin
        n_uc_req++;
        rl = dut.ifu_l1i_req_paddr[PA_WIDTH-1:L1I_OFFSET_BITS];
        pc = W.ex[(ep < W.ne) ? ep : 0].pc;
        if (!cm_all || (ep >= W.ne) ||
            !((rl == va_line(pc)) ||
              (rl == va_line({pc[VA_WIDTH-1:6], 6'd0} + VA_WIDTH'(64))))) begin
          n_uc_bad++;
          if (n_uc_bad <= 4)
            $display("%s", $sformatf(
              {"ERROR: [%s] uncached request %09h: committed %0d, ",
               "next pc %011h"}, tname, dut.ifu_l1i_req_paddr, cm_all, pc));
        end
      end
      for (int b = 0; b < 2; b++) begin
        if (dut.u_l1i.u_mshr.b_fil_valid[b] &&
            W.uc_ppn.exists(
              dut.u_l1i.u_mshr.b_fil_line[b][PA_WIDTH-1:12])) begin
          n_uc_fill_bad++;
          $display("ERROR: [%s] an uncached line %09h was written into the L1I",
                   tname, dut.u_l1i.u_mshr.b_fil_line[b]);
        end
      end
      if (dut.ifu_ibuf_val && dut.ibuf_ifu_rdy) begin
        n  = 0;
        uc = 1'b0;
        for (int i = 0; i < FTQ_PD_WIDTH; i++) begin
          if (dut.ifu_ibuf_en[i]) begin
            n++;
            if (W.uc_vpn.exists(dut.ifu_ibuf_slot[i].start_pc[VA_WIDTH-1:12]))
              uc = 1'b1;
          end
        end
        if (uc) begin
          n_uc_dlv++;
          if ((n != 1) || !cm_all) begin
            n_uc_dlv_bad++;
            $display("%s", $sformatf(
              {"ERROR: [%s] uncached delivery of %0d instructions, ",
               "committed %0d"}, tname, n, cm_all));
          end
        end
      end
    end
    end
  end

  // The taken target of a conditional, from its (expanded) B-type
  // encoding: pc + the sign-extended immediate.
  function automatic logic [VA_WIDTH-1:0] br_target(
      input logic [VA_WIDTH-1:0] pc, input logic [31:0] w);
    logic [12:0] imm;
    imm = {w[31], w[7], w[30:25], w[11:8], 1'b0};
    return pc + {{(VA_WIDTH-13){imm[12]}}, imm};
  endfunction

  // A resolution carries the RESOLVED TAKEN TARGET of a conditional
  // whatever its direction (ftb_decisions.md 5.5, "conditional target:
  // rewrite if the resolved taken target differs"). BP-121: before, a
  // not-taken conditional resolved with its fall-through as target, so
  // the FTB stored the fall-through and the next taken instance of the
  // branch was fetched to it (hist: the alternating branch).
  task automatic resolve(input int e, input logic [FTQ_IDX_BITS-1:0] idx,
                         input logic [3:0] pos, input logic mis);
    rq[rq_tl % 256].ftq_idx    = idx;
    rq[rq_tl % 256].pos        = pos;
    rq[rq_tl % 256].taken      = W.ex[e].taken;
    rq[rq_tl % 256].target     = (W.ex[e].btype == COND)
                               ? br_target(W.ex[e].pc, W.ex[e].instr)
                               : W.ex[e].target;
    rq[rq_tl % 256].br_type    = W.ex[e].btype;
    rq[rq_tl % 256].mispredict = mis;
`ifndef BASE_RTL
    rq[rq_tl % 256].is_rvc     = W.ex[e].rvc;
`endif
    rq_tl++;
  endtask

  // The entry pointer of a retired instruction (FTQ_PTR_BITS, the
  // commit watermark's width). A redirect fixes the next one; past
  // that, a new index advances the pointer by its distance.
  task automatic track_entry(input logic [FTQ_IDX_BITS-1:0] idx);
    logic [FTQ_PTR_BITS-1:0] np;
    if (after_redir) begin
      np = redir_next;
      if (np[FTQ_IDX_BITS-1:0] != idx) begin
        n_err++;
        $display("ERROR: [%s] first index after a redirect %0d, exp %0d",
                 tname, idx, np[FTQ_IDX_BITS-1:0]);
      end
      cur_ptr     = np;
      cur_val     = 1'b1;
      after_redir = 1'b0;
      wm          = np - FTQ_PTR_BITS'(1);
      wm_val      = (np != '0) || wm_val;
    end else if (!cur_val) begin
      cur_ptr = {1'b0, idx};
      cur_val = 1'b1;
    end else if (idx != cur_ptr[FTQ_IDX_BITS-1:0]) begin
      np      = cur_ptr + FTQ_PTR_BITS'(FTQ_IDX_BITS'(idx -
                cur_ptr[FTQ_IDX_BITS-1:0]));
      wm      = np - FTQ_PTR_BITS'(1);
      wm_val  = 1'b1;
      cur_ptr = np;
    end
  endtask

  task automatic redirect(input logic [FTQ_IDX_BITS-1:0] idx,
                          input logic [3:0] pos,
                          input logic [VA_WIDTH-1:0] pc,
                          input logic self, input ftq_redir_cause_e c);
    logic [FTQ_PTR_BITS-1:0] kp;
    rd_pend  = 1'b1;
    rd_idx   = idx;
    rd_pos   = pos;
    rd_pc    = pc;
    rd_self  = self;
    rd_cause = c;
    rd_taken = 1'b0;
    rd_cond  = 1'b0;
    // The pointer of entry idx: the current entry's, or one behind it
    // for a mispredict named by the previous entry's branch.
    kp = cur_ptr - FTQ_PTR_BITS'(FTQ_IDX_BITS'(cur_ptr[FTQ_IDX_BITS-1:0]
                                                - idx));
    redir_next  = self ? kp : kp + FTQ_PTR_BITS'(1);
    after_redir = 1'b1;
    // Every entry before the restart point has retired.
    wm     = redir_next - FTQ_PTR_BITS'(1);
    wm_val = 1'b1;
  endtask

  initial begin : backend
    ifu_pd_pkt_t s;
    decode_pkt_t d;
    logic        stop;
    logic        prsnt;
    bkend_ftq_redir_val   = 1'b0;
    bkend_ftq_redir_idx   = '0;
    bkend_ftq_redir_pos   = '0;
    bkend_ftq_redir_pc    = '0;
    bkend_ftq_redir_self  = 1'b0;
    bkend_ftq_redir_cause = RC_MISPREDICT;
    bkend_ftq_redir_taken = 1'b0;
    bkend_ftq_commit_val  = 1'b0;
    bkend_ftq_commit_idx  = '0;
    bkend_ftq_rsv_val     = '0;
    bkend_ftq_rsv[0]      = '0;
    bkend_ftq_rsv[1]      = '0;
    dec_ibuf_rdy          = 1'b0;
    cmt_ifu_maint_val     = 1'b0;
    cmt_ifu_maint_op      = 1'b0;
    cmt_ifu_maint_paddr   = '0;
    forever begin
      @(posedge clk);
      // ---- sample at the edge -----------------------------------
      if (rstn && bkend_ftq_rsv_val[0] && ftq_bkend_rsv_rdy[0]) rq_hd++;
      stop  = 1'b0;
      prsnt = rstn && run_be && dec_ibuf_rdy && !bkend_ftq_redir_val &&
              !mt_pend;
      // BP-123: the maintenance handshake, sampled at the edge.
      if (rstn && mt_req && cmt_ifu_maint_val && cmt_ifu_maint_rdy)
        mt_req = 1'b0;
      // An invalidate the L1I took with fills in flight: the drain of
      // IF-31 had something to wait for.
      if (rstn && dut.ifu_l1i_inv_val && dut.ifu_l1i_inv_rdy &&
          dut.u_l1i.mt_busy_any)
        n_maint_drain++;
      if (rstn && mt_pend && !mt_req && ifu_cmt_maint_ack) begin
        mt_pend = 1'b0;
        stop    = 1'b1;
        redirect(mt_idx, mt_pos, W.ex[mt_e].pc + VA_WIDTH'(4), 1'b1,
                 RC_REPLAY);
      end
      // BP-123, eager mode. With nothing presented this cycle, a branch
      // that ended its block is resolved against the block the FTQ
      // fetched after it (its predicted successor), once that block was
      // fetched after the branch's own writeback, as a backend resolves
      // a branch against the FTQ's predicted target. Then the entry of
      // the last retired instruction commits.
      if (prsnt && eager && !pd_out[0].valid && cfi_pend && (ep < W.ne) &&
          fseen[FTQ_IDX_BITS'(cfi_idx + 1)] && wbseen[cfi_idx]) begin
        n_eager_res++;
        if (fstart[FTQ_IDX_BITS'(cfi_idx + 1)] == W.ex[ep].pc) begin
          resolve(cfi_e, cfi_idx, cfi_pos, 1'b0);
          cfi_pend = 1'b0;
        end else begin
          n_mispred++;
          if (cfi_e >= warm_e) begin
            n_mis_warm++;
            n_mis_type[int'(W.ex[cfi_e].btype)]++;
          end
          resolve(cfi_e, cfi_idx, cfi_pos, 1'b1);
          cfi_pend = 1'b0;
          redirect(cfi_idx, cfi_pos, W.ex[ep].pc, 1'b0, RC_MISPREDICT);
          rd_taken = W.ex[cfi_e].taken;
          rd_cond  = (W.ex[cfi_e].btype == COND);
          stop     = 1'b1;
        end
      end
      if (prsnt && eager && !pd_out[0].valid && !cfi_pend && cur_val &&
          !after_redir) begin
        wm     = cur_ptr;
        wm_val = 1'b1;
      end
      if (prsnt) begin
        for (int i = 0; i < SLOTS; i++) begin
          s = pd_out[i];
          d = decode_bundle[i];
          if (!s.valid || stop) continue;
          if (ep >= W.ne) continue;                 // past the end
          if (s.start_pc != W.ex[ep].pc) begin
            stop = 1'b1;
            // A direct jump or call never has a wrong path after it:
            // predecode truncates the bundle at a JAL (M1, M3, IB-2),
            // so what follows one is its target. Only a conditional's
            // direction and an indirect's target can be wrong here.
            if (cfi_pend && ((W.ex[cfi_e].btype == DIRECT_UNC) ||
                             (W.ex[cfi_e].btype == DIRECT_CALL))) begin
              n_err++;
              $display("ERROR: [%s] pc %011h after a JAL at %011h",
                       tname, s.start_pc, W.ex[cfi_e].pc);
            end else if (cfi_pend) begin
              if (trace)
                $display("%0d MISP pc %0h act %0d got %0h exp %0h e %0d", cyc,
                         W.ex[cfi_e].pc[15:0], W.ex[cfi_e].taken,
                         s.start_pc[15:0], W.ex[ep].pc[15:0], cfi_e);
              n_mispred++;
              if ((W.ex[cfi_e].btype == RETURN) ||
                  (W.ex[cfi_e].btype == RETURN_CALL))
                n_mis_ras++;
              if (W.ex[cfi_e].pc == watch_pc) n_mis_watch++;
              if (cfi_e >= warm_e) begin
                n_mis_warm++;
                n_mis_type[int'(W.ex[cfi_e].btype)]++;
                if (mis_pc.exists(W.ex[cfi_e].pc))
                  mis_pc[W.ex[cfi_e].pc]++;
                else
                  mis_pc[W.ex[cfi_e].pc] = 1;
                mis_typ[W.ex[cfi_e].pc] = W.ex[cfi_e].btype;
              end
              resolve(cfi_e, cfi_idx, cfi_pos, 1'b1);
              cfi_pend = 1'b0;
              redirect(cfi_idx, cfi_pos, W.ex[ep].pc, 1'b0, RC_MISPREDICT);
              // The resolved direction rides with the redirect (BP-121).
              rd_taken = W.ex[cfi_e].taken;
              rd_cond  = (W.ex[cfi_e].btype == COND);
            end else begin
              n_err++;
              $display("%s", $sformatf(
                {"ERROR: [%s] stream: got pc %011h exp %011h ",
                 "(entry %0d), not after a control transfer"},
                tname, s.start_pc, W.ex[ep].pc, ep));
            end
            continue;
          end
          // The expected instruction.
          if (trace) $display("%0d RETIRE %0h idx %0d pos %0d e %0d", cyc,
                              s.start_pc[15:0], s.ftq_idx, s.pos, ep);
          if (trace && (W.ex[ep].btype == COND) &&
              (fstart[s.ftq_idx][15:0] == watch16))
            $display({"%0d WBR pc %0h act %0d tage %0d sc %b prm %0d/%0h",
                      " alc %0h ghr %b"}, cyc,
                     s.start_pc[15:0], W.ex[ep].taken, tg_tkn[s.ftq_idx],
                     tg_sc[s.ftq_idx],
                     tg_prm[s.ftq_idx][14:12], tg_prm[s.ftq_idx][11:0],
                     tg_alc[s.ftq_idx], tg_ghr[s.ftq_idx]);
          n_retired++;
          if (cfi_pend) begin
            resolve(cfi_e, cfi_idx, cfi_pos, 1'b0);
            cfi_pend = 1'b0;
          end
          track_entry(s.ftq_idx);
          // A faulting slot has no encoding; no document says what
          // its is_rvc holds (reported, BP-118), so it is not checked.
          if ((W.ex[ep].fault == IFU_FAULT_NONE) &&
              (s.is_rvc != W.ex[ep].rvc)) begin
            n_err++;
            $display("ERROR: [%s] pc %011h is_rvc %0d", tname, s.start_pc,
                     s.is_rvc);
          end
          if (d.is_illegal) begin
            n_err++;
            $display("ERROR: [%s] pc %011h decode raised illegal", tname,
                     s.start_pc);
          end
          // BP-123: decode's operation, where the program names one.
          if ((W.ex[ep].aluop >= 0) && (int'(d.alu_op) != W.ex[ep].aluop)) begin
            n_err++;
            $display("ERROR: [%s] pc %011h instr %08h alu_op %0d exp %0d",
                     tname, s.start_pc, s.instr, d.alu_op, W.ex[ep].aluop);
          end
          // BP-123: predecode classes a non-control-transfer as none
          // (prefetch.i is an ORI, Zicbop).
          if ((W.ex[ep].fault == IFU_FAULT_NONE) &&
              (W.ex[ep].btype == NO_BRANCH) && !W.ex[ep].trap &&
              (s.br_type != 2'b00)) begin
            n_err++;
            $display("ERROR: [%s] pc %011h instr %08h predecode class %0d",
                     tname, s.start_pc, s.instr, s.br_type);
          end
          if (fstart[s.ftq_idx] + VA_WIDTH'(2 * int'(s.pos)) != s.start_pc)
          begin
            n_err++;
            $display("%s", $sformatf(
              {"ERROR: [%s] pc %011h ftq_idx %0d pos %0d does not ",
               "name its block (start %011h)"}, tname, s.start_pc,
              s.ftq_idx, s.pos, fstart[s.ftq_idx]));
          end
          if (W.ex[ep].fault != IFU_FAULT_NONE) begin
            if ((s.fault_cause != W.ex[ep].fault) ||
                (s.fault_va != W.ex[ep].fva) ||
                ((W.ex[ep].fault == IFU_FAULT_GUEST_PAGE) &&
                 ((s.fault_gpa != W.ex[ep].fgpa) ||
                  (s.fault_gpa_imp != W.ex[ep].fimp)))) begin
              n_err++;
              $display("%s", $sformatf(
                {"ERROR: [%s] pc %011h fault %0d va %011h gpa %011h ",
                 "kind %0d; expected %0d %011h %011h %0d"}, tname,
                s.start_pc, s.fault_cause, s.fault_va, s.fault_gpa,
                s.fault_gpa_imp, W.ex[ep].fault, W.ex[ep].fva,
                W.ex[ep].fgpa, W.ex[ep].fimp));
            end else begin
              n_fault_ok++;
            end
            n_trap++;
            stop = 1'b1;
            // BP-124: a trap taken to S (pt_upriv).
            if (W.ex[ep].npriv >= 0) csr_itlb_priv = 2'(W.ex[ep].npriv);
            redirect(s.ftq_idx, s.pos, W.ex[ep].target, 1'b1, RC_TRAP);
            ep++;
            continue;
          end
          if ((s.fault_cause != IFU_FAULT_NONE) ||
              (s.instr != W.ex[ep].instr)) begin
            n_err++;
            $display("ERROR: [%s] pc %011h instr %08h exp %08h fault %0d",
                     tname, s.start_pc, s.instr, W.ex[ep].instr,
                     s.fault_cause);
          end
          if (W.ex[ep].trap) begin
            n_trap++;
            stop = 1'b1;
            // BP-124: an ecall to S or an sret to U (pt_upriv).
            if (W.ex[ep].npriv >= 0) csr_itlb_priv = 2'(W.ex[ep].npriv);
            redirect(s.ftq_idx, s.pos, W.ex[ep].target, 1'b1, RC_TRAP);
            ep++;
            continue;
          end
          // BP-123. A store's memory effect lands as it retires.
          for (int k = 0; k < W.ex[ep].pn; k++) begin
            W.mem[W.pat_a[W.ex[ep].p0 + k]] =
              W.pat_h[W.ex[ep].p0 + k][7:0];
            W.mem[W.pat_a[W.ex[ep].p0 + k] + PA_WIDTH'(1)] =
              W.pat_h[W.ex[ep].p0 + k][15:8];
            n_patch++;
          end
          // BP-123. FENCE.I or cbo.inval: nothing after it is taken
          // until the IFU acknowledges, then fetch restarts after it
          // (l1i_ifu_interfaces.md 11, A1).
          if (W.ex[ep].maint == 3) begin
            // A CSR write: the new envcfg bits, then the restart.
            csr_ptw_menvcfg_adue  = W.act_madue[W.ex[ep].p0];
            csr_ptw_henvcfg_adue  = W.act_hadue[W.ex[ep].p0];
            csr_ptw_menvcfg_pbmte = W.act_mpbmte[W.ex[ep].p0];
            csr_ptw_henvcfg_pbmte = W.act_hpbmte[W.ex[ep].p0];
            n_csrw++;
            stop = 1'b1;
            redirect(s.ftq_idx, s.pos, W.ex[ep].pc + VA_WIDTH'(4), 1'b1,
                     RC_REPLAY);
            ep++;
            continue;
          end
          if (W.ex[ep].maint != 0) begin
            stop    = 1'b1;
            mt_pend = 1'b1;
            mt_req  = 1'b1;
            mt_e    = ep;
            mt_idx  = s.ftq_idx;
            mt_pos  = s.pos;
            n_maint++;
            ep++;
            continue;
          end
          if (W.ex[ep].btype != NO_BRANCH) begin
            cfi_pend = 1'b1;
            cfi_e    = ep;
            cfi_idx  = s.ftq_idx;
            cfi_pos  = s.pos;
          end
          // The architectural RAS operation of this instruction, if any
          // (ras_decisions.md 2): a call pushes its link, the address
          // after it; a return pops; a return-call pops then pushes.
          if ((W.ex[ep].btype == DIRECT_CALL)   ||
              (W.ex[ep].btype == INDIRECT_CALL) ||
              (W.ex[ep].btype == RETURN)        ||
              (W.ex[ep].btype == RETURN_CALL)) begin
            rasev_t ev;
            ev.t  = W.ex[ep].btype;
            ev.pc = W.ex[ep].pc;
            ev.ra = W.ex[ep].pc + (W.ex[ep].rvc ? VA_WIDTH'(2) : VA_WIDTH'(4));
            ras_exp.push_back(ev);
          end
          ep++;
        end
      end
      #1;
      // ---- the RAS commit check (BP-121) ------------------------
      while ((ras_got.size() > 0) && (ras_exp.size() > 0)) begin
        rasev_t g;
        rasev_t x;
        g = ras_got.pop_front();
        x = ras_exp.pop_front();
        if ((g.t != x.t) ||
            ((x.t != RETURN) && (g.ra != x.ra))) begin
          n_ras_bad++;
          if (n_ras_bad <= 4) $display("%s", $sformatf(
            {"ERROR: [%s] RAS commit %0d ret %011h, expected %0d ret ",
             "%011h (the instruction at %011h)"}, tname, g.t, g.ra, x.t,
            x.ra, x.pc));
        end else begin
          n_ras_ok++;
        end
      end
      if (ras_got.size() > 0) begin
        rasev_t g;
        g = ras_got.pop_front();
        n_ras_bad++;
        if (n_ras_bad <= 4)
          $display("ERROR: [%s] RAS commit %0d ret %011h with none retired",
                   tname, g.t, g.ra);
      end
      meas = rstn && run_be && (ep < W.ne);
      // ---- the history check (BP-121) --------------------------
      if (h_chk) begin
        if (dut.bpu_ghr_buf[dut.bpu_ghist_ptr - GHIST_PTR_BITS'(1)] == h_dir)
          n_hist_ok++;
        else
          n_hist_bad++;
      end
      h_chk = rd_pend && rd_cond && (rd_cause == RC_MISPREDICT) && !rd_self;
      h_dir = rd_taken;
      // ---- BP-123: the invalidate-during-a-walk trigger ----------
      bkend_itlb_inv_val = 1'b0;
      if (rstn && inv_watch && (inv_at < 0) && itlb_l2t_req_val &&
          itlb_l2t_req_rdy && (itlb_l2t_vpn == inv_vpn))
        inv_at = cyc + 4;
      if (rstn && (inv_at >= 0) && (cyc >= inv_at)) begin
        bkend_itlb_inv_val    = 1'b1;
        bkend_itlb_inv_op     = 2'd0;              // VMA, all
        bkend_itlb_inv_rs1_nz = 1'b0;
        bkend_itlb_inv_rs2_nz = 1'b0;
        inv_at    = -1;
        inv_watch = 1'b0;
        n_inv_fired++;
        if (u_ptw.r_st != u_ptw.S_IDLE) n_inv_busy++;
      end
      // ---- drive for the next cycle -----------------------------
      bkend_ftq_redir_val = rd_pend;
      if (rd_pend) begin
        bkend_ftq_redir_idx   = rd_idx;
        bkend_ftq_redir_pos   = rd_pos;
        bkend_ftq_redir_pc    = rd_pc;
        bkend_ftq_redir_self  = rd_self;
        bkend_ftq_redir_cause = rd_cause;
        bkend_ftq_redir_taken = rd_taken;
      end
      rd_pend = 1'b0;
      // BP-121: an entry commits only after the resolutions of its
      // branches were accepted (a branch resolves before it retires).
      // The commit walk reads the entry's resolved slots (ftq_resolve
      // writes them), so the watermark waits while the resolution
      // queue holds anything.
      if (rq_hd == rq_tl) begin
        bkend_ftq_commit_val = wm_val;
        bkend_ftq_commit_idx = wm;
      end
      bkend_ftq_rsv_val[0] = (rq_hd != rq_tl);
      bkend_ftq_rsv[0]     = rq[rq_hd % 256];
      dec_ibuf_rdy         = rstn && run_be && !mt_pend;
      // BP-123.
      cmt_ifu_maint_val    = mt_req;
      cmt_ifu_maint_op     = (W.ex[mt_e].maint == 1) ? MAINT_FENCE_I
                                                     : MAINT_CBO_INVAL;
      cmt_ifu_maint_paddr  = W.ex[mt_e].mpa;
      // Every entry with a retired instruction has been committed (as
      // driven to the FTQ this cycle).
      cm_all = !cur_val ||
               (wm_val && bkend_ftq_commit_val &&
                (bkend_ftq_commit_idx == wm) &&
                (after_redir || (wm == cur_ptr)));
    end
  end

  // =================================================================
  // Scaffolding.
  // =================================================================
  task automatic reset_all(input logic use_sv39);
    rstn         = 1'b0;
    run_be       = 1'b0;
    W.ne           = 0;
    ep           = 0;
    cfi_pend     = 1'b0;
    after_redir  = 1'b0;
    cur_val      = 1'b0;
    cur_ptr      = '0;
    wm_val       = 1'b0;
    wm           = '0;
    n_retired    = 0;
    n_mispred    = 0;
    n_trap       = 0;
    n_err        = 0;
    n_fault_ok   = 0;
    n_mis_ras    = 0;
    n_mis_watch  = 0;
    watch_pc     = '0;
    n_mis_warm   = 0;
    for (int t = 0; t < 8; t++) n_mis_type[t] = 0;
    mis_pc.delete();
    mis_typ.delete();
    ras_exp.delete();
    ras_got.delete();
    n_ras_ok     = 0;
    n_ras_bad    = 0;
    n_hist_ok    = 0;
    n_hist_bad   = 0;
    h_chk        = 1'b0;
    h_dir        = 1'b0;
    warm_e       = 0;
    W.dry          = 1'b0;
    meas         = 1'b0;
    n_use_ubtb   = 0;
    n_use_lp     = 0;
    n_use_lp2    = 0;
    n_lp_kept    = 0;
    n_lp_bad     = 0;
    n_use_ftb    = 0;
    n_use_tage   = 0;
    n_use_sc     = 0;
    n_sc_flip    = 0;
    n_use_ittage = 0;
    n_use_ras    = 0;
    n_u_ftb      = 0;
    n_tage_ok    = 0;
    n_tage_late  = 0;
    n_it_ok      = 0;
    n_it_late    = 0;
    n_sc_ok      = 0;
    n_sc_late    = 0;
    n_p2_blk     = 0;
    n_hist_mis   = 0;
    n_ftb_drop   = 0;
    n_ras_sq     = 0;
    n_p3_no_p2   = 0;
    n_p3_rep     = 0;
    n_rest_rep   = 0;
    n_own_ok     = 0;
    n_own_bad    = 0;
    n_jmp_swap   = 0;
    n_fills      = 0;
    n_walks      = 0;
    n_pd_redir   = 0;
    n_u_ubtb     = 0;
    n_u_lp       = 0;
    n_u_tage     = 0;
    n_u_ittage   = 0;
    n_u_sc       = 0;
    n_u_ras      = 0;
    n_rc_p2      = 0;
    n_rc_commit  = 0;
    n_redir_p2   = 0;
    n_redir_p3   = 0;
    n_nomap      = 0;
    rq_hd        = 0;
    rq_tl        = 0;
    rd_pend      = 1'b0;
    // BP-123.
    mt_pend       = 1'b0;
    mt_req        = 1'b0;
    mt_e          = 0;
    n_maint       = 0;
    n_maint_drain = 0;
    eager         = 1'b0;
    cm_all        = 1'b1;
    n_eager_res   = 0;
    n_patch       = 0;
    n_csrw        = 0;
    up_vpn        = '1;
    up_wval       = 1'b0;
    up_wpriv      = '0;
    n_up_wu_flt   = 0;
    n_up_ws_hit   = 0;
    n_up_drop     = 0;
    n_uc_req      = 0;
    n_uc_bad      = 0;
    n_uc_fill_bad = 0;
    n_uc_dlv      = 0;
    n_uc_dlv_bad  = 0;
    n_pw_acc      = 0;
    n_pw_cas      = 0;
    n_pw_err      = 0;
    n_pw_chg      = 0;
    n_pw_bad      = 0;
    pw_lat_min    = 2;
    pw_lat_max    = 2;
    pw_rdy_pat    = 0;
    err_arm       = 1'b0;
    err_pa        = '0;
    chg_arm       = 1'b0;
    chg_pa        = '0;
    chg_val       = '0;
    W.pat_a.delete();
    W.pat_h.delete();
    W.act_madue.delete();
    W.act_hadue.delete();
    W.act_mpbmte.delete();
    W.act_hpbmte.delete();
    W.patching    = 1'b0;
    W.nowrite     = 1'b0;
    W.uc_ppn.delete();
    W.uc_vpn.delete();
    W.h2          = 1'b0;
    W.g_bare      = 1'b0;
    W.gmap.delete();
    walk_lo       = '0;
    walk_hi       = '0;
    n_walk_rng    = 0;
    walk2_lo      = '0;
    walk2_hi      = '0;
    n_walk_rng2   = 0;
    inv_watch     = 1'b0;
    inv_vpn       = '0;
    inv_at        = -1;
    n_inv_fired   = 0;
    n_inv_busy    = 0;
    W.mem.delete();
    W.vmap.delete();
    W.sv39         = use_sv39;
    W.satp_root    = PA_WIDTH'('h0_8F00_0000);
    W.pt_next      = PA_WIDTH'('h0_8F00_1000);
    for (int i = 0; i < 512; i++) W.wr64(W.satp_root + PA_WIDTH'(8 * i), '0);
    for (int i = 0; i < FTQ_DEPTH; i++) fstart[i] = '0;
    // csr. Bare runs in M-mode; Sv39 runs in S-mode with ASID 1. PMP
    // entry 0 is NAPOT over all of memory with R, W and X, so S-mode
    // fetch is not denied by the no-match rule.
    csr_itlb_v          = 1'b0;
    csr_itlb_priv       = use_sv39 ? 2'd1 : 2'd3;
    csr_itlb_satp_mode  = use_sv39 ? 4'd8 : 4'd0;
    csr_itlb_satp_asid  = use_sv39 ? ASID_WIDTH'(1) : '0;
    csr_itlb_vsatp_mode = '0;
    csr_itlb_vsatp_asid = '0;
    csr_itlb_hgatp_mode = '0;
    csr_itlb_hgatp_vmid = '0;
    csr_itlb_pmpcfg     = '0;
    csr_itlb_pmpaddr    = '0;
    csr_itlb_pmpcfg[0]  = 8'h1F;
    csr_itlb_pmpaddr[0] = '1;
    // The walker's CSR group (MMU-24a), BP-123: the same regime.
    csr_ptw_satp_mode     = csr_itlb_satp_mode;
    csr_ptw_satp_ppn      = PPN_WIDTH'(W.satp_root >> 12);
    csr_ptw_vsatp_mode    = '0;
    csr_ptw_vsatp_ppn     = '0;
    csr_ptw_hgatp_mode    = '0;
    csr_ptw_hgatp_ppn     = '0;
    csr_ptw_menvcfg_adue  = 1'b0;
    csr_ptw_henvcfg_adue  = 1'b0;
    csr_ptw_menvcfg_pbmte = 1'b1;
    csr_ptw_henvcfg_pbmte = 1'b1;
    // config
    sc_enable             = 1'b1;
    ftb_fastpath_en       = 1'b0;
    tage_enable_aging     = 1'b0;
    tage_aging_interval   = '0;
    ittage_enable_aging   = 1'b0;
    ittage_aging_interval = '0;
    ext_enable            = RVA23_ENABLE;
    // maintenance
    bkend_itlb_inv_val    = 1'b0;
    bkend_itlb_inv_op     = '0;
    bkend_itlb_inv_rs1_nz = 1'b0;
    bkend_itlb_inv_rs2_nz = 1'b0;
    bkend_itlb_inv_vpn    = '0;
    bkend_itlb_inv_asid   = '0;
    bkend_itlb_inv_vmid   = '0;
  endtask

  // BP-123. The two-stage regime: V=1 in VS-mode, vsatp Sv39 and hgatp
  // Sv39x4, ASID 1 and VMID 3. The G-stage root is 16 KiB at
  // 0x8E00_0000; VS-stage tables take GPAs from 0xC000_0000. The reset
  // vector is mapped VA = GPA = SPA.
  task automatic set_h2();
    W.h2       = 1'b1;
    W.hg_root  = PA_WIDTH'('h0_8E00_0000);
    for (int i = 0; i < 2048; i++) W.wr64(W.hg_root + PA_WIDTH'(8 * i), '0);
    W.gpt_next = GPA_WIDTH'('h0_C000_0000);
    W.vs_root  = W.vs_alloc();
    csr_itlb_v            = 1'b1;
    csr_itlb_priv         = 2'd1;
    csr_itlb_satp_mode    = 4'd0;
    csr_itlb_vsatp_mode   = 4'd8;
    csr_itlb_vsatp_asid   = ASID_WIDTH'(1);
    csr_itlb_hgatp_mode   = 4'd8;
    csr_itlb_hgatp_vmid   = VMID_WIDTH'(3);
    csr_ptw_satp_mode     = 4'd0;
    csr_ptw_vsatp_mode    = 4'd8;
    csr_ptw_vsatp_ppn     = (GPA_WIDTH-12)'(W.vs_root >> 12);
    csr_ptw_hgatp_mode    = 4'd8;
    csr_ptw_hgatp_ppn     = PPN_WIDTH'(W.hg_root >> 12);
    W.h_map4k(RESET_VECTOR, GPA_WIDTH'(RESET_VECTOR), PA_WIDTH'(RESET_VECTOR));
  endtask

  // A PMP entry over one naturally aligned 4 KiB page (NAPOT), with the
  // permission bits given (R 1, W 2, X 4). Lower entries win.
  task automatic pmp_page(input int k, input logic [PA_WIDTH-1:0] pa,
                          input logic [2:0] rwx);
    csr_itlb_pmpcfg[k]  = {5'b00011, rwx};           // A = NAPOT
    csr_itlb_pmpaddr[k] = (PA_WIDTH-2)'(pa >> 2) | (PA_WIDTH-2)'('h1FF);
  endtask

  // The last PMP entry an S-mode fetch and walk may use: everything.
  task automatic pmp_all(input int k);
    csr_itlb_pmpcfg[0]  = 8'h00;
    csr_itlb_pmpaddr[0] = '0;
    csr_itlb_pmpcfg[k]  = 8'h1F;
    csr_itlb_pmpaddr[k] = '1;
  endtask

  task automatic release_reset();
    repeat (4) @(posedge clk);
    #1;
    rstn   = 1'b1;
    run_be = 1'b1;
  endtask

  // Run until the whole stream has retired, then stop taking decode's
  // output so the front end backs up and nothing more retires, and
  // check that the FTQ commits through the watermark.
  int cyc_run;

  task automatic run_and_check(input int max_cyc);
    int c;
    c = 0;
    while ((ep < W.ne) && (c < max_cyc) && (n_err < 20)) begin
      @(posedge clk);
      #1;
      c++;
    end
    cyc_run = c;
    run_be = 1'b0;
    repeat (200) @(posedge clk);
    #1;
    chk($sformatf("the whole stream retired: %0d of %0d in %0d cycles",
                  ep, W.ne, c), ep == W.ne);
    chk($sformatf("no stream, decode or index error (%0d)", n_err),
        n_err == 0);
    chk("every retired instruction is the executed stream, in order",
        n_retired == W.ne);
    chk($sformatf("the FTQ committed through the watermark: ptr %0d wm %0d",
                  dut.u_ftq.w_commit_ptr, wm),
        wm_val && (dut.u_ftq.w_commit_ptr == wm + FTQ_PTR_BITS'(1)));
    chk("every resolution was accepted", rq_hd == rq_tl);
    // BP-123, Problem 4, every program.
    chk($sformatf({"no uncached request before older commits or off ",
                   "the path (%0d of %0d)"}, n_uc_bad, n_uc_req),
        n_uc_bad == 0);
    chk($sformatf("no uncached line written into the L1I (%0d)", n_uc_fill_bad),
        n_uc_fill_bad == 0);
    chk($sformatf({"uncached instructions delivered one at a time ",
                   "(%0d bad of %0d)"}, n_uc_dlv_bad, n_uc_dlv),
        n_uc_dlv_bad == 0);
    chk($sformatf("the walker's memory port kept WM-1 and WM-3 (%0d)",
                  n_pw_bad), n_pw_bad == 0);
    $display("%s", $sformatf(
      {"   BP123 %s: uncached requests %0d, uncached deliveries %0d; ",
       "maintenance %0d (drained %0d); walks %0d, walker accesses %0d, ",
       "CAS %0d, changed %0d, errors %0d; eager resolutions %0d, ",
       "CSR writes %0d, faults checked %0d"}, tname, n_uc_req, n_uc_dlv,
      n_maint, n_maint_drain, n_walks, n_pw_acc, n_pw_cas, n_pw_chg,
      n_pw_err, n_eager_res, n_csrw, n_fault_ok));
    $display("%s", $sformatf(
             {"   %s: %0d retired in %0d cycles, %0d mispredicts, %0d ",
              "traps, %0d predecode redirects, %0d resolutions, %0d L1I ",
              "fills, %0d walks, commit ptr %0d"}, tname, n_retired, c,
             n_mispred, n_trap, n_pd_redir, rq_tl, n_fills, n_walks,
             dut.u_ftq.w_commit_ptr));
    $display("%s", $sformatf(
             {"   %s: redirects p2 %0d p3 %0d, unmapped resolutions %0d; ",
              "updates received uBTB %0d ",
              "LP %0d TAGE %0d SC %0d ITTAGE %0d, RAS commits %0d; ",
              "RETURN_CALL at p2 %0d, committed %0d"}, tname, n_redir_p2,
             n_redir_p3, n_nomap, n_u_ubtb, n_u_lp, n_u_tage, n_u_sc,
             n_u_ittage, n_u_ras, n_rc_p2, n_rc_commit));
    $display("%s", $sformatf(
             {"   %s: RAS mispredicts %0d; FTB jump field trained by a ",
              "jump at another position %0d"}, tname, n_mis_ras,
             n_jmp_swap));
    // BP-121.
    chk($sformatf("every RAS commit is the retired stream's (%0d ok, %0d bad)",
                  n_ras_ok, n_ras_bad), n_ras_bad == 0);
    chk($sformatf("every retired RAS operation committed (%0d left)",
                  ras_exp.size()), ras_exp.size() == 0);
    chk($sformatf("no late TAGE / ITTAGE / SC response (%0d %0d %0d)",
                  n_tage_late, n_it_late, n_sc_late),
        (n_tage_late == 0) && (n_it_late == 0) && (n_sc_late == 0));
    chk($sformatf("no FTB lookup dropped by an FTB update (%0d)",
                  n_ftb_drop), n_ftb_drop == 0);
    chk($sformatf("no RAS operation by a squashed block (%0d)", n_ras_sq),
        n_ras_sq == 0);
    chk($sformatf("no p3 slot write without the p2 slot group (%0d)",
                  n_p3_no_p2), n_p3_no_p2 == 0);
    chk($sformatf({"a p2 redirect keeps its block's RAS operation ",
                   "(%0d ok, %0d bad)"}, n_own_ok, n_own_bad),
        n_own_bad == 0);
    chk($sformatf({"an LP direction at p2 is kept at p3 (%0d ok, %0d bad)"},
                  n_lp_kept, n_lp_bad), n_lp_bad == 0);
    chk($sformatf({"after a conditional's mispredict the newest history ",
                   "bit is its resolved direction (%0d ok, %0d bad)"},
                  n_hist_ok, n_hist_bad), n_hist_bad == 0);
    report();
  endtask

  // The BP-121 report: the program line the Results Capture table is
  // built from, the after-warm-up breakdown, the PCs that mispredict
  // more than once after warm-up, and per predictor the updates
  // received and the predictions used.
  task automatic report();
    $display("%s", $sformatf(
      {"   RESULT %s cycles %0d mispredicts %0d warm %0d [cond %0d ret %0d ",
       "rc %0d ind %0d icall %0d] pd %0d p2 %0d p3 %0d warm_e %0d of %0d"},
      tname, cyc_run, n_mispred, n_mis_warm, n_mis_type[int'(COND)],
      n_mis_type[int'(RETURN)], n_mis_type[int'(RETURN_CALL)],
      n_mis_type[int'(INDIRECT_NONRET)], n_mis_type[int'(INDIRECT_CALL)],
      n_pd_redir, n_redir_p2, n_redir_p3, warm_e, W.ne));
    foreach (mis_pc[p]) begin
      if (mis_pc[p] > 1)
        $display("   REPEAT %s pc %011h type %0d mispredicted %0d times",
                 tname, p, mis_typ[p], mis_pc[p]);
    end
    $display("%s", $sformatf(
      {"   PRED %s upd/used: uBTB %0d/%0d LP %0d/%0d/%0d FTB %0d/%0d ",
       "TAGE %0d/%0d SC %0d/%0d(flip %0d) ITTAGE %0d/%0d RAS %0d/%0d"},
      tname, n_u_ubtb, n_use_ubtb, n_u_lp, n_use_lp, n_use_lp2, n_u_ftb,
      n_use_ftb,
      n_u_tage, n_use_tage, n_u_sc, n_use_sc, n_sc_flip, n_u_ittage,
      n_use_ittage, n_u_ras, n_use_ras));
    $display("%s", $sformatf(
      {"   CHK %s RAS commits ok %0d; history after a mispredict ok %0d; ",
       "own p2 redirect RAS ok %0d; p3 writes without p2 %0d; ",
       "squashed RAS ops %0d; dropped FTB lookups %0d; p3 RAS repairs %0d, ",
       "backend restores naming a repaired entry %0d; LP p2 directions ",
       "kept at p3 %0d, not kept %0d"}, tname, n_ras_ok,
      n_hist_ok, n_own_ok, n_p3_no_p2, n_ras_sq, n_ftb_drop, n_p3_rep,
      n_rest_rep, n_lp_kept, n_lp_bad));
    $display("%s", $sformatf(
      {"   RESP %s on time/late: TAGE %0d/%0d ITTAGE %0d/%0d SC %0d/%0d ",
       "p2 blocks %0d, history bundle changed at p2 without a ",
       "redirect %0d"}, tname, n_tage_ok, n_tage_late, n_it_ok, n_it_late,
      n_sc_ok, n_sc_late, n_p2_blk, n_hist_mis));
  endtask

  // =================================================================
  // Program 1, bare (V=0, satp.MODE Bare, M-mode): physical fetch.
  // =================================================================
  task automatic p_bare();
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] link;
    tname = "bare";
    $display("-- %s --", tname);
    reset_all(1'b0);
    W.wp = RESET_VECTOR;
    // Straight-line mixed 16- and 32-bit code, then a 32-bit
    // instruction straddling the line boundary at 0x40.
    W.mixed(20);
    while (W.wp != RESET_VECTOR + VA_WIDTH'('h3E)) W.i16();
    W.i32(ADDI_T0);
    W.mixed(5);
    // Never taken, then always taken.
    W.cond(1'b0, W.wp + VA_WIDTH'('h40));
    W.mixed(3);
    W.cond(1'b1, RESET_VECTOR + VA_WIDTH'('h100));
    W.mixed(4);
    // JAL forward.
    W.jal(5'd0, RESET_VECTOR + VA_WIDTH'('h180));
    W.mixed(3);
    // Call and return, three times to the same function.
    fn = RESET_VECTOR + VA_WIDTH'('h400);
    for (int k = 0; k < 3; k++) begin
      link = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, fn);
      W.mixed(4);
      W.cond(1'b1, W.wp + VA_WIDTH'(8));        // a taken branch in it
      W.i32(ADDI_T0);
      W.ret(link);
      W.mixed(2);
    end
    // A 32-bit instruction straddling the page boundary at 0x1000.
    W.jal(5'd0, RESET_VECTOR + VA_WIDTH'('hFF0));
    while (W.wp != RESET_VECTOR + VA_WIDTH'('hFFE)) W.i16();
    W.i32(ADDI_T0);
    W.mixed(6);
    // An ecall: a trap redirect to the handler.
    W.ecall(RESET_VECTOR + VA_WIDTH'('h2000));
    W.mixed(4);
    // An access fault: a fetch just below main memory (MMU-15a)
    // faults with cause 1 and traps to the second handler. Within JAL
    // range of the handler.
    W.jal_fault(VA_WIDTH'('h0_7FFF_F000), IFU_FAULT_ACCESS,
              RESET_VECTOR + VA_WIDTH'('h3000));
    W.mixed(5);
    fn = RESET_VECTOR + VA_WIDTH'('h3400);
    link = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, fn);
    W.mixed(2);
    W.ret(link);
    W.mixed(2);
    // BP-121: straight-line code; nothing is after warm-up.
    warm_e = W.ne + 1;
    W.halt();
    release_reset();
    run_and_check(20000);
    chk($sformatf("a predecode redirect occurred (%0d)", n_pd_redir),
        n_pd_redir > 0);
    chk($sformatf("a backend mispredict occurred (%0d)", n_mispred),
        n_mispred > 0);
    chk($sformatf("two backend trap redirects occurred (%0d)", n_trap),
        n_trap == 2);
    chk("the access fault reached decode with its cause and VA",
        n_fault_ok == 1);
  endtask

  // =================================================================
  // Program 2, Sv39 (V=0, satp.MODE Sv39, S-mode).
  // =================================================================
  task automatic p_sv39();
    logic [VA_WIDTH-1:0] b;
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] link;
    tname = "sv39";
    $display("-- %s --", tname);
    reset_all(1'b1);
    // Three code pages, not physically contiguous, and a handler page.
    // b + 0x4000 is not mapped. All within JAL range of each other.
    b = VA_WIDTH'('h0_8001_0000);
    W.map4k(b,                       PA_WIDTH'('h0_8100_0000));
    W.map4k(b + VA_WIDTH'('h1000),   PA_WIDTH'('h0_8120_5000));
    W.map4k(b + VA_WIDTH'('h2000),   PA_WIDTH'('h0_8100_7000));
    W.map4k(VA_WIDTH'('h0_8002_0000), PA_WIDTH'('h0_8130_0000));
    // The reset vector is fetched physically before any translation,
    // so it jumps to the program; under Sv39 that fetch is already
    // translated, so the reset vector page is mapped to itself.
    W.map4k(RESET_VECTOR, PA_WIDTH'(RESET_VECTOR));
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, b);
    W.mixed(10);
    W.cond(1'b1, b + VA_WIDTH'('h200));
    W.mixed(3);
    // A 32-bit instruction straddling into the next, discontiguous
    // page.
    W.jal(5'd0, b + VA_WIDTH'('hFF0));
    while (W.wp != b + VA_WIDTH'('hFFE)) W.i16();
    W.i32(ADDI_T0);
    W.mixed(4);
    fn = b + VA_WIDTH'('h2100);
    for (int k = 0; k < 2; k++) begin
      link = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, fn);
      W.mixed(3);
      W.ret(link);
      W.mixed(2);
    end
    // A page fault: a fetch from an unmapped VA, cause 12.
    W.jal_fault(b + VA_WIDTH'('h4000), IFU_FAULT_PAGE,
              VA_WIDTH'('h0_8002_0000));
    W.mixed(6);
    // BP-121: straight-line code; nothing is after warm-up.
    warm_e = W.ne + 1;
    W.halt();
    release_reset();
    run_and_check(20000);
    chk($sformatf("the L2 TLB walked (%0d)", n_walks), n_walks > 0);
    chk("the page fault reached decode with its cause and VA",
        n_fault_ok == 1);
    chk($sformatf("a backend mispredict occurred (%0d)", n_mispred),
        n_mispred > 0);
  endtask

  // =================================================================
  // Program 3, loops (bare). An outer loop of 8 iterations around an
  // inner counted loop of 6, so the inner loop branch runs the same
  // trip count again and again (the LP's case). The outer body holds
  // a conditional that is always taken (TAGE, SC), an indirect jump
  // and an indirect call to a function that returns (ITTAGE, RAS).
  // =================================================================
  // BP-122, TD#169: the loop predictor's end state in lp and loops.
  // It supplies directions the entry keeps (p2), and the inner loop's
  // branch at br_pc mispredicts at most once after warm-up.
  localparam int LOOPS_OUTER = 14;
  localparam int LOOPS_WARM  = 8;
  localparam int LP_OUTER    = 16;
  localparam int LP_WARM     = 8;

  task automatic lp_end_chk(input logic [VA_WIDTH-1:0] br_pc);
    int n;
    n = mis_pc.exists(br_pc) ? mis_pc[br_pc] : 0;
    chk($sformatf("%s: the LP supplied p2 directions (%0d)", tname,
                  n_use_lp2), n_use_lp2 > 0);
    chk($sformatf("%s: the loop exit at %011h mispredicted %0d times %s",
                  tname, br_pc, n, "after warm-up (at most 1)"), n <= 1);
  endtask

  task automatic p_loops();
    logic [VA_WIDTH-1:0] otop;
    logic [VA_WIDTH-1:0] itop;
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] link;
    int                  eo;
    int                  ei;
    tname = "loops";
    $display("-- %s --", tname);
    reset_all(1'b0);
    W.wp = RESET_VECTOR;
    W.mixed(4);
    fn   = RESET_VECTOR + VA_WIDTH'('h800);
    otop = W.wp;
    eo   = W.ne;
    // Outer body, first iteration.
    W.mixed(2);
    itop = W.wp;
    ei   = W.ne;
    W.mixed(3);
    W.loop_br(itop);
    W.rep_iter(ei, 6);
    W.cond(1'b1, W.wp + VA_WIDTH'(12));            // always taken, skips 8
    W.mixed(2);
    // jalr x0, 0(x7): an indirect jump to a fixed target 0x40 ahead.
    W.jalr_to(5'd0, 5'd7, W.wp + VA_WIDTH'('h40));
    W.mixed(2);
    // jalr x1, 0(x28): an indirect call to fn, which returns.
    link = W.wp + VA_WIDTH'(4);
    W.jalr_to(5'd1, 5'd28, fn);
    W.mixed(3);
    W.ret(link);
    W.mixed(1);
    W.loop_br(otop);
    // BP-122 (ruled by Jeff): 14 outer iterations, warm-up after 8. The
    // loop predictor is trusted after five exits of the inner loop at
    // the earliest (one with no count, one to learn it, three
    // confirmations); BP-121 ran 8 and warmed up after 2.
    W.rep_iter(eo, LOOPS_OUTER);
    warm_e = eo + LOOPS_WARM * ((W.ne - eo) / LOOPS_OUTER);
    W.mixed(3);
    W.halt();
    release_reset();
    run_and_check(60000);
    chk($sformatf("the uBTB received updates (%0d)", n_u_ubtb), n_u_ubtb > 0);
    chk($sformatf("the LP received updates (%0d)", n_u_lp), n_u_lp > 0);
    chk($sformatf("TAGE received updates (%0d)", n_u_tage), n_u_tage > 0);
    chk($sformatf("SC received updates (%0d)", n_u_sc), n_u_sc > 0);
    chk($sformatf("ITTAGE received updates (%0d)", n_u_ittage),
        n_u_ittage > 0);
    chk($sformatf("the RAS committed (%0d)", n_u_ras), n_u_ras > 0);
    lp_end_chk(VA_WIDTH'(RESET_VECTOR) + VA_WIDTH'('h18));
  endtask

  // =================================================================
  // Program 4, coro (bare). Two coroutines, A (the loop) and B,
  // switching by RETURN_CALL. Each iteration:
  //   L:   jal  x5, B            call, x5 = L+4 (push L+4)
  //   B:   ...                   B's prologue
  //   B1:  jalr x1, 0(x5)        RETURN_CALL: to L+4, x1 = B1+4
  //   L+4: ...
  //   A1:  jalr x5, 0(x1)        RETURN_CALL: to B1+4, x5 = A1+4
  //   B1+4: ...
  //   B2:  jalr x0, 0(x5)        RETURN: to A1+4
  //   A1+4: ... bne x6, x0, L
  // The stack is level across the iteration: a push, two pop-then-
  // pushes, a pop. Each RETURN_CALL's target is the other coroutine's
  // resume address, the top of the stack.
  // =================================================================
  task automatic p_coro();
    logic [VA_WIDTH-1:0] l;
    logic [VA_WIDTH-1:0] b;
    logic [VA_WIDTH-1:0] b1;
    logic [VA_WIDTH-1:0] a1;
    int                  e0;
    tname = "coro";
    $display("-- %s --", tname);
    reset_all(1'b0);
    W.wp = RESET_VECTOR;
    W.mixed(3);
    b  = RESET_VECTOR + VA_WIDTH'('h600);
    l  = W.wp;
    e0 = W.ne;
    W.jal(5'd5, b);                          // L
    W.mixed(3);                              // B prologue
    b1 = W.wp;
    W.jalr_to(5'd1, 5'd5, l + VA_WIDTH'(4)); // B1: RETURN_CALL
    W.mixed(2);                              // A at L+4
    a1 = W.wp;
    W.jalr_to(5'd5, 5'd1, b1 + VA_WIDTH'(4)); // A1: RETURN_CALL
    W.mixed(2);                              // B at B1+4
    W.jalr_to(5'd0, 5'd5, a1 + VA_WIDTH'(4)); // B2: RETURN
    W.mixed(1);                              // A at A1+4
    W.loop_br(l);
    W.rep_iter(e0, 10);
    // BP-121: after two iterations.
    warm_e = e0 + 2 * ((W.ne - e0) / 10);
    W.mixed(3);
    W.halt();
    release_reset();
    run_and_check(40000);
    chk($sformatf("the p2 classification formed RETURN_CALL (%0d)",
                  n_rc_p2), n_rc_p2 > 0);
    chk($sformatf("the RAS committed RETURN_CALLs (%0d, 2 per iteration)",
                  n_rc_commit), n_rc_commit == 20);
  endtask

  // =================================================================
  // Program 5, calls (bare), BP-120, TD#159. Six iterations of:
  //   main: jal x1, f            push Lm
  //   f:    jal x1, g            push Lf1
  //   g:    ret                  pop  -> Lf1
  //   f:    jal x1, h            push Lf2
  //   h:    ret                  pop  -> Lf2
  //   f:    ret                  pop  -> Lm
  //   main: bne x6, x0, top
  // f's return follows a pop then a push. Before BP-120 the pop of
  // Lf2 moved TOSR to TOSR-1, the slot Lf1 was popped from, so f's
  // return was predicted to Lf1 (ras_decisions.md 3.2).
  //
  // THE LAYOUT KEEPS ONE JUMP PER FTB ENTRY. An FTB entry is indexed by
  // the region of the block START and holds one jump (5.5, TD#156), and
  // a block that starts at a return address runs on into the next
  // region. So each call is the last instruction of its 32-byte region
  // and its return address is the next region's start: main's call at
  // +0x1C, f's at f+0x1C and f+0x3C, f's return at f+0x42, g's and h's
  // returns at g+6 and h+6. Each block start then finds only its own
  // jump, and the block end the FTB records is the call's return
  // address, which is what the RAS pushes (IC-FTB-03).
  // =================================================================
  task automatic p_calls();
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] g;
    logic [VA_WIDTH-1:0] h;
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] lm;
    logic [VA_WIDTH-1:0] lf1;
    logic [VA_WIDTH-1:0] lf2;
    int                  e0;
    tname = "calls";
    $display("-- %s --", tname);
    reset_all(1'b0);
    W.wp  = RESET_VECTOR;
    f   = RESET_VECTOR + VA_WIDTH'('h800);
    g   = RESET_VECTOR + VA_WIDTH'('hA00);
    h   = RESET_VECTOR + VA_WIDTH'('hC00);
    W.mixed(3);
    top = W.wp;
    e0  = W.ne;
    while (W.wp != RESET_VECTOR + VA_WIDTH'('h1C)) W.i16();
    lm  = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, f);                          // main calls f
    W.mixed(3);
    while (W.wp != f + VA_WIDTH'('h1C)) W.i16();
    lf1 = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, g);                          // f calls g
    W.mixed(2);
    W.ret(lf1);                              // g returns
    W.mixed(1);
    while (W.wp != f + VA_WIDTH'('h3C)) W.i16();
    lf2 = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, h);                          // f calls h
    W.mixed(2);
    W.ret(lf2);                              // h returns
    W.mixed(1);
    watch_pc = W.wp;                         // f's return
    W.ret(lm);                               // f returns to main
    W.mixed(1);
    W.loop_br(top);
    W.rep_iter(e0, 6);
    // BP-121: after two iterations.
    warm_e = e0 + 2 * ((W.ne - e0) / 6);
    W.mixed(3);
    W.halt();
    release_reset();
    run_and_check(40000);
    // Reported, not checked: f's return still mispredicts in every
    // iteration, before BP-120 and after, for reasons outside TD#159
    // (the BP-120 Results Capture: the FTB lookup of the block after a
    // redirect is dropped when an FTB update borrows the read port, so
    // main's call is not pushed at p2). The RAS mispredict count is the
    // before/after measure of the link.
    $display("   %s: f's return mispredicted %0d times in 6 iterations",
             tname, n_mis_watch);
  endtask

  // =================================================================
  // BP-121 programs. Each loop is emitted once per iteration (see the
  // file header); warm_e is set at the start of the first iteration
  // counted as after warm-up.
  // =================================================================



  task automatic begin_prog(input string nm);
    tname = nm;
    $display("-- %s --", tname);
    reset_all(1'b0);
    W.wp = RESET_VECTOR;
  endtask

  task automatic end_prog(input int max_cyc);
    W.halt();
    if ($test$plusargs("DUMPEX")) begin
      for (int e = 0; e < W.ne; e++)
        $display("EX %0d pc %0h instr %08h rvc %0d bt %0d tk %0d tgt %0h", e,
                 W.ex[e].pc[15:0], W.ex[e].instr, W.ex[e].rvc, W.ex[e].btype,
                 W.ex[e].taken, W.ex[e].target[15:0]);
    end
    release_reset();
    run_and_check(max_cyc);
  endtask

  // -----------------------------------------------------------------
  // lp: a counted inner loop of 10 inside an outer loop of 12. The
  // inner loop branch has the same trip count every time (the loop
  // predictor's case).
  // -----------------------------------------------------------------
  task automatic p_lp();
    logic [VA_WIDTH-1:0] otop;
    logic [VA_WIDTH-1:0] itop;
    begin_prog("lp");
    W.mixed(3);
    otop = W.wp;
    // BP-122 (ruled by Jeff): 16 outer iterations, warm-up at 8 (12 and
    // 4 before); see LOOPS_OUTER.
    for (int o = 0; o < LP_OUTER; o++) begin
      if (o == LP_WARM) warm_e = W.ne;
      W.wp = otop;
      W.mixed(2);
      itop = W.wp;
      for (int i = 0; i < 10; i++) begin
        W.wp = itop;
        W.mixed(3);
        W.bcc(i != 9, itop);
      end
      W.mixed(2);
      W.bcc(o != LP_OUTER - 1, otop);
    end
    W.mixed(3);
    end_prog(80000);
    chk($sformatf("lp: the LP trained (%0d updates; %0d directions used)",
                  n_u_lp, n_use_lp), n_u_lp > 0);
    lp_end_chk(VA_WIDTH'(RESET_VECTOR) + VA_WIDTH'('h16));
  endtask

  // -----------------------------------------------------------------
  // hist: two branches whose outcomes depend on history (TAGE). A
  // alternates not taken / taken; B is not taken twice then taken.
  // Neither is predictable from its own bias. 96 iterations, the second
  // 48 after warm-up: TAGE allocates one tagged entry per history
  // context on a mispredict, and the six contexts of the combined
  // pattern take most of the first 48 to settle (measured: with a
  // 16-iteration warm-up the period-3 branch still mispredicted 9 of
  // 32; with 48, 3 mispredicts in 48 iterations, none repeating).
  // -----------------------------------------------------------------
  task automatic p_hist();
    logic [VA_WIDTH-1:0] top;
    begin_prog("hist");
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 96; it++) begin
      if (it == 48) warm_e = W.ne;
      W.wp = top;
      W.mixed(2);
      W.cskip((it % 2) == 1, 2);              // A
      W.mixed(1);
      W.cskip((it % 3) == 2, 2);              // B
      W.mixed(1);
      W.bcc(it != 95, top);
    end
    W.mixed(3);
    end_prog(80000);
    chk($sformatf("hist: TAGE supplied a direction (%0d)", n_use_tage),
        n_use_tage > 0);
  endtask

  // -----------------------------------------------------------------
  // twocond: two conditionals in one block, both slots. Each block
  // sits alone in its 32-byte region, so no other start shares its
  // FTB entry (the shared case is multistart's and region's). Block X:
  // c1 never taken, c2 always taken. Block Y: c1 alternates, c2 never
  // taken. X jumps to Y, Y to the loop branch.
  // -----------------------------------------------------------------
  task automatic p_twocond();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] x;
    logic [VA_WIDTH-1:0] y;
    logic [VA_WIDTH-1:0] back;
    begin_prog("twocond");
    x = RESET_VECTOR + VA_WIDTH'('h400);
    y = RESET_VECTOR + VA_WIDTH'('h440);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 24; it++) begin
      if (it == 8) warm_e = W.ne;
      W.wp = top;
      W.i16();
      W.jal(5'd0, x);
      back = top + VA_WIDTH'(6);
      W.i16();
      W.cskip(1'b0, 1);                     // X c1
      W.cskip(1'b1, 1);                     // X c2
      W.i16();
      W.jal(5'd0, y);
      W.i16();
      W.cskip((it % 2) == 1, 1);            // Y c1
      W.cskip(1'b0, 1);                     // Y c2
      W.i16();
      W.jal(5'd0, back);
      W.mixed(1);
      W.bcc(it != 23, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // ftbonly: eight blocks 0x800 apart, chained by taken conditionals.
  // They share one uBTB set (pc[10:5]) of four ways and occupy eight
  // FTB sets (pc[13:5]), so the FTB holds every branch and the uBTB
  // cannot.
  // -----------------------------------------------------------------
  task automatic p_ftbonly();
    logic [VA_WIDTH-1:0] b [0:7];
    logic [VA_WIDTH-1:0] ex_pc;
    begin_prog("ftbonly");
    for (int k = 0; k < 8; k++)
      b[k] = RESET_VECTOR + VA_WIDTH'('h1000 + k * 'h800);
    W.mixed(3);
    W.jal(5'd0, b[0]);
    for (int it = 0; it < 16; it++) begin
      if (it == 4) warm_e = W.ne;
      for (int k = 0; k < 7; k++) begin
        W.wp = b[k];
        W.mixed(2);
        W.bcc(1'b1, b[k+1]);
      end
      W.wp = b[7];
      W.mixed(1);
      ex_pc = W.wp + VA_WIDTH'(8);
      W.bcc(it == 15, ex_pc);                 // exit on the last pass
      if (it != 15) begin
        W.jal(5'd0, b[0]);
      end else begin
        W.d_jal_fill();
      end
    end
    W.mixed(3);
    end_prog(80000);
  endtask


  // -----------------------------------------------------------------
  // nest: calls nested five deep, main -> f1 -> f2 -> f3 -> f4 -> f5.
  // -----------------------------------------------------------------

  task automatic p_nest();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] l;
    begin_prog("nest");
    for (int k = 1; k <= 5; k++)
      W.fnv[k] = RESET_VECTOR + VA_WIDTH'('h400 + k * 'h100);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 12; it++) begin
      if (it == 4) warm_e = W.ne;
      W.wp = top;
      W.mixed(2);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, W.fnv[1]);
      W.emit_nest(1, 5, l);
      W.mixed(1);
      W.bcc(it != 11, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // recur: one function calling itself six deep from one call site,
  // so the RAS sees the same return address pushed again and again
  // (the recursion counter, ras_decisions.md 5). Layout of f:
  //   f+0   mixed(2)        6 bytes
  //   f+6   beq -> f+16     taken at the bottom of the recursion
  //   f+10  jal x1, f       link f+14
  //   f+14  c.addi
  //   f+16  ret
  // -----------------------------------------------------------------

  task automatic p_recur();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] l;
    begin_prog("recur");
    f = RESET_VECTOR + VA_WIDTH'('h800);
    // The not-taken path of the bottom beq (f+10..f+16) is written by
    // the first call; the taken bottom is written here too, dry.
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 10; it++) begin
      if (it == 3) warm_e = W.ne;
      W.wp = top;
      W.mixed(2);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, f);
      W.emit_rec(f, 6, l);
      W.mixed(1);
      W.bcc(it != 9, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // deep: a chain of 18 distinct functions, f0 -> f1 -> ... -> f17,
  // so 18 distinct return addresses are live: beyond the 15 usable
  // speculative entries (the wrap, ras_decisions.md 3.2).
  // -----------------------------------------------------------------
  task automatic p_deep();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] l;
    begin_prog("deep");
    for (int k = 1; k <= 18; k++)
      W.fnv[k] = RESET_VECTOR + VA_WIDTH'('h400 + k * 'h40);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 8; it++) begin
      if (it == 3) warm_e = W.ne;
      W.wp = top;
      W.mixed(2);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, W.fnv[1]);
      W.emit_nest(1, 18, l);
      W.mixed(1);
      W.bcc(it != 7, top);
    end
    W.mixed(3);
    end_prog(120000);
  endtask

  // -----------------------------------------------------------------
  // indir: an indirect jump and an indirect call whose targets
  // alternate, each preceded by a conditional that alternates with
  // them, so the target is a function of global history (ITTAGE).
  // -----------------------------------------------------------------
  task automatic p_indir();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] ta;
    logic [VA_WIDTH-1:0] tb;
    logic [VA_WIDTH-1:0] jn;
    logic [VA_WIDTH-1:0] fa;
    logic [VA_WIDTH-1:0] fb;
    logic [VA_WIDTH-1:0] l;
    logic                odd;
    begin_prog("indir");
    ta = RESET_VECTOR + VA_WIDTH'('h400);
    tb = RESET_VECTOR + VA_WIDTH'('h480);
    jn = RESET_VECTOR + VA_WIDTH'('h500);
    fa = RESET_VECTOR + VA_WIDTH'('h600);
    fb = RESET_VECTOR + VA_WIDTH'('h680);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 40; it++) begin
      if (it == 16) warm_e = W.ne;
      odd = (it % 2) == 1;
      W.wp = top;
      W.mixed(1);
      W.cskip(odd, 1);
      W.jalr_to(5'd0, 5'd7, odd ? ta : tb);   // indirect jump
      if (odd) begin
        W.mixed(2);
        W.jal(5'd0, jn);
      end else begin
        W.mixed(1);
        W.jal(5'd0, jn);
      end
      W.mixed(1);
      W.cskip(!odd, 1);
      l = W.wp + VA_WIDTH'(4);
      W.jalr_to(5'd1, 5'd28, odd ? fa : fb);  // indirect call
      if (odd) W.mixed(2);
      else     W.mixed(1);
      W.ret(l);
      W.mixed(1);
      // The loop back edge, a JAL to the top: the loop body spans
      // several distant blocks.
      W.exit_or_jal(it == 39, top);
    end
    W.mixed(3);
    end_prog(120000);
    chk($sformatf("indir: ITTAGE supplied a target (%0d)", n_use_ittage),
        n_use_ittage > 0);
  endtask

  // -----------------------------------------------------------------
  // region: two calls and a return in one 32-byte region (TD#161):
  //   f+0x0  jal x1, g     link f+0x4
  //   f+0x4  c.addi
  //   f+0x6  jal x1, h     link f+0xA
  //   f+0xA  c.addi
  //   f+0xC  ret
  // The three blocks of f (starts f, f+0x4, f+0xA) share one FTB entry.
  // -----------------------------------------------------------------
  task automatic p_region();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] g;
    logic [VA_WIDTH-1:0] h;
    logic [VA_WIDTH-1:0] l;
    begin_prog("region");
    f = RESET_VECTOR + VA_WIDTH'('h800);
    g = RESET_VECTOR + VA_WIDTH'('hA00);
    h = RESET_VECTOR + VA_WIDTH'('hC00);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 16; it++) begin
      if (it == 4) warm_e = W.ne;
      W.wp = top;
      W.mixed(2);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, f);
      W.jal(5'd1, g);
      W.mixed(1);
      W.ret(f + VA_WIDTH'('h4));
      W.i16();
      W.jal(5'd1, h);
      W.mixed(1);
      W.ret(f + VA_WIDTH'('hA));
      W.i16();
      W.ret(l);
      W.mixed(1);
      W.bcc(it != 15, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // multistart: one region entered at two starts. Region R:
  //   R+0x00  c.addi x2
  //   R+0x04  c1, never taken          (seen from start R only)
  //   R+0x08  c.addi x2
  //   R+0x0C  c2, taken to R+0x18      (seen from both starts)
  //   R+0x18  c.addi
  //   R+0x1A  jal x0 back
  // Even iterations enter at R, odd at R+0x08.
  // -----------------------------------------------------------------
  task automatic p_multistart();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] r;
    logic [VA_WIDTH-1:0] cont;
    logic [VA_WIDTH-1:0] j1;
    logic [VA_WIDTH-1:0] j2;
    begin_prog("multistart");
    r = RESET_VECTOR + VA_WIDTH'('hC00);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 24; it++) begin
      if (it == 8) warm_e = W.ne;
      W.wp = top;
      W.i16();
      // Taken on odd iterations, to the jump to R+0x08.
      j1 = W.wp + VA_WIDTH'(4);
      j2 = j1 + VA_WIDTH'(4);
      W.bcc((it % 2) == 1, j2);
      if ((it % 2) == 0) begin
        W.jal(5'd0, r);
        W.i16();
        W.i16();
        W.bcc(1'b0, r + VA_WIDTH'('h8));       // c1
      end else begin
        W.jal(5'd0, r + VA_WIDTH'('h8));
      end
      W.i16();
      W.i16();
      W.bcc(1'b1, r + VA_WIDTH'('h18));       // c2
      W.i16();
      cont = j2 + VA_WIDTH'(4);
      W.jal(5'd0, cont);
      W.mixed(1);
      W.bcc(it != 23, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask



  // -----------------------------------------------------------------
  // cross: a block crossing a 32-byte boundary, a 32-bit instruction
  // straddling it, a conditional past it, and a call as the last
  // instruction of the next region. Region X:
  //   X+0x14  entered here (region offset 10)
  //   X+0x1E  a 32-bit instruction straddling X+0x20
  //   X+0x24  conditional, taken to X+0x30 (stored in X's entry at
  //           region position 18, beyond the region)
  //   X+0x3C  jal x1, fn: the last instruction of region X+0x20
  // -----------------------------------------------------------------
  task automatic p_cross();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] x;
    logic [VA_WIDTH-1:0] fn;
    begin_prog("cross");
    x  = RESET_VECTOR + VA_WIDTH'('h900);
    fn = RESET_VECTOR + VA_WIDTH'('hB00);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 16; it++) begin
      if (it == 4) warm_e = W.ne;
      W.wp = top;
      W.mixed(1);
      W.jal(5'd0, x + VA_WIDTH'('h14));
      W.i16();
      W.i16();
      W.i32(ADDI_T0);
      W.i16();
      W.i32(ADDI_T0);                          // X+0x1E, straddles
      W.i16();
      W.bcc(1'b1, x + VA_WIDTH'('h30));        // X+0x24
      W.fill_dry_at(x + VA_WIDTH'('h28), 8);
      W.pad_to(x + VA_WIDTH'('h3C));
      W.jal(5'd1, fn);                         // X+0x3C
      W.mixed(2);
      W.ret(x + VA_WIDTH'('h40));
      W.i16();
      W.jal(5'd0, top + VA_WIDTH'(6));
      // Back in the loop, after the JAL at top+2.
      W.mixed(1);
      W.bcc(it != 15, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // rvc: compressed control transfers among compressed and 32-bit
  // code: c.bnez (alternating), c.jalr x1 (a call, link pc+2), c.jr x1
  // (its return), c.j, and c.beqz as the loop branch.
  // -----------------------------------------------------------------
  task automatic p_rvc();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] l;
    logic [VA_WIDTH-1:0] b;
    begin_prog("rvc");
    fn = RESET_VECTOR + VA_WIDTH'('h100);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 24; it++) begin
      if (it == 8) warm_e = W.ne;
      W.wp = top;
      W.i16();
      b = W.wp;
      W.cbz(1'b1, (it % 2) == 1, b + VA_WIDTH'(4));   // skips one c.addi
      if ((it % 2) == 0) W.i16();
      else               W.fill_dry_at(b + VA_WIDTH'(2), 2);
      W.i32(ADDI_T0);
      l = W.wp + VA_WIDTH'(2);
      W.cjalr(5'd1, fn);
      W.i16();
      W.i32(ADDI_T0);
      W.cjr(5'd1, l);
      W.i16();
      b = W.wp;
      W.cj(b + VA_WIDTH'(8));
      W.fill_dry_at(b + VA_WIDTH'(2), 6);
      W.i16();
      W.cbz(1'b0, it != 23, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // misp_call: a conditional the predictors cannot learn (pseudo-
  // random), then a call and its return (TD#162). After each backend
  // mispredict of the conditional the call's block is the first block
  // fetched.
  // -----------------------------------------------------------------
  task automatic p_misp_call();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] l;
    begin_prog("misp_call");
    W.lfsr = 16'hACE1;
    fn   = RESET_VECTOR + VA_WIDTH'('h400);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 32; it++) begin
      if (it == 8) warm_e = W.ne;
      W.wp = top;
      W.mixed(1);
      W.cskip(W.lfsr_bit(), 1);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, fn);
      W.mixed(2);
      W.ret(l);
      W.mixed(1);
      W.bcc(it != 31, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // jals: a chain of twelve JALs to distinct blocks, run three times.
  // On the first pass every JAL is new to the predictors and predecode
  // redirects (M1).
  // -----------------------------------------------------------------
  task automatic p_jals();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] t;
    begin_prog("jals");
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 3; it++) begin
      if (it == 1) warm_e = W.ne;
      W.wp = top;
      W.mixed(1);
      for (int k = 0; k < 12; k++) begin
        t = RESET_VECTOR + VA_WIDTH'('h200 + k * 'h60);
        W.jal(5'd0, t);
        W.mixed(2);
      end
      W.jal(5'd0, top + VA_WIDTH'('h100));
      W.wp = top + VA_WIDTH'('h100);
      W.mixed(1);
      W.bcc(it != 2, top);
    end
    W.mixed(3);
    end_prog(80000);
    chk($sformatf("jals: predecode redirected (%0d)", n_pd_redir),
        n_pd_redir > 0);
  endtask


  // =================================================================
  // BP-123 programs: maintenance (Problem 4).
  // =================================================================
  // A function at f, its old body six c.addi and a return. It is called
  // twice, so the L1I and the IFU's line buffer hold it. Then one store
  // rewrites it (three addi t1 and the return), the maintenance
  // operation retires (FENCE.I, or cbo.inval of its line), and the
  // function is called again: the stream expects the NEW body. A
  // stale fetch delivers the old one and fails the stream check.
  task automatic smc_fn(input logic [VA_WIDTH-1:0] f, input int calls);
    logic [VA_WIDTH-1:0] link;
    for (int k = 0; k < calls; k++) begin
      link = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, f);
      for (int i = 0; i < 6; i++) W.i16();
      W.ret(link);
    end
  endtask

  task automatic smc_store(input logic [VA_WIDTH-1:0] f);
    logic [VA_WIDTH-1:0] w;
    logic                d;
    W.store();
    w     = W.wp;
    d     = W.dry;
    W.dry = 1'b1;
    W.wp  = f;
    for (int i = 0; i < 3; i++) W.i32(ADDI_T1);
    W.ret(f);
    W.dry = d;
    W.wp  = w;
    W.store_end();
  endtask

  task automatic smc_call_new(input logic [VA_WIDTH-1:0] f);
    logic [VA_WIDTH-1:0] link;
    link = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, f);
    W.nowrite = 1'b1;
    for (int i = 0; i < 3; i++) W.i32(ADDI_T1);
    W.ret(link);
    W.nowrite = 1'b0;
  endtask

  // op 1 FENCE.I, 2 cbo.inval of the function's line. Phase 1 plain;
  // phase 2 with a mispredicted branch just before the operation and
  // cold code after it, so the IFU has fetches in flight when the L1I
  // takes the invalidate.
  task automatic p_smc(input int op);
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] g;
    begin_prog(op == 1 ? "fencei" : "cboinval");
    f = RESET_VECTOR + VA_WIDTH'('h800);
    g = RESET_VECTOR + VA_WIDTH'('hC40);
    W.mixed(3);
    smc_fn(f, 2);
    W.mixed(2);
    smc_store(f);
    W.mixed(2);
    if (op == 1) W.fence_i();
    else         W.cbo_inval(5'd10, PA_WIDTH'(f));
    W.mixed(2);
    smc_call_new(f);
    W.mixed(2);
    // Phase 2.
    smc_fn(g, 2);
    smc_store(g);
    W.cskip(1'b1, 1);                       // taken, cold: mispredicted
    if (op == 1) W.fence_i();
    else         W.cbo_inval(5'd10, PA_WIDTH'(g) + PA_WIDTH'('h24));
    W.mixed(60);                            // cold lines after it
    smc_call_new(g);
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(20000);
    chk($sformatf("two maintenance operations retired (%0d)", n_maint),
        n_maint == 2);
    chk($sformatf("two stores applied their patches (%0d)", n_patch),
        n_patch == 2 * 8);
    chk($sformatf("an invalidate drained fills in flight (%0d)",
                  n_maint_drain), n_maint_drain > 0);
    chk($sformatf("a backend mispredict occurred (%0d)", n_mispred),
        n_mispred > 0);
  endtask

  // =================================================================
  // BP-123 programs: uncached fetch under Sv39 (Problem 4).
  // =================================================================
  // A cacheable code page c, and a page u mapped with PBMT NC (1) or IO
  // (2). Branches into u, within it (taken and not, a jump, a counted
  // loop) and out of it; a call into u and a return out. Every
  // instruction from u must be fetched uncached, one at a time, after
  // everything older has committed (the per-cycle checks), and never
  // allocated in the L1I.
  task automatic p_uc(input logic [1:0] pbmt);
    logic [VA_WIDTH-1:0] c;
    logic [VA_WIDTH-1:0] u;
    logic [VA_WIDTH-1:0] link;
    logic [VA_WIDTH-1:0] top;
    int                  e0;
    int                  nu;
    tname = (pbmt == 2'd1) ? "uc_nc" : "uc_io";
    $display("-- %s --", tname);
    reset_all(1'b1);
    eager = 1'b1;
    c = VA_WIDTH'('h0_8001_0000);
    u = VA_WIDTH'('h0_8001_1000);
    W.map4k(RESET_VECTOR, PA_WIDTH'(RESET_VECTOR));
    W.map4k(c, PA_WIDTH'('h0_8100_0000));
    W.map4k_pbmt(u, PA_WIDTH'('h0_8120_3000), pbmt);
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, c);
    W.mixed(4);
    W.jal(5'd0, u + VA_WIDTH'('h10));       // into u
    W.mixed(3);
    W.cskip(1'b1, 2);                       // within: taken
    W.mixed(2);
    W.cskip(1'b0, 1);                       // within: not taken
    W.jal(5'd0, u + VA_WIDTH'('h200));      // within: a jump
    top = W.wp;
    e0  = W.ne;
    W.mixed(2);
    W.loop_br(top);
    W.rep_iter(e0, 3);                      // within: a loop
    W.mixed(2);
    W.jal(5'd0, c + VA_WIDTH'('h200));      // out of u
    W.mixed(3);
    link = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, u + VA_WIDTH'('h400));      // a call into u
    W.mixed(2);
    W.ret(link);                            // a return out of it
    W.mixed(2);
    nu = 0;
    for (int e = 0; e < W.ne; e++)
      if (W.uc_vpn.exists(W.ex[e].pc[VA_WIDTH-1:12])) nu++;
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf("uncached requests were made (%0d)", n_uc_req),
        n_uc_req > 0);
    chk($sformatf("every instruction from the page came alone (%0d of %0d)",
                  n_uc_dlv, nu), n_uc_dlv == nu);
  endtask


  // =================================================================
  // BP-123 programs: the page table walker in RTL (Problem 4).
  // =================================================================
  // Address map of the walker programs. Code c and handlers h, mapped
  // ordinarily; fault and test targets each in its own 2 MiB region,
  // T(k), reached by an indirect jump. Handlers h + 0x40 * k.
  localparam logic [VA_WIDTH-1:0] PC_C = VA_WIDTH'('h0_8001_0000);
  localparam logic [VA_WIDTH-1:0] PC_H = VA_WIDTH'('h0_8002_0000);
  localparam logic [PA_WIDTH-1:0] PA_C = PA_WIDTH'('h0_8100_0000);
  localparam logic [PA_WIDTH-1:0] PA_H = PA_WIDTH'('h0_8130_0000);
  localparam logic [GPA_WIDTH-1:0] GP_C = GPA_WIDTH'('h0_1001_0000);
  localparam logic [GPA_WIDTH-1:0] GP_H = GPA_WIDTH'('h0_1002_0000);

  // A Svnapot 64 KiB PTE PPN for a page in the region: PPN[3:0] = 1000.
  function automatic logic [43:0] napot(input logic [43:0] page);
    return {page[43:4], 4'b1000};
  endfunction

  function automatic logic [VA_WIDTH-1:0] tgt(input int k);
    return VA_WIDTH'('h0_8040_0000) + VA_WIDTH'(k) * VA_WIDTH'('h20_0000) +
           VA_WIDTH'('h10);
  endfunction
  function automatic logic [VA_WIDTH-1:0] hnd(input int k);
    return PC_H + VA_WIDTH'(k * 'h40);
  endfunction

  task automatic map_ch();
    if (W.h2) begin
      W.h_map4k(PC_C, GP_C, PA_C);
      W.h_map4k(PC_H, GP_H, PA_H);
    end else begin
      W.map4k(RESET_VECTOR, PA_WIDTH'(RESET_VECTOR));
      W.map4k(PC_C, PA_C);
      W.map4k(PC_H, PA_H);
    end
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, PC_C);
    W.mixed(2);
  endtask

  // A two-stage mapping with chosen leaves: VA page -> GPA page by a
  // VS-stage leaf, GPA page -> SPA page by a G-stage leaf.
  task automatic h_map(input logic [VA_WIDTH-1:0] va,
                       input logic [GPA_WIDTH-1:0] gpa,
                       input logic [PA_WIDTH-1:0] spa,
                       input logic [63:0] vs_leaf, input logic [63:0] g_leaf);
    W.wr64(W.g_slot(gpa[GPA_WIDTH-1:12], 0), g_leaf);
    W.gmap[gpa[GPA_WIDTH-1:12]] = spa[PA_WIDTH-1:12];
    W.wr64(W.vs_slot(va, 0), vs_leaf);
    W.vmap[va[VA_WIDTH-1:12]] = spa[PA_WIDTH-1:12];
  endtask

  // The GPA of the VS-stage level-0 table that maps va, and the SPA of
  // the G-stage leaf that maps that table page.
  function automatic logic [GPA_WIDTH-1:0] vs_l0_gpa(
      input logic [VA_WIDTH-1:0] va);
    logic [63:0] p;
    p = W.rd64(W.vs_slot(va, 1));
    return GPA_WIDTH'(p[53:10]) << 12;
  endfunction

  // A short body at a target, then an indirect jump to a handler.
  task automatic run_at(input logic [VA_WIDTH-1:0] at,
                        input logic [VA_WIDTH-1:0] back);
    W.jalr_to(5'd0, 5'd7, at);
    W.mixed(4);
    W.jalr_to(5'd0, 5'd7, back);
    W.mixed(2);
  endtask

  // ---- single stage: every fault cause and every cause-1 source -------
  task automatic p_pt_faults_s();
    logic [PA_WIDTH-1:0] a;
    tname = "pt_faults_s";
    $display("-- %s --", tname);
    reset_all(1'b1);
    csr_ptw_menvcfg_adue = 1'b1;
    pmp_all(2);
    map_ch();
    // 0 cause 12: nothing mapped.
    W.jr_fault(tgt(0), IFU_FAULT_PAGE, hnd(0));
    W.mixed(2);
    // 1 cause 1: PMP denies the read of the level-0 table.
    a = W.s_slot(tgt(1), 0);
    W.wr64(a, W.mk_pte(44'h8_1400, PTE_LEAF, 2'b00, 1'b0));
    pmp_page(0, a, 3'b000);
    W.jr_fault(tgt(1), IFU_FAULT_ACCESS, hnd(1));
    W.mixed(2);
    // 2 cause 1: PMP denies the Svadu write (the table page is R only).
    a = W.s_slot(tgt(2), 0);
    W.wr64(a, W.mk_pte(44'h8_1410, PTE_LEAF & 8'hBF, 2'b00, 1'b0));
    pmp_page(1, a, 3'b001);
    W.jr_fault(tgt(2), IFU_FAULT_ACCESS, hnd(2));
    W.mixed(2);
    // 3 cause 1: a level-0 table outside cacheable coherent memory.
    W.wr64(W.s_slot(tgt(3), 1), W.mk_pte(44'h4_0000, PTE_PTR, 2'b00, 1'b0));
    W.wr64(PA_WIDTH'('h0_4000_0000) + PA_WIDTH'(8 * tgt(3)[20:12]),
           W.mk_pte(44'h8_1420, PTE_LEAF, 2'b00, 1'b0));
    W.jr_fault(tgt(3), IFU_FAULT_ACCESS, hnd(3));
    W.mixed(2);
    // 4 cause 1: a leaf PPN above bit 23.
    W.wr64(W.s_slot(tgt(4), 0),
           W.mk_pte(44'h100_0000 | 44'h8_1430, PTE_LEAF, 2'b00, 1'b0));
    W.jr_fault(tgt(4), IFU_FAULT_ACCESS, hnd(4));
    W.mixed(2);
    // 5 cause 1: a non-leaf PPN above bit 23.
    W.wr64(W.s_slot(tgt(5), 1),
           W.mk_pte(44'h100_0000 | 44'h8_F100, PTE_PTR, 2'b00, 1'b0));
    W.jr_fault(tgt(5), IFU_FAULT_ACCESS, hnd(5));
    W.mixed(2);
    // 6 cause 1: the memory port answers the leaf read with an error.
    a = W.s_slot(tgt(6), 0);
    W.wr64(a, W.mk_pte(44'h8_1440, PTE_LEAF, 2'b00, 1'b0));
    err_pa  = a;
    err_arm = 1'b1;
    W.jr_fault(tgt(6), IFU_FAULT_ACCESS, hnd(6));
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf("all seven faults reached decode (%0d)", n_fault_ok),
        n_fault_ok == 7);
    chk($sformatf("the memory error was returned (%0d)", n_pw_err),
        n_pw_err == 1);
  endtask

  // ---- two stage: cause 20 of each kind, the GPA width, 12 and 1 -------
  task automatic p_pt_faults_h();
    logic [GPA_WIDTH-1:0] g;
    logic [GPA_WIDTH-1:0] tg;
    logic [PA_WIDTH-1:0]  a;
    tname = "pt_faults_h";
    $display("-- %s --", tname);
    reset_all(1'b1);
    set_h2();
    csr_ptw_menvcfg_adue = 1'b1;
    csr_ptw_henvcfg_adue = 1'b1;
    pmp_all(2);
    map_ch();
    // 0 kind 00: the final GPA is not mapped by the G-stage.
    g = GPA_WIDTH'('h0_2000_0000);
    W.wr64(W.vs_slot(tgt(0), 0), W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0));
    W.jr_gfault(tgt(0), FAULT_GPA_WIDTH'(g | GPA_WIDTH'('h10)), 2'b00, hnd(0));
    W.mixed(2);
    // 1 kind 01: a VS-stage table page is not mapped by the G-stage.
    tg = GPA_WIDTH'('h0_2100_0000);
    W.wr64(W.vs_slot(tgt(1), 1), W.mk_pte(44'(tg >> 12), PTE_PTR, 2'b00, 1'b0));
    W.jr_gfault(tgt(1),
                FAULT_GPA_WIDTH'(tg + GPA_WIDTH'(8 * tgt(1)[20:12])),
                2'b01, hnd(1));
    W.mixed(2);
    // 2 kind 10: the VS leaf needs A; the G-stage leaf of its table page
    // grants no write.
    g = GPA_WIDTH'('h0_2200_0000);
    h_map(tgt(2), g, PA_WIDTH'('h0_8140_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF & 8'hBF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1400, F_URWXAD, 2'b00, 1'b0));
    tg = vs_l0_gpa(tgt(2));
    W.wr64(W.g_slot(tg[GPA_WIDTH-1:12], 0),
           W.mk_pte(44'(W.g2s(tg) >> 12), 8'hDB, 2'b00, 1'b0));
    W.jr_gfault(tgt(2),
                FAULT_GPA_WIDTH'(tg + GPA_WIDTH'(8 * tgt(2)[20:12])),
                2'b10, hnd(2));
    W.mixed(2);
    // 3 a VS leaf whose GPA has a bit above 40: the whole GPA, kind 00,
    //   the offset filled by the IFU (MMU-23, IFU-2a; BP-124: this was
    //   MMU-30's GPA 0). PPN bit 43 set, so GPA bit 55.
    W.wr64(W.vs_slot(tgt(3), 0),
           W.mk_pte(44'h800_0000_0123, PTE_LEAF, 2'b00, 1'b0));
    W.jr_gfault(tgt(3), {44'h800_0000_0123, tgt(3)[11:0]}, 2'b00, hnd(3));
    W.mixed(2);
    // 4 a VS non-leaf whose GPA has a bit above 40: the whole GPA of the
    //   VS PTE the next level reads, kind 01 (BP-124: was GPA 0).
    W.wr64(W.vs_slot(tgt(4), 1),
           W.mk_pte(44'h2000_0041, PTE_PTR, 2'b00, 1'b0));
    W.jr_gfault(tgt(4), {44'h2000_0041, 12'h000} +
                FAULT_GPA_WIDTH'(8 * tgt(4)[20:12]), 2'b01, hnd(4));
    W.mixed(2);
    // 5 cause 12: a VS leaf with W and not R.
    W.wr64(W.vs_slot(tgt(5), 0),
           W.mk_pte(44'h1234, 8'hC5, 2'b00, 1'b0));
    W.jr_fault(tgt(5), IFU_FAULT_PAGE, hnd(5));
    W.mixed(2);
    // 6 cause 1: a G-stage leaf PPN above bit 23.
    g = GPA_WIDTH'('h0_2400_0000);
    h_map(tgt(6), g, PA_WIDTH'('h0_8140_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
          W.mk_pte(44'h100_8140, F_URWXAD, 2'b00, 1'b0));
    W.jr_fault(tgt(6), IFU_FAULT_ACCESS, hnd(6));
    W.mixed(2);
    // 7 cause 1: a memory error on the G-stage leaf read.
    g = GPA_WIDTH'('h0_2600_0000);
    h_map(tgt(7), g, PA_WIDTH'('h0_8141_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1410, F_URWXAD, 2'b00, 1'b0));
    err_pa  = W.g_slot(g[GPA_WIDTH-1:12], 0);
    err_arm = 1'b1;
    W.jr_fault(tgt(7), IFU_FAULT_ACCESS, hnd(7));
    W.mixed(2);
    // 8 cause 1: PMP denies the read of a G-stage table page.
    g = GPA_WIDTH'('h0_2800_0000);
    h_map(tgt(8), g, PA_WIDTH'('h0_8142_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1420, F_URWXAD, 2'b00, 1'b0));
    a = W.g_slot(g[GPA_WIDTH-1:12], 0);
    pmp_page(0, a, 3'b000);
    W.jr_fault(tgt(8), IFU_FAULT_ACCESS, hnd(8));
    W.mixed(2);
    // 9 kind 00 on GUEST PAGE 0, at a non-zero offset (BP-124). The VS
    //   leaf maps the target to GPA page 0, whose G-stage leaf is
    //   written invalid here; fault_gpa is the offset alone. Under
    //   MMU-30 a GPA of 0 was left 0, the collision of BP-123 risk 1.
    begin
      logic [VA_WIDTH-1:0] t9;
      t9 = tgt(9) + VA_WIDTH'('h7A4);
      W.wr64(W.g_slot('0, 0), 64'd0);
      W.wr64(W.vs_slot(t9, 0), W.mk_pte(44'h0, PTE_LEAF, 2'b00, 1'b0));
      W.jr_gfault(t9, FAULT_GPA_WIDTH'(t9[11:0]), 2'b00, hnd(9));
      W.mixed(2);
    end
    warm_e = W.ne + 1;
    end_prog(40000);
    chk($sformatf("all ten faults reached decode (%0d)", n_fault_ok),
        n_fault_ok == 10);
  endtask

  // ---- Svnapot, single stage: one walk serves the 64 KiB page ----------
  task automatic p_pt_napot_s();
    logic [VA_WIDTH-1:0] n;
    logic [PA_WIDTH-1:0] pa;
    tname = "pt_napot_s";
    $display("-- %s --", tname);
    reset_all(1'b1);
    map_ch();
    n  = VA_WIDTH'('h0_8010_0000);
    pa = PA_WIDTH'('h0_8150_0000);
    for (int i = 0; i < 16; i++) begin
      W.wr64(W.s_slot(n + VA_WIDTH'(i * 'h1000), 0),
             W.mk_pte(napot(44'(pa[PA_WIDTH-1:12])), PTE_LEAF, 2'b00, 1'b1));
      W.vmap[n[VA_WIDTH-1:12] + (VA_WIDTH-12)'(i)] =
        pa[PA_WIDTH-1:12] + PPN_WIDTH'(i);
    end
    walk_lo = n[VA_WIDTH-1:12];
    walk_hi = n[VA_WIDTH-1:12] + (VA_WIDTH-12)'(16);
    run_at(n + VA_WIDTH'('h10), PC_C + VA_WIDTH'('h100));
    run_at(n + VA_WIDTH'('h5010), PC_C + VA_WIDTH'('h200));
    run_at(n + VA_WIDTH'('hF030), PC_C + VA_WIDTH'('h300));
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf("one walk for three pages of the 64 KiB page (%0d)",
                  n_walk_rng), n_walk_rng == 1);
  endtask

  // ---- Svnapot and MMU-27, two stage ------------------------------------
  task automatic p_pt_napot_h();
    logic [VA_WIDTH-1:0]  va;
    logic [GPA_WIDTH-1:0] ga;
    logic [PA_WIDTH-1:0]  sa;
    tname = "pt_napot_h";
    $display("-- %s --", tname);
    reset_all(1'b1);
    set_h2();
    map_ch();
    // A: VS 4 KiB leaves into a G-stage 64 KiB NAPOT page. Each 4 KiB
    // page walks (the smaller size wins, MMU-27).
    va = VA_WIDTH'('h0_8010_0000);
    ga = GPA_WIDTH'('h0_3000_0000);
    sa = PA_WIDTH'('h0_8150_0000);
    for (int i = 0; i < 16; i++)
      W.wr64(W.g_slot(ga[GPA_WIDTH-1:12] + (GPA_WIDTH-12)'(i), 0),
             W.mk_pte(napot(44'(sa[PA_WIDTH-1:12])), F_URWXAD, 2'b00, 1'b1));
    for (int i = 0; i < 16; i += 3) begin
      W.wr64(W.vs_slot(va + VA_WIDTH'(i * 'h1000), 0),
             W.mk_pte(44'(ga[GPA_WIDTH-1:12]) + 44'(i), PTE_LEAF, 2'b00, 1'b0));
      W.vmap[va[VA_WIDTH-1:12] + (VA_WIDTH-12)'(i)] =
        sa[PA_WIDTH-1:12] + PPN_WIDTH'(i);
    end
    walk_lo = va[VA_WIDTH-1:12];
    walk_hi = va[VA_WIDTH-1:12] + (VA_WIDTH-12)'(16);
    run_at(va + VA_WIDTH'('h10), PC_C + VA_WIDTH'('h100));
    run_at(va + VA_WIDTH'('h3010), PC_C + VA_WIDTH'('h140));
    // B: a VS 64 KiB NAPOT page over G-stage 4 KiB leaves.
    va = VA_WIDTH'('h0_8020_0000);
    ga = GPA_WIDTH'('h0_3010_0000);
    sa = PA_WIDTH'('h0_8160_0000);
    for (int i = 0; i < 16; i++) begin
      W.wr64(W.vs_slot(va + VA_WIDTH'(i * 'h1000), 0),
             W.mk_pte(napot(44'(ga[GPA_WIDTH-1:12])), PTE_LEAF, 2'b00, 1'b1));
      W.wr64(W.g_slot(ga[GPA_WIDTH-1:12] + (GPA_WIDTH-12)'(i), 0),
             W.mk_pte(44'(sa[PA_WIDTH-1:12]) + 44'(i), F_URWXAD, 2'b00, 1'b0));
      W.vmap[va[VA_WIDTH-1:12] + (VA_WIDTH-12)'(i)] =
        sa[PA_WIDTH-1:12] + PPN_WIDTH'(i);
    end
    run_at(va + VA_WIDTH'('h10), PC_C + VA_WIDTH'('h180));
    run_at(va + VA_WIDTH'('h7010), PC_C + VA_WIDTH'('h1C0));
    // C: NAPOT at both stages: 64 KiB, one walk for the page.
    va = VA_WIDTH'('h0_8030_0000);
    walk2_lo = va[VA_WIDTH-1:12];
    walk2_hi = va[VA_WIDTH-1:12] + (VA_WIDTH-12)'(16);
    ga = GPA_WIDTH'('h0_3020_0000);
    sa = PA_WIDTH'('h0_8170_0000);
    for (int i = 0; i < 16; i++) begin
      W.wr64(W.vs_slot(va + VA_WIDTH'(i * 'h1000), 0),
             W.mk_pte(napot(44'(ga[GPA_WIDTH-1:12])), PTE_LEAF, 2'b00, 1'b1));
      W.wr64(W.g_slot(ga[GPA_WIDTH-1:12] + (GPA_WIDTH-12)'(i), 0),
             W.mk_pte(napot(44'(sa[PA_WIDTH-1:12])), F_URWXAD, 2'b00, 1'b1));
      W.vmap[va[VA_WIDTH-1:12] + (VA_WIDTH-12)'(i)] =
        sa[PA_WIDTH-1:12] + PPN_WIDTH'(i);
    end
    run_at(va + VA_WIDTH'('h10), PC_C + VA_WIDTH'('h200));
    run_at(va + VA_WIDTH'('h9010), PC_C + VA_WIDTH'('h240));
    // D: a VS 2 MiB leaf over a G-stage 4 KiB leaf.
    va = VA_WIDTH'('h0_8060_0000);
    ga = GPA_WIDTH'('h0_3040_0000);
    sa = PA_WIDTH'('h0_8180_3000);
    W.wr64(W.vs_slot(va, 1), W.mk_pte(44'(ga >> 12), PTE_LEAF, 2'b00, 1'b0));
    W.wr64(W.g_slot(ga[GPA_WIDTH-1:12] + (GPA_WIDTH-12)'(5), 0),
           W.mk_pte(44'(sa >> 12), F_URWXAD, 2'b00, 1'b0));
    W.vmap[va[VA_WIDTH-1:12] + (VA_WIDTH-12)'(5)] = sa[PA_WIDTH-1:12];
    run_at(va + VA_WIDTH'('h5010), PC_C + VA_WIDTH'('h280));
    // E: a VS 4 KiB leaf over a G-stage 2 MiB leaf.
    va = VA_WIDTH'('h0_8080_0000);
    ga = GPA_WIDTH'('h0_3080_7000);
    sa = PA_WIDTH'('h0_81A0_0000);
    W.wr64(W.vs_slot(va, 0), W.mk_pte(44'(ga >> 12), PTE_LEAF, 2'b00, 1'b0));
    W.wr64(W.g_slot(ga[GPA_WIDTH-1:12], 1),
           W.mk_pte(44'(sa[PA_WIDTH-1:12]), F_URWXAD, 2'b00, 1'b0));
    W.vmap[va[VA_WIDTH-1:12]] = sa[PA_WIDTH-1:12] + PPN_WIDTH'(7);
    run_at(va + VA_WIDTH'('h10), PC_C + VA_WIDTH'('h2C0));
    // The A region again: a second page of A walks again (4 KiB size),
    // the C region's second page did not (64 KiB): counted below.
    warm_e = W.ne + 1;
    end_prog(40000);
    chk($sformatf("G-stage NAPOT under VS 4 KiB: two walks (%0d)",
                  n_walk_rng), n_walk_rng == 2);
    chk($sformatf("NAPOT at both stages: one walk for two pages (%0d)",
                  n_walk_rng2), n_walk_rng2 == 1);
  endtask


  // ---- reserved encodings and PBMTE, single stage ------------------------
  // Every reserved Svnapot encoding (N set with PPN[3:0] other than
  // 1000, N on a superpage, N on a non-leaf), PBMT 3, PBMT on a
  // non-leaf; then, after a CSR write clears menvcfg.PBMTE, a leaf with
  // PBMT NC. Each is a page fault, cause 12.
  task automatic p_pt_rsv_s();
    int                  k;
    logic [VA_WIDTH-1:0] t;
    tname = "pt_rsv_s";
    $display("-- %s --", tname);
    reset_all(1'b1);
    map_ch();
    k = 0;
    for (int lo = 0; lo < 16; lo++) begin
      if (lo == 8) continue;
      t = VA_WIDTH'('h0_8040_0000) + VA_WIDTH'(lo * 'h1000) + VA_WIDTH'('h10);
      W.wr64(W.s_slot(t, 0),
             W.mk_pte({40'h0_0000_8142, 4'(lo)}, PTE_LEAF, 2'b00, 1'b1));
      W.jr_fault(t, IFU_FAULT_PAGE, hnd(k));
      W.mixed(1);
      k++;
    end
    // N on a 2 MiB leaf.
    W.wr64(W.s_slot(tgt(1), 1), W.mk_pte(44'h8_1608, PTE_LEAF, 2'b00, 1'b1));
    W.jr_fault(tgt(1), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(1);
    // N on a non-leaf.
    W.wr64(W.s_slot(tgt(2), 1), W.mk_pte(44'h8_F108, PTE_PTR, 2'b00, 1'b1));
    W.jr_fault(tgt(2), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(1);
    // PBMT 3 on a leaf.
    W.wr64(W.s_slot(tgt(3), 0), W.mk_pte(44'h8_1430, PTE_LEAF, 2'd3, 1'b0));
    W.jr_fault(tgt(3), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(1);
    // PBMT on a non-leaf.
    W.wr64(W.s_slot(tgt(4), 1), W.mk_pte(44'h8_F110, PTE_PTR, 2'd1, 1'b0));
    W.jr_fault(tgt(4), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(1);
    // menvcfg.PBMTE cleared: PBMT NC on a leaf is reserved.
    W.csr_env(1'b0, 1'b0, 1'b0, 1'b1);
    W.mixed(1);
    W.wr64(W.s_slot(tgt(5), 0), W.mk_pte(44'h8_1450, PTE_LEAF, 2'd1, 1'b0));
    W.jr_fault(tgt(5), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(40000);
    chk($sformatf("all %0d faults reached decode (%0d)", k, n_fault_ok),
        n_fault_ok == k);
    chk($sformatf("the CSR write retired (%0d)", n_csrw), n_csrw == 1);
  endtask

  // ---- reserved encodings and PBMTE, two stage ----------------------------
  // At the VS-stage every reserved Svnapot encoding and PBMT 3 is a page
  // fault, 12; at the G-stage the same are guest-page faults, 20, kind
  // 00 with the GPA. Then henvcfg.PBMTE clear makes a VS PBMT a page
  // fault, and menvcfg.PBMTE clear a G-stage PBMT a guest-page fault.
  task automatic p_pt_rsv_h();
    int                   k;
    logic [VA_WIDTH-1:0]  t;
    logic [GPA_WIDTH-1:0] g;
    tname = "pt_rsv_h";
    $display("-- %s --", tname);
    reset_all(1'b1);
    set_h2();
    map_ch();
    k = 0;
    for (int lo = 0; lo < 16; lo++) begin
      if (lo == 8) continue;
      // VS-stage N reserved.
      t = VA_WIDTH'('h0_8040_0000) + VA_WIDTH'(lo * 'h1000) + VA_WIDTH'('h10);
      W.wr64(W.vs_slot(t, 0),
             W.mk_pte({40'h0_0000_0123, 4'(lo)}, PTE_LEAF, 2'b00, 1'b1));
      W.jr_fault(t, IFU_FAULT_PAGE, hnd(k++));
      W.mixed(1);
      // G-stage N reserved.
      t = VA_WIDTH'('h0_8060_0000) + VA_WIDTH'(lo * 'h1000) + VA_WIDTH'('h10);
      g = GPA_WIDTH'('h0_3000_0000) + GPA_WIDTH'(lo * 'h1000);
      h_map(t, g, PA_WIDTH'('h0_8150_0000),
            W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
            W.mk_pte({40'h0_0000_8150, 4'(lo)}, F_URWXAD, 2'b00, 1'b1));
      W.jr_gfault(t, FAULT_GPA_WIDTH'(g | GPA_WIDTH'('h10)), 2'b00, hnd(k++));
      W.mixed(1);
    end
    // VS PBMT 3.
    W.wr64(W.vs_slot(tgt(3), 0), W.mk_pte(44'h0_0124, PTE_LEAF, 2'd3, 1'b0));
    W.jr_fault(tgt(3), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(1);
    // G PBMT 3.
    g = GPA_WIDTH'('h0_3100_0000);
    h_map(tgt(4), g, PA_WIDTH'('h0_8151_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1510, F_URWXAD, 2'd3, 1'b0));
    W.jr_gfault(tgt(4),
                FAULT_GPA_WIDTH'(g | GPA_WIDTH'('h10)), 2'b00, hnd(k++));
    W.mixed(1);
    // henvcfg.PBMTE clear: a VS PBMT NC is reserved, menvcfg's stays set.
    W.csr_env(1'b0, 1'b0, 1'b1, 1'b0);
    W.mixed(1);
    W.wr64(W.vs_slot(tgt(5), 0), W.mk_pte(44'h0_0125, PTE_LEAF, 2'd1, 1'b0));
    W.jr_fault(tgt(5), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(1);
    // menvcfg.PBMTE clear: a G-stage PBMT NC is reserved.
    W.csr_env(1'b0, 1'b0, 1'b0, 1'b1);
    W.mixed(1);
    g = GPA_WIDTH'('h0_3200_0000);
    h_map(tgt(6), g, PA_WIDTH'('h0_8152_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1520, F_URWXAD, 2'd1, 1'b0));
    W.jr_gfault(tgt(6),
                FAULT_GPA_WIDTH'(g | GPA_WIDTH'('h10)), 2'b00, hnd(k++));
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(60000);
    chk($sformatf("all %0d faults reached decode (%0d)", k, n_fault_ok),
        n_fault_ok == k);
    chk($sformatf("two CSR writes retired (%0d)", n_csrw), n_csrw == 2);
  endtask

  // ---- Svade and Svadu, single stage --------------------------------------
  // menvcfg.ADUE clear: a leaf with A clear faults (Svade). After a CSR
  // write sets it, the walker sets A by compare and swap and the fetch
  // proceeds; then the memory model sets A in a PTE between the walk's
  // read and its CAS (WM-11), the CAS fails and the walk restarts.
  task automatic p_pt_ad_s();
    logic [PA_WIDTH-1:0] a1;
    logic [PA_WIDTH-1:0] a2;
    tname = "pt_ad_s";
    $display("-- %s --", tname);
    reset_all(1'b1);
    map_ch();
    W.wr64(W.s_slot(tgt(0), 0),
           W.mk_pte(44'h8_1400, PTE_LEAF & 8'hBF, 2'b00, 1'b0));
    W.jr_fault(tgt(0), IFU_FAULT_PAGE, hnd(0));
    W.mixed(1);
    W.csr_env(1'b1, 1'b0, 1'b1, 1'b1);
    W.mixed(1);
    a1 = W.s_slot(tgt(1), 0);
    W.wr64(a1, W.mk_pte(44'h8_1410, PTE_LEAF & 8'hBF, 2'b00, 1'b0));
    W.vmap[tgt(1)[VA_WIDTH-1:12]] = PPN_WIDTH'(24'h8_1410);
    run_at(tgt(1), hnd(1));
    a2 = W.s_slot(tgt(2), 0);
    W.wr64(a2, W.mk_pte(44'h8_1420, PTE_LEAF & 8'hBF, 2'b00, 1'b0));
    W.vmap[tgt(2)[VA_WIDTH-1:12]] = PPN_WIDTH'(24'h8_1420);
    chg_arm = 1'b1;
    chg_pa  = a2;
    chg_val = W.mk_pte(44'h8_1420, PTE_LEAF, 2'b00, 1'b0);
    run_at(tgt(2), hnd(2));
    warm_e = W.ne + 1;
    end_prog(30000);
    chk("Svade: the A-clear leaf faulted", n_fault_ok == 1);
    chk("Svadu: the walker set A in memory",
        W.rd64(a1) == W.mk_pte(44'h8_1410, (PTE_LEAF & 8'hBF) | 8'h40,
                               2'b00, 1'b0));
    chk($sformatf({"WM-11: the PTE changed before the CAS (%0d) and ",
                   "the walk restarted"}, n_pw_chg),
        (n_pw_chg == 1) && (n_pw_cas == 2));
  endtask

  // ---- Svade and Svadu, two stage -------------------------------------------
  task automatic p_pt_ad_h();
    logic [GPA_WIDTH-1:0] g;
    logic [GPA_WIDTH-1:0] tg;
    logic [PA_WIDTH-1:0]  gl;
    logic [PA_WIDTH-1:0]  vl;
    logic [PA_WIDTH-1:0]  gl5;
    logic [PA_WIDTH-1:0]  vl1;
    logic [PA_WIDTH-1:0]  gl1;
    tname = "pt_ad_h";
    $display("-- %s --", tname);
    reset_all(1'b1);
    set_h2();
    csr_ptw_menvcfg_adue = 1'b1;
    csr_ptw_henvcfg_adue = 1'b1;
    map_ch();
    // 1 (h 1, m 1): the VS update writes through the G-stage and sets
    // the G-stage D of the VS table page (MMU-8a), then executes.
    g = GPA_WIDTH'('h0_2000_0000);
    h_map(tgt(1), g, PA_WIDTH'('h0_8140_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF & 8'hBF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1400, F_URWXAD, 2'b00, 1'b0));
    tg  = vs_l0_gpa(tgt(1));
    gl1 = W.g_slot(tg[GPA_WIDTH-1:12], 0);
    W.wr64(gl1, W.mk_pte(44'(W.g2s(tg) >> 12), 8'h5F, 2'b00, 1'b0)); // D clear
    vl1 = W.vs_slot(tgt(1), 0);
    run_at(tgt(1), hnd(1));
    // 2 (h 1, m 1): the G-stage leaf of the VS table page grants no
    // write: guest-page fault, kind 10.
    g = GPA_WIDTH'('h0_2200_0000);
    h_map(tgt(2), g, PA_WIDTH'('h0_8141_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF & 8'hBF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1410, F_URWXAD, 2'b00, 1'b0));
    tg = vs_l0_gpa(tgt(2));
    W.wr64(W.g_slot(tg[GPA_WIDTH-1:12], 0),
           W.mk_pte(44'(W.g2s(tg) >> 12), 8'hDB, 2'b00, 1'b0));
    W.jr_gfault(tgt(2),
                FAULT_GPA_WIDTH'(tg + GPA_WIDTH'(8 * tgt(2)[20:12])),
                2'b10, hnd(2));
    W.mixed(1);
    // 3 (h 1, m 0): the VS-stage is Svadu, the G-stage Svade: the G D
    // the update needs faults, kind 10.
    W.csr_env(1'b0, 1'b1, 1'b1, 1'b1);
    W.mixed(1);
    g = GPA_WIDTH'('h0_2400_0000);
    h_map(tgt(3), g, PA_WIDTH'('h0_8142_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF & 8'hBF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1420, F_URWXAD, 2'b00, 1'b0));
    tg = vs_l0_gpa(tgt(3));
    W.wr64(W.g_slot(tg[GPA_WIDTH-1:12], 0),
           W.mk_pte(44'(W.g2s(tg) >> 12), 8'h5F, 2'b00, 1'b0));       // D clear
    W.jr_gfault(tgt(3),
                FAULT_GPA_WIDTH'(tg + GPA_WIDTH'(8 * tgt(3)[20:12])),
                2'b10, hnd(3));
    W.mixed(1);
    // 4, 5 (h 0, m 1): the VS-stage is Svade, the G-stage Svadu.
    W.csr_env(1'b1, 1'b0, 1'b1, 1'b1);
    W.mixed(1);
    g = GPA_WIDTH'('h0_2600_0000);
    h_map(tgt(4), g, PA_WIDTH'('h0_8143_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF & 8'hBF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1430, F_URWXAD, 2'b00, 1'b0));
    W.jr_fault(tgt(4), IFU_FAULT_PAGE, hnd(4));
    W.mixed(1);
    g   = GPA_WIDTH'('h0_2800_0000);
    h_map(tgt(5), g, PA_WIDTH'('h0_8144_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1440, 8'h9F, 2'b00, 1'b0));                  // A clear
    gl5 = W.g_slot(g[GPA_WIDTH-1:12], 0);
    run_at(tgt(5), hnd(5));
    // 6 (h 1, m 1): the VS leaf changes before its CAS (WM-11).
    W.csr_env(1'b1, 1'b1, 1'b1, 1'b1);
    W.mixed(1);
    g = GPA_WIDTH'('h0_2A00_0000);
    h_map(tgt(6), g, PA_WIDTH'('h0_8145_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF & 8'hBF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1450, F_URWXAD, 2'b00, 1'b0));
    vl      = W.vs_slot(tgt(6), 0);
    chg_arm = 1'b1;
    chg_pa  = vl;
    chg_val = W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0);
    run_at(tgt(6), hnd(6));
    warm_e = W.ne + 1;
    end_prog(60000);
    chk($sformatf("three faults (%0d)", n_fault_ok), n_fault_ok == 3);
    chk("the VS update set the VS leaf's A",
        W.rd64(vl1)[6] == 1'b1);
    chk("and the G-stage D of its table page",
        W.rd64(gl1)[7] == 1'b1);
    chk("G-stage Svadu set the code page's G leaf A",
        W.rd64(gl5)[6] == 1'b1);
    chk($sformatf("WM-11 restart (%0d)", n_pw_chg), n_pw_chg == 1);
  endtask

  // ---- an ITLB invalidate while a walk is in progress ---------------------
  // ITLB-14, IL-13, IL-14: the walk completes and is answered, the ITLB
  // installs nothing from it, and the next lookup walks again.
  task automatic p_pt_inv();
    tname = "pt_inv";
    $display("-- %s --", tname);
    reset_all(1'b1);
    pw_lat_min = 10;
    pw_lat_max = 10;
    map_ch();
    W.map4k(tgt(1) - VA_WIDTH'('h10), PA_WIDTH'('h0_8140_0000));
    walk_lo   = tgt(1)[VA_WIDTH-1:12];
    walk_hi   = tgt(1)[VA_WIDTH-1:12] + (VA_WIDTH-12)'(1);
    inv_watch = 1'b1;
    inv_vpn   = tgt(1)[VA_WIDTH-1:12];
    run_at(tgt(1), hnd(1));
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf({"the invalidate fired while the walker was walking ",
                   "(%0d of %0d)"}, n_inv_busy, n_inv_fired),
        (n_inv_fired == 1) && (n_inv_busy == 1));
    chk($sformatf("the page was walked again (%0d walks)", n_walk_rng),
        n_walk_rng >= 2);
  endtask


  // =================================================================
  // BP-123, Problem 5: the RVA23 extensions that reach fetch and
  // decode. Every Zcb encoding, every C.MOP.n (Zcmop), every MOP.R.n
  // and MOP.RR.n (Zimop) and the three Zicbop prefetches, through the
  // expander, predecode, the ibuf and decode. A 16-bit encoding's
  // expected expansion is the LLVM oracle's (ifu/tb/
  // ifu_rvc_exp_oracle.hex, BP-117), not this file's; decode must not
  // raise illegal and must give the named operation; predecode must
  // class none of them as a control transfer.
  // =================================================================
  logic [39:0] rvc_orc [0:65535];

  task automatic zc(input logic [15:0] c, input alu_op_t op);
    W.put_hw(W.wp, c);
    W.add_ex(W.wp, rvc_orc[c][31:0], 1'b1, NO_BRANCH, 1'b0, '0);
    W.ex[W.ne-1].aluop = int'(op);
    W.wp = W.wp + VA_WIDTH'(2);
  endtask

  task automatic z32(input logic [31:0] w, input alu_op_t op);
    W.i32(w);
    W.ex[W.ne-1].aluop = int'(op);
  endtask

  task automatic p_zstar();
    int n_zcb;
    int n_cls;
    begin_prog("zstar");
    $readmemh("../ifu/tb/ifu_rvc_exp_oracle.hex", rvc_orc);
    W.mixed(2);
    n_zcb = 0;
    n_cls = 0;
    // Zcb. c.lbu, c.lhu, c.lh, c.sb, c.sh (quadrant 0); c.zext.b,
    // c.sext.b, c.zext.h, c.sext.h, c.zext.w, c.not, c.mul (quadrant 1).
    for (int x = 0; x < 256; x++) begin           // rs1', uimm, rd'/rs2'
      logic [2:0] r1;
      logic [1:0] ui;
      logic [2:0] r2;
      r1 = x[7:5];
      ui = x[4:3];
      r2 = x[2:0];
      zc({6'b100000, r1, ui, r2, 2'b00}, ALU_LBU);
      zc({6'b100010, r1, ui, r2, 2'b00}, ALU_SB);
      n_zcb += 2;
      if (!ui[1]) begin
        zc({6'b100001, r1, 1'b0, ui[0], r2, 2'b00}, ALU_LHU);
        zc({6'b100001, r1, 1'b1, ui[0], r2, 2'b00}, ALU_LH);
        zc({6'b100011, r1, 1'b0, ui[0], r2, 2'b00}, ALU_SH);
        n_zcb += 3;
      end
    end
    for (int r = 0; r < 8; r++) begin
      zc({6'b100111, 3'(r), 5'b11000, 2'b01}, ALU_ANDI);    // c.zext.b
      zc({6'b100111, 3'(r), 5'b11001, 2'b01}, ALU_SEXTB);
      zc({6'b100111, 3'(r), 5'b11010, 2'b01}, ALU_ZEXTH);
      zc({6'b100111, 3'(r), 5'b11011, 2'b01}, ALU_SEXTH);
      zc({6'b100111, 3'(r), 5'b11100, 2'b01}, ALU_ADDUW);   // c.zext.w
      zc({6'b100111, 3'(r), 5'b11101, 2'b01}, ALU_XOR);     // c.not
      n_zcb += 6;
      for (int r2 = 0; r2 < 8; r2++) begin
        zc({6'b100111, 3'(r), 2'b10, 3'(r2), 2'b01}, ALU_MUL);
        n_zcb++;
      end
    end
    for (int e = 0; e < W.ne; e++) begin
      logic [15:0] c;
      c = {W.rd8(W.va2pa(W.ex[e].pc) + PA_WIDTH'(1)),
           W.rd8(W.va2pa(W.ex[e].pc))};
      if (W.ex[e].rvc && (W.ex[e].aluop >= 0) && (rvc_orc[c][39:32] == 8'd1))
        n_cls++;
    end
    // Zcmop: C.MOP.n, n = 1, 3, ..., 15: c.lui's space with rd = n,
    // nzimm 0. The oracle's class 5: the canonical NOP.
    for (int n = 1; n < 16; n += 2)
      zc({3'b011, 1'b0, 5'(n), 5'b00000, 2'b01}, ALU_ADD);
    // Zimop: MOP.R.n, n = 0..31, and MOP.RR.n, n = 0..7, rd a0, rs1 a1,
    // rs2 a2: write zero to rd.
    for (int n = 0; n < 32; n++)
      z32({1'b1, 1'(n >> 4), 2'b00, 2'(n >> 2), 4'b0111, 2'(n), 5'd11,
           3'b100, 5'd10, 7'b1110011}, ALU_MOP);
    for (int n = 0; n < 8; n++)
      z32({1'b1, 1'(n >> 2), 2'b00, 2'(n), 1'b1, 5'd12, 5'd11, 3'b100,
           5'd10, 7'b1110011}, ALU_MOP);
    // Zicbop: prefetch.i, .r, .w 64(a1) (LLVM's words): the ORI HINT.
    z32(32'h0405_E013, ALU_OR);
    z32(32'h0415_E013, ALU_OR);
    z32(32'h0435_E013, ALU_OR);
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(40000);
    chk($sformatf("every Zcb encoding ran (%0d)", n_zcb), n_zcb == 1008);
    chk($sformatf("each expansion is the LLVM oracle's, class 1 (%0d)", n_cls),
        n_cls == 1008);
  endtask


  // ---- the other two vsatp / hgatp combinations, end to end -------------
  // G-stage only (vsatp Bare, hgatp Sv39x4): the fetch address is the
  // GPA, 41 bits (FE-19, MMU-20), and the walker returns the G-stage
  // leaf; the ITLB's VS-level permission rule has no leaf to read
  // (ITLB-16, fixed by BP-123). Code runs at a GPA with bit 40 set,
  // and an unmapped GPA is a guest-page fault, kind 00.
  task automatic p_pt_gonly();
    logic [VA_WIDTH-1:0] hi;
    tname = "pt_gonly";
    $display("-- %s --", tname);
    reset_all(1'b1);
    set_h2();
    csr_itlb_vsatp_mode = 4'd0;
    csr_ptw_vsatp_mode  = 4'd0;
    W.vmap.delete();

    W.g_map(RESET_VECTOR[VA_WIDTH-1:12], PA_WIDTH'(RESET_VECTOR),
            W.mk_pte(44'(RESET_VECTOR >> 12), F_URWXAD, 2'b00, 1'b0));
    W.vmap[RESET_VECTOR[VA_WIDTH-1:12]] = PPN_WIDTH'(RESET_VECTOR >> 12);
    W.g_map(PC_C[VA_WIDTH-1:12], PA_C, W.mk_pte(44'(PA_C >> 12), F_URWXAD,
                                               2'b00, 1'b0));
    W.vmap[PC_C[VA_WIDTH-1:12]] = PA_C[PA_WIDTH-1:12];
    W.g_map(PC_H[VA_WIDTH-1:12], PA_H, W.mk_pte(44'(PA_H >> 12), F_URWXAD,
                                               2'b00, 1'b0));
    W.vmap[PC_H[VA_WIDTH-1:12]] = PA_H[PA_WIDTH-1:12];
    hi = VA_WIDTH'('h100_8000_3000);                // GPA bit 40
    W.g_map(hi[VA_WIDTH-1:12], PA_WIDTH'('h0_8145_0000),
            W.mk_pte(44'h8_1450, F_URWXAD, 2'b00, 1'b0));
    W.vmap[hi[VA_WIDTH-1:12]] = PPN_WIDTH'(24'h8_1450);
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, PC_C);
    W.mixed(4);
    run_at(hi + VA_WIDTH'('h20), PC_C + VA_WIDTH'('h100));
    W.jr_gfault(VA_WIDTH'('h0_8070_0010),
                FAULT_GPA_WIDTH'(GPA_WIDTH'('h0_8070_0010)), 2'b00,
                hnd(1));
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf("the guest-page fault reached decode (%0d)", n_fault_ok),
        n_fault_ok == 1);
  endtask

  // VS-stage only (vsatp Sv39, hgatp Bare): a GPA is the SPA. A VS leaf
  // whose PPN names an address above PA_WIDTH is then an access fault
  // (MMU-28 for a supervisor physical page; there is no G-stage to give
  // a guest-page fault), and an invalid leaf a page fault.
  task automatic p_pt_vsonly();
    tname = "pt_vsonly";
    $display("-- %s --", tname);
    reset_all(1'b1);
    W.h2     = 1'b1;
    W.g_bare = 1'b1;
    W.vs_root = W.vs_alloc();
    csr_itlb_v            = 1'b1;
    csr_itlb_priv         = 2'd1;
    csr_itlb_satp_mode    = 4'd0;
    csr_itlb_vsatp_mode   = 4'd8;
    csr_itlb_vsatp_asid   = ASID_WIDTH'(1);
    csr_itlb_hgatp_mode   = 4'd0;
    csr_itlb_hgatp_vmid   = VMID_WIDTH'(3);
    csr_ptw_satp_mode     = 4'd0;
    csr_ptw_vsatp_mode    = 4'd8;
    csr_ptw_vsatp_ppn     = (GPA_WIDTH-12)'(W.vs_root >> 12);
    csr_ptw_hgatp_mode    = 4'd0;

    W.wr64(W.vs_slot(RESET_VECTOR, 0),
           W.mk_pte(44'(RESET_VECTOR >> 12), PTE_LEAF, 2'b00, 1'b0));
    W.vmap[RESET_VECTOR[VA_WIDTH-1:12]] = PPN_WIDTH'(RESET_VECTOR >> 12);
    W.wr64(W.vs_slot(PC_C, 0),
           W.mk_pte(44'(PA_C >> 12), PTE_LEAF, 2'b00, 1'b0));
    W.vmap[PC_C[VA_WIDTH-1:12]] = PA_C[PA_WIDTH-1:12];
    W.wr64(W.vs_slot(PC_H, 0),
           W.mk_pte(44'(PA_H >> 12), PTE_LEAF, 2'b00, 1'b0));
    W.vmap[PC_H[VA_WIDTH-1:12]] = PA_H[PA_WIDTH-1:12];
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, PC_C);
    W.mixed(4);
    W.wr64(W.vs_slot(tgt(1), 0),
           W.mk_pte(44'h100_8140, PTE_LEAF, 2'b00, 1'b0));
    W.jr_fault(tgt(1), IFU_FAULT_ACCESS, hnd(1));
    W.mixed(2);
    W.wr64(W.vs_slot(tgt(2), 0), W.mk_pte(44'h8_1410, 8'hC5, 2'b00, 1'b0));
    W.jr_fault(tgt(2), IFU_FAULT_PAGE, hnd(2));
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf("both faults reached decode (%0d)", n_fault_ok),
        n_fault_ok == 2);
  endtask

  // =================================================================
  // ---- BP-124: U against the privilege before A (MMU-8c), and a held
  // fault is the answer only at its own privilege (ITLB-10b) ----------
  // Under Svadu (menvcfg.ADUE set), single stage:
  //   0  at U, a fetch from a U-clear page with A clear: cause 12, the
  //      trap taken to S, A still clear in memory
  //   1  at S, a fetch from a U-set page with A clear: cause 12, A
  //      still clear
  //   2  at U, the block after a JAL that ends the U code page falls
  //      into page p2 (U clear, A clear) on the wrong path: the ITLB
  //      walks it at U and the walk faults; the predecode redirect has
  //      flushed the block, so the fault is held and not collected.
  //      After an ecall to S, a fetch at S of p2 must drop the held U
  //      fault, walk at S and execute; that walk sets p2's A
  // The U code page is U set with A and D set.
  localparam logic [VA_WIDTH-1:0] PC_U = VA_WIDTH'('h0_8003_0000);
  localparam logic [PA_WIDTH-1:0] PA_U = PA_WIDTH'('h0_8170_0000);

  task automatic p_pt_upriv();
    logic [PA_WIDTH-1:0] a0;
    logic [PA_WIDTH-1:0] a1;
    logic [PA_WIDTH-1:0] a2;
    logic [VA_WIDTH-1:0] p2;
    logic [63:0]         l0;
    logic [63:0]         l1;
    logic [63:0]         l2;
    tname = "pt_upriv";
    $display("-- %s --", tname);
    reset_all(1'b1);
    csr_ptw_menvcfg_adue = 1'b1;                     // Svadu
    map_ch();
    W.wr64(W.s_slot(PC_U, 0), W.mk_pte(44'(PA_U >> 12), PTE_LEAF | 8'h10,
                                       2'b00, 1'b0));
    W.vmap[PC_U[VA_WIDTH-1:12]] = PA_U[PA_WIDTH-1:12];
    p2 = PC_U + VA_WIDTH'('h1000);
    a0 = W.s_slot(tgt(0), 0);
    a1 = W.s_slot(tgt(1), 0);
    a2 = W.s_slot(p2, 0);
    l0 = W.mk_pte(44'h8_1400, PTE_LEAF & 8'hBF, 2'b00, 1'b0);        // A
    l1 = W.mk_pte(44'h8_1410, (PTE_LEAF & 8'hBF) | 8'h10, 2'b00, 1'b0);
    l2 = W.mk_pte(44'h8_1420, PTE_LEAF & 8'hBF, 2'b00, 1'b0);
    W.wr64(a0, l0);
    W.wr64(a1, l1);
    W.wr64(a2, l2);
    W.vmap[p2[VA_WIDTH-1:12]] = PPN_WIDTH'(24'h8_1420);
    up_vpn = p2[VA_WIDTH-1:12];
    // 0: to U, then a fetch from the U-clear page.
    W.sret_to(PC_U + VA_WIDTH'('h100), 2'd0);
    W.mixed(2);
    W.jr_fault(tgt(0), IFU_FAULT_PAGE, hnd(0));
    W.ex[W.ne-1].npriv = 1;                          // the trap, to S
    W.mixed(2);
    // 1: at S, a fetch from the U-set page.
    W.jr_fault(tgt(1), IFU_FAULT_PAGE, hnd(1));
    W.mixed(2);
    // 2: to U at the last 32-byte block of the U page, which ends with
    // a JAL back into the page; the fall-through block is p2.
    W.sret_to(PC_U + VA_WIDTH'('hFE0), 2'd0);
    for (int i = 0; i < 7; i++) W.i32(ADDI_T0);
    W.jal(5'd0, PC_U + VA_WIDTH'('h200));
    W.mixed(2);
    W.ecall(hnd(2));
    W.ex[W.ne-1].npriv = 1;                          // to S
    W.mixed(2);
    run_at(p2 + VA_WIDTH'('h10), hnd(3));
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf("both privilege faults reached decode (%0d)",
                  n_fault_ok), n_fault_ok == 2);
    chk("0: a U fetch from a U-clear page left A clear",
        W.rd64(a0) == l0);
    chk("1: an S fetch from a U-set page left A clear",
        W.rd64(a1) == l1);
    chk($sformatf("2: p2 was walked at U and faulted (%0d)", n_up_wu_flt),
        n_up_wu_flt >= 1);
    chk($sformatf("2: the held U fault was dropped at S (%0d)", n_up_drop),
        n_up_drop >= 1);
    chk($sformatf("2: p2 was walked at S and hit (%0d)", n_up_ws_hit),
        n_up_ws_hit == 1);
    chk("2: the S walk set p2's A", W.rd64(a2) == (l2 | 64'h40));
  endtask

  // Program selection. +PROG=<name> runs one program; without it,
  // every program runs.
  // =================================================================
  task automatic run_prog(input string nm);
    case (nm)
      "bare":       p_bare();
      "sv39":       p_sv39();
      "loops":      p_loops();
      "coro":       p_coro();
      "calls":      p_calls();
      "lp":         p_lp();
      "hist":       p_hist();
      "twocond":    p_twocond();
      "ftbonly":    p_ftbonly();
      "nest":       p_nest();
      "recur":      p_recur();
      "deep":       p_deep();
      "indir":      p_indir();
      "region":     p_region();
      "multistart": p_multistart();
      "cross":      p_cross();
      "rvc":        p_rvc();
      "misp_call":  p_misp_call();
      "jals":       p_jals();
      "fencei":     p_smc(1);
      "cboinval":   p_smc(2);
      "uc_nc":      p_uc(2'd1);
      "uc_io":      p_uc(2'd2);
      "pt_faults_s": p_pt_faults_s();
      "pt_faults_h": p_pt_faults_h();
      "pt_napot_s": p_pt_napot_s();
      "pt_napot_h": p_pt_napot_h();
      "pt_rsv_s":   p_pt_rsv_s();
      "pt_rsv_h":   p_pt_rsv_h();
      "pt_ad_s":    p_pt_ad_s();
      "pt_ad_h":    p_pt_ad_h();
      "pt_inv":     p_pt_inv();
      "zstar":      p_zstar();
      "pt_gonly":   p_pt_gonly();
      "pt_vsonly":  p_pt_vsonly();
      "pt_upriv":   p_pt_upriv();
      default: begin
        fail_cnt++;
        $display("FAIL: unknown program %s", nm);
      end
    endcase
  endtask

  string all_progs [0:35] = '{"bare", "sv39", "loops", "coro", "calls",
                              "lp", "hist", "twocond", "ftbonly", "nest",
                              "recur", "deep", "indir", "region",
                              "multistart", "cross", "rvc", "misp_call",
                              "jals", "fencei", "cboinval", "uc_nc",
                              "uc_io", "pt_faults_s", "pt_faults_h",
                              "pt_napot_s", "pt_napot_h", "pt_rsv_s",
                              "pt_rsv_h", "pt_ad_s", "pt_ad_h", "pt_inv",
                              "zstar", "pt_gonly", "pt_vsonly",
                              "pt_upriv"};

  // =================================================================
  initial begin
    string prog;
    pass_cnt = 0;
    fail_cnt = 0;
    // BP-122: one program per simulation. The mode that ran every
    // program in one simulation carried the RAM predictor tables from
    // one program into the next: the FTB array has no reset, and the
    // TAGE, ITTAGE and SC tables are filled once, at time 0, by the
    // FAST_INIT plusargs every run uses. It is removed rather than given
    // a table reset, which the RTL does not have and the testbench would
    // have to force into every RAM. sim_fe_top runs each program alone.
    if ($value$plusargs("PROG=%s", prog)) begin
      run_prog(prog);
    end else begin
      fail_cnt++;
      $display("FAIL: +PROG=<name> is required; programs:");
      foreach (all_progs[i]) $display("  %s", all_progs[i]);
    end
    $display("tb_fe_top: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fe_top: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #30000000;
    $fatal(1, "tb_fe_top: timeout");
  end

endmodule : tb
