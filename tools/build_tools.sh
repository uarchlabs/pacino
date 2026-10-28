#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/build_tools.sh [--check] [TOOL...] -- check the project tools and
# build those missing or at the wrong version
#
# TOOL is any of verilator, spike, surfer, lcov, fst2vcd, embecosm;
# default all six, in that order. Verilator, Spike, Surfer, lcov and
# fst2vcd install to $RVA_ROOT/tools/bin. The Embecosm toolchain is a
# prebuilt release, located or installed by check_embecosm.sh.
#
# Two phases, so that every question comes first and the builds then run
# without input:
#   1. Check (seconds). Each tools/check_<TOOL>.sh runs report-only. When
#      the Embecosm toolchain is not found, check_embecosm.sh --ask asks
#      for an existing install or a download, and saves the answer. When
#      any apt package is missing, the run stops here, nothing built, and
#      prints one apt command for all of them. (Rust, for Surfer, is not
#      a prerequisite: check_surfer.sh installs it into tools/rust.)
#   2. Build. Each tool not OK in phase 1 runs check_<TOOL>.sh --build
#      (Embecosm: --install, when the download was chosen). A tool is
#      built even if an earlier one fails.
# --check runs phase 1 only and asks nothing.
#
# No system package is installed. They can be installed ahead with:
#   sudo apt install $(sed 's/#.*//' tools/apt-requirements.txt)
#
# Exit status is non-zero unless every tool is OK; the summary names
# them. RVA_ROOT and JOBS: see tools/check_lib.sh.
#
# Every run is logged to $RVA_ROOT/logs/pacino_setup_YYYY-MM-DD_N.log,
# N the lowest number unused that day: a header (date, user, host, OS,
# git branch and commit, options), then all the output, as printed.
set -uo pipefail

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TOOLS_DIR/.." && pwd)"
ALL_TOOLS="verilator spike surfer lcov fst2vcd embecosm"
ARGS="$*"

build_opt="--build"
if [ "${1:-}" = "--check" ]; then
  build_opt=""
  shift
fi

tools="${*:-$ALL_TOOLS}"
for t in $tools; do
  if [ ! -f "$TOOLS_DIR/check_$t.sh" ]; then
    echo "build_tools.sh: unknown tool '$t'; known: $ALL_TOOLS" >&2
    exit 2
  fi
done

# --- Log ----------------------------------------------------------------
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR" || exit 1
n=1
while [ -e "$LOG_DIR/pacino_setup_$(date +%F)_$n.log" ]; do
  n=$((n + 1))
done
LOG="$LOG_DIR/pacino_setup_$(date +%F)_$n.log"

# Copy stdout and stderr to the log. On exit, close them and wait for tee
# so its last lines are written before the shell prompt returns.
exec > >(tee -a "$LOG") 2>&1
TEE_PID=$!

# The check scripts append each missing package here (check_lib.sh
# check_pkgs); the summary ends with one apt command for all of them.
PACINO_MISSING_PKGS=$(mktemp) || exit 1
export PACINO_MISSING_PKGS
trap 'rm -f "$PACINO_MISSING_PKGS"; exec >&- 2>&-; wait "$TEE_PID"' EXIT

os=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")
echo "=== pacino setup log"
echo "date:     $(date '+%F %T %z')"
echo "user:     $(id -un)"
echo "host:     $(hostname)"
echo "os:       ${os:-unknown} ($(uname -srm))"
branch=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
commit=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)
echo "branch:   ${branch:-none (not a git tree)}"
echo "commit:   ${commit:-none}"
echo "command:  $0 $ARGS"
echo "log:      $LOG"

# status[TOOL]: OK, or why it is not
declare -A status
to_build=""

# --- Phase 1: check, and ask the Embecosm question ----------------------
# PACINO_PLAN quiets each script's "Build X with" hint; phase 2 builds.
for t in $tools; do
  echo "=== check $t"
  opt=""
  [ "$t" = embecosm ] && [ -n "$build_opt" ] && opt="--ask"
  PACINO_PLAN=1 bash "$TOOLS_DIR/check_$t.sh" $opt
  rc=$?
  if [ "$rc" = 0 ]; then
    status[$t]="OK"
  elif [ "$t" = embecosm ] && [ "$rc" != 3 ]; then
    # Not found and not to be installed: --check, skipped, no terminal,
    # or a wrong EMBECOSM_BIN in the environment
    status[$t]="MISSING"
    [ -n "$build_opt" ] && status[$t]="FAIL"
  else
    status[$t]="MISSING"
    to_build="$to_build $t"
  fi
done

blocked=0
[ -s "$PACINO_MISSING_PKGS" ] && blocked=1

# --- Phase 2: build, unattended ----------------------------------------
if [ -n "$build_opt" ] && [ "$blocked" = 0 ]; then
  for t in $to_build; do
    echo "=== build $t"
    opt="--build"
    [ "$t" = embecosm ] && opt="--install"
    if bash "$TOOLS_DIR/check_$t.sh" $opt </dev/null; then
      status[$t]="OK"
    else
      status[$t]="FAIL"
    fi
  done
elif [ -n "$build_opt" ]; then
  for t in $to_build; do
    status[$t]="NOT BUILT"
  done
fi

echo "=== summary"
failed=0
for t in $tools; do
  printf '%-9s %s\n' "${status[$t]}" "$t"
  [ "${status[$t]}" = OK ] || failed=1
done
if [ -s "$PACINO_MISSING_PKGS" ]; then
  need=$(awk '{ print $1 }' "$PACINO_MISSING_PKGS" | sort -u | xargs)
  pkgs=$(awk '{ print $2 }' "$PACINO_MISSING_PKGS" | sort -u | xargs)
  echo "Missing packages ($need):"
  echo "  sudo apt install $pkgs"
fi
if [ "$blocked" = 1 ] && [ -n "$build_opt" ]; then
  echo "Nothing was built. Install the above, then run tools/build_tools.sh"
  echo "again."
fi
echo "log: $LOG"
[ "$failed" = 0 ]
