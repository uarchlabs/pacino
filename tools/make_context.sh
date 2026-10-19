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

#cp $HOFF/session_handoff-068.md $DEST
#cp $HOFF/session_handoff-069.md $DEST
#cp $HOFF/session_handoff-070.md $DEST
#cp $HOFF/session_handoff-071.md $DEST
#cp $HOFF/session_handoff-072.md $DEST
#cp $HOFF/session_handoff-073.md $DEST
cp $HOFF/session_handoff-074.md $DEST
cp $HOFF/session_handoff-075.md $DEST
cp $HOFF/session_handoff-076.md $DEST
cp $HOFF/session_handoff-077.md $DEST
cp $HOFF/session_handoff-078.md $DEST
#cp $HOFF/session_handoff-079.md $DEST
#cp $HOFF/session_handoff-080.md $DEST
#cp prompts/TOOLS-006.md c/
#
#cp prompts/BP-109.md c/
#cp prompts/BP-110.md c/
#cp prompts/BP-111.md c/
#cp prompts/BP-112.md c/
#cp prompts/BP-113.md c/
#cp prompts/BP-114.md c/
cp planning/CLOSED_TECH_DEBT.md c/
cp misc/pa_session_map.md c/
#cp blogs/BLOG_fetch_2_ftq_rtl.md c/
