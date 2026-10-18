#! /usr/bin/env bash

# No longer used, now attaching files to the PA session
#echo "Documents included: " > cntx.md
#echo "planning/BLOG_GENERATION_PROCESS.md" >> cntx.md


ARCH=planning/arch
INTF=planning/interfaces

DEST=~/Downloads/context
mkdir -p ~/Downloads/context
#rm -f ~/Downloads/context/*

cp pa_handoffs/session_handoff-068.md $DEST
cp pa_handoffs/session_handoff-069.md $DEST
cp prompts/INFRA-012.md $DEST
cp prompts/TOOLS-003.md $DEST
cp prompts/TOOLS-004.md $DEST
cp prompts/TOOLS-005.md $DEST
cp pa_handoffs/session_handoff-070.md $DEST
cp pa_handoffs/session_handoff-071.md $DEST
cp pa_handoffs/session_handoff-072.md $DEST
cp pa_handoffs/session_handoff-073.md $DEST
