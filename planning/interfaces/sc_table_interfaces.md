<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# SC Table Interface Specification
```
 FILE:    sc_table_interfaces.md
 SOURCE:  various
 STATUS:  Draft -- session-058
 UPDATED: 2026-06-30
 CONTACT: Jeff Nye
```

---
## Overview

The SC prediction tables hold signed confidence counters. The
counters are read in parallel during prediction and summed in
sc_cntrl. During update the consulted counter in each table is
stepped toward the resolved direction. There is no allocation and
no tag compare.

There are two phases, prediction request and update request. The
phases do not overlap (sc_decisions.md section 4).

SC supports dual prediction. Each table module contains two bw_ram
instances, one per prediction slot (RAM0 for slot 0, RAM1 for slot
1). Each prediction slot operates independently. All signals indexed
[s] target the per-slot RAM exclusively.

---
## Table description

There are SC_NUM_TABLES tables. The current version has 5 tables,
ST0-ST4.

There are two table module types.

sc_table implements ST0-ST3. The file is
frontend/branch_predictor/rtl/sc_table.sv.
sc_brimli implements ST4. The file is
frontend/branch_predictor/rtl/sc_brimli.sv.

sc_brimli is a separate module to simplify specialization and
instantiation in sc.sv. The two modules may be combined in a future
revision.

An SC table entry is a single signed confidence counter of width
SC_TBL_CTR (6b). SC entries have no tag, no USE field, no EPC field,
and no valid bit (SC_TBL_TAG, SC_TBL_USE, SC_TBL_EPC all 0, and
SC_MAX_VAL_WIDTH=0 in bp_defines_pkg.sv).

The definitive specification of the field widths is in
bp_defines_pkg.sv.

Index difference between the two module types:

sc_table (ST0-ST3) derives its index from the PC and a folded
history. ST0 uses SC_TBL_FH[0]=0 and takes a PC slice without a
fold. ST1-ST3 hash the PC with the per-table fold.

sc_brimli (ST4) derives its index from the BrIMLI index function
get_br_imli_idx over PC[15:6], sc_phr_p2, and br_imli.

---
## Bank Address Assignment

Each sc_table and sc_brimli instance contains two bw_ram instances,
one per prediction slot. Each bw_ram is instantiated with BANKS=2.

The bank_addr port of each bw_ram is derived from the MSB of the
index. The row address is the remaining lower bits. For a
THIS_INDEX_BITS-wide index:

  bank_addr = index[THIS_INDEX_BITS-1]
  row_addr  = index[THIS_INDEX_BITS-2:0]

This decomposition applies to prediction reads, update writes, and
the tbl_ri initialization path. It is identical for sc_table and
sc_brimli.

sc_table (ST0-ST3): SC_TBL_IDX=9, SC_TBL_ENTRIES=512.
  bank_addr = index[8], row_addr = index[7:0]. 256 rows/bank.

sc_brimli (ST4): SC_TBL_IDX[4]=10, SC_TBL_ENTRIES[4]=1024.
  bank_addr = index[9], row_addr = index[8:0]. 512 rows/bank.

---
## Table Pipeline

The prediction phase uses pipestages p2, p3. Table index inputs are
presented at p2. The bw_ram read latency is one cycle; ctr_p3 is the
flopped read output, available at p3. p3 is the SC result-formation
stage in sc_cntrl.

The update phase uses pipestages u0, u1. Table inputs are presented
at u0. SRAM write occurs at u1.

---
## Port Naming Convention

Signal names follow the pattern:
`<signal>_<pipestage>`

- `pipestage` : p2 for the index inputs, p3 for the counter output.
                u0, u1 for the update path. px for flush-related
                signals (not yet defined).

Slot dimension uses vector index [0:NUM_PRED_SLOTS-1].
clk and rstn carry no pipe stage suffix.

The ports are not identical between the two table types. They are
listed below.

---
## Parameters Types and Structs

All types defined in bp_defines_pkg.sv and bp_structs_pkg.sv. This
document describes port semantics, timing contracts, and
consumer/producer obligations. It does not restate struct field
layouts -- see bp_structs_pkg.sv. It does not restate parameter
values -- see bp_defines_pkg.sv.

### Top Level Parameters

These parameters are defined in bp_defines_pkg.sv. They define the
limits; they are not table specific.

```
NUM_PRED_SLOTS   : int
SC_MAX_IDX_WIDTH : int
SC_MAX_CTR_WIDTH : int
SC_MAX_FH        : int
```

Top level module parameters are vectored. The vector positions are
aligned with the assumption that tables are instantiated in a
generate loop and the loop index selects the parameter for that
table.

Table specific vectored parameters (values in bp_defines_pkg.sv):

```
SC_TBL_BANKS[0:4]   : int  not currently used.
SC_TBL_ENTRIES[0:4] : int  entries per bw_ram instance.
SC_TBL_FH[0:4]      : int  index fold width. ST0=0 (no fold).
                           ST4 unused (BrIMLI index).
SC_TBL_HIST[0:4]    : int  history bit count. Duplicate of SC_TBL_FH.
SC_TBL_TAG[0:4]     : int  tag width. 0 for all SC tables.
SC_TBL_CTR[0:4]     : int  counter width.
SC_TBL_USE[0:4]     : int  USE width. 0 for all SC tables.
SC_TBL_EPC[0:4]     : int  EPC width. 0 for all SC tables.
SC_TBL_IDX[0:4]     : int  index bus width.
```

## Derived Parameters

```
CNTRL_BITS_WIDTH = SC_TBL_CTR (6b). The SC entry is the counter only.
ALLOC_DATA_WIDTH = CNTRL_BITS_WIDTH. No tag, no separate alloc field.
```

---
## Internal Module Parameters

Internally a table uses the THIS_ nomenclature to specialize the top
level parameters for use in the module. These are set at
instantiation.

```
THIS_TABLE       : int  which table, ST0-ST4.
THIS_INDEX_BITS  : int  local width of the index bus.
THIS_CTR_WIDTH   : int  local width of the CTR field.
THIS_ENTRIES     : int  local bw_ram entry count.
THIS_FH          : int  local index fold width (sc_table only).
```

---
## Port Lists

There are two prediction slots, 0 and 1, referenced by vector index
[0:NUM_PRED_SLOTS-1]. The two slots are independent.

### sc_table Port List (ST0-ST3)

#### sc_table prediction ports

```
output logic [THIS_CTR_WIDTH-1:0]
  ctr_p3[0:NUM_PRED_SLOTS-1]
output logic [THIS_INDEX_BITS-1:0]
  idx_hash_p2[0:NUM_PRED_SLOTS-1]

input  logic [NUM_PRED_SLOTS-1:0]   sc_pred_val_p2
input  logic [VA_WIDTH-1:1]         inp_pc_p2[0:NUM_PRED_SLOTS-1]
input  logic [SC_MAX_FH-1:0]        idx_fh_p2
```

#### sc_table update ports

```
input  logic [NUM_PRED_SLOTS-1:0]   sc_upd_val_u0
input  logic [THIS_CTR_WIDTH-1:0]   ctr_wd_u0[0:NUM_PRED_SLOTS-1]
input  logic [NUM_PRED_SLOTS-1:0]   ctr_wr_u0
input  logic [THIS_INDEX_BITS-1:0]  upd_index_u0[0:NUM_PRED_SLOTS-1]
```

#### sc_table misc ports

```
input  logic                          tbl_ri_active
input  logic                          tbl_ri_wr
input  logic [THIS_INDEX_BITS-1:0]    tbl_ri_wa
input  logic [ALLOC_DATA_WIDTH-1:0]   tbl_ri_wd
input  logic                          rstn
input  logic                          clk
```

### sc_brimli Port List (ST4)

#### sc_brimli prediction ports

```
output logic [THIS_CTR_WIDTH-1:0]
  ctr_p3[0:NUM_PRED_SLOTS-1]
output logic [THIS_INDEX_BITS-1:0]
  idx_hash_p2[0:NUM_PRED_SLOTS-1]

input  logic [NUM_PRED_SLOTS-1:0]   sc_pred_val_p2
input  logic [VA_WIDTH-1:1]         inp_pc_p2[0:NUM_PRED_SLOTS-1]
input  logic [9:0]                  sc_phr_p2
input  logic [9:0]                  br_imli
input  br_imli_mode_e               br_imli_mode
```

#### sc_brimli update ports

```
input  logic [NUM_PRED_SLOTS-1:0]   sc_upd_val_u0
input  logic [THIS_CTR_WIDTH-1:0]   ctr_wd_u0[0:NUM_PRED_SLOTS-1]
input  logic [NUM_PRED_SLOTS-1:0]   ctr_wr_u0
input  logic [THIS_INDEX_BITS-1:0]  upd_index_u0[0:NUM_PRED_SLOTS-1]
```

#### sc_brimli misc ports

```
input  logic                          tbl_ri_active
input  logic                          tbl_ri_wr
input  logic [THIS_INDEX_BITS-1:0]    tbl_ri_wa
input  logic [ALLOC_DATA_WIDTH-1:0]   tbl_ri_wd
input  logic                          rstn
input  logic                          clk
```

---
## Misc Interface

### Semantics

The tbl_ri ports are not driven by sc_cntrl. They are driven by an
SRAM initialization module instantiated in sc.sv. The init module is
components/rtl/sram_init.sv. The scheme is identical to tage
(tage_table_interfaces.md Misc Interface).

```
tbl_ri_active  ram initialization is active.
tbl_ri_wr      ram write signal. Converted to an active-low bit
               write and a global select. When tbl_ri_active is
               asserted, tbl_ri_wr overrides all other write
               signals. No case exists where tbl_ri_wr and the
               other write signals are asserted together.
tbl_ri_wa      ram address. When tbl_ri_active is asserted,
               overrides all other ram address signals. Sized to
               THIS_INDEX_BITS.
tbl_ri_wd      ram write data. When tbl_ri_active is asserted,
               overrides all other ram data inputs. Init value is
               SC_SRAM_INIT_VALUE (sc_decisions.md section 13).
```

---
## Prediction Interface

### sc_table Semantics (ST0-ST3)

```
sc_pred_val_p2[s]  enables the bw_ram read for slot s. Produced by
                   sc top level.
inp_pc_p2[s]       staged branch PC for slot s. Used locally to
                   derive the index hash via sc_idx_hash
                   (sc_table_hash_rules.md). Produced by the BP
                   cluster staging path (sc_interfaces.md).
idx_fh_p2          the per-table index fold, staged to p2. For ST0
                   this port is tied to constant zero at the ST0
                   instance in sc.sv (SC_TBL_FH[0]=0, PC slice only);
                   port presence cannot be parameterized away in
                   SystemVerilog. For ST1-ST3 this is
                   sc_t1_idx_fh_p2 / sc_t2_idx_fh_p2 /
                   sc_t3_idx_fh_p2 selected at instantiation.
                   Produced by the BP cluster staging path.
ctr_p3[s]          the signed counter read from the entry. Raw
                   SC_TBL_CTR-wide value. sc_cntrl performs the
                   signed read and sum (sc_decisions.md section 9).
idx_hash_p2[s]     the index computed at p2 from inp_pc_p2 and
                   idx_fh_p2. One value per slot. Consumed by
                   sc_cntrl to populate sc_upd_idx in the prediction
                   meta. Rules in sc_table_hash_rules.md.
```

### sc_brimli Semantics (ST4)

```
sc_pred_val_p2[s]  enables the bw_ram read for slot s. Produced by
                   sc top level.
inp_pc_p2[s]       staged branch PC for slot s. sc_brimli uses
                   inp_pc_p2[s][15:6] as the get_br_imli_idx PC
                   input (sc_decisions.md section 12). Produced by
                   the BP cluster staging path.
sc_phr_p2          low 10 bits of the path history, staged to p2.
                   get_br_imli_idx PHR input. Produced by the BP
                   cluster staging path.
br_imli            the BrIMLI counter. Held in sc_cntrl
                   (sc_decisions.md sections 8, 12), presented to
                   sc_brimli as an input. get_br_imli_idx IMLI
                   input.
br_imli_mode       BrIMLI index mode selector (br_imli_mode_e).
                   Selects IMLI/PHR/IMLI-only index behavior for
                   perf evaluation (sc_decisions.md section 12).
ctr_p3[s]          the signed counter read from the entry. Raw
                   SC_TBL_CTR-wide value.
idx_hash_p2[s]     the index computed at p2 via get_br_imli_idx.
                   One value per slot. Consumed by sc_cntrl to
                   populate sc_upd_idx[4] in the prediction meta.
                   Rules in sc_table_hash_rules.md.
```

The two module types have disjoint prediction-index input sets.
sc_table takes idx_fh_p2 and does not take sc_phr_p2, br_imli, or
br_imli_mode. sc_brimli takes sc_phr_p2, br_imli, and br_imli_mode
and does not take a fold.

---
## Update Interface

### sc_table and sc_brimli Semantics

```
sc_upd_val_u0[s]  enables the bw_ram write for slot s. Produced by
                  sc top level.
ctr_wd_u0[s]      the counter write data. The saturated stepped
                  counter (sat_sc result, sc_decisions.md section
                  10). Produced by sc_cntrl.
ctr_wr_u0[s]      the write enable for the counter. Gated by
                  THIS_TABLE membership in the update. Produced by
                  sc_cntrl.
upd_index_u0[s]   the entry index for the write. Sourced from
                  sc_pred_meta.sc_upd_idx captured at predict time,
                  carried through sc_upd_inp. No re-hash on the
                  update path (sc_pred_meta_t comment,
                  sc_decisions.md section 10). Produced by sc_cntrl.
```

The index hash is prediction-path only. The update path takes the
precomputed index on upd_index_u0.

---
## Read-during-write contract

Prediction and update paths are mutually exclusive by design.
Prediction is bw_ram read only. Update is bw_ram write only. No
read-modify-write is required (sc_decisions.md section 4). The
prediction-phase counter snapshot captured in sc_pred_meta supplies
the write data base for the update; the update does not read the
table.

bw_ram read-write conflict is undefined (bw_ram.sv). The mutually-
exclusive phase design guarantees no concurrent read and write to
the same instance.

---
## Entry Formats

The SC table entry is a single signed counter of width SC_TBL_CTR.
There is no separate entry-format document (sc_decisions.md section
7 file-set decision: sc_table_entry_formats.md dropped).

---
## Known Gaps and Deferred Items

| ID       | Item                                    | Status         |
|----------|-----------------------------------------|----------------|
| IC-SCT-01| sc_idx_hash not yet defined. Referenced | TBD.           |
|          | by sc_table idx_hash_p2. Definition in  | sc_table_      |
|          | sc_table_hash_rules.md.                  | hash_rules.md  |
| IC-SCT-02| get_br_imli_idx not yet defined.        | TBD.           |
|          | Referenced by sc_brimli idx_hash_p2.    | sc_table_      |
|          | Definition in sc_table_hash_rules.md.    | hash_rules.md  |
| IC-SCT-03| Flush port definitions (_px signals)    | TBD. TD #96.   |
|          | not yet defined.                        |                |

