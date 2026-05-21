
# TAGE Manual Testbench Decisions
```
 FILE:    planning/tage_mtb_decisions.md
 SOURCE:  manual edit
 STATUS:  DRAFT
 UPDATED: 2026-05-20
 CONTACT: Jeff Nye
```

## Purpose

This document is the TAGE specialization for the general
`planning/manual_tb_decisions.md`  testbench guidance file.

## RAM access paths

Hierarchical access to individual RAMs is through this path:

```
u_dut.u_tage_bim.u_ram_s0.mem[bank][row]
```

## RAM Entry field format

There are two formats for RAM entries depending on which table. The
format for T0 and the other tables is found in:
```
planning/interfaces/tage_table_interfaces.md
```


## DUT inputs driven by constants

Which DUT ports get tieoffs and what values

```
tage_enable_aging   = 1'b0;
tage_aging_interval = 32'b0;
folded_hist         = '0;
consumer_ready      = 1'b1;
```

## FAST_INIT plus args name is:
The plusarg name: +TAGE_FAST_INIT=1


## Required tasks

Two tasks will be required to set fields within the table RAMs.
```
task automatic tage_ram_write(
  input int              tbl,
  input int              idx,
  input tage_ram_entry_t entry
);

task automatic tage_ram_read(
  input  int              tbl,
  input  int              idx,
  output tage_ram_entry_t entry
);
```

A task to set the fields within tage_pred_inp_t

```
task automatic tage_set_pred_inp(...)
```

A task to set the fields within tage_upd_inp_t

```
task automatic tage_set_upd_inp(...)
```

A task to compare fields within tage_pred_inp_t
A task to compare fields within tage_upd_inp_t


A task to perform an update request
A task to perform a  prediction request
A task to perform a round trip test


## TAGE related planning files

Not all of these files will be required

```
planning/arch/tage_cntrl_alloc_rules.md
planning/arch/tage_cntrl_ctr_update_rules.md
planning/arch/tage_cntrl_decisions.md
planning/arch/tage_cntrl_uaon_update_rules.md
planning/arch/tage_cntrl_use_update_rules.md
planning/arch/tage_table_hash_rules.md

planning/interfaces/tage_interfaces.md
planning/interfaces/tage_table_interfaces.md

planning/testbenches/manual_tb_decisions.md  
planning/testbenches/tage_mtb_decisions.md   (this file)

planning/verification/tage_coverage_plan.md

```
