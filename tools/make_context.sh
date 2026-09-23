#! /usr/bin/env bash

# No longer used, now attaching files to the PA session
#echo "Documents included: " > cntx.md
#echo "planning/BLOG_GENERATION_PROCESS.md" >> cntx.md


DEST=~/Downloads/context
mkdir -p ~/Downloads/context
rm -f ~/Downloads/context/*

cp prompts/BP-082.md $DEST
cp prompts/BP-083.md $DEST
cp prompts/BP-084.md $DEST
cp prompts/BP-085.md $DEST
cp prompts/BP-086.md $DEST
cp prompts/BP-087.md $DEST
cp prompts/BP-088.md $DEST
cp prompts/BP-089.md $DEST
cp prompts/BP-090.md $DEST

cp planning/interfaces/bpu_port_inventory.md $DEST
cp planning/interfaces/ftq_bpu_interfaces.md $DEST
cp planning/interfaces/ubtb_interfaces.md $DEST

