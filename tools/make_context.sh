#! /usr/bin/env bash

# No longer used, now attaching files to the PA session
#echo "Documents included: " > cntx.md
#echo "planning/BLOG_GENERATION_PROCESS.md" >> cntx.md


ARCH=planning/arch
INTF=planning/interfaces

DEST=~/Downloads/context
mkdir -p ~/Downloads/context
#rm -f ~/Downloads/context/*

cp $ARCH/ifu_decisions.md $DEST
cp $INTF/ifu_ibuf_interfaces.md $DEST
cp $INTF/ftq_backend_interfaces.md $DEST
