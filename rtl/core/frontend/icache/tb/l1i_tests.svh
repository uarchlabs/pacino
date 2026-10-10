// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      l1i_tests.svh
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// Self checking tests for node 'l1i'.
//
// `include this INSIDE the testbench module. The tests use the
// driver task the testbench declares and the address
// decomposition the node's own package declares, so a test
// cannot disagree with the design about where a field is.
//
// Every comparison is written with == inside cg_check rather
// than through cg_check_eq, because a word on this node is 512 bits
// and cg_check_eq carries 64. A width safe compare is exact
// and a truncated one is not.
//--------------------------------------------------------------------

  // the beat the responder returns for one line address
  // and one beat index, and the whole line built from
  // them. Emitted from the same place the responder's own
  // copy is.
  function automatic l1i_beat_t tb_seed(input l1i_addr_t base,
                                    input int unsigned n);
    longint unsigned k;
    k = (longint'({32'd0, base}) >> 5) +
        longint'(n);
    tb_seed = l1i_beat_t'(k) ^ l1i_beat_t'(64'hcafe_0000_0000_0001);
  endfunction

  function automatic l1i_line_t tb_line(input l1i_addr_t base);
    tb_line = '0;
    for(int unsigned b = 0; b < L1iBeats; b++) begin
      tb_line[b*L1iBeatBits +: L1iBeatBits] =
          tb_seed(l1i_line_base(base), b);
    end
  endfunction

  task automatic run_tests();
    l1i_addr_t a;
    l1i_word_t r0;
    l1i_word_t r1;
    int unsigned t0;
    int unsigned t1;
    int unsigned k;
    logic        took;
    logic        all_ok;
    logic        rdy_dm;
    logic        rdy_pf;

    // -----------------------------------------------------
    // T1. The address decomposition agrees with itself. A
    // line address rebuilt from its own fields is the line
    // it came from. D-39, one source for every consumer.
    // -----------------------------------------------------
    a = l1i_addr_t'(32'h0001_2340);
    cg_check("l1i_line_addr rebuilds the line it came from",
             l1i_line_addr(l1i_tag_of(a), l1i_bank_of(a), l1i_set_of(a))
             == l1i_line_base(a));
    cg_check("the offset is what l1i_line_base took off",
             (l1i_line_base(a) | l1i_addr_t'(l1i_offset_of(a))) == a);

    // ---------------------------------------------------
    // T2. The replacement encoding, checked against the
    // package alone. Out of reset every set points at way
    // 0, which is what makes the fill order below
    // predictable. Policy is tree_plru.
    // ---------------------------------------------------
    cg_check("the reset victim is way 0",
             l1i_repl_victim(L1iReplReset) == l1i_way_t'(0));
    cg_check("touching a way moves the victim off it",
             l1i_repl_victim(l1i_repl_update(L1iReplReset, l1i_way_t'(0)))
             != l1i_way_t'(0));

    // -----------------------------------------------------
    // T3. A cold read misses and the same address then
    // hits. The hit is checked by data, and by taking
    // fewer cycles than the miss did.
    // -----------------------------------------------------
    a  = l1i_addr_t'(32'h0000_1000);
    t0 = cg_cycle;
    drv_core(a, 1'b0, '0, '0, r0);
    t1 = cg_cycle;
    drv_core(a, 1'b0, '0, '0, r1);
    cg_check("the second read agrees with the first",
             r1 == r0);
    cg_check("the hit is quicker than the miss",
             (cg_cycle - t1) < (t1 - t0));

    // ---------------------------------------------------
    // T4. Every way of one set. L1iWays lines that share a
    // set index all fit, so every one of them hits
    // afterwards. That is the invalid way first tie break
    // doing its job.
    // ---------------------------------------------------
    for(int unsigned w = 0; w < L1iWays; w++) begin
      a = l1i_addr_t'(32'h0000_2000) +
          l1i_addr_t'(w * (1 << L1iTagLsb));
      drv_core(a, 1'b0, '0, '0, r0);
    end
    for(int unsigned w = 0; w < L1iWays; w++) begin
      a  = l1i_addr_t'(32'h0000_2000) +
           l1i_addr_t'(w * (1 << L1iTagLsb));
      t0 = cg_cycle;
      drv_core(a, 1'b0, '0, '0, r0);
      cg_check("every way of the set still hits",
               (cg_cycle - t0) < 16);
    end

    // -----------------------------------------------------
    // T6. EVERY OUTSTANDING REQUEST IS ACCEPTED BEFORE ANY
    // OF THEM IS ANSWERED. The responder is held off, so no
    // fill can complete and every request stays in flight;
    // a blocking port would have stopped at the first one.
    // -----------------------------------------------------
    tb_hold = 1'b1;
    nb_clear();
    all_ok = 1'b1;
    for(k = 0; k < L1iMaxOutstanding; k++) begin
      nb_req(36'h00040000 + l1i_addr_t'(k) * l1i_addr_t'(L1iLineBytes),
             l1i_req_id_t'(k), 1'b0, took);
      if(!took) all_ok = 1'b0;
    end
    nb_idle();
    cg_check("every outstanding request was accepted",
             all_ok);
    cg_check("and none of them had been answered yet",
             nb_n == 0);

    // let them all come back, each on its own identifier
    tb_hold = 1'b0;
    all_ok  = 1'b1;
    for(k = 0; k < L1iMaxOutstanding; k++) begin
      nb_wait(l1i_req_id_t'(k), took);
      if(!took) all_ok = 1'b0;
    end
    cg_check("every identifier was answered", all_ok);
    cg_check("one answer per identifier and no more",
             nb_n == L1iMaxOutstanding);
    cg_check("and two of them carry different lines",
             nb_data[0] != nb_data[1]);
    all_ok = 1'b1;
    for(k = 0; k < L1iMaxOutstanding; k++) begin
      if(nb_err[k]) all_ok = 1'b0;
    end
    cg_check("and no answer carried an error", all_ok);

    // -----------------------------------------------------
    // T7. AN ANSWER OUT OF ORDER. One line is warmed so a
    // request for it hits, and a cold line in the other
    // bank is left stuck at the held responder. The hit is
    // presented SECOND and answered FIRST, and the
    // identifier is the only thing that says so.
    // -----------------------------------------------------
    drv_core(36'h00050040, 1'b0, '0, '0, r0);
    tb_hold = 1'b1;
    nb_clear();
    nb_req(36'h00050000,        l1i_req_id_t'(1), 1'b0, took);
    nb_req(36'h00050040, l1i_req_id_t'(2), 1'b0, took);
    nb_idle();
    nb_wait(l1i_req_id_t'(2), took);
    cg_check("the request presented second was answered",
             took);
    cg_check("while the one presented first was still outstanding",
             !nb_seen[1]);
    tb_hold = 1'b0;
    nb_wait(l1i_req_id_t'(1), took);
    cg_check("the first was answered after it", took);
    cg_check("so the two answers came back out of order",
             nb_ord[2] < nb_ord[1]);

    // -----------------------------------------------------
    // T8. TWO REQUESTS FOR ONE LINE ARE ANSWERED
    // SEPARATELY. They share one register, so ONE line is
    // fetched, and each is answered in its own cycle
    // carrying its own identifier and the same 'L1iLineBits'
    // bits. The requester sees nothing of the merge.
    // -----------------------------------------------------
    tb_hold = 1'b1;
    nb_clear();
    all_ok = 1'b1;
    nb_req(36'h00060000, l1i_req_id_t'(3), 1'b0, took);
    if(!took) all_ok = 1'b0;
    nb_req(36'h00060000, l1i_req_id_t'(4), 1'b0, took);
    if(!took) all_ok = 1'b0;
    nb_idle();
    cg_check("both requests for one line were accepted",
             all_ok);
    tb_hold = 1'b0;
    nb_wait(l1i_req_id_t'(3), took);
    all_ok = took;
    nb_wait(l1i_req_id_t'(4), took);
    cg_check("and both were answered", all_ok && took);
    cg_check("each with its own identifier and one line",
             nb_data[3] == nb_data[4]);
    cg_check("one line was fetched for the two of them",
             nb_fill == 1);

    // -----------------------------------------------------
    // T9. THE TARGET AFTER THE LAST ONE IS REFUSED. Filling
    // one register's targets takes ready down, and it stays
    // down for a request naming an UNRELATED line, because
    // ready reads the occupancy and never the address.
    // -----------------------------------------------------
    tb_hold = 1'b1;
    nb_clear();
    all_ok = 1'b1;
    for(k = 0; k < L1iMshrTargets; k++) begin
      nb_req(36'h00070000, l1i_req_id_t'(k), 1'b0, took);
      if(!took) all_ok = 1'b0;
    end
    nb_idle();
    cg_check("every target of one register was accepted",
             all_ok);
    nb_ready(1'b0, rdy_dm);
    cg_check("the target after the last one is refused",
             !rdy_dm);
    nb_try(36'h00071000, l1i_req_id_t'(8), 1'b0, 8, took);
    cg_check("and so is a request to an unrelated line",
             !took);
    tb_hold = 1'b0;
    all_ok  = 1'b1;
    for(k = 0; k < L1iMshrTargets; k++) begin
      nb_wait(l1i_req_id_t'(k), took);
      if(!took) all_ok = 1'b0;
    end
    cg_check("every one of them was answered separately",
             all_ok && (nb_n == L1iMshrTargets));
    nb_ready(1'b0, rdy_dm);
    cg_check("and ready came back once it had drained",
             rdy_dm);

    // ---------------------------------------------------
    // T10. THE 'prefetch' RESERVE. With fewer than 2 registers
    // free a request carrying the bit is refused and a
    // request without it is not. That difference is the
    // whole of what the bit does.
    // ---------------------------------------------------
    tb_hold = 1'b1;
    nb_clear();
    all_ok = 1'b1;
    for(k = 0; k < L1iMshrs - 1; k++) begin
      nb_req(36'h00080000 + l1i_addr_t'(k) * l1i_addr_t'(L1iLineBytes),
             l1i_req_id_t'(k), 1'b0, took);
      if(!took) all_ok = 1'b0;
    end
    nb_idle();
    cg_check("the file was filled to one free register",
             all_ok);
    nb_ready(1'b1, rdy_pf);
    nb_ready(1'b0, rdy_dm);
    cg_check("a prefetch is refused inside the reserve",
             !rdy_pf);
    cg_check("and a request without the bit is not",
             rdy_dm);

    tb_hold = 1'b0;
    all_ok  = 1'b1;
    for(k = 0; k < L1iMshrs - 1; k++) begin
      nb_wait(l1i_req_id_t'(k), took);
      if(!took) all_ok = 1'b0;
    end
    cg_check("the file drained", all_ok);
    nb_ready(1'b1, rdy_pf);
    cg_check("a prefetch is accepted outside the reserve",
             rdy_pf);
    nb_clear();
    nb_req(36'h00090000, l1i_req_id_t'(0), 1'b1, took);
    nb_idle();
    nb_wait(l1i_req_id_t'(0), rdy_pf);
    cg_check("and it is answered like any other request",
             took && rdy_pf);

    // ---------------------------------------------------
    // THE SEED THE RESPONDER RETURNS, so a fill can be
    // checked against what it should contain rather than
    // only against another fill. Emitted from the same
    // place the responder's own copy is.
    // ---------------------------------------------------

    // ---------------------------------------------------
    // T11. A HIT STREAM, ONE ANSWER PER CYCLE. 4 warm
    // lines in ONE bank are asked for back to back, and
    // the answers come out on consecutive cycles. A bank
    // that serves one access at a time cannot do that,
    // however many registers stand in front of it.
    // L1I-5, hit throughput one request per cycle.
    // ---------------------------------------------------
    for(k = 0; k < 4; k++) begin
      drv_core(36'h000a0000 + l1i_addr_t'(k) * l1i_addr_t'(128),
               1'b0, '0, '0, r0);
    end
    nb_clear();
    all_ok = 1'b1;
    for(k = 0; k < 4; k++) begin
      nb_req(36'h000a0000 + l1i_addr_t'(k) * l1i_addr_t'(128),
             l1i_req_id_t'(k), 1'b0, took);
      if(!took) all_ok = 1'b0;
    end
    nb_idle();
    cg_check("a hit stream is accepted one per cycle",
             all_ok);
    for(k = 0; k < 4; k++) begin
      nb_wait(l1i_req_id_t'(k), took);
      if(!took) all_ok = 1'b0;
    end
    cg_check("and every one of them was answered",
             all_ok);

    // the answers land on consecutive cycles, which is one
    // hit a cycle sustained across the whole stream
    all_ok = 1'b1;
    for(k = 1; k < 4; k++) begin
      if(nb_rsp[k] != nb_rsp[k-1] + 1) all_ok = 1'b0;
    end
    cg_check_eq("MEASURED hits per 4 cycles on a hit stream",
                longint'(nb_rsp[3]) - longint'(nb_rsp[0]) + 1,
                longint'(4));
    cg_check("a hit stream is answered one per cycle",
             all_ok);

    // and none of them waited on the one in front
    all_ok = 1'b1;
    for(k = 0; k < 4; k++) begin
      if((nb_rsp[k] - nb_acc[k]) != L1iReadLatency) begin
        all_ok = 1'b0;
      end
    end
    cg_check("and none of them waited on the one in front",
             all_ok);

    // ---------------------------------------------------
    // T12. THE HIT LATENCY IS read_latency_cycles,
    // MEASURED. L1iReadLatency is the configuration's number,
    // carried into the package, so this compares the
    // design against what was asked for and not against a
    // literal in a test.
    // ---------------------------------------------------
    // the package's own three numbers agree: the answer
    // is registered out of the compare, and every stage
    // between that and L1iReadLatency is a pad stage
    cg_check("the pipeline depth adds up to L1iReadLatency",
             (L1iCmpStage + L1iPipePad + 1) == L1iReadLatency);
    drv_core(36'h000a4000, 1'b0, '0, '0, r0);
    nb_clear();
    nb_req(36'h000a4000, l1i_req_id_t'(5), 1'b0, took);
    nb_idle();
    nb_wait(l1i_req_id_t'(5), took);
    cg_check("the warm line was answered", took);
    cg_check_eq("MEASURED hit latency in cycles",
                longint'(nb_rsp[5]) - longint'(nb_acc[5]),
                longint'(L1iReadLatency));

    // ---------------------------------------------------
    // T13. A HIT UNDER A MISS, IN THE SAME BANK. The cold
    // line is asked for FIRST and the responder is held,
    // so its fill cannot complete. The warm line is in the
    // SAME bank and is answered anyway, at the same
    // latency it would have had on its own. A blocking
    // bank is stuck waiting for the fill and cannot.
    // ---------------------------------------------------
    drv_core(36'h000a8000, 1'b0, '0, '0, r0);
    cg_check("the two lines are in one bank",
             l1i_bank_of(36'h000a8000) == l1i_bank_of(36'h000ac000));
    tb_hold = 1'b1;
    nb_clear();
    nb_req(36'h000ac000, l1i_req_id_t'(6), 1'b0, took);
    nb_req(36'h000a8000, l1i_req_id_t'(7), 1'b0, took);
    nb_idle();
    nb_wait(l1i_req_id_t'(7), took);
    cg_check("the hit was answered under the miss", took);
    cg_check("while the miss was still outstanding",
             !nb_seen[6]);
    cg_check_eq("and at the hit latency, not the miss's",
                longint'(nb_rsp[7]) - longint'(nb_acc[7]),
                longint'(L1iReadLatency));
    tb_hold = 1'b0;
    nb_wait(l1i_req_id_t'(6), took);
    cg_check("and the miss completed after it",
             took && (nb_ord[7] < nb_ord[6]));

    // ---------------------------------------------------
    // T14. L1iMshrs FILLS IN FLIGHT AT ONCE, counted at the
    // memory side. Channel D is held, so no fill can
    // complete and every one that left is still out. A
    // master that carries one fill at a time peaks at one
    // however many registers are behind it. L1I-23.
    // ---------------------------------------------------
    tb_dhold = 1'b1;
    nb_clear();
    all_ok = 1'b1;
    for(k = 0; k < L1iMshrs; k++) begin
      nb_req(36'h000b0000 + l1i_addr_t'(k) * l1i_addr_t'(L1iLineBytes),
             l1i_req_id_t'(k), 1'b0, took);
      if(!took) all_ok = 1'b0;
    end
    nb_idle();
    cg_check("every one of them was accepted", all_ok);
    // one fill leaves a cycle, so give them room to
    cg_tick(4 * L1iMshrs);
    cg_check_eq("MEASURED fills in flight at once",
                longint'(nb_pk), longint'(L1iMshrs));
    cg_check("and not one of them had completed",
             nb_n == 0);
    tb_dhold = 1'b0;
    all_ok   = 1'b1;
    for(k = 0; k < L1iMshrs; k++) begin
      nb_wait(l1i_req_id_t'(k), took);
      if(!took) all_ok = 1'b0;
    end
    cg_check("and all of them then came back", all_ok);

    // ---------------------------------------------------
    // T15. TWO FILLS WHOSE BEATS INTERLEAVE. The responder
    // hands out beats round robin, so a beat of one line
    // arrives while the other line is part way through.
    // Both have to be reassembled per source, and both
    // answers are checked against the line the responder
    // would return rather than only against each other.
    // ---------------------------------------------------
    tb_dhold = 1'b1;
    tb_ilv   = 1'b1;
    nb_clear();
    nb_req(36'h000b8000, l1i_req_id_t'(1), 1'b0, took);
    nb_req(36'h000b8080, l1i_req_id_t'(2), 1'b0, took);
    nb_idle();
    cg_tick(16);
    cg_check_eq("two fills are outstanding together",
                longint'(nb_pk), 2);
    tb_dhold = 1'b0;
    nb_wait(l1i_req_id_t'(1), took);
    all_ok = took;
    nb_wait(l1i_req_id_t'(2), took);
    cg_check("both interleaved fills were answered",
             all_ok && took);
    cg_check("the beats of the two did interleave",
             nb_ilv > 0);
    cg_check("the first line was reassembled correctly",
             nb_data[1] == l1i_word_t'(tb_line(36'h000b8000)));
    cg_check("and so was the second",
             nb_data[2] == l1i_word_t'(tb_line(36'h000b8080)));
    tb_ilv = 1'b0;

    // ---------------------------------------------------
    // T16. A LATER FILL COMPLETES FIRST. The responder is
    // told to serve the highest numbered source first, so
    // the fill issued SECOND comes back FIRST. The right
    // register has to retire: each identifier gets the
    // line ITS request asked for.
    // ---------------------------------------------------
    tb_dhold = 1'b1;
    tb_rev   = 1'b1;
    nb_clear();
    nb_req(36'h000bc000, l1i_req_id_t'(1), 1'b0, took);
    nb_req(36'h000bc080, l1i_req_id_t'(2), 1'b0, took);
    nb_idle();
    cg_tick(16);
    cg_check_eq("both fills are outstanding together",
                longint'(nb_pk), 2);
    tb_dhold = 1'b0;
    nb_wait(l1i_req_id_t'(2), took);
    cg_check("the fill issued second came back", took);
    cg_check("before the one issued first", !nb_seen[1]);
    nb_wait(l1i_req_id_t'(1), took);
    cg_check("and the first came back after it",
             took && (nb_ord[2] < nb_ord[1]));
    cg_check("the first line went to the register that asked for it",
             nb_data[1] == l1i_word_t'(tb_line(36'h000bc000)));
    cg_check("and the same for the second",
             nb_data[2] == l1i_word_t'(tb_line(36'h000bc080)));
    tb_rev = 1'b0;

  endtask
