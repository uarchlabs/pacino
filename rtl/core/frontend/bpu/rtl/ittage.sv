// ===================================================================
// FILE:    ittage.sv
// DATE:    2026-05-18
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// ITTAGE structural wrapper. Instantiates ittage_cntrl and five
// ittage_table instances (IT1-IT5) with one shared sram_init.
// BP-038: PQ, UQ, credit arbiter, response buffer added.
// trx_type_comb forwarded combinationally (not registered).
// consumer_ready tied to 1'b1 internally; not a port.
// BP-038a: trx_type_comb connected to ittage_cntrl trx_type port.
// BP-038b: Response buffer removed; outputs driven directly from
//          ittage_cntrl. Six active arbitration rules remain.
// ===================================================================
`ifndef ITTAGE_SV
`define ITTAGE_SV

`default_nettype none

import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ittage (
  input  logic                      clk,
  input  logic                      rstn,

  // prediction interface
  input  logic [NUM_PRED_SLOTS-1:0] ittage_pred_val_p0,
  input  ittage_pred_inp_t          ittage_pred_inp_p0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0] ittage_pred_rdy_p2,
  output ittage_pred_meta_t         ittage_pred_meta_p2[0:NUM_PRED_SLOTS-1],

  // update interface
  input  logic [NUM_PRED_SLOTS-1:0] ittage_upd_val_u0,
  input  ittage_upd_inp_t           ittage_upd_inp_u0[0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0] ittage_upd_rdy_u1,

  // arbitration status outputs (BP-038)
  output logic                      pq_not_full,
  output logic [NUM_PRED_SLOTS-1:0] upd_rdy,

  // aging control (shared across slots)
  input  logic                      ittage_enable_aging,
  input  logic [31:0]               ittage_aging_interval,

  // folded history (shared across prediction slots)
  input  bp_folded_hist_t           folded_hist,

  // ram init ready
  output logic                      ittage_rdy
);

  // ================================================================
  // Localparams -- must match ittage_cntrl and ittage_table.
  // ================================================================
  localparam int CNTRL_BITS_WIDTH =
    IT_MAX_VAL_WIDTH  + IT_MAX_CTR_WIDTH
    + IT_MAX_USE_WIDTH + IT_MAX_EPC_WIDTH
    + IT_MAX_TGT_WIDTH;  // 1+3+2+2+38 = 46

  localparam int IT_MAX_ALLOC_DATA_WIDTH =
    CNTRL_BITS_WIDTH + IT_MAX_TAG_WIDTH;  // 46+11 = 57

  // Max entries: 2^IT_MAX_IDX_WIDTH covers largest table (IT3-5).
  localparam int IT_MAX_NUM_ENTRIES = 1 << IT_MAX_IDX_WIDTH;

  // -- Arbitration FIFO and counter sizing (BP-038)
  localparam int PQ_IDX_W    = $clog2(ITTAGE_PQ_DEPTH);
  localparam int PQ_PTR_W    = PQ_IDX_W + 1;
  localparam int UQ_IDX_W    = $clog2(ITTAGE_UQ_DEPTH);
  localparam int UQ_PTR_W    = UQ_IDX_W + 1;
  localparam int PRED_CRED_W =
    $clog2(ITTAGE_PRED_CREDITS + 1);
  localparam int UPD_CRED_W  =
    $clog2(ITTAGE_UPD_CREDITS  + 1);
  localparam int STARVE_W    =
    $clog2(ITTAGE_STARVE_THRESH + 1);

  // ================================================================
  // Fast-init mode: plusarg +ITTAGE_FAST_INIT=1.
  // When active: ittage_rdy driven high immediately.
  // sram_init still elaborates and cycles normally.
  // ================================================================
  logic fast_init;
  initial begin
    int fi;
    fi        = 0;
    fast_init = 1'b0;
    void'($value$plusargs("ITTAGE_FAST_INIT=%d", fi));
    if (fi != 0) fast_init = 1'b1;
  end

  // ================================================================
  // Shared sram_init: single instance at top level; MAX parameters
  // cover all five tables. All tables receive the same init signals.
  // ================================================================
  logic                               ri_cs;
  logic                               ri_wr;
  logic [IT_MAX_IDX_WIDTH-1:0]        ri_wa;
  logic [IT_MAX_ALLOC_DATA_WIDTH-1:0] ri_wd;
  logic                               ri_active;
  logic                               ri_rdy;

  sram_init #(
    .NUM_ENTRIES(IT_MAX_NUM_ENTRIES),
    .ADDR_BITS  (IT_MAX_IDX_WIDTH),
    .DATA_WIDTH (IT_MAX_ALLOC_DATA_WIDTH),
    .INIT_VAL   (IT_SRAM_INIT_VALUE)
  ) u_sram_init (
    .clk   (clk),
    .rstn  (rstn),
    .cs    (ri_cs),
    .wr    (ri_wr),
    .waddr (ri_wa),
    .wdata (ri_wd),
    .active(ri_active),
    .ready (ri_rdy)
  );

  // ================================================================
  // Internal bus: ittage_table outputs -> ittage_cntrl inputs.
  // All arrays [0:IT_NUM_TABLES-1]. Index 0 tied to zero (no IT0).
  // ================================================================
  logic [NUM_PRED_SLOTS-1:0] tbl_hit_p1[0:IT_NUM_TABLES-1];
  logic [IT_MAX_TGT_WIDTH-1:0]
    tbl_pred_tgt_p1[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [CNTRL_BITS_WIDTH-1:0]
    tbl_cntrl_bits_p1[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  // idx_hash output is THIS_INDEX_BITS; zero-extended to IT_MAX here.
  logic [IT_MAX_IDX_WIDTH-1:0]
    tbl_idx_hash_p0[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_TAG_WIDTH-1:0]
    tbl_tag_hash_p0[0:IT_NUM_TABLES-1][0:NUM_PRED_SLOTS-1];

  // IT0 placeholder -- never instantiated.
  assign tbl_hit_p1[0] = '0;
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : gen_tbl0_tie
    assign tbl_pred_tgt_p1[0][s]   = '0;
    assign tbl_cntrl_bits_p1[0][s] = '0;
    assign tbl_idx_hash_p0[0][s]   = '0;
    assign tbl_tag_hash_p0[0][s]   = '0;
  end : gen_tbl0_tie

  // ================================================================
  // Internal bus: ittage_cntrl outputs -> ittage_table inputs.
  // Write data fanned to all tables; alc_wd sliced per table width.
  // ================================================================
  logic [IT_MAX_CTR_WIDTH-1:0]
    cntrl_prm_ctr_wd[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_CTR_WIDTH-1:0]
    cntrl_alt_ctr_wd[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_USE_WIDTH-1:0]
    cntrl_use_wd[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_EPC_WIDTH-1:0]
    cntrl_epc_wd[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_TGT_WIDTH-1:0]
    cntrl_tgt_wd[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_ALLOC_DATA_WIDTH-1:0]
    cntrl_alc_wd[0:NUM_PRED_SLOTS-1];
  // Write strobes.
  logic [NUM_PRED_SLOTS-1:0] cntrl_prm_ctr_wr;
  logic [NUM_PRED_SLOTS-1:0] cntrl_alt_ctr_wr;
  logic [NUM_PRED_SLOTS-1:0] cntrl_use_wr;
  logic [NUM_PRED_SLOTS-1:0] cntrl_epc_wr;
  logic [NUM_PRED_SLOTS-1:0] cntrl_tgt_wr;
  logic [NUM_PRED_SLOTS-1:0] cntrl_alc_wr;
  // Table selectors.
  logic [IT_TBL_SEL_WIDTH-1:0]
    cntrl_prm_tbl_sel[0:NUM_PRED_SLOTS-1];
  logic [IT_TBL_SEL_WIDTH-1:0]
    cntrl_alt_tbl_sel[0:NUM_PRED_SLOTS-1];
  logic [IT_TBL_SEL_WIDTH-1:0]
    cntrl_alc_tbl_sel[0:NUM_PRED_SLOTS-1];
  // Update and allocation addresses (max width; sliced per table).
  logic [IT_MAX_IDX_WIDTH-1:0]
    cntrl_upd_index[0:NUM_PRED_SLOTS-1];
  logic [IT_MAX_IDX_WIDTH-1:0]
    cntrl_alc_index[0:NUM_PRED_SLOTS-1];

  // ================================================================
  // Arbitration layer (BP-038)
  // ================================================================

  // ----------------------------------------------------------------
  // Arbitrated signals (competing stage -> ittage_cntrl)
  // ----------------------------------------------------------------
  logic [NUM_PRED_SLOTS-1:0]        cntrl_pred_val_p0;
  ittage_pred_inp_t
    cntrl_pred_inp_p0[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]        cntrl_pred_rdy_p2;
  ittage_pred_meta_t
    cntrl_pred_meta_p2[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]        cntrl_upd_val_u0;
  ittage_upd_inp_t
    cntrl_upd_inp_u0[0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]        cntrl_upd_rdy_u1_w;

  // -- Arbiter outputs and trx_type
  logic arb_grant_pred, arb_grant_upd;
  logic trx_type_comb;
  // trx_type_comb: combinational from arbiter (not registered).
  assign trx_type_comb = arb_grant_upd;

  // -- pq_has_data / uq_has_data (include bypass candidates)
  logic pq_has_data_w, uq_has_data_w;
  assign pq_has_data_w =
    !pq_empty || (|ittage_pred_val_p0);
  assign uq_has_data_w =
    !uq_empty || (|ittage_upd_val_u0);

  // consumer_ready = 1'b1 internally; no downstream SC chain.

  // ----------------------------------------------------------------
  // Credit arbiter registers
  // ----------------------------------------------------------------
  logic [PRED_CRED_W-1:0] pred_credits_r;
  logic [UPD_CRED_W-1:0]  upd_credits_r;
  logic [STARVE_W-1:0]     starve_ctr_r;

  // ----------------------------------------------------------------
  // Prediction Queue (PQ) FIFO
  // ----------------------------------------------------------------
  ittage_pred_inp_t
    pq_inp_mem[ITTAGE_PQ_DEPTH][0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]
    pq_val_mem[ITTAGE_PQ_DEPTH];
  logic [PQ_PTR_W-1:0] pq_head_r, pq_tail_r;
  logic pq_full, pq_empty;

  assign pq_full  = (pq_tail_r[PQ_IDX_W-1:0]
                     == pq_head_r[PQ_IDX_W-1:0])
                 && (pq_tail_r[PQ_IDX_W]
                     != pq_head_r[PQ_IDX_W]);
  assign pq_empty   = (pq_head_r == pq_tail_r);
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
      if ((|ittage_pred_val_p0) && !pq_full
          && (!pq_empty || !arb_grant_pred)) begin
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          pq_inp_mem[pq_tail_r[PQ_IDX_W-1:0]][s]
            <= ittage_pred_inp_p0[s];
        end
        pq_val_mem[pq_tail_r[PQ_IDX_W-1:0]]
          <= ittage_pred_val_p0;
        pq_tail_r <= pq_tail_r + PQ_PTR_W'(1);
      end
    end
  end

  // ----------------------------------------------------------------
  // Update Queue (UQ) FIFO
  // ----------------------------------------------------------------
  ittage_upd_inp_t
    uq_data_mem[ITTAGE_UQ_DEPTH][0:NUM_PRED_SLOTS-1];
  logic [NUM_PRED_SLOTS-1:0]
    uq_val_mem[ITTAGE_UQ_DEPTH];
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
      if ((|ittage_upd_val_u0) && !uq_full
          && (!uq_empty || !arb_grant_upd)) begin
        for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
          uq_data_mem[uq_tail_r[UQ_IDX_W-1:0]][s]
            <= ittage_upd_inp_u0[s];
        end
        uq_val_mem[uq_tail_r[UQ_IDX_W-1:0]]
          <= ittage_upd_val_u0;
        uq_tail_r <= uq_tail_r + UQ_PTR_W'(1);
      end
    end
  end

  // ----------------------------------------------------------------
  // Credit arbiter: combinational grant logic
  // Rules applied in priority order per bp_arb_spec.md section 4.5.
  // Six active rules (Rule 1 eliminated with RB removal).
  // ----------------------------------------------------------------
  always_comb begin : arb_comb
    arb_grant_pred = 1'b0;
    arb_grant_upd  = 1'b0;

    // Rule 2: starvation override (highest priority)
    if (uq_has_data_w
        && (starve_ctr_r
            >= STARVE_W'(ITTAGE_STARVE_THRESH))) begin
      arb_grant_upd = 1'b1;
    end
    // Rules 3/4: both queues have data
    else if (pq_has_data_w && uq_has_data_w) begin
      if (pred_credits_r > '0)
        // Rule 3: pred has credits
        arb_grant_pred = 1'b1;
      else
        // Rule 4: pred credits exhausted
        arb_grant_upd = 1'b1;
    end
    // Rule 5: PQ only (UQ empty)
    else if (pq_has_data_w && !uq_has_data_w) begin
      arb_grant_pred = 1'b1;
    end
    // Rule 6: UQ only
    else if (!pq_has_data_w && uq_has_data_w) begin
      arb_grant_upd = 1'b1;
    end
    // Rule 7: both empty -- no grant (implicit)
  end

  // ----------------------------------------------------------------
  // Credit register updates
  // ----------------------------------------------------------------
  always_ff @(posedge clk) begin : arb_cred_ff
    if (!rstn) begin
      pred_credits_r <=
        PRED_CRED_W'(ITTAGE_PRED_CREDITS);
      upd_credits_r  <=
        UPD_CRED_W'(ITTAGE_UPD_CREDITS);
      starve_ctr_r   <= '0;
    end else begin
      if (uq_has_data_w
          && (starve_ctr_r
              >= STARVE_W'(ITTAGE_STARVE_THRESH))) begin
        // Rule 2 fired: reset starve, reload upd_credits
        starve_ctr_r  <= '0;
        upd_credits_r <= UPD_CRED_W'(ITTAGE_UPD_CREDITS);
      end else if (pq_has_data_w && uq_has_data_w) begin
        if (pred_credits_r > '0) begin
          // Rule 3 fired: dec pred_credits, inc starve
          pred_credits_r <=
            pred_credits_r - PRED_CRED_W'(1);
          starve_ctr_r   <=
            starve_ctr_r + STARVE_W'(1);
        end else begin
          // Rule 4 fired: reload all credits, reset starve
          pred_credits_r <=
            PRED_CRED_W'(ITTAGE_PRED_CREDITS);
          upd_credits_r  <=
            UPD_CRED_W'(ITTAGE_UPD_CREDITS);
          starve_ctr_r   <= '0;
        end
      end
      // Rules 5, 6, 7: no credit changes
    end
  end

  // ----------------------------------------------------------------
  // Competing stage mux: route PQ/bypass or UQ/bypass to ittage_cntrl
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
        cntrl_pred_val_p0 = ittage_pred_val_p0;
        for (int s = 0; s < NUM_PRED_SLOTS; s++)
          cntrl_pred_inp_p0[s] = ittage_pred_inp_p0[s];
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
        // UQ bypass: route ittage_upd_inp_t directly
        cntrl_upd_val_u0 = ittage_upd_val_u0;
        for (int s = 0; s < NUM_PRED_SLOTS; s++)
          cntrl_upd_inp_u0[s] = ittage_upd_inp_u0[s];
      end else begin
        // From UQ head: ittage_upd_inp_t stored directly
        cntrl_upd_val_u0 =
          uq_val_mem[uq_head_r[UQ_IDX_W-1:0]];
        for (int s = 0; s < NUM_PRED_SLOTS; s++)
          cntrl_upd_inp_u0[s] =
            uq_data_mem[uq_head_r[UQ_IDX_W-1:0]][s];
      end
    end
  end

  // ----------------------------------------------------------------
  // bp_arb_trx_t pipeline register (p0/u0).
  // trx_type_comb (not arb_trx_r) is the combinational grant signal.
  // ----------------------------------------------------------------
  bp_arb_trx_t              arb_trx_r;
  logic [TRX_SLOT_BITS-1:0] arb_trx_slot_w;

  // Lowest active slot for current grant
  always_comb begin : arb_slot_comb
    arb_trx_slot_w = '0;
    for (int s = NUM_PRED_SLOTS-1; s >= 0; s--) begin
      if (arb_grant_pred && ittage_pred_val_p0[s])
        arb_trx_slot_w = TRX_SLOT_BITS'(s);
      if (arb_grant_upd && ittage_upd_val_u0[s])
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

  // -- Output: ittage_cntrl prediction results connect directly
  assign ittage_pred_rdy_p2 = cntrl_pred_rdy_p2;

  for (genvar s = 0;
       s < NUM_PRED_SLOTS; s++) begin : gen_pred_out
    assign ittage_pred_meta_p2[s] = cntrl_pred_meta_p2[s];
  end : gen_pred_out

  // ittage_upd_rdy_u1: from ittage_cntrl registered upd_val
  assign ittage_upd_rdy_u1 = cntrl_upd_rdy_u1_w;

  // ================================================================
  // ittage_cntrl instantiation. All ports connected.
  // ================================================================
  ittage_cntrl u_cntrl (
    .clk                  (clk),
    .rstn                 (rstn),
    .ittage_pred_val_p0   (cntrl_pred_val_p0),
    .ittage_pred_inp_p0   (cntrl_pred_inp_p0),
    .ittage_pred_rdy_p2   (cntrl_pred_rdy_p2),
    .ittage_pred_meta_p2  (cntrl_pred_meta_p2),
    .ittage_upd_val_u0    (cntrl_upd_val_u0),
    .ittage_upd_inp_u0    (cntrl_upd_inp_u0),
    .ittage_upd_rdy_u1    (cntrl_upd_rdy_u1_w),
    .ittage_enable_aging  (ittage_enable_aging),
    .ittage_aging_interval(ittage_aging_interval),
    .trx_type             (trx_type_comb),
    .tbl_hit_p1           (tbl_hit_p1),
    .tbl_pred_tgt_p1      (tbl_pred_tgt_p1),
    .tbl_cntrl_bits_p1    (tbl_cntrl_bits_p1),
    .tbl_idx_hash_p0      (tbl_idx_hash_p0),
    .tbl_tag_hash_p0      (tbl_tag_hash_p0),
    .prm_ctr_wd_u0        (cntrl_prm_ctr_wd),
    .alt_ctr_wd_u0        (cntrl_alt_ctr_wd),
    .use_wd_u0            (cntrl_use_wd),
    .epc_wd_u0            (cntrl_epc_wd),
    .tgt_wd_u0            (cntrl_tgt_wd),
    .alc_wd_u0            (cntrl_alc_wd),
    .prm_ctr_wr_u0        (cntrl_prm_ctr_wr),
    .alt_ctr_wr_u0        (cntrl_alt_ctr_wr),
    .use_wr_u0            (cntrl_use_wr),
    .epc_wr_u0            (cntrl_epc_wr),
    .tgt_wr_u0            (cntrl_tgt_wr),
    .alc_wr_u0            (cntrl_alc_wr),
    .prm_tbl_sel_u0       (cntrl_prm_tbl_sel),
    .alt_tbl_sel_u0       (cntrl_alt_tbl_sel),
    .alc_tbl_sel_u0       (cntrl_alc_tbl_sel),
    .upd_index_u0         (cntrl_upd_index),
    .alc_index_u0         (cntrl_alc_index)
  );

  // ================================================================
  // IT1-IT5: ittage_table instances.
  // t=0 skipped (no IT0 base table).
  // - alc_wd sliced to each table's ALLOC_DATA_WIDTH = 46+TH_TAG.
  // - upd_index and alc_index sliced to TH_IDX bits.
  // - idx_hash_p0 zero-extended from TH_IDX to IT_MAX_IDX_WIDTH.
  // - tbl_ri_* driven from shared sram_init; wa/wd sliced per table.
  // - pred/upd val and inp routed through arbitration layer.
  // ================================================================
  for (genvar t = 0;
       t < IT_NUM_TABLES; t++) begin : gen_ittage_tables
    if (t != 0) begin : gen_active

      localparam int TH_IDX = IT_TBL_IDX[t];
      localparam int TH_TAG = IT_TBL_TAG[t];
      localparam int TH_ALC = CNTRL_BITS_WIDTH + TH_TAG;

      // Per-slot signals sliced to this table's widths.
      logic [TH_ALC-1:0]  alc_wd_s[0:NUM_PRED_SLOTS-1];
      logic [TH_IDX-1:0]  upd_idx_s[0:NUM_PRED_SLOTS-1];
      logic [TH_IDX-1:0]  alc_idx_s[0:NUM_PRED_SLOTS-1];
      // idx_hash at table width before extension to max.
      logic [TH_IDX-1:0]  idx_hash_local[0:NUM_PRED_SLOTS-1];
      logic               tbl_ri_wr;
      logic [TH_IDX-1:0]  tbl_ri_wa;
      logic [TH_ALC-1:0]  tbl_ri_wd;
      assign tbl_ri_wr = fast_init ? '0 : ri_wr;
      assign tbl_ri_wa = fast_init ? '0 : ri_wa[TH_IDX-1:0];
      assign tbl_ri_wd = fast_init ? '0 : ri_wd[TH_ALC-1:0];

      for (genvar s = 0;
           s < NUM_PRED_SLOTS; s++) begin : gen_slot_signals
        assign alc_wd_s[s]  = cntrl_alc_wd[s][TH_ALC-1:0];
        assign upd_idx_s[s] = cntrl_upd_index[s][TH_IDX-1:0];
        assign alc_idx_s[s] = cntrl_alc_index[s][TH_IDX-1:0];
        assign tbl_idx_hash_p0[t][s] =
          IT_MAX_IDX_WIDTH'(idx_hash_local[s]);
      end : gen_slot_signals

      ittage_table #(
        .THIS_TABLE     (t),
        .THIS_INDEX_BITS(TH_IDX),
        .THIS_TAG_BITS  (TH_TAG)
      ) u_table (
        .hit_p1             (tbl_hit_p1[t]),
        .pred_tgt_p1        (tbl_pred_tgt_p1[t]),
        .cntrl_bits_p1      (tbl_cntrl_bits_p1[t]),
        .idx_hash_p0        (idx_hash_local),
        .tag_hash_p0        (tbl_tag_hash_p0[t]),
        .ittage_pred_val_p0 (cntrl_pred_val_p0),
        .ittage_pred_inp_p0 (cntrl_pred_inp_p0),
        .folded_hist        (folded_hist),
        .ittage_upd_val_u0  (cntrl_upd_val_u0),
        .prm_ctr_wd_u0      (cntrl_prm_ctr_wd),
        .alt_ctr_wd_u0      (cntrl_alt_ctr_wd),
        .use_wd_u0          (cntrl_use_wd),
        .epc_wd_u0          (cntrl_epc_wd),
        .tgt_wd_u0          (cntrl_tgt_wd),
        .alc_wd_u0          (alc_wd_s),
        .prm_ctr_wr_u0      (cntrl_prm_ctr_wr),
        .alt_ctr_wr_u0      (cntrl_alt_ctr_wr),
        .use_wr_u0          (cntrl_use_wr),
        .epc_wr_u0          (cntrl_epc_wr),
        .tgt_wr_u0          (cntrl_tgt_wr),
        .alc_wr_u0          (cntrl_alc_wr),
        .prm_tbl_sel_u0     (cntrl_prm_tbl_sel),
        .alt_tbl_sel_u0     (cntrl_alt_tbl_sel),
        .alc_tbl_sel_u0     (cntrl_alc_tbl_sel),
        .upd_index_u0       (upd_idx_s),
        .alc_index_u0       (alc_idx_s),
        .tbl_ri_active      (ri_active),
        .tbl_ri_wr          (tbl_ri_wr),
        .tbl_ri_wa          (tbl_ri_wa),
        .tbl_ri_wd          (tbl_ri_wd),
        .rstn               (rstn),
        .clk                (clk)
      );

    end : gen_active
  end : gen_ittage_tables

  // ================================================================
  // ittage_rdy: sram_init complete or fast_init active.
  // ================================================================
  assign ittage_rdy = fast_init | ri_rdy;

endmodule : ittage

`endif // ITTAGE_SV

`default_nettype wire
