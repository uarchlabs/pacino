<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# ITTAGE table entry formats
```
 FILE:    ittage_table_entry_formats.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-09-22
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
TAG  TGT EPC USE CTR VALID
```

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
```

### TAG field

The TAG width is specified by `IT_TBL_TAG[t]`. This document does
not define the tag's VALUE: it is tag_hash_p0, computed inside
ittage_table from the PC and two folded histories
(ittage_table_hash_rules.md, Tag Hash Function), and ittage_cntrl
captures it into ittage_alc_tag at predict time.

This read that the tag "is extracted from the virtual address
beginning with bit 1", a second and different derivation: the
hash shifts the PC by THIS_INDEX_BITS and XORs fh1 and fh2 into
it. The hash rules are the sole home for the derivation; the
heading was also duplicated. Session-072.

### CTR field usage in ITTAGE

CTR encodes confidence in the stored target. CTR is incremented
on correct prediction and decremented on misprediction. When CTR
reaches null on misprediction, the target field is replaced with
the resolved target. 

In ITTAGE CTR is not a direction predictor as it is in TAGE.

### TGT field

The TGT width is `IT_TBL_TGT_WIDTH[t]`, 40 for every tagged table.
THE FIELD HOLDS VA[40:1]. Bit 0 is not stored because it is always
zero at 2-byte granularity, and the reconstruction is
`{stored, 1'b0}`. NO BITS ARE INFERRED: there is no sign or zero
extension anywhere in the path.

RULED session-073 (Jeff), raised by BP-109 as TD#132. The field was
38 bits, pinned session-070, with bits 40:39 supplied by extension.
No extension rule is correct for both a V=1 guest physical address
(zero extended, bit 38 significant) and a V=0 Sv39 kernel address
(bits 40:39 set), and a wrong entry cannot be corrected by any
update because the update writes back the bits the entry already
holds. Widening costs 2 bits x 2048 entries x the TWO PER-SLOT RAM
COPIES (u_ram_s0, u_ram_s1) = 8,192 bits; the array goes 226,304 ->
234,496 bits, measured by BP-111. IT_TBL_BANKS divides a copy and
does not duplicate it, so it is not the factor here.
misc/prop1.md records the alternatives that were rejected.
ftq_bpu_interfaces.md 5.2 is the reconstruction's home.

### Maximum field widths

The maximum range for each field is stored in a parameter. These parameters
are found in `bp_defines_pkg.sv`

`IT_MAX_TAG_WIDTH`
`IT_MAX_TGT_WIDTH`
`IT_MAX_EPC_WIDTH`
`IT_MAX_USE_WIDTH`
`IT_MAX_CTR_WIDTH`
`IT_MAX_VAL_WIDTH`
