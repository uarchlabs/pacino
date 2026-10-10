// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      l1i_mshr.sv
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// The miss handling file of node 'l1i'. 16 registers
// of 4 targets each, against a core link declaring 16
// outstanding requests.
//
// A REGISTER IS TAKEN AT THE ACCEPTANCE, before the lookup has
// said hit or miss. That is what lets ready be exact: a request
// this file accepted has a place to be answered from whichever
// the lookup turns out to be, and no request has to be refused
// part way down the pipeline.
//
// SIXTEEN FILLS MAY BE IN FLIGHT, one per register. Channel A
// carries the register index as the source, channel D names the
// fill it answers with the same number, and a register retires
// when ITS line is complete and not when the memory side is
// idle.
//
// A RESPONSE CARRIES NO READY. The requester reserved room for
// the answer when it allocated the identifier, so a ready it
// could deassert is a ready it never deasserts, and a second
// flow control beside the identifier free list is a second
// thing that can disagree with it.
//
// THE 'prefetch' QUALIFIER IS READ IN ONE PLACE, in ready:
// a request carrying it is refused unless 2 registers are
// free. Everything else about such a request is identical to
// any other, including its identifier space and its answer.
//
// PACINO CHANGES (BP-123, cachegen_decisions.md CG-D1):
//
// THE 'uncached' QUALIFIER (icache_decisions.md L1I-24,
// l1i_ifu_interfaces.md IF-44). An uncached request is a miss
// whatever the tags hold, is filled from the memory side like any
// miss, is answered like any request, and is NOT written into the
// array. So:
//   - a fresh register taken by one looks up with the bank's forced
//     miss (no replacement update) and is marked not to allocate
//   - it merges only onto a register already known to fetch from
//     memory (its lookup missed, or it was itself taken uncached); a
//     register whose lookup is still in flight may yet be answered
//     from the array, so the request takes a register of its own
//   - a CACHEABLE request merged onto a register taken uncached marks
//     it to allocate, and the fill is installed (L1I-24: "a cacheable
//     request merged onto the same MSHR still allocates"). A cacheable
//     request prefers a register that already allocates, so the line
//     is never filled into two ways
//   - the qualifier is never set with 'prefetch' (MMU-14); a request
//     carrying both is reported
//
// PACINO CHANGES (BP-125, TD#172): a register taken uncached looked up
// with no replacement update, so when a cacheable request merged onto
// it makes the fill install (L1I-24), the install itself moves the
// replacement state, b_fil_rpl, as the cacheable lookup it stands for
// would have. Without it the installed line stayed the set's victim.
//
// MAINTENANCE (L1I-18, l1i_ifu_interfaces.md IF-30, IF-31). hold
// takes ready down while an invalidate is in progress; busy_any says
// whether any register is in use (the drain of invalidate_all), and
// busy_line whether one holds the line of inv_line (the drain of
// invalidate_line). The second is the merge comparison, made against
// the invalidate's address.
//--------------------------------------------------------------------
// The import is at file scope and before the module, which is what
// the project verilog style asks for. Verilator's IMPORTSTAR objects
// to a wildcard in $unit scope, so it is turned off across these
// lines and nowhere else.
/* verilator lint_off IMPORTSTAR */
import l1i_pkg::*;
/* verilator lint_on IMPORTSTAR */

module l1i_mshr (
  input  logic    clk,
  input  logic    rstn,

  // the core side
  input  logic    req_valid,
  output logic    req_ready,
  input  l1i_addr_t   req_addr,
  input  l1i_req_id_t req_id,
  input  logic    req_prefetch,
  input  logic    req_uncached,   // L1I-24 (BP-123)

  output logic    rsp_valid,
  output l1i_req_id_t rsp_id,
  output l1i_word_t   rsp_data,
  output logic    rsp_err,

  // the bank side. The lookup leaves in the cycle the
  // request is accepted, so the array read is stage 0 of
  // the bank's own pipeline and nothing sits in between.
  output logic    b_req_valid [2],
  input  logic    b_req_ready [2],
  output l1i_addr_t   b_req_addr  [2],
  output l1i_mshr_t   b_req_src   [2],
  output logic    b_req_unc   [2],

  // a hit, out of a bank's compare stage
  input  logic    b_rsp_valid [2],
  input  l1i_line_t   b_rsp_data  [2],
  input  logic    b_rsp_err   [2],
  input  l1i_mshr_t   b_rsp_src   [2],

  // a miss, out of the same stage, with the victim way the
  // bank chose from the replacement state it had in front
  // of it
  input  logic    b_mis_valid [2],
  input  l1i_addr_t   b_mis_line  [2],
  input  l1i_mshr_t   b_mis_src   [2],
  input  l1i_way_t    b_mis_way   [2],

  // installing a returned line, into the bank that holds it
  output logic    b_fil_valid [2],
  output l1i_addr_t   b_fil_line  [2],
  output l1i_way_t    b_fil_way   [2],
  output l1i_line_t   b_fil_data  [2],
  // the install also moves the replacement state (BP-125)
  output logic    b_fil_rpl   [2],

  // the memory side. One fill may issue every cycle the
  // link accepts one, up to L1iMshrs outstanding, and a
  // return names the register it belongs to.
  output logic    m_req_valid,
  input  logic    m_req_ready,
  output l1i_addr_t   m_req_addr,
  output l1i_mshr_t   m_req_src,
  input  logic    m_rsp_valid,
  input  l1i_mshr_t   m_rsp_src,
  input  l1i_line_t   m_rsp_data,
  input  logic    m_rsp_err,

  // maintenance (BP-123): ready held low, and the two drains
  input  logic    hold,
  input  l1i_addr_t   inv_line,
  output logic    busy_any,
  output logic    busy_line
);

  localparam int unsigned NBnk = 2;

  // ---------------------------------------------------------
  // The file. A register moves through these flags in order:
  //
  //   e_val  taken by an acceptance, freed by the last
  //          target leaving it
  //   e_mis  the lookup missed and a line has to be fetched
  //   e_snt  the fetch has been handed to the memory side
  //   e_got  the line is here and the targets can be
  //          answered. A hit sets it straight from the bank
  //          and never sets e_mis at all
  // ---------------------------------------------------------
  logic     e_val  [L1iMshrs];
  logic     e_mis  [L1iMshrs];
  logic     e_snt  [L1iMshrs];
  logic     e_got  [L1iMshrs];
  l1i_addr_t    e_line [L1iMshrs];
  l1i_way_t     e_way  [L1iMshrs];
  l1i_line_t    e_data [L1iMshrs];
  logic     e_err  [L1iMshrs];
  // BP-123: taken by an uncached request (its lookup is a forced
  // miss), and whether its fill is to be installed
  logic     e_unc  [L1iMshrs];
  logic     e_alloc [L1iMshrs];
  l1i_tgt_vec_t t_val  [L1iMshrs];
  l1i_req_id_t  t_id   [L1iMshrs][L1iMshrTargets];

  // ---------------------------------------------------------
  // How many registers are free, and whether ANY of them is
  // full of targets. Both are address independent, which is
  // what keeps the compare out of the ready path.
  // ---------------------------------------------------------
  logic [L1iMshrCntBits-1:0] free_n;
  logic                   any_full;

  always_comb begin
    free_n   = '0;
    any_full = 1'b0;
    for(int unsigned m = 0; m < L1iMshrs; m++) begin
      if(!e_val[m]) free_n = free_n + L1iMshrCntBits'(1);
      if(e_val[m] && (&t_val[m])) any_full = 1'b1;
    end
  end

  // ---------------------------------------------------------
  // Which register a request lands on. A LINE ALREADY IN
  // FLIGHT takes a target slot on the register that has it;
  // anything else takes a free register. A register whose
  // line has already come back is NOT merged onto: it is
  // retiring, the array has the line by then, and a request
  // arriving after that hits on its own lookup.
  //
  // Every walk counts DOWN so the LOWEST numbered match
  // wins, which is what makes the choice predictable.
  // ---------------------------------------------------------
  logic                  mrg_hit;
  l1i_mshr_t                 mrg_way;
  logic                  fre_any;
  l1i_mshr_t                 fre_way;
  logic [L1iMshrTgtBits-1:0] tgt_sel;

  // BP-123. The candidates by kind: any register for the line,
  // one that already allocates, and one sure to fetch from memory.
  logic                  mrg_any;
  l1i_mshr_t                 mrg_any_way;
  logic                  mrg_al;
  l1i_mshr_t                 mrg_al_way;
  logic                  mrg_mem;
  l1i_mshr_t                 mrg_mem_way;

  always_comb begin
    mrg_any     = 1'b0;
    mrg_any_way = '0;
    mrg_al      = 1'b0;
    mrg_al_way  = '0;
    mrg_mem     = 1'b0;
    mrg_mem_way = '0;
    fre_any = 1'b0;
    fre_way = '0;
    for(int unsigned m = L1iMshrs; m > 0; m--) begin
      if(e_val[m-1] && !e_got[m-1] &&
         (e_line[m-1] == l1i_line_base(req_addr))) begin
        mrg_any     = 1'b1;
        mrg_any_way = l1i_mshr_t'(m-1);
        if(e_alloc[m-1]) begin
          mrg_al     = 1'b1;
          mrg_al_way = l1i_mshr_t'(m-1);
        end
        if(e_mis[m-1] || e_unc[m-1]) begin
          mrg_mem     = 1'b1;
          mrg_mem_way = l1i_mshr_t'(m-1);
        end
      end
      if(!e_val[m-1]) begin
        fre_any = 1'b1;
        fre_way = l1i_mshr_t'(m-1);
      end
    end
    // An uncached request merges only where the line comes from
    // memory; a cacheable one prefers a register that allocates.
    if(req_uncached) begin
      mrg_hit = mrg_mem;
      mrg_way = mrg_mem_way;
    end else begin
      mrg_hit = mrg_any;
      mrg_way = mrg_al ? mrg_al_way : mrg_any_way;
    end

    tgt_sel = '0;
    for(int unsigned t = L1iMshrTargets; t > 0; t--) begin
      if(!t_val[mrg_way][t-1]) tgt_sel = L1iMshrTgtBits'(t-1);
    end
  end

  // ---------------------------------------------------------
  // READY. It reads the occupancy and never the address, so
  // a register holding every target refuses requests to
  // unrelated lines for as long as it stays full. That costs
  // throughput and it keeps a wide compare out of this path.
  //
  // It does not read req_valid either, so a requester cannot
  // create the acceptance it is asking about.
  // ---------------------------------------------------------
  logic bnk_ok;

  always_comb begin
    // every bank has to be able to take a lookup, because
    // which one this request needs is an address and ready
    // does not read one
    bnk_ok = 1'b1;
    for(int unsigned b = 0; b < NBnk; b++) begin
      if(!b_req_ready[b]) bnk_ok = 1'b0;
    end
  end

  // the reserve, and the ONE place the qualifier is read
  wire qual_ok = !req_prefetch ||
                 (free_n >= L1iMshrCntBits'(L1iQualReserve));

  // hold: no request is taken while an invalidate is in progress,
  // IF-30 (BP-123)
  assign req_ready = rstn && fre_any && !any_full && qual_ok
                     && bnk_ok && !hold;

  wire accept = req_valid && req_ready;

  // ---------------------------------------------------------
  // THE LOOKUP. It goes to the bank in the SAME CYCLE the
  // request is accepted, so the array read is stage 0 and a
  // hit answers L1iReadLatency cycles later. Nothing holds a
  // request between the port and the arrays.
  //
  // A MERGED REQUEST DOES NOT LOOK UP. Its line is already
  // being fetched, so an array read for it could only miss.
  // ---------------------------------------------------------
  always_comb begin
    for(int unsigned b = 0; b < NBnk; b++) begin
      b_req_valid[b] = accept && !mrg_hit &&
                       (l1i_bank_of(req_addr) == l1i_bank_t'(b));
      b_req_addr[b]  = req_addr;
      b_req_src[b]   = fre_way;
      b_req_unc[b]   = req_uncached;
    end
  end

  // ---------------------------------------------------------
  // THE FILL REQUEST. The lowest numbered register that has
  // missed and has not been sent yet. One leaves every cycle
  // the link takes one, and every register that has been
  // sent and not answered is a fill in flight, so there may
  // be L1iMshrs of them at once.
  // ---------------------------------------------------------
  logic  fis_any;
  l1i_mshr_t fis_sel;

  always_comb begin
    fis_any = 1'b0;
    fis_sel = '0;
    for(int unsigned m = L1iMshrs; m > 0; m--) begin
      if(e_val[m-1] && e_mis[m-1] && !e_snt[m-1]) begin
        fis_any = 1'b1;
        fis_sel = l1i_mshr_t'(m-1);
      end
    end
  end

  assign m_req_valid = fis_any;
  assign m_req_addr  = e_line[fis_sel];
  assign m_req_src   = fis_sel;

  // ---------------------------------------------------------
  // INSTALLING THE RETURNED LINE. It is written into the
  // bank in the cycle it arrives, using the way the lookup
  // chose when it missed, so no second array read is needed
  // and no replacement decision is taken twice.
  // ---------------------------------------------------------
  // BP-123: installed only when a cacheable request is on the
  // register, including one merging onto it in this very cycle
  wire fil_alloc = e_alloc[m_rsp_src] ||
                   (accept && mrg_hit && !req_uncached &&
                    (mrg_way == m_rsp_src));

  always_comb begin
    for(int unsigned b = 0; b < NBnk; b++) begin
      // a line that came back with an error is answered
      // and NOT installed
      b_fil_valid[b] = m_rsp_valid && !m_rsp_err && fil_alloc &&
                       (l1i_bank_of(e_line[m_rsp_src])
                        == l1i_bank_t'(b));
      b_fil_line[b]  = e_line[m_rsp_src];
      b_fil_way[b]   = e_way [m_rsp_src];
      b_fil_data[b]  = m_rsp_data;
      // BP-125: a register taken uncached looked up without moving the
      // replacement state; an install from it is a merged cacheable
      // request's, which moves it here (L1I-24). A register taken
      // cacheable moved it at its own lookup.
      b_fil_rpl[b]   = b_fil_valid[b] && e_unc[m_rsp_src];
    end
  end

  // ---------------------------------------------------------
  // Retirement. ONE TARGET PER CYCLE across the whole file,
  // carrying the identifier that target arrived with. Two
  // requests merged onto one register leave over two cycles
  // with two identifiers and the same line.
  // ---------------------------------------------------------
  logic                   ret_any;
  l1i_mshr_t                  ret_sel;
  logic [L1iMshrTgtBits-1:0] ret_tgt;

  always_comb begin
    ret_any = 1'b0;
    ret_sel = '0;
    for(int unsigned m = L1iMshrs; m > 0; m--) begin
      if(e_val[m-1] && e_got[m-1] && (|t_val[m-1])) begin
        ret_any = 1'b1;
        ret_sel = l1i_mshr_t'(m-1);
      end
    end

    ret_tgt = '0;
    for(int unsigned t = L1iMshrTargets; t > 0; t--) begin
      if(t_val[ret_sel][t-1]) ret_tgt = L1iMshrTgtBits'(t-1);
    end
  end

  assign rsp_valid = ret_any;
  assign rsp_id    = t_id[ret_sel][ret_tgt];
  // a line is one word wide on this node, so the line the
  // register holds IS the answer
  assign rsp_data  = l1i_word_t'(e_data[ret_sel]);
  assign rsp_err   = e_err[ret_sel];

  // the register is freed by the LAST target leaving it
  wire ret_last = ret_any &&
      !(|(t_val[ret_sel] & ~(l1i_tgt_vec_t'(1) << ret_tgt)));

  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) begin
      // the whole file is free out of reset, so ready may
      // stand in the first cycle after rstn rises
      for(int unsigned m = 0; m < L1iMshrs; m++) begin
        e_val[m]  <= 1'b0;
        e_mis[m]  <= 1'b0;
        e_snt[m]  <= 1'b0;
        e_got[m]  <= 1'b0;
        e_line[m] <= '0;
        e_way[m]  <= '0;
        e_data[m] <= '0;
        e_err[m]  <= 1'b0;
        e_unc[m]  <= 1'b0;
        e_alloc[m] <= 1'b0;
        t_val[m]  <= '0;
        for(int unsigned t = 0; t < L1iMshrTargets; t++) begin
          t_id[m][t] <= '0;
        end
      end
    end else begin
      // A LOOKUP ANSWERS EXACTLY ONE OF THESE. A bank
      // reports a hit or a miss for the register it was
      // given, never both and never neither.
      for(int unsigned b = 0; b < NBnk; b++) begin
        if(b_rsp_valid[b]) begin
          e_got [b_rsp_src[b]] <= 1'b1;
          e_data[b_rsp_src[b]] <= b_rsp_data[b];
          e_err [b_rsp_src[b]] <= b_rsp_err[b];
        end
        if(b_mis_valid[b]) begin
          e_mis[b_mis_src[b]] <= 1'b1;
          e_way[b_mis_src[b]] <= b_mis_way[b];
        end
      end

      // the fill left for memory
      if(m_req_valid && m_req_ready) begin
        e_snt[fis_sel] <= 1'b1;
      end

      // the fill came back. It names ITS register, so the
      // order the returns arrive in says nothing.
      if(m_rsp_valid) begin
        e_got [m_rsp_src] <= 1'b1;
        e_data[m_rsp_src] <= m_rsp_data;
        e_err [m_rsp_src] <= m_rsp_err;
        e_mis [m_rsp_src] <= 1'b0;
      end

      if(ret_any) begin
        t_val[ret_sel][ret_tgt] <= 1'b0;
        if(ret_last) begin
          e_val[ret_sel] <= 1'b0;
          e_mis[ret_sel] <= 1'b0;
          e_snt[ret_sel] <= 1'b0;
          e_got[ret_sel] <= 1'b0;
        end
      end

      // A retiring register cannot be the one an accept
      // lands on: a merge needs !e_got and a free register
      // needs !e_val, and retirement holds both the other
      // way round. The two writes below cannot collide.
      if(accept) begin
        if(mrg_hit) begin
          t_val[mrg_way][tgt_sel] <= 1'b1;
          t_id [mrg_way][tgt_sel] <= req_id;
          if(!req_uncached) e_alloc[mrg_way] <= 1'b1;
        end else begin
          e_val [fre_way]    <= 1'b1;
          e_mis [fre_way]    <= 1'b0;
          e_snt [fre_way]    <= 1'b0;
          e_got [fre_way]    <= 1'b0;
          e_line[fre_way]    <= l1i_line_base(req_addr);
          e_err [fre_way]    <= 1'b0;
          e_unc [fre_way]    <= req_uncached;
          e_alloc[fre_way]   <= !req_uncached;
          t_val [fre_way]    <= l1i_tgt_vec_t'(1);
          t_id  [fre_way][0] <= req_id;
        end
      end
    end
  end

  // ---------------------------------------------------------
  // THE DRAINS OF AN INVALIDATE (BP-123, IF-31). Any register in
  // use, and any register holding the invalidated line. A
  // register holds its line from the acceptance until its last
  // target leaves, so both cover every fill in flight.
  // ---------------------------------------------------------
  always_comb begin
    busy_any  = 1'b0;
    busy_line = 1'b0;
    for(int unsigned m = 0; m < L1iMshrs; m++) begin
      if(e_val[m]) busy_any = 1'b1;
      if(e_val[m] && (e_line[m] == l1i_line_base(inv_line)))
        busy_line = 1'b1;
    end
  end

  // ---------------------------------------------------------
  // UNCACHED IS NEVER A PREFETCH (BP-123, IF-44, MMU-14).
  // ---------------------------------------------------------
  always_ff @(posedge clk) begin
    if(accept && req_uncached && req_prefetch) begin
      $error("l1i_mshr: request %0d is both uncached and a prefetch",
             req_id);
    end
  end

  // ---------------------------------------------------------
  // NO IDENTIFIER IS IN FLIGHT TWICE. The requester owns the
  // free list, so this is the whole of the node's handling
  // of a request beyond the last one: it has no counter and
  // no recovery path, it says the requester broke the rule.
  // ---------------------------------------------------------
  // accept already carries the reset state, through ready, so
  // neither check reads rstn and neither flops it
  always_ff @(posedge clk) begin
    if(accept) begin
      for(int unsigned m = 0; m < L1iMshrs; m++) begin
        for(int unsigned t = 0; t < L1iMshrTargets; t++) begin
          if(e_val[m] && t_val[m][t] &&
             (t_id[m][t] == req_id)) begin
            $error("l1i_mshr: identifier %0d is already in flight",
                   req_id);
          end
        end
      end
    end
  end

  // ---------------------------------------------------------
  // NO ANSWER IN THE CYCLE ITS REQUEST WAS ACCEPTED. The
  // minimum separation is one cycle, so the requester never
  // has to allocate an identifier and retire it in the same
  // cycle. L1iReadLatency is at least one at every timing the
  // emitter accepts, so the check is here to say so rather
  // than to leave it resting on the pipeline depth being
  // what it is today.
  // ---------------------------------------------------------
  always_ff @(posedge clk) begin
    if(accept && rsp_valid && (rsp_id == req_id)) begin
      $error("l1i_mshr: identifier %0d answered as it was accepted",
             req_id);
    end
  end

  // ---------------------------------------------------------
  // THE BANK AND THE FILE AGREE ABOUT THE LINE. The register
  // took its line from the address at the acceptance and the
  // bank carried that address down its own pipeline, so the
  // miss report naming a different line is the two of them
  // holding different addresses for one access.
  // ---------------------------------------------------------
  always_ff @(posedge clk) begin
    for(int unsigned b = 0; b < NBnk; b++) begin
      if(b_mis_valid[b] &&
         (b_mis_line[b] != e_line[b_mis_src[b]])) begin
        $error("l1i_mshr: bank %0d missed on a line",
               b);
        $error("  register %0d does not hold it",
               b_mis_src[b]);
      end
    end
  end

  // ---------------------------------------------------------
  // A FILL ANSWERS A REGISTER THAT ASKED FOR ONE. d_source
  // is the only thing that correlates a return with a
  // request, so a return naming a register that is not
  // waiting is the two ends disagreeing about which fill
  // this is, and the line would land in the wrong register.
  // ---------------------------------------------------------
  always_ff @(posedge clk) begin
    if(m_rsp_valid &&
       !(e_val[m_rsp_src] && e_snt[m_rsp_src])) begin
      $error("l1i_mshr: a fill returned for register %0d which asked for none",
             m_rsp_src);
    end
  end

  // ---------------------------------------------------------
  // EVERY ACCEPTED REQUEST IS LINE ALIGNED. A line is one
  // word wide on this node, so an address inside a line
  // names a word that does not exist. The check is on this
  // side of the boundary on purpose, so a requester defect
  // is caught where it crosses rather than where it
  // eventually shows.
  // ---------------------------------------------------------
  always_ff @(posedge clk) begin
    if(accept && (|l1i_offset_of(req_addr))) begin
      $error("l1i_mshr: request address %0h is not line aligned",
             req_addr);
    end
  end

endmodule
