// ===================================================================
// FILE:    tb_tage_manual_tasks.svh
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// TAGE-specific tasks for tb_tage_manual.sv.
// Included inside module tb. References module-scope signals:
// clk, rstn, stg_pred_val, stg_pred_inp, stg_upd_val, stg_upd_inp,
// tage_pred_rdy_p2, tage_pred_meta_p2, tage_upd_rdy_u1, u_dut.
// ===================================================================

// -------------------------------------------------------------------
// tage_ram_entry_t: packed struct for RAM access tasks.
// T1-T4 layout: {tag,epc,useful,ctr,valid} = 16 bits at MAX_* widths.
// T0: only ctr[1:0] is significant (2-bit CTR only).
// Field 'useful' replaces reserved word 'use' (Verilator 5.020).
// -------------------------------------------------------------------
typedef struct packed {
  logic [TAGE_MAX_TAG_WIDTH-1:0] tag;    // bits [15:8]
  logic [TAGE_MAX_EPC_WIDTH-1:0] epc;    // bits [7:6]
  logic [TAGE_MAX_USE_WIDTH-1:0] useful; // bits [5:4]
  logic [TAGE_MAX_CTR_WIDTH-1:0] ctr;    // bits [3:1]
  logic                          valid;  // bit  [0]
} tage_ram_entry_t;

// -------------------------------------------------------------------
// tage_ram_write: write one entry to a table RAM.
// idx is the full THIS_INDEX_BITS-wide address.
// bank = idx[10], row = idx[9:0] for 11-bit index.
// T0 (tage_bim): writes ctr[1:0] to both u_ram_s0 and u_ram_s1.
// T1-T4: writes full 16-bit entry to both u_ram_s0 and u_ram_s1.
// -------------------------------------------------------------------
task automatic tage_ram_write(
  input int              tbl,
  input int              idx,
  input tage_ram_entry_t entry
);
  int          bank;
  int          row;
  logic [1:0]  bim_raw;
  logic [15:0] tbl_raw;
  bank    = (idx >> 10) & 1;
  row     = idx & 1023;
  bim_raw = entry.ctr[1:0];
  tbl_raw = {entry.tag, entry.epc, entry.useful, entry.ctr, entry.valid};
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

// -------------------------------------------------------------------
// tage_ram_read: read one entry from a table RAM (reads u_ram_s0).
// -------------------------------------------------------------------
task automatic tage_ram_read(
  input  int              tbl,
  input  int              idx,
  output tage_ram_entry_t entry
);
  int          bank;
  int          row;
  logic [1:0]  bim_raw;
  logic [15:0] tbl_raw;
  bank  = (idx >> 10) & 1;
  row   = idx & 1023;
  entry = '0;
  case (tbl)
    0: begin
      bim_raw        = u_dut.u_tage_bim.u_ram_s0.mem[bank][row];
      entry.ctr[1:0] = bim_raw;
    end
    1: begin
      tbl_raw = u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[bank][row];
      entry   = tage_ram_entry_t'(tbl_raw);
    end
    2: begin
      tbl_raw = u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[bank][row];
      entry   = tage_ram_entry_t'(tbl_raw);
    end
    3: begin
      tbl_raw = u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[bank][row];
      entry   = tage_ram_entry_t'(tbl_raw);
    end
    4: begin
      tbl_raw = u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[bank][row];
      entry   = tage_ram_entry_t'(tbl_raw);
    end
    default: ;
  endcase
endtask

// -------------------------------------------------------------------
// tage_set_pred_inp: populate a tage_pred_inp_t struct.
// -------------------------------------------------------------------
task automatic tage_set_pred_inp(
  output tage_pred_inp_t          inp,
  input  logic [VA_WIDTH-1:0]     pc,
  input  logic [FTQ_IDX_BITS-1:0] branch_id
);
  inp.pc        = pc;
  inp.branch_id = branch_id;
endtask

// -------------------------------------------------------------------
// tage_set_upd_inp: populate a tage_upd_inp_t struct.
// -------------------------------------------------------------------
task automatic tage_set_upd_inp(
  output tage_upd_inp_t   inp,
  input  tage_pred_meta_t pred_meta,
  input  logic            resolved_taken,
  input  logic            cond_mispredict
);
  inp.tage_pred_meta  = pred_meta;
  inp.resolved_taken  = resolved_taken;
  inp.cond_mispredict = cond_mispredict;
endtask

// -------------------------------------------------------------------
// tage_predict: drive prediction request, wait for rdy_p2, capture
// meta. Timeout after 16 cycles; report via tb_error on timeout.
// Uses staging FFs (stg_pred_val, stg_pred_inp) so that tage.sv
// always_comb blocks see tage_pred_val_p0 as an FF output (nba_sequent).
// -------------------------------------------------------------------
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
  @(posedge clk);
  stg_pred_val = '0;
  timeout = 0;
  while (!(|tage_pred_rdy_p2) && (timeout < 16)) begin
    @(posedge clk);
    timeout++;
  end
  if (!(|tage_pred_rdy_p2)) begin
    tb_error("tage_predict: timeout waiting for rdy_p2");
    errs++;
  end
  rdy     = tage_pred_rdy_p2;
  meta[0] = tage_pred_meta_p2[0];
  meta[1] = tage_pred_meta_p2[1];
  @(posedge clk);
endtask

// -------------------------------------------------------------------
// tage_update: drive update request for one cycle, wait for
// tage_upd_rdy_u1. Timeout after 16 cycles.
// -------------------------------------------------------------------
task automatic tage_update(
  input  tage_upd_inp_t inp[0:1],
  input  logic [1:0]    val,
  inout  integer        errs
);
  int timeout;
  stg_upd_inp[0] = inp[0];
  stg_upd_inp[1] = inp[1];
  stg_upd_val    = val;
  @(posedge clk);
  stg_upd_val = '0;
  timeout = 0;
  while (!(|(tage_upd_rdy_u1 & val)) && (timeout < 16)) begin
    @(posedge clk);
    timeout++;
  end
  if (!(|(tage_upd_rdy_u1 & val))) begin
    tb_error("tage_update: timeout waiting for upd_rdy_u1");
    errs++;
  end
  @(posedge clk);
endtask

// -------------------------------------------------------------------
// tage_check_pred_meta: compare tage_pred_meta_t got vs exp field by
// field for each slot where mask[s]=1. Calls tb_error on each
// mismatch. label identifies the calling test in error output.
// -------------------------------------------------------------------
task automatic tage_check_pred_meta(
  input tage_pred_meta_t got[0:1],
  input tage_pred_meta_t exp[0:1],
  input logic [1:0]      mask,
  input string           label,
  inout integer          errs
);
  for (int s = 0; s < 2; s++) begin
    if (!mask[s]) continue;
    if (got[s].tage_prm_idx !== exp[s].tage_prm_idx) begin
      tb_error($sformatf("%s s%0d: prm_idx", label, s));
      errs++;
    end
    if (got[s].tage_alt_idx !== exp[s].tage_alt_idx) begin
      tb_error($sformatf("%s s%0d: alt_idx", label, s));
      errs++;
    end
    if (got[s].tage_prm_comp !== exp[s].tage_prm_comp) begin
      tb_error($sformatf("%s s%0d: prm_comp", label, s));
      errs++;
    end
    if (got[s].tage_alt_comp !== exp[s].tage_alt_comp) begin
      tb_error($sformatf("%s s%0d: alt_comp", label, s));
      errs++;
    end
    if (got[s].tage_prm_useful !== exp[s].tage_prm_useful) begin
      tb_error($sformatf("%s s%0d: prm_useful", label, s));
      errs++;
    end
    if (got[s].tage_alt_useful !== exp[s].tage_alt_useful) begin
      tb_error($sformatf("%s s%0d: alt_useful", label, s));
      errs++;
    end
    if (got[s].tage_prm_ctr !== exp[s].tage_prm_ctr) begin
      tb_error($sformatf("%s s%0d: prm_ctr", label, s));
      errs++;
    end
    if (got[s].tage_alt_ctr !== exp[s].tage_alt_ctr) begin
      tb_error($sformatf("%s s%0d: alt_ctr", label, s));
      errs++;
    end
    if (got[s].tage_alc_comp !== exp[s].tage_alc_comp) begin
      tb_error($sformatf("%s s%0d: alc_comp", label, s));
      errs++;
    end
    if (got[s].tage_alc_idx !== exp[s].tage_alc_idx) begin
      tb_error($sformatf("%s s%0d: alc_idx", label, s));
      errs++;
    end
    if (got[s].tage_alc_tag !== exp[s].tage_alc_tag) begin
      tb_error($sformatf("%s s%0d: alc_tag", label, s));
      errs++;
    end
    if (got[s].tage_prm_tkn !== exp[s].tage_prm_tkn) begin
      tb_error($sformatf("%s s%0d: prm_tkn", label, s));
      errs++;
    end
    if (got[s].tage_alt_tkn !== exp[s].tage_alt_tkn) begin
      tb_error($sformatf("%s s%0d: alt_tkn", label, s));
      errs++;
    end
    if (got[s].tage_pred_strong !== exp[s].tage_pred_strong) begin
      tb_error($sformatf("%s s%0d: pred_strong", label, s));
      errs++;
    end
    if (got[s].tage_use_alt_on_na !== exp[s].tage_use_alt_on_na) begin
      tb_error($sformatf("%s s%0d: use_alt_on_na", label, s));
      errs++;
    end
    if (got[s].tage_using_primary !== exp[s].tage_using_primary) begin
      tb_error($sformatf("%s s%0d: using_primary", label, s));
      errs++;
    end
    if (got[s].tage_high_conf !== exp[s].tage_high_conf) begin
      tb_error($sformatf("%s s%0d: high_conf", label, s));
      errs++;
    end
    if (got[s].tage_pred_tkn !== exp[s].tage_pred_tkn) begin
      tb_error($sformatf("%s s%0d: pred_tkn", label, s));
      errs++;
    end
    if (got[s].branch_id !== exp[s].branch_id) begin
      tb_error($sformatf("%s s%0d: branch_id", label, s));
      errs++;
    end
  end
endtask

// -------------------------------------------------------------------
// tage_round_trip_sanity: throwaway infrastructure check.
// Verifies RAM write/read paths and one predict-update-predict cycle.
// PC = 40'h0000_1234 with folded_hist=0:
//   T1 idx = PC[12:2] & 0x7FF = 1165 (bank=1, row=141)
//   T1 tag = PC[18:11] & 0xFF = 8'h02
// This test must pass without any RTL modifications.
// -------------------------------------------------------------------
task automatic tage_round_trip_sanity(inout integer errs);
  localparam logic [VA_WIDTH-1:0] TEST_PC  = 40'h0000_1234;
  localparam int                  TEST_TBL = 1;
  localparam int                  TEST_IDX = 1165;

  tage_ram_entry_t wr_entry;
  tage_ram_entry_t rd_entry;
  tage_pred_inp_t  pred_inp[0:1];
  tage_pred_meta_t meta1[0:1];
  tage_pred_meta_t meta2[0:1];
  tage_upd_inp_t   upd_inp[0:1];
  logic [1:0]      rdy;
  int              local_errs;
  int              pre_errs;

  local_errs = 0;
  start_test("round_trip_sanity");

  // Step 2: write known T1 entry with valid=1, tag matching TEST_PC.
  wr_entry        = '0;
  wr_entry.valid  = 1'b1;
  wr_entry.ctr    = 3'b110;
  wr_entry.useful = 2'b01;
  wr_entry.epc    = 2'b00;
  wr_entry.tag    = 8'h02;
  tage_ram_write(TEST_TBL, TEST_IDX, wr_entry);

  // Step 3: read back and verify every field.
  // Do not proceed past this step if any field mismatches.
  tage_ram_read(TEST_TBL, TEST_IDX, rd_entry);
  pre_errs = local_errs;
  if (rd_entry.valid !== wr_entry.valid) begin
    tb_error("round_trip_sanity: valid mismatch");
    local_errs++;
  end
  if (rd_entry.ctr !== wr_entry.ctr) begin
    tb_error("round_trip_sanity: ctr mismatch");
    local_errs++;
  end
  if (rd_entry.useful !== wr_entry.useful) begin
    tb_error("round_trip_sanity: useful mismatch");
    local_errs++;
  end
  if (rd_entry.epc !== wr_entry.epc) begin
    tb_error("round_trip_sanity: epc mismatch");
    local_errs++;
  end
  if (rd_entry.tag !== wr_entry.tag) begin
    tb_error("round_trip_sanity: tag mismatch");
    local_errs++;
  end
  if (local_errs > pre_errs) begin
    stop_test("round_trip_sanity", local_errs);
    errs = errs + local_errs;
    return;
  end

  // Step 4: predict slot 0 with TEST_PC.
  pred_inp[0]           = '0;
  pred_inp[0].pc        = TEST_PC;
  pred_inp[0].branch_id = '0;
  pred_inp[1]           = '0;
  tage_predict(pred_inp, 2'b01, meta1, rdy, local_errs);

  // Step 5: verify rdy[0] asserted.
  if (!rdy[0]) begin
    tb_error("round_trip_sanity: pred1 rdy[0] not asserted");
    local_errs++;
  end

  // Step 7: update using meta captured at step 4/6.
  upd_inp[0]                 = '0;
  upd_inp[0].tage_pred_meta  = meta1[0];
  upd_inp[0].resolved_taken  = 1'b1;
  upd_inp[0].cond_mispredict = 1'b0;
  upd_inp[1]                 = '0;
  tage_update(upd_inp, 2'b01, local_errs);

  // Steps 8-9: second prediction and verify rdy.
  tage_predict(pred_inp, 2'b01, meta2, rdy, local_errs);
  if (!rdy[0]) begin
    tb_error("round_trip_sanity: pred2 rdy[0] not asserted");
    local_errs++;
  end

  stop_test("round_trip_sanity", local_errs);
  errs = errs + local_errs;
endtask
