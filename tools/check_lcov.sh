#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/check_lcov.sh [--build] -- report lcov and its packages; with
# --build, install lcov when it is missing or the wrong version.
#
# lcov is installed from https://github.com/linux-test-project/lcov at
# tag LCOV_REF, cloned into $RVA_ROOT/tools/lcov, to $RVA_ROOT/tools
# (bin/genhtml and the other scripts, etc/lcovrc, share/man). The project
# runs genhtml, as GENHTML in rtl/Vars.mk, for the bpu coverage reports.
# lcov 1.x is Perl scripts; nothing is compiled. It is correct when
# genhtml --version reports LCOV_REF and etc/lcovrc exists; the version
# is checked again after the install.
#
# Packages: the [lcov] group of tools/apt-requirements.txt. Options, exit
# status and RVA_ROOT: see tools/check_lib.sh.
set -uo pipefail
source "$(dirname "$0")/check_lib.sh" "$@"

SRC="$RVA_ROOT/tools/lcov"
LCOV_URL="https://github.com/linux-test-project/lcov.git"
LCOV_REF="v1.15"

verify_lcov() {
  if [ ! -x "$BIN/genhtml" ]; then
    echo "MISSING genhtml at $BIN/genhtml"
    return 1
  fi
  local version
  version=$("$BIN/genhtml" --version 2>&1 || true)
  if [ "$version" != "genhtml: LCOV version ${LCOV_REF#v}" ]; then
    echo "BROKEN  genhtml: expected ${LCOV_REF#v}, got: $version"
    return 1
  fi
  if [ ! -f "$RVA_ROOT/tools/etc/lcovrc" ]; then
    echo "MISSING lcovrc at $RVA_ROOT/tools/etc/lcovrc"
    return 1
  fi
  echo "OK      lcov: ${version#genhtml: } at $BIN/genhtml"
}

check_pkgs lcov
verify_lcov; tool_ok=$?
[ -z "$MISSING_PKGS" ] && [ "$tool_ok" = 0 ] && exit 0
[ -n "$MISSING_PKGS" ] && apt_hint
[ "$tool_ok" = 0 ] && exit 1
if [ "$BUILD" = 0 ]; then
  echo "Install lcov with: $0 --build"
  exit 1
fi
if [ -n "$MISSING_PKGS" ]; then
  echo "NOT BUILT lcov: install the packages first"
  exit 1
fi

# --- Install ------------------------------------------------------------
# A clone at another tag is replaced. lcov's Makefile takes the version it
# stamps into each script from git describe, so the clone keeps the tag.
# The subshell stands alone and $? is tested after: set -e is ignored in a
# subshell tested by || or if, so a failed step would not stop the build.
(
  set -e
  if [ "$(git -C "$SRC" describe --tags --exact-match 2>/dev/null)" \
       != "$LCOV_REF" ]; then
    rm -rf "$SRC"
    git clone --quiet --depth 1 --branch "$LCOV_REF" "$LCOV_URL" "$SRC"
  fi
  make -C "$SRC" install PREFIX="$RVA_ROOT/tools"
)
if [ $? -ne 0 ]; then
  echo "FAILED  lcov install"
  exit 1
fi

verify_lcov
