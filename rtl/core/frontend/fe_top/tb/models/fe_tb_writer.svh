// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fe_tb_writer.svh -- the program writer
//
// A SHARED FRONT-END TESTBENCH MODEL (DOC-001, fe_demo_tb_decisions.md
// FDT-4). Not a compilation unit: it is included inside the body of
// module tb, after the package imports, by tb_fe_top
// (rtl/core/frontend/fe_top/tb) and tb_fe_demo (examples/fe_demo/tb),
// in the order those files give. The text was moved here from
// tb_fe_top.sv unchanged except where this header says otherwise.
//
// Holds: the expected-stream record ex_t, the instruction constants,
// the program writer class pw_c (the memory image, the address map,
// the page table writer and the instruction emitters) and its one
// object W. See tb_fe_top.sv for the method: the executed stream is
// built by the writer, not computed by an instruction-set model.
// ===================================================================

  localparam int MAXE    = 32768;

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
    // takes it like a trap: at retirement it sets the privilege (csr_priv) and
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
    // BP-134, rec_undo: f calls itself n deep from one call site, and
    // every return of f is in a block with a conditional before it,
    // whose outcome tk[] gives per return, innermost first:
    //   f+0   mixed(2)        6 bytes
    //   f+6   beq -> f+14     taken at the bottom of the recursion
    //   f+10  jal x1, f       link f+14
    //   f+14  bne -> f+64     the conditional of the return block
    //   f+18  ret             not-taken path
    //   f+64  c.addi          taken path, in another 32-byte region
    //   f+66  ret
    // The path a return does not take is written dry.
    logic rc_tk [$];
    task emit_rcx(input logic [VA_WIDTH-1:0] f, input int n,
                  input logic [VA_WIDTH-1:0] link);
      logic d;
      logic t;
      wp = f;
      mixed(2);
      bcc(n == 0, f + VA_WIDTH'(14));
      if (n > 0) begin
        jal(5'd1, f);
        emit_rcx(f, n - 1, f + VA_WIDTH'(14));
      end
      t = rc_tk.pop_front();
      bcc(t, f + VA_WIDTH'(64));
      d   = dry;
      dry = 1'b1;
      if (t) begin
        wp = f + VA_WIDTH'(18);
        ret(link);
        wp = f + VA_WIDTH'(64);
        dry = d;
        i16();
        ret(link);
      end else begin
        dry = d;
        ret(link);
        dry = 1'b1;
        wp  = f + VA_WIDTH'(64);
        i16();
        ret(link);
        dry = d;
        wp  = link;
      end
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
