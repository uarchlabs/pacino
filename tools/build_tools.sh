#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/build_tools.sh [--check] [TOOL...] -- check the project tools and
# build those missing or at the wrong version
#
# TOOL is any of verilator, spike, surfer, lcov, fst2vcd, embecosm;
# default all six, in that order. Each runs tools/check_<TOOL>.sh --build,
# or without --build when --check is given (report only, nothing is
# built). Verilator, Spike, Surfer, lcov and fst2vcd install to
# $RVA_ROOT/tools/bin. The Embecosm toolchain is a
# prebuilt release; when it is missing check_embecosm.sh asks for the
# path of an existing install or installs it into $RVA_ROOT/tools/.
#
# No system package is installed. Install them first with:
#   sudo apt install $(sed 's/#.*//' tools/apt-requirements.txt)
# A check script that finds one missing prints the command and does not
# build.
#
# Each tool is run even if an earlier one fails. Exit status is non-zero
# if any failed; the summary names them. RVA_ROOT and JOBS: see
# tools/check_lib.sh.
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
trap 'exec >&- 2>&-; wait "$TEE_PID"' EXIT

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

failed=""
for t in $tools; do
  echo "=== $t"
  if ! bash "$TOOLS_DIR/check_$t.sh" $build_opt; then
    failed="$failed $t"
  fi
done

echo "=== summary"
for t in $tools; do
  case " $failed " in
    *" $t "*) echo "FAIL    $t" ;;
    *)        echo "OK      $t" ;;
  esac
done
echo "log: $LOG"
[ -z "$failed" ]
