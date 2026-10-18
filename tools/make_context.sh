#! /usr/bin/env bash

# No longer used, now attaching files to the PA session
#echo "Documents included: " > cntx.md
#echo "planning/BLOG_GENERATION_PROCESS.md" >> cntx.md


ARCH=planning/arch
INTF=planning/interfaces
HOFF=pa_handoffs
DEST=~/Downloads/context
mkdir -p ~/Downloads/context
#rm -f ~/Downloads/context/*

cp $HOFF/session_handoff-068.md $DEST
cp $HOFF/session_handoff-069.md $DEST
cp $HOFF/session_handoff-070.md $DEST
cp $HOFF/session_handoff-071.md $DEST
cp $HOFF/session_handoff-072.md $DEST
cp $HOFF/session_handoff-073.md $DEST
cp $HOFF/session_handoff-074.md $DEST
cp $HOFF/session_handoff-075.md $DEST
cp $HOFF/session_handoff-076.md $DEST
cp $HOFF/session_handoff-077.md $DEST
cp $HOFF/session_handoff-078.md $DEST
cp $HOFF/session_handoff-079.md $DEST
cp $HOFF/session_handoff-080.md $DEST
