#! /usr/bin/env bash

rm -f ho
echo "We are resuming a session for the RVA23 Co-Design" > ho
echo "which is part of RISC-V RVA23 Design"              >> ho

echo "I have attached the following " >> ho
echo "- planning/ANTIPATTERNS.md"       >> ho
echo "- planning/PROJECT_CORE.md"       >> ho
echo "- planning/PROJECT_STATUS.md"     >> ho
echo "- template/TASK_TEMPLATE.md"      >> ho
echo "- pa_handoffs/session_handoff-$1.md" >> ho
echo "- CLAUDE.md"             >> ho

echo "" >> ho
echo "Process this and suggest the next steps when you are ready" >> ho
echo "" >> ho

cat planning/ANTIPATTERNS.md                        >> ho
cat planning/PROJECT_CORE.md                        >> ho
cat planning/PROJECT_STATUS.md                      >> ho
cat template/TASK_TEMPLATE.md                       >> ho
cat pa_handoffs/session_handoff-$1.md               >> ho
cat CLAUDE.md                                       >> ho
