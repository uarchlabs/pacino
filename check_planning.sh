#!/usr/bin/env bash
# Compare planning files against the delivered versions.
# Baseline: session-071, except the three files updated in
# session-073 (PROJECT_STATUS.md, l1i_ifu_interfaces.md,
# mmu_decisions.md).
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
PLAN  PROJECT_CORE.md                   0320bf9df383
PLAN  PROJECT_STATUS.md           0c745fcc1a76

ARCH  bp_arb_spec.md                    d77fcf79123c
ARCH  bp_cluster.md                     bbfdeb78b28f
ARCH  bp_history_decisions.md           632a8a57ceab
ARCH  dcd_decisions.md                  3060707d7350
ARCH  fe_decisions.md                   47c145d1ddc1
ARCH  ftb_decisions.md            95d65b58517c
ARCH  ftq_decisions.md                  145d8d0ee0df
ARCH  ftq_entry_formats.md              982078e73bc6
ARCH  ibuf_decisions.md                 280c63bb3213
ARCH  icache_decisions.md               1f2e8430e1b9
ARCH  ifu_decisions.md                  72e04cc7055d
ARCH  itlb_decisions.md                 8ecd4944ccfe
ARCH  ittage_cntrl_ctr_update_rules.md  1c49fda9242e
ARCH  ittage_cntrl_decisions.md         28a3b83f2f34
ARCH  mmu_decisions.md                  a1df9b550fd0
ARCH  ras_decisions.md                  d841d505e3c9
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
ARCH  ittage_table_entry_formats.md     221656385c19
ARCH  tage_cntrl_ctr_update_rules.md    1674f0129d91
ARCH  tage_cntrl_use_update_rules.md    d1dc910897a2
ARCH  ftb_confidence_override_rules.md  889aa69be146
ARCH  pacino_cache.md                   f871e6288ecf
TEST  tage_tb_decisions.md              ae2979a6d9f0
TEST  tage_mtb_decisions.md             33a02ac0df2c
TEST  sc_tb_decisions.md                7e3a2f535d9b
TEST  manual_tb_decisions.md            9ac8ad00f83e
VERF  tage_coverage_plan.md             07a285114196

INTF  ittage_table_interfaces.md        152940fce590
INTF  tage_table_interfaces.md          c77c3b137298
INTF  bp_history_interfaces.md          f799a4123d5b
INTF  bpu_port_inventory.md             0add13030cb6
INTF  ftb_interfaces.md                 04c4be57569e
INTF  ftq_backend_interfaces.md         b34fce489216
INTF  ftq_bpu_interfaces.md             ac5e14b07d24
INTF  ftq_ifu_interfaces.md             72a610baec12
INTF  ifu_ibuf_interfaces.md            d2df21b0164c
INTF  itlb_ifu_interfaces.md            bad2da3edbaa
INTF  itlb_l2tlb_interfaces.md          cdd678fff43d
INTF  ittage_interfaces.md              7b90d2a1b3e3
INTF  l1i_ifu_interfaces.md             5d29946afbb1
INTF  loop_pred_interfaces.md           c20911b0ecc7
INTF  ras_interfaces.md                 45e38659a223
INTF  sc_interfaces.md                  c5913f89bc7c
INTF  sc_table_interfaces.md            f64578d705ba
INTF  tage_interfaces.md                1fc5cde68a3e
INTF  ubtb_interfaces.md                cc3a1269d860


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
