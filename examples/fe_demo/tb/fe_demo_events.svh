// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// fe_demo_events.svh -- the event checks (DOC-009,
// fe_demo_tb_decisions.md FDT-10c)
//
// Included inside module tb by tb_fe_demo.sv, after fe_demo_lib.svh and
// before the programs. Each scenario checks the events of its
// description's event table, the table of the level-2 Events section of
// docs/<scenario>.md (FDT-12c, FDT-13 item 4).
//
// THE TABLE. waves/mk_sucl.py --svh writes fe_demo_evt_tbl.svh into each
// model's directory before the compile (Makefile): one evt_row(<label>,
// <cyc>, <line>) per event, <label> the marker label of FDT-12c (the
// event text up to its first ';', ':', ',' or '(', at most six words,
// joined by '_'), <cyc> the row's cyc and <line> its line in the
// description. The expected cycles are the description's, never the
// run's.
//
// THE CHECKS. Each program, programs/fdNN_<name>.svh, gives
//   fdNN_evt_defs()  one evt_def(<label>, <kind>, <late>, <last>,
//                    <why>) per event, in table order: kind EV_EXACT,
//                    EV_WINDOW or EV_NONE (no condition on signals can
//                    express it; why says so); late as below; last 1
//                    for an event the table states as the last of its
//                    kind, whose cycle is the last its condition holds
//   fdNN_evt_now()   a vector, bit k set in a cycle when the condition
//                    of the k-th evt_def holds
// tb_fe_demo.sv dispatches to them by name (evt_defs, evt_now).
//
// THE CYCLE OF AN EVENT is the cyc of the first instant at which the
// waveform shows its condition, so the marker of its row (FDT-12c, the
// first time tb.cyc equals the row's cyc) shows it. The conditions are
// read at each rising edge, before it updates anything, out of reset
// and while the backend takes decode's output (run_be); cyc then still
// holds the number of the cycle that edge ends. A signal a register of
// the design drives changes at the edge, so the marker of that cycle
// shows it: the event's cycle is that cyc. A signal the testbench
// drives changes one time unit after the edge (the backend model's
// #1), as does design logic combinational from it, so at the marker of
// the cycle it is high in it still shows the previous value, and at the
// next marker it shows the new one for that one time unit: an event
// whose evt_def gives late = 1 takes cyc + 1. The descriptions read
// such signals at the marker. An event's cycle may instead
// be given directly with evt_at: tb_fe_demo.sv gives the_run_ends, the
// row every table ends with, as cyc_run, the cycle count the result line
// reports.
//
// A row and its check are matched by label. A row with no check, a
// check with no row, or a label given twice fails the scenario, so a
// change to a row's text or to the table's order cannot pass unseen.
//
// THE KINDS (FDT-10c). Order is checked for every event: in table order,
// the cycles seen must not decrease. Then, for each checked event,
//   EV_EXACT   the cycle seen equals the row's cyc
//   EV_WINDOW  the cycle seen is within the row's cyc plus or minus
//              max(EV_WIN_MIN, cyc / EV_WIN_DIV)
// A count or value an event states is part of its condition, so it must
// match exactly for the event to be seen at all. An event never seen
// fails. events checked <n> of <m> in the result line: m the rows of the
// table, n those with a condition (not EV_NONE).
//
// +EVDUMP prints, after the result line, the cycle seen for every check
// (for writing a table from a run; FDT-10a format).
// ===================================================================

  localparam int EV_MAX     = 32;   // checks per scenario
  localparam int EV_WIN_MIN = 8;    // FDT-10c: at least 8 cycles
  localparam int EV_WIN_DIV = 10;   // FDT-10c: a tenth of the value

  typedef enum int {EV_EXACT, EV_WINDOW, EV_NONE} ev_kind_e;

  // The table, from fe_demo_evt_tbl.svh.
  string    ev_lbl  [$];
  int       ev_cyc  [$];
  int       ev_line [$];
  // The program's checks, in its order, and the cycle each was seen:
  // ck_obs by its condition (evt_mon), ck_at given by evt_at; -1 not
  // seen.
  string    ck_lbl  [$];
  ev_kind_e ck_kind [$];
  string    ck_why  [$];
  logic     ck_late [$];
  logic     ck_last [$];
  int       ck_obs  [EV_MAX];
  int       ck_at   [EV_MAX];
  logic     ev_dump;

  // One row of the table (fe_demo_evt_tbl.svh).
  function automatic void evt_row(input string lbl, input int c,
                                  input int line);
    ev_lbl.push_back(lbl);
    ev_cyc.push_back(c);
    ev_line.push_back(line);
  endfunction

  // One check of the program, in table order.
  function automatic void evt_def(input string lbl, input ev_kind_e k,
                                  input logic late = 1'b0,
                                  input logic last = 1'b0,
                                  input string why = "");
    ck_lbl.push_back(lbl);
    ck_kind.push_back(k);
    ck_late.push_back(late);
    ck_last.push_back(last);
    ck_why.push_back(why);
  endfunction

  // The index of check lbl, -1 if the program has none.
  function automatic int ck_idx(input string lbl);
    foreach (ck_lbl[j]) if (ck_lbl[j] == lbl) return j;
    return -1;
  endfunction

  // An event's cycle given directly, when the condition is the
  // testbench's own measure.
  function automatic void evt_at(input string lbl, input int c);
    int j;
    j = ck_idx(lbl);
    if ((j >= 0) && (ck_at[j] < 0)) ck_at[j] = c;
  endfunction

  // The cycle check j was seen, -1 if never.
  function automatic int ck_seen(input int j);
    return (ck_at[j] >= 0) ? ck_at[j] : ck_obs[j];
  endfunction

  // A backend mispredict redirect to pc this cycle (the backend drives
  // it after the edge, so it is stable at the edge that reads it).
  function automatic logic ev_redir(input logic [VA_WIDTH-1:0] pc);
    return bkend_ftq_redir_val && (bkend_ftq_redir_cause == RC_MISPREDICT) &&
           (bkend_ftq_redir_pc == pc);
  endfunction

  // A backend redirect of any cause to pc this cycle: a restart after a
  // maintenance operation, a trap.
  function automatic logic ev_redir_any(input logic [VA_WIDTH-1:0] pc);
    return bkend_ftq_redir_val && (bkend_ftq_redir_pc == pc);
  endfunction

  // A predecode redirect the FTQ takes this cycle, to pc.
  function automatic logic ev_pd_redir(input logic [VA_WIDTH-1:0] pc);
    return dut.u_ftq.w_pd_redir_val && !bkend_ftq_redir_val &&
           (dut.u_ftq.w_pd_redir_pc == pc);
  endfunction

  // The FTQ's p0 request this cycle, at pc. ev_p0(RESET_VECTOR) is the
  // first request most scenarios make at cyc 0.
  function automatic logic ev_p0(input logic [VA_WIDTH-1:0] pc);
    return dut.ftq_pred_val_p0 && (dut.ftq_pred_pc_p0 == pc);
  endfunction

  // A p2 redirect the FTQ accepts this cycle, from any slot, to pc.
  function automatic logic ev_p2_redir(input logic [VA_WIDTH-1:0] pc);
    logic r;
    r = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++)
      r = r || (dut.bpu_redir_p2[s].valid &&
                (dut.bpu_redir_p2[s].target_pc == pc));
    return dut.u_ftq.w_ok_redir_p2 && r;
  endfunction

  // A p3 redirect the FTQ accepts this cycle, from any slot, to pc.
  function automatic logic ev_p3_redir(input logic [VA_WIDTH-1:0] pc);
    logic r;
    r = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++)
      r = r || (dut.bpu_redir_p3[s].valid &&
                (dut.bpu_redir_p3[s].target_pc == pc));
    return dut.u_ftq.w_ok_redir_p3 && r;
  endfunction

  // The start of a run: the table and the checks of scenario nm.
  function automatic void evt_begin(input string nm);
    ev_lbl.delete();
    ev_cyc.delete();
    ev_line.delete();
    ck_lbl.delete();
    ck_kind.delete();
    ck_why.delete();
    ck_late.delete();
    ck_last.delete();
    for (int j = 0; j < EV_MAX; j++) ck_at[j] = -1;
    ev_dump = $test$plusargs("EVDUMP");
    evt_table(nm);
    evt_defs(nm);
  endfunction

  // The first cycle each condition holds, or the last for a last
  // event; none seen during reset.
  always @(posedge clk) begin : evt_mon
    logic [EV_MAX-1:0] now;
    if (!rstn) begin
      for (int j = 0; j < EV_MAX; j++) ck_obs[j] <= -1;
    end else if (run_be && (ck_lbl.size() > 0)) begin
      now = evt_now(tname);
      for (int j = 0; j < EV_MAX; j++)
        if (now[j] && (j < ck_late.size()) &&
            ((ck_obs[j] < 0) || ck_last[j]))
          ck_obs[j] <= ck_late[j] ? cyc + 1 : cyc;
    end
  end

  // The window of an expected cycle.
  function automatic int evt_win(input int c);
    return (c / EV_WIN_DIV > EV_WIN_MIN) ? c / EV_WIN_DIV : EV_WIN_MIN;
  endfunction

  // The checks, at the end of a run. Each failed check prints an -E:
  // line (FDT-10a); figs is the result line's item. 1 when all pass.
  function automatic logic evt_check(input string nm, output string figs);
    int    n;
    int    nbad;
    int    prev;
    string pl;
    string why;
    n    = 0;
    nbad = 0;
    prev = -1;
    pl   = "";
    if (ck_lbl.size() > EV_MAX) begin
      say("E", nm, $sformatf("event checks %0d, more than EV_MAX %0d",
                             ck_lbl.size(), EV_MAX));
      nbad++;
    end
    foreach (ck_lbl[j]) begin
      int hits;
      hits = 0;
      foreach (ev_lbl[k]) if (ev_lbl[k] == ck_lbl[j]) hits++;
      foreach (ck_lbl[i]) if ((i < j) && (ck_lbl[i] == ck_lbl[j])) hits = 2;
      if (hits != 1) begin
        say("E", nm, $sformatf({"event check %s, table rows with its ",
                                "label %0d, not 1"}, ck_lbl[j], hits));
        nbad++;
      end
    end
    foreach (ev_lbl[k]) begin
      int j;
      int c;
      int o;
      j = ck_idx(ev_lbl[k]);
      c = ev_cyc[k];
      if (j < 0) begin
        say("E", nm, $sformatf("event c%0d_%s, line %0d, has no check",
                               c, ev_lbl[k], ev_line[k]));
        nbad++;
        continue;
      end
      if (ck_kind[j] == EV_NONE) continue;
      n++;
      o = ck_seen(j);
      why = "";
      if (o < 0)
        why = "never seen";
      else if ((ck_kind[j] == EV_EXACT) && (o != c))
        why = $sformatf("seen at cyc %0d, exact", o);
      else if ((ck_kind[j] == EV_WINDOW) &&
               ((o < c - evt_win(c)) || (o > c + evt_win(c))))
        why = $sformatf("seen at cyc %0d, window %0d to %0d", o,
                        c - evt_win(c), c + evt_win(c));
      else if (o < prev)
        why = $sformatf("seen at cyc %0d, out of order, before %s at %0d",
                        o, pl, prev);
      if (why != "") begin
        say("E", nm, $sformatf("event c%0d_%s, line %0d, %s", c, ev_lbl[k],
                               ev_line[k], why));
        nbad++;
      end
      if (o >= 0) begin
        prev = o;
        pl   = ev_lbl[k];
      end
    end
    figs = $sformatf("events checked %0d of %0d", n, ev_lbl.size());
    if (nbad > 0) figs = $sformatf("%s, event checks failed %0d", figs, nbad);
    return nbad == 0;
  endfunction

  // +EVDUMP: the cycle seen for every check, after the result line.
  function automatic void evt_print(input string nm);
    if (!ev_dump) return;
    foreach (ck_lbl[j])
      say("I", nm, $sformatf("event %s, seen %s%s", ck_lbl[j],
                             (ck_seen(j) < 0) ? "never" :
                             $sformatf("at cyc %0d", ck_seen(j)),
                             (ck_kind[j] == EV_NONE) ?
                             {", not checked, ", ck_why[j]} : ""));
  endfunction
