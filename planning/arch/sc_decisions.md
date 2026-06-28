<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Statistical Corrector (SC) Micro-Architectural Decisions
```
 FILE:    sc_decisions.md
 SOURCE:  manual and PA sessions
 STATUS:  Draft -- session-056
 UPDATED: 2026-06-26
 CONTACT: Jeff Nye
```

## 0. New Technical Debt 

Technical debt additions or new actions discovered as a result 
of this definition.

```
a.) Document sc_idx_hash in sc_table_hash_rules.md
b.) Document get_br_imli_idx in sc_table_hash_rules.md

c.) TD#87 verify TAGE tage_pred_strong maps to this
    decodings and add tage_pred_medium and
    tage_pred_weak signals to tage_pred_meta

  tage_pred_strong = 1'b0; //high confidence
  tage_pred_medium = 1'b0; //...
  tage_pred_weak   = 1'b0; //...

  000  strongly not taken  tage_pred_strong = 1'b1
  001  medium   not taken  tage_pred_medium = 1'b1
  010  medium   not taken  tage_pred_medium = 1'b1
  011  weak     not taken  tage_pred_weak   = 1'b1
  100  weak     taken      tage_pred_weak   = 1'b1
  101  medium   taken      tage_pred_medium = 1'b1
  110  medium   taken      tage_pred_medium = 1'b1
  111  strongly taken      tage_pred_strong = 1'b1

d.) TD#88 create two new tage_pred_meta_t signals
    and add logic to generate them in TAGE

    This signal is for convenience/timing

    logic [TAGE_MAX_CTR_WIDTH-1:0] tage_provider_ctr;
    tage_provider_ctr = tage_using_primary
                      ? tage_prm_ctr : tage_alt_ctr;

    This signal is signed (extended CTR)

    logic signed [TAGE_MAX_CTR_WIDTH+1:0] tage_extd_ctr;
    tage_extd_ctr = $signed({2'b00, provider_ctr, 1'b0}) - 5'sd7;

e.) Ask PA to summarize this dynamic threshold design, have the
    references added.  Known:

Storage Free Confidence Estimation for the TAGE Branch Predictor, HPCA 2011
A. Seznec, "Analysis of the O-GEHL Branch Predictor," ISCA 2005

f.) TD#89 FTB needs to store the bits [15:6] of the branch target
    this is placed into sc_upd_inp.sc_branch_range
g.) TD#90 FTB needs to store the sign of the offset of this branch and
    this is placed into sc_upd_inp.sc_backwards_branch
h.) TD#91 Top level bpc needs to route tage_pred_inp.pc to the ports
    of the SC, this must be staged from p0 to p2.
    SC will get additional port(s) pc[0:NUM_PRED_SLOTS-1];
    There are two of these, one for each prediction slot
i.) TD#92 add SC port that captures bits [9:0] of bp_folded_hist.tage_phr
    internally SC pipes this to p2, signal is called sc_phr_p2. 


```

## 1. Context

Not all of this context will be necessary for all tasks.

### SC Planning context:

```
- SC top level decisions (this document)
    - planning/arch/sc_decisions.md

- SC table index creation  [NOT WRITTEN]
    - planning/arch/sc_table_hash_rules.md

- SC control logic description  [NOT WRITTEN, NEEDED ?]
    - planning/arch/sc_cntrl_decisions.md

- SC confidence counter operation  [NOT WRITTEN]
    - planning/arch/sc_cntrl_ctr_update_rules.md

- SC table entry format reference  [NOT WRITTEN]
    - planning/arch/sc_table_entry_formats.md

- SC line coverage plan   [NOT WRITTEN]
    - verification/sc_coverage_plan.md

- SC table module IO ports and semantics  [NOT WRITTEN]
    - planning/interfaces/sc_table_interfaces.md

- SC top level IO ports and semantics  [NOT WRITTEN]
    - planning/interfaces/sc_interfaces.md

- SC testbench requirements  [NOT WRITTEN]
    - planning/testbenches/sc_tb_decisions.md

- SC SRAM reset triggered initialization semantics  [NOT WRITTEN]
    - planning/arch/sram_init.md

```
### BPU Planning context:

```
- Decisions related to the branch prediction unit
    - planning/arch/bp_decisions.md

- Decisions related to the load balanced prediction/update interface
    - planning/arch/bp_arb_spec.md
```

### SC RTL configuration context:

```
- Structures and meta data used to communicate in the BPU
    - rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv

- RTL design parameters for configuration of units in the BPU
    - rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
```

### RTL library components:

There is a library of common/shared modules.

```
- Banked RAM module 
    - rtl/lib/rtl/bw_ram.sv
    - This is the basis of the SC tables
 
- RAM init module
    - rtl/lib/rtl/sram_init.sv
    - This is the module that performs post reset table initization.
```

---

## 2. Overview and Scope

The Statistical Corrector (SC) is used to improve the accuracy of the TAGE
predictor by detecting branches which have shown little correlation to the TAGE
mechanism. The SC uses the TAGE output and the SC internal counters to
determine whether to reverse the TAGE prediction.

The SC is table based. The tables contain the confidence counters.  The tables
are indexed through a hashing scheme based on the PC. The tables are read in
parallel, their outputs are summed. If the magnitude of this sum falls within a
specified range the SC will invert the TAGE prediction. The range is specified
by parameters `SC_LO_THRESHOLD` and `SC_HI_THRESHOLD`. 

The TAGE s2 output is supplied to the SC, the SC operation is one cycle and the
SC outputs its results in s3.

Like TAGE, the SC supports dual predictions. These predictions operate in
parallel and do not share resources or conflict in operation. 

SC predictions require TAGE output. SC updates can proceed without input from
TAGE. 

## 3. Pipeline Notation

NOTE: There is an unfortunate discrepency in nomenclature of pipe stage naming.

The planning documents, specifications, etc, use s0/s1/s2/s3 pipestage naming.
However the RTL uses p0/p1/p2/p3. This document will continue the s0-3 labels
for consistency with the other documents until such time that all documents can
be updated.

The reason for the shift is the prediction slot 0/slot 1 complication re: slot0
-> s0, slot1 -> s1

The SC begins prediction operation using s2 signals.

For updates the pipestage numbering is u0/u1. This is consistent with
documentation and RTL.

So planning docs say s0/s1/s2/s3/u0/u1, RTL should use p0/p1/p2/p3/u0/u1.

---

## 4. Operation Phases

There are two non-overlapping phases for the SC operation. There is the
prediction phase and the update phase.

TAGE and SC are in lock step, TAGE and SC are each in the prediction phase or
the update phase. There is never a case there one is in the opposite phase.

There are dedicating module IOs for each phase. The module IO list and naming
convention are found in `sc_interfaces.md`.

These phases are defined to eliminate the need for read/modify/write to any of
the SC tables. Prediction is a RAM read process. Update is a RAM write process.
Data and meta data needed for update is generated during the prediction phase
and returned along with the prediction.

---
## 5. SC IO structures

In the prediction phase the SC is supplied with the TAGE prediction output,
`tage_pred_meta_t`, and the TAGE prediction request input, `tage_pred_inp_t`. 
The input contains the PC for the prediction request and the branch id.

NOTE: this is somewhat redundant in that the `branch_id` is also available in
the TAGE prediction output. We will accept the redundancy for now. See TD #85
for cleanup task.

### Prediction Phase SC structure inputs:

`(tage_pred_meta_t) tage_pred_meta` -> to SC
`(tage_pred_inp_t)  tage_pred_inp`  -> to SC

### Prediction Phase SC structure outputs:

SC -> `(sc_pred_meta_t) sc_pred_meta` to TOP

### Update Phase SC structure inputs:

`(sc_upd_inp_t) sc_upd_inp` -> to SC

### Update Phase SC structure outputs:

SC -> `(sc_pred_meta_t) sc_pred_meta` to TOP

The details of the SC top level ports and the SC table ports are found in
`sc_interfaces.md` and `sc_table_interfaces.md`.

---

## 6. Table Structure

The SC contains 5 tables. Each table contains two RAMs, one for each prediction
slot. These RAMs operate in parallel, there is no conflict or shared
information between these RAMs.

The number of tables is a parameter in `bp_defines_pkg.sv`, `SC_NUM_TABLES`.
Therefore there are 2 x `SC_NUM_TABLES` RAM instances in the tables.

The number of tables may change in the future. This requires the instantiation
of the SC tables to use a generate for-loop.

There are 4+1 tables by default. The default table naming is ST0-ST4.

Tables ST0-ST3 contain confidence counters.  Table ST4 is the BrIMLI table.
BrIMLI is described later.

ST1-ST3 are indexed using the PC hashed with the history inputs.  The history
inputs are an SC top level port, `(bp_folded_hist_t) bp_folded_hist`.

ST0 uss a portion of the PC directly without a hash.

ST4 is indexed by the BrIMLI counter.

Each table ST1-ST3 has a different history length. History length determines
how many bits of history are XOR's with the PC to form the index.

The table geometry are controlled by parameter arrays. These parameters are
found in `bp_defined_pkg.sv`. 

NOTE: `SC_TBL_BANKS[0:4]` this parameter is not currently used.

The RAM library component, `bw_ram` includes a BANK module parameter, this is
not related to prediction slots. This is a placeholder for eventual mapping
of `bw_ram` to a physical RAM model. The `bw_ram` models in `sc_table` always
use BANK(2) for their module parameter. This is also their default.

## 7. SC Table Parameters and Structures

In future this section can be just a reference to the two package files,
`bp_defines_pkg.sv` and `bp_structs_pkg.sv`. Do this once the discussion
has been reviewed and validated.

### Parameter reference

SC and `sc_table` parameters are defined in `bp_defines_pkg.sv`. That file is
the reference, this section is a brief summary. Some parameters are defined to
be consistent with TAGE and ITTAGE table parameters but do not apply to the SC.

```
SC_TBL_BANKS[n]  : this parameter is not currently used.
SC_TBL_ENTRIES[n]: table N entry count, e.g. rows
SC_TBL_FH[n]     : table N history length
SC_TBL_HIST[n]   : table N history length, duplicate of SC_TBL_FH
SC_TBL_TAG[n]    : table N tag width, SC table entries do not have tags
SC_TBL_CTR[n]    : table N confidence counter width
SC_TBL_USE[n]    : table N useful field width, SC entries do not have USE field
SC_TBL_EPC[n]    : table N epoch field width, SC entries do not have EPC field
SC_TBL_IDX[n]    : table N number of bits in the index.
```

There are also a number of MAX width parameters which are used to define a
common signal widths for port definitions etc.

These parameters support the prediction and up date phases. Their use is
explicitly shown in the following sections.

```
int SC_THRSH_BITS   =   12;
int SC_THRSH_MIN    =    2;
int SC_THRSH_MID    = 2048;
int SC_THRSH_MAX    = 4096;
int SC_TC_BITS      =   10;
int SC_LSUM_BITS    =   10;
int SC_CHOOSER_BITS =    6;
int SC_CHOOSER_MAX  =   32;
int SC_CHOOSER_MIN  =  -32;
```

### SC Enum Structures Reference

SC enums and structures are defined in `bp_structs_pkg.sv`.
That file is the reference, this is a brief summary supporting the discussion.

this section is a brief summary. Some parameters are defined to
be consistent with TAGE and ITTAGE table parameters but do not apply to the SC.

This enum supports range selection for the override logic

```
typedef enum logic [1:0] {
  CHOOSE_NONE  = 2'b00,
  CHOOSE_MED   = 2'b01,
  CHOOSE_HIGH  = 2'b10,
  CHOOSE_RSRVD = 2'b11,
} bp_sc_chooser_e;
```

---

## 8. SC Control Local State and Controls

There are local registers in `sc_cntrl.sv`. They are define here:

```
//Unsigned dynamic threshold
logic [SC_THRSH_BITS-1:0]  threshold,threshhold_d;

//Threshold adaption counter, includes declaration of temporaries
logic signed [SC_TC_BITS-1:0]     TC,TC_d,TC_inc; 

//There are two corners for the thresholding

// corner 1: TAGE-hi  & SC-very-low
logic signed [SC_CHOOSER_BITS-1:0] choose_hi_vlo;

// corner 2: TAGE-med & SC-very-very-low
logic signed [SC_CHOOSER_BITS-1:0] choose_med_vvlo;

// These are locally declared in the module
localparam signed [SC_TC_BITS-1:0] LCL_TC_MAX
                  = {1'b0,{(SC_TC_BITS-1){1'b1}}}; // 0111..1
localparam signed [SC_TC_BITS-1:0] LCL_TC_MIN
                  = {1'b1,{(SC_TC_BITS-1){1'b0}}}; // 1000..0

// Registers used by br_imli index generation
`br_imli` is the backwards branch counter, cleared on reset
`bb_hist` is the backwards branch path register, cleared on reset
`last_back_pc` stores the pc range of the previous backwards branch

logic [9:0]  br_imli;
logic [10:0] last_back_pc; //bit [10] is the valid bit; 
logic [9:0]  bb_hist;

```

---

### Persistent state reset

Abstracted - verilog reset is assumed, reset is active low, rstn
```
if(!rstn) {
  TC = 0;
  threshold       = SC_THRSH_MID;
  choose_hi_vlo   = 0;
  choose_med_vvlo = 0;
  br_imli = 0;
  bb_hist = 0;
  last_back_pc = 0;

}

```

## 8. SC Prediction Phase Operation

The inputs to the prediction phase are the PC, table histories, tage 
results. The outputs populate an `sc_pred_meta_t` structure.
```
// Read the SC tables

// inp_pc is an SC input port, one for each prediction slot, it is 
// staged from the tage input 

// sc_phr_p2 is an SC input port, it is staged from the p0 version of the
// bp_folded_hist.phr[9:0] input of tage and staged to p2.

logic [SC_MAX_IDX_WIDTH-1:0] st0_index = sc_idx_hash(inp_pc,SC_TBL_FH[0]);
logic [SC_MAX_IDX_WIDTH-1:0] st1_index = sc_idx_hash(inp_pc,SC_TBL_FH[1]);
logic [SC_MAX_IDX_WIDTH-1:0] st2_index = sc_idx_hash(inp_pc,SC_TBL_FH[2]);
logic [SC_MAX_IDX_WIDTH-1:0] st3_index = sc_idx_hash(inp_pc,SC_TBL_FH[3]);
logic [SC_MAX_IDX_WIDTH-1:0] st4_index
  = get_br_imli_idx(inp_pc,sc_phr_p2,br_imli);

logic [SC_MAX_CTR_WIDTH+1:0] value0 = (ST0[st0_index].ctr << 1) + 1;
logic [SC_MAX_CTR_WIDTH+1:0] value1 = (ST1[st1_index].ctr << 1) + 1;
logic [SC_MAX_CTR_WIDTH+1:0] value2 = (ST2[st2_index].ctr << 1) + 1;
logic [SC_MAX_CTR_WIDTH+1:0] value3 = (ST3[st3_index].ctr << 1) + 1;
logic [SC_MAX_CTR_WIDTH+1:0] value4 = (ST4[st4_index].ctr << 1) + 1;

// Calculate the local sum, include the TAGE contribution
logic signed [SC_LSUM_BITS-1:0] sc_sum = value0
                                       + value1
                                       + value2
                                       + value3
                                       + value4
                                       + tage_pred_meta.tage_extd_ctr;
// Create the local SC prediction
logic lcl_sc_pred_tkn = sc_sum >= 0;

// Create confidence bands

logic [SC_LSUM_BITS-1:0] abs_sum;
abs_sum = abs(sc_sum); // SC confidence magnitude

logic sc_vlo  = (abs_sum < (threshold >> 1));  // "very low"
logic sc_vvlo = (abs_sum < (threshold >> 2));  // "very very low"

// TAGE confidence: storage-free estimation, Seznec HPCA-2011
logic tage_hi  = tage_pred_meta.tage_pred_strong
logic tage_med = tage_pred_meta.tage_pred_medium

// Final selection: SC wins except in two corners
logic           final_pred;
bp_sc_chooser_e use_chooser;
logic           sc_override;

logic preds_differ = lcl_sc_pred_tkn != tage_pred_meta.tage_pred_tkn

if (!preds_differ) {

  final_pred  = lcl_sc_pred_tkn;    // agree
  sc_override = 1'b0;
  use_chooser = CHOOSE_NONE;

} else if (tage_hi && sc_vlo) {     // corner 1

  final_pred  = (choose_hi_vlo >= 0) ? lcl_sc_pred_tkn
                                     : tage_pred_meta.tage_pred_tkn;
  sc_override = (choose_hi_vlo >= 0 & preds_differ) ? 1'b1 : 1'b0;
  use_chooser = CHOOSE_HIGH;

} else if (tage_med && sc_vvlo) {   // corner 2

  final_pred  = (choose_med_vvlo >= 0) ? lcl_sc_pred_tkn
                                       : tage_pred_meta.tage_pred_tkn;
  sc_override = (choose_med_vvlo >= 0 & preds_differ) ? 1'b1 : 1'b0;
  use_chooser = CHOOSE_MED;

} else {

  final_pred  = lcl_sc_pred_tkn;    // general case: SC
  sc_override = (preds_differ) ? 1'b1 : 1'b0;
  use_chooser = CHOOSE_NONE;

}

// Capture what is needed for Update
sc_pred_meta.sc_sum           = sc_sum;
sc_pred_meta.sc_abs_sum       = abs_sum;
sc_pred_meta.sc_pred_tkn      = final_pred;
sc_pred_meta.sc_lcl_pred_tkn  = lcl_sc_pred_tkn;
sc_pred_meta.sc_tage_pred_tkn = tage_pred_tkn;
sc_pred_meta.sc_chooser       = use_chooser;
sc_pred_meta.sc_upd_idx[0]    = st0_index;
sc_pred_meta.sc_upd_idx[1]    = st1_index;
sc_pred_meta.sc_upd_idx[2]    = st2_index;
sc_pred_meta.sc_upd_idx[3]    = st3_index;
sc_pred_meta.sc_upd_idx[4]    = st4_index;
sc_pred_meta.sc_upd_ctr[0]    = value0;
sc_pred_meta.sc_upd_ctr[1]    = value1;
sc_pred_meta.sc_upd_ctr[2]    = value2;
sc_pred_meta.sc_upd_ctr[3]    = value3;
sc_pred_meta.sc_upd_ctr[4]    = value4;
sc_pred_meta.pc_range         = pc[15:6];
```

## 8. SC Update Phase Operation

Inputs to the update phase are taken from `sc_upd_inp` and the local
dynamic registers.

```
// Was the non-override SC prediction correct ?
logic sc_wrong  = (sc_upd_inp.sc_pred_meta.sc_lcl_pred_tkn
               != sc_upd_inp.resolved_taken);

// Is the threshold in the weak range
logic sc_lo_upd = (sc_upd_inp.sc_pred_meta.sc_abs_sum) < threshold;

// Use these signals to decide to update the CTRs and other state
logic do_update = sc_wrong || sc_lo_upd;

// Threshold-adaptation counter, compute next, then test it
if      (sc_wrong)  TC_inc = sat_tc(TC, +1);
else if (sc_lo_upd) TC_inc = sat_tc(TC, -1);
else                TC_inc = TC;

if(TC_inc == LCL_TC_MAX) {
  TC_d = 0;
  threshold_d = sat_thr(threshold, +1);
}
else if (TC_inc == LCL_TC_MIN) {
  TC_d = 0;
  threshold_d = sat_thr(threshold, -1);
}
else {
  TC_d = TC_inc;
  threshold_d = threshold;
}

posedge clk {
  TC = TC_d;
  threshold = threshold_d;

}

// If an update is enabled move the CTR's toward resolved direction 
if (do_update) {
    incr = resolved_taken ? +1 : -1;

    ST0[sc_upd_inp.sc_pred_meta.sc_upd_idx[0]]
       = sat_sc(sc_upd_inp.sc_pred_meta.sc_upd_ctr[0],incr);
    ST1[sc_upd_inp.sc_pred_meta.sc_upd_idx[1]]
       = sat_sc(sc_upd_inp.sc_pred_meta.sc_upd_ctr[1],incr);
    ST2[sc_upd_inp.sc_pred_meta.sc_upd_idx[2]]
       = sat_sc(sc_upd_inp.sc_pred_meta.sc_upd_ctr[2],incr);
    ST3[sc_upd_inp.sc_pred_meta.sc_upd_idx[3]]
       = sat_sc(sc_upd_inp.sc_pred_meta.sc_upd_ctr[3],incr);
    ST4[sc_upd_inp.sc_pred_meta.sc_upd_idx[4]]
       = sat_sc(sc_upd_inp.sc_pred_meta.sc_upd_ctr[4],incr);
}

// Train the chooser: only the counter that was consulted

logic sc_pred_match = sc_upd_inp.sc_pred_meta.sc_pred_tkn
                          == sc_upd_inp.resolved_taken;

logic tg_pred_match = sc_upd_inp.sc_pred_meta.sc_tage_pred_tkn
                          == sc_upd_inp.resolved_taken;

if(sc_upd_inp.sc_pred_meta.sc_chooser == CHOOSE_HIGH) {

    if(sc_pred_match)      choose_hi_vlo = sat_ch(choose_hi_vlo,+1);
    else if(tg_pred_match) choose_hi_vlo = sat_ch(choose_hi_vlo,-1);

} else if(sc_upd_inp.sc_pred_meta.sc_chooser == CHOOSE_MED) {

    if(sc_pred_match)      choose_med_vvlo = sat_ch(choose_med_vvlo, +1);
    else if(tg_pred_match) choose_med_vvlo = sat_ch(choose_med_vvlo, -1);

}
```

---
## 8. SC Helper Functions

Documenting the helper functions used above.

```
  signed [SC_TC_BITS-1:0] sat_tc(signed [SC_TC_BITS-1:0] curr_TC,int delta)
  {
    if(delta == 0) return curr_TC;
    if(curr_TC == LCL_TC_MIN & delta < 0) return curr_TC;
    if(curr_TC == LCL_TC_MAX & delta > 0) return curr_TC;

    return curr_TC + delta;
  }

  unsigned [SC_THRSH_BITS-1:0] sat_thr(unsigned [SC_THRSH_BITS-1:0] curr_THR,
                                       int delta)
  {
    if(delta == 0) return curr_THR;
    if(curr_THR == SC_THRSH_MIN & delta < 0) return curr_THR;
    if(curr_THR == SC_THRSH_MAX & delta > 0) return curr_THR;

    return curr_THR + delta;
  }

  signed [SC_MAX_CTR_WIDTH-1:0] sat_sc(signed [SC_MAX_CTR_WIDTH-1:0] curr_CTR,
                                       int delta)
  {
    if(delta == 0) return curr_CTR;
    if(curr_CTR == SC_CTR_MIN & delta < 0) return curr_CTR;
    if(curr_CTR == SC_CTR_MAX & delta > 0) return curr_CTR;
    return curr_CTR + delta;
  }

  signed [SC_CHOOSER_BITS-1:0] sat_ch(signed [SC_CHOOSER_BITS-1:0] curr_CH,
                                      int delta)
  {
    if(delta == 0) return curr_CH;

    if(curr_CH == SC_CHOOSER_MIN & delta < 0) return curr_CH;
    if(curr_CH == SC_CHOOSER_MAX & delta > 0) return curr_CH;
    return curr_CH + delta;
  }

```

## 9. BrIMLI Register and Semantics

### BrIMLI Update

`last_back_pc` is a register, cleared on reset, that holds PC[15:6] of the
last backward conditional branch seen by the SC.

`br_imli` is the backwards branch counter, cleared on reset
`bb_hist` is the backwards branch path register, cleared on reset

```
logic [9:0]  br_imli;
logic [10:0] last_back_pc; //bit [10] is the valid bit; 
logic [9:0]  bb_hist;

logic [9:0] branch_range = sc_upd_inp.sc_pred_meta.branch_range;
logic is_backwards       = sc_upd_inp.sc_pred_meta.backwards_branch;

// conditional branch is implied, sc only sees conditional branches
if (conditional branch)
{
    if (sc_upd_inp.resolved_taken)
    {
        if (is_backwards)  // backward branch
        {
            branch_range = sc_upd_inp.sc_pred_meta.pc[15:6]
            if (last_back_pc[10] && branch_range == last_back_pc[9:0] )
            {
              br_imli++; //this is a saturating add
            }
            else
            {
                bb_hist = (bb_hist << 1) ^ last_back_pc ^ branch_range;
                br_imli = 0;
            }
            last_back_pc = {1'b1,branch_range};
        }
    }
}
```

### BrIMLI index calculation

```
logic [9:0] get_br_imli_idx (input [9:0] pc,
                             input [9:0] phr,
                             input [9:0] br_imli,
                             input br_imli_mode_e mode = IDX_IMLI_PHR)
{
  logic [9:0] f_idx;

  case (mode)
    // Case 1 — your current behavior. IMLI when active, PHR when cold.
    IDX_IMLI_PHR:  f_idx = (br_imli == 0) ? phr : br_imli;

    // Case 2 — PHR-only baseline. Same table, IMLI never used.
    //          This is the control: whatever this scores is the
    //          "free" PHR contribution with no IMLI involved.
    IDX_PHR_ONLY:  f_idx = phr;

    // Case 3 — IMLI-only. No PHR substitution. When the counter is
    //          cold (0), f_idx contributes nothing and the index is a
    //          pure PC hash; only real IMLI streaks stir the index.
    IDX_IMLI_ONLY: f_idx = br_imli;

    default:       f_idx = (br_imli == 0) ? phr : br_imli;
  endcase

  return pc ^ f_idx ^ (pc >> 4);   // mask to table depth if < 1024 entries
}
```


<!-- 

This was the simple solution. I added the alternatives above. Pick
the mode that supplies the best performance during perf eval


logic [9:0] get_br_imli_idx (input [9:0] pc,
                             input [9:0] phr,
                             input [9:0] br_imli)
{
  logic [9:0] f_br_imli = br_imli == 0 ? phr : br_imli;

  logic [9:0] br_imli_idx_hash = pc ^ f_br_imli ^ (pc >> 4);
  return br_imli_idx_hash;
}
-->

## 4. Reset initialization

Entries in the SC tables do not require a valid bit.

The entries in the RAMs are initialized on the rising edge of the active low
reset.  On detection of this edge the `sram_init` module walks each entry in
the RAMs writing value S`C_SRAM_INIT_VALUE` to the entry. Note all RAMs are
accessed in parallel during this process. The `sram_init` module is
parameterized with the maximum number of entries across ST0-ST4 and the maximum
data width across each table.

This initialization process requires an control signal override scheme where,
when in ram initialization all table share the same address, input data and
write enable.  When the `sram_init` module completes the RAM initialzation is
asserts the SC primary output `sc_ready`.

The SC control logic of the SC can assume that it will see no transactions
(other than RAM init transactions) until `sc_ready` is asserted.

For simulation purposes there is a fast initialization mode that uses an
initial statement and for loop to directly initialize each RAM entry
in zero time. Fast initialization is triggered through a command line
parameter. Each predictor has it's own fast init CLI parameters. For the
SC this is `SC_FAST_INIT`. The fast init block is placed in `sc_table.sv`.

This shows common semantics:

```
  // Fast init: write bw_ram mem arrays at time zero via
  // hierarchical reference. Active only when +SC_FAST_INIT=1.
  // bw_ram mem is 2D: mem[BANKS][ENTRIES]. Loop covers both banks.
  initial begin
    int fast_init;
    fast_init = 0;
    void'($value$plusargs("SC_FAST_INIT=%d", fast_init));
    if (fast_init != 0) begin
      for (int b = 0; b < 2; b++) begin
        for (int i = 0; i < RAM_ENTRIES; i++) begin
          u_ram_s0.mem[b][i] =
            ALLOC_DATA_WIDTH'(SC_SRAM_INIT_VALUE);
          u_ram_s1.mem[b][i] =
            ALLOC_DATA_WIDTH'(SC_SRAM_INIT_VALUE);
        end
      end
    end
  end
```

`RAM_ENTRIES` is a table instance specific module parameter derived from
the number of index bits or number of entries in this table instance.

---

## Document History

  2026-06-26  Session-056. Initial draft. Manually created then refined.
  2026-06-28  Session-056. Completed draft, manually edited

