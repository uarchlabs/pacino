#! /usr/bin/env bash

# No longer used, now attaching files to the PA session
#echo "Documents included: " > cntx.md
#echo "planning/BLOG_GENERATION_PROCESS.md" >> cntx.md


ARCH=planning/arch
INTF=planning/interfaces

DEST=~/Downloads/context
mkdir -p ~/Downloads/context
#rm -f ~/Downloads/context/*

cp $ARCH/ftq_decisions.md $DEST
cp $INTF/ftq_ifu_interfaces.md $DEST
cp ./rtl/core/frontend/ftq/rtl/ftq.sv $DEST
#cp planning/BLOG_GENERATION_PROCESS.md $DEST
#cp misc/pa_session_map.md $DEST
#cp pa_handoffs/session_handoff-064.md $DEST
#cp pa_handoffs/session_handoff-065.md $DEST
#cp pa_handoffs/session_handoff-066.md $DEST
#cp pa_handoffs/session_handoff-067.md $DEST
#cp prompts/BP-091.md $DEST
#cp prompts/BP-092.md $DEST
#cp prompts/BP-092a.md $DEST
#cp prompts/BP-093.md $DEST
#cp prompts/BP-094.md $DEST
#cp prompts/BP-095.md $DEST
#cp prompts/BP-096.md $DEST
#cp prompts/BP-097.md $DEST
#cp prompts/INFRA-012.md $DEST
#cp planning/PROJECT_STATUS.md $DEST
#cp planning/CLOSED_TECH_DEBT.md $DEST
#cp blogs/BLOG_bpu_16_external_anchors.md  $DEST
#cp blogs/BLOG_bpu_19_bp_cluster_build.md  $DEST
