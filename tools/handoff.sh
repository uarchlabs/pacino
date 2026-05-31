#! /usr/bin/env bash

rm -f ho
echo "We are resuming a session for the RVA23 Co-Design" > ho
echo "which is part of RISC-V RVA23 Design"              >> ho

echo "" >> ho
echo "I have attached the following "      >> ho
#echo "- planning/ANTIPATTERNS.md"          >> ho
echo "- planning/PROJECT_CORE.md"          >> ho
echo "- planning/PROJECT_STATUS.md"        >> ho
echo "" >> ho
echo "This is the experiment file template all generated "   >> ho
echo "experiment files need to follow this format exactly. " >> ho
echo "- templates/TASK_TEMPLATE.md"         >> ho
echo "" >> ho
echo "- pa_handoffs/session_handoff-$1.md" >> ho
echo "- CLAUDE.md"                         >> ho

echo "" >> ho
echo "Also adding additinoal context for 1st task"           >> ho
echo "" >> ho
echo "- tools/gen_sessions.py"               >> ho
echo "- docs/sessions.html"                 >> ho

echo "" >> ho
echo "Process this and suggest the next steps when you are ready" >> ho
echo "" >> ho

#cat planning/ANTIPATTERNS.md                        >> ho
cat planning/PROJECT_CORE.md                        >> ho
cat planning/PROJECT_STATUS.md                      >> ho
cat templates/TASK_TEMPLATE.md                       >> ho
cat pa_handoffs/session_handoff-$1.md               >> ho
cat CLAUDE.md                                       >> ho
cat tools/gen_sessions.py >> ho
cat docs/sessions.html >> ho
