## Generic file, hand edited to cat session specific context
#echo "Files in package " >  ho
#echo "BLOG_GENERATION_PROCESS.md " >  ho
#echo "pa_handoffs/session_handoff-044.md" >> ho
#echo "pa_handoffs/session_handoff-045.md" >> ho
#echo "pa_handoffs/session_handoff-046.md" >> ho
##echo "pa_handoffs/session_handoff-047.md" >> ho
##echo "pa_handoffs/session_handoff-048.md" >> ho
##echo "pa_handoffs/session_handoff-049.md" >> ho
#
#echo "prompts/TB-001.md"        >> ho
#echo "prompts/TB-002.md"        >> ho
#echo "prompts/BP-040.md"        >> ho
#echo "prompts/BP-041.md"        >> ho
#echo "prompts/BP-042.md"        >> ho
#echo "prompts/BP-042a.md"       >> ho
#echo "prompts/BP-042b.md"       >> ho
#echo "prompts/INFRA-007.md"     >> ho
#
##echo "prompts/BP-043.md"        >> ho
##echo "prompts/BP-043a.md"       >> ho
##echo "prompts/BP-044.md"        >> ho
##echo "prompts/BP-044a.md"        >> ho
##echo "prompts/BP-044b.md"        >> ho
##echo "prompts/BP-044c.md"        >> ho
##echo "prompts/BP-045.md"        >> ho
##echo "prompts/BP-046.md"        >> ho
##echo "prompts/BP-047.md"        >> ho
##echo "prompts/BP-048.md"        >> ho
##echo "prompts/BP-049.md"        >> ho
##echo "prompts/BP-049a.md"       >> ho
##echo "prompts/BP-050.md"        >> ho
##echo "prompts/BP-051.md"        >> ho
##echo "prompts/BP-052.md"        >> ho
##echo "prompts/BP-053.md"        >> ho
##echo "prompts/BP-054.md"        >> ho
##echo "prompts/BP-054a.md"       >> ho
##echo "prompts/BP-055.md"        >> ho
##echo "prompts/BP-056.md"        >> ho
##echo "prompts/BP-057.md"        >> ho
##echo "prompts/BP-058.md"        >> ho
##echo "prompts/BP-059.md"        >> ho
##echo "prompts/BP-060.md"        >> ho
#
#echo "# separator -------------------" >> ho
#cat planning/BLOG_GENERATION_PROCESS.md >> ho
#
#echo "# separator -------------------" >> ho
#cat pa_handoffs/session_handoff-044.md >> ho
#
#echo "# separator -------------------" >> ho
#cat pa_handoffs/session_handoff-045.md >> ho
#
#echo "# separator -------------------" >> ho
#cat pa_handoffs/session_handoff-046.md >> ho
#
##echo "# separator -------------------" >> ho
##cat pa_handoffs/session_handoff-047.md >> ho
##echo "# separator -------------------" >> ho
##cat pa_handoffs/session_handoff-048.md >> ho
##echo "# separator -------------------" >> ho
##cat pa_handoffs/session_handoff-049.md >> ho
#
#echo "# separator -------------------" >> ho
#cat prompts/TB-001.md        >> ho
#
#echo "# separator -------------------" >> ho
#cat prompts/TB-002.md        >> ho
#
#echo "# separator -------------------" >> ho
#cat prompts/BP-040.md        >> ho
#
#echo "# separator -------------------" >> ho
#cat prompts/BP-041.md        >> ho
#
#echo "# separator -------------------" >> ho
#cat prompts/BP-042.md        >> ho
#
#echo "# separator -------------------" >> ho
#cat prompts/BP-042.md        >> ho
#
#echo "# separator -------------------" >> ho
#cat prompts/BP-042a.md       >> ho
#
#echo "# separator -------------------" >> ho
#cat prompts/BP-042b.md       >> ho
#
#echo "# separator -------------------" >> ho
#cat prompts/INFRA-007.md     >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-043.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-043a.md       >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-044.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-044a.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-044b.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-044c.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-045.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-046.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-047.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-048.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-049.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-049a.md       >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-050.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-051.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-052.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-053.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-054.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-054a.md       >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-055.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-056.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-057.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-058.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-059.md        >> ho
##echo "# separator -------------------" >> ho
##cat prompts/BP-060.md        >> ho
#

cat planning/arch/ftb_decisions.md > ho
cat planning/interfaces/ftb_interfaces.md >> ho
cat planning/interfaces/ubtb_interfaces.md >> ho

cat bpu/rtl/ftb_cntrl.sv >> ho
cat bpu/rtl/ftb_array.sv >> ho
cat bpu/rtl/bp_defines_pkg.sv >> ho

