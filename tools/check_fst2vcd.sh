#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/check_fst2vcd.sh [--build] -- report fst2vcd and its packages;
# with --build, build fst2vcd when it is missing or the wrong version.
#
# fst2vcd is a GTKWave helper. Only it is built, not GTKWave: its source
# and the FST library it uses (fstapi, lz4, fastlz) are compiled from
# https://github.com/gtkwave/gtkwave at tag GTKWAVE_REF, cloned into
# $RVA_ROOT/tools/gtkwave, to $RVA_ROOT/tools/bin/fst2vcd. GTKWave's
# configure is not run (it needs GTK); a config.h with the few settings
# these files read is written instead. The project runs fst2vcd, as
# FST2VCD in rtl/Vars.mk, from examples/fe_demo/waves/fe_demo_sigs.py.
#
# fst2vcd has no version option. The build writes GTKWAVE_REF to
# $RVA_ROOT/tools/share/fst2vcd/VERSION; it is correct when that names
# GTKWAVE_REF and fst2vcd -h exits 0. Both are checked again after a
# build.
#
# Packages: the [fst2vcd] group of tools/apt-requirements.txt. Options,
# exit status and RVA_ROOT: see tools/check_lib.sh.
set -uo pipefail
source "$(dirname "$0")/check_lib.sh" "$@"

SRC="$RVA_ROOT/tools/gtkwave"
GTKWAVE_URL="https://github.com/gtkwave/gtkwave.git"
GTKWAVE_REF="v3.3.104"
STAMP="$RVA_ROOT/tools/share/fst2vcd/VERSION"

verify_fst2vcd() {
  if [ ! -x "$BIN/fst2vcd" ]; then
    echo "MISSING fst2vcd at $BIN/fst2vcd"
    return 1
  fi
  if ! "$BIN/fst2vcd" -h >/dev/null 2>&1; then
    echo "BROKEN  fst2vcd: $BIN/fst2vcd -h failed"
    return 1
  fi
  local stamp
  stamp=$(cat "$STAMP" 2>/dev/null || true)
  if [ "$stamp" != "gtkwave $GTKWAVE_REF" ]; then
    echo "BROKEN  fst2vcd: expected gtkwave $GTKWAVE_REF, got:" \
         "${stamp:-no $STAMP}"
    return 1
  fi
  echo "OK      fst2vcd: $stamp at $BIN/fst2vcd"
}

check_pkgs fst2vcd
verify_fst2vcd; tool_ok=$?
[ -z "$MISSING_PKGS" ] && [ "$tool_ok" = 0 ] && exit 0
[ -n "$MISSING_PKGS" ] && apt_hint
[ "$tool_ok" = 0 ] && exit 1
if [ "$BUILD" = 0 ]; then
  build_hint "Build fst2vcd"
  exit 1
fi
if [ -n "$MISSING_PKGS" ]; then
  echo "NOT BUILT fst2vcd: install the packages first"
  exit 1
fi

# --- Build --------------------------------------------------------------
# A clone at another tag is replaced. config.h: getopt_long for the
# options, alloca.h for fstapi, setenv/unsetenv for WAVE_LOCALE_FIX, and
# the bug address the help text prints.
# The subshell stands alone and $? is tested after: set -e is ignored in a
# subshell tested by || or if, so a failed step would not stop the build.
(
  set -e
  if [ "$(git -C "$SRC" describe --tags --exact-match 2>/dev/null)" \
       != "$GTKWAVE_REF" ]; then
    rm -rf "$SRC"
    git clone --quiet --depth 1 --branch "$GTKWAVE_REF" "$GTKWAVE_URL" \
      "$SRC"
  fi
  top="$SRC/gtkwave3-gtk3"
  build="$SRC/build_fst2vcd"
  rm -rf "$build"
  mkdir -p "$build" "$BIN" "$(dirname "$STAMP")"
  printf '%s\n' \
    '#define HAVE_GETOPT_H 1' \
    '#define HAVE_ALLOCA_H 1' \
    '#define HAVE_SETENV 1' \
    '#define HAVE_UNSETENV 1' \
    '#define PACKAGE_BUGREPORT "bybell@rocketmail.com"' > "$build/config.h"
  cd "$top/src/helpers"
  gcc -O2 -I"$build" -I"$top" -Ifst -o "$build/fst2vcd" \
    fst2vcd.c fst/fstapi.c fst/lz4.c fst/fastlz.c -lz -lpthread
  install -m 755 "$build/fst2vcd" "$BIN/fst2vcd"
  echo "gtkwave $GTKWAVE_REF" > "$STAMP"
)
if [ $? -ne 0 ]; then
  echo "FAILED  fst2vcd build"
  exit 1
fi

verify_fst2vcd
