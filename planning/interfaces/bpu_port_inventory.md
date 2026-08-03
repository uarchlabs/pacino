<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# BPU Top-Level Port Inventory
```
 FILE:    bpu_port_inventory.md
 SOURCE:  INFRA-011
 STATUS:  WORKING
 UPDATED: 2026-08-02
 CONTACT: Jeff Nye
```

---

## Legend

Stage is the pipestage suffix carried by the port name as declared.
NONE means the name carries no suffix. Slot is ARRAY for a declared
slot dimension, SCALAR for a single non-slotted signal, PACKED when
the slot dimension is inside the struct, NAMED when the slot appears
in the port name. Doc is OK when the interface document lists the
port with matching direction and type, MISMATCH when listed
differently, MISSING when not listed.

---

## 1. ubtb

RTL: rtl/core/frontend/bpu/rtl/ubtb.sv
Doc: planning/interfaces/ubtb_interfaces.md

| Port       | Dir | Type / Width   | Stage | Slot   | Doc      |
|------------|-----|----------------|-------|--------|----------|
| clk        | in  | logic          | NONE  | SCALAR | OK       |
| rstn       | in  | logic          | NONE  | SCALAR | OK       |
| pred_pc_p0 | in  | [VA_WIDTH-1:0] | p0    | SCALAR | MISMATCH |
| pred_p1    | out | ubtb_pred_t    | p1    | ARRAY  | MISMATCH |
| upd_u0     | in  | ubtb_upd_t     | u0    | ARRAY  | MISMATCH |

Notes:
- pred_p1 declared with packed slot dimension on the type:
  `ubtb_pred_t [NUM_PRED_SLOTS-1:0] pred_p1` (ubtb.sv:37).
- upd_u0 declared with packed slot dimension on the type:
  `ubtb_upd_t [NUM_PRED_SLOTS-1:0] upd_u0` (ubtb.sv:38).
- MISMATCH rows: direction and type agree with the document; the
  document name differs. Document names are pred_pc, pred, upd
  (ubtb_interfaces.md:45-47).

EXTRA: none

---

## 2. loop_pred

RTL: rtl/core/frontend/bpu/rtl/loop_pred.sv
Doc: planning/interfaces/loop_pred_interfaces.md

| Port          | Dir | Type / Width   | Stage | Slot   | Doc |
|---------------|-----|----------------|-------|--------|-----|
| clk           | in  | logic          | NONE  | SCALAR | OK  |
| rstn          | in  | logic          | NONE  | SCALAR | OK  |
| pred_pc_p0    | in  | [VA_WIDTH-1:0] | p0    | SCALAR | OK  |
| pred_valid_p0 | in  | logic          | p0    | SCALAR | OK  |
| pred_p0       | out | lp_pred_t      | p0    | SCALAR | OK  |
| upd_p0        | in  | lp_upd_t       | p0    | SCALAR | OK  |
| upd_valid_p0  | in  | logic          | p0    | SCALAR | OK  |

EXTRA: none

---

## 3. ftb

RTL: rtl/core/frontend/bpu/rtl/ftb.sv
Doc: planning/interfaces/ftb_interfaces.md

| Port                  | Dir | Type / Width          | Stage | Slot   | Doc |
|-----------------------|-----|-----------------------|-------|--------|-----|
| clk                   | in  | logic                 | NONE  | SCALAR | OK  |
| rstn                  | in  | logic                 | NONE  | SCALAR | OK  |
| pred_valid_p0         | in  | logic                 | p0    | SCALAR | OK  |
| pred_pc_p0            | in  | [VA_WIDTH-1:0]        | p0    | SCALAR | OK  |
| ftb_valid_p2          | out | logic                 | p2    | SCALAR | OK  |
| ftb_hit_p2            | out | logic                 | p2    | SCALAR | OK  |
| ftb_way_p2            | out | [FTB_WAY_BITS-1:0]    | p2    | SCALAR | OK  |
| ftb_br0_valid_p2      | out | logic                 | p2    | SCALAR | OK  |
| ftb_br0_pos_p2        | out | [FTB_BR_POS_BITS-1:0] | p2    | SCALAR | OK  |
| ftb_br0_taken_p2      | out | logic                 | p2    | SCALAR | OK  |
| ftb_br0_conf_p2       | out | [FTB_CONF_WIDTH-1:0]  | p2    | SCALAR | OK  |
| ftb_br0_target_p2     | out | [VA_WIDTH-1:0]        | p2    | SCALAR | OK  |
| ftb_br1_valid_p2      | out | logic                 | p2    | SCALAR | OK  |
| ftb_br1_pos_p2        | out | [FTB_BR_POS_BITS-1:0] | p2    | SCALAR | OK  |
| ftb_br1_taken_p2      | out | logic                 | p2    | SCALAR | OK  |
| ftb_br1_conf_p2       | out | [FTB_CONF_WIDTH-1:0]  | p2    | SCALAR | OK  |
| ftb_br1_target_p2     | out | [VA_WIDTH-1:0]        | p2    | SCALAR | OK  |
| ftb_jmp_valid_p2      | out | logic                 | p2    | SCALAR | OK  |
| ftb_jmp_pos_p2        | out | [FTB_BR_POS_BITS-1:0] | p2    | SCALAR | OK  |
| ftb_jmp_target_p2     | out | [VA_WIDTH-1:0]        | p2    | SCALAR | OK  |
| ftb_is_call_p2        | out | logic                 | p2    | SCALAR | OK  |
| ftb_is_ret_p2         | out | logic                 | p2    | SCALAR | OK  |
| ftb_is_jalr_p2        | out | logic                 | p2    | SCALAR | OK  |
| ftb_pft_addr_p2       | out | [VA_WIDTH-1:0]        | p2    | SCALAR | OK  |
| ftb_fastpath_p2       | out | [1:0]                 | p2    | SCALAR | OK  |
| ftb_fastpath_en       | in  | logic                 | NONE  | SCALAR | OK  |
| ftb_upd_valid_u0      | in  | logic                 | u0    | SCALAR | OK  |
| ftb_upd_pc_u0         | in  | [VA_WIDTH-1:0]        | u0    | SCALAR | OK  |
| ftb_upd_hit_u0        | in  | logic                 | u0    | SCALAR | OK  |
| ftb_upd_way_u0        | in  | [FTB_WAY_BITS-1:0]    | u0    | SCALAR | OK  |
| ftb_upd_is_br_u0      | in  | logic                 | u0    | SCALAR | OK  |
| ftb_upd_br_idx_u0     | in  | logic                 | u0    | SCALAR | OK  |
| ftb_upd_taken_u0      | in  | logic                 | u0    | SCALAR | OK  |
| ftb_upd_target_u0     | in  | [VA_WIDTH-1:0]        | u0    | SCALAR | OK  |
| ftb_upd_pos_u0        | in  | [FTB_BR_POS_BITS-1:0] | u0    | SCALAR | OK  |
| ftb_upd_is_jmp_u0     | in  | logic                 | u0    | SCALAR | OK  |
| ftb_upd_jmp_target_u0 | in  | [VA_WIDTH-1:0]        | u0    | SCALAR | OK  |
| ftb_upd_is_call_u0    | in  | logic                 | u0    | SCALAR | OK  |
| ftb_upd_is_ret_u0     | in  | logic                 | u0    | SCALAR | OK  |
| ftb_upd_is_jalr_u0    | in  | logic                 | u0    | SCALAR | OK  |
| ftb_upd_pft_addr_u0   | in  | [VA_WIDTH-1:0]        | u0    | SCALAR | OK  |
| ftb_flush_px          | in  | logic                 | px    | SCALAR | OK  |

Notes:
- br0 / br1 / jmp in the port names are the conditional and jump
  fields of one indexed entry, not prediction slots
  (ftb_interfaces.md:77-78). Slot is SCALAR on those rows.
- ftb_fastpath_p2 [1:0] is bit 0 = br0, bit 1 = br1
  (ftb_interfaces.md:171), not a slot dimension.

EXTRA: none

---

## 4. tage

RTL: rtl/core/frontend/bpu/rtl/tage.sv
Doc: planning/interfaces/tage_interfaces.md

| Port                | Dir | Type / Width         | Stage | Slot   | Doc |
|---------------------|-----|----------------------|-------|--------|-----|
| clk                 | in  | logic                | NONE  | SCALAR | OK  |
| rstn                | in  | logic                | NONE  | SCALAR | OK  |
| tage_pred_val_p0    | in  | [NUM_PRED_SLOTS-1:0] | p0    | ARRAY  | OK  |
| tage_pred_inp_p0    | in  | tage_pred_inp_t      | p0    | ARRAY  | OK  |
| tage_pred_rdy_p2    | out | [NUM_PRED_SLOTS-1:0] | p2    | ARRAY  | OK  |
| tage_pred_meta_p2   | out | tage_pred_meta_t     | p2    | ARRAY  | OK  |
| tage_upd_val_u0     | in  | [NUM_PRED_SLOTS-1:0] | u0    | ARRAY  | OK  |
| tage_upd_inp_u0     | in  | tage_upd_inp_t       | u0    | ARRAY  | OK  |
| tage_upd_rdy_u1     | out | [NUM_PRED_SLOTS-1:0] | u1    | ARRAY  | OK  |
| pq_not_full         | out | logic                | NONE  | SCALAR | OK  |
| upd_rdy             | out | [NUM_PRED_SLOTS-1:0] | NONE  | ARRAY  | OK  |
| tage_enable_aging   | in  | logic                | NONE  | SCALAR | OK  |
| tage_aging_interval | in  | [31:0]               | NONE  | SCALAR | OK  |
| consumer_ready      | in  | logic                | NONE  | SCALAR | OK  |
| folded_hist         | in  | bp_folded_hist_t     | NONE  | SCALAR | OK  |
| tage_rdy            | out | logic                | NONE  | SCALAR | OK  |

Notes:
- tage_pred_inp_p0, tage_pred_meta_p2, tage_upd_inp_u0 declared with
  unpacked slot dimension [0:NUM_PRED_SLOTS-1] after the port name
  (tage.sv:39, 41, 44).
- The _val / _rdy ports carry the slot dimension as a packed vector
  [NUM_PRED_SLOTS-1:0], one bit per slot.

EXTRA: none

---

## 5. ittage

RTL: rtl/core/frontend/bpu/rtl/ittage.sv
Doc: planning/interfaces/ittage_interfaces.md

| Port                  | Dir | Type / Width         | Stage | Slot   | Doc |
|-----------------------|-----|----------------------|-------|--------|-----|
| clk                   | in  | logic                | NONE  | SCALAR | OK  |
| rstn                  | in  | logic                | NONE  | SCALAR | OK  |
| ittage_pred_val_p0    | in  | [NUM_PRED_SLOTS-1:0] | p0    | ARRAY  | OK  |
| ittage_pred_inp_p0    | in  | ittage_pred_inp_t    | p0    | ARRAY  | OK  |
| ittage_pred_rdy_p2    | out | [NUM_PRED_SLOTS-1:0] | p2    | ARRAY  | OK  |
| ittage_pred_meta_p2   | out | ittage_pred_meta_t   | p2    | ARRAY  | OK  |
| ittage_upd_val_u0     | in  | [NUM_PRED_SLOTS-1:0] | u0    | ARRAY  | OK  |
| ittage_upd_inp_u0     | in  | ittage_upd_inp_t     | u0    | ARRAY  | OK  |
| ittage_upd_rdy_u1     | out | [NUM_PRED_SLOTS-1:0] | u1    | ARRAY  | OK  |
| pq_not_full           | out | logic                | NONE  | SCALAR | OK  |
| upd_rdy               | out | [NUM_PRED_SLOTS-1:0] | NONE  | ARRAY  | OK  |
| ittage_enable_aging   | in  | logic                | NONE  | SCALAR | OK  |
| ittage_aging_interval | in  | [31:0]               | NONE  | SCALAR | OK  |
| folded_hist           | in  | bp_folded_hist_t     | NONE  | SCALAR | OK  |
| ittage_rdy            | out | logic                | NONE  | SCALAR | OK  |

Notes:
- ittage_pred_inp_p0, ittage_pred_meta_p2, ittage_upd_inp_u0
  declared with unpacked slot dimension [0:NUM_PRED_SLOTS-1] after
  the port name (ittage.sv:33, 35, 39).

EXTRA: none

---

## 6. sc

RTL: rtl/core/frontend/bpu/rtl/sc.sv
Doc: planning/interfaces/sc_interfaces.md

| Port              | Dir | Type / Width         | Stage | Slot   | Doc |
|-------------------|-----|----------------------|-------|--------|-----|
| clk               | in  | logic                | NONE  | SCALAR | OK  |
| rstn              | in  | logic                | NONE  | SCALAR | OK  |
| tage_pred_rdy_p2  | in  | [NUM_PRED_SLOTS-1:0] | p2    | ARRAY  | OK  |
| tage_pred_meta_p2 | in  | tage_pred_meta_t     | p2    | ARRAY  | OK  |
| inp_pc_p2         | in  | [VA_WIDTH-1:1]       | p2    | ARRAY  | OK  |
| sc_phr_p2         | in  | [9:0]                | p2    | SCALAR | OK  |
| sc_t1_idx_fh_p2   | in  | [SC_MAX_FH-1:0]      | p2    | SCALAR | OK  |
| sc_t2_idx_fh_p2   | in  | [SC_MAX_FH-1:0]      | p2    | SCALAR | OK  |
| sc_t3_idx_fh_p2   | in  | [SC_MAX_FH-1:0]      | p2    | SCALAR | OK  |
| sc_pred_rdy_p3    | out | [NUM_PRED_SLOTS-1:0] | p3    | ARRAY  | OK  |
| sc_pred_meta_p3   | out | sc_pred_meta_t       | p3    | ARRAY  | OK  |
| sc_upd_val_u0     | in  | [NUM_PRED_SLOTS-1:0] | u0    | ARRAY  | OK  |
| sc_upd_inp_u0     | in  | sc_upd_inp_t         | u0    | ARRAY  | OK  |
| sc_upd_rdy_u1     | out | [NUM_PRED_SLOTS-1:0] | u1    | ARRAY  | OK  |
| sc_uq_not_full    | out | logic                | NONE  | SCALAR | OK  |
| sc_upd_rdy        | out | [NUM_PRED_SLOTS-1:0] | NONE  | ARRAY  | OK  |
| sc_enable         | in  | logic                | NONE  | SCALAR | OK  |
| sc_ready          | out | logic                | NONE  | SCALAR | OK  |

Notes:
- tage_pred_meta_p2, inp_pc_p2, sc_pred_meta_p3, sc_upd_inp_u0
  declared with unpacked slot dimension [0:NUM_PRED_SLOTS-1] after
  the port name (sc.sv:60, 63, 71, 75).
- inp_pc_p2 is declared [VA_WIDTH-1:1], not [VA_WIDTH-1:0]
  (sc.sv:63). Transcribed as declared.

EXTRA: none

---

## 7. ras

RTL: rtl/core/frontend/bpu/rtl/ras.sv
Doc: planning/interfaces/ras_interfaces.md

| Port                 | Dir | Type / Width      | Stage | Slot   | Doc |
|----------------------|-----|-------------------|-------|--------|-----|
| clk                  | in  | logic             | NONE  | SCALAR | OK  |
| rstn                 | in  | logic             | NONE  | SCALAR | OK  |
| ras_tos_addr_p0      | out | [VA_WIDTH-1:0]    | p0    | ARRAY  | OK  |
| ras_tos_valid_p0     | out | logic             | p0    | ARRAY  | OK  |
| ras_pred_val_p2      | in  | logic             | p2    | ARRAY  | OK  |
| ras_br_type_p2       | in  | bp_br_type_e      | p2    | ARRAY  | OK  |
| ras_pc_p2            | in  | [VA_WIDTH-1:0]    | p2    | ARRAY  | OK  |
| ras_fall_through_p2  | in  | [VA_WIDTH-1:0]    | p2    | ARRAY  | OK  |
| ras_pop_addr_p2      | out | [VA_WIDTH-1:0]    | p2    | ARRAY  | OK  |
| ras_pop_valid_p2     | out | logic             | p2    | ARRAY  | OK  |
| ras_snapshot_p2      | out | bp_ras_snapshot_t | p2    | ARRAY  | OK  |
| ras_pred_val_p3      | in  | logic             | p3    | ARRAY  | OK  |
| ras_br_type_p3       | in  | bp_br_type_e      | p3    | ARRAY  | OK  |
| ras_restore_val      | in  | logic             | NONE  | SCALAR | OK  |
| ras_restore_snapshot | in  | bp_ras_snapshot_t | NONE  | SCALAR | OK  |
| ras_commit_val       | in  | logic             | NONE  | SCALAR | OK  |
| ras_commit_br_type   | in  | bp_br_type_e      | NONE  | SCALAR | OK  |
| ras_commit_ret_addr  | in  | [VA_WIDTH-1:0]    | NONE  | SCALAR | OK  |
| ras_commit_snapshot  | in  | bp_ras_snapshot_t | NONE  | SCALAR | OK  |
| ras_flush_val        | in  | logic             | NONE  | SCALAR | OK  |
| ras_flush_snapshot   | in  | bp_ras_snapshot_t | NONE  | SCALAR | OK  |

Notes:
- All ARRAY rows use the unpacked slot dimension
  [0:NUM_PRED_SLOTS-1] after the port name (ras.sv:38-55).
- ras_pc_p2 is declared but not read in ras.sv. TD #101. The
  document records the same condition (ras_interfaces.md:118).

EXTRA: none

---

## 8. bp_history

RTL: rtl/core/frontend/bpu/rtl/bp_history.sv
Doc: planning/interfaces/bp_history_interfaces.md

| Port              | Dir | Type / Width         | Stage | Slot   | Doc      |
|-------------------|-----|----------------------|-------|--------|----------|
| clk               | in  | logic                | NONE  | SCALAR | OK       |
| rstn              | in  | logic                | NONE  | SCALAR | OK       |
| pred_taken        | in  | [1:0]                | NONE  | ARRAY  | OK       |
| pred_pc           | in  | [VA_WIDTH-1:0]       | NONE  | ARRAY  | MISMATCH |
| num_branches      | in  | [1:0]                | NONE  | SCALAR | OK       |
| ckpt_wr_en        | in  | logic                | NONE  | SCALAR | OK       |
| ckpt_wr_idx       | in  | [FTQ_IDX_BITS-1:0]   | NONE  | SCALAR | OK       |
| rollback_valid    | in  | logic                | NONE  | SCALAR | OK       |
| rollback_ckpt_idx | in  | [FTQ_IDX_BITS-1:0]   | NONE  | SCALAR | OK       |
| ghist_ptr         | out | [GHIST_PTR_BITS-1:0] | NONE  | SCALAR | OK       |
| phist_ptr         | out | [PHIST_PTR_BITS-1:0] | NONE  | SCALAR | OK       |
| ckpt_ghist_ptr    | out | [GHIST_PTR_BITS-1:0] | NONE  | SCALAR | OK       |
| ckpt_phist_ptr    | out | [PHIST_PTR_BITS-1:0] | NONE  | SCALAR | OK       |
| ghr_buf           | out | [GHR_WIDTH-1:0]      | NONE  | SCALAR | OK       |
| phr_buf           | out | [PHR_WIDTH-1:0]      | NONE  | SCALAR | OK       |
| folded            | out | bp_folded_hist_t     | NONE  | SCALAR | OK       |

Notes:
- pred_taken is one bit per slot: bit 0 = slot 0, bit 1 = slot 1
  (bp_history.sv:33-34). The dimension is the literal [1:0], not
  NUM_PRED_SLOTS.
- pred_pc is declared with the unpacked dimension as the literal
  [2] after the port name (bp_history.sv:36), not
  [0:NUM_PRED_SLOTS-1].
- num_branches [1:0] is a count with values 0, 1, 2
  (bp_history.sv:37), not a slot dimension.
- pred_pc MISMATCH: see finding 4.

EXTRA: none

---

## Findings

1. planning/interfaces/ubtb_interfaces.md:45 -- port pred_pc_p0 is
   listed as pred_pc. The p0 stage suffix present in ubtb.sv:36 is
   absent from the document name. Direction and type agree.

2. planning/interfaces/ubtb_interfaces.md:46 -- port pred_p1 is
   listed as pred. The p1 stage suffix present in ubtb.sv:37 is
   absent from the document name. Direction and type agree.

3. planning/interfaces/ubtb_interfaces.md:47 -- port upd_u0 is
   listed as upd. The u0 stage suffix present in ubtb.sv:38 is
   absent from the document name. Direction and type agree.

4. planning/interfaces/bp_history_interfaces.md:58 -- port pred_pc
   is listed as `input logic [VA_WIDTH-1:0] [2]`, both dimensions
   before the name (packed form). bp_history.sv:36 declares
   `input logic [VA_WIDTH-1:0] pred_pc [2]`, the [2] dimension
   unpacked after the name. Direction agrees; the dimension
   placement differs.

---

## Coverage

Eight modules, 140 ports read from the RTL port declaration blocks:
ubtb 5, loop_pred 7, ftb 42, tage 16, ittage 15, sc 18, ras 21,
bp_history 16. All eighteen Context Loaded paths were present on
disk. No port row required UNKNOWN.
