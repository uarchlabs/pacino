// ===================================================================
// FILE:    tb_tage_tasks.sv
// DATE:    2026-05-20
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Task-infrastructure testbench for tage.sv.
// All stimulus enters through the tage.sv port list.
// One round-trip sanity test validates infrastructure compile and
// basic predict-update-predict sequence. Test cases against
// planning document rule rows are written by the project author.
// ===================================================================

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tb;

  localparam int NUM_PRED_SLOTS = 2;

  // -- tage_ram_entry_t: testbench-local struct for RAM access tasks.
  // Fields at TAGE_MAX_* widths from bp_defines_pkg.
  // T1-T4 packed layout: {tag,epc,useful,ctr,valid} = 16 bits total,
  // matching the raw bw_ram entry layout in tage_table.sv exactly.
  // For T0: only ctr[1:0] is significant (TAGE_TBL_CTR[0]=2).
  typedef struct packed {
    logic [TAGE_MAX_TAG_WIDTH-1:0] tag;
    logic [TAGE_MAX_EPC_WIDTH-1:0] epc;
    logic [TAGE_MAX_USE_WIDTH-1:0] useful;
    logic [TAGE_MAX_CTR_WIDTH-1:0] ctr;
    logic                          valid;
  } tage_ram_entry_t;

  // ----------------------------------------------------------------
  // Signal declarations
  // ----------------------------------------------------------------
  logic clk;
  logic rstn;

  logic [NUM_PRED_SLOTS-1:0]       tage_pred_val_p0;
  tage_pred_inp_t                  tage_pred_inp_p0[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]       tage_pred_rdy_p2;
  tage_pred_meta_t                 tage_pred_meta_p2[0:NUM_PRED_SLOTS-1];

  logic [NUM_PRED_SLOTS-1:0]       tage_upd_val_u0;
  tage_upd_inp_t                   tage_upd_inp_u0[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]       tage_upd_rdy_u1;

  logic                            pq_not_full;
  logic [NUM_PRED_SLOTS-1:0]       upd_rdy;

  logic                            tage_enable_aging;
  logic [31:0]                     tage_aging_interval;
  logic                            consumer_ready;
  bp_folded_hist_t                 folded_hist;
  logic                            tage_rdy;

  // ----------------------------------------------------------------
  // DUT instantiation: tage #(.NUM_PRED_SLOTS(2))
  // ----------------------------------------------------------------
  tage #(
    .NUM_PRED_SLOTS (NUM_PRED_SLOTS)
  ) u_dut (
    .clk                 (clk),
    .rstn                (rstn),
    .tage_pred_val_p0    (tage_pred_val_p0),
    .tage_pred_inp_p0    (tage_pred_inp_p0),
    .tage_pred_rdy_p2    (tage_pred_rdy_p2),
    .tage_pred_meta_p2   (tage_pred_meta_p2),
    .tage_upd_val_u0     (tage_upd_val_u0),
    .tage_upd_inp_u0     (tage_upd_inp_u0),
    .tage_upd_rdy_u1     (tage_upd_rdy_u1),
    .pq_not_full         (pq_not_full),
    .upd_rdy             (upd_rdy),
    .tage_enable_aging   (tage_enable_aging),
    .tage_aging_interval (tage_aging_interval),
    .consumer_ready      (consumer_ready),
    .folded_hist         (folded_hist),
    .tage_rdy            (tage_rdy)
  );

  // ----------------------------------------------------------------
  // Clock: 10ns period (half-period = 5 time units)
  // ----------------------------------------------------------------
  initial clk = 0;
  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  // ----------------------------------------------------------------
  // Cycle counter
  // ----------------------------------------------------------------
  int cycle_cnt;
  initial cycle_cnt = 0;
  /* verilator lint_off BLKSEQ */
  always @(posedge clk) cycle_cnt++;
  /* verilator lint_on BLKSEQ */

  // ----------------------------------------------------------------
  // Input tie-offs: aging, folded history, consumer ready
  // ----------------------------------------------------------------
  initial begin
    tage_enable_aging   = 1'b0;
    tage_aging_interval = 32'b0;
    folded_hist         = '0;
    consumer_ready      = 1'b1;
  end

  // ----------------------------------------------------------------
  // Staging variables: pred path
  // Blocking assignments to struct-typed array elements in initial
  // block coroutines do not propagate through always_comb in
  // NBA via always_ff required under --timing (struct array update path).
  // ----------------------------------------------------------------
  tage_pred_inp_t            stg_pred_inp[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] stg_pred_val;
  initial begin
    stg_pred_val    = '0;
    stg_pred_inp[0] = '0;
    stg_pred_inp[1] = '0;
  end

  // -- Staging variables: update path
  tage_upd_inp_t             stg_upd_inp[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0] stg_upd_val;
  initial begin
    stg_upd_val    = '0;
    stg_upd_inp[0] = '0;
    stg_upd_inp[1] = '0;
  end

  // -- Synchronous drivers: NBA propagation for struct-typed arrays
  always_ff @(posedge clk) begin : pred_stg_ff
    tage_pred_val_p0[0] <= stg_pred_val[0];
    tage_pred_val_p0[1] <= stg_pred_val[1];
    tage_pred_inp_p0[0] <= stg_pred_inp[0];
    tage_pred_inp_p0[1] <= stg_pred_inp[1];
  end

  always_ff @(posedge clk) begin : upd_stg_ff
    tage_upd_val_u0[0] <= stg_upd_val[0];
    tage_upd_val_u0[1] <= stg_upd_val[1];
    tage_upd_inp_u0[0] <= stg_upd_inp[0];
    tage_upd_inp_u0[1] <= stg_upd_inp[1];
  end

  // ================================================================
  // Utility tasks
  // ================================================================

  task automatic tb_info(input string msg);
    $display("[INFO]  t=%0t %s", $time, msg);
  endtask

  task automatic tb_warn(input string msg);
    $display("[WARN]  t=%0t %s", $time, msg);
  endtask

  task automatic tb_error(
    input string  msg,
    inout integer errs
  );
    $display("[ERROR] t=%0t %s", $time, msg);
    errs++;
  endtask

  // ================================================================
  // RAM access tasks
  // ================================================================

  // tage_ram_write: write tage_ram_entry_t into tbl at idx.
  // idx is the full 11-bit address: bank=idx[10], row=idx[9:0].
  // T0 (tage_bim): 2-bit CTR only; writes both u_ram_s0 and u_ram_s1.
  // T1-T4: 16-bit entry; packed layout matches tage_ram_entry_t.
  // Both slot RAMs written so either slot prediction path sees value.
  task automatic tage_ram_write(
    input int              tbl,
    input int              idx,
    input tage_ram_entry_t entry
  );
    int bank, row;
    logic [1:0]  bim_raw;
    logic [15:0] tbl_raw;
    bank    = (idx >> 10) & 1;
    row     = idx & 1023;
    bim_raw = entry.ctr[1:0];
    tbl_raw = {entry.tag, entry.epc, entry.useful,
               entry.ctr, entry.valid};
    case (tbl)
      0: begin
        u_dut.u_tage_bim.u_ram_s0.mem[bank][row] = bim_raw;
        u_dut.u_tage_bim.u_ram_s1.mem[bank][row] = bim_raw;
      end
      1: begin
        u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[bank][row] = tbl_raw;
        u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s1.mem[bank][row] = tbl_raw;
      end
      2: begin
        u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[bank][row] = tbl_raw;
        u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s1.mem[bank][row] = tbl_raw;
      end
      3: begin
        u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[bank][row] = tbl_raw;
        u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s1.mem[bank][row] = tbl_raw;
      end
      4: begin
        u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[bank][row] = tbl_raw;
        u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s1.mem[bank][row] = tbl_raw;
      end
      default: ;
    endcase
  endtask

  // tage_ram_read: read tage_ram_entry_t from tbl at idx.
  // Reads u_ram_s0 (slot 0 RAM). bank=idx[10], row=idx[9:0].
  task automatic tage_ram_read(
    input  int              tbl,
    input  int              idx,
    output tage_ram_entry_t entry
  );
    int bank, row;
    logic [1:0]  bim_raw;
    logic [15:0] tbl_raw;
    bank  = (idx >> 10) & 1;
    row   = idx & 1023;
    entry = '0;
    case (tbl)
      0: begin
        bim_raw        =
          u_dut.u_tage_bim.u_ram_s0.mem[bank][row];
        entry.ctr[1:0] = bim_raw;
      end
      1: begin
        tbl_raw = u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[bank][row];
        entry = tage_ram_entry_t'(tbl_raw);
      end
      2: begin
        tbl_raw = u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[bank][row];
        entry = tage_ram_entry_t'(tbl_raw);
      end
      3: begin
        tbl_raw = u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[bank][row];
        entry = tage_ram_entry_t'(tbl_raw);
      end
      4: begin
        tbl_raw = u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[bank][row];
        entry = tage_ram_entry_t'(tbl_raw);
      end
      default: ;
    endcase
  endtask

  // ================================================================
  // Prediction request task
  // ================================================================
  // Drive tage_pred_val_p0 and tage_pred_inp_p0 via staging FF.
  // Deassert valid one cycle after staging fires.
  // Poll tage_pred_rdy_p2 up to 16 cycles.
  // Capture tage_pred_meta_p2 when rdy asserts.
  task automatic tage_predict(
    input  tage_pred_inp_t  inp[0:1],
    input  logic [1:0]      val,
    output tage_pred_meta_t meta[0:1],
    output logic [1:0]      rdy,
    inout  integer          errs
  );
    int timeout;
    stg_pred_inp[0] = inp[0];
    stg_pred_inp[1] = inp[1];
    stg_pred_val    = val;
    @(posedge clk); // staging FF fires, DUT sees inputs at p0
    stg_pred_val = '0; // deassert; takes effect next posedge
    timeout = 0;
    while (!(|tage_pred_rdy_p2) && (timeout < 16)) begin
      @(posedge clk);
      timeout++;
    end
    if (!(|tage_pred_rdy_p2))
      tb_error("tage_predict: timeout waiting for rdy_p2", errs);
    rdy     = tage_pred_rdy_p2;
    meta[0] = tage_pred_meta_p2[0];
    meta[1] = tage_pred_meta_p2[1];
    @(posedge clk); // advance past the rdy cycle
  endtask

  // ================================================================
  // Update request task
  // ================================================================
  // Drive tage_upd_val_u0 and tage_upd_inp_u0 for one cycle.
  // Deassert valid one cycle after staging fires.
  // Poll tage_upd_rdy_u1 up to 16 cycles.
  // Wait one additional cycle for pipeline to settle.
  task automatic tage_update(
    input tage_upd_inp_t inp[0:1],
    input logic [1:0]    val,
    inout integer        errs
  );
    int timeout;
    stg_upd_inp[0] = inp[0];
    stg_upd_inp[1] = inp[1];
    stg_upd_val    = val;
    @(posedge clk); // staging FF fires, DUT sees inputs at u0
    stg_upd_val = '0; // deassert; takes effect next posedge
    timeout = 0;
    while (!(|(tage_upd_rdy_u1 & val)) && (timeout < 16)) begin
      @(posedge clk);
      timeout++;
    end
    if (!(|(tage_upd_rdy_u1 & val)))
      tb_error("tage_update: timeout waiting for upd_rdy_u1", errs);
    @(posedge clk); // wait one cycle for pipeline to settle
  endtask

  // ================================================================
  // Prediction compare task
  // ================================================================
  // Compare got vs exp field by field for each slot where mask[s]=1.
  // tb_error called for each field mismatch.
  // label identifies the calling test case in error output.
  task automatic tage_check_meta(
    input tage_pred_meta_t got[0:1],
    input tage_pred_meta_t exp[0:1],
    input logic [1:0]      mask,
    input string           label,
    inout integer          errs
  );
    for (int s = 0; s < 2; s++) begin
      if (!mask[s]) continue;
      if (got[s].tage_prm_idx !== exp[s].tage_prm_idx)
        tb_error($sformatf("%s s%0d: prm_idx",label,s),errs);
      if (got[s].tage_alt_idx !== exp[s].tage_alt_idx)
        tb_error($sformatf("%s s%0d: alt_idx",label,s),errs);
      if (got[s].tage_prm_comp !== exp[s].tage_prm_comp)
        tb_error($sformatf("%s s%0d: prm_comp",label,s),errs);
      if (got[s].tage_alt_comp !== exp[s].tage_alt_comp)
        tb_error($sformatf("%s s%0d: alt_comp",label,s),errs);
      if (got[s].tage_prm_useful !== exp[s].tage_prm_useful)
        tb_error($sformatf("%s s%0d: prm_useful",label,s),errs);
      if (got[s].tage_alt_useful !== exp[s].tage_alt_useful)
        tb_error($sformatf("%s s%0d: alt_useful",label,s),errs);
      if (got[s].tage_prm_ctr !== exp[s].tage_prm_ctr)
        tb_error($sformatf("%s s%0d: prm_ctr",label,s),errs);
      if (got[s].tage_alt_ctr !== exp[s].tage_alt_ctr)
        tb_error($sformatf("%s s%0d: alt_ctr",label,s),errs);
      if (got[s].tage_alc_comp !== exp[s].tage_alc_comp)
        tb_error($sformatf("%s s%0d: alc_comp",label,s),errs);
      if (got[s].tage_alc_idx !== exp[s].tage_alc_idx)
        tb_error($sformatf("%s s%0d: alc_idx",label,s),errs);
      if (got[s].tage_alc_tag !== exp[s].tage_alc_tag)
        tb_error($sformatf("%s s%0d: alc_tag",label,s),errs);
      if (got[s].tage_prm_tkn !== exp[s].tage_prm_tkn)
        tb_error($sformatf("%s s%0d: prm_tkn",label,s),errs);
      if (got[s].tage_alt_tkn !== exp[s].tage_alt_tkn)
        tb_error($sformatf("%s s%0d: alt_tkn",label,s),errs);
      if (got[s].tage_pred_strong !== exp[s].tage_pred_strong)
        tb_error($sformatf("%s s%0d: pred_strong",label,s),errs);
      if (got[s].tage_use_alt_on_na !== exp[s].tage_use_alt_on_na)
        tb_error($sformatf("%s s%0d: use_alt_on_na",label,s),errs);
      if (got[s].tage_using_primary !== exp[s].tage_using_primary)
        tb_error($sformatf("%s s%0d: using_primary",label,s),errs);
      if (got[s].tage_high_conf !== exp[s].tage_high_conf)
        tb_error($sformatf("%s s%0d: high_conf",label,s),errs);
      if (got[s].tage_pred_tkn !== exp[s].tage_pred_tkn)
        tb_error($sformatf("%s s%0d: pred_tkn",label,s),errs);
      if (got[s].branch_id !== exp[s].branch_id)
        tb_error($sformatf("%s s%0d: branch_id",label,s),errs);
    end
  endtask

  // ================================================================
  // Round-trip sanity test (infrastructure validation only)
  // ================================================================
  // This test is a throwaway to confirm the task infrastructure
  // compiles and runs. It will be replaced by the project author.
  //
  // PC = 40'h0000_1234:
  //   T1 idx = (0x1234 >> 2) & 0x7FF = 1165 (bank=1, row=141)
  //   T1 tag = (0x1234 >> 11) & 0xFF = 2 = 8'h02 (folded_hist=0)
  task automatic tage_round_trip_sanity(inout integer errs);
    localparam logic [VA_WIDTH-1:0] TEST_PC  = 40'h0000_1234;
    localparam int                  TEST_TBL = 1;
    localparam int                  TEST_IDX = 1165; // bank=1, row=141

    tage_ram_entry_t wr_entry;
    tage_pred_inp_t  pred_inp[0:1];
    tage_pred_meta_t meta1[0:1];
    tage_pred_meta_t meta2[0:1];
    tage_upd_inp_t   upd_inp[0:1];
    logic [1:0]      rdy;
    int              local_errs;

    local_errs = 0;
    tb_info("tage_round_trip_sanity: start");

    // -- Step 1: write T1 entry with tag matching TEST_PC
    wr_entry       = '0;
    wr_entry.valid = 1'b1;
    wr_entry.ctr   = 3'b010; // ctr=2: NT direction, not weak
    wr_entry.useful = 2'b01;
    wr_entry.epc   = 2'b00;
    wr_entry.tag   = 8'h02; // (TEST_PC >> 11) & 0xFF = 2
    tage_ram_write(TEST_TBL, TEST_IDX, wr_entry);

    // -- Steps 2-4: prediction slot 0, capture meta
    pred_inp[0]           = '0;
    pred_inp[0].pc        = TEST_PC;
    pred_inp[0].branch_id = '0;
    pred_inp[1]           = '0;
    tage_predict(pred_inp, 2'b01, meta1, rdy, local_errs);

    // -- Step 3: verify rdy[0] asserted
    if (!rdy[0])
      tb_error("round_trip: pred1 rdy[0] not asserted", local_errs);

    // -- Step 5: update using captured meta
    upd_inp[0]                 = '0;
    upd_inp[0].tage_pred_meta  = meta1[0];
    upd_inp[0].resolved_taken  = 1'b1;
    upd_inp[0].cond_mispredict = 1'b1; // predicted NT, resolved T
    upd_inp[1]                 = '0;
    tage_update(upd_inp, 2'b01, local_errs);

    // -- Steps 6-7: second prediction, verify rdy
    tage_predict(pred_inp, 2'b01, meta2, rdy, local_errs);
    if (!rdy[0])
      tb_error("round_trip: pred2 rdy[0] not asserted", local_errs);

    // -- Step 8: report pass/fail
    if (local_errs == 0)
      tb_info("tage_round_trip_sanity: PASS");
    else
      tb_error("tage_round_trip_sanity: FAIL", local_errs);
    errs = errs + local_errs;
  endtask

  // ================================================================
  // Main initial block
  // ================================================================
  initial begin : tb_main
    integer total_errors;
    integer en_ram_access;
    integer en_ctr_pred;
    integer en_ctr_upd;
    integer en_alloc;
    integer en_round_trip;

    total_errors  = 0;
    en_ram_access = 1;
    en_ctr_pred   = 1;
    en_ctr_upd    = 1;
    en_alloc      = 1;
    en_round_trip = 1;

    // -- Reset: rstn low for 4 clock cycles, then deassert
    rstn = 1'b0;
    repeat (4) @(posedge clk);
    rstn = 1'b1;

    // -- Wait for tage_rdy (immediate with +TAGE_FAST_INIT=1)
    while (!tage_rdy) @(posedge clk);
    @(posedge clk);

    // -- Round-trip sanity test
    if (en_round_trip) begin
      tage_round_trip_sanity(total_errors);
    end

    // -- Final pass/fail report
    @(posedge clk);
    if (total_errors == 0)
      $display("[PASS] TB-001: all tests passed");
    else
      $display("[FAIL] TB-001: %0d error(s)", total_errors);

    $finish;
  end

endmodule : tb

`default_nettype wire
