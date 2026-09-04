#! /usr/bin/env bash

#echo "Documents included: " > cntx.md
#echo "planning/BLOG_GENERATION_PROCESS.md" >> cntx.md
#echo "blogs/BLOG_bpu_13_contradiction_detection.md" >> cntx.md
#echo "pa_handoffs/session_handoff-047.md" >> cntx.md
#echo "pa_handoffs/session_handoff-048.md" >> cntx.md
#echo "pa_handoffs/session_handoff-049.md" >> cntx.md
#echo "pa_handoffs/session_handoff-050.md" >> cntx.md
#echo "-- Separator ---------------------" >> cntx.md
#cat planning/BLOG_GENERATION_PROCESS.md >> cntx.md
#echo "-- Separator ---------------------" >> cntx.md
#cat blogs/BLOG_bpu_13_contradiction_detection.md >> cntx.md
#echo "-- Separator ---------------------" >> cntx.md
#cat pa_handoffs/session_handoff-047.md >> cntx.md
#echo "-- Separator ---------------------" >> cntx.md
#cat pa_handoffs/session_handoff-048.md >> cntx.md
#echo "-- Separator ---------------------" >> cntx.md
#cat pa_handoffs/session_handoff-049.md >> cntx.md
#echo "-- Separator ---------------------" >> cntx.md
#cat pa_handoffs/session_handoff-050.md >> cntx.md


DEST=~/Downloads/context
mkdir -p ~/Downloads/context
rm -f ~/Downloads/context/*
#cp planning/BLOG_GENERATION_PROCESS.md $DEST
#cp blogs/BLOG_bpu_13_contradiction_detection.md  $DEST
#cp pa_handoffs/session_handoff-047.md $DEST
#cp pa_handoffs/session_handoff-048.md $DEST
#cp pa_handoffs/session_handoff-049.md $DEST
#cp pa_handoffs/session_handoff-050.md $DEST


cp prompts/BP-045.md $DEST
cp prompts/BP-046.md $DEST
cp prompts/BP-047.md $DEST
cp prompts/BP-048.md $DEST
cp prompts/BP-049.md $DEST
cp prompts/BP-049a.md $DEST
cp prompts/BP-050.md $DEST
cp prompts/BP-050a.md $DEST
cp prompts/BP-050b.md $DEST
cp prompts/BP-051.md $DEST
cp prompts/BP-052.md $DEST
cp prompts/BP-053.md $DEST
cp prompts/BP-054.md $DEST
cp prompts/BP-054a.md $DEST
cp prompts/BP-056.md $DEST
cp prompts/BP-057.md $DEST
cp prompts/BP-058.md $DEST
cp prompts/BP-059.md $DEST
cp prompts/BP-060.md $DEST
cp prompts/BP-061.md $DEST

cp planning/PROJECT_STATUS.md $DEST
cp planning/CLOSED_TECH_DEBT.md $DEST
