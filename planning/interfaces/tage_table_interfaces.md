<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# TAGE Table Interface Specification
```
 FILE:    tage_table_interfaces.md
 SOURCE:  various
 STATUS:  COMPLETE
 UPDATED: 2026-06-10
 CONTACT: Jeff Nye
```
 
---
## Overview

TAGE is a tagged geometric history length branch predictor
providing direction prediction for conditional branches. It
fires at p2 alongside FTB and overrides FTB direction when
TAGE disagrees. s2_redirect fires on override.

There are two phases in a TAGE design, prediction request and update
request. The phase do not overlap.

TAGE supports dual prediction. Each table type contains two rams
one for each prediction request/update request. The dual nature is
also described as dual slots.

Each prediction slot operates independently. All signals indexed [s] 
target RAMs exclusively. Slot 0 and slot 1 may perform any combination of read, write, or allocation simultaneously without interference.

TAGE is comprised of tagged and untagged components, also know as tables.

Upto 2 components can be updated in a single update cycle, in
the literature these are called the primary and alternative
components. This means there can be 4 total writes during an update. 
This is true only for the ctr field. Only the ctr field can 
be updated in two components. 

---
## Table description

There are a parameterized number of tables. Current working
version has 5 tables.

Tables are also known as components (unrelated to this projects library
of components). The term components is often used in the literature.

There are two table types, tagged and untagged.

There are four tagged tables, T1-T4.
There is one untagged table, T0.

There are separate verilog modules for the table types.

Tagged tages use tage_table,
  the file is frontend/branch_predictor/rtl/tage_table.sv
Untagged tages use tage_bim,
  the file is frontend/branch_predictor/rtl/tage_bim.sv

The untagged table, T0, is known as the base table. This is also known 
as the bimodal table or bim. An entry in T0 is a 2b CTR. T0 has two internal
banks using the bit write SRAM module, common/rtl/bw_ram.sv

The tagged tables are T1-T4, and entry in a tagged table include 
a tag field of table specific width, an EPC field of parameterized
width, a USE field of parameterized width, a CTR field of parameterized
width and a 1b VALID bit. By default the EPC field is 2b, the USE field is
2b, the CTR field is 3b. The tagged tables have an associated history 
length of (8b, 13b, 32b, 119b) respectively.

The definitive specification of the field widths is found in
`bp_defines_pkg.sv`


## Bank Address Assignment

Each tage_table and tage_bim instance contains two bw_ram
instances, one per prediction slot (RAM0 for slot 0, RAM1
for slot 1). Each bw_ram is instantiated with BANKS=2.

The bank_addr port of each bw_ram is derived from the MSB
of the index. The row address is the remaining lower bits.
For a THIS_INDEX_BITS-wide index:

  bank_addr = index[THIS_INDEX_BITS-1]
  row_addr  = index[THIS_INDEX_BITS-2:0]

This decomposition applies to prediction reads, normal
update writes, and the tbl_ri initialization path. It is
identical for tage_bim and tage_table.

## Table Pipeline

The prediction phase uses pipestages p0, p1, p2. Table inputs are
presented on p0, SRAM read/compare/tag match occurs on p1. P2 is
not used by tables.

The update phase uses pipestages u0, u1. Table inputs are presented on
u0, SRAM write occurs in u1.

---
## Port Naming Convention

Signal names follow the pattern:
`<signal>_<pipestage>`

- `pipestage` : p0, p1, p2 for prediction path.
                u0, u1 for update path.
                px for flush-related signals (not yet defined).

Slot dimension uses vector index [0:NUM_PRED_SLOTS-1].
clk and rstn carry no pipe stage suffix.

The ports are not identical between the two table types. They are
listed below.

---

## Parameters Types and Structs

All types defined in bp_defines_pkg.sv and bp_structs_pkg.sv.
This document describes port semantics, timing contracts, and
consumer/producer obligations. It does not restate struct
field layouts -- see bp_structs_pkg.sv.

### Top Level Parameters
These parameters are defined in the br_defines_pkg.sv.
These parameters define the limits, they are not table specific.


NUM_PRED_SLOTS   : int
MAX_IDX_WIDTH    : int
MAX_TAG_WIDTH    : int
MAX_EPC_WIDTH    : int
MAX_USE_WIDTH    : int
MAX_CTR_WIDTH    : int
MAX_VAL_WIDTH    : int

Top level module parameters are vectored, the vector positions are 
aligned with the assumption that tables will be instantiated in a generate
loop and the loop index will select the proper parameter for that table.

These are the table specific vectored parameters. These values are for
explanation the values to use during design are found in bp_defines_pkg.sv.

TAGE_TBL_BANKS[0:4]   : int  this parameter is not currently used
TAGE_TBL_ENTRIES[0:4] : int  this describes the number of entries in ech
                             bw_ram instance.
TAGE_TBL_FH[0:4]   : int  this is the width of the index folded history (fh)
                          for tables T1-T4, this is not used by T0.
TAGE_TBL_FH1[0:4]  : int  this is the width of the 1st tag folded history (fh1)
                          for tables T1-T4, this is not used by T0.
TAGE_TBL_FH2[0:4]  : int  this is the width of the 2nd tag folded history (fh2)
                          for tables T1-T4, this is not used by T0.
TAGE_TBL_HIST[0:4] : int  this is the number of history bits for tables T1-T4
                          this is not used by T0.
TAGE_TBL_TAG[0:4]  : int  this is the width of the tag in tables T1-T4
                          this is not used by T0.
TAGE_TBL_CTR[0:4]  : int  this is the width of the CTR field in tables T0-T4
TAGE_TBL_USE[0:4]  : int  this is the width of the USE field in tables T1-T4
                          this is not used by T0.
TAGE_TBL_EPC[0:4]  : int  this is the width of the EPC field in tables T1-T4
                          this is not used by T0.
TAGE_TBL_IDX[0:4]  : int  this is the width of the index bus for tables T0-T4

## Derived Parameters

### T1-TN
CNTRL_BITS_WIDTH = MAX_EPC_WIDTH+MAX_USE_WIDTH+MAX_CTR_WIDTH+MAX_VAL_WIDTH;
                   the width of the control bits in tables T1-T4.
ALLOC_DATA_WIDTH = CNTRL_BITS_WIDTH+THIS_TAG_BITS

### T0

CNTRL_BITS_WIDTH = 2     the width of the control bits in tables T0.
ALLOC_DATA_WIDTH = CNTRL_BITS_WIDTH


---

## Internal Module Parameters
Internally a table uses the THIS_ nomenclature to specialized the top level
module level parameters for use in the module. These are set by the 
table specific assignments that occur above this level at module 
instantiation.

### Common internal module parameters

```
THIS_TABLE         : int this indicates which table T0-T4
TBL_SEL_WIDTH      : int this is the width of the table select bus, typically
                         tbl_sel or alc_set buses
THIS_VAL_WIDTH     : int = 1 this is a static value, the parameter is only
                         used for documentation
```

### Internal module parameters 

These are assigned during instantiation.

```
THIS_INDEX_BITS    : int this is the local width of the index bus

THIS_TAG_BITS      : int this is the local width of the TAG field
                         this is not used by T0
THIS_EPC_WIDTH     : int this is the local width of the EPC field
                         this is not used by T0
THIS_USE_WIDTH     : int this is the local width of the USE field
                         this is not used by T0
THIS_CTR_WIDTH     : int this is the local width of the CTR field
```

---

## Port Lists

There are two prediction slots, 0 and 1, these are referenced by
a vector index 0/1.  These are two independent prediction slots.


### T0 Port List, tage_bim

#### T0 prediction ports

```
output [NUM_PRED_SLOTS-1:0]  taken_p1  // this is bit [1] of the entry.
output [THIS_CTR_WIDTH-1:0]  cntrl_bits_p1[0:NUM_PRED_SLOTS-1]

input  [NUM_PRED_SLOTS-1:0]  tage_pred_val_p0
input  tage_pred_inp_t       tage_pred_inp_p0[0:NUM_PRED_SLOTS-1]
```

#### T0 update ports

```
input [NUM_PRED_SLOTS-1:0]     tage_upd_val_u0
input [THIS_CTR_WIDTH-1:0]     prm_ctr_wd_u0[0:NUM_PRED_SLOTS-1]
input [NUM_PRED_SLOTS-1:0]     prm_ctr_wr_u0
input [TBL_SEL_WIDTH-1:0]      prm_tbl_sel_u0[0:NUM_PRED_SLOTS-1]
input [THIS_INDEX_BITS-1:0]    upd_index_u0[0:NUM_PRED_SLOTS-1]
```

#### T0 misc ports

```
input                          tbl_ri_active
input                          tbl_ri_wr
input [THIS_INDEX_BITS-1:0]    tbl_ri_wa
input [ALLOC_DATA_WIDTH-1:0]   tbl_ri_wd
input rstn
input clk
```


### T1-TN Port List, tage_table

#### T1-TN prediction ports

```
output [NUM_PRED_SLOTS-1:0]    hit_p1
output [NUM_PRED_SLOTS-1:0]    taken_p1

output [CNTRL_BITS_WIDTH-1:0]  cntrl_bits_p1[0:NUM_PRED_SLOTS-1]

output logic [THIS_INDEX_BITS-1:0]
  idx_hash_p0[0:NUM_PRED_SLOTS-1]
output logic [MAX_TAG_WIDTH-1:0]
  tag_hash_p0[0:NUM_PRED_SLOTS-1]

input [NUM_PRED_SLOTS-1:0]     tage_pred_val_p0
input tage_pred_inp_t          tage_pred_inp_p0[0:NUM_PRED_SLOTS-1]
```

#### T1-TN update ports

```
input [NUM_PRED_SLOTS-1:0]     tage_upd_val_u0
input [THIS_CTR_WIDTH-1:0]     prm_ctr_wd_u0[0:NUM_PRED_SLOTS-1]
input [THIS_CTR_WIDTH-1:0]     alt_ctr_wd_u0[0:NUM_PRED_SLOTS-1]
input [THIS_USE_WIDTH-1:0]     use_wd_u0[0:NUM_PRED_SLOTS-1]
input [THIS_EPC_WIDTH-1:0]     epc_wd_u0[0:NUM_PRED_SLOTS-1]
input [ALLOC_DATA_WIDTH-1:0]   alc_wd_u0[0:NUM_PRED_SLOTS-1]
input [NUM_PRED_SLOTS-1:0]     prm_ctr_wr_u0
input [NUM_PRED_SLOTS-1:0]     alt_ctr_wr_u0
input [NUM_PRED_SLOTS-1:0]     use_wr_u0
input [NUM_PRED_SLOTS-1:0]     epc_wr_u0
input [NUM_PRED_SLOTS-1:0]     alc_wr_u0
input [TBL_SEL_WIDTH-1:0]      prm_tbl_sel_u0[0:NUM_PRED_SLOTS-1]
input [TBL_SEL_WIDTH-1:0]      alt_tbl_sel_u0[0:NUM_PRED_SLOTS-1]
input [THIS_INDEX_BITS-1:0]    upd_index_u0[0:NUM_PRED_SLOTS-1]

input [TBL_SEL_WIDTH-1:0]      alc_tbl_sel_u0[0:NUM_PRED_SLOTS-1]
input [THIS_INDEX_BITS-1:0]    alc_index_u0[0:NUM_PRED_SLOTS-1]
```


#### T1-TN misc ports

```
input                          tbl_ri_active
input                          tbl_ri_wr
input [THIS_INDEX_BITS-1:0]    tbl_ri_wa
input [ALLOC_DATA_WIDTH-1:0]   tbl_ri_wd
input bp_folded_hist_t         folded_hist

input rstn
input clk
```


## Misc Interface

### Semantics:

The tbl_ri ports are not driven by tage_cntrl. They are driven
by an SRAM initialization module instantiated in tage.sv. The 
init module is found components/rtl/sram_init.sv


tbl_ri_active  ram initialization is active

tbl_ri_wr      ram write signal, this needs to be converted to an active low
               bit write and a global select. When tbl_ri_active is 
               asserted, tbl_ri_wr overrides all other write signals. But there
               is no case where tbl_ri_wr and the other write signals are
               asserted. 

tbl_ri_wa      ram address signal. When tbl_ri_active is asserted, tbl_ri_wa
               overrides all other ram address signals. Sized to 
               THIS_INDEX_BITS.

tbl_ri_wd      ram write data signal When tbl_ri_active is asserted, tbl_ri_wd
               overrides all other ram data input signals.

---
## Prediction Interface

### T0 Semantics:

There are two effective copies of these signals for each prediction slot.

The unused signals are not documented here.

taken_p1            this is the MSB of the T0 entry

cntrl_bits_p1       this is a THIS_CTR_WIDTH (default 2b) wide bus that 
                    is the contents of the T0 entry.

tage_pred_val_p0    is the trigger that enable SRAM read
                    produced by tage top top level for prediction slot 0/1

index_hash_p0       is the PC-derived index which accesses the SRAM for
                    prediction slot 0/1. This signal is taken from 
                    tage_pred_inp_0/1_p0.pc[12:2].  This signal is not 
                    hashed it is directly taken from the PC input.
                    This is not routed through tage_hash

### T1-TN Semantics:

tage_pred_val_p0[s]  is the trigger that enables the SRAM read.
                     Produced by tage top level.

tage_pred_inp_p0[s]  carries the branch PC and branch_id for
                     prediction slot s. The pc field is used
                     locally within tage_table to derive the
                     index hash and tag hash via the functions
                     defined in tage_table_hash_rules.md.
                     Produced by tage top level.

folded_hist          the bp_folded_hist_t output of bp_history,
                     shared across both prediction slots. Each
                     tage_table instance selects the three fields
                     corresponding to its THIS_TABLE value
                     (tage_tN_idx_fh, tage_tN_tag_fh1,
                     tage_tN_tag_fh2) and uses them locally to
                     compute the index and tag hashes. index_hash
                     and tag_hash are no longer sourced externally.
                     Produced by bp_history.

hit_p1[s]     is the result of a tag compare. Gated with valid.

taken_p1[s]   is the MSB of the entry CTR field. Can be asserted
              without hit; ignored when hit is 0.

cntrl_bits_p1[s]  is the control bit portion of the entry, used by
                  tage_cntrl to form the response data.

idx_hash_p0[s]    combinational index hash computed from pc and
                  folded_hist at p0. One value per prediction slot.
                  Used by tage_cntrl to populate tage_prm_idx,
                  tage_alt_idx, and tage_alc_idx in prediction meta.
                  The rules for idx_hash_p0 generation are found
                  in tage_table_hash_rules.md

tag_hash_p0[s]    combinational tag hash computed from pc and
                  folded_hist at p0. One value per prediction slot.
                  Used by tage_cntrl to populate tage_alc_tag in
                  prediction meta.
                  The rules for idx_hash_p0 generation are found
                  in tage_table_hash_rules.md
---

## Update Interface

### T0 Semantics:

tage_upd_val_u0 is the trigger that enables SRAM writes
                this is produced by tage top level

prm_ctr_wd_u0   this is the ctr field write data for T0
                this is produced by tage_cntrl.

prm_ctr_wr_u0   this is the write signal for the T0 entry. This is
                gated by THIS_TABLE compared to prm_tbl_sel_u0.
                this is produced by tage_cntrl.

prm_tbl_sel_u0  this is the component index used to select a TAGE table
                this is produced by tage_cntrl.

upd_index_u0    this is used to access the ram entry
                this is produced by tage_cntrl.

### T1-TN Semantics:

tage_upd_val_u0[s]  is the trigger that enables SRAM writes
                    this is produced by tage top level

prm_ctr_wd_u0[s]   this is the ctr field write data for the
                primary component. See above about multiple ctr writes.
                this is produced by tage_cntrl.

alt_ctr_wd_u0[s]   this is the ctr field write data for the
                alternative component. See above about multiple ctr writes.
                this is produced by tage_cntrl.

use_wd_u0[s]       this is the use field write data.
                this is produced by tage_cntrl.

epc_wd_u0[s]       this is the epc field write data.
                this is produced by tage_cntrl.

alc_wd_u0[s]       this is the allocation field write data. This field
                writes all control and tag bits.
                this is produced by tage_cntrl.

prm_ctr_wr_u0[s]   this is the write signal for the primary ctr. This is
                gated by THIS_TABLE compared to prm_tbl_sel_u0.
                this is produced by tage_cntrl.

alt_ctr_wr_u0[s]   this is the write signal for the alternative ctr. This is
                gated by THIS_TABLE compared to alt_tbl_sel_u0.
                this is produced by tage_cntrl.

use_wr_u0[s]       this is the write signal for the use field. This is
                gated by THIS_TABLE compared to prm_tbl_sel_u0.
                this is produced by tage_cntrl.

epc_wr_u0[s]       this is the write signal for the epc field. This is
                gated by THIS_TABLE compared to prm_tbl_sel_u0.
                this is produced by tage_cntrl.

alc_wr_u0[s]       this is the write signal for an entry allocation. This is
                gated by THIS_TABLE compared to alc_tbl_sel_u0.
                this is produced by tage_cntrl.

prm_tbl_sel_u0[s]  this is the primary component index used to select 
                   a TAGE table this is produced by tage_cntrl.

alt_tbl_sel_u0[s]  this is the alternative component index used to 
                   select a TAGE table this is produced by tage_cntrl.

upd_index_u0[s]    this is used to access the ram entry
                   this is produced by tage_cntrl.

alc_tbl_sel_u0[s]  this is the component index used to select a TAGE table
                   for allocation this is produced by tage_cntrl.

alc_index_u0[s] this is allocation index used to access the ram entry for 
                allocation this is produced by tage_cntrl 
---

## Entry Formats

The table entry formats for TAGE are found in
`planning/arch/tage_table_entry_formats.md`


