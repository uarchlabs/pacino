# ITTAGE Table Interface Specification
```
 FILE:    ittage_table_interfaces.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-05-16
 CONTACT: Jeff Nye
```

---
## Overview

ITTAGE is a indirect target tagged geometric history length 
branch predictor providing target prediction for indirect 
branches. It fires at p2 alongside FTB and overrides FTB 
target when ITTAGE has a matching entry. s2_redirect fires
on override.

There are two phases in a ITTAGE design, prediction request and update
request. The phase do not overlap.

ITTAGE supports dual prediction. Each table type contains two rams
one for each prediction request/update request. The dual nature is
also described as dual slots.

Each prediction slot operates independently. All signals indexed [s]
target RAMs exclusively. Slot 0 and slot 1 may perform any combination of read, write, or allocation simultaneously without interference.

ITTAGE is comprised only tagged components, also know as tables. There
are no untagged components in ITTAGE.

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

There is only one table type in ITTAGE, tagged.
There are five tables, IT1-IT5.

Tagged tables use module ittage_table,
the file is rtl/core/frontend/bpu/rtl/ittage_table.sv

The tagged tables are IT1-IT5, and entry in a tagged table include
a tag field of table specific width, a target address field (TGT) of 
parameterized width, an EPC field of parameterized width, 
a USE field of parameterized width, a CTR field of parameterized width 
and a 1b VALID bit. 

By default:
the EPC field is 2b
the USE field is 2b
the CTR field is 3b.
the TGT field is 38b.

The tables have an associated history
length of (4b, 8b, 13b, 16b, 32b) respectively.

## Bank Address Assignment

Each ittage_table instance contains two bw_ram
instances, one per prediction slot (RAM0 for slot 0, RAM1
for slot 1). Each bw_ram is instantiated with BANKS=2.

The bank_addr port of each bw_ram is derived from the MSB
of the index. The row address is the remaining lower bits.
For a THIS_INDEX_BITS-wide index:

  bank_addr = index[THIS_INDEX_BITS-1]
  row_addr  = index[THIS_INDEX_BITS-2:0]

This decomposition applies to prediction reads, normal
update writes, and the tbl_ri initialization path.


## Table Pipeline

The prediction phase uses pipestages p0, p1, p2. Table inputs are
presented on p0, SRAM read/compare/tag match occurs on p1. P2 is
not used by tables.

The update phase uses pipestages u0, u1. Table inputs are presented on
u0, SRAM write occurs in u1.

---
## Port Naming Convention

Port naming convention follows ittage_interfaces.md
§Port Naming Convention. The ports are not identical between
the two table types. They are listed below.

---

## Parameters Types and Structs

All types defined in bp_defines_pkg.sv and bp_structs_pkg.sv.
This document describes port semantics, timing contracts, and
consumer/producer obligations. It does not restate struct
field layouts -- see bp_structs_pkg.sv.

### Top Level Parameters
These parameters are defined in the br_defines_pkg.sv.  These parameters 
define the limits, they are not table specific.

```
NUM_PRED_SLOTS    : int
IT_MAX_IDX_WIDTH  : int
IT_MAX_TAG_WIDTH  : int
IT_MAX_TGT_WIDTH  : int
IT_MAX_EPC_WIDTH  : int
IT_MAX_USE_WIDTH  : int
IT_MAX_CTR_WIDTH  : int
IT_MAX_VAL_WIDTH  : int
```

Top level module parameters are vectored, the vector positions are
aligned with the assumption that tables will be instantiated in a generate
loop and the loop index will select the proper parameter for that table.

These are the table specific vectored parameters. These values are for
explanation the values to use during design are found in bp_defines_pkg.sv.

These parameters are shared across all tables. Note: position zero
is a placeholder for the non-existent IT0.

```
IT_TBL_BANKS[0:5]     : int  this parameter is not currently used
IT_TBL_ENTRIES[0:5]   : int  this describes the number of entries in each
                              bw_ram instance.
IT_TBL_FH[0:5]        : int  this is the width of the index folded history (fh)
IT_TBL_FH1[0:5]       : int  this is the width of the 1st tag folded history (fh1)
IT_TBL_FH2[0:5]       : int  this is the width of the 2nd tag folded history (fh2)
IT_TBL_HIST[0:5]      : int  this is the number of history bits 
IT_TBL_TAG[0:5]       : int  this is the width of the tag field 
IT_TBL_CTR[0:5]       : int  this is the width of the CTR field
IT_TBL_USE[0:5]       : int  this is the width of the USE field
IT_TBL_EPC[0:5]       : int  this is the width of the EPC field
IT_TBL_IDX[0:5]       : int  this is the width of the index bus for tables 
IT_TBL_TGT_WIDTH[0:5] : int  this is the width of the target bus 
```

## Derived Parameters

### IT1-IT5
```
THIS_CNTRL_BITS_WIDTH : int  THIS_EPC_WIDTH + THIS_USE_WIDTH
                             + THIS_CTR_WIDTH + THIS_TGT_WIDTH
                             + THIS_VAL_WIDTH

THIS_ALLOC_DATA_WIDTH : int  THIS_CNTRL_BITS_WIDTH + THIS_TAG_BITS
```

---

## Internal Module Parameters
Internally a table uses the THIS_ nomenclature to specialized the top level
module level parameters for use in the module. These are set by the
table specific assignments that occur above this level at module
instantiation.

### Common internal module parameters

```
THIS_TABLE         : int  this indicates which table IT0-IT5.
                          IT0 is a placeholder only and is never
                          instantiated. Valid range is IT1-IT5.
TBL_SEL_WIDTH      : int  this is the width of the table select bus,
                          typically tbl_sel or alc_sel buses.
THIS_VAL_WIDTH     : int  = 1 this is a static value, the parameter is
                          only used for documentation.
```

### Internal module parameters 

These are assigned during instantiation.

```
THIS_INDEX_BITS    : int  this is the local width of the index bus
THIS_TAG_BITS      : int  this is the local width of the TAG field
THIS_EPC_WIDTH     : int  this is the local width of the EPC field
THIS_USE_WIDTH     : int  this is the local width of the USE field
THIS_CTR_WIDTH     : int  this is the local width of the CTR field
THIS_TGT_WIDTH     : int  this is the local width of the TGT field
```

---

## Port Lists

There are two prediction slots, 0 and 1, these are referenced by
a vector index 0/1.  These are two independent prediction slots.


## IT1-IT5 Port List (ittage_table)

### Prediction Ports

```
output [NUM_PRED_SLOTS-1:0]           hit_p1
output [IT_MAX_TGT_WIDTH-1:0]         pred_tgt_p1[0:NUM_PRED_SLOTS-1]
output [THIS_CNTRL_BITS_WIDTH-1:0]    cntrl_bits_p1[0:NUM_PRED_SLOTS-1]

output logic [THIS_INDEX_BITS-1:0]    idx_hash_p0[0:NUM_PRED_SLOTS-1]
output logic [IT_MAX_TAG_WIDTH-1:0]   tag_hash_p0[0:NUM_PRED_SLOTS-1]

input  [NUM_PRED_SLOTS-1:0]           ittage_pred_val_p0
input  ittage_pred_inp_t              ittage_pred_inp_p0[0:NUM_PRED_SLOTS-1]
```

### Update Ports

```
input  [NUM_PRED_SLOTS-1:0]      ittage_upd_val_u0
input  [THIS_CTR_WIDTH-1:0]      prm_ctr_wd_u0[0:NUM_PRED_SLOTS-1]
input  [THIS_CTR_WIDTH-1:0]      alt_ctr_wd_u0[0:NUM_PRED_SLOTS-1]
input  [THIS_USE_WIDTH-1:0]      use_wd_u0[0:NUM_PRED_SLOTS-1]
input  [THIS_EPC_WIDTH-1:0]      epc_wd_u0[0:NUM_PRED_SLOTS-1]
input  [IT_MAX_TGT_WIDTH-1:0]    tgt_wd_u0[0:NUM_PRED_SLOTS-1]
input  [THIS_ALLOC_DATA_WIDTH-1:0] alc_wd_u0[0:NUM_PRED_SLOTS-1]
input  [NUM_PRED_SLOTS-1:0]      prm_ctr_wr_u0
input  [NUM_PRED_SLOTS-1:0]      alt_ctr_wr_u0
input  [NUM_PRED_SLOTS-1:0]      use_wr_u0
input  [NUM_PRED_SLOTS-1:0]      epc_wr_u0
input  [NUM_PRED_SLOTS-1:0]      tgt_wr_u0
input  [NUM_PRED_SLOTS-1:0]      alc_wr_u0
input  [TBL_SEL_WIDTH-1:0]       prm_tbl_sel_u0[0:NUM_PRED_SLOTS-1]
input  [TBL_SEL_WIDTH-1:0]       alt_tbl_sel_u0[0:NUM_PRED_SLOTS-1]
input  [THIS_INDEX_BITS-1:0]     upd_index_u0[0:NUM_PRED_SLOTS-1]
input  [TBL_SEL_WIDTH-1:0]       alc_tbl_sel_u0[0:NUM_PRED_SLOTS-1]
input  [THIS_INDEX_BITS-1:0]     alc_index_u0[0:NUM_PRED_SLOTS-1]
```

prm_ctr_wr_u0 and alt_ctr_wr_u0 are mutually exclusive. They are
never both asserted in the same cycle for the same slot. Both are
real write paths -- the distinction from TAGE is that TAGE may
assert both simultaneously; ITTAGE never does.

tgt_wr_u0 is asserted only on misprediction AND provider CTR was
null at predict time. It is gated by THIS_TABLE vs prm_tbl_sel_u0
or alt_tbl_sel_u0 depending on ittage_using_primary. See
ittage_interfaces.md §Target Write Gating for full gating
conditions and mutual exclusion with CTR writes.

### Misc Ports

```
input                              tbl_ri_active
input                              tbl_ri_wr
input  [THIS_INDEX_BITS-1:0]       tbl_ri_wa
input  [THIS_ALLOC_DATA_WIDTH-1:0] tbl_ri_wd
input  bp_folded_hist_t            folded_hist
input                              rstn
input                              clk
```
---

## Misc Interface

### Semantics:

The tbl_ri ports are not driven by ittage_cntrl. They are driven
by an SRAM initialization module instantiated in ittage.sv. The
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

### Port Semantics

ittage_pred_val_p0[s]   trigger that enables SRAM read for
                        slot s. Produced by ittage top level.

ittage_pred_inp_p0[s]   carries branch PC and branch_id for
                        slot s. PC used locally to derive
                        index_hash and tag_hash. Produced by
                        ittage top level.

folded_hist             bp_folded_hist_t output of bp_history,
                        shared across both prediction slots.
                        Each ittage_table selects the three
                        fields for its THIS_TABLE value
                        (it_tN_idx_fh, it_tN_tag_fh1,
                        it_tN_tag_fh2). Produced by bp_history.

hit_p1[s]               result of tag compare gated with valid
                        bit. One bit per slot.

pred_tgt_p1[s]          38-bit target address read from the
                        matching entry. Valid only when
                        hit_p1[s]=1.

cntrl_bits_p1[s]        control bit portion of entry used by
                        ittage_cntrl to form response metadata.

idx_hash_p0[s]          combinational index hash from pc and
                        folded_hist at p0. Used by ittage_cntrl
                        to populate ittage_prm_idx and
                        ittage_alc_idx in prediction meta.
                        The rules for idx_hash_p0 generation are
                        found in ittage_table_hash_rules.md

tag_hash_p0[s]          combinational tag hash from pc and
                        folded_hist at p0. Used by ittage_cntrl
                        to populate ittage_alc_tag in prediction
                        meta. The rules for tag_hash_p0 generation
                        are found in ittage_table_hash_rules.md

---

## Update Interface

### Port Semantics

ittage_upd_val_u0[s]   trigger that enables SRAM writes for
                       slot s. Produced by ittage top level.

prm_ctr_wd_u0[s]       CTR write data for the primary provider
                       entry. Produced by ittage_cntrl.

alt_ctr_wd_u0[s]       CTR write data for the alternate provider
                       entry. Produced by ittage_cntrl.

use_wd_u0[s]           USE field write data.
                       Produced by ittage_cntrl.

epc_wd_u0[s]           EPC field write data.
                       Produced by ittage_cntrl.

tgt_wd_u0[s]           38-bit target write data. Written only on
                       misprediction when provider CTR was null.
                       Produced by ittage_cntrl.

alc_wd_u0[s]           allocation write data. Writes all control
                       bits, tag, and target for a new entry.
                       Produced by ittage_cntrl.

prm_ctr_wr_u0[s]       write enable for primary provider CTR.
                       Gated by THIS_TABLE vs prm_tbl_sel_u0.
                       Mutually exclusive with alt_ctr_wr_u0.

alt_ctr_wr_u0[s]       write enable for alternate provider CTR.
                       Gated by THIS_TABLE vs alt_tbl_sel_u0.
                       Mutually exclusive with prm_ctr_wr_u0.

use_wr_u0[s]           write enable for USE field. Gated by
                       THIS_TABLE vs prm_tbl_sel_u0.

epc_wr_u0[s]           write enable for EPC field. Gated by
                       THIS_TABLE vs prm_tbl_sel_u0.

tgt_wr_u0[s]           write enable for target field. Asserted
                       only on misprediction when provider CTR
                       was null at predict time.

alc_wr_u0[s]           write enable for allocation. Gated by
                       THIS_TABLE vs alc_tbl_sel_u0.

prm_tbl_sel_u0[s]      primary provider table index. Used to
                       gate field write enables.
                       Produced by ittage_cntrl.

alt_tbl_sel_u0[s]      alternate provider table index. Used to
                       gate alt_ctr write enable.
                       Produced by ittage_cntrl.

upd_index_u0[s]        RAM address for update writes.
                       Produced by ittage_cntrl.

alc_tbl_sel_u0[s]      table index for allocation.
                       Produced by ittage_cntrl.

alc_index_u0[s]        RAM address for allocation write.
                       Produced by ittage_cntrl.

---

## Entry Format

### IT1-IT5 Table Entry

```
MSB                                            LSB
<tag>  TGT[37:0] EPC[1:0]  USE[1:0]  CTR[2:0]  VALID
```

Field widths for EPC, USE, CTR, TGT, and
VALID are uniform across IT1-IT5. The tag field varies.

```
VALID  : 1 bit
CTR    : 3 bits (confidence counter, not direction)
USE    : 2 bits
EPC    : 2 bits
TGT    : 38 bits (IT_TBL_TGT_WIDTH -- upper 38 bits of Sv39 VA.
                  Bit 0 always zero for instruction alignment
                  and is not stored.)
TAG    : 8 bits (IT1-IT2), 9 bits (IT3-IT4), 11 bits (IT5)
```

CTR encodes confidence in the stored target. CTR is incremented
on correct prediction and decremented on misprediction. When CTR
reaches null on misprediction, the target field is replaced with
the resolved target. CTR is not a direction predictor.

There is no IT0 entry format. ITTAGE has no base table.

