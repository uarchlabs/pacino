# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/check_lib.sh -- shared code for tools/check_<tool>.sh. Sourced,
# not run.
#
# Sets:
#   RVA_ROOT  the repo holding this file. An RVA_ROOT already in the
#             environment that names another tree is overridden, with a
#             warning, so a stale value cannot redirect a build.
#   BIN       $RVA_ROOT/tools/bin, where every tool is installed
#   JOBS      make parallelism. Default: nproc, capped at one job per
#             2 GB of memory (a Verilator compile job can use that much).
#   BUILD     1 when --build was given, else 0
#
# Usage of a check script: check_<tool>.sh [--build]
#   no option  report only; exit 0 when the tool and its packages are
#              all present, else 1
#   --build    as above, and build the tool into $BIN when it is missing
#              or the wrong version. Packages are never installed; when
#              one is missing the script prints the apt command and
#              exits 1 without building.

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -n "${RVA_ROOT:-}" ] && [ "$RVA_ROOT" != "$_root" ]; then
  echo "WARNING RVA_ROOT=$RVA_ROOT is another tree; using $_root" >&2
fi
export RVA_ROOT="$_root"
BIN="$RVA_ROOT/tools/bin"
REQS="$RVA_ROOT/tools/apt-requirements.txt"

if [ -z "${JOBS:-}" ]; then
  _mem_gb=$(awk '/^MemTotal:/ { print int($2 / 1048576) }' /proc/meminfo)
  JOBS=$(nproc)
  [ "$JOBS" -gt $(( _mem_gb / 2 )) ] && JOBS=$(( _mem_gb / 2 ))
  [ "$JOBS" -lt 1 ] && JOBS=1
fi
export JOBS

BUILD=0
case "${1:-}" in
  "")      ;;
  --build) BUILD=1 ;;
  *)       echo "usage: $(basename "$0") [--build]" >&2; exit 2 ;;
esac

# Packages of group TOOL in apt-requirements.txt, one per line
pkgs_for() {
  awk -v t="$1" '
    /^# \[/   { sec = $2; gsub(/[][]/, "", sec); next }
    { sub(/#.*/, "") }
    NF && sec == t { print $1 }
  ' "$REQS"
}

# Report the packages of group TOOL; set MISSING_PKGS to those absent.
# A removed package whose config files remain is not installed. When
# PACINO_MISSING_PKGS names a file (tools/build_tools.sh sets it), each
# absent package is also appended to it as "<tool> <package>".
check_pkgs() {
  MISSING_PKGS=""
  if ! command -v dpkg-query >/dev/null 2>&1; then
    echo "SKIPPED pkg:    no dpkg-query; this is not Debian/Ubuntu."
    echo "        Install the equivalents of: $(pkgs_for "$1" | xargs)"
    return
  fi
  local p
  for p in $(pkgs_for "$1"); do
    if [ "$(dpkg-query -W -f='${db:Status-Status}' "$p" 2>/dev/null)" \
         = installed ]; then
      echo "OK      pkg:    $p"
    else
      echo "MISSING pkg:    $p"
      MISSING_PKGS="$MISSING_PKGS $p"
      [ -n "${PACINO_MISSING_PKGS:-}" ] && \
        echo "$1 $p" >> "$PACINO_MISSING_PKGS"
    fi
  done
}

# Print the apt command for MISSING_PKGS. Not printed under
# tools/build_tools.sh (PACINO_MISSING_PKGS set), which prints one command
# for every tool.
apt_hint() {
  [ -n "${PACINO_MISSING_PKGS:-}" ] && return
  echo "Install the missing packages with:"
  echo "  sudo apt install$MISSING_PKGS"
}

# Report only: print "$1 with: <script> --build". Not printed in the
# check phase of tools/build_tools.sh (PACINO_PLAN set), which builds
# afterwards itself.
build_hint() {
  [ -n "${PACINO_PLAN:-}" ] && return
  echo "$1 with: $0 --build"
}
