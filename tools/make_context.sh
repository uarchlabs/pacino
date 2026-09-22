#! /usr/bin/env bash

# No longer used, now attaching files to the PA session
#echo "Documents included: " > cntx.md
#echo "planning/BLOG_GENERATION_PROCESS.md" >> cntx.md


DEST=~/Downloads/context
mkdir -p ~/Downloads/context
rm -f ~/Downloads/context/*

cp misc/pa_session_map.md  $DEST
cp blogs/BLOG_bpu_15_specification_under_test.md $DEST
cp blogs/BLOG_bpu_16_external_anchors.md $DEST
cp planning/BLOG_GENERATION_PROCESS.md $DEST
cp pa_handoffs/session_handoff-056.md $DEST
cp pa_handoffs/session_handoff-057.md $DEST
cp pa_handoffs/session_handoff-058.md $DEST
cp pa_handoffs/session_handoff-059.md $DEST
cp pa_handoffs/session_handoff-060.md $DEST
cp prompts/BP-075.md $DEST
cp prompts/BP-075a.md $DEST
cp prompts/BP-076.md $DEST
cp prompts/BP-077.md $DEST
cp prompts/BP-078.md $DEST
cp prompts/BP-079.md $DEST
cp prompts/BP-080.md $DEST
