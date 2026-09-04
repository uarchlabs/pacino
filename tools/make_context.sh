#! /usr/bin/env bash

# No longer used, now attaching files to the PA session
#echo "Documents included: " > cntx.md
#echo "planning/BLOG_GENERATION_PROCESS.md" >> cntx.md


DEST=~/Downloads/context
mkdir -p ~/Downloads/context
rm -f ~/Downloads/context/*

cp planning/BLOG_GENERATION_PROCESS.md $DEST
cp blog_handoffs/blog_handoff-005.md    $DEST
cp blogs/BLOG_bpu_14_directed_validation.md  $DEST
cp pa_handoffs/session_handoff-050.md $DEST
cp pa_handoffs/session_handoff-051.md $DEST
cp pa_handoffs/session_handoff-052.md $DEST
cp pa_handoffs/session_handoff-053.md $DEST
cp pa_handoffs/session_handoff-054.md $DEST
cp pa_handoffs/session_handoff-055.md $DEST
cp pa_handoffs/session_handoff-056.md $DEST
cp prompts/BP-062.md $DEST
cp prompts/BP-063.md $DEST
cp prompts/BP-064.md $DEST
cp prompts/BP-065.md $DEST
cp prompts/BP-065a.md $DEST
cp prompts/BP-066.md $DEST
cp prompts/BP-066a.md $DEST
cp prompts/BP-066b.md $DEST
cp prompts/BP-067.md $DEST
cp prompts/BP-068.md $DEST
cp prompts/BP-069.md $DEST
cp prompts/BP-070.md $DEST
cp prompts/BP-071.md $DEST
cp prompts/BP-072.md $DEST
cp prompts/BP-073.md $DEST
cp prompts/BP-074.md $DEST

cp planning/PROJECT_STATUS.md $DEST
cp planning/PROJECT_CORE.md $DEST
cp planning/CLOSED_TECH_DEBT.md $DEST
cp misc/pa_session_map.md $DEST
