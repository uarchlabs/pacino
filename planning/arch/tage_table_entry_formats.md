<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->

# TAGE table entry formats
```
 FILE:    tage_table_entry_formats.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-09-19
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

CTR is a 3-bit direction counter; its MSB is the predicted
direction (tage_cntrl_decisions.md, CTR Encoding). It steps toward
the resolved direction. It has no null state and plays no part in
choosing an allocation candidate, which is chosen by u_eff == 0
(tage_cntrl_alloc_rules.md). This read that CTR "encodes confidence"
and that an entry whose CTR "reaches null on misprediction" becomes
a re-allocation candidate, which is the ITTAGE target rule, not
TAGE's. Session-071.

### Maximum field widths

The maximum range for each field is stored in a parameter. These parameters
are found in `bp_defines_pkg.sv`

`TAGE_MAX_TAG_WIDTH`
`TAGE_MAX_EPC_WIDTH`
`TAGE_MAX_USE_WIDTH`
`TAGE_MAX_CTR_WIDTH`
`TAGE_MAX_VAL_WIDTH`

