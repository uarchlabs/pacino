<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

# TAGE table entry formats
```
 FILE:    tage_table_entry_formats.md
 SOURCE:  
 STATUS:  COMPLETE
 UPDATED: 2026-06-10
 CONTACT: Jeff Nye
```

---

# Scope

This describes the field ordering for tables in TAGE.

# Entry Format

## T0 Table Entry

The T0 table contains a single CTR field. The field width is specifed
by an arrayed parameter `TAGE_TBL_CTR[0]`

## T1-T4 Table Entry

The ordering of the fields in the tagged TAGE tables is shown:

```
MSB               LSB
TAG EPC USE CTR VALID
```

Field widths for EPC, USE, and CTR are defined by parameters 
found in `bp_defines_pkg.sv`

The VALID bit is always 1 bit.

The remaining fields have table specific parameters selected
from the named parameter array. [t] indicates the table, T0-T4.

The fields are listed from LSB to MSB
```
VALID  : 1 bit
CTR    : `TAGE_TBL_CTR[t]`
USE    : `TAGE_TBL_USE[t]`
EPC    : `TAGE_TBL_EPC[t]`
TAG    : `TAGE_TBL_TAG[t]`

### CTR field usage in TAGE

CTR encodes confidence in the predicted direction. CTR is incremented
on correct prediction and decremented on misprediction. When CTR
reaches null on misprediction the entry is now a candidate for re-allocation.

### Maximum field widths

The maximum range for each field is stored in a parameter. These parameters
are found in `bp_defines_pkg.sv`

`TAGE_MAX_TAG_WIDTH`
`TAGE_MAX_EPC_WIDTH`
`TAGE_MAX_USE_WIDTH`
`TAGE_MAX_CTR_WIDTH`
`TAGE_MAX_VAL_WIDTH`

