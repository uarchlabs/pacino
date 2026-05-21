// ===================================================================
// FILE:    tage.sv
// DATE:    2026-05-12
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// TAGE predictor structural top level.
// T0: tage_bim (untagged bimodal, no hit_p1, no folded_hist).
// T1-T4: tage_table via generate loop (gen_tage_tbl).
// tage_cntrl: one instance. sram_init: one instance.
// tage_cntrl drives all table buses at MAX_* widths.
// Per-table intermediate wires in generate loop slice cntrl
// outputs to THIS_* widths for each tage_table instance.
// T0 cntrl_bits: 2b CTR zero-extended to CNTRL_BITS_W=8b.
// T0 hit_p1: driven '1 (T0 always hits, no tag comparison).
// BP-023b: PQ, UQ, credit arbiter, response buffer added.
// trx_type forwarded to tage_cntrl (combinational, not registered).
// BP-023c: consumer_ready promoted to input port (SC drives it).
// ===================================================================

`ifndef TAGE_SV
`define TAGE_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module tage #(
  parameter int NUM_PRED_SLOTS = 2
) (
  input  logic                             clk,
  input  logic                             rstn,
  // -- prediction interface
  input  logic [NUM_PRED_SLOTS-1:0]        tage_pred_val_p0,
  input  tage_pred_inp_t                   tage_pred_inp_p0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]        tage_pred_rdy_p2,
  output tage_pred_meta_t                  tage_pred_meta_p2[0:NUM_PRED_SLOTS-1],
  // -- update interface
  input  logic [NUM_PRED_SLOTS-1:0]        tage_upd_val_u0,
  input  tage_upd_inp_t                    tage_upd_inp_u0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]        tage_upd_rdy_u1,
  // -- arbitration status outputs (BP-023b)
  output logic                             pq_not_full,
  output logic [NUM_PRED_SLOTS-1:0]        upd_rdy,
  // -- aging control (shared across both slots)
  input  logic                             tage_enable_aging,
  input  logic [31:0]                      tage_aging_interval,
  // -- consumer ready (SC drives; 1=ready to accept result)
  input  logic                             consumer_ready,
  // -- folded history (T1-T4 only; tage_bim does not use)
  input  bp_folded_hist_t                  folded_hist,
  // -- RAM init ready
  output logic                             tage_rdy
);

  // ----------------------------------------------------------------
  // Local parameters
  // ----------------------------------------------------------------
  // CNTRL_BITS_W: packed control field width at MAX_* widths.
  localparam int CNTRL_BITS_W =
    TAGE_MAX_EPC_WIDTH + TAGE_MAX_USE_WIDTH
    + TAGE_MAX_CTR_WIDTH + TAGE_MAX_VAL_WIDTH; // = 8
  // ALLOC_DATA_W: tage_table T1-T4 RAM entry width.
  localparam int ALLOC_DATA_W =
    CNTRL_BITS_W + TAGE_MAX_TAG_WIDTH;   // = 16
  // TBL_SEL_W: matches TAGE_TBL_SEL_WIDTH in bp_defines_pkg.
  localparam int TBL_SEL_W = TAGE_TBL_SEL_WIDTH; // = 3

  // -- Arbitration FIFO and counter sizing (BP-023b)
  localparam int PQ_IDX_W    = $clog2(TAGE_PQ_DEPTH);
  localparam int PQ_PTR_W    = PQ_IDX_W + 1;
  localparam int UQ_IDX_W    = $clog2(TAGE_UQ_DEPTH);
  localparam int UQ_PTR_W    = UQ_IDX_W + 1;
  localparam int RB_IDX_W    = $clog2(TAGE_RESP_BUF_DEPTH);
  localparam int RB_PTR_W    = RB_IDX_W + 1;
  localparam int PRED_CRED_W =
    $clog2(TAGE_PRED_CREDITS + 1);  // 3b: holds 0..4
  localparam int UPD_CRED_W  =
    $clog2(TAGE_UPD_CREDITS  + 1);  // 1b: holds 0..1
  localparam int STARVE_W    =
    $clog2(TAGE_STARVE_THRESH + 1); // 4b: holds 0..8

  // ----------------------------------------------------------------
  // Interconnect wires: tage_cntrl <-> table instances
  // ----------------------------------------------------------------

  // -- prediction val forwarded to each table
  logic [NUM_PRED_SLOTS-1:0]
    w_pred_val_p0[0:TAGE_NUM_TABLES-1];

  // -- prediction results collected from each table
  // w_hit_p1[0]: T0 always hits; driven constant 1 below.
  // w_hit_p1[1:4]: driven by tage_table instances.
  logic [NUM_PRED_SLOTS-1:0]
    w_hit_p1[0:TAGE_NUM_TABLES-1];
  logic [NUM_PRED_SLOTS-1:0]
    w_taken_p1[0:TAGE_NUM_TABLES-1];
  logic [CNTRL_BITS_W-1:0]
    w_cntrl_bits_p1
      [0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];

  // -- update enables
  logic [NUM_PRED_SLOTS-1:0]
    w_upd_val_u0[0:TAGE_NUM_TABLES-1];

  // -- update write data
  logic [TAGE_MAX_CTR_WIDTH-1:0]
    w_prm_ctr_wd_u0
      [0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_CTR_WIDTH-1:0]
    w_alt_ctr_wd_u0
      [0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_USE_WIDTH-1:0]
    w_use_wd_u0
      [0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_EPC_WIDTH-1:0]
    w_epc_wd_u0
      [0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [ALLOC_DATA_W-1:0]
    w_alc_wd_u0
      [0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];

  // -- update write strobes
  logic [NUM_PRED_SLOTS-1:0]
    w_prm_ctr_wr_u0[0:TAGE_NUM_TABLES-1];
  logic [NUM_PRED_SLOTS-1:0]
    w_alt_ctr_wr_u0[0:TAGE_NUM_TABLES-1];
  logic [NUM_PRED_SLOTS-1:0]
    w_use_wr_u0[0:TAGE_NUM_TABLES-1];
  logic [NUM_PRED_SLOTS-1:0]
    w_epc_wr_u0[0:TAGE_NUM_TABLES-1];
  logic [NUM_PRED_SLOTS-1:0]
    w_alc_wr_u0[0:TAGE_NUM_TABLES-1];

  // -- table selector buses (TBL_SEL_W matches tage_cntrl)
  logic [TBL_SEL_W-1:0]
    w_prm_tbl_sel_u0
      [0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [TBL_SEL_W-1:0]
    w_alt_tbl_sel_u0
      [0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [TBL_SEL_W-1:0]
    w_alc_tbl_sel_u0
      [0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];

  // -- update and allocation address buses
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    w_upd_index_u0
      [0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    w_alc_index_u0
      [0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];

  // -- p0 index and tag hashes collected from table instances
  // w_idx_p0[0]: from tage_bim.idx_hash_p0
  // w_idx_p0[1:4], w_tag_p0[1:4]: from tage_table instances
  // w_tag_p0[0]: T0 has no tag -- driven to zero below
  logic [TAGE_MAX_IDX_WIDTH-1:0]
    w_idx_p0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [TAGE_MAX_TAG_WIDTH-1:0]
    w_tag_p0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];

  // ----------------------------------------------------------------
  // sram_init raw outputs (before fast_init_r mux).
  // ----------------------------------------------------------------
  logic                      ri_active_raw;
  logic                      ri_wr_raw;
  logic [TAGE_MAX_IDX_WIDTH-1:0]  ri_wa_raw;
  logic [ALLOC_DATA_W-1:0]   ri_wd_raw;
  logic                      tbl_ri_cs;  // unused (sram_init cs)
  logic                      ri_rdy_raw;

  // ----------------------------------------------------------------
  // fast_init_r: set at time zero from +TAGE_FAST_INIT plusarg.
  // Drives the tbl_ri_* and tage_rdy muxes.
  // ----------------------------------------------------------------
  logic fast_init_r;
  initial begin
    int fi;
    fi = 0;
    void'($value$plusargs("TAGE_FAST_INIT=%d", fi));
    fast_init_r = (fi != 0) ? 1'b1 : 1'b0;
  end

  // ----------------------------------------------------------------
  // tbl_ri_* mux: fast_init_r=1 straps to zero (sram_init bypass).
  // fast_init_r=0: pass through sram_init raw outputs.
  // ----------------------------------------------------------------
  logic                      tbl_ri_active;
  logic                      tbl_ri_wr;
  logic [TAGE_MAX_IDX_WIDTH-1:0]  tbl_ri_wa;
  logic [ALLOC_DATA_W-1:0]   tbl_ri_wd;

  assign tbl_ri_active = fast_init_r ? 1'b0 : ri_active_raw;
  assign tbl_ri_wr     = fast_init_r ? 1'b0 : ri_wr_raw;
  assign tbl_ri_wa     = fast_init_r ? '0   : ri_wa_raw;
  assign tbl_ri_wd     = fast_init_r ? '0   : ri_wd_raw;

  // ----------------------------------------------------------------
  // T0 intermediate wires for tage_bim connections
  // tage_bim output width: THIS_CTR_WIDTH = TAGE_TBL_CTR[0] = 2b.
  // ----------------------------------------------------------------
  // tage_bim prediction outputs.
  logic [NUM_PRED_SLOTS-1:0]
    bim_taken_p1;
  logic [TAGE_TBL_CTR[0]-1:0]
    bim_cntrl_p1[0:NUM_PRED_SLOTS-1];
  // Update input slices: MAX_*-wide buses sliced to THIS_* widths.
  logic [TAGE_TBL_IDX[0]-1:0] bim_upd_idx_u0[0:NUM_PRED_SLOTS-1];
  logic [TAGE_TBL_CTR[0]-1:0] bim_prm_ctr_wd_u0[0:NUM_PRED_SLOTS-1];

  // T0 hit: T0 (tage_bim) has no tag match; always hits.
  // Drive constant 1 for all slots.
  assign w_hit_p1[0]   = {NUM_PRED_SLOTS{1'b1}};
  // Wire T0 taken direction from tage_bim.
  assign w_taken_p1[0] = bim_taken_p1;
  // Wire T0 cntrl_bits: zero-extend 2b CTR to CNTRL_BITS_W=8b.
  // Layout: [0]=VAL=1, [3:1]=CTR(2b padded to 3b), [7:4]=0.
  assign w_cntrl_bits_p1[0][0] =
    {5'b0, bim_cntrl_p1[0], 1'b1};
  assign w_cntrl_bits_p1[0][1] =
    {5'b0, bim_cntrl_p1[1], 1'b1};
  // Slice update index: MAX_IDX -> TAGE_TBL_IDX[0]=11 (same).
  assign bim_upd_idx_u0[0] = w_upd_index_u0[0][0][TAGE_TBL_IDX[0]-1:0];
  assign bim_upd_idx_u0[1] = w_upd_index_u0[0][1][TAGE_TBL_IDX[0]-1:0];
  // Slice CTR write data: MAX_CTR=3 -> TAGE_TBL_CTR[0]=2.
  assign bim_prm_ctr_wd_u0[0] =
    w_prm_ctr_wd_u0[0][0][TAGE_TBL_CTR[0]-1:0];
  assign bim_prm_ctr_wd_u0[1] =
    w_prm_ctr_wd_u0[0][1][TAGE_TBL_CTR[0]-1:0];

  // T0 has no tag. Drive w_tag_p0[0] to zero for both slots.
  assign w_tag_p0[0][0] = '0;
  assign w_tag_p0[0][1] = '0;

  // ================================================================
  // Arbitration layer (BP-023b)
  // ================================================================

  // ----------------------------------------------------------------
  // Arbitrated signals (competing stage -> tage_cntrl)
  // ----------------------------------------------------------------
  logic [NUM_PRED_SLOTS-1:0]       cntrl_pred_val_p0;
  tage_pred_inp_t
    cntrl_pred_inp_p0[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]       cntrl_pred_rdy_p2;
  tage_pred_meta_t
    cntrl_pred_meta_p2[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]       cntrl_upd_val_u0;
  tage_upd_inp_t
    cntrl_upd_inp_u0[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]       cntrl_upd_rdy_u1_w;

  // -- Arbiter outputs and trx_type
  logic arb_grant_pred, arb_grant_upd;
  logic trx_type_comb;
  // trx_type_comb: combinational from arbiter (not registered).
  // Using the registered arb_trx_r.trx_type would lag by 1 cycle,
  // causing write enables to fire on the wrong competing stage.
  assign trx_type_comb = arb_grant_upd;

  // -- pq_has_data / uq_has_data (include bypass candidates)
  logic pq_has_data_w, uq_has_data_w;
  assign pq_has_data_w = !pq_empty || (|tage_pred_val_p0);
  assign uq_has_data_w = !uq_empty || (|tage_upd_val_u0);

  // -- consumer_ready: port input (SC drives; used by RB logic)

  // -- resp_buf_full: forwarded from RB (declared below)
  logic resp_buf_full_w;

  // ----------------------------------------------------------------
  // Credit arbiter registers
  // ----------------------------------------------------------------
  logic [PRED_CRED_W-1:0] pred_credits_r;
  logic [UPD_CRED_W-1:0]  upd_credits_r;
  logic [STARVE_W-1:0]     starve_ctr_r;

  // ----------------------------------------------------------------
  // Prediction Queue (PQ) FIFO
  // ----------------------------------------------------------------
  tage_pred_inp_t
    pq_inp_mem[TAGE_PQ_DEPTH][0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]
    pq_val_mem[TAGE_PQ_DEPTH];
  logic [PQ_PTR_W-1:0] pq_head_r, pq_tail_r;
  logic pq_full, pq_empty;

  assign pq_full  = (pq_tail_r[PQ_IDX_W-1:0]
                     == pq_head_r[PQ_IDX_W-1:0])
                 && (pq_tail_r[PQ_IDX_W]
                     != pq_head_r[PQ_IDX_W]);
  assign pq_empty = (pq_head_r == pq_tail_r);
  assign pq_not_full = !pq_full;

  always_ff @(posedge clk) begin : pq_ff
    if (!rstn) begin
      pq_head_r <= '0;
      pq_tail_r <= '0;
    end else begin
      // Dequeue on PRED grant from non-empty PQ
      if (arb_grant_pred && !pq_empty)
        pq_head_r <= pq_head_r + PQ_PTR_W'(1);
      // Enqueue: incoming pred, not in bypass (pq non-empty
      // or no grant this cycle)
      if ((|tage_pred_val_p0) && !pq_full
          && (!pq_empty || !arb_grant_pred)) begin
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          pq_inp_mem[pq_tail_r[PQ_IDX_W-1:0]][s]
            <= tage_pred_inp_p0[s];
        end
        pq_val_mem[pq_tail_r[PQ_IDX_W-1:0]]
          <= tage_pred_val_p0;
        pq_tail_r <= pq_tail_r + PQ_PTR_W'(1);
      end
    end
  end

  // ----------------------------------------------------------------
  // Update Queue (UQ) FIFO
  // ----------------------------------------------------------------
  cond_pred_upd_inp_t
    uq_data_mem[TAGE_UQ_DEPTH][0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]
    uq_val_mem[TAGE_UQ_DEPTH];
  logic [UQ_PTR_W-1:0] uq_head_r, uq_tail_r;
  logic uq_full, uq_empty;

  assign uq_full  = (uq_tail_r[UQ_IDX_W-1:0]
                     == uq_head_r[UQ_IDX_W-1:0])
                 && (uq_tail_r[UQ_IDX_W]
                     != uq_head_r[UQ_IDX_W]);
  assign uq_empty = (uq_head_r == uq_tail_r);
  assign upd_rdy  = {NUM_PRED_SLOTS{!uq_full}};

  always_ff @(posedge clk) begin : uq_ff
    if (!rstn) begin
      uq_head_r <= '0;
      uq_tail_r <= '0;
    end else begin
      // Dequeue on UPD grant from non-empty UQ
      if (arb_grant_upd && !uq_empty)
        uq_head_r <= uq_head_r + UQ_PTR_W'(1);
      // Enqueue: incoming upd, not in bypass (uq non-empty
      // or no grant this cycle)
      if ((|tage_upd_val_u0) && !uq_full
          && (!uq_empty || !arb_grant_upd)) begin
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          uq_data_mem[uq_tail_r[UQ_IDX_W-1:0]][s].tage
            <= tage_upd_inp_u0[s];
          uq_data_mem[uq_tail_r[UQ_IDX_W-1:0]][s].sc
            <= '0;
          uq_data_mem[uq_tail_r[UQ_IDX_W-1:0]][s].sc_valid
            <= 1'b0;
          uq_data_mem[uq_tail_r[UQ_IDX_W-1:0]][s].resolved_taken
            <= tage_upd_inp_u0[s].resolved_taken;
          uq_data_mem[uq_tail_r[UQ_IDX_W-1:0]][s].cond_mispredict
            <= tage_upd_inp_u0[s].cond_mispredict;
        end
        uq_val_mem[uq_tail_r[UQ_IDX_W-1:0]]
          <= tage_upd_val_u0;
        uq_tail_r <= uq_tail_r + UQ_PTR_W'(1);
      end
    end
  end

  // ----------------------------------------------------------------
  // Credit arbiter: combinational grant logic
  // Rules applied in priority order per spec section 4.5.
  // Rule 1 (resp_buf_full blocks pred): encoded as guards on
  // pred-granting rules 3 and 5.
  // ----------------------------------------------------------------
  always_comb begin : arb_comb
    arb_grant_pred = 1'b0;
    arb_grant_upd  = 1'b0;

    // Rule 2: starvation override (highest priority)
    if (uq_has_data_w
        && (starve_ctr_r >= STARVE_W'(TAGE_STARVE_THRESH))) begin
      arb_grant_upd = 1'b1;
    end
    // Rules 3/4: both queues have data
    else if (pq_has_data_w && uq_has_data_w) begin
      if ((pred_credits_r > '0) && !resp_buf_full_w)
        // Rule 3: pred has credits, RB not full
        arb_grant_pred = 1'b1;
      else
        // Rule 4: pred credits exhausted (or RB full)
        arb_grant_upd = 1'b1;
    end
    // Rule 5: PQ only (UQ empty)
    else if (pq_has_data_w && !uq_has_data_w) begin
      if (!resp_buf_full_w)
        arb_grant_pred = 1'b1;
      // resp_buf_full: no grant (rule 1 blocks pred)
    end
    // Rule 6: UQ only
    else if (!pq_has_data_w && uq_has_data_w) begin
      arb_grant_upd = 1'b1;
    end
    // Rule 7: both empty -- no grant (implicit)
  end

  // ----------------------------------------------------------------
  // Credit register updates (always_ff, conditions mirror arb_comb)
  // ----------------------------------------------------------------
  always_ff @(posedge clk) begin : arb_cred_ff
    if (!rstn) begin
      pred_credits_r <= PRED_CRED_W'(TAGE_PRED_CREDITS);
      upd_credits_r  <= UPD_CRED_W'(TAGE_UPD_CREDITS);
      starve_ctr_r   <= '0;
    end else begin
      if (uq_has_data_w
          && (starve_ctr_r >= STARVE_W'(TAGE_STARVE_THRESH))) begin
        // Rule 2 fired: reset starve, reload upd_credits
        starve_ctr_r  <= '0;
        upd_credits_r <= UPD_CRED_W'(TAGE_UPD_CREDITS);
      end else if (pq_has_data_w && uq_has_data_w) begin
        if ((pred_credits_r > '0) && !resp_buf_full_w) begin
          // Rule 3 fired: dec pred_credits, inc starve
          pred_credits_r <= pred_credits_r - PRED_CRED_W'(1);
          starve_ctr_r   <= starve_ctr_r + STARVE_W'(1);
        end else begin
          // Rule 4 fired: reload all credits, reset starve
          pred_credits_r <= PRED_CRED_W'(TAGE_PRED_CREDITS);
          upd_credits_r  <= UPD_CRED_W'(TAGE_UPD_CREDITS);
          starve_ctr_r   <= '0;
        end
      end
      // Rules 5, 6, 7: no credit changes
    end
  end

  // ----------------------------------------------------------------
  // Competing stage mux: route PQ/bypass or UQ/bypass to tage_cntrl
  // ----------------------------------------------------------------
  always_comb begin : comp_stage_mux_comb
    cntrl_pred_val_p0 = '0;
    cntrl_upd_val_u0  = '0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      cntrl_pred_inp_p0[s] = '0;
      cntrl_upd_inp_u0[s]  = '0;
    end

    if (arb_grant_pred) begin
      if (pq_empty) begin
        // PQ bypass: use incoming prediction directly
        cntrl_pred_val_p0 = tage_pred_val_p0;
        for (int s = 0; s < NUM_PRED_SLOTS; s++)
          cntrl_pred_inp_p0[s] = tage_pred_inp_p0[s];
      end else begin
        // From PQ head
        cntrl_pred_val_p0 =
          pq_val_mem[pq_head_r[PQ_IDX_W-1:0]];
        for (int s = 0; s < NUM_PRED_SLOTS; s++)
          cntrl_pred_inp_p0[s] =
            pq_inp_mem[pq_head_r[PQ_IDX_W-1:0]][s];
      end
    end else if (arb_grant_upd) begin
      if (uq_empty) begin
        // UQ bypass: use incoming update directly
        // Fan tage_upd_inp_t to cntrl_upd_inp_u0 (tage_upd_inp_t)
        cntrl_upd_val_u0 = tage_upd_val_u0;
        for (int s = 0; s < NUM_PRED_SLOTS; s++)
          cntrl_upd_inp_u0[s] = tage_upd_inp_u0[s];
      end else begin
        // From UQ head: extract .tage sub-field
        cntrl_upd_val_u0 =
          uq_val_mem[uq_head_r[UQ_IDX_W-1:0]];
        for (int s = 0; s < NUM_PRED_SLOTS; s++)
          cntrl_upd_inp_u0[s] =
            uq_data_mem[uq_head_r[UQ_IDX_W-1:0]][s].tage;
      end
    end
  end

  // ----------------------------------------------------------------
  // bp_arb_trx_t pipeline register (p0/u0).
  // Captures the arbitration decision for pipeline tracking.
  // trx_type_comb (not arb_trx_r) is forwarded to tage_cntrl.
  // ----------------------------------------------------------------
  bp_arb_trx_t              arb_trx_r;
  logic [TRX_SLOT_BITS-1:0] arb_trx_slot_w;

  // Lowest active slot for current grant
  always_comb begin : arb_slot_comb
    arb_trx_slot_w = '0;
    for (int s = NUM_PRED_SLOTS-1; s >= 0; s--) begin
      if (arb_grant_pred && tage_pred_val_p0[s])
        arb_trx_slot_w = TRX_SLOT_BITS'(s);
      if (arb_grant_upd && tage_upd_val_u0[s])
        arb_trx_slot_w = TRX_SLOT_BITS'(s);
    end
  end

  always_ff @(posedge clk) begin : arb_trx_ff
    if (!rstn) begin
      arb_trx_r <= '0;
    end else begin
      arb_trx_r.trx_type <= arb_grant_upd;
      arb_trx_r.trx_slot <= arb_trx_slot_w;
    end
  end

  // ----------------------------------------------------------------
  // Prediction response buffer (RB)
  // Depth TAGE_RESP_BUF_DEPTH. Entry: cond_pred_meta_t per slot.
  // Bypass when RB empty and consumer_ready (consumer_ready=1).
  // ----------------------------------------------------------------
  cond_pred_meta_t
    rb_meta_mem[TAGE_RESP_BUF_DEPTH][0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]
    rb_val_mem[TAGE_RESP_BUF_DEPTH];
  logic [RB_PTR_W-1:0] rb_head_r, rb_tail_r;
  logic rb_full, rb_empty;

  assign rb_full  = (rb_tail_r[RB_IDX_W-1:0]
                     == rb_head_r[RB_IDX_W-1:0])
                 && (rb_tail_r[RB_IDX_W]
                     != rb_head_r[RB_IDX_W]);
  assign rb_empty = (rb_head_r == rb_tail_r);
  assign resp_buf_full_w = rb_full;

  always_ff @(posedge clk) begin : rb_ff
    if (!rstn) begin
      rb_head_r <= '0;
      rb_tail_r <= '0;
    end else begin
      // Dequeue: RB non-empty and consumer ready
      if (!rb_empty && consumer_ready)
        rb_head_r <= rb_head_r + RB_PTR_W'(1);
      // Enqueue: cntrl produced result and bypass not active
      // (bypass fires when rb_empty && consumer_ready)
      if (|cntrl_pred_rdy_p2) begin
        if (!rb_empty || !consumer_ready) begin
          for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
            rb_meta_mem[rb_tail_r[RB_IDX_W-1:0]][s].tage
              <= cntrl_pred_meta_p2[s];
            rb_meta_mem[rb_tail_r[RB_IDX_W-1:0]][s].sc
              <= '0;
            rb_meta_mem[rb_tail_r[RB_IDX_W-1:0]][s].sc_valid
              <= 1'b0;
          end
          rb_val_mem[rb_tail_r[RB_IDX_W-1:0]]
            <= cntrl_pred_rdy_p2;
          rb_tail_r <= rb_tail_r + RB_PTR_W'(1);
        end
      end
    end
  end

  // -- Response buffer output mux (bypass or RB head)
  always_comb begin : rb_out_comb
    if (rb_empty && consumer_ready) begin
      // Bypass: pass tage_cntrl result directly
      tage_pred_rdy_p2 = cntrl_pred_rdy_p2;
      for (int s = 0; s < NUM_PRED_SLOTS; s++)
        tage_pred_meta_p2[s] = cntrl_pred_meta_p2[s];
    end else begin
      // From RB head (extract .tage sub-field)
      tage_pred_rdy_p2 =
        rb_val_mem[rb_head_r[RB_IDX_W-1:0]]
        & {NUM_PRED_SLOTS{consumer_ready}};
      for (int s = 0; s < NUM_PRED_SLOTS; s++)
        tage_pred_meta_p2[s] =
          rb_meta_mem[rb_head_r[RB_IDX_W-1:0]][s].tage;
    end
  end

  // tage_upd_rdy_u1: from tage_cntrl's registered upd_val
  assign tage_upd_rdy_u1 = cntrl_upd_rdy_u1_w;

  // ================================================================
  // tage_cntrl instance
  // ================================================================
  tage_cntrl #(
    .NUM_PRED_SLOTS      (NUM_PRED_SLOTS)
  ) u_tage_cntrl (
    .clk                 (clk),
    .rstn                (rstn),
    .tage_pred_val_p0    (cntrl_pred_val_p0),
    .tage_pred_inp_p0    (cntrl_pred_inp_p0),
    .tage_pred_rdy_p2    (cntrl_pred_rdy_p2),
    .tage_pred_meta_p2   (cntrl_pred_meta_p2),
    .tage_upd_val_u0     (cntrl_upd_val_u0),
    .tage_upd_inp_u0     (cntrl_upd_inp_u0),
    .tage_upd_rdy_u1     (cntrl_upd_rdy_u1_w),
    .trx_type            (trx_type_comb),
    .tage_enable_aging   (tage_enable_aging),
    .tage_aging_interval (tage_aging_interval),
    .t_pred_val_p0       (w_pred_val_p0),
    .t_hit_p1            (w_hit_p1),
    .t_taken_p1          (w_taken_p1),
    .t_cntrl_bits_p1     (w_cntrl_bits_p1),
    .t_upd_val_u0        (w_upd_val_u0),
    .t_prm_ctr_wd_u0     (w_prm_ctr_wd_u0),
    .t_alt_ctr_wd_u0     (w_alt_ctr_wd_u0),
    .t_use_wd_u0         (w_use_wd_u0),
    .t_epc_wd_u0         (w_epc_wd_u0),
    .t_alc_wd_u0         (w_alc_wd_u0),
    .t_prm_ctr_wr_u0     (w_prm_ctr_wr_u0),
    .t_alt_ctr_wr_u0     (w_alt_ctr_wr_u0),
    .t_use_wr_u0         (w_use_wr_u0),
    .t_epc_wr_u0         (w_epc_wr_u0),
    .t_alc_wr_u0         (w_alc_wr_u0),
    .t_prm_tbl_sel_u0    (w_prm_tbl_sel_u0),
    .t_alt_tbl_sel_u0    (w_alt_tbl_sel_u0),
    .t_alc_tbl_sel_u0    (w_alc_tbl_sel_u0),
    .t_upd_index_u0      (w_upd_index_u0),
    .t_alc_index_u0      (w_alc_index_u0),
    .t_idx_p0            (w_idx_p0),
    .t_tag_p0            (w_tag_p0)
  );

  // ================================================================
  // sram_init: one shared instance for all table instances.
  // DATA_WIDTH=ALLOC_DATA_W (16b) covers tage_table T1-T4 entry.
  // tbl_ri_wd[TAGE_TBL_CTR[0]-1:0] sliced for tage_bim (2b CTR).
  // INIT_VAL='0 initializes all table entries to zero on reset.
  // ================================================================
  sram_init #(
    .NUM_ENTRIES (1 << TAGE_MAX_IDX_WIDTH),
    .ADDR_BITS   (TAGE_MAX_IDX_WIDTH),
    .DATA_WIDTH  (ALLOC_DATA_W),
    .INIT_VAL    (TAGE_SRAM_INIT_VALUE),
    .START_DELAY (8'h00)
  ) u_sram_init (
    .clk    (clk),
    .rstn   (rstn),
    .cs     (tbl_ri_cs),
    .wr     (ri_wr_raw),
    .waddr  (ri_wa_raw),
    .wdata  (ri_wd_raw),
    .active (ri_active_raw),
    .ready  (ri_rdy_raw)
  );

  // tage_rdy: muxed on fast_init_r.
  // fast_init_r=1: assert immediately (sram_init bypassed).
  // fast_init_r=0: follow sram_init ready output.
  assign tage_rdy = fast_init_r ? 1'b1 : ri_rdy_raw;

  // ================================================================
  // T0: tage_bim instance (outside generate).
  // Parameters bound from TAGE_TBL_* at index 0.
  // hit_p1: not present; w_hit_p1[0] driven constant 1 above.
  // tbl_ri_wd: sliced to TAGE_TBL_CTR[0]=2b (bim entry width).
  // tage_pred_inp_p0: routed from arbitration (cntrl_pred_inp_p0).
  // ================================================================
  tage_bim #(
    .THIS_TABLE      (0),
    .THIS_INDEX_BITS (TAGE_TBL_IDX[0]),
    .THIS_CTR_WIDTH  (TAGE_TBL_CTR[0]),
    .TBL_SEL_WIDTH   (TAGE_TBL_SEL_WIDTH),
    .NUM_PRED_SLOTS  (NUM_PRED_SLOTS)
  ) u_tage_bim (
    .taken_p1         (bim_taken_p1),
    .cntrl_bits_p1    (bim_cntrl_p1),
    .tage_pred_val_p0 (w_pred_val_p0[0]),
    .tage_pred_inp_p0 (cntrl_pred_inp_p0),
    .tage_upd_val_u0  (w_upd_val_u0[0]),
    .prm_ctr_wd_u0    (bim_prm_ctr_wd_u0),
    .prm_ctr_wr_u0    (w_prm_ctr_wr_u0[0]),
    .prm_tbl_sel_u0   (w_prm_tbl_sel_u0[0]),
    .upd_index_u0     (bim_upd_idx_u0),
    .tbl_ri_active    (tbl_ri_active),
    .tbl_ri_wr        (tbl_ri_wr),
    .tbl_ri_wa        (tbl_ri_wa),
    .tbl_ri_wd        (tbl_ri_wd[TAGE_TBL_CTR[0]-1:0]),
    .rstn             (rstn),
    .clk              (clk),
    .idx_hash_p0      (w_idx_p0[0])
  );

  // ================================================================
  // T1-T4: tage_table instances via generate loop.
  // gen_tage_tbl: one instance per table index t=1..4.
  // Parameters bound from TAGE_TBL_* at index t.
  // Intermediate wires inside loop slice MAX_*-wide cntrl buses
  // to THIS_*_BITS for each tage_table instance.
  // tage_pred_inp_p0: routed from arbitration (cntrl_pred_inp_p0).
  // ================================================================
  genvar t;
  generate
    for (t = 1; t < TAGE_NUM_TABLES; t++) begin : gen_tage_tbl
      // Per-table width aliases.
      localparam int T_IDX_W = TAGE_TBL_IDX[t]; // = 11
      localparam int T_CTR_W = TAGE_TBL_CTR[t]; // = 3

      // Width-matched intermediate wires.
      // upd_index and alc_index: slice MAX_IDX -> THIS_INDEX.
      logic [T_IDX_W-1:0] upd_idx_w[0:NUM_PRED_SLOTS-1];
      logic [T_IDX_W-1:0] alc_idx_w[0:NUM_PRED_SLOTS-1];
      // prm_ctr and alt_ctr: slice MAX_CTR -> THIS_CTR.
      logic [T_CTR_W-1:0] prm_ctr_w[0:NUM_PRED_SLOTS-1];
      logic [T_CTR_W-1:0] alt_ctr_w[0:NUM_PRED_SLOTS-1];

      assign upd_idx_w[0] = w_upd_index_u0[t][0][T_IDX_W-1:0];
      assign upd_idx_w[1] = w_upd_index_u0[t][1][T_IDX_W-1:0];
      assign alc_idx_w[0] = w_alc_index_u0[t][0][T_IDX_W-1:0];
      assign alc_idx_w[1] = w_alc_index_u0[t][1][T_IDX_W-1:0];
      assign prm_ctr_w[0] = w_prm_ctr_wd_u0[t][0][T_CTR_W-1:0];
      assign prm_ctr_w[1] = w_prm_ctr_wd_u0[t][1][T_CTR_W-1:0];
      assign alt_ctr_w[0] = w_alt_ctr_wd_u0[t][0][T_CTR_W-1:0];
      assign alt_ctr_w[1] = w_alt_ctr_wd_u0[t][1][T_CTR_W-1:0];

      tage_table #(
        .THIS_TABLE      (t),
        .THIS_INDEX_BITS (TAGE_TBL_IDX[t]),
        .THIS_TAG_BITS   (TAGE_TBL_TAG[t]),
        .THIS_EPC_WIDTH  (TAGE_TBL_EPC[t]),
        .THIS_USE_WIDTH  (TAGE_TBL_USE[t]),
        .THIS_CTR_WIDTH  (TAGE_TBL_CTR[t]),
        .TBL_SEL_WIDTH   (TAGE_TBL_SEL_WIDTH),
        .NUM_PRED_SLOTS  (NUM_PRED_SLOTS)
      ) u_tage_tbl (
        .clk              (clk),
        .rstn             (rstn),
        .hit_p1           (w_hit_p1[t]),
        .taken_p1         (w_taken_p1[t]),
        .cntrl_bits_p1    (w_cntrl_bits_p1[t]),
        .tage_pred_val_p0 (w_pred_val_p0[t]),
        .tage_pred_inp_p0 (cntrl_pred_inp_p0),
        .folded_hist      (folded_hist),
        .tage_upd_val_u0  (w_upd_val_u0[t]),
        .prm_ctr_wd_u0    (prm_ctr_w),
        .alt_ctr_wd_u0    (alt_ctr_w),
        .use_wd_u0        (w_use_wd_u0[t]),
        .epc_wd_u0        (w_epc_wd_u0[t]),
        .alc_wd_u0        (w_alc_wd_u0[t]),
        .prm_ctr_wr_u0    (w_prm_ctr_wr_u0[t]),
        .alt_ctr_wr_u0    (w_alt_ctr_wr_u0[t]),
        .use_wr_u0        (w_use_wr_u0[t]),
        .epc_wr_u0        (w_epc_wr_u0[t]),
        .alc_wr_u0        (w_alc_wr_u0[t]),
        .prm_tbl_sel_u0   (w_prm_tbl_sel_u0[t]),
        .alt_tbl_sel_u0   (w_alt_tbl_sel_u0[t]),
        .alc_tbl_sel_u0   (w_alc_tbl_sel_u0[t]),
        .upd_index_u0     (upd_idx_w),
        .alc_index_u0     (alc_idx_w),
        .tbl_ri_active    (tbl_ri_active),
        .tbl_ri_wr        (tbl_ri_wr),
        .tbl_ri_wa        (tbl_ri_wa),
        .tbl_ri_wd        (tbl_ri_wd),
        .idx_hash_p0      (w_idx_p0[t]),
        .tag_hash_p0      (w_tag_p0[t])
      );
    end
  endgenerate

endmodule : tage

`endif // TAGE_SV

`default_nettype wire
