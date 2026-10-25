<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fe_top Connectivity Inventory
```
 FILE:    fe_top_connectivity.md
 SOURCE:  DOC-002, DOC-006
 STATUS:  WORKING
 UPDATED: 2026-10-17
 CONTACT: Jeff Nye
```

This is the connectivity of `fe_top` as built
(planning/testbenches/fe_demo_tb_decisions.md FDT-14). It lists the
seven instances, every net between two of them grouped by interface,
every port that crosses the `fe_top` boundary grouped as
planning/arch/fe_decisions.md FE-17 and FE-20 group them, the
predictors one level inside `bp_cluster`, and the page table walker
the testbench places beside `fe_top`. The front-end block diagram,
docs/fe_block.svg, is drawn from it.

Where the RTL and a planning document disagree, this file records
the RTL. The disagreements are listed in section 8.

---

## 1. Sources and method

- RTL: `rtl/core/frontend/fe_top/rtl/fe_top.sv` (827 lines) and
  `rtl/core/frontend/bpu/rtl/bp_cluster.sv` (1978 lines), read to the
  last line. BP-138, BP-139 and BP-140 lengthened bp_cluster.sv to
  2039 lines; the bp_cluster.sv citations they moved are given at
  their current lines (DOC-006, DOC-007). Each instance's port
  declarations were read from its own module file for direction and
  declaration line.
- Widths are the elaborated widths. The fe_top source list of
  examples/fe_demo/Makefile (less ptw.sv) was elaborated with
  tools/bin/verilator (5.048) `--json-only --top-module fe_top`, and
  the width of every fe_top net and every instance port was read from
  the elaborated type table. Every net's width equals the width of
  each port it is bound to; no binding changes width.
- Configuration: NUM_PRED_SLOTS = 2, the package default
  (bp_defines_pkg.sv:65, `BP_NUM_PRED_SLOTS`), the demonstration's
  two-slot model. Since DOC-006 the demonstration's default model is
  built with one slot (Makefile `SLOT1_FLAGS`); in that build every
  width and element count that NUM_PRED_SLOTS sets is the one-slot
  value. The instances and the nets are the same.
- Notation. `W bits` is the packed width. `N x W bits` is an unpacked
  array of N elements of W bits each. `from` is the instance output
  that drives the net, `to` the instance input that reads it. File
  names without a directory are the module files of section 2.1.
  `bind fe_top.sv:L` is the line of the port connection.
- fe_top is purely structural (fe_top.sv:8-13, FE-15). Every binding
  is a net name, a member select of `fe_cfg` (section 5.2) or a
  constant (section 5.3). Every internal net has exactly one driving
  instance output.

Counts: 7 instances; 141 internal nets between two instances
(section 3); 7 cluster outputs that end on unread wires and 3 constant
inputs (section 5); 75 fe_top ports (section 4), of which `fe_cfg`
is distributed as 7 member selects to 8 instance inputs.

---

## 2. Instances, parameters and types

### 2.1 Instances in fe_top

```
inst     module         instantiated    module file
u_bpu    bp_cluster     fe_top.sv:400   rtl/core/frontend/bpu/rtl/bp_cluster.sv
u_ftq    ftq            fe_top.sv:505   rtl/core/frontend/ftq/rtl/ftq.sv
u_ifu    ifu            fe_top.sv:637   rtl/core/frontend/ifu/rtl/ifu.sv
u_l1i    l1i            fe_top.sv:711   rtl/core/frontend/icache/rtl/l1i.sv
u_itlb   itlb           fe_top.sv:754   rtl/mmu/itlb/rtl/itlb.sv
u_ibuf   ibuf           fe_top.sv:802   rtl/core/frontend/ibuf/rtl/ibuf.sv
u_dec    instr_decoder  fe_top.sv:817   rtl/core/frontend/decode/rtl/
                                        instr_decoder.sv
```

Module declarations: bp_cluster.sv:105, ftq.sv:70, ifu.sv:58,
l1i.sv:48, itlb.sv:159, ibuf.sv:56, instr_decoder.sv:93. Every
instance takes its parameter defaults; fe_top overrides none. `u_dec`
is combinational and has no clk or rstn. The PMP/PMA checker is
inside `u_itlb` (fe_top.sv:24-25, MMU-10a).

FE-15 (planning/arch/fe_decisions.md:1333) names the same seven units.

### 2.2 Parameters (package values)

```
VA_WIDTH         41   bp_defines_pkg.sv:25
PA_WIDTH         36   bp_defines_pkg.sv:573
FTQ_DEPTH        64   bp_defines_pkg.sv:30
FTQ_IDX_BITS      6   bp_defines_pkg.sv:113   $clog2(FTQ_DEPTH)
FTQ_PTR_BITS      7   bp_defines_pkg.sv:118   FTQ_IDX_BITS + 1
NUM_PRED_SLOTS    2   bp_defines_pkg.sv:65
NUM_RESOLVE_PORTS 2   bp_defines_pkg.sv:128   = NUM_PRED_SLOTS
SLOTS             8   decode_pkg.sv:21        decode width
FTB_BR_POS_BITS   4   bp_defines_pkg.sv:186
FTB_WAY_BITS      2   bp_defines_pkg.sv:177
FTQ_PD_WIDTH     16   bp_defines_pkg.sv:237   halfwords per block
FTQ_PD_POS_BITS   4   bp_defines_pkg.sv:242
RB_CORR_BITS      2   bp_defines_pkg.sv:108
RB_CNT_BITS       2   bp_defines_pkg.sv:109
GHR_WIDTH       256   bp_defines_pkg.sv:26
PHR_WIDTH        32   bp_defines_pkg.sv:27
GHIST_PTR_BITS    8   bp_defines_pkg.sv:28
PHIST_PTR_BITS    5   bp_defines_pkg.sv:29
REQ_ID_BITS       4   bp_defines_pkg.sv:578
L1I_LINE_BITS   512   bp_defines_pkg.sv:575
ASID_WIDTH       16   bp_defines_pkg.sv:601
VMID_WIDTH       14   bp_defines_pkg.sv:602
PPN_WIDTH        24   bp_defines_pkg.sv:600   PA_WIDTH - 12
PERM_WIDTH        8   bp_defines_pkg.sv:603
CAUSE_WIDTH       5   bp_defines_pkg.sv:604
FAULT_GPA_WIDTH  56   bp_defines_pkg.sv:597
PMA_WIDTH         4   bp_defines_pkg.sv:605
```

bp_defines_pkg.sv and bp_structs_pkg.sv are in
rtl/core/frontend/bpu/rtl/, decode_pkg.sv in
rtl/core/frontend/decode/rtl/, csr_pkg.sv in rtl/core/csr/rtl/.

### 2.3 Types (elaborated width of one element)

```
type                width  declared
decode_pkt_t          133  decode_pkg.sv:311
vec_decode_pkt_t       46  decode_pkg.sv:678
ext_enable_t           16  decode_pkg.sv:623
ifu_pd_pkt_t          190  bp_structs_pkg.sv:611
ftq_resolve_t          57  bp_structs_pkg.sv:537
ftq_redir_cause_e       2  bp_structs_pkg.sv:130
ftq_pd_info_t           6  bp_structs_pkg.sv:555
bp_ftq_slot_t          57  bp_structs_pkg.sv:417
bp_ras_snapshot_t      12  bp_structs_pkg.sv:153
bp_redirect_t          42  bp_structs_pkg.sv:507
bp_br_type_e            3  bp_structs_pkg.sv:96
tage_pred_meta_t       79  bp_structs_pkg.sv:241
ittage_pred_meta_t    147  bp_structs_pkg.sv:298
lp_pred_t              80  bp_structs_pkg.sv:191
ftb_pred_meta_t         7  bp_structs_pkg.sv:454
sc_pred_meta_t        112  bp_structs_pkg.sv:361
ubtb_upd_t            176  bp_structs_pkg.sv:709
lp_upd_t              163  bp_structs_pkg.sv:755
tage_upd_inp_t         81  bp_structs_pkg.sv:250
ittage_upd_inp_t      188  bp_structs_pkg.sv:308
sc_upd_inp_t          125  bp_structs_pkg.sv:382
fe_csr_t              733  csr_pkg.sv:247
fe_cfg_t               84  csr_pkg.sv:232
ptw_csr_t                  csr_pkg.sv:264 (walker only, section 7)
```

---

## 3. Connections between instances, by interface

Every net here is declared in fe_top.sv:219-395 and bound to exactly
two instance ports, one output and one input, except where a group
note says otherwise. The groups follow the interface documents and
the comments of fe_top.sv:219, 320, 352, 373, 389.

### 3.1 FTQ -> BPU prediction request, p0

Specified by:

- planning/interfaces/ftq_bpu_interfaces.md 3 (line 81)

```
ftq_pred_val_p0  logic  1 bits  (fe_top.sv:222)
  from u_ftq.ftq_pred_val_p0  ftq.sv:79  (bind fe_top.sv:508)
  to   u_bpu.ftq_pred_val_p0  bp_cluster.sv:110  (bind fe_top.sv:403)
ftq_pred_pc_p0  logic [VA_WIDTH-1:0]  41 bits  (fe_top.sv:223)
  from u_ftq.ftq_pred_pc_p0  ftq.sv:80  (bind fe_top.sv:509)
  to   u_bpu.ftq_pred_pc_p0  bp_cluster.sv:111  (bind fe_top.sv:404)
ftq_pred_idx_p0  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:224)
  from u_ftq.ftq_pred_idx_p0  ftq.sv:81  (bind fe_top.sv:510)
  to   u_bpu.ftq_pred_idx_p0  bp_cluster.sv:112  (bind fe_top.sv:405)
```

### 3.2 BPU -> FTQ RAM init readies (BP-137)

Specified by:

- planning/interfaces/ftq_bpu_interfaces.md 3 (lines 100-108)

```
bpu_tage_rdy  logic  1 bits  (fe_top.sv:309)
  from u_bpu.tage_rdy  bp_cluster.sv:283  (bind fe_top.sv:488)
  to   u_ftq.tage_rdy  ftq.sv:95  (bind fe_top.sv:514)
bpu_ittage_rdy  logic  1 bits  (fe_top.sv:310)
  from u_bpu.ittage_rdy  bp_cluster.sv:284  (bind fe_top.sv:489)
  to   u_ftq.ittage_rdy  ftq.sv:96  (bind fe_top.sv:515)
bpu_sc_ready  logic  1 bits  (fe_top.sv:311)
  from u_bpu.sc_ready  bp_cluster.sv:285  (bind fe_top.sv:490)
  to   u_ftq.sc_ready  ftq.sv:97  (bind fe_top.sv:516)
```

### 3.3 BPU -> FTQ queue status

Specified by:

- planning/interfaces/ftq_bpu_interfaces.md 8 (lines 935-958)

```
tage_pq_not_full  logic  1 bits  (fe_top.sv:269)
  from u_bpu.tage_pq_not_full  bp_cluster.sv:292  (bind fe_top.sv:491)
  to   u_ftq.tage_pq_not_full  ftq.sv:86  (bind fe_top.sv:511)
ittage_pq_not_full  logic  1 bits  (fe_top.sv:270)
  from u_bpu.ittage_pq_not_full  bp_cluster.sv:295  (bind fe_top.sv:494)
  to   u_ftq.ittage_pq_not_full  ftq.sv:87  (bind fe_top.sv:512)
sc_uq_not_full  logic  1 bits  (fe_top.sv:271)
  from u_bpu.sc_uq_not_full  bp_cluster.sv:298  (bind fe_top.sv:497)
  to   u_ftq.sc_uq_not_full  ftq.sv:88  (bind fe_top.sv:513)
bpu_tage_upd_rdy  logic [NUM_PRED_SLOTS-1:0]  2 bits  (fe_top.sv:312)
  from u_bpu.tage_upd_rdy  bp_cluster.sv:293  (bind fe_top.sv:492)
  to   u_ftq.tage_upd_rdy  ftq.sv:196  (bind fe_top.sv:571)
bpu_ittage_upd_rdy  logic [NUM_PRED_SLOTS-1:0]  2 bits  (fe_top.sv:314)
  from u_bpu.ittage_upd_rdy  bp_cluster.sv:296  (bind fe_top.sv:495)
  to   u_ftq.ittage_upd_rdy  ftq.sv:197  (bind fe_top.sv:572)
bpu_sc_upd_rdy  logic [NUM_PRED_SLOTS-1:0]  2 bits  (fe_top.sv:316)
  from u_bpu.sc_upd_rdy  bp_cluster.sv:299  (bind fe_top.sv:498)
  to   u_ftq.sc_upd_rdy  ftq.sv:198  (bind fe_top.sv:573)
```

### 3.4 BPU -> FTQ initial prediction, p1

Specified by:

- planning/interfaces/ftq_bpu_interfaces.md 4 (line 142)

```
bpu_pred_val_p1  logic  1 bits  (fe_top.sv:225)
  from u_bpu.bpu_pred_val_p1  bp_cluster.sv:115  (bind fe_top.sv:406)
  to   u_ftq.bpu_pred_val_p1  ftq.sv:100  (bind fe_top.sv:517)
bpu_pred_idx_p1  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:226)
  from u_bpu.bpu_pred_idx_p1  bp_cluster.sv:116  (bind fe_top.sv:407)
  to   u_ftq.bpu_pred_idx_p1  ftq.sv:101  (bind fe_top.sv:518)
bpu_pred_slot_p1  bp_ftq_slot_t  2 x 57 bits  (fe_top.sv:227)
  from u_bpu.bpu_pred_slot_p1  bp_cluster.sv:117  (bind fe_top.sv:408)
  to   u_ftq.bpu_pred_slot_p1  ftq.sv:102  (bind fe_top.sv:519)
bpu_pred_ras_p1  bp_ras_snapshot_t  12 bits  (fe_top.sv:228)
  from u_bpu.bpu_pred_ras_p1  bp_cluster.sv:119  (bind fe_top.sv:409)
  to   u_ftq.bpu_pred_ras_p1  ftq.sv:104  (bind fe_top.sv:520)
bpu_pred_pft_p1  logic [VA_WIDTH-1:0]  41 bits  (fe_top.sv:229)
  from u_bpu.bpu_pred_pft_p1  bp_cluster.sv:123  (bind fe_top.sv:410)
  to   u_ftq.bpu_pred_pft_p1  ftq.sv:105  (bind fe_top.sv:521)
```

### 3.5 BPU -> FTQ slot correction, p2 and p3

Specified by:

- planning/interfaces/ftq_bpu_interfaces.md 4a (line 276)

```
bpu_slot_val_p2  logic  1 bits  (fe_top.sv:234)
  from u_bpu.bpu_slot_val_p2  bp_cluster.sv:141  (bind fe_top.sv:415)
  to   u_ftq.bpu_slot_val_p2  ftq.sv:112  (bind fe_top.sv:524)
bpu_slot_idx_p2  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:235)
  from u_bpu.bpu_slot_idx_p2  bp_cluster.sv:142  (bind fe_top.sv:416)
  to   u_ftq.bpu_slot_idx_p2  ftq.sv:113  (bind fe_top.sv:525)
bpu_slot_p2  bp_ftq_slot_t  2 x 57 bits  (fe_top.sv:236)
  from u_bpu.bpu_slot_p2  bp_cluster.sv:143  (bind fe_top.sv:417)
  to   u_ftq.bpu_slot_p2  ftq.sv:114  (bind fe_top.sv:526)
bpu_slot_val_p3  logic  1 bits  (fe_top.sv:237)
  from u_bpu.bpu_slot_val_p3  bp_cluster.sv:147  (bind fe_top.sv:418)
  to   u_ftq.bpu_slot_val_p3  ftq.sv:115  (bind fe_top.sv:527)
bpu_slot_idx_p3  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:238)
  from u_bpu.bpu_slot_idx_p3  bp_cluster.sv:148  (bind fe_top.sv:419)
  to   u_ftq.bpu_slot_idx_p3  ftq.sv:116  (bind fe_top.sv:528)
bpu_slot_p3  bp_ftq_slot_t  2 x 57 bits  (fe_top.sv:239)
  from u_bpu.bpu_slot_p3  bp_cluster.sv:149  (bind fe_top.sv:420)
  to   u_ftq.bpu_slot_p3  ftq.sv:117  (bind fe_top.sv:529)
```

### 3.6 BPU -> FTQ block-scalar correction, p2

Specified by:

- planning/interfaces/ftq_bpu_interfaces.md 4c (line 360)

```
bpu_blk_val_p2  logic  1 bits  (fe_top.sv:240)
  from u_bpu.bpu_blk_val_p2  bp_cluster.sv:157  (bind fe_top.sv:421)
  to   u_ftq.bpu_blk_val_p2  ftq.sv:122  (bind fe_top.sv:530)
bpu_blk_idx_p2  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:241)
  from u_bpu.bpu_blk_idx_p2  bp_cluster.sv:158  (bind fe_top.sv:422)
  to   u_ftq.bpu_blk_idx_p2  ftq.sv:123  (bind fe_top.sv:531)
bpu_blk_ras_p2  bp_ras_snapshot_t  12 bits  (fe_top.sv:242)
  from u_bpu.bpu_blk_ras_p2  bp_cluster.sv:159  (bind fe_top.sv:423)
  to   u_ftq.bpu_blk_ras_p2  ftq.sv:124  (bind fe_top.sv:532)
bpu_blk_pft_p2  logic [VA_WIDTH-1:0]  41 bits  (fe_top.sv:243)
  from u_bpu.bpu_blk_pft_p2  bp_cluster.sv:160  (bind fe_top.sv:424)
  to   u_ftq.bpu_blk_pft_p2  ftq.sv:125  (bind fe_top.sv:533)
```

### 3.7 BPU -> FTQ redirects, p2 and p3

Specified by:

- planning/interfaces/ftq_bpu_interfaces.md 6 (line 643)

```
bpu_redir_p2  bp_redirect_t  2 x 42 bits  (fe_top.sv:230)
  from u_bpu.bpu_redir_p2  bp_cluster.sv:126  (bind fe_top.sv:411)
  to   u_ftq.bpu_redir_p2  ftq.sv:128  (bind fe_top.sv:534)
bpu_redir_idx_p2  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:231)
  from u_bpu.bpu_redir_idx_p2  bp_cluster.sv:128  (bind fe_top.sv:412)
  to   u_ftq.bpu_redir_idx_p2  ftq.sv:129  (bind fe_top.sv:535)
bpu_redir_p3  bp_redirect_t  2 x 42 bits  (fe_top.sv:232)
  from u_bpu.bpu_redir_p3  bp_cluster.sv:129  (bind fe_top.sv:413)
  to   u_ftq.bpu_redir_p3  ftq.sv:130  (bind fe_top.sv:536)
bpu_redir_idx_p3  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:233)
  from u_bpu.bpu_redir_idx_p3  bp_cluster.sv:131  (bind fe_top.sv:414)
  to   u_ftq.bpu_redir_idx_p3  ftq.sv:131  (bind fe_top.sv:537)
```

### 3.8 BPU -> FTQ prediction metadata, p2 and p3

Specified by:

- planning/interfaces/ftq_bpu_interfaces.md 7.1 (line 716)
- planning/interfaces/ftq_bpu_interfaces.md 7.2 (line 754)

```
bpu_meta_val_p2  logic  1 bits  (fe_top.sv:244)
  from u_bpu.bpu_meta_val_p2  bp_cluster.sv:166  (bind fe_top.sv:425)
  to   u_ftq.bpu_meta_val_p2  ftq.sv:134  (bind fe_top.sv:538)
bpu_meta_idx_p2  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:245)
  from u_bpu.bpu_meta_idx_p2  bp_cluster.sv:167  (bind fe_top.sv:426)
  to   u_ftq.bpu_meta_idx_p2  ftq.sv:135  (bind fe_top.sv:539)
bpu_meta_tage_p2  tage_pred_meta_t  2 x 79 bits  (fe_top.sv:246)
  from u_bpu.bpu_meta_tage_p2  bp_cluster.sv:168  (bind fe_top.sv:427)
  to   u_ftq.bpu_meta_tage_p2  ftq.sv:136  (bind fe_top.sv:540)
bpu_meta_ittage_p2  ittage_pred_meta_t  2 x 147 bits  (fe_top.sv:247)
  from u_bpu.bpu_meta_ittage_p2  bp_cluster.sv:170  (bind fe_top.sv:428)
  to   u_ftq.bpu_meta_ittage_p2  ftq.sv:138  (bind fe_top.sv:541)
bpu_meta_lp_p2  lp_pred_t  2 x 80 bits  (fe_top.sv:248)
  from u_bpu.bpu_meta_lp_p2  bp_cluster.sv:172  (bind fe_top.sv:429)
  to   u_ftq.bpu_meta_lp_p2  ftq.sv:140  (bind fe_top.sv:542)
bpu_meta_ftb_p2  ftb_pred_meta_t  2 x 7 bits  (fe_top.sv:249)
  from u_bpu.bpu_meta_ftb_p2  bp_cluster.sv:174  (bind fe_top.sv:430)
  to   u_ftq.bpu_meta_ftb_p2  ftq.sv:142  (bind fe_top.sv:543)
bpu_meta_val_p3  logic  1 bits  (fe_top.sv:250)
  from u_bpu.bpu_meta_val_p3  bp_cluster.sv:179  (bind fe_top.sv:431)
  to   u_ftq.bpu_meta_val_p3  ftq.sv:144  (bind fe_top.sv:544)
bpu_meta_idx_p3  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:251)
  from u_bpu.bpu_meta_idx_p3  bp_cluster.sv:180  (bind fe_top.sv:432)
  to   u_ftq.bpu_meta_idx_p3  ftq.sv:145  (bind fe_top.sv:545)
bpu_meta_sc_p3  sc_pred_meta_t  2 x 112 bits  (fe_top.sv:252)
  from u_bpu.bpu_meta_sc_p3  bp_cluster.sv:181  (bind fe_top.sv:433)
  to   u_ftq.bpu_meta_sc_p3  ftq.sv:146  (bind fe_top.sv:546)
```

### 3.9 FTQ -> BPU per-predictor updates, u0

Specified by:

- planning/interfaces/ftq_bpu_interfaces.md 8 (line 841)

```
ubtb_upd_u0  ubtb_upd_t [NUM_PRED_SLOTS-1:0]  352 bits  (fe_top.sv:292)
  from u_ftq.ubtb_upd_u0  ftq.sv:184  (bind fe_top.sv:562)
  to   u_bpu.ubtb_upd_u0  bp_cluster.sv:186  (bind fe_top.sv:434)
lp_upd_valid_p0  logic [NUM_PRED_SLOTS-1:0]  2 bits  (fe_top.sv:293)
  from u_ftq.lp_upd_valid_p0  ftq.sv:185  (bind fe_top.sv:563)
  to   u_bpu.lp_upd_valid_p0  bp_cluster.sv:190  (bind fe_top.sv:435)
lp_upd_p0  lp_upd_t  2 x 163 bits  (fe_top.sv:294)
  from u_ftq.lp_upd_p0  ftq.sv:186  (bind fe_top.sv:564)
  to   u_bpu.lp_upd_p0  bp_cluster.sv:191  (bind fe_top.sv:436)
tage_upd_val_u0  logic [NUM_PRED_SLOTS-1:0]  2 bits  (fe_top.sv:295)
  from u_ftq.tage_upd_val_u0  ftq.sv:187  (bind fe_top.sv:565)
  to   u_bpu.tage_upd_val_u0  bp_cluster.sv:214  (bind fe_top.sv:454)
tage_upd_inp_u0  tage_upd_inp_t  2 x 81 bits  (fe_top.sv:296)
  from u_ftq.tage_upd_inp_u0  ftq.sv:188  (bind fe_top.sv:566)
  to   u_bpu.tage_upd_inp_u0  bp_cluster.sv:215  (bind fe_top.sv:455)
ittage_upd_val_u0  logic [NUM_PRED_SLOTS-1:0]  2 bits  (fe_top.sv:297)
  from u_ftq.ittage_upd_val_u0  ftq.sv:190  (bind fe_top.sv:567)
  to   u_bpu.ittage_upd_val_u0  bp_cluster.sv:218  (bind fe_top.sv:456)
ittage_upd_inp_u0  ittage_upd_inp_t  2 x 188 bits  (fe_top.sv:298)
  from u_ftq.ittage_upd_inp_u0  ftq.sv:191  (bind fe_top.sv:568)
  to   u_bpu.ittage_upd_inp_u0  bp_cluster.sv:219  (bind fe_top.sv:457)
sc_upd_val_u0  logic [NUM_PRED_SLOTS-1:0]  2 bits  (fe_top.sv:299)
  from u_ftq.sc_upd_val_u0  ftq.sv:193  (bind fe_top.sv:569)
  to   u_bpu.sc_upd_val_u0  bp_cluster.sv:222  (bind fe_top.sv:458)
sc_upd_inp_u0  sc_upd_inp_t  2 x 125 bits  (fe_top.sv:300)
  from u_ftq.sc_upd_inp_u0  ftq.sv:194  (bind fe_top.sv:570)
  to   u_bpu.sc_upd_inp_u0  bp_cluster.sv:223  (bind fe_top.sv:459)
```

### 3.10 FTQ -> BPU FTB update, u0

Specified by:

- planning/interfaces/ftq_bpu_interfaces.md 8 (line 841;
  the FTB notes, lines 892-900)
- planning/interfaces/ftb_interfaces.md 2.5 (line 245)

```
ftb_upd_valid_u0  logic  1 bits  (fe_top.sv:274)
  from u_ftq.ftb_upd_valid_u0  ftq.sv:201  (bind fe_top.sv:574)
  to   u_bpu.ftb_upd_valid_u0  bp_cluster.sv:195  (bind fe_top.sv:437)
ftb_upd_pc_u0  logic [VA_WIDTH-1:0]  41 bits  (fe_top.sv:275)
  from u_ftq.ftb_upd_pc_u0  ftq.sv:202  (bind fe_top.sv:575)
  to   u_bpu.ftb_upd_pc_u0  bp_cluster.sv:196  (bind fe_top.sv:438)
ftb_upd_hit_u0  logic  1 bits  (fe_top.sv:276)
  from u_ftq.ftb_upd_hit_u0  ftq.sv:203  (bind fe_top.sv:576)
  to   u_bpu.ftb_upd_hit_u0  bp_cluster.sv:197  (bind fe_top.sv:439)
ftb_upd_way_u0  logic [FTB_WAY_BITS-1:0]  2 bits  (fe_top.sv:277)
  from u_ftq.ftb_upd_way_u0  ftq.sv:204  (bind fe_top.sv:577)
  to   u_bpu.ftb_upd_way_u0  bp_cluster.sv:198  (bind fe_top.sv:440)
ftb_upd_is_br_u0  logic  1 bits  (fe_top.sv:278)
  from u_ftq.ftb_upd_is_br_u0  ftq.sv:205  (bind fe_top.sv:578)
  to   u_bpu.ftb_upd_is_br_u0  bp_cluster.sv:199  (bind fe_top.sv:441)
ftb_upd_br_idx_u0  logic  1 bits  (fe_top.sv:279)
  from u_ftq.ftb_upd_br_idx_u0  ftq.sv:206  (bind fe_top.sv:579)
  to   u_bpu.ftb_upd_br_idx_u0  bp_cluster.sv:200  (bind fe_top.sv:442)
ftb_upd_taken_u0  logic  1 bits  (fe_top.sv:280)
  from u_ftq.ftb_upd_taken_u0  ftq.sv:207  (bind fe_top.sv:580)
  to   u_bpu.ftb_upd_taken_u0  bp_cluster.sv:201  (bind fe_top.sv:443)
ftb_upd_target_u0  logic [VA_WIDTH-1:0]  41 bits  (fe_top.sv:281)
  from u_ftq.ftb_upd_target_u0  ftq.sv:208  (bind fe_top.sv:581)
  to   u_bpu.ftb_upd_target_u0  bp_cluster.sv:202  (bind fe_top.sv:444)
ftb_upd_pos_u0  logic [FTB_BR_POS_BITS-1:0]  4 bits  (fe_top.sv:282)
  from u_ftq.ftb_upd_pos_u0  ftq.sv:209  (bind fe_top.sv:582)
  to   u_bpu.ftb_upd_pos_u0  bp_cluster.sv:203  (bind fe_top.sv:445)
ftb_upd_is_jmp_u0  logic  1 bits  (fe_top.sv:283)
  from u_ftq.ftb_upd_is_jmp_u0  ftq.sv:210  (bind fe_top.sv:583)
  to   u_bpu.ftb_upd_is_jmp_u0  bp_cluster.sv:204  (bind fe_top.sv:446)
ftb_upd_jmp_target_u0  logic [VA_WIDTH-1:0]  41 bits  (fe_top.sv:284)
  from u_ftq.ftb_upd_jmp_target_u0  ftq.sv:211  (bind fe_top.sv:584)
  to   u_bpu.ftb_upd_jmp_target_u0  bp_cluster.sv:205  (bind fe_top.sv:447)
ftb_upd_is_call_u0  logic  1 bits  (fe_top.sv:285)
  from u_ftq.ftb_upd_is_call_u0  ftq.sv:212  (bind fe_top.sv:585)
  to   u_bpu.ftb_upd_is_call_u0  bp_cluster.sv:206  (bind fe_top.sv:448)
ftb_upd_is_ret_u0  logic  1 bits  (fe_top.sv:286)
  from u_ftq.ftb_upd_is_ret_u0  ftq.sv:213  (bind fe_top.sv:586)
  to   u_bpu.ftb_upd_is_ret_u0  bp_cluster.sv:207  (bind fe_top.sv:449)
ftb_upd_is_jalr_u0  logic  1 bits  (fe_top.sv:287)
  from u_ftq.ftb_upd_is_jalr_u0  ftq.sv:214  (bind fe_top.sv:587)
  to   u_bpu.ftb_upd_is_jalr_u0  bp_cluster.sv:208  (bind fe_top.sv:450)
ftb_upd_jmp_rvc_u0  logic  1 bits  (fe_top.sv:288)
  from u_ftq.ftb_upd_jmp_rvc_u0  ftq.sv:215  (bind fe_top.sv:588)
  to   u_bpu.ftb_upd_jmp_rvc_u0  bp_cluster.sv:210  (bind fe_top.sv:451)
ftb_upd_pft_addr_u0  logic [VA_WIDTH-1:0]  41 bits  (fe_top.sv:289)
  from u_ftq.ftb_upd_pft_addr_u0  ftq.sv:216  (bind fe_top.sv:589)
  to   u_bpu.ftb_upd_pft_addr_u0  bp_cluster.sv:211  (bind fe_top.sv:452)
```

### 3.11 FTQ -> BPU RAS commit and restore

Specified by:

- planning/interfaces/ftq_bpu_interfaces.md 8 (RAS commit
  lines 901-904, restore lines 960-965)

```
ras_commit_val  logic  1 bits  (fe_top.sv:265)
  from u_ftq.ras_commit_val  ftq.sv:171  (bind fe_top.sv:557)
  to   u_bpu.ras_commit_val  bp_cluster.sv:229  (bind fe_top.sv:462)
ras_commit_br_type  bp_br_type_e  3 bits  (fe_top.sv:266)
  from u_ftq.ras_commit_br_type  ftq.sv:172  (bind fe_top.sv:558)
  to   u_bpu.ras_commit_br_type  bp_cluster.sv:230  (bind fe_top.sv:463)
ras_commit_ret_addr  logic [VA_WIDTH-1:0]  41 bits  (fe_top.sv:267)
  from u_ftq.ras_commit_ret_addr  ftq.sv:173  (bind fe_top.sv:559)
  to   u_bpu.ras_commit_ret_addr  bp_cluster.sv:231  (bind fe_top.sv:464)
ras_commit_snapshot  bp_ras_snapshot_t  12 bits  (fe_top.sv:268)
  from u_ftq.ras_commit_snapshot  ftq.sv:174  (bind fe_top.sv:560)
  to   u_bpu.ras_commit_snapshot  bp_cluster.sv:232  (bind fe_top.sv:465)
ras_restore_val  logic  1 bits  (fe_top.sv:263)
  from u_ftq.ras_restore_val  ftq.sv:169  (bind fe_top.sv:555)
  to   u_bpu.ras_restore_val  bp_cluster.sv:227  (bind fe_top.sv:460)
ras_restore_snapshot  bp_ras_snapshot_t  12 bits  (fe_top.sv:264)
  from u_ftq.ras_restore_snapshot  ftq.sv:170  (bind fe_top.sv:556)
  to   u_bpu.ras_restore_snapshot  bp_cluster.sv:228  (bind fe_top.sv:461)
```

### 3.12 FTQ <-> BPU history rollback and checkpoint

Specified by:

- planning/interfaces/ftq_bpu_interfaces.md 9 (line 974)

```
ftq_rollback_val  logic  1 bits  (fe_top.sv:253)
  from u_ftq.ftq_rollback_val  ftq.sv:150  (bind fe_top.sv:547)
  to   u_bpu.ftq_rollback_val  bp_cluster.sv:245  (bind fe_top.sv:468)
ftq_rollback_idx  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:254)
  from u_ftq.ftq_rollback_idx  ftq.sv:151  (bind fe_top.sv:548)
  to   u_bpu.ftq_rollback_idx  bp_cluster.sv:246  (bind fe_top.sv:469)
ftq_rollback_corr  logic  1 bits  (fe_top.sv:255)
  from u_ftq.ftq_rollback_corr  ftq.sv:154  (bind fe_top.sv:549)
  to   u_bpu.ftq_rollback_corr  bp_cluster.sv:254  (bind fe_top.sv:470)
ftq_rollback_n  logic [RB_CNT_BITS-1:0]  2 bits  (fe_top.sv:256)
  from u_ftq.ftq_rollback_n  ftq.sv:155  (bind fe_top.sv:550)
  to   u_bpu.ftq_rollback_n  bp_cluster.sv:255  (bind fe_top.sv:471)
ftq_rollback_tkn  logic [RB_CORR_BITS-1:0]  2 bits  (fe_top.sv:257)
  from u_ftq.ftq_rollback_tkn  ftq.sv:156  (bind fe_top.sv:551)
  to   u_bpu.ftq_rollback_tkn  bp_cluster.sv:256  (bind fe_top.sv:472)
ftq_rollback_pbit  logic [RB_CORR_BITS-1:0]  2 bits  (fe_top.sv:258)
  from u_ftq.ftq_rollback_pbit  ftq.sv:157  (bind fe_top.sv:552)
  to   u_bpu.ftq_rollback_pbit  bp_cluster.sv:257  (bind fe_top.sv:473)
ftq_rollback_slot_ex  logic [NUM_PRED_SLOTS-1:0]  2 bits  (fe_top.sv:259)
  from u_ftq.ftq_rollback_slot_ex  ftq.sv:160  (bind fe_top.sv:553)
  to   u_bpu.ftq_rollback_slot_ex  bp_cluster.sv:262  (bind fe_top.sv:474)
ftq_rollback_slot_tkn  logic [NUM_PRED_SLOTS-1:0]  2 bits  (fe_top.sv:260)
  from u_ftq.ftq_rollback_slot_tkn  ftq.sv:161  (bind fe_top.sv:554)
  to   u_bpu.ftq_rollback_slot_tkn  bp_cluster.sv:263  (bind fe_top.sv:475)
ckpt_ghist_ptr  logic [GHIST_PTR_BITS-1:0]  8 bits  (fe_top.sv:261)
  from u_bpu.ckpt_ghist_ptr  bp_cluster.sv:268  (bind fe_top.sv:478)
  to   u_ftq.ckpt_ghist_ptr  ftq.sv:108  (bind fe_top.sv:522)
ckpt_phist_ptr  logic [PHIST_PTR_BITS-1:0]  5 bits  (fe_top.sv:262)
  from u_bpu.ckpt_phist_ptr  bp_cluster.sv:269  (bind fe_top.sv:479)
  to   u_ftq.ckpt_phist_ptr  ftq.sv:109  (bind fe_top.sv:523)
```

### 3.13 FTQ -> IFU translation request

Specified by:

- planning/interfaces/ftq_ifu_interfaces.md 4.1 (line 174)

```
ftq_ifu_xlate_val  logic  1 bits  (fe_top.sv:322)
  from u_ftq.ftq_ifu_xlate_val  ftq.sv:221  (bind fe_top.sv:590)
  to   u_ifu.ftq_ifu_xlate_val  ifu.sv:67  (bind fe_top.sv:640)
ftq_ifu_xlate_rdy  logic  1 bits  (fe_top.sv:323)
  from u_ifu.ftq_ifu_xlate_rdy  ifu.sv:68  (bind fe_top.sv:641)
  to   u_ftq.ftq_ifu_xlate_rdy  ftq.sv:222  (bind fe_top.sv:591)
ftq_ifu_xlate_pc  logic [VA_WIDTH-1:0]  41 bits  (fe_top.sv:324)
  from u_ftq.ftq_ifu_xlate_pc  ftq.sv:223  (bind fe_top.sv:592)
  to   u_ifu.ftq_ifu_xlate_pc  ifu.sv:69  (bind fe_top.sv:642)
ftq_ifu_xlate_idx  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:325)
  from u_ftq.ftq_ifu_xlate_idx  ftq.sv:224  (bind fe_top.sv:593)
  to   u_ifu.ftq_ifu_xlate_idx  ifu.sv:70  (bind fe_top.sv:643)
```

### 3.14 FTQ -> IFU fetch request

Specified by:

- planning/interfaces/ftq_ifu_interfaces.md 4 (line 126)

```
ftq_ifu_req_val  logic  1 bits  (fe_top.sv:326)
  from u_ftq.ftq_ifu_req_val  ftq.sv:226  (bind fe_top.sv:594)
  to   u_ifu.ftq_ifu_req_val  ifu.sv:73  (bind fe_top.sv:644)
ftq_ifu_req_rdy  logic  1 bits  (fe_top.sv:327)
  from u_ifu.ftq_ifu_req_rdy  ifu.sv:74  (bind fe_top.sv:645)
  to   u_ftq.ftq_ifu_req_rdy  ftq.sv:227  (bind fe_top.sv:595)
ftq_ifu_start_pc  logic [VA_WIDTH-1:0]  41 bits  (fe_top.sv:328)
  from u_ftq.ftq_ifu_start_pc  ftq.sv:228  (bind fe_top.sv:596)
  to   u_ifu.ftq_ifu_start_pc  ifu.sv:75  (bind fe_top.sv:646)
ftq_ifu_next_pc  logic [VA_WIDTH-1:0]  41 bits  (fe_top.sv:329)
  from u_ftq.ftq_ifu_next_pc  ftq.sv:229  (bind fe_top.sv:597)
  to   u_ifu.ftq_ifu_next_pc  ifu.sv:76  (bind fe_top.sv:647)
ftq_ifu_idx  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:330)
  from u_ftq.ftq_ifu_idx  ftq.sv:230  (bind fe_top.sv:598)
  to   u_ifu.ftq_ifu_idx  ifu.sv:77  (bind fe_top.sv:648)
ftq_ifu_taken_val  logic  1 bits  (fe_top.sv:331)
  from u_ftq.ftq_ifu_taken_val  ftq.sv:231  (bind fe_top.sv:599)
  to   u_ifu.ftq_ifu_taken_val  ifu.sv:78  (bind fe_top.sv:649)
ftq_ifu_taken_pos  logic [FTB_BR_POS_BITS-1:0]  4 bits  (fe_top.sv:332)
  from u_ftq.ftq_ifu_taken_pos  ftq.sv:232  (bind fe_top.sv:600)
  to   u_ifu.ftq_ifu_taken_pos  ifu.sv:79  (bind fe_top.sv:650)
ftq_ifu_gen  logic  1 bits  (fe_top.sv:333)
  from u_ftq.ftq_ifu_gen  ftq.sv:233  (bind fe_top.sv:601)
  to   u_ifu.ftq_ifu_gen  ifu.sv:80  (bind fe_top.sv:651)
ftq_ifu_commit_ptr  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:334)
  from u_ftq.ftq_ifu_commit_ptr  ftq.sv:235  (bind fe_top.sv:602)
  to   u_ifu.ftq_ifu_commit_ptr  ifu.sv:81  (bind fe_top.sv:652)
```

### 3.15 FTQ -> IFU flush

Specified by:

- planning/interfaces/ftq_ifu_interfaces.md 5 (line 252)

```
ftq_ifu_flush_val  logic  1 bits  (fe_top.sv:335)
  from u_ftq.ftq_ifu_flush_val  ftq.sv:237  (bind fe_top.sv:603)
  to   u_ifu.ftq_ifu_flush_val  ifu.sv:84  (bind fe_top.sv:653)
ftq_ifu_flush_idx  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:336)
  from u_ftq.ftq_ifu_flush_idx  ftq.sv:238  (bind fe_top.sv:604)
  to   u_ifu.ftq_ifu_flush_idx  ifu.sv:85  (bind fe_top.sv:654)
```

### 3.16 IFU -> FTQ predecode writeback

Specified by:

- planning/interfaces/ftq_ifu_interfaces.md 6 (line 329)

```
ifu_ftq_pdwb_val  logic  1 bits  (fe_top.sv:337)
  from u_ifu.ifu_ftq_pdwb_val  ifu.sv:88  (bind fe_top.sv:655)
  to   u_ftq.ifu_ftq_pdwb_val  ftq.sv:240  (bind fe_top.sv:605)
ifu_ftq_pdwb_idx  logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:338)
  from u_ifu.ifu_ftq_pdwb_idx  ifu.sv:89  (bind fe_top.sv:656)
  to   u_ftq.ifu_ftq_pdwb_idx  ftq.sv:241  (bind fe_top.sv:606)
ifu_ftq_pdwb_gen  logic  1 bits  (fe_top.sv:339)
  from u_ifu.ifu_ftq_pdwb_gen  ifu.sv:90  (bind fe_top.sv:657)
  to   u_ftq.ifu_ftq_pdwb_gen  ftq.sv:242  (bind fe_top.sv:607)
ifu_ftq_pd  ftq_pd_info_t  16 x 6 bits  (fe_top.sv:340)
  from u_ifu.ifu_ftq_pd  ifu.sv:91  (bind fe_top.sv:658)
  to   u_ftq.ifu_ftq_pd  ftq.sv:243  (bind fe_top.sv:608)
ifu_ftq_pd_range  logic [FTQ_PD_WIDTH-1:0]  16 bits  (fe_top.sv:341)
  from u_ifu.ifu_ftq_pd_range  ifu.sv:92  (bind fe_top.sv:659)
  to   u_ftq.ifu_ftq_pd_range  ftq.sv:244  (bind fe_top.sv:609)
ifu_ftq_cfi_val  logic  1 bits  (fe_top.sv:342)
  from u_ifu.ifu_ftq_cfi_val  ifu.sv:93  (bind fe_top.sv:660)
  to   u_ftq.ifu_ftq_cfi_val  ftq.sv:245  (bind fe_top.sv:610)
ifu_ftq_cfi_pos  logic [FTQ_PD_POS_BITS-1:0]  4 bits  (fe_top.sv:343)
  from u_ifu.ifu_ftq_cfi_pos  ifu.sv:94  (bind fe_top.sv:661)
  to   u_ftq.ifu_ftq_cfi_pos  ftq.sv:246  (bind fe_top.sv:611)
ifu_ftq_mis_val  logic  1 bits  (fe_top.sv:344)
  from u_ifu.ifu_ftq_mis_val  ifu.sv:95  (bind fe_top.sv:662)
  to   u_ftq.ifu_ftq_mis_val  ftq.sv:247  (bind fe_top.sv:612)
ifu_ftq_mis_pos  logic [FTQ_PD_POS_BITS-1:0]  4 bits  (fe_top.sv:345)
  from u_ifu.ifu_ftq_mis_pos  ifu.sv:96  (bind fe_top.sv:663)
  to   u_ftq.ifu_ftq_mis_pos  ftq.sv:248  (bind fe_top.sv:613)
ifu_ftq_target  logic [VA_WIDTH-1:0]  41 bits  (fe_top.sv:346)
  from u_ifu.ifu_ftq_target  ifu.sv:97  (bind fe_top.sv:664)
  to   u_ftq.ifu_ftq_target  ftq.sv:249  (bind fe_top.sv:614)
ifu_ftq_fault_val  logic  1 bits  (fe_top.sv:347)
  from u_ifu.ifu_ftq_fault_val  ifu.sv:98  (bind fe_top.sv:665)
  to   u_ftq.ifu_ftq_fault_val  ftq.sv:250  (bind fe_top.sv:615)
ifu_ftq_fault_pos  logic [FTQ_PD_POS_BITS-1:0]  4 bits  (fe_top.sv:348)
  from u_ifu.ifu_ftq_fault_pos  ifu.sv:99  (bind fe_top.sv:666)
  to   u_ftq.ifu_ftq_fault_pos  ftq.sv:251  (bind fe_top.sv:616)
ifu_ftq_uc_end  logic  1 bits  (fe_top.sv:349)
  from u_ifu.ifu_ftq_uc_end  ifu.sv:100  (bind fe_top.sv:667)
  to   u_ftq.ifu_ftq_uc_end  ftq.sv:252  (bind fe_top.sv:617)
```

### 3.17 IFU -> L1I fetch request

Specified by:

- planning/interfaces/l1i_ifu_interfaces.md 4.1 (line 213)

```
ifu_l1i_req_val  logic  1 bits  (fe_top.sv:356)
  from u_ifu.ifu_l1i_req_val  ifu.sv:103  (bind fe_top.sv:668)
  to   u_l1i.core_valid  l1i.sv:53  (bind fe_top.sv:714)
ifu_l1i_req_rdy  logic  1 bits  (fe_top.sv:357)
  from u_l1i.core_ready  l1i.sv:59  (bind fe_top.sv:720)
  to   u_ifu.ifu_l1i_req_rdy  ifu.sv:104  (bind fe_top.sv:669)
ifu_l1i_req_id  logic [REQ_ID_BITS-1:0]  4 bits  (fe_top.sv:358)
  from u_ifu.ifu_l1i_req_id  ifu.sv:105  (bind fe_top.sv:670)
  to   u_l1i.core_id  l1i.sv:55  (bind fe_top.sv:716)
ifu_l1i_req_paddr  logic [PA_WIDTH-1:0]  36 bits  (fe_top.sv:359)
  from u_ifu.ifu_l1i_req_paddr  ifu.sv:106  (bind fe_top.sv:671)
  to   u_l1i.core_addr  l1i.sv:54  (bind fe_top.sv:715)
ifu_l1i_req_prefetch  logic  1 bits  (fe_top.sv:360)
  from u_ifu.ifu_l1i_req_prefetch  ifu.sv:107  (bind fe_top.sv:672)
  to   u_l1i.core_prefetch  l1i.sv:56  (bind fe_top.sv:717)
ifu_l1i_req_uncached  logic  1 bits  (fe_top.sv:361)
  from u_ifu.ifu_l1i_req_uncached  ifu.sv:108  (bind fe_top.sv:673)
  to   u_l1i.core_uncached  l1i.sv:57  (bind fe_top.sv:718)
```

### 3.18 L1I -> IFU response

Specified by:

- planning/interfaces/l1i_ifu_interfaces.md 5.1 (line 340)

```
l1i_ifu_rsp_val  logic  1 bits  (fe_top.sv:367)
  from u_l1i.core_rvalid  l1i.sv:60  (bind fe_top.sv:721)
  to   u_ifu.l1i_ifu_rsp_val  ifu.sv:109  (bind fe_top.sv:674)
l1i_ifu_rsp_id  logic [REQ_ID_BITS-1:0]  4 bits  (fe_top.sv:368)
  from u_l1i.core_rid  l1i.sv:61  (bind fe_top.sv:722)
  to   u_ifu.l1i_ifu_rsp_id  ifu.sv:110  (bind fe_top.sv:675)
l1i_ifu_rsp_data  logic [L1I_LINE_BITS-1:0]  512 bits  (fe_top.sv:369)
  from u_l1i.core_rdata  l1i.sv:58  (bind fe_top.sv:719)
  to   u_ifu.l1i_ifu_rsp_data  ifu.sv:111  (bind fe_top.sv:676)
l1i_ifu_rsp_err  logic  1 bits  (fe_top.sv:370)
  from u_l1i.core_rerr  l1i.sv:62  (bind fe_top.sv:723)
  to   u_ifu.l1i_ifu_rsp_err  ifu.sv:112  (bind fe_top.sv:677)
```

### 3.19 IFU -> L1I maintenance

Specified by:

- planning/interfaces/l1i_ifu_interfaces.md 10.1 (line 578)

```
ifu_l1i_inv_val  logic  1 bits  (fe_top.sv:362)
  from u_ifu.ifu_l1i_inv_val  ifu.sv:115  (bind fe_top.sv:678)
  to   u_l1i.core_inv_val  l1i.sv:65  (bind fe_top.sv:724)
ifu_l1i_inv_rdy  logic  1 bits  (fe_top.sv:363)
  from u_l1i.core_inv_rdy  l1i.sv:66  (bind fe_top.sv:725)
  to   u_ifu.ifu_l1i_inv_rdy  ifu.sv:116  (bind fe_top.sv:679)
ifu_l1i_inv_all  logic  1 bits  (fe_top.sv:364)
  from u_ifu.ifu_l1i_inv_all  ifu.sv:117  (bind fe_top.sv:680)
  to   u_l1i.core_inv_all  l1i.sv:67  (bind fe_top.sv:726)
ifu_l1i_inv_paddr  logic [PA_WIDTH-1:0]  36 bits  (fe_top.sv:365)
  from u_ifu.ifu_l1i_inv_paddr  ifu.sv:118  (bind fe_top.sv:681)
  to   u_l1i.core_inv_addr  l1i.sv:68  (bind fe_top.sv:727)
l1i_ifu_inv_done  logic  1 bits  (fe_top.sv:366)
  from u_l1i.core_inv_done  l1i.sv:69  (bind fe_top.sv:728)
  to   u_ifu.l1i_ifu_inv_done  ifu.sv:119  (bind fe_top.sv:682)
```

### 3.20 IFU <-> ITLB

Specified by:

- planning/interfaces/itlb_ifu_interfaces.md 2 (line 34)

```
ifu_itlb_req_val  logic  1 bits  (fe_top.sv:375)
  from u_ifu.ifu_itlb_req_val  ifu.sv:129  (bind fe_top.sv:688)
  to   u_itlb.ifu_itlb_req_val  itlb.sv:176  (bind fe_top.sv:757)
ifu_itlb_req_rdy  logic  1 bits  (fe_top.sv:376)
  from u_itlb.ifu_itlb_req_rdy  itlb.sv:177  (bind fe_top.sv:758)
  to   u_ifu.ifu_itlb_req_rdy  ifu.sv:130  (bind fe_top.sv:689)
ifu_itlb_vpn  logic [VA_WIDTH-13:0]  29 bits  (fe_top.sv:377)
  from u_ifu.ifu_itlb_vpn  ifu.sv:131  (bind fe_top.sv:690)
  to   u_itlb.ifu_itlb_vpn  itlb.sv:178  (bind fe_top.sv:759)
ifu_itlb_tag  logic  1 bits  (fe_top.sv:378)
  from u_ifu.ifu_itlb_tag  ifu.sv:132  (bind fe_top.sv:691)
  to   u_itlb.ifu_itlb_tag  itlb.sv:179  (bind fe_top.sv:760)
itlb_ifu_rsp_val  logic  1 bits  (fe_top.sv:379)
  from u_itlb.itlb_ifu_rsp_val  itlb.sv:180  (bind fe_top.sv:761)
  to   u_ifu.itlb_ifu_rsp_val  ifu.sv:133  (bind fe_top.sv:692)
itlb_ifu_tag  logic  1 bits  (fe_top.sv:380)
  from u_itlb.itlb_ifu_tag  itlb.sv:181  (bind fe_top.sv:762)
  to   u_ifu.itlb_ifu_tag  ifu.sv:134  (bind fe_top.sv:693)
itlb_ifu_status  logic [1:0]  2 bits  (fe_top.sv:381)
  from u_itlb.itlb_ifu_status  itlb.sv:182  (bind fe_top.sv:763)
  to   u_ifu.itlb_ifu_status  ifu.sv:135  (bind fe_top.sv:694)
itlb_ifu_ppn  logic [PPN_WIDTH-1:0]  24 bits  (fe_top.sv:382)
  from u_itlb.itlb_ifu_ppn  itlb.sv:183  (bind fe_top.sv:764)
  to   u_ifu.itlb_ifu_ppn  ifu.sv:136  (bind fe_top.sv:695)
itlb_ifu_cause  logic [CAUSE_WIDTH-1:0]  5 bits  (fe_top.sv:383)
  from u_itlb.itlb_ifu_cause  itlb.sv:184  (bind fe_top.sv:765)
  to   u_ifu.itlb_ifu_cause  ifu.sv:137  (bind fe_top.sv:696)
itlb_ifu_gpa  logic [FAULT_GPA_WIDTH-1:0]  56 bits  (fe_top.sv:384)
  from u_itlb.itlb_ifu_gpa  itlb.sv:185  (bind fe_top.sv:766)
  to   u_ifu.itlb_ifu_gpa  ifu.sv:138  (bind fe_top.sv:697)
itlb_ifu_gpa_imp  logic [1:0]  2 bits  (fe_top.sv:385)
  from u_itlb.itlb_ifu_gpa_imp  itlb.sv:186  (bind fe_top.sv:767)
  to   u_ifu.itlb_ifu_gpa_imp  ifu.sv:139  (bind fe_top.sv:698)
itlb_ifu_pma  logic [PMA_WIDTH-1:0]  4 bits  (fe_top.sv:386)
  from u_itlb.itlb_ifu_pma  itlb.sv:187  (bind fe_top.sv:768)
  to   u_ifu.itlb_ifu_pma  ifu.sv:140  (bind fe_top.sv:699)
```

### 3.21 IFU -> ibuf

Specified by:

- planning/interfaces/ifu_ibuf_interfaces.md 2 (line 30)

```
ifu_ibuf_val  logic  1 bits  (fe_top.sv:391)
  from u_ifu.ifu_ibuf_val  ifu.sv:143  (bind fe_top.sv:700)
  to   u_ibuf.ifu_ibuf_val  ibuf.sv:64  (bind fe_top.sv:805)
ifu_ibuf_en  logic [FTQ_PD_WIDTH-1:0]  16 bits  (fe_top.sv:392)
  from u_ifu.ifu_ibuf_en  ifu.sv:144  (bind fe_top.sv:701)
  to   u_ibuf.ifu_ibuf_en  ibuf.sv:65  (bind fe_top.sv:806)
ifu_ibuf_slot  ifu_pd_pkt_t  16 x 190 bits  (fe_top.sv:393)
  from u_ifu.ifu_ibuf_slot  ifu.sv:145  (bind fe_top.sv:702)
  to   u_ibuf.ifu_ibuf_slot  ibuf.sv:66  (bind fe_top.sv:807)
ibuf_ifu_rdy  logic  1 bits  (fe_top.sv:394)
  from u_ibuf.ibuf_ifu_rdy  ibuf.sv:67  (bind fe_top.sv:808)
  to   u_ifu.ibuf_ifu_rdy  ifu.sv:146  (bind fe_top.sv:703)
```

### 3.22 ibuf -> decode

Specified by:

- planning/arch/ibuf_decisions.md IBUF-10 (line 95)
- planning/arch/ibuf_decisions.md IBUF-12 (line 126)

```
ibuf_dec_slot  ifu_pd_pkt_t  8 x 190 bits  (fe_top.sv:395)
  from u_ibuf.ibuf_dec_slot  ibuf.sv:73  (bind fe_top.sv:810)
  to   u_dec.pd_bundle  instr_decoder.sv:100  (bind fe_top.sv:819)
```
---

## 4. The fe_top boundary

The ports are declared at fe_top.sv:96-217 and grouped as FE-17
(planning/arch/fe_decisions.md:1378) and FE-20
(planning/arch/fe_decisions.md:1445) group them; fe_top.sv:29-60
restates the grouping. `->` is a fe_top input read by an instance
input; `<-` is a fe_top output driven by an instance output.

FE-17 counts two groups that cross (translation and backend) and
says the instruction path is not a boundary group: what crosses is
the L1I's l2-side port `mem`, a topology edge. FE-20 adds three inward
groups (csr, config, maintenance) and one outward dependency, the
ibuf read ready. The RTL carries all of them as fe_top ports; the
L1I's `mem` port is section 4.8. Two outputs are in no group
(section 4.12).

`bkend_ftq_redir_val` is the one fe_top net with two readers: the
FTQ and the ibuf clear (fe_top.sv:44-45, IBUF-13).

### 4.1 Clock and reset

Specified by:

- not grouped by FE-17 or FE-20

```
clk  in   logic  1 bits  (fe_top.sv:97)
  -> u_bpu, u_ftq, u_ifu, u_l1i, u_itlb, u_ibuf
     (binds fe_top.sv:401, 506, 638, 712, 755, 803)
rstn  in   logic  1 bits  (fe_top.sv:98)
  -> u_bpu, u_ftq, u_ifu, u_l1i, u_itlb, u_ibuf
     (binds fe_top.sv:402, 507, 639, 713, 756, 804)
```

### 4.2 backend: decode to rename (FE-17), with the read ready (FE-20 outward)

Specified by:

- planning/arch/fe_decisions.md FE-17 backend (line 1410)
- planning/arch/fe_decisions.md FE-20 outward (line 1475)
- planning/arch/dcd_decisions.md 10 (line 262), 10b (line 612)
- planning/arch/ibuf_decisions.md IBUF-12 (line 126)

```
decode_bundle  out  decode_pkt_t     [SLOTS-1:0]  1064 bits  (fe_top.sv:103)
  <- u_dec.decode_bundle  instr_decoder.sv:103  (bind fe_top.sv:820)
vec_decode_bundle  out  vec_decode_pkt_t [SLOTS-1:0]  368 bits  (fe_top.sv:104)
  <- u_dec.vec_decode_bundle  instr_decoder.sv:108  (bind fe_top.sv:821)
is_vector  out  logic            [SLOTS-1:0]  8 bits  (fe_top.sv:105)
  <- u_dec.is_vector  instr_decoder.sv:109  (bind fe_top.sv:822)
pd_out  out  ifu_pd_pkt_t  8 x 190 bits  (fe_top.sv:106)
  <- u_dec.pd_out  instr_decoder.sv:112  (bind fe_top.sv:823)
vtype_hazard  out  logic            [SLOTS-1:0]  8 bits  (fe_top.sv:107)
  <- u_dec.vtype_hazard  instr_decoder.sv:115  (bind fe_top.sv:824)
dec_ibuf_rdy  in   logic  1 bits  (fe_top.sv:108)
  -> u_ibuf.dec_ibuf_rdy  ibuf.sv:74  (bind fe_top.sv:811)
```

### 4.3 backend: FTQ resolution (FE-17)

Specified by:

- planning/arch/fe_decisions.md FE-17 backend (line 1410)
- planning/interfaces/ftq_backend_interfaces.md 4 (line 74)

```
bkend_ftq_rsv_val  in   logic [NUM_RESOLVE_PORTS-1:0]  2 bits  (fe_top.sv:113)
  -> u_ftq.bkend_ftq_rsv_val  ftq.sv:257  (bind fe_top.sv:618)
bkend_ftq_rsv  in   ftq_resolve_t  2 x 57 bits  (fe_top.sv:114)
  -> u_ftq.bkend_ftq_rsv  ftq.sv:258  (bind fe_top.sv:619)
ftq_bkend_rsv_rdy  out  logic [NUM_RESOLVE_PORTS-1:0]  2 bits  (fe_top.sv:116)
  <- u_ftq.ftq_bkend_rsv_rdy  ftq.sv:260  (bind fe_top.sv:620)
```

### 4.4 backend: FTQ redirect (FE-17)

Specified by:

- planning/interfaces/ftq_backend_interfaces.md 5 (line 172)
- planning/arch/ibuf_decisions.md IBUF-8, IBUF-13 (lines 161, 166)

```
bkend_ftq_redir_val  in   logic  1 bits  (fe_top.sv:117)
  -> u_ftq.bkend_ftq_redir_val  ftq.sv:262  (bind fe_top.sv:621)
  -> u_ibuf.bkend_ftq_redir_val  ibuf.sv:70  (bind fe_top.sv:809)
bkend_ftq_redir_idx  in   logic [FTQ_IDX_BITS-1:0]  6 bits  (fe_top.sv:118)
  -> u_ftq.bkend_ftq_redir_idx  ftq.sv:263  (bind fe_top.sv:622)
bkend_ftq_redir_pos  in   logic [FTB_BR_POS_BITS-1:0]  4 bits  (fe_top.sv:119)
  -> u_ftq.bkend_ftq_redir_pos  ftq.sv:264  (bind fe_top.sv:623)
bkend_ftq_redir_pc  in   logic [VA_WIDTH-1:0]  41 bits  (fe_top.sv:120)
  -> u_ftq.bkend_ftq_redir_pc  ftq.sv:265  (bind fe_top.sv:624)
bkend_ftq_redir_self  in   logic  1 bits  (fe_top.sv:121)
  -> u_ftq.bkend_ftq_redir_self  ftq.sv:266  (bind fe_top.sv:625)
bkend_ftq_redir_cause  in   ftq_redir_cause_e  2 bits  (fe_top.sv:122)
  -> u_ftq.bkend_ftq_redir_cause  ftq.sv:267  (bind fe_top.sv:626)
bkend_ftq_redir_taken  in   logic  1 bits  (fe_top.sv:125)
  -> u_ftq.bkend_ftq_redir_taken  ftq.sv:270  (bind fe_top.sv:627)
```

### 4.5 backend: FTQ commit (FE-17)

Specified by:

- planning/interfaces/ftq_backend_interfaces.md 6 (line 313)

```
bkend_ftq_commit_val  in   logic  1 bits  (fe_top.sv:126)
  -> u_ftq.bkend_ftq_commit_val  ftq.sv:274  (bind fe_top.sv:628)
bkend_ftq_commit_idx  in   logic [FTQ_PTR_BITS-1:0]  7 bits  (fe_top.sv:127)
  -> u_ftq.bkend_ftq_commit_idx  ftq.sv:275  (bind fe_top.sv:629)
```

### 4.6 backend: commit stage to IFU, FENCE.I and cbo.inval (FE-17)

Specified by:

- planning/interfaces/l1i_ifu_interfaces.md 11.2 (line 690)

```
cmt_ifu_maint_val  in   logic  1 bits  (fe_top.sv:133)
  -> u_ifu.cmt_ifu_maint_val  ifu.sv:122  (bind fe_top.sv:683)
cmt_ifu_maint_rdy  out  logic  1 bits  (fe_top.sv:134)
  <- u_ifu.cmt_ifu_maint_rdy  ifu.sv:123  (bind fe_top.sv:684)
cmt_ifu_maint_op  in   logic  1 bits  (fe_top.sv:135)
  -> u_ifu.cmt_ifu_maint_op  ifu.sv:124  (bind fe_top.sv:685)
cmt_ifu_maint_paddr  in   logic [PA_WIDTH-1:0]  36 bits  (fe_top.sv:136)
  -> u_ifu.cmt_ifu_maint_paddr  ifu.sv:125  (bind fe_top.sv:686)
ifu_cmt_maint_ack  out  logic  1 bits  (fe_top.sv:137)
  <- u_ifu.ifu_cmt_maint_ack  ifu.sv:126  (bind fe_top.sv:687)
```

### 4.7 translation: ITLB to the page table walker (FE-17)

Specified by:

- planning/arch/fe_decisions.md FE-17 translation (line 1391)
- planning/interfaces/itlb_l2tlb_interfaces.md 2 (line 41)

```
itlb_l2t_req_val  out  logic  1 bits  (fe_top.sv:143)
  <- u_itlb.itlb_l2t_req_val  itlb.sv:190  (bind fe_top.sv:769)
itlb_l2t_req_rdy  in   logic  1 bits  (fe_top.sv:144)
  -> u_itlb.itlb_l2t_req_rdy  itlb.sv:191  (bind fe_top.sv:770)
itlb_l2t_vpn  out  logic [VA_WIDTH-13:0]  29 bits  (fe_top.sv:145)
  <- u_itlb.itlb_l2t_vpn  itlb.sv:192  (bind fe_top.sv:771)
itlb_l2t_asid  out  logic [ASID_WIDTH-1:0]  16 bits  (fe_top.sv:146)
  <- u_itlb.itlb_l2t_asid  itlb.sv:193  (bind fe_top.sv:772)
itlb_l2t_vmid  out  logic [VMID_WIDTH-1:0]  14 bits  (fe_top.sv:147)
  <- u_itlb.itlb_l2t_vmid  itlb.sv:194  (bind fe_top.sv:773)
itlb_l2t_v  out  logic  1 bits  (fe_top.sv:148)
  <- u_itlb.itlb_l2t_v  itlb.sv:195  (bind fe_top.sv:774)
itlb_l2t_tag  out  logic [1:0]  2 bits  (fe_top.sv:149)
  <- u_itlb.itlb_l2t_tag  itlb.sv:196  (bind fe_top.sv:775)
itlb_l2t_acc  out  logic [1:0]  2 bits  (fe_top.sv:150)
  <- u_itlb.itlb_l2t_acc  itlb.sv:197  (bind fe_top.sv:776)
itlb_l2t_priv  out  logic [1:0]  2 bits  (fe_top.sv:151)
  <- u_itlb.itlb_l2t_priv  itlb.sv:198  (bind fe_top.sv:777)
l2t_itlb_rsp_val  in   logic  1 bits  (fe_top.sv:152)
  -> u_itlb.l2t_itlb_rsp_val  itlb.sv:199  (bind fe_top.sv:778)
l2t_itlb_tag  in   logic [1:0]  2 bits  (fe_top.sv:153)
  -> u_itlb.l2t_itlb_tag  itlb.sv:200  (bind fe_top.sv:779)
l2t_itlb_status  in   logic [1:0]  2 bits  (fe_top.sv:154)
  -> u_itlb.l2t_itlb_status  itlb.sv:201  (bind fe_top.sv:780)
l2t_itlb_ppn  in   logic [PPN_WIDTH-1:0]  24 bits  (fe_top.sv:155)
  -> u_itlb.l2t_itlb_ppn  itlb.sv:202  (bind fe_top.sv:781)
l2t_itlb_size  in   logic [2:0]  3 bits  (fe_top.sv:156)
  -> u_itlb.l2t_itlb_size  itlb.sv:203  (bind fe_top.sv:782)
l2t_itlb_perm  in   logic [PERM_WIDTH-1:0]  8 bits  (fe_top.sv:157)
  -> u_itlb.l2t_itlb_perm  itlb.sv:204  (bind fe_top.sv:783)
l2t_itlb_pbmt  in   logic [1:0]  2 bits  (fe_top.sv:158)
  -> u_itlb.l2t_itlb_pbmt  itlb.sv:205  (bind fe_top.sv:784)
l2t_itlb_cause  in   logic [CAUSE_WIDTH-1:0]  5 bits  (fe_top.sv:159)
  -> u_itlb.l2t_itlb_cause  itlb.sv:206  (bind fe_top.sv:785)
l2t_itlb_gpa  in   logic [FAULT_GPA_WIDTH-1:0]  56 bits  (fe_top.sv:160)
  -> u_itlb.l2t_itlb_gpa  itlb.sv:207  (bind fe_top.sv:786)
l2t_itlb_gpa_imp  in   logic [1:0]  2 bits  (fe_top.sv:161)
  -> u_itlb.l2t_itlb_gpa_imp  itlb.sv:208  (bind fe_top.sv:787)
```

### 4.8 instruction: the L1I l2-side link (FE-17, FE-21)

Specified by:

- planning/arch/fe_decisions.md FE-17 instruction (line 1385)
- planning/arch/fe_decisions.md FE-21 (lines 1479, 1490)
- planning/arch/pacino_cache.md (lines 383, 554)

```
l1i_mem_a_valid  out  logic  1 bits  (fe_top.sv:167)
  <- u_l1i.mem_a_valid  l1i.sv:72  (bind fe_top.sv:729)
l1i_mem_a_ready  in   logic  1 bits  (fe_top.sv:168)
  -> u_l1i.mem_a_ready  l1i.sv:73  (bind fe_top.sv:730)
l1i_mem_a_opcode  out  logic [2:0]  3 bits  (fe_top.sv:169)
  <- u_l1i.mem_a_opcode  l1i.sv:74  (bind fe_top.sv:731)
l1i_mem_a_param  out  logic [2:0]  3 bits  (fe_top.sv:170)
  <- u_l1i.mem_a_param  l1i.sv:75  (bind fe_top.sv:732)
l1i_mem_a_size  out  logic [2:0]  3 bits  (fe_top.sv:171)
  <- u_l1i.mem_a_size  l1i.sv:76  (bind fe_top.sv:733)
l1i_mem_a_source  out  logic [3:0]  4 bits  (fe_top.sv:172)
  <- u_l1i.mem_a_source  l1i.sv:77  (bind fe_top.sv:734)
l1i_mem_a_address  out  logic [PA_WIDTH-1:0]  36 bits  (fe_top.sv:173)
  <- u_l1i.mem_a_address  l1i.sv:78  (bind fe_top.sv:735)
l1i_mem_a_mask  out  logic [31:0]  32 bits  (fe_top.sv:174)
  <- u_l1i.mem_a_mask  l1i.sv:79  (bind fe_top.sv:736)
l1i_mem_a_data  out  logic [255:0]  256 bits  (fe_top.sv:175)
  <- u_l1i.mem_a_data  l1i.sv:80  (bind fe_top.sv:737)
l1i_mem_a_corrupt  out  logic  1 bits  (fe_top.sv:176)
  <- u_l1i.mem_a_corrupt  l1i.sv:81  (bind fe_top.sv:738)
l1i_mem_d_valid  in   logic  1 bits  (fe_top.sv:177)
  -> u_l1i.mem_d_valid  l1i.sv:82  (bind fe_top.sv:739)
l1i_mem_d_ready  out  logic  1 bits  (fe_top.sv:178)
  <- u_l1i.mem_d_ready  l1i.sv:83  (bind fe_top.sv:740)
l1i_mem_d_opcode  in   logic [2:0]  3 bits  (fe_top.sv:179)
  -> u_l1i.mem_d_opcode  l1i.sv:84  (bind fe_top.sv:741)
l1i_mem_d_param  in   logic [2:0]  3 bits  (fe_top.sv:180)
  -> u_l1i.mem_d_param  l1i.sv:85  (bind fe_top.sv:742)
l1i_mem_d_size  in   logic [2:0]  3 bits  (fe_top.sv:181)
  -> u_l1i.mem_d_size  l1i.sv:86  (bind fe_top.sv:743)
l1i_mem_d_source  in   logic [3:0]  4 bits  (fe_top.sv:182)
  -> u_l1i.mem_d_source  l1i.sv:87  (bind fe_top.sv:744)
l1i_mem_d_sink  in   logic [1:0]  2 bits  (fe_top.sv:183)
  -> u_l1i.mem_d_sink  l1i.sv:88  (bind fe_top.sv:745)
l1i_mem_d_denied  in   logic  1 bits  (fe_top.sv:184)
  -> u_l1i.mem_d_denied  l1i.sv:89  (bind fe_top.sv:746)
l1i_mem_d_data  in   logic [255:0]  256 bits  (fe_top.sv:185)
  -> u_l1i.mem_d_data  l1i.sv:90  (bind fe_top.sv:747)
l1i_mem_d_corrupt  in   logic  1 bits  (fe_top.sv:186)
  -> u_l1i.mem_d_corrupt  l1i.sv:91  (bind fe_top.sv:748)
```

### 4.9 csr: fe_csr_t (FE-20)

Specified by:

- planning/arch/fe_decisions.md FE-20 csr (line 1450)
- planning/arch/csr_decisions.md CSR-6 (line 138)

```
fe_csr  in   fe_csr_t  733 bits  (fe_top.sv:192)
  -> u_itlb.fe_csr  itlb.sv:215  (bind fe_top.sv:788)
```

### 4.10 config: fe_cfg_t (FE-20)

Specified by:

- planning/arch/fe_decisions.md FE-20 config (line 1459)
- planning/arch/csr_decisions.md CSR-6 (line 138)

```
fe_cfg  in   fe_cfg_t  84 bits  (fe_top.sv:199)
  .tage_enable_aging -> u_bpu.tage_enable_aging
      bp_cluster.sv:274  (bind fe_top.sv:482)
  .tage_aging_interval -> u_bpu.tage_aging_interval
      bp_cluster.sv:275  (bind fe_top.sv:483)
  .ittage_enable_aging -> u_bpu.ittage_enable_aging
      bp_cluster.sv:276  (bind fe_top.sv:484)
  .ittage_aging_interval -> u_bpu.ittage_aging_interval
      bp_cluster.sv:277  (bind fe_top.sv:485)
  .sc_enable -> u_bpu.sc_enable
      bp_cluster.sv:278  (bind fe_top.sv:486)
  .sc_enable -> u_ftq.sc_enable
      ftq.sv:183  (bind fe_top.sv:561)
  .ftb_fastpath_en -> u_bpu.ftb_fastpath_en
      bp_cluster.sv:279  (bind fe_top.sv:487)
  .ext_enable -> u_dec.ext_enable
      instr_decoder.sv:95  (bind fe_top.sv:818)
```

### 4.11 maintenance: ITLB invalidate (FE-20)

Specified by:

- planning/arch/fe_decisions.md FE-20 maintenance (line 1472)
- planning/arch/itlb_decisions.md 7 (lines 362-375)

```
bkend_itlb_inv_val  in   logic  1 bits  (fe_top.sv:204)
  -> u_itlb.bkend_itlb_inv_val  itlb.sv:218  (bind fe_top.sv:789)
bkend_itlb_inv_op  in   logic [1:0]  2 bits  (fe_top.sv:205)
  -> u_itlb.bkend_itlb_inv_op  itlb.sv:219  (bind fe_top.sv:790)
bkend_itlb_inv_rs1_nz  in   logic  1 bits  (fe_top.sv:206)
  -> u_itlb.bkend_itlb_inv_rs1_nz  itlb.sv:220  (bind fe_top.sv:791)
bkend_itlb_inv_rs2_nz  in   logic  1 bits  (fe_top.sv:207)
  -> u_itlb.bkend_itlb_inv_rs2_nz  itlb.sv:221  (bind fe_top.sv:792)
bkend_itlb_inv_vpn  in   logic [VA_WIDTH-13:0]  29 bits  (fe_top.sv:208)
  -> u_itlb.bkend_itlb_inv_vpn  itlb.sv:222  (bind fe_top.sv:793)
bkend_itlb_inv_asid  in   logic [ASID_WIDTH-1:0]  16 bits  (fe_top.sv:209)
  -> u_itlb.bkend_itlb_inv_asid  itlb.sv:223  (bind fe_top.sv:794)
bkend_itlb_inv_vmid  in   logic [VMID_WIDTH-1:0]  14 bits  (fe_top.sv:210)
  -> u_itlb.bkend_itlb_inv_vmid  itlb.sv:224  (bind fe_top.sv:795)
```

### 4.12 observation: not in FE-17 or FE-20

Specified by:

- no planning document
- section 8, D5

```
ftq_full  out  logic  1 bits  (fe_top.sv:215)
  <- u_ftq.ftq_full  ftq.sv:281  (bind fe_top.sv:630)
ftq_empty  out  logic  1 bits  (fe_top.sv:216)
  <- u_ftq.ftq_empty  ftq.sv:282  (bind fe_top.sv:631)
```
---

## 5. Unread outputs, member selects and constants

### 5.1 Cluster outputs that end on unread wires

Declared at fe_top.sv:302-317; each is bound to one bp_cluster
output and read by nothing (fe_top.sv:80-83).

```
bpu_ghist_ptr          8 bits  fe_top.sv:305  <- u_bpu.ghist_ptr
                               bp_cluster.sv:266  (bind fe_top.sv:476)
bpu_phist_ptr          5 bits  fe_top.sv:306  <- u_bpu.phist_ptr
                               bp_cluster.sv:267  (bind fe_top.sv:477)
bpu_ghr_buf          256 bits  fe_top.sv:307  <- u_bpu.ghr_buf
                               bp_cluster.sv:270  (bind fe_top.sv:480)
bpu_phr_buf           32 bits  fe_top.sv:308  <- u_bpu.phr_buf
                               bp_cluster.sv:271  (bind fe_top.sv:481)
bpu_tage_upd_rdy_u1    2 bits  fe_top.sv:313  <- u_bpu.tage_upd_rdy_u1
                               bp_cluster.sv:294  (bind fe_top.sv:493)
bpu_ittage_upd_rdy_u1  2 bits  fe_top.sv:315  <- u_bpu.ittage_upd_rdy_u1
                               bp_cluster.sv:297  (bind fe_top.sv:496)
bpu_sc_upd_rdy_u1      2 bits  fe_top.sv:317  <- u_bpu.sc_upd_rdy_u1
                               bp_cluster.sv:300  (bind fe_top.sv:499)
```

The three `_u1` outputs are "update applied" flops, not accept
readies (planning/interfaces/ftq_bpu_interfaces.md 8, notes at
lines 905-907; fe_top.sv:81-83). The history pointers and buffers are
the section 9 outputs of ftq_bpu_interfaces.md (lines 1115-1120);
only the checkpoint pair `ckpt_ghist_ptr` / `ckpt_phist_ptr` has a
consumer, the FTQ (section 3.12).

### 5.2 fe_cfg member selects

`fe_cfg` (fe_cfg_t, csr_pkg.sv:224-232) is not passed whole. Its
members drive existing instance ports by member select
(fe_top.sv:52-59, CSR-6): see section 4.10. `sc_enable` is the one
member with two readers, the cluster and the FTQ (fe_top.sv:486,
561; FE-20 config, planning/arch/fe_decisions.md:1459). `fe_csr`
(fe_csr_t, csr_pkg.sv:236-247) is passed whole to the ITLB
(fe_top.sv:788).

### 5.3 Constant inputs

```
u_bpu.ftb_flush_px        1'b0  bp_cluster.sv:212  (fe_top.sv:453)
u_bpu.ras_flush_val       1'b0  bp_cluster.sv:233  (fe_top.sv:466)
u_bpu.ras_flush_snapshot  '0    bp_cluster.sv:234  (fe_top.sv:467)
                                12 bits, bp_ras_snapshot_t
```

Held inactive: the flush groups are redundant with the RAS restore group
and read by nothing in the RAS (fe_top.sv:84-87;
planning/interfaces/ftq_bpu_interfaces.md 8, lines 966-970;
planning/arch/ras_decisions.md 4.4.2, line 570), and ftb_flush_px for
the same reason (FE-14).

---

## 6. Inside bp_cluster

The cluster is a four-stage pipeline (p0 to p3) with an update stage
u0 and its write u1 (bp_cluster.sv:55-61). The FTQ-facing ports are
grouped in the port list as follows; the predictor instances are at
bp_cluster.sv:1812-2035.

### 6.1 bp_cluster port groups

```
group                                       ports at       spec
P0  prediction request, FTQ -> BPU          bp_cluster.sv:109-112
                                            ftq_bpu 3
P1  initial prediction, BPU -> FTQ          :114-123   ftq_bpu 4
RD  redirects p2, p3                        :125-131   ftq_bpu 6
SL  slot correction p2, p3                  :133-150   ftq_bpu 4a
BK  block-scalar correction p2              :152-160   ftq_bpu 4c
M2  metadata write p2 (tage ittage lp ftb)  :162-175   ftq_bpu 7.1
M3  metadata write p3 (sc)                  :177-182   ftq_bpu 7.2
UP  updates u0: ubtb lp ftb tage ittage sc  :184-224   ftq_bpu 8
RS  RAS restore, commit, flush              :226-234   ftq_bpu 8
RB  history rollback                        :236-263   ftq_bpu 9
HI  history pointer and buffer outputs      :265-271   ftq_bpu 9
CF  configuration inputs                    :273-279   FE-20 config
ST  status: init readies, queue status      :281-300   ftq_bpu 3, 8
```

`ftq_bpu` is planning/interfaces/ftq_bpu_interfaces.md.

### 6.2 Predictor instances

```
inst           module      line  stage
u_bp_history   bp_history  1815  p1 checkpoint write; history
                                 advance per predicted branch
u_ubtb         ubtb        1844  p1 (combinational from the p0 PC,
                                 registered into p1 by the cluster)
u_loop_pred    loop_pred   1861  p1, and the p2 re-read (BP-122)
u_ftb          ftb         1885  p2
u_tage         tage        1935  p2
u_ittage       ittage      1958  p2
u_sc           sc          1985  p3 (indexes at p2, answers at p3)
u_ras          ras         2013  p0 top-of-stack read, p2 push/pop,
                                 p3 repair
```

Stages are bp_cluster.sv:55-61 and the comments above each instance
(bp_cluster.sv:1813, 1839, 1856, 1882, 1933, 1955, 1977, 2009). `ubtb`
is instantiated with `N_SLOTS = NUM_PRED_SLOTS`
(bp_cluster.sv:1844-1846).

### 6.3 Which cluster port groups each predictor serves

```
u_bp_history
  RB  rollback_valid, _ckpt_idx, _corr, _n, _tkn, _pbit
      (bp_cluster.sv:1823-1828; formed at 1370, 1385, rb_corr_mux 1413)
  HI  ghist_ptr, phist_ptr, ckpt_ghist_ptr, ckpt_phist_ptr, ghr_buf,
      phr_buf, bound straight to the cluster ports (1829-1834)
  P1  ckpt_wr_en / ckpt_wr_idx = r_val_p1 / r_idx_p1 (964-965)
  internal: folded -> u_tage, u_ittage; sliced folds -> u_sc
u_ubtb
  P0  pred_pc_p0 = ftq_pred_pc_p0 (1849)
  P1  pred_p1, blk_p1 -> p1_form_comb (779) -> bpu_pred_slot_p1
      (1699), bpu_pred_pft_p1 (953)
  UP  upd_u0 = ubtb_upd_u0 with valid qualified by the resolved type
      (1748-1765)
u_loop_pred
  P0  pred_pc_p0 / pred_valid_p0 (1675, 642)
  P1  pred_p1 -> p1_form_comb (779)
  M2  pred_p2 -> bpu_meta_lp_p2 (1779)
  UP  upd_p0 = lp_upd_p0, upd_valid_p0 = lp_upd_valid_p0 & COND
      (1877-1878, 1678-1679)
  RB  rst_val / rst_idx / rst_ex / rst_tkn / inv_val from the
      rollback (lp_rst_comb 1446; ftq_rollback_slot_ex/_tkn 1462-1463)
u_ftb
  P0  pred_valid_p0 = w_req_val_p0 (635, 1888), pred_pc_p0 (1889)
  SL  p2 slot fields -> p2_class_comb (985), p2_slot_comb (1241),
      bpu_slot_val_p2 (1261)
  RD  p2 redirect -> p2_succ_comb (1107)
  BK  ftb_pft_addr_p2 -> bpu_blk_pft_p2 (1275)
  M2  hit, way, jmp_pos -> bpu_meta_ftb_p2 (1776-1778)
  UP  ftb_upd_* bound by name, valid gated by is_br | is_jmp (1643-1644)
  CF  ftb_fastpath_en (1912)
u_tage
  P0  tage_pred_val_p0 (640), tage_pred_inp_p0 (1666-1667)
  SL/RD  tage_pred_meta_p2 -> p2 direction (p2_class_comb 985)
  M2  tage_pred_meta_p2 -> bpu_meta_tage_p2 (1774)
  UP  tage_upd_val_u0 & COND & tage_upd_rdy (1798-1800), tage_upd_inp_u0
  ST  tage_rdy (1951), tage_pq_not_full, tage_uq_not_full ->
      tage_upd_rdy, tage_upd_rdy_u1 (1944-1946); consumer_ready from
      SC (1585-1586)
  CF  tage_enable_aging, tage_aging_interval (1947-1948)
u_ittage
  P0  ittage_pred_val_p0 (641), ittage_pred_inp_p0 (1668-1669)
  RD  ittage target -> p2_succ_comb (1107)
  M2  ittage_pred_meta_p2 -> bpu_meta_ittage_p2 (1775)
  UP  ittage_upd_val_u0 & indirect & ittage_upd_rdy (1801-1803)
  ST  ittage_rdy (1973), ittage_pq_not_full, ittage_uq_not_full ->
      ittage_upd_rdy, ittage_upd_rdy_u1 (1967-1969)
  CF  ittage_enable_aging, ittage_aging_interval (1970-1971)
u_sc
  takes the TAGE p2 result (1988-1989), PC and folds staged to p2
  SL  p3 direction -> p3_slot_comb (1340), bpu_slot_val_p3 (1360)
  RD  p3 redirect -> p3_redir_comb (1289)
  M3  sc_pred_meta_p3 -> bpu_meta_sc_p3 (1791)
  UP  sc_upd_val_u0 & COND & queue room & sc_enable (1804-1807),
      sc_upd_inp_u0; arbiter sc_arb_comb (1559)
  ST  sc_ready (2005); sc_uq_not_full and sc_upd_rdy formed at
      1594-1596 from 2000-2001; sc_upd_rdy_u1 (1999)
  CF  sc_enable (2004)
u_ras
  P1  top of stack at p0 -> p1 target of a return (p1_form_comb);
      bpu_pred_ras_p1 = the p2 snapshot of the last slot (961)
  BK  bpu_blk_ras_p2 (1274)
  RD  p2 pop address -> p2_succ_comb (1107); p3 repair (1728-1730)
  RS  ras_restore_val gated by the cluster's own redirect (1402),
      ras_restore_snapshot, ras_commit_val gated by call/return type
      (1649-1653), commit br_type / ret_addr / snapshot, flush
      (2026-2034)
```

The p0 request reaches the table predictors only when both TAGE and
ITTAGE prediction queues can accept it: `w_req_val_p0 =
ftq_pred_val_p0 & w_pq_rdy_p0`, with `w_pq_rdy_p0 = tage_pq_not_full &
ittage_pq_not_full` (bp_cluster.sv:634-635). The update fan-out by
resolved branch type is rederived from the uBTB payload of each
channel (bp_cluster.sv:1732-1746, upd_br_type at 1609-1618).

---

## 7. The walker beside fe_top in the testbench

`fe_top` has no walker; the testbench instantiates one beside it
(FE-17 translation, planning/arch/fe_decisions.md:1391; MMU-1a). The
shared model rtl/core/frontend/fe_top/tb/models/fe_tb_dut.svh holds
both, included in module tb by examples/fe_demo/tb/tb_fe_demo.sv:57
and by tb_fe_top.

```
fe_top dut (.*)     fe_tb_dut.svh:101  every fe_top port, by name, to
                                       the tb nets of lines 27-99
ptw u_ptw (.*)      fe_tb_dut.svh:122  rtl/mmu/ptw/rtl/ptw.sv:155
```

What connects them, all by `.*` name matching:

```
translation group (itlb_l2tlb_interfaces.md 2)
  tb nets fe_tb_dut.svh:45-61 and 106-107
  dut.itlb_l2t_*  (fe_top.sv:143-151)  -> u_ptw ports ptw.sv:170-178
  u_ptw.l2t_itlb_* (ptw.sv:179-188)   -> dut ports fe_top.sv:152-161
walker memory port (planning/interfaces/ptw_mem_interfaces.md 3)
  tb nets fe_tb_dut.svh:108-116
  u_ptw.ptw_mem_req_* (ptw.sv:191-196) -> memory model
  memory model -> u_ptw.mem_ptw_rsp_* (ptw.sv:197-199)
  model: fe_tb_mem.svh:106-226 (initial ptw_mem at 155; ready
  pattern at 224)
walker CSR group (MMU-24a)
  ptw_csr  fe_tb_dut.svh:117 -> u_ptw.ptw_csr ptw.sv:206
  driven by csr_sync, fe_tb_csr.svh:29 (csr_tb_pkg::pack_ptw_csr)
the L1I mem link (section 4.8)
  answered by the same memory model, fe_tb_mem.svh:35-103
  (a_ready at 35, the D-channel responder initial tl_mem at 37)
```

The walker and the L1I read one memory image (fe_tb_mem.svh; FE-21,
planning/arch/fe_decisions.md:1490, ptw_mem_interfaces.md WM-10, line
143). `fe_csr` and `ptw_csr` are packed from the one csr_tb_pkg shadow
(fe_tb_dut.svh:119-121).

---

## 8. Disagreements between the RTL and the planning documents

The RTL is what sections 2 to 7 record.

```
D1  FTB update port count.
    RTL: 15 payload ports plus the valid (fe_top.sv:274-289;
    bp_cluster.sv:195-211). The comments fe_top.sv:69, fe_top.sv:273,
    bp_cluster.sv:194 and ftq.sv:200 say 14.
    Plan: ftq_bpu_interfaces.md 8 says 15 (lines 883, 895-900; "This
    read 14"). The plan agrees with the ports; the four RTL comments
    are stale since BP-121 added ftb_upd_jmp_rvc_u0.

D2  ITTAGE update payload name.
    RTL: ittage_upd_inp_u0 (fe_top.sv:298; bp_cluster.sv:219-220;
    ftq port bound at fe_top.sv:568).
    Plan: ftq_bpu_interfaces.md 8 table, line 885, "ittage_upd_inp".

D3  TAGE and ITTAGE queue status port names (TD#49).
    RTL: tage.sv:47-48 and ittage.sv:46-47 declare <p>_pq_not_full and
    <p>_uq_not_full; bp_cluster.sv:1945-1946 and 1968-1969 bind them;
    bp_cluster.sv:286-288 says TD#49 was applied by BP-132.
    Plan: ftq_bpu_interfaces.md 8, lines 947-956, says tage and
    ittage declare pq_not_full and upd_rdy without prefix and that
    TD#49 is not yet applied. The cluster boundary names (tage_upd_rdy,
    ittage_upd_rdy) agree with lines 938-939.

D4  uBTB update port at the cluster boundary.
    RTL: ubtb_upd_u0, ubtb_upd_t [NUM_PRED_SLOTS-1:0], 352 bits
    (bp_cluster.sv:186; fe_top.sv:292).
    Plan: ftq_bpu_interfaces.md 8 (line 881) names only the predictor
    port upd_u0; no planning document names the boundary port.

D5  Observation outputs.
    RTL: ftq_full and ftq_empty are fe_top outputs (fe_top.sv:212-216).
    Plan: in no FE-17 or FE-20 group (fe_decisions.md:1378, 1445) and
    named by no interface document.

D6  Decode outputs.
    RTL: decode_bundle, vec_decode_bundle, is_vector, pd_out,
    vtype_hazard (fe_top.sv:103-107), from u_dec (fe_top.sv:820-824).
    Plan: FE-17 backend (fe_decisions.md:1410) says "decode to rename
    and dispatch" with no port list; no interface document names
    decode_bundle, vec_decode_bundle or pd_out (is_vector and
    vtype_hazard appear in dcd_decisions.md:612 and 262).

D7  The instruction group.
    RTL: fe_top.sv:30-32 lists "instruction" as a boundary group, the
    20 l1i_mem_* ports (fe_top.sv:167-186).
    Plan: FE-17 (fe_decisions.md:1378, 1385) counts two groups and
    says the instruction path is not a boundary group, its `mem` port
    being a topology edge; FE-21 (fe_decisions.md:1479, 1490) says the
    port leaves the top as a boundary edge. The ports are the same;
    the documents count them differently.

D8  The config group comment.
    RTL: fe_top.sv:52-54 says "see Results Capture for the ones FE-20
    does not list".
    Plan: FE-20 config (fe_decisions.md:1459-1468) now lists every
    member fe_top distributes (sc_enable, ftb_fastpath_en, the four
    aging inputs, ext_enable); the comment refers to the text before
    the BP-118 correction.

D9  Walker-side labels.
    RTL: the server of the translation group is the page table walker
    (fe_tb_dut.svh:122; fe_top.sv:33-36).
    Plan: itlb_l2tlb_interfaces.md 2 (lines 44-63) labels the far end
    "L2TLB" while its line 22 says the server is the walker. Naming
    only; ports and widths agree.
```

No width disagreement was found: every port width in
ftq_bpu_interfaces.md 3 and 8, ftq_ifu_interfaces.md 4 to 6,
l1i_ifu_interfaces.md 4.1, 5.1, 10.1 and 11.2,
itlb_ifu_interfaces.md 2, ifu_ibuf_interfaces.md 2,
ftq_backend_interfaces.md 4 to 6, itlb_l2tlb_interfaces.md 2 and
ptw_mem_interfaces.md 3 that was compared resolves to the elaborated
width recorded here.
