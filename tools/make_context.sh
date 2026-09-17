#! /usr/bin/env bash

# No longer used, now attaching files to the PA session
#echo "Documents included: " > cntx.md
#echo "planning/BLOG_GENERATION_PROCESS.md" >> cntx.md


DEST=~/Downloads/context
mkdir -p ~/Downloads/context
rm -f ~/Downloads/context/*

cp planning/arch/itlb_decisions.md $DEST
cp planning/arch/mmu_decisions.md $DEST
cp planning/arch/ifu_decisions.md $DEST
cp planning/arch/ibuf_decisions.md $DEST
cp planning/arch/dcd_decisions.md $DEST
cp planning/interfaces/ifu_ibuf_interfaces.md $DEST
cp planning/interfaces/itlb_ifu_interfaces.md $DEST
cp planning/interfaces/itlb_l2tlb_interfaces.md $DEST
