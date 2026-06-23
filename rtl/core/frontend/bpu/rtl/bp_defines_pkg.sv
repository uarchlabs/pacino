// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    bp_defines_pkg.sv
// DATE:    2026-05-14
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Branch predictor cluster package: parameters
// All BP cluster modules import this package.
// ===================================================================
`ifndef BP_DEFINES_PKG_SV
`define BP_DEFINES_PKG_SV

package bp_defines_pkg;

  // ================================================================
  // :Global parameters:
  // ================================================================
  parameter int VA_WIDTH          = 40;  // virtual address width (RVA23)
  parameter int GHR_WIDTH         = 256; // global history register width
  parameter int PHR_WIDTH         = 32;  // path history register width
  parameter int GHIST_PTR_BITS    = $clog2(GHR_WIDTH); // = 8
  parameter int PHIST_PTR_BITS    = $clog2(PHR_WIDTH);  // = 5
  parameter int FTQ_DEPTH         = 64;  // fetch target queue depth
  parameter int FETCH_BLOCK_BYTES = 64;  // fetch block size in bytes
  parameter int INST_OFFSET       =  2;  // right shift for PC 
  // NUM_PRED_SLOTS: 1 = single prediction, 2 = dual 
  // Elaboration-time parameter; not a runtime signal.
  // Update channel array bp_update_t [NUM_PRED_SLOTS-1:0] is declared
  // at instantiation, not inside bp_update_t.
  parameter int NUM_PRED_SLOTS    = 2;
  // TRX_SLOT_BITS: slot index width for bp_arb_trx_t.
  // Clamped to 1 when NUM_PRED_SLOTS == 1 to prevent a
  // zero-width vector ($clog2(1) == 0 -> [-1:0] is illegal).
  localparam int TRX_SLOT_BITS = (NUM_PRED_SLOTS > 1) ?
                                   $clog2(NUM_PRED_SLOTS) : 1;
  parameter int FTQ_CONF_BITS     = 4;  // confidence field width (TBD)

  // FTQ slot index width: $clog2(64) = 6
  localparam int FTQ_IDX_BITS = $clog2(FTQ_DEPTH);

  // ================================================================
  // :uBTB parameters:
  // ================================================================
  // Size: 256 entries, 4-way associative.
  // Stage: s1 output. First prediction; no redirect generated.
  parameter int UBTB_ENTRIES = 256;
  parameter int UBTB_WAYS    = 4;

  localparam int UBTB_SETS     = UBTB_ENTRIES / UBTB_WAYS; // = 64
  localparam int UBTB_IDX_BITS = $clog2(UBTB_SETS);        // = 6
  localparam int UBTB_TAG_BITS = 20;                        // PC[26:7]

  // ================================================================
  // :Loop predictor parameters:
  // ================================================================
  // Size: 256 entries, 4-way associative (64 sets).
  // Stage: s1 output. Overrides uBTB when trusted.
  parameter int LP_TBL_ENTRIES = 256;
  parameter int LP_TBL_WAYS    = 4;
  parameter int LP_TAG_BITS    = 14;
  parameter int LP_ITR_BITS    = 14; // iteration counter width
  parameter int LP_CNF_BITS    = 2;  // confidence counter width
  parameter int LP_AGE_BITS    = 8;  // age/replacement counter width

  localparam int LP_N_SETS   = LP_TBL_ENTRIES / LP_TBL_WAYS; // = 64
  localparam int LP_IDX_BITS   = $clog2(LP_N_SETS);           // = 6
  localparam int LP_WAY_BITS   = $clog2(LP_TBL_WAYS);         // = 2
  localparam int LP_CONF_LEVEL = (1 << LP_CNF_BITS) - 1;      // = 3

  // ----------------------------------------------------------------
  // LP arbitration parameters (TBD)
  // ----------------------------------------------------------------
  localparam int LP_PQ_DEPTH       = 0; // TBD
  localparam int LP_UQ_DEPTH       = 0; // TBD
  localparam int LP_UQ_WR_PORTS    = 0; // TBD
  localparam int LP_RESP_BUF_DEPTH = 0; // TBD
  localparam int LP_PRED_CREDITS   = 0; // TBD
  localparam int LP_UPD_CREDITS    = 0; // TBD
  localparam int LP_STARVE_THRESH  = 0; // TBD

  // ================================================================
  // :FTB parameters:
  // ================================================================
  // Size: 2048 entries, 8-way associative.
  // Stage: s2 output. Authoritative target for direct branches.
  parameter int FTB_ENTRIES = 2048;
  parameter int FTB_WAYS    = 8;

  localparam int FTB_SETS     = FTB_ENTRIES / FTB_WAYS; // = 256
  localparam int FTB_IDX_BITS = $clog2(FTB_SETS);       // = 8

  // ----------------------------------------------------------------
  // FTB arbitration parameters (TBD)
  // ----------------------------------------------------------------
  localparam int FTB_PQ_DEPTH       = 0; // TBD
  localparam int FTB_UQ_DEPTH       = 0; // TBD
  localparam int FTB_UQ_WR_PORTS    = 0; // TBD
  localparam int FTB_RESP_BUF_DEPTH = 0; // TBD
  localparam int FTB_PRED_CREDITS   = 0; // TBD
  localparam int FTB_UPD_CREDITS    = 0; // TBD
  localparam int FTB_STARVE_THRESH  = 0; // TBD

  // ================================================================
  // :TAGE parameters:
  // ================================================================
  parameter int TAGE_NUM_TABLES = 5;
  //                                        T0   T1   T2   T3   T4
  parameter int TAGE_TBL_BANKS[0:4]   = '{   2,   2,   2,   2,   2 };
  parameter int TAGE_TBL_ENTRIES[0:4] = '{2048,2048,2048,2048,2048 };
  parameter int TAGE_TBL_FH[0:4]      = '{   0,   8,  11,  11,  11 };
  parameter int TAGE_TBL_FH1[0:4]     = '{   0,   8,   8,   8,   8 };
  parameter int TAGE_TBL_FH2[0:4]     = '{   0,   7,   7,   7,   7 };
  parameter int TAGE_TBL_HIST[0:4]    = '{   0,   8,  13,  32, 119 };
  parameter int TAGE_TBL_TAG[0:4]     = '{   0,   8,   8,   8,   8 };
  parameter int TAGE_TBL_CTR[0:4]     = '{   2,   3,   3,   3,   3 };
  parameter int TAGE_TBL_USE[0:4]     = '{   0,   2,   2,   2,   2 };
  parameter int TAGE_TBL_EPC[0:4]     = '{   0,   2,   2,   2,   2 };
  parameter int TAGE_TBL_IDX[0:4]     = '{  11,  11,  11,  11,  11 };

  // TAGE meta field widths (G11 resolved here).
  // Per-table index widths; max of T0-T4 used for TAGE_MAX_AWIDTH.
//  localparam int TAGE_T0_IDX_BITS   = TAGE_TBL_IDX[0];
//  localparam int TAGE_T1_IDX_BITS   = TAGE_TBL_IDX[1];
//  localparam int TAGE_T2_IDX_BITS   = TAGE_TBL_IDX[2];
//  localparam int TAGE_T3_IDX_BITS   = TAGE_TBL_IDX[3];
//  localparam int TAGE_T4_IDX_BITS   = TAGE_TBL_IDX[4];

  localparam int TAGE_MAX_AWIDTH    = 11;
  localparam int TAGE_MAX_TAG_BITS  =  8;
  localparam int TAGE_MAX_DWIDTH    = TAGE_MAX_TAG_BITS;

  // tage_table per-entry max field widths.
  // Used as bus widths on tage_table prediction and update ports.
  // Resolves Known Gap 2 from tage_table_interfaces.md.
  localparam int TAGE_MAX_IDX_WIDTH = 11;
  localparam int TAGE_MAX_TAG_WIDTH = 8;
  localparam int TAGE_MAX_EPC_WIDTH = 2;
  localparam int TAGE_MAX_USE_WIDTH = 2;
  localparam int TAGE_MAX_CTR_WIDTH = 3;
  localparam int TAGE_MAX_VAL_WIDTH = 1;
  localparam int TAGE_MAX_FH  = 11;
  localparam int TAGE_MAX_FH1 = 8;
  localparam int TAGE_MAX_FH2 = 7;

  localparam int TAGE_SRAM_INIT_VALUE = 0;
  localparam int TAGE_UAON_THRES      = 8; // UAON threshold value
  localparam int TAGE_UAON_WIDTH      = 4;
  localparam int TAGE_TBL_SEL_WIDTH   = $clog2(TAGE_NUM_TABLES); // = 3

  // ----------------------------------------------------------------
  // TAGE arbitration parameters
  // ----------------------------------------------------------------
  localparam int TAGE_PQ_DEPTH       = 8;
  localparam int TAGE_UQ_DEPTH       = 8;
  localparam int TAGE_UQ_WR_PORTS    = 2;
  localparam int TAGE_RESP_BUF_DEPTH = 2;
  localparam int TAGE_PRED_CREDITS   = 4;
  localparam int TAGE_UPD_CREDITS    = 1;
  localparam int TAGE_STARVE_THRESH  = 8;

  // ================================================================
  // :SC parameters:
  // ================================================================
  // SC (Statistical Corrector) parameters
  // ----------------------------------------------------------------
  // Stage: s3 output. Corrects TAGE when systematically biased.
  // Threshold: fixed at design time (TBD, not CSR-configurable).

  parameter int SC_NUM_ALL_TBLS = 5; //TODO clean this up
  parameter int SC_NUM_TABLES   = 5;
  //                                      ST0   ST1  ST2  ST3  ST4
  parameter int SC_TBL_BANKS[0:4]      = '{  2,   2,   2,   2,   2 };
  parameter int SC_TBL_ENTRIES[0:4]    = '{512, 512, 512, 512,1024 };
  parameter int SC_TBL_FH[0:4]         = '{  0,   4,  16,  64,   0 };
  parameter int SC_TBL_HIST[0:4]       = '{  0,   4,  16,  64,   0 };
  parameter int SC_TBL_TAG[0:4]        = '{  0,   0,   0,   0,   0 };
  parameter int SC_TBL_CTR[0:4]        = '{  6,   6,   6,   6,   6 };
  parameter int SC_TBL_USE[0:4]        = '{  0,   0,   0,   0,   0 };
  parameter int SC_TBL_EPC[0:4]        = '{  0,   0,   0,   0,   0 };
  parameter int SC_TBL_IDX[0:4]        = '{  9,   9,   9,   9,  10 };

  localparam int SC_MAX_IDX_WIDTH = 10;
  localparam int SC_MAX_TAG_WIDTH =  0;
  localparam int SC_MAX_EPC_WIDTH =  0;
  localparam int SC_MAX_USE_WIDTH =  0;
  localparam int SC_MAX_CTR_WIDTH =  6;
  localparam int SC_MAX_VAL_WIDTH =  0;
  localparam int SC_MAX_FH        = 64;
  localparam int SC_MAX_FH1       =  0;
  localparam int SC_MAX_FH2       =  0;

  localparam int SC_SRAM_INIT_VALUE = 0;
  localparam int SC_TBL_SEL_WIDTH   = $clog2(SC_NUM_TABLES);

  localparam int SC_LO_THRESHOLD    = 25;
  localparam int SC_HI_THRESHOLD    = 35;
  localparam int SC_IMLI_INDEX_BITS = 10; //SC_TBL_IDX[4]

  parameter int SC_MAX_DATA_WIDTH = SC_MAX_CTR_WIDTH; 
  // ----------------------------------------------------------------
  // SC arbitration parameters
  // SC shares the TAGE UQ; no PQ or UQ parameters here.
  // ----------------------------------------------------------------
  localparam int SC_RESP_BUF_DEPTH = 0; // TBD

  // ================================================================
  // :ITTAGE parameters:
  // ================================================================
  parameter int IT_NUM_TABLES = 6;
  //                                        -  IT1  IT2  IT3  IT4  IT5
  parameter int IT_TBL_BANKS[0:5]      = '{ 0,   2,   2,   2,   2,   2 };
  parameter int IT_TBL_ENTRIES[0:5]    = '{ 0, 256, 256, 512, 512, 512 };
  parameter int IT_TBL_FH[0:5]         = '{ 0,   4,   8,   9,   9,   9 };
  parameter int IT_TBL_FH1[0:5]        = '{ 0,   4,   8,   9,   9,   9 };
  parameter int IT_TBL_FH2[0:5]        = '{ 0,   4,   8,   8,   8,   8 };
  parameter int IT_TBL_HIST[0:5]       = '{ 0,   4,   8,  13,  16,  32 };
  parameter int IT_TBL_TAG[0:5]        = '{ 0,   8,   8,   9,   9,  11 };
  parameter int IT_TBL_CTR[0:5]        = '{ 0,   3,   3,   3,   3,   3 };
  parameter int IT_TBL_USE[0:5]        = '{ 0,   2,   2,   2,   2,   2 };
  parameter int IT_TBL_EPC[0:5]        = '{ 0,   2,   2,   2,   2,   2 };
  parameter int IT_TBL_IDX[0:5]        = '{ 0,   8,   8,   9,   9,   9 };
  parameter int IT_TBL_TGT_WIDTH[0:5]  = '{ 0,  38,  38,  38,  38,  38 };

  localparam int IT_MAX_IDX_WIDTH = 9;
  localparam int IT_MAX_TAG_WIDTH = 11;
  localparam int IT_MAX_EPC_WIDTH = 2;
  localparam int IT_MAX_USE_WIDTH = 2;
  localparam int IT_MAX_CTR_WIDTH = 3;
  localparam int IT_MAX_VAL_WIDTH = 1;
  localparam int IT_MAX_TGT_WIDTH = 38;
  localparam int IT_MAX_FH        = 9;
  localparam int IT_MAX_FH1       = 9;
  localparam int IT_MAX_FH2       = 8;

  localparam int IT_SRAM_INIT_VALUE = 0;
  localparam int IT_UAON_THRES      = 8; // UAON threshold value
  localparam int IT_UAON_WIDTH      = 4;
  localparam int IT_TBL_SEL_WIDTH   = $clog2(IT_NUM_TABLES);

  // ----------------------------------------------------------------
  // ITTAGE arbitration parameters (TBD)
  // ----------------------------------------------------------------
  localparam int ITTAGE_PQ_DEPTH       = 4;
  localparam int ITTAGE_UQ_DEPTH       = 2;
  localparam int ITTAGE_UQ_WR_PORTS    = 2;
  localparam int ITTAGE_RESP_BUF_DEPTH = 2;
  localparam int ITTAGE_PRED_CREDITS   = 2;
  localparam int ITTAGE_UPD_CREDITS    = 1;
  localparam int ITTAGE_STARVE_THRESH  = 2;


  // ============================================================
  // :RAS parameters:
  // ============================================================
  // Dual-stack RAS. Static partition: 16 speculative entries,
  // 32 commit entries. Simple circular buffer. No linked list.
  // See planning/arch/ras_decisions.md section 3.
  parameter int RAS_SPEC_ENTRIES    = 16;
  parameter int RAS_COMMIT_ENTRIES  = 32;
  parameter int RAS_RCTR_WIDTH      = 4;
  parameter int RAS_ADDR_WIDTH      = VA_WIDTH;

  // RAS_PTR_BITS: $clog2(16) = 4
  localparam int RAS_PTR_BITS = $clog2(RAS_SPEC_ENTRIES);
  // RAS_COMMIT_PTR_BITS: $clog2(32) = 5
  localparam int RAS_COMMIT_PTR_BITS = $clog2(RAS_COMMIT_ENTRIES);

endpackage : bp_defines_pkg

`endif // BP_DEFINES_PKG_SV
