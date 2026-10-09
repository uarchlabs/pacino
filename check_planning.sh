#!/usr/bin/env bash
# Compare planning files against the delivered versions.
# Baseline: session-071, except the files updated in session-073
# (ftb_decisions.md, ftb_interfaces.md, ubtb_interfaces.md,
# ftq_bpu_interfaces.md, ftq_entry_formats.md,
# ittage_table_entry_formats.md, ftq_backend_interfaces.md)
# and the files updated in session-074 (PROJECT_CORE.md,
# PROJECT_STATUS.md, CLAUDE.md, dcd_decisions.md,
# cachegen_decisions.md (new), l1i_ifu_interfaces.md,
# fe_decisions.md, icache_decisions.md, ifu_decisions.md,
# ibuf_decisions.md, ftq_ifu_interfaces.md, itlb_ifu_interfaces.md,
# ftq_decisions.md, mmu_decisions.md,
# ifu_ibuf_interfaces.md), and the files updated in session-075
# (PROJECT_STATUS.md, ftq_decisions.md, ftq_entry_formats.md,
# ftq_ifu_interfaces.md, ifu_decisions.md, ifu_ibuf_interfaces.md,
# itlb_ifu_interfaces.md, ftq_bpu_interfaces.md, dcd_decisions.md,
# ibuf_decisions.md, itlb_decisions.md, mmu_decisions.md,
# fe_decisions.md, itlb_l2tlb_interfaces.md, ftq_backend_interfaces.md,
# bp_arb_spec.md, ftb_decisions.md, ras_decisions.md,
# ras_interfaces.md, ubtb_interfaces.md, ftb_interfaces.md), and the
# files updated in session-076 (PROJECT_STATUS.md, bp_arb_spec.md,
# bp_cluster.md, bp_history_decisions.md, bp_history_interfaces.md,
# fe_decisions.md,
# ftb_confidence_override_rules.md, ftb_decisions.md,
# ftb_interfaces.md, ftq_backend_interfaces.md,
# ftq_bpu_interfaces.md, ftq_decisions.md, ftq_entry_formats.md,
# ittage_interfaces.md, loop_pred_interfaces.md, ras_decisions.md,
# ras_interfaces.md, sc_interfaces.md, tage_interfaces.md,
# ubtb_interfaces.md, cachegen_decisions.md, icache_decisions.md,
# ifu_decisions.md, mmu_decisions.md, itlb_ifu_interfaces.md,
# l1i_ifu_interfaces.md).
# CLAUDE.md is checked from the repo root (UNKN) since session-074.
# Usage: ./check_planning.sh [root]   (default: current directory)
#   root is the repo root, the directory that contains planning/.
# Exit status: 0 if every file matches, 1 otherwise.

ROOT="${1:-.}"

PLAN="planning"
ARCH="planning/arch"
INTF="planning/interfaces"
TEST="planning/testbenches"
VERF="planning/verification"
UNKN="."

# One file per line: <location> <file> <md5 prefix, 12 chars>
# <location> is one of PLAN ARCH INTF TEST VERF UNKN. Blank lines and # are ignored.
read -r -d '' FILES <<'EOF'
PLAN  PROJECT_CORE.md                   e3be8c359f3a
PLAN  PROJECT_STATUS.md                 00db9abc924d

UNKN  CLAUDE.md                         21a3681a7f6f

ARCH  bp_arb_spec.md                    5582b13af4fc
ARCH  bp_cluster.md                     187952e94e30
ARCH  bp_history_decisions.md           9d39b17222ec
ARCH  cachegen_decisions.md             a203a652e690
ARCH  dcd_decisions.md                  e961051d9415
ARCH  fe_decisions.md                   0045ab00dd4a
ARCH  ftb_decisions.md            a6b8e397e78d
ARCH  ftq_decisions.md            cca4aed5e94d
ARCH  ftq_entry_formats.md        2301dd3f97e2
ARCH  ibuf_decisions.md                 34f9eb23bd4f
ARCH  icache_decisions.md               61fdd9f822f3
ARCH  ifu_decisions.md            bd1ea4b281d5
ARCH  itlb_decisions.md                 71e886e9787f
ARCH  ittage_cntrl_ctr_update_rules.md  1c49fda9242e
ARCH  ittage_cntrl_decisions.md         28a3b83f2f34
ARCH  mmu_decisions.md                  46c645d2caa5
ARCH  ras_decisions.md                  c59c656a2b5f
ARCH  sc_decisions.md                   d264a4ba07ed
ARCH  sc_table_hash_rules.md            ef4c7e462412
ARCH  sram_init.md                      62d9e6c2825c
ARCH  tage_cntrl_uaon_update_rules.md   be55531dd5c0
ARCH  tage_cntrl_alloc_rules.md         3a22df5e85f3
ARCH  tage_cntrl_decisions.md           e784fba208cd
ARCH  tage_table_entry_formats.md       bfd6ee8f1d3d
ARCH  tage_table_hash_rules.md          d829daf22e1c
ARCH  ittage_table_hash_rules.md        e9d7d77217dc

ARCH  ittage_cntrl_alloc_rules.md       a61a19c81fa5
ARCH  ittage_cntrl_use_update_rules.md  b729da8f6a79
ARCH  ittage_table_entry_formats.md  abee67476ca8
ARCH  tage_cntrl_ctr_update_rules.md    1674f0129d91
ARCH  tage_cntrl_use_update_rules.md    d1dc910897a2
ARCH  ftb_confidence_override_rules.md  34362cfb6dd7
ARCH  pacino_cache.md                   f871e6288ecf
TEST  tage_tb_decisions.md              ae2979a6d9f0
TEST  tage_mtb_decisions.md             33a02ac0df2c
TEST  sc_tb_decisions.md                7e3a2f535d9b
TEST  manual_tb_decisions.md            9ac8ad00f83e
VERF  tage_coverage_plan.md             07a285114196

INTF  ittage_table_interfaces.md        152940fce590
INTF  tage_table_interfaces.md          c77c3b137298
INTF  bp_history_interfaces.md          9456f916e7d4
INTF  bpu_port_inventory.md             0add13030cb6
INTF  ftb_interfaces.md           cd521eb2f07d
INTF  ftq_backend_interfaces.md   1c425156a6e7
INTF  ftq_bpu_interfaces.md       4a169d510a90
INTF  ftq_ifu_interfaces.md       8d3732475aa5
INTF  ifu_ibuf_interfaces.md      d1c8ae118057
INTF  itlb_ifu_interfaces.md            41f8d2a51124
INTF  itlb_l2tlb_interfaces.md          5df4cb596827
INTF  ittage_interfaces.md              43f50427b6a7
INTF  l1i_ifu_interfaces.md             6fb85b387edb
INTF  loop_pred_interfaces.md           f1eb16c7ce58
INTF  ras_interfaces.md                 2c75f3d57bb0
INTF  sc_interfaces.md                  8a747bc6aaea
INTF  sc_table_interfaces.md            f64578d705ba
INTF  tage_interfaces.md                e25a37204743
INTF  ubtb_interfaces.md          b7ed4eddefa8


EOF

match=0; differ=0; missing=0; bad=0; total=0

while read -r loc file want; do
  [[ -z "$loc" || "$loc" == \#* ]] && continue
  total=$((total + 1))

  case "$loc" in
    PLAN|ARCH|INTF|TEST|VERF|UNKN) rel="${!loc}/$file" ;;
    *) printf 'BADLOC   %s  (location "%s")\n' "$file" "$loc"
       bad=$((bad + 1)); continue ;;
  esac
  rel="${rel#./}"
  path="$ROOT/$rel"

  if [[ ! -f "$path" ]]; then
    printf 'MISSING  %s\n' "$rel"
    missing=$((missing + 1))
    continue
  fi
  got=$(md5sum "$path" | cut -c1-12)
  if [[ "$got" == "$want" ]]; then
    printf 'MATCH    %s\n' "$rel"
    match=$((match + 1))
  else
    printf 'DIFFER   %s  (got %s, want %s)\n' "$rel" "$got" "$want"
    differ=$((differ + 1))
  fi
done <<< "$FILES"

printf '\n%d match, %d differ, %d missing, %d bad location, of %d\n' \
  "$match" "$differ" "$missing" "$bad" "$total"

[[ $differ -eq 0 && $missing -eq 0 && $bad -eq 0 ]]
