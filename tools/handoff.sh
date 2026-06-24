#! /usr/bin/env bash

rm -f ho
echo "We are resuming a session for the RVA23 Co-Design" > ho
echo "which is part of RISC-V RVA23 Design"              >> ho
# -------------------------------------------------------------
echo "" >> ho
echo "I have attached the following " >> ho
echo "- planning/PROJECT_CORE.md"     >> ho
echo "- planning/PROJECT_STATUS.md"   >> ho
# -------------------------------------------------------------
echo "" >> ho
echo "The experiment file template, is called " >> ho
echo "- templates/TASK_TEMPLATE.md"             >> ho
echo "All experiment files need to follow that format exactly. " >> ho
# -------------------------------------------------------------
echo "" >> ho
echo "The the session hand off file name is: " >> ho
echo "- pa_handoffs/session_handoff-$1.md"     >> ho
# -------------------------------------------------------------
echo "" >> ho
echo "The FTB decisions document name is:"      >> ho
echo "- pa_handoffs/ftb_decision_record-051.md" >> ho
# -------------------------------------------------------------
echo "" >> ho
echo "Lastly I have include current CLAUDE.md file:" >> ho
echo "- CLAUDE.md" >> ho

echo "" >> ho
cat planning/PROJECT_CORE.md               >> ho
cat planning/PROJECT_STATUS.md             >> ho
cat templates/TASK_TEMPLATE.md             >> ho
cat pa_handoffs/session_handoff-$1.md      >> ho
cat pa_handoffs/ftb_decision_record-051.md >> ho
cat CLAUDE.md                              >> ho
