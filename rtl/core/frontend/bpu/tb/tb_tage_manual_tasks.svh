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
// This exercises each row of the CTR update table.
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 1.1  1  1  1  1   1  0  >0   >0   INC  —    —     Provider = primary, predicted taken correctly     |
// 1.2  1  1  1  0   1  1  >0   >0   INC  —    —     Provider = primary, predicted taken correctly     |
// 2.1  1  0  0  0   0  0  >0   >0   INC  —    —     Provider = primary, predicted not-taken correctly |
// 2.2  1  0  0  1   0  1  >0   >0   INC  —    —     Provider = primary, predicted not-taken correctly |
// 3    1  1  0  1   1  0  >0   >0   DEC  INC  —     Provider = primary wrong, alt opposite prediction |
// 4    1  0  1  1   0  1  >0   >0   DEC  INC  —     Provider = primary wrong, alt opposite prediction |
// 5    1  1  0  0   1  1  >0   >0   DEC  —    —     Provider = primary wrong, alt same or ignored     |
// 6    1  0  1  0   0  0  >0   >0   DEC  —    —     Provider = primary wrong, alt same or ignored     |
// 7.1  0  1  1  1   0  1  >0   >0   —    INC  —     Provider = alt, predicted taken correctly         |
// 7.2  0  1  1  0   1  1  >0   >0   —    INC  —     Provider = alt, predicted taken correctly         |
// 8.1  0  0  0  0   0  0  >0   >0   —    INC  —     Provider = alt, predicted not-taken correctly     |
// 8.2  0  0  0  1   1  0  >0   >0   —    INC  —     Provider = alt, predicted not-taken correctly     |
// 9    0  1  0  1   0  1  >0   >0   INC  DEC  —     Provider = alt wrong, primary opposite prediction |
// 10   0  0  1  1   1  0  >0   >0   INC  DEC  —     Provider = alt wrong, primary opposite prediction |
// 11   0  1  0  0   1  1  >0   >0   —    DEC  —     Provider = alt wrong, pred_diff ignored           |
// 12   0  0  1  0   0  0  >0   >0   —    DEC  —     Provider = alt wrong, pred_diff ignored           |
// 13a  1  0  0  0   0  0  0    0    —    —    INC   BIM predicted NT, resolved NT, correct |
// 13b  1  0  1  0   0  0  0    0    —    —    DEC   BIM predicted NT, resolved T, wrong |
// 13c  1  1  0  0   1  1  0    0    —    —    DEC   BIM predicted T, resolved NT, wrong |
// 13d  1  1  1  0   1  1  0    0    —    —    INC   BIM predicted T, resolved T, correct |
// 13e  0  x  x  x   x  x  0    0    ASRT ASTR ASTR  Invalid: UP=0 when pCMP=aCMP=0. ADR-001 violation |
// 14.1 1  1  0  0   1  1  >0   0    DEC  —    -     Alt=BIM, primary wrong, alt same |
// 14.2 1  1  0  1   1  0  >0   0    DEC  —    -     Alt=BIM, primary wrong, alt opposite |       
// 15.1 1  0  1  0   0  0  >0   0    DEC  —    -     Alt=BIM, primary predicted NT, resolved T, wrong |
// 15.2 1  0  1  1   0  1  >0   0    DEC  —    -     Alt=BIM, primary predicted NT, resolved T, wrong, alt opposite |
// 16.1 1  1  1  0   1  1  >0   0    INC  —    -     Alt=BIM, primary predicted T, resolved T, correct, alt same |
// 16.2 1  1  1  1   1  0  >0   0    INC  —    -     Alt=BIM, primary predicted T, resolved T, correct, alt opposite |
// 17.1 1  0  0  0   0  0  >0   0    INC  —    -     Alt=BIM, primary predicted NT, resolved NT, correct, alt same |
// 17.2 1  0  0  1   0  1  >0   0    INC  —    -     Alt=BIM, primary predicted NT, resolved NT, correct, alt opposite |
// 18   x  x  x  x   x  x  0    >0   ASTR ASTR ASTR  Invalid condition pCMP=0 aCMP>0, handled by assert|
// -------------------------------------------------------------------
task automatic tage_ctr_test(
  inout int tb_errs,
  input int verb = 0,
  input int toe  = 0
);

  string this_test;
  int errs,v;
  logic [VA_WIDTH-1:0] pc;
  logic [FTQ_IDX_BITS-1:0]  bid;
  int pidx,aidx; //,t0idx;
  int pcomp,acomp;
  logic [TAGE_MAX_CTR_WIDTH-1:0] pctr,actr,t0ctr;
  logic pred_diff; //this is just to make correlating to the table easier

  tage_ram_entry_t pentry,aentry,t0entry,rentry,pexp_entry,aexp_entry,t0exp_entry;
  tage_pred_meta_t pred_meta; //attached to upd_data
  tage_upd_inp_t   upd_data;  //sent during update

  v = 1;
  this_test = "tage_ctr_test";
  errs = 0;

  start_test(this_test);

  //Set initial conditions
  pc    = 40'h1000;
  bid   = 3;

  pidx  = int'(11'h100);
  aidx  = int'(11'h0F0);

  pcomp = 4;
  acomp = 2;
 
  pctr  = 3'b010;
  actr  = 3'b001;
  t0ctr = 3'b001;  //this is a 2b field in the RAM

  pentry.tag    = 8'hEF;
  aentry.tag    = 8'hDF;
  t0entry.tag   = 8'hD0; //this is dont care

  pentry.epc    = 2'h0;
  aentry.epc    = 2'h0;
  t0entry.epc   = 2'h0;  //this is dont care

  pentry.ctr    = pctr;
  aentry.ctr    = actr;
  t0entry.ctr   = t0ctr; //this is a 2b field in the RAM

  pentry.valid  = 1;
  aentry.valid  = 1;
  t0entry.valid = 1; //this is dont care

  // -----------------------------
  // Set the initial ram entry values and verify them
  // -----------------------------
  tage_ram_write(pcomp,pidx,pentry);
  tage_ram_write(acomp,aidx,aentry);

  tage_ram_read(pcomp,pidx,rentry);
  tage_cmp_ram_entry("PCOMP",pcomp,pidx,pentry,rentry,errs,0);

  tage_ram_read(acomp,aidx,rentry);
  tage_cmp_ram_entry("ACOMP",acomp,aidx,aentry,rentry,errs,0);
  // -----------------------------
  // Set the update data
  // -----------------------------
  // clear them first
  pred_meta = '0;
  upd_data  = '0;

  // These are the constant or dont care fields
  pred_meta.tage_prm_idx       = pidx;
  pred_meta.tage_alt_idx       = aidx;
  pred_meta.tage_prm_useful    = 0;
  pred_meta.tage_alt_useful    = 0;
  pred_meta.tage_alc_comp      = 0;
  pred_meta.tage_alc_idx       = 0;
  pred_meta.tage_alc_tag       = 0;
  pred_meta.tage_pred_strong   = 0;
  pred_meta.tage_use_alt_on_na = 0;
  pred_meta.tage_high_conf     = 0;
  pred_meta.branch_id          = bid;

  pred_meta.tage_prm_ctr   = pctr;
  pred_meta.tage_alt_ctr   = actr;
  
  pred_meta.tage_prm_comp  = pcomp;
  pred_meta.tage_alt_comp  = acomp;

// -------------------------------------------------------------
// ROW 1.1
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 1.1  1  1  1  1   1  0  >0   >0   INC  —    —     Provider = primary, predicted taken correctly     |
//
// PCTR = 2 -> 3  PUSE = 0 -> 1
// ACTR = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 1.1");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 1, 1, 1, 0,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry; //these are the expected ram contents for prm
  aexp_entry        = aentry;
  pexp_entry.ctr    = 3; pexp_entry.useful = 1;
  aexp_entry.ctr    = 1; aexp_entry.useful = 0;
  check_ctr_row("R1.1",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 1.2
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 1.2  1  1  1  0   1  1  >0   >0   INC  —    —     Provider = primary, predicted taken correctly     |
//
// PCTR = 2 -> 3  PUSE = 0 -> 1  ERROR: there is something wrong with USEFUL
// ACTR = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 1.2");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 1, 1, 1, 1,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 3; pexp_entry.useful = 0; //ERROR: should be 1
  aexp_entry.ctr    = 1; aexp_entry.useful = 0;
  check_ctr_row("R1.2",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 2.1
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 2.1  1  0  0  0   0  0  >0   >0   INC  —    —     Provider = primary, predicted not-taken correctly |
//
// PCTR = 2 -> 3  PUSE = 0 -> 1  ERROR: there is something wrong with USEFUL
// ACTR = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 2.1");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 0, 0, 0, 0,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 3; pexp_entry.useful = 0; //ERROR HERE: should be 1
  aexp_entry.ctr    = 1; aexp_entry.useful = 0;
  check_ctr_row("R2.1",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 2.2
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 2.2  1  0  0  1   0  1  >0   >0   INC  —    —     Provider = primary, predicted not-taken correctly |
//
// PCTR = 2 -> 3  PUSE = 0 -> 1
// ACTR = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 2.2");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 0, 0, 0, 0,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 3; pexp_entry.useful = 0; //ERROR HERE: should be 1
  aexp_entry.ctr    = 1; aexp_entry.useful = 0;
  check_ctr_row("R2.2",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 3
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 3    1  1  0  1   1  0  >0   >0   DEC  INC  —     Provider = primary wrong, alt opposite prediction |
//
// PCTR = 2 -> 1  PUSE = 0 -> 0
// ACTR = 1 -> 2  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 3");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 1, 0, 1, 0,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 1; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 2; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R3",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 4
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 4    1  0  1  1   0  1  >0   >0   DEC  INC  —     Provider = primary wrong, alt opposite prediction |
//
// PCTR = 2 -> 1  PUSE = 0 -> 0
// ACTR = 1 -> 2  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 4");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 0, 1, 0, 1,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 1; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 2; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R4",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 5
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 5    1  1  0  0   1  1  >0   >0   DEC  —    —     Provider = primary wrong, alt same or ignored     |
//
// PCTR = 2 -> 1  PUSE = 0 -> 0
// ACTR = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 5");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 1, 0, 1, 1,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 1; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 1; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R5",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 6
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 6    1  0  1  0   0  0  >0   >0   DEC  —    —     Provider = primary wrong, alt same or ignored     |
//
// PCTR = 2 -> 1  PUSE = 0 -> 0
// ACTR = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 6");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 0, 1, 0, 0,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 1; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 1; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R6",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 7.1
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 7.1  0  1  1  1   0  1  >0   >0   —    INC  —     Provider = alt, predicted taken correctly         |
//
// PCTR = 2 -> 2  PUSE = 0 -> 0
// ACTR = 1 -> 2  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 7.1");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,0, 1, 1, 0, 1,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 2; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 2; aexp_entry.useful = 1; //POSSIBLE ERROR
  check_ctr_row("R7.1",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 7.2
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 7.2  0  1  1  0   1  1  >0   >0   —    INC  —     Provider = alt, predicted taken correctly         |
//
// PCTR = 2 -> 2  PUSE = 0 -> 0
// ACTR = 1 -> 2  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 7.2");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,0, 1, 1, 1, 1,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 2; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 2; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R7.2",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 8.1
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 8.1  0  0  0  0   0  0  >0   >0   —    INC  —     Provider = alt, predicted not-taken correctly     |
//
// PCTR = 2 -> 2  PUSE = 0 -> 0
// ACTR = 1 -> 2  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 8.1");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,0, 0, 0, 0, 0,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 2; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 2; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R8.1",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 8.2
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 8.2  0  0  0  1   1  0  >0   >0   —    INC  —     Provider = alt, predicted not-taken correctly     |
//
// PCTR = 2 -> 2  PUSE = 0 -> 0
// ACTR = 1 -> 2  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 8.2");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,0, 0, 0, 1, 0,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 2; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 2; aexp_entry.useful = 1; //POSSIBLE ERROR
  check_ctr_row("R8.2",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 9
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 9    0  1  0  1   0  1  >0   >0   INC  DEC  —     Provider = alt wrong, primary opposite prediction |
//
// PCTR = 2 -> 3  PUSE = 0 -> 0
// ACTR = 1 -> 0  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 9");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,0, 1, 0, 0, 1,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 3; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 0; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("RX",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 10
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 10   0  0  1  1   1  0  >0   >0   INC  DEC  —     Provider = alt wrong, primary opposite prediction |
//
// PCTR = 2 -> 3  PUSE = 0 -> 0
// ACTR = 1 -> 0  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 10");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,0, 0, 1, 1, 0,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 3; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 0; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R10",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 11
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 11   0  1  0  0   1  1  >0   >0   —    DEC  —     Provider = alt wrong, pred_diff ignored           |
//
// PCTR = 2 -> 2  PUSE = 0 -> 0
// ACTR = 1 -> 0  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 11");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,0, 1, 0, 1, 1,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 2; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 0; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R11",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 12
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 12   0  0  1  0   0  0  >0   >0   —    DEC  —     Provider = alt wrong, pred_diff ignored           |
//
// PCTR = 2 -> 2  PUSE = 0 -> 0
// ACTR = 1 -> 0  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 12");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,0, 0, 1, 0, 0,pcomp,acomp);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 2; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 0; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R12",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 13a
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 13a  1  0  0  0   0  0  0    0    —    —    INC   BIM predicted NT, resolved NT, correct |
//
// T0CTR = 2 -> 3
// PCTR  = 2 -> 2  PUSE  = 0 -> 0
// ACTR  = 1 -> 1  AUSE  = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 13a");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  reset_t0_entry(pidx,pentry);
  //                             UP PT RT pT aT pcomp acomp
  set_ctr_row(pred_meta,upd_data,1, 0, 0, 0, 0, 0,    0);
  tage_update({upd_data,upd_data},2'b01,errs);

  t0exp_entry       = t0entry;
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  t0exp_entry.ctr   = 3; 
  pexp_entry.ctr    = 2; pexp_entry.useful = 0;
  aexp_entry.ctr    = 1; aexp_entry.useful = 0;
  check_ctr_row   ("R13a",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);
  check_ctr_row_t0("R13a",pidx,t0exp_entry,errs,v);

// -------------------------------------------------------------
// ROW 13b
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 13b  1  0  1  0   0  0  0    0    —    —    DEC   BIM predicted NT, resolved T, wrong |
//
// T0CTR = 2 -> 1
// PCTR  = 2 -> 2  PUSE = 0 -> 0
// ACTR  = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 13b");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  reset_t0_entry(pidx,pentry);
  //                             UP PT RT pT aT pcomp acomp
  set_ctr_row(pred_meta,upd_data,1, 0, 1, 0, 0, 0,    0);
  tage_update({upd_data,upd_data},2'b01,errs);

  t0exp_entry       = t0entry;
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  t0exp_entry.ctr   = 1; 
  pexp_entry.ctr    = 2; pexp_entry.useful = 0;
  aexp_entry.ctr    = 1; aexp_entry.useful = 0;
  check_ctr_row   ("R13b",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);
  check_ctr_row_t0("R13b",pidx,t0exp_entry,errs,v);

// -------------------------------------------------------------
// ROW 13c
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 13c  1  1  0  0   1  1  0    0    —    —    DEC   BIM predicted T, resolved NT, wrong |
//
// T0CTR = 2 -> 1
// PCTR  = 2 -> 2  PUSE = 0 -> 0
// ACTR  = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 13c");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  reset_t0_entry(pidx,pentry);
  //                             UP PT RT pT aT pcomp acomp
  set_ctr_row(pred_meta,upd_data,1, 1, 0, 1, 1, 0,    0);
  tage_update({upd_data,upd_data},2'b01,errs);

  t0exp_entry       = t0entry;
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  t0exp_entry.ctr   = 1; 
  pexp_entry.ctr    = 2; pexp_entry.useful = 0;
  aexp_entry.ctr    = 1; aexp_entry.useful = 0;
  check_ctr_row   ("R13c",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);
  check_ctr_row_t0("R13c",pidx,t0exp_entry,errs,v);

// -------------------------------------------------------------
// ROW 13d
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 13d  1  1  1  0   1  1  0    0    —    —    INC   BIM predicted T, resolved T, correct |
//
// T0CTR = 2 -> 3
// PCTR  = 2 -> 2  PUSE = 0 -> 0
// ACTR  = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 13d");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  reset_t0_entry(pidx,pentry);
  //                             UP PT RT pT aT pcomp acomp
  set_ctr_row(pred_meta,upd_data,1, 1, 1, 1, 1, 0,    0);
  tage_update({upd_data,upd_data},2'b01,errs);

  t0exp_entry       = t0entry;
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  t0exp_entry.ctr   = 3; 
  pexp_entry.ctr    = 2; pexp_entry.useful = 0;
  aexp_entry.ctr    = 1; aexp_entry.useful = 0;
  check_ctr_row   ("R13c",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);
  check_ctr_row_t0("R13c",pidx,t0exp_entry,errs,v);

// -------------------------------------------------------------
// ROW 14.1
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 14.1 1  1  0  0   1  1  >0   0    DEC  —    -     Alt=BIM, primary wrong, alt same |
//
// PCTR  = 2 -> 1  PUSE = 0 -> 0
// ACTR  = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 14.1");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 1, 0, 1, 1,pcomp,0);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 1; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 1; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R14.1",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 14.2
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 14.2 1  1  0  1   1  0  >0   0    DEC  —    -     Alt=BIM, primary wrong, alt opposite |       
//
// PCTR  = 2 -> 1  PUSE = 0 -> 0
// ACTR  = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 14.2");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 1, 0, 1, 0,pcomp,0);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 1; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 1; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R14.2",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 15.1
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 15.1 1  0  1  0   0  0  >0   0    DEC  —    -     Alt=BIM, primary predicted NT, resolved T, wrong |
//
// PCTR  = 2 -> 1  PUSE = 0 -> 0
// ACTR  = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 15.1");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 0, 1, 0, 0,pcomp,0);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 1; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 1; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R15.1",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 15.2
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 15.2 1  0  1  1   0  1  >0   0    DEC  —    -     Alt=BIM, primary predicted NT, resolved T, wrong, alt opposite |
//
// PCTR  = 2 -> 1  PUSE = 0 -> 0
// ACTR  = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 15.2");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 0, 1, 0, 1,pcomp,0);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 1; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 1; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R15.2",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 16.1
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 16.1 1  1  1  0   1  1  >0   0    INC  —    -     Alt=BIM, primary predicted T, resolved T, correct, alt same |
//
// PCTR  = 2 -> 3  PUSE = 0 -> 0
// ACTR  = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 16.1");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 1, 1, 1, 1,pcomp,0);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 3; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 1; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R16.1",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 16.2
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 16.2 1  1  1  1   1  0  >0   0    INC  —    -     Alt=BIM, primary predicted T, resolved T, correct, alt opposite |
//
// PCTR  = 2 -> 3  PUSE = 0 -> 0
// ACTR  = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 16.2");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 1, 1, 1, 0,pcomp,0);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 3; pexp_entry.useful = 1; //POSSIBLE ERROR
  aexp_entry.ctr    = 1; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R16.2",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 17.1
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 17.1 1  0  0  0   0  0  >0   0    INC  —    -     Alt=BIM, primary predicted NT, resolved NT, correct, alt same |
//
// PCTR  = 2 -> 3  PUSE = 0 -> 0
// ACTR  = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 17.1");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 0, 0, 0, 0,pcomp,0);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 3; pexp_entry.useful = 0; //POSSIBLE ERROR
  aexp_entry.ctr    = 1; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R17.1",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

// -------------------------------------------------------------
// ROW 17.2
// ROW  UP PT RT dif pT aT pCMP aCMP pACT aACT t0ACT Comments
// 17.2 1  0  0  1   0  1  >0   0    INC  —    -     Alt=BIM, primary predicted NT, resolved NT, correct, alt opposite |
//
// PCTR  = 2 -> 3  PUSE = 0 -> 0
// ACTR  = 1 -> 1  AUSE = 0 -> 0 
// -------------------------------------------------------------
  tb_info("CTR ROW 17.2");
  // reset the ram entry
  reset_ctr_entries(pcomp,pidx,acomp,aidx,pentry,aentry);
  //                             UP PT RT pT aT
  set_ctr_row(pred_meta,upd_data,1, 0, 0, 0, 1,pcomp,0);
  tage_update({upd_data,upd_data},2'b01,errs);
                 
  pexp_entry        = pentry;
  aexp_entry        = aentry;
  pexp_entry.ctr    = 3; pexp_entry.useful = 1; //POSSIBLE ERROR
  aexp_entry.ctr    = 1; aexp_entry.useful = 0; //POSSIBLE ERROR
  check_ctr_row("R17.2",pcomp,pidx,acomp,aidx,pexp_entry,aexp_entry,errs,v);

  // END
  stop_test(this_test,errs);
  tb_pf(this_test,errs);
  tb_errs += errs;
endtask

// -------------------------------------------------------------------
// -------------------------------------------------------------------
task automatic reset_t0_entry(
  input int              t0idx,
  input tage_ram_entry_t t0entry
);
  tage_ram_write(0, t0idx, t0entry);
endtask
// -------------------------------------------------------------------
// -------------------------------------------------------------------
task automatic check_ctr_row_t0(
  input string           label,
  input int              t0idx,
  input tage_ram_entry_t t0exp,
  inout int              errs,
  input int              v
);

  tage_ram_entry_t r;
  tage_ram_read(0, t0idx, r);
  tage_cmp_ram_entry_t0({label," T0   "}, t0idx, t0exp, r, errs, v);
endtask
// -------------------------------------------------------------------
// -------------------------------------------------------------------
task automatic set_ctr_row(
  inout tage_pred_meta_t meta,
  inout tage_upd_inp_t   upd,
  input logic using_primary,
  input logic pred_tkn,
  input logic resolved_taken,
  input logic prm_tkn,
  input logic alt_tkn,
  input int   prm_comp,
  input int   alt_comp,

);
  meta.tage_using_primary = using_primary;
  meta.tage_pred_tkn      = pred_tkn;
  meta.tage_prm_comp      = prm_comp;
  meta.tage_alt_comp      = alt_comp;
  upd.resolved_taken      = resolved_taken;
  meta.tage_prm_tkn       = prm_tkn;
  meta.tage_alt_tkn       = alt_tkn;
  upd.cond_mispredict     = pred_tkn != resolved_taken;
  upd.tage_pred_meta      = meta;
endtask
// -------------------------------------------------------------------
// -------------------------------------------------------------------
task automatic check_ctr_row(
  input string label,
  input int    pcomp, pidx, acomp, aidx,
  input tage_ram_entry_t pexp, aexp,
  inout int    errs,
  input int    v
);
  tage_ram_entry_t r;
  tage_ram_read(pcomp, pidx, r);
//$display("DBG: G : errors %0d",errs);
  tage_cmp_ram_entry({label," PCOMP"}, pcomp, pidx, pexp, r, errs, v);
//$display("DBG: H : errors %0d",errs);
  tage_ram_read(acomp, aidx, r);
//$display("DBG: I : errors %0d",errs);
  tage_cmp_ram_entry({label," ACOMP"}, acomp, aidx, aexp, r, errs, v);
//$display("DBG: J : errors %0d",errs);
endtask
// -------------------------------------------------------------------
// -------------------------------------------------------------------
task automatic reset_ctr_entries(
  input int pcomp, pidx, acomp, aidx,
  input tage_ram_entry_t pentry, aentry
);
  tage_ram_write(pcomp, pidx, pentry);
  tage_ram_write(acomp, aidx, aentry);
endtask
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
// -------------------------------------------------------------------
task automatic tage_cmp_ram_entry_t0(
  input string           which,
  input int              idx,
  input tage_ram_entry_t exp,
  input tage_ram_entry_t act,
  inout int              errs,
  input int              v
);
  if(exp.ctr !== act.ctr) begin
    $write("-E: %s : CTR mismatch, T0 idx=0x%04x",which,idx);
    $write(" exp: %02x",exp.ctr);
    $write(" act: %02x **\n",act.ctr);
    ++errs;
  end else if(v) begin
    $write("-I: %s : CTR match, T0 idx=0x%04x",which,idx);
    $write(" exp: %02x",exp.ctr);
    $write(" act: %02x\n",act.ctr);
  end
endtask
// -------------------------------------------------------------------
// tage_cmp_ram_entry: compare two ram entries
// -------------------------------------------------------------------
task automatic tage_cmp_ram_entry(
  input string which,
  input int tbl,
  input int idx,
  input tage_ram_entry_t exp,
  input tage_ram_entry_t act,
  inout int errs,
  input int v=0
);
  int lerrs = 0;
  if(exp.tag !== act.tag) begin
    $write("-E: %s : TAG mismatch, tbl %0d idx=0x%04x",which,tbl,idx);
    $write(" exp: %02x",exp.tag);
    $write(" act: %02x **\n",act.tag);
    ++lerrs;
  end else if(v) begin
    $write("-I: %s : TAG match, tbl %0d idx=0x%04x",which,tbl,idx);
    $write(" exp: %02x",exp.tag);
    $write(" act: %02x\n",act.tag);
  end

  if(exp.epc !== act.epc) begin
    $write("-E: %s : EPC mismatch, tbl %0d idx=0x%04x",which,tbl,idx);
    $write(" exp: %02x",exp.epc);
    $write(" act: %02x **\n",act.epc);
    ++lerrs;
  end else if(v) begin
    $write("-I: %s : EPC match, tbl %0d idx=0x%04x",which,tbl,idx);
    $write(" exp: %02x",exp.epc);
    $write(" act: %02x\n",act.epc);
  end

  if(exp.useful !== act.useful) begin
    $write("-E: %s : USE mismatch, tbl %0d idx=0x%04x",which,tbl,idx);
    $write(" exp: %02x",exp.useful);
    $write(" act: %02x **\n",act.useful);
    //$display("-D: %s : errors %0d, workaround Verilator opt bug",which,lerrs);
    ++lerrs;
    //$display("-D: %s : errors %0d, workaround Verilator opt bug",which,lerrs);
  end else if(v) begin
    $write("-I: %s : USE match, tbl %0d idx=0x%04x",which,tbl,idx);
    $write(" exp: %02x",exp.useful);
    $write(" act: %02x\n",act.useful);
  end

  if(exp.ctr !== act.ctr) begin
    $write("-E: %s : CTR mismatch, tbl %0d idx=0x%04x",which,tbl,idx);
    $write(" exp: %02x",exp.ctr);
    $write(" act: %02x **\n",act.ctr);
    ++lerrs;
  end else if(v) begin
    $write("-I: %s : CTR match, tbl %0d idx=0x%04x",which,tbl,idx);
    $write(" exp: %02x",exp.ctr);
    $write(" act: %02x\n",act.ctr);
  end

  if(exp.valid !== act.valid) begin
    $write("-E: %s : VAL mismatch, tbl %0d idx=0x%04x",which,tbl,idx);
    $write(" exp: %02x",exp.valid);
    $write(" act: %02x **\n",act.valid);
    ++lerrs;
  end else if(v) begin
    $write("-I: %s : VAL match, tbl %0d idx=0x%04x",which,tbl,idx);
    $write(" exp: %02x",exp.valid);
    $write(" act: %02x\n",act.valid);
  end

  errs += lerrs;
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
task automatic tage_round_trip_sanity(
  inout integer tb_errs,
  input verb = 0,
  input toe  = 0
);

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
  int errs;
  string this_test;
  errs = 0;
  this_test = "tage_round_trip_sanity";
 
  start_test(this_test);
  // Step 1: ?? this test was generated by IA, then modified

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
  if (rd_entry.valid !== wr_entry.valid) begin
    tb_error({this_test,": valid mismatch"});
    errs++;
  end
  if (rd_entry.ctr !== wr_entry.ctr) begin
    tb_error({this_test,": ctr mismatch"});
    errs++;
  end
  if (rd_entry.useful !== wr_entry.useful) begin
    tb_error({this_test,": useful mismatch"});
    errs++;
  end
  if (rd_entry.epc !== wr_entry.epc) begin
    tb_error({this_test,": epc mismatch"});
    errs++;
  end
  if (rd_entry.tag !== wr_entry.tag) begin
    tb_error({this_test,": tag mismatch"});
    errs++;
  end

  if (toe) begin
    if (errs > 0) begin
      stop_test(this_test, errs);
      tb_pf(this_test, errs);
      tb_errs += errs;
      return;
    end
  end

  // Step 4: predict slot 0 with TEST_PC.
  pred_inp[0]           = '0;
  pred_inp[0].pc        = TEST_PC;
  pred_inp[0].branch_id = '0;
  pred_inp[1]           = '0;
  tage_predict(pred_inp, 2'b01, meta1, rdy, errs);

  // Step 5: verify rdy[0] asserted.
  if (!rdy[0]) begin
    tb_error("round_trip_sanity: pred1 rdy[0] not asserted");
    errs++;
  end

  // Step 7: update using meta captured at step 4/6.
  upd_inp[0]                 = '0;
  upd_inp[0].tage_pred_meta  = meta1[0];
  upd_inp[0].resolved_taken  = 1'b1;
  upd_inp[0].cond_mispredict = 1'b0;
  upd_inp[1]                 = '0;
  tage_update(upd_inp, 2'b01, errs);

  // Steps 8-9: second prediction and verify rdy.
  tage_predict(pred_inp, 2'b01, meta2, rdy, errs);
  if (!rdy[0]) begin
    tb_error("round_trip_sanity: pred2 rdy[0] not asserted");
    errs++;
  end

  stop_test(this_test,errs);
  tb_pf(this_test,errs);
  tb_errs += errs;
endtask
