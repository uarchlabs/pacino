# tage_table Hash Rules
```
 FILE:    tage_table_hash_rules.md 
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-04-06
 CONTACT: Jeff Nye
```

---

## Scope

Define the hash functions used locally within each tage_table instance 
to derive index_hash_p0 and tag_hash_p0 for T1-T4, replacing the removed 
inputs that were previously sourced from tage_cntrl. T0 is excluded — it 
uses direct PC bits, no hash.

---

## Input ports associated with hashing functions for T1-TN

Each tage_table generates four hashed values. A index hash for
prediction slot 0 and slot 1, and a tag hash for prediction slot 0
and slot 1.

There are two PCs supplied by the tage_pred_inp_p0.
These are tage_pred_inp_p0[0].pc or tage_pred_inp_p0[1].pc these
are inputs to the index and tag hash functions. 

The primary input struct bp_folded_hist_t folded_hist provides
the folded history buses used for both the index and tag hashes.

Each table, indicated by the module parameter THIS_TABLE selects
one of the four groups in folded_hist. There are 3 buses in each
of the groups.  The fh bus is used for index hashing function.
The fh1 and fh2 buses are used by the tag hashing function.

The buses are named as tage_tN_idx_fh,tage_tN_tag_fh1,tage_tN_tag_fh2,
where tN is either t1, t2, t3, t4.

The width parameters for these buses are similarly named
TAGE_TN_FH TAGE_TN_FH1 TAGE_TN_FH2, again TN is T1, T2, T3, T4

---

## Relevant parameters

INST_OFFSET is a global parameter which defines the left shift of
the pc address, this shift is 2 at present.

THIS_INDEX_BITS is a module level parameter that defines the table
specific width of the index 

THIS_TAG_BITS is a module level parameter that defines the table
specific width of the tag field 

THIS_TABLE is a module level parameter that defines the table component
id, at present 1,2,3,4.

VA_WIDTH is a global parameter that sets the MSB of the PC. The PC
is zero indexed.

## Hashing functions for T1-TN

### Index hash function

Then index hash functions take the PC and the idx folded hash as inputs,
the outputs are the slot 0 and slot 1 index hashes.

The width of the output is set by module parameter THIS_INDEX_BITS.

The width of the PC input global parameter VA_WIDTH
The width of the fh input is set by the table specific parameter
TAGE_TN_FH, where N is determined by the value of module parameter THIS_TABLE

The hashing operation is 

tmpA = (PC >> INST_OFFSET) ^ fh
output = tmpA[THIS_INDEX_BITS-1:0]

There are two instances of this function, creating two indexes, one
for slot 0 and one for slot 1.

### Tag hash function

Then tag hash functions take the PC and the tag folded hashes as inputs,
the outputs are the slot 0 and slot 1 tag hashes. There are two folded
hash inputs fh1 fh2.

The width of the output is set by module parameter THIS_TAG_BITS.

The width of the PC input global parameter VA_WIDTH

The width of the fh1 input is set by the table specific parameter
TAGE_TN_FH1, where N is determined by the value of module parameter THIS_TABLE

The width of the fh2 input is set by the table specific parameter
TAGE_TN_FH2, where N is determined by the value of module parameter THIS_TABLE

The hashing operation is 

tmpA = PC >>  THIS_INDEX_BITS
tmpB = tmpA ^ fh1 ^ (fh2 << 1)
output = tmpB[THIS_TAG_BITS-1:0]

There are two instances of this function, creating two tags, one
for slot 0 and one for slot 1.


## Hashing functions for T0

There are no hashing operations for T0. The indexes for T0 are derived 
from the PC inputs,

tage_pred_inp_p0[0].pc[12:2]
tage_pred_inp_p0[1].pc[12:2]

There is no tag in T0 and so no tag hash operation.

