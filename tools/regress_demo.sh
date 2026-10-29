#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/regress_demo.sh [ROOT] -- the demonstration regression (DOC-009,
# fe_demo_tb_decisions.md FDT-2, FDT-2a)
#
# Run from the repository root with no arguments. ROOT defaults to the
# repo root (the parent of this script's directory); pass a path to run
# against a scratch copy of the tree.
#
# It is not tools/regress.sh: it gates no push and records no pass
# (new_user_decisions.md NU-19, NU-20 are regress.sh's), and regress.sh
# does not scan examples/. It makes no git call and writes nothing under
# .git; what it writes are the models and out/ in examples/fe_demo, which
# are not committed (FDT-1).
#
# What it does, in examples/fe_demo of ROOT:
#   - reads the scenarios, the 2-slot ones and the two models from
#     `make scenario_list`, so it keeps no list of its own
#   - builds each model once from the tree it runs in, with make -B (the
#     event tables of the descriptions are written first, FDT-10c)
#   - runs every scenario, in FD order, one at a time, each with its own
#     make call on its model; make -o keeps the call from rebuilding the
#     model. A scenario whose model did not build is not run and fails
#   - prints one line per scenario, with its events checked <n> of <m>
#     from its result line (FDT-10), and the totals
#
# A scenario PASSES when its make call exits 0 and its log holds its
# -I: <scenario>: PASS, result line. Failures are compared with
# ROOT/tools/known_failures_demo.txt (a missing file is empty, and the
# script says so), in the format of tools/known_failures.txt:
#   examples/fe_demo <scenario> TD#<n> <description>
# with # comments and blank lines ignored. The third field must be
# TD#<n> or TD#?; a line without one, or with fewer than three fields,
# is reported as malformed and waives nothing. Jeff alone edits the
# file (FDT-2).
#
# Exit 0 only when every failing scenario is listed there, every listed
# scenario ran and still fails, no listed line is malformed, and both
# models built. As tools/regress.sh treats a listed target, a listed
# scenario that passes fails the run (NOW-PASSES), and so does one that
# did not run (stale entry).
# Logs are kept in a temp directory whose path is printed at the end.

set -u

usage() {
  echo "usage: tools/regress_demo.sh [ROOT]" >&2
  exit 2
}

[ $# -le 1 ] || usage
ROOT=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
DEMO_REL=examples/fe_demo
if [ ! -f "$ROOT/$DEMO_REL/Makefile" ]; then
  echo "regress_demo: no $DEMO_REL/Makefile under '$ROOT'" >&2
  exit 2
fi
ROOT=$(cd "$ROOT" && pwd)
DEMO=$ROOT/$DEMO_REL

# The demonstration Makefile includes $(RVA_ROOT)/rtl/Vars.mk and the
# fe_top source list; point both at the tree under test.
export RVA_ROOT=$ROOT

KNOWN_FILE=$ROOT/tools/known_failures_demo.txt
LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/regress_demo.XXXXXX")
T_ALL0=$(date +%s)

# -- the scenarios and the models, from the Makefile
LIST=$(make -s --no-print-directory -C "$DEMO" scenario_list) || {
  echo "regress_demo: make scenario_list failed in $DEMO" >&2
  exit 2
}
SCENS=$(sed -n 's/^scenarios: //p' <<< "$LIST")
SCEN_2S=" $(sed -n 's/^two_slot: //p' <<< "$LIST") "
read -r VTB1 VTB2 <<< "$(sed -n 's/^models: //p' <<< "$LIST")"
if [ -z "$SCENS" ] || [ -z "${VTB1:-}" ] || [ -z "${VTB2:-}" ]; then
  echo "regress_demo: make scenario_list gave no scenarios or models" >&2
  exit 2
fi

# -- known failures: key "<dir> <scenario>" -> TD field
declare -A KNOWN_TD=()
declare -A KNOWN_SEEN=()
BAD_KNOWN=()
if [ -f "$KNOWN_FILE" ]; then
  KNOWN_STATE="tools/known_failures_demo.txt"
  kline=0
  while read -r kdir ktgt ktd _; do
    kline=$((kline + 1))
    case "$kdir" in ''|\#*) continue ;; esac
    if [ -z "$ktgt" ] || ! [[ "$ktd" =~ ^TD#([0-9]+|\?)$ ]]; then
      msg="line $kline: '$kdir ${ktgt:-<no scenario>} ${ktd:-<no TD>}'"
      BAD_KNOWN+=("$msg: the third field must be TD#<n> or TD#?")
      continue
    fi
    KNOWN_TD["$kdir $ktgt"]=$ktd
  done < "$KNOWN_FILE"
else
  KNOWN_STATE="no tools/known_failures_demo.txt: treated as empty"
fi

# -- build each model once, from this tree
declare -A BUILT=()
BUILD_LINES=()
BUILD_FAIL=()
for m in "$VTB1" "$VTB2"; do
  log=$LOG_DIR/build_${m%%/*}.log
  t0=$(date +%s)
  make -B -C "$DEMO" "$m" > "$log" 2>&1
  rc=$?
  secs=$(( $(date +%s) - t0 ))
  warns=$(grep -c '^%Warning' "$log")
  if [ $rc -eq 0 ] && [ "$warns" -eq 0 ] && [ -x "$DEMO/$m" ]; then
    BUILT[$m]=1
    res=BUILT
  else
    res=FAIL
    BUILD_FAIL+=("$m (exit $rc, $warns warning(s)) log $log")
  fi
  BUILD_LINES+=("$(printf '  %-10s %-22s rc=%-3s warn=%-2s %4ss' \
    "$res" "$m" "$rc" "$warns" "$secs")")
done

# -- run every scenario on its model, one at a time
SUMMARY=()
FAIL_NEW=()
FAIL_KNOWN=()
NOW_PASSES=()
N_RUN=0
N_PASS=0
EV_N=0
EV_M=0
for s in $SCENS; do
  case "$SCEN_2S" in *" $s "*) m=$VTB2; slots=2 ;; *) m=$VTB1; slots=1 ;; esac
  key="$DEMO_REL $s"
  log=$LOG_DIR/$s.log
  ev="-"
  if [ -z "${BUILT[$m]:-}" ]; then
    rc=-
    secs=0
    ok=0
    echo "model $m did not build; $s not run" > "$log"
  else
    t0=$(date +%s)
    make -C "$DEMO" "$s" -o "$VTB1" -o "$VTB2" > "$log" 2>&1
    rc=$?
    secs=$(( $(date +%s) - t0 ))
    N_RUN=$((N_RUN + 1))
    [ -n "${KNOWN_TD[$key]:-}" ] && KNOWN_SEEN[$key]=1
    # The result line with its continuation lines, joined (FDT-10a).
    res=$(awk -v s="$s" '$0 ~ "^-[IE]: " s ": (PASS|FAIL)," {p = 1;
          printf "%s", $0; next} p && /^    / {sub(/^ +/, " "); printf "%s",
          $0; next} {p = 0}' "$log")
    n=$(sed -nE 's/.*events checked ([0-9]+) of ([0-9]+).*/\1 \2/p' \
        <<< "$res")
    if [ -n "$n" ]; then
      ev="${n% *}/${n#* }"
      EV_N=$((EV_N + ${n% *}))
      EV_M=$((EV_M + ${n#* }))
    fi
    ok=0
    [ $rc -eq 0 ] && [[ "$res" == "-I: $s: PASS,"* ]] && ok=1
  fi
  if [ $ok -eq 1 ]; then
    N_PASS=$((N_PASS + 1))
    if [ -n "${KNOWN_TD[$key]:-}" ]; then
      result="NOW-PASSES"
      NOW_PASSES+=("$key ${KNOWN_TD[$key]}: known failure now passes")
    else
      result="PASS"
    fi
  elif [ -n "${KNOWN_TD[$key]:-}" ] && [ "$rc" != "-" ]; then
    result="KNOWN-FAIL"
    FAIL_KNOWN+=("$key ${KNOWN_TD[$key]}")
  else
    result="FAIL"
    FAIL_NEW+=("$key (exit $rc) log $log")
  fi
  SUMMARY+=("$(printf '  %-10s %-20s slots=%s rc=%-3s events %-7s %4ss' \
    "$result" "$s" "$slots" "$rc" "$ev" "$secs")")
done

# A listed entry whose scenario did not run is stale.
STALE_KNOWN=()
for key in "${!KNOWN_TD[@]}"; do
  [ -z "${KNOWN_SEEN[$key]:-}" ] && \
    STALE_KNOWN+=("$key ${KNOWN_TD[$key]}: listed but no such scenario ran")
done

T_ALL=$(( $(date +%s) - T_ALL0 ))
N_SCEN=$(wc -w <<< "$SCENS")

echo
echo "=================================================================="
echo "DEMONSTRATION REGRESSION SUMMARY"
echo "root $ROOT"
echo "known failures: $KNOWN_STATE"
echo "=================================================================="
echo "models (make -B, once each)"
for line in "${BUILD_LINES[@]}"; do echo "$line"; done
echo "scenarios ($DEMO_REL)"
for line in "${SUMMARY[@]}"; do echo "$line"; done
echo "------------------------------------------------------------------"
echo "scenarios: $N_SCEN   run: $N_RUN   passed: $N_PASS" \
     "  events checked: $EV_N of $EV_M   total time: ${T_ALL}s"
echo "new failures: ${#FAIL_NEW[@]}   known failures: ${#FAIL_KNOWN[@]}" \
     "  now passing: ${#NOW_PASSES[@]}   stale entries: ${#STALE_KNOWN[@]}" \
     "  malformed entries: ${#BAD_KNOWN[@]}   build failures: ${#BUILD_FAIL[@]}"
for x in "${BUILD_FAIL[@]}";  do echo "BUILD FAIL: $x"; done
for x in "${BAD_KNOWN[@]}";   do echo "MALFORMED KNOWN-FAILURE ENTRY: $x"; done
for x in "${FAIL_NEW[@]}";    do echo "FAIL: $x"; done
for x in "${FAIL_KNOWN[@]}";  do echo "known failure: $x"; done
for x in "${NOW_PASSES[@]}";  do echo "KNOWN FAILURE NOW PASSES: $x"; done
for x in "${STALE_KNOWN[@]}"; do echo "STALE KNOWN-FAILURE ENTRY: $x"; done
echo "logs: $LOG_DIR"

if [ ${#BUILD_FAIL[@]} -ne 0 ] || [ ${#FAIL_NEW[@]} -ne 0 ] || \
   [ ${#NOW_PASSES[@]} -ne 0 ] || [ ${#STALE_KNOWN[@]} -ne 0 ] || \
   [ ${#BAD_KNOWN[@]} -ne 0 ]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
exit 0
