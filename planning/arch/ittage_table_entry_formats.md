<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# ITTAGE table entry formats
```
 FILE:    ittage_table_entry_formats.md
 SOURCE:  
 STATUS:  COMPLETE
 UPDATED: 2026-06-10
 CONTACT: Jeff Nye
```

---

# Scope

This describes the field ordering for tables in ITTAGE.

# Entry Format

## IT0

There is no IT0 entry format. ITTAGE has no base table.

## IT1-IT5 Table Entry

The ordering of the fields in the tagged ITTAGE tables is 
show

```
MSB                      LSB
<tag>  TGT EPC USE CTR VALID


Field widths for EPC, USE, CTR, TGT, and VALID 
are defined by parameters found in `bp_defines_pkg.sv`

The VALID bit is always 1 bit.

The remaining fields have table specific parameters selected
from the named parameter array. [t] indicates the table, IT0-IT5.

Only t=1-5 is actually used. The IT0 position is a placeholder 
for consistent parameter array semantics.

The fields are listed from LSB to MSB
```
VALID  : 1 bit
CTR    : `IT_TBL_CTR[t]`
USE    : `IT_TBL_USE[t]`
EPC    : `IT_TBL_EPC[t]`
TGT    : `IT_TBL_TGT_WIDTH[t]`
TAG    : `IT_TBL_TAG[t]`

### TAG field construction

The TAG width is specified by `IT_TBL_TGT_WIDTH`. This is extracted
from the virtual address beginning with bit 1. Bit 0 is not used
and not stored.

### CTR field usage in ITTAGE

CTR encodes confidence in the stored target. CTR is incremented
on correct prediction and decremented on misprediction. When CTR
reaches null on misprediction, the target field is replaced with
the resolved target. 

In ITTAGE CTR is not a direction predictor as it is in TAGE.

### Maximum field widths

The maximum range for each field is stored in a parameter. These parameters
are found in `bp_defines_pkg.sv`

`IT_MAX_TAG_WIDTH`
`IT_MAX_TGT_WIDTH`
`IT_MAX_EPC_WIDTH`
`IT_MAX_USE_WIDTH`
`IT_MAX_CTR_WIDTH`
`IT_MAX_VAL_WIDTH`
