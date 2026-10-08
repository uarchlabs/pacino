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
//             line) and holds the page tables the L2 TLB model walks
//   L2 TLB    walks Sv39 from the satp root this file sets, in that
//             memory, and answers the ITLB with the IL-4 status, the
//             IL-7 size, the PTE low byte as perm and the PBMT
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
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;
import decode_pkg::*;

module tb;

  localparam int MAXE    = 4096;
  localparam int TL_LAT  = 6;      // memory latency, request to beat 0
  localparam int L2T_LAT = 5;      // L2 TLB walk latency

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
  logic [GPA_WIDTH-1:0]        l2t_itlb_gpa;
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

  // ---- bookkeeping ----------------------------------------------------
  int    pass_cnt;
  int    fail_cnt;
  string tname;
  int    cyc;

  always @(posedge clk) cyc <= rstn ? cyc + 1 : 0;

  task automatic chk(input string nm, input logic cond);
    if (cond) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: [%s] %s", tname, nm);
    end
  endtask

  // =================================================================
  // Memory: bytes, physical.
  // =================================================================
  logic [7:0] mem [logic [PA_WIDTH-1:0]];

  function automatic logic [7:0] rd8(input logic [PA_WIDTH-1:0] a);
    return mem.exists(a) ? mem[a] : 8'h00;
  endfunction

  function automatic logic [63:0] rd64(input logic [PA_WIDTH-1:0] a);
    logic [63:0] d;
    for (int i = 0; i < 8; i++) d[8*i +: 8] = rd8(a + PA_WIDTH'(i));
    return d;
  endfunction

  function automatic void wr64(input logic [PA_WIDTH-1:0] a,
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

  function automatic logic [PA_WIDTH-1:0] va2pa(input logic [VA_WIDTH-1:0] va);
    logic [VA_WIDTH-13:0] v;
    if (!sv39) return va[PA_WIDTH-1:0];
    v = va[VA_WIDTH-1:12];
    if (!vmap.exists(v)) begin
      $display("tb_fe_top: write to an unmapped VA %011h", va);
      return '0;
    end
    return {vmap[v], va[11:0]};
  endfunction

  // A page table page, zeroed, from the bump allocator.
  function automatic logic [PA_WIDTH-1:0] pt_alloc();
    logic [PA_WIDTH-1:0] p;
    p       = pt_next;
    pt_next = pt_next + PA_WIDTH'('h1000);
    for (int i = 0; i < 512; i++) wr64(p + PA_WIDTH'(8 * i), '0);
    return p;
  endfunction

  // Map one 4 KiB page, V R X A D, supervisor (U clear).
  localparam logic [7:0] PTE_LEAF = 8'hCB;
  localparam logic [7:0] PTE_PTR  = 8'h01;

  task automatic map4k(input logic [VA_WIDTH-1:0] va,
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
  } ex_t;

  ex_t ex [0:MAXE-1];
  int  ne;

  task automatic put_hw(input logic [VA_WIDTH-1:0] va,
                        input logic [15:0] h);
    logic [PA_WIDTH-1:0] pa;
    pa = va2pa(va);
    mem[pa]                 = h[7:0];
    mem[pa + PA_WIDTH'(1)]  = h[15:8];
  endtask

  task automatic add_ex(input logic [VA_WIDTH-1:0] pc,
                        input logic [31:0] w, input logic rvc,
                        input bp_br_type_e bt, input logic tk,
                        input logic [VA_WIDTH-1:0] tgt);
    ex[ne].pc     = pc;
    ex[ne].instr  = w;
    ex[ne].rvc    = rvc;
    ex[ne].btype  = bt;
    ex[ne].taken  = tk;
    ex[ne].target = tgt;
    ex[ne].trap   = 1'b0;
    ex[ne].fault  = IFU_FAULT_NONE;
    ex[ne].fva    = '0;
    ne++;
  endtask

  // Encoders.
  function automatic logic [31:0] enc_jal(input logic [4:0] rd,
                                          input int imm);
    logic [20:0] o;
    o = 21'(imm);
    return {o[20], o[10:1], o[11], o[19:12], rd, 7'b1101111};
  endfunction

  function automatic logic [31:0] enc_br(input logic [2:0] f3,
                                         input int imm);
    logic [12:0] o;
    o = 13'(imm);
    return {o[12], o[10:5], 5'd0, 5'd0, f3, o[4:1], o[11], 7'b1100011};
  endfunction

  localparam logic [31:0] ADDI_T0 = 32'h0012_8293;   // addi t0,t0,1
  localparam logic [15:0] CADDI   = 16'h0505;        // c.addi a0,1
  localparam logic [31:0] CADDI_X = 32'h0015_0513;   // its expansion
  localparam logic [31:0] RET     = 32'h0000_8067;   // jalr x0,0(ra)
  localparam logic [31:0] ECALL   = 32'h0000_0073;

  // The write cursor and the instructions it emits. Each one is
  // written and appended as executed.
  logic [VA_WIDTH-1:0] wp;

  task automatic i32(input logic [31:0] w);
    put_hw(wp, w[15:0]);
    put_hw(wp + VA_WIDTH'(2), w[31:16]);
    add_ex(wp, w, 1'b0, NO_BRANCH, 1'b0, '0);
    wp = wp + VA_WIDTH'(4);
  endtask

  task automatic i16();
    put_hw(wp, CADDI);
    add_ex(wp, CADDI_X, 1'b1, NO_BRANCH, 1'b0, '0);
    wp = wp + VA_WIDTH'(2);
  endtask

  // n instructions of mixed length, a fixed pattern.
  task automatic mixed(input int n);
    for (int k = 0; k < n; k++) begin
      if ((k % 3) == 1) i32(ADDI_T0);
      else              i16();
    end
  endtask

  // A conditional, beq x0,x0 (taken) or bne x0,x0 (not taken).
  task automatic cond(input logic tk, input logic [VA_WIDTH-1:0] tgt);
    logic [31:0] w;
    w = enc_br(tk ? 3'b000 : 3'b001, int'(tgt - wp));
    put_hw(wp, w[15:0]);
    put_hw(wp + VA_WIDTH'(2), w[31:16]);
    add_ex(wp, w, 1'b0, COND, tk, tk ? tgt : wp + VA_WIDTH'(4));
    wp = tk ? tgt : wp + VA_WIDTH'(4);
  endtask

  // jal rd, tgt. rd = x1 is a call.
  task automatic jal(input logic [4:0] rd, input logic [VA_WIDTH-1:0] tgt);
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
  task automatic ret(input logic [VA_WIDTH-1:0] link);
    put_hw(wp, RET[15:0]);
    put_hw(wp + VA_WIDTH'(2), RET[31:16]);
    add_ex(wp, RET, 1'b0, RETURN, 1'b1, link);
    wp = link;
  endtask

  // ecall, trapping to the handler.
  task automatic ecall(input logic [VA_WIDTH-1:0] handler);
    put_hw(wp, ECALL[15:0]);
    put_hw(wp + VA_WIDTH'(2), ECALL[31:16]);
    add_ex(wp, ECALL, 1'b0, NO_BRANCH, 1'b0, handler);
    ex[ne-1].trap = 1'b1;
    wp = handler;
  endtask

  // jal x0 to an address whose fetch faults: the JAL, then the
  // faulting fetch, which traps to the handler. Nothing is written
  // at the target.
  task automatic jal_fault(input logic [VA_WIDTH-1:0] tgt,
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
  task automatic halt();
    logic [31:0] w;
    w = enc_jal(5'd0, 0);
    put_hw(wp, w[15:0]);
    put_hw(wp + VA_WIDTH'(2), w[31:16]);
    add_ex(wp, w, 1'b0, DIRECT_UNC, 1'b1, wp);
  endtask

  // ---- BP-119 additions ---------------------------------------------
  // A conditional on a register, bne rs1, x0 (the loop branch). Its
  // outcome is the writer's: tk is this execution's direction.
  function automatic logic [31:0] enc_bner(input logic [4:0] rs1,
                                           input int imm);
    logic [12:0] o;
    o = 13'(imm);
    return {o[12], o[10:5], 5'd0, rs1, 3'b001, o[4:1], o[11], 7'b1100011};
  endfunction

  function automatic logic [31:0] enc_jalr(input logic [4:0] rd,
                                           input logic [4:0] rs1);
    return {12'd0, rs1, 3'b000, rd, 7'b1100111};
  endfunction

  // The loop branch at the end of a loop body, written taken back to
  // the body start; rep_iter appends the other iterations.
  task automatic loop_br(input logic [VA_WIDTH-1:0] top);
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
  task automatic rep_iter(input int e0, input int n);
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
  task automatic jalr_to(input logic [4:0] rd, input logic [4:0] rs1,
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
            rd8(q_addr[d_src] + PA_WIDTH'(32 * int'(d_beat) + b));
        end
      end
    end
  end

  // =================================================================
  // The L2 TLB model: an Sv39 walk of this memory.
  // =================================================================
  logic                 w_val  [0:3];
  int                   w_due  [0:3];
  logic [1:0]           w_st   [0:3];
  logic [PPN_WIDTH-1:0] w_ppn  [0:3];
  logic [2:0]           w_sz   [0:3];
  logic [7:0]           w_perm [0:3];
  int                   n_walks;

  assign itlb_l2t_req_rdy = rstn;

  task automatic walk(input logic [VA_WIDTH-13:0] vpn, output logic [1:0] st,
                      output logic [PPN_WIDTH-1:0] ppn, output logic [2:0] sz,
                      output logic [7:0] perm);
    logic [PA_WIDTH-1:0] t;
    logic [63:0]         pte;
    logic [8:0]          vi;
    st   = 2'b01;                 // fault, cause 12
    ppn  = '0;
    sz   = 3'b000;
    perm = '0;
    t    = satp_root;
    for (int l = 2; l >= 0; l--) begin
      vi  = vpn[9*l +: 9];
      pte = rd64(t + PA_WIDTH'(8 * vi));
      if (!pte[0] || (!pte[1] && pte[2])) return;
      if (pte[1] || pte[3]) begin
        st   = 2'b00;
        ppn  = PPN_WIDTH'(pte[53:10]);
        // IL-7: 000 4 KiB, 010 2 MiB, 011 1 GiB (this model returns
        // no 64 KiB page and no reserved code).
        sz   = (l == 2) ? 3'b011 : ((l == 1) ? 3'b010 : 3'b000);
        perm = pte[7:0];
        return;
      end
      t = PA_WIDTH'(pte[53:10]) << 12;
    end
  endtask

  initial begin : l2t_model
    logic                 s_req;
    logic [1:0]           s_tag;
    logic [VA_WIDTH-13:0] s_vpn;
    int                   r;
    l2t_itlb_rsp_val = 1'b0;
    l2t_itlb_tag     = '0;
    l2t_itlb_status  = '0;
    l2t_itlb_ppn     = '0;
    l2t_itlb_size    = '0;
    l2t_itlb_perm    = '0;
    l2t_itlb_pbmt    = '0;
    l2t_itlb_cause   = '0;
    l2t_itlb_gpa     = '0;
    for (int i = 0; i < 4; i++) w_val[i] = 1'b0;
    forever begin
      @(posedge clk);
      s_req = rstn && itlb_l2t_req_val && itlb_l2t_req_rdy;
      s_tag = itlb_l2t_tag;
      s_vpn = itlb_l2t_vpn;
      #1;
      l2t_itlb_rsp_val = 1'b0;
      if (!rstn) begin
        for (int i = 0; i < 4; i++) w_val[i] = 1'b0;
      end else begin
        r = -1;
        for (int i = 0; i < 4; i++)
          if (w_val[i] && (w_due[i] <= cyc) && (r < 0)) r = i;
        if (r >= 0) begin
          w_val[r]         = 1'b0;
          l2t_itlb_rsp_val = 1'b1;
          l2t_itlb_tag     = 2'(r);
          l2t_itlb_status  = w_st[r];
          l2t_itlb_ppn     = w_ppn[r];
          l2t_itlb_size    = w_sz[r];
          l2t_itlb_perm    = w_perm[r];
          l2t_itlb_cause   = (w_st[r] == 2'b01) ? CAUSE_WIDTH'(12) : '0;
        end
        if (s_req) begin
          w_val[s_tag] = 1'b1;
          w_due[s_tag] = cyc + L2T_LAT;
          walk(s_vpn, w_st[s_tag], w_ppn[s_tag], w_sz[s_tag],
               w_perm[s_tag]);
          n_walks++;
        end
      end
    end
  end

  // =================================================================
  // The FTQ fetch log: the block start the FTQ presented for each
  // index, taken from the FTQ-to-IFU fetch handshake inside the top.
  // =================================================================
  logic [VA_WIDTH-1:0] fstart [0:FTQ_DEPTH-1];
  int                  n_pd_redir;

  always @(posedge clk) begin : fetch_log
    if (rstn && dut.ftq_ifu_req_val && dut.ftq_ifu_req_rdy &&
        !dut.ftq_ifu_flush_val)
      fstart[dut.ftq_ifu_idx] <= dut.ftq_ifu_start_pc;
    if (rstn && dut.u_ftq.w_pd_redir_val && !bkend_ftq_redir_val)
      n_pd_redir <= n_pd_redir + 1;
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

  always @(posedge clk) begin : upd_log
    if (rstn) begin
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
          dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_upd_hit_u0 &&
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

  task automatic resolve(input int e, input logic [FTQ_IDX_BITS-1:0] idx,
                         input logic [3:0] pos, input logic mis);
    rq[rq_tl % 256].ftq_idx    = idx;
    rq[rq_tl % 256].pos        = pos;
    rq[rq_tl % 256].taken      = ex[e].taken;
    rq[rq_tl % 256].target     = ex[e].target;
    rq[rq_tl % 256].br_type    = ex[e].btype;
    rq[rq_tl % 256].mispredict = mis;
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
    bkend_ftq_commit_val  = 1'b0;
    bkend_ftq_commit_idx  = '0;
    bkend_ftq_rsv_val     = '0;
    bkend_ftq_rsv[0]      = '0;
    bkend_ftq_rsv[1]      = '0;
    dec_ibuf_rdy          = 1'b0;
    forever begin
      @(posedge clk);
      // ---- sample at the edge -----------------------------------
      if (rstn && bkend_ftq_rsv_val[0] && ftq_bkend_rsv_rdy[0]) rq_hd++;
      stop  = 1'b0;
      prsnt = rstn && run_be && dec_ibuf_rdy && !bkend_ftq_redir_val;
      if (prsnt) begin
        for (int i = 0; i < SLOTS; i++) begin
          s = pd_out[i];
          d = decode_bundle[i];
          if (!s.valid || stop) continue;
          if (ep >= ne) continue;                 // past the end
          if (s.start_pc != ex[ep].pc) begin
            stop = 1'b1;
            // A direct jump or call never has a wrong path after it:
            // predecode truncates the bundle at a JAL (M1, M3, IB-2),
            // so what follows one is its target. Only a conditional's
            // direction and an indirect's target can be wrong here.
            if (cfi_pend && ((ex[cfi_e].btype == DIRECT_UNC) ||
                             (ex[cfi_e].btype == DIRECT_CALL))) begin
              n_err++;
              $display("ERROR: [%s] pc %011h after a JAL at %011h",
                       tname, s.start_pc, ex[cfi_e].pc);
            end else if (cfi_pend) begin
              n_mispred++;
              if ((ex[cfi_e].btype == RETURN) ||
                  (ex[cfi_e].btype == RETURN_CALL))
                n_mis_ras++;
              if (ex[cfi_e].pc == watch_pc) n_mis_watch++;
              resolve(cfi_e, cfi_idx, cfi_pos, 1'b1);
              cfi_pend = 1'b0;
              redirect(cfi_idx, cfi_pos, ex[ep].pc, 1'b0, RC_MISPREDICT);
            end else begin
              n_err++;
              $display("%s", $sformatf(
                {"ERROR: [%s] stream: got pc %011h exp %011h ",
                 "(entry %0d), not after a control transfer"},
                tname, s.start_pc, ex[ep].pc, ep));
            end
            continue;
          end
          // The expected instruction.
          n_retired++;
          if (cfi_pend) begin
            resolve(cfi_e, cfi_idx, cfi_pos, 1'b0);
            cfi_pend = 1'b0;
          end
          track_entry(s.ftq_idx);
          // A faulting slot has no encoding; no document says what
          // its is_rvc holds (reported, BP-118), so it is not checked.
          if ((ex[ep].fault == IFU_FAULT_NONE) &&
              (s.is_rvc != ex[ep].rvc)) begin
            n_err++;
            $display("ERROR: [%s] pc %011h is_rvc %0d", tname, s.start_pc,
                     s.is_rvc);
          end
          if (d.is_illegal) begin
            n_err++;
            $display("ERROR: [%s] pc %011h decode raised illegal", tname,
                     s.start_pc);
          end
          if (fstart[s.ftq_idx] + VA_WIDTH'(2 * int'(s.pos)) != s.start_pc)
          begin
            n_err++;
            $display("%s", $sformatf(
              {"ERROR: [%s] pc %011h ftq_idx %0d pos %0d does not ",
               "name its block (start %011h)"}, tname, s.start_pc,
              s.ftq_idx, s.pos, fstart[s.ftq_idx]));
          end
          if (ex[ep].fault != IFU_FAULT_NONE) begin
            if ((s.fault_cause != ex[ep].fault) ||
                (s.fault_va != ex[ep].fva)) begin
              n_err++;
              $display("ERROR: [%s] pc %011h fault %0d va %011h", tname,
                       s.start_pc, s.fault_cause, s.fault_va);
            end else begin
              n_fault_ok++;
            end
            n_trap++;
            stop = 1'b1;
            redirect(s.ftq_idx, s.pos, ex[ep].target, 1'b1, RC_TRAP);
            ep++;
            continue;
          end
          if ((s.fault_cause != IFU_FAULT_NONE) ||
              (s.instr != ex[ep].instr)) begin
            n_err++;
            $display("ERROR: [%s] pc %011h instr %08h exp %08h fault %0d",
                     tname, s.start_pc, s.instr, ex[ep].instr,
                     s.fault_cause);
          end
          if (ex[ep].trap) begin
            n_trap++;
            stop = 1'b1;
            redirect(s.ftq_idx, s.pos, ex[ep].target, 1'b1, RC_TRAP);
            ep++;
            continue;
          end
          if (ex[ep].btype != NO_BRANCH) begin
            cfi_pend = 1'b1;
            cfi_e    = ep;
            cfi_idx  = s.ftq_idx;
            cfi_pos  = s.pos;
          end
          ep++;
        end
      end
      #1;
      // ---- drive for the next cycle -----------------------------
      bkend_ftq_redir_val = rd_pend;
      if (rd_pend) begin
        bkend_ftq_redir_idx   = rd_idx;
        bkend_ftq_redir_pos   = rd_pos;
        bkend_ftq_redir_pc    = rd_pc;
        bkend_ftq_redir_self  = rd_self;
        bkend_ftq_redir_cause = rd_cause;
      end
      rd_pend = 1'b0;
      bkend_ftq_commit_val = wm_val;
      bkend_ftq_commit_idx = wm;
      bkend_ftq_rsv_val[0] = (rq_hd != rq_tl);
      bkend_ftq_rsv[0]     = rq[rq_hd % 256];
      dec_ibuf_rdy         = rstn && run_be;
    end
  end

  // =================================================================
  // Scaffolding.
  // =================================================================
  task automatic reset_all(input logic use_sv39);
    rstn         = 1'b0;
    run_be       = 1'b0;
    ne           = 0;
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
    mem.delete();
    vmap.delete();
    sv39         = use_sv39;
    satp_root    = PA_WIDTH'('h0_8F00_0000);
    pt_next      = PA_WIDTH'('h0_8F00_1000);
    for (int i = 0; i < 512; i++) wr64(satp_root + PA_WIDTH'(8 * i), '0);
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

  task automatic release_reset();
    repeat (4) @(posedge clk);
    #1;
    rstn   = 1'b1;
    run_be = 1'b1;
  endtask

  // Run until the whole stream has retired, then stop taking decode's
  // output so the front end backs up and nothing more retires, and
  // check that the FTQ commits through the watermark.
  task automatic run_and_check(input int max_cyc);
    int c;
    c = 0;
    while ((ep < ne) && (c < max_cyc) && (n_err < 20)) begin
      @(posedge clk);
      #1;
      c++;
    end
    run_be = 1'b0;
    repeat (200) @(posedge clk);
    #1;
    chk($sformatf("the whole stream retired: %0d of %0d in %0d cycles",
                  ep, ne, c), ep == ne);
    chk($sformatf("no stream, decode or index error (%0d)", n_err),
        n_err == 0);
    chk("every retired instruction is the executed stream, in order",
        n_retired == ne);
    chk($sformatf("the FTQ committed through the watermark: ptr %0d wm %0d",
                  dut.u_ftq.w_commit_ptr, wm),
        wm_val && (dut.u_ftq.w_commit_ptr == wm + FTQ_PTR_BITS'(1)));
    chk("every resolution was accepted", rq_hd == rq_tl);
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
    wp = RESET_VECTOR;
    // Straight-line mixed 16- and 32-bit code, then a 32-bit
    // instruction straddling the line boundary at 0x40.
    mixed(20);
    while (wp != RESET_VECTOR + VA_WIDTH'('h3E)) i16();
    i32(ADDI_T0);
    mixed(5);
    // Never taken, then always taken.
    cond(1'b0, wp + VA_WIDTH'('h40));
    mixed(3);
    cond(1'b1, RESET_VECTOR + VA_WIDTH'('h100));
    mixed(4);
    // JAL forward.
    jal(5'd0, RESET_VECTOR + VA_WIDTH'('h180));
    mixed(3);
    // Call and return, three times to the same function.
    fn = RESET_VECTOR + VA_WIDTH'('h400);
    for (int k = 0; k < 3; k++) begin
      link = wp + VA_WIDTH'(4);
      jal(5'd1, fn);
      mixed(4);
      cond(1'b1, wp + VA_WIDTH'(8));        // a taken branch in it
      i32(ADDI_T0);
      ret(link);
      mixed(2);
    end
    // A 32-bit instruction straddling the page boundary at 0x1000.
    jal(5'd0, RESET_VECTOR + VA_WIDTH'('hFF0));
    while (wp != RESET_VECTOR + VA_WIDTH'('hFFE)) i16();
    i32(ADDI_T0);
    mixed(6);
    // An ecall: a trap redirect to the handler.
    ecall(RESET_VECTOR + VA_WIDTH'('h2000));
    mixed(4);
    // An access fault: a fetch just below main memory (MMU-15a)
    // faults with cause 1 and traps to the second handler. Within JAL
    // range of the handler.
    jal_fault(VA_WIDTH'('h0_7FFF_F000), IFU_FAULT_ACCESS,
              RESET_VECTOR + VA_WIDTH'('h3000));
    mixed(5);
    fn = RESET_VECTOR + VA_WIDTH'('h3400);
    link = wp + VA_WIDTH'(4);
    jal(5'd1, fn);
    mixed(2);
    ret(link);
    mixed(2);
    halt();
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
    map4k(b,                       PA_WIDTH'('h0_8100_0000));
    map4k(b + VA_WIDTH'('h1000),   PA_WIDTH'('h0_8120_5000));
    map4k(b + VA_WIDTH'('h2000),   PA_WIDTH'('h0_8100_7000));
    map4k(VA_WIDTH'('h0_8002_0000), PA_WIDTH'('h0_8130_0000));
    // The reset vector is fetched physically before any translation,
    // so it jumps to the program; under Sv39 that fetch is already
    // translated, so the reset vector page is mapped to itself.
    map4k(RESET_VECTOR, PA_WIDTH'(RESET_VECTOR));
    wp = RESET_VECTOR;
    mixed(3);
    jal(5'd0, b);
    mixed(10);
    cond(1'b1, b + VA_WIDTH'('h200));
    mixed(3);
    // A 32-bit instruction straddling into the next, discontiguous
    // page.
    jal(5'd0, b + VA_WIDTH'('hFF0));
    while (wp != b + VA_WIDTH'('hFFE)) i16();
    i32(ADDI_T0);
    mixed(4);
    fn = b + VA_WIDTH'('h2100);
    for (int k = 0; k < 2; k++) begin
      link = wp + VA_WIDTH'(4);
      jal(5'd1, fn);
      mixed(3);
      ret(link);
      mixed(2);
    end
    // A page fault: a fetch from an unmapped VA, cause 12.
    jal_fault(b + VA_WIDTH'('h4000), IFU_FAULT_PAGE,
              VA_WIDTH'('h0_8002_0000));
    mixed(6);
    halt();
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
    wp = RESET_VECTOR;
    mixed(4);
    fn   = RESET_VECTOR + VA_WIDTH'('h800);
    otop = wp;
    eo   = ne;
    // Outer body, first iteration.
    mixed(2);
    itop = wp;
    ei   = ne;
    mixed(3);
    loop_br(itop);
    rep_iter(ei, 6);
    cond(1'b1, wp + VA_WIDTH'(12));            // always taken, skips 8
    mixed(2);
    // jalr x0, 0(x7): an indirect jump to a fixed target 0x40 ahead.
    jalr_to(5'd0, 5'd7, wp + VA_WIDTH'('h40));
    mixed(2);
    // jalr x1, 0(x28): an indirect call to fn, which returns.
    link = wp + VA_WIDTH'(4);
    jalr_to(5'd1, 5'd28, fn);
    mixed(3);
    ret(link);
    mixed(1);
    loop_br(otop);
    rep_iter(eo, 8);
    mixed(3);
    halt();
    release_reset();
    run_and_check(60000);
    chk($sformatf("the uBTB received updates (%0d)", n_u_ubtb), n_u_ubtb > 0);
    chk($sformatf("the LP received updates (%0d)", n_u_lp), n_u_lp > 0);
    chk($sformatf("TAGE received updates (%0d)", n_u_tage), n_u_tage > 0);
    chk($sformatf("SC received updates (%0d)", n_u_sc), n_u_sc > 0);
    chk($sformatf("ITTAGE received updates (%0d)", n_u_ittage),
        n_u_ittage > 0);
    chk($sformatf("the RAS committed (%0d)", n_u_ras), n_u_ras > 0);
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
    wp = RESET_VECTOR;
    mixed(3);
    b  = RESET_VECTOR + VA_WIDTH'('h600);
    l  = wp;
    e0 = ne;
    jal(5'd5, b);                          // L
    mixed(3);                              // B prologue
    b1 = wp;
    jalr_to(5'd1, 5'd5, l + VA_WIDTH'(4)); // B1: RETURN_CALL
    mixed(2);                              // A at L+4
    a1 = wp;
    jalr_to(5'd5, 5'd1, b1 + VA_WIDTH'(4)); // A1: RETURN_CALL
    mixed(2);                              // B at B1+4
    jalr_to(5'd0, 5'd5, a1 + VA_WIDTH'(4)); // B2: RETURN
    mixed(1);                              // A at A1+4
    loop_br(l);
    rep_iter(e0, 10);
    mixed(3);
    halt();
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
    wp  = RESET_VECTOR;
    f   = RESET_VECTOR + VA_WIDTH'('h800);
    g   = RESET_VECTOR + VA_WIDTH'('hA00);
    h   = RESET_VECTOR + VA_WIDTH'('hC00);
    mixed(3);
    top = wp;
    e0  = ne;
    while (wp != RESET_VECTOR + VA_WIDTH'('h1C)) i16();
    lm  = wp + VA_WIDTH'(4);
    jal(5'd1, f);                          // main calls f
    mixed(3);
    while (wp != f + VA_WIDTH'('h1C)) i16();
    lf1 = wp + VA_WIDTH'(4);
    jal(5'd1, g);                          // f calls g
    mixed(2);
    ret(lf1);                              // g returns
    mixed(1);
    while (wp != f + VA_WIDTH'('h3C)) i16();
    lf2 = wp + VA_WIDTH'(4);
    jal(5'd1, h);                          // f calls h
    mixed(2);
    ret(lf2);                              // h returns
    mixed(1);
    watch_pc = wp;                         // f's return
    ret(lm);                               // f returns to main
    mixed(1);
    loop_br(top);
    rep_iter(e0, 6);
    mixed(3);
    halt();
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
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    p_bare();
    p_sv39();
    p_loops();
    p_coro();
    p_calls();
    $display("tb_fe_top: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fe_top: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #3000000;
    $fatal(1, "tb_fe_top: timeout");
  end

endmodule : tb
