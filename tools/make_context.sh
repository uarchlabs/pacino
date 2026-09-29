#! /usr/bin/env bash

# No longer used, now attaching files to the PA session
#echo "Documents included: " > cntx.md
#echo "planning/BLOG_GENERATION_PROCESS.md" >> cntx.md


ARCH=planning/arch
INTF=planning/interfaces

DEST=~/Downloads/context
mkdir -p ~/Downloads/context
#rm -f ~/Downloads/context/*

cp pa_handoffs/session_handoff-067.md $DEST
cp pa_handoffs/session_handoff-068.md $DEST
cp prompts/BP-098.md $DEST
cp prompts/BP-099.md $DEST
cp prompts/BP-100.md $DEST
cp prompts/BP-101.md $DEST
cp prompts/BP-102.md $DEST
cp prompts/BP-103.md $DEST
cp prompts/BP-104.md $DEST
cp prompts/BP-105.md $DEST
cp prompts/BP-106.md $DEST
cp prompts/BP-107.md $DEST
cp prompts/BP-108.md $DEST
cp ia_context/ia_handoffs/ia_session_handoff-001.md $DEST
cp ia_context/ia_handoffs/ia_session_handoff-002.md $DEST
cp ia_context/ia_handoffs/ia_session_handoff-003.md $DEST
cp ia_context/ia_handoffs/ia_session_handoff-004.md $DEST
cp ia_context/ia_handoffs/ia_session_handoff-005.md $DEST
cp misc/pa_session_map.md $DEST
cp planning/CLOSED_TECH_DEBT.md $DEST
cp planning/PROJECT_STATUS.md $DEST
cp planning/BLOG_GENERATION_PROCESS.md $DEST
cp blogs/BLOG_bpu_20_cluster_simulation.md $DEST
