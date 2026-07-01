<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# SC Table Hash Rules
```
 FILE:    sc_table_hash_rules.md
 SOURCE:  various
 STATUS:  Draft -- session-058
 UPDATED: 2026-06-30
 CONTACT: Jeff Nye
```

---
## Overview

This document defines the index hashing for the SC tables. There
are two functions. sc_idx_hash indexes ST0-ST3 (sc_table).
get_br_imli_idx indexes ST4 (sc_brimli).

SC tables have no tags. There is no tag hash.

The functions are prediction-path only. The update path uses the
index captured at predict time in sc_pred_meta.sc_upd_idx, carried
through sc_upd_inp, presented on upd_index_u0. No re-hash occurs on
the update path (sc_decisions.md section 10).

All widths are in bp_defines_pkg.sv. That file is authoritative.

---
## Parameter references

```
INST_OFFSET      = 2         (bp_defines_pkg.sv)
VA_WIDTH         = 40        (bp_defines_pkg.sv)
SC_TBL_IDX[0:4]  = {9,9,9,9,10}  (bp_defines_pkg.sv)
SC_MAX_IDX_WIDTH = 10        (bp_defines_pkg.sv)
SC_MAX_FH        = 64        (bp_defines_pkg.sv)
```

THIS_INDEX_BITS is the per-table index width, set at instantiation
from SC_TBL_IDX[THIS_TABLE]. For ST0-ST3 it is 9. For ST4 it is 10.

THIS_TABLE is the per-table identifier, 0-4, set at instantiation.

---
## sc_idx_hash (ST0-ST3, sc_table)

### Inputs

```
inp_pc_p2[s]      staged branch PC, [VA_WIDTH-1:1] (sc_interfaces.md).
fh_idx_ext        the per-table index fold, [SC_MAX_FH-1:0], selected
                  by THIS_TABLE.
```

fh_idx_ext selection by THIS_TABLE:

```
case (THIS_TABLE)
  0: fh_idx_ext = 0;
  1: fh_idx_ext = sc_t1_idx_fh_p2;
  2: fh_idx_ext = sc_t2_idx_fh_p2;
  3: fh_idx_ext = sc_t3_idx_fh_p2;
  default: assert; // sc_table instantiated only for THIS_TABLE 0-3
endcase
```

ST0 uses fh_idx_ext=0. SC_TBL_FH[0]=0; ST0 is an unhashed PC slice
(sc_decisions.md section 9).

ST4 is not indexed by this function. sc_brimli uses get_br_imli_idx.
The default arm is unreachable by construction; the assert is
defensive.

### Function

```
logic [THIS_INDEX_BITS-1:0] hashed_index =
  THIS_INDEX_BITS'((inp_pc_p2[s] >> INST_OFFSET) ^ fh_idx_ext);
```

The PC is right-shifted by INST_OFFSET (2) to drop the instruction
offset. The shifted PC is XORed with the fold. The result is
truncated to THIS_INDEX_BITS by the cast.

---
## get_br_imli_idx (ST4, sc_brimli)

### Inputs

```
pc         [9:0]  PC[15:6] of the branch (sc_decisions.md section 12).
phr        [9:0]  low 10 bits of path history, sc_phr_p2
                  (sc_interfaces.md).
br_imli    [9:0]  BrIMLI counter, held in sc_cntrl, presented to
                  sc_brimli as an input (sc_decisions.md sections
                  8, 12).
mode       br_imli_mode_e, default IDX_IMLI_PHR (bp_structs_pkg.sv).
```

The pc argument is PC[15:6]. sc_decisions.md section 12 declares the
argument as [9:0] and defines last_back_pc and branch_range as
PC[15:6]; the [9:0] argument is those 10 bits.

### Function

```
logic [9:0] get_br_imli_idx (input [9:0] pc,
                             input [9:0] phr,
                             input [9:0] br_imli,
                             input br_imli_mode_e mode = IDX_IMLI_PHR)
{
  logic [9:0] f_idx;

  case (mode)
    IDX_IMLI_PHR:  f_idx = (br_imli == 0) ? phr : br_imli;
    IDX_PHR_ONLY:  f_idx = phr;
    IDX_IMLI_ONLY: f_idx = br_imli;
    default:       f_idx = (br_imli == 0) ? phr : br_imli;
  endcase

  return pc ^ f_idx ^ (pc >> 4);
}
```

Mode semantics (sc_decisions.md section 12, bp_structs_pkg.sv
br_imli_mode_e):

```
IDX_IMLI_PHR  (2'b00) IMLI when active, PHR when br_imli cold (==0).
IDX_PHR_ONLY  (2'b01) PHR always; IMLI never used.
IDX_IMLI_ONLY (2'b10) IMLI always; no PHR substitution.
IDX_IMLI_RSRV (2'b11) not used.
```

The mode is a perf-evaluation selector. Source of the mode value
(CSR, tie, or register) is a bp_cluster decision; sc_brimli takes it
as an input port (sc_table_interfaces.md).

---
## Update-path index

No hash on update. upd_index_u0[s] carries the predict-time index
from sc_pred_meta.sc_upd_idx[THIS_TABLE] (sc_decisions.md section
10, sc_table_interfaces.md).

