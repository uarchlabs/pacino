# ittage_table Hash Rules
```
 FILE:    ittage_table_hash_rules.md
 SOURCE:  various
 STATUS:  NEEDS RE-VERIFICATION
 UPDATED: 2026-04-27
 CONTACT: Jeff Nye
```

---

## Scope

Define the hash functions used locally within each ittage_table
instance to derive index_hash_p0 and tag_hash_p0 for IT1-IT5.
There is no IT0 -- ITTAGE has no base table and no direct PC
index path.

---

## Input Ports Associated with Hashing Functions for IT1-IT5

Each ittage_table generates four hashed values: an index hash
for prediction slot 0 and slot 1, and a tag hash for prediction
slot 0 and slot 1.

There are two PCs supplied by ittage_pred_inp_p0:
  ittage_pred_inp_p0[0].pc
  ittage_pred_inp_p0[1].pc
These are inputs to both the index and tag hash functions.

The primary input struct bp_folded_hist_t folded_hist provides
the folded history buses used for both the index and tag hashes.
Each table, indicated by the module parameter THIS_TABLE, selects
one of the five groups in folded_hist. There are 3 buses in each
group. The fh bus is used by the index hash function. The fh1 and
fh2 buses are used by the tag hash function.

The buses are named as it_tN_idx_fh, it_tN_tag_fh1, it_tN_tag_fh2,
where tN is t1, t2, t3, t4, or t5.

The width parameters for these buses are similarly named:
  IT_TBL_FH[N], IT_TBL_FH1[N], IT_TBL_FH2[N]
where N is the value of THIS_TABLE (1 through 5).

---

## Relevant Parameters

INST_OFFSET is a global parameter which defines the right shift
of the PC address. This shift is 2 at present.

THIS_INDEX_BITS is a module level parameter that defines the
table-specific width of the index.

THIS_TAG_BITS is a module level parameter that defines the
table-specific width of the tag field.

THIS_TABLE is a module level parameter that defines the table
component id. Valid range is 1 through 5.

VA_WIDTH is a global parameter that sets the MSB of the PC.
The PC is zero indexed.

---

## Hashing Functions for IT1-IT5

### Index Hash Function

The index hash function takes the PC and the idx folded history
as inputs. The outputs are the slot 0 and slot 1 index hashes.

Output width: THIS_INDEX_BITS.
PC input width: VA_WIDTH.
fh input width: IT_TBL_FH[THIS_TABLE].

The hashing operation is:

```
tmpA   = (PC >> INST_OFFSET) ^ fh
output = tmpA[THIS_INDEX_BITS-1:0]
```

There are two instances of this function, one for slot 0 and
one for slot 1, producing idx_hash_p0[0] and idx_hash_p0[1].

### Tag Hash Function

The tag hash function takes the PC and two tag folded histories
as inputs. The outputs are the slot 0 and slot 1 tag hashes.

Output width: THIS_TAG_BITS.
PC input width: VA_WIDTH.
fh1 input width: IT_TBL_FH1[THIS_TABLE].
fh2 input width: IT_TBL_FH2[THIS_TABLE].

The hashing operation is:

```
tmpA   = PC >> THIS_INDEX_BITS
tmpB   = tmpA ^ fh1 ^ (fh2 << 1)
output = tmpB[THIS_TAG_BITS-1:0]
```

There are two instances of this function, one for slot 0 and
one for slot 1, producing tag_hash_p0[0] and tag_hash_p0[1].

---

## No IT0 Hash

There is no IT0 in ITTAGE. There is no direct PC index path
and no base table. All five active tables (IT1-IT5) use the
hash functions defined above. There is no equivalent of the
TAGE T0 pc[12:2] direct index.

