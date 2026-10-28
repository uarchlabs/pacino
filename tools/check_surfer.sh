#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/check_surfer.sh [--build] -- report Surfer and its packages; with
# --build, build Surfer when it is missing or the wrong version.
#
# Surfer is built from https://gitlab.com/surfer-project/surfer at tag
# SURFER_REF, cloned into $RVA_ROOT/tools/surfer, and installed to
# $RVA_ROOT/tools/bin (cargo install --root). It is correct when every
# shared library resolves (ldd) and --version names exactly SURFER_REF
# ("git: v0.7.0)", not a later commit such as v0.7.0-35-g010b840); the
# version is checked again after a build.
#
# Rust is needed to build only. It comes from rustup and is never
# installed here; when Surfer must be built and Rust is missing, the
# script prints the rustup command and exits 1 without building.
#
# Packages: the [surfer] group of tools/apt-requirements.txt. Options,
# exit status, RVA_ROOT and JOBS: see tools/check_lib.sh.
set -uo pipefail
source "$(dirname "$0")/check_lib.sh" "$@"

SRC="$RVA_ROOT/tools/surfer"
SURFER_URL="https://gitlab.com/surfer-project/surfer.git"
SURFER_REF="v0.7.0"

verify_surfer() {
  if [ ! -x "$BIN/surfer" ]; then
    echo "MISSING surfer at $BIN/surfer"
    return 1
  fi
  local unresolved version
  unresolved=$(ldd "$BIN/surfer" | grep 'not found' || true)
  if [ -n "$unresolved" ]; then
    echo "BROKEN  surfer: unresolved libraries:"
    echo "$unresolved"
    return 1
  fi
  version=$("$BIN/surfer" --version 2>&1 || true)
  if [[ "$version" != *"git: $SURFER_REF)"* ]]; then
    echo "BROKEN  surfer: expected $SURFER_REF, got: $version"
    return 1
  fi
  echo "OK      surfer: $version at $BIN/surfer"
}

[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
if command -v cargo >/dev/null 2>&1; then
  echo "OK      rust:   $(rustc --version)"
  have_rust=1
else
  echo "MISSING rust (needed to build only)"
  have_rust=0
fi

check_pkgs surfer
verify_surfer; tool_ok=$?
[ -z "$MISSING_PKGS" ] && [ "$tool_ok" = 0 ] && exit 0
[ -n "$MISSING_PKGS" ] && apt_hint
[ "$tool_ok" = 0 ] && exit 1
# Rust is needed now that Surfer must be built. tools/build_tools.sh sets
# PACINO_MISSING_RUST and prints the rustup command itself.
if [ "$have_rust" = 0 ]; then
  if [ -n "${PACINO_MISSING_RUST:-}" ]; then
    echo surfer >> "$PACINO_MISSING_RUST"
  else
    echo "Install Rust with (it edits ~/.bashrc and ~/.profile):"
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
  fi
fi
if [ "$BUILD" = 0 ]; then
  build_hint "Build Surfer"
  exit 1
fi
if [ -n "$MISSING_PKGS" ] || [ "$have_rust" = 0 ]; then
  echo "NOT BUILT surfer: install the prerequisites first"
  exit 1
fi

# --- Build --------------------------------------------------------------
# The link step is slow. --no-track keeps cargo's .crates.toml and
# .crates2.json out of tools/; --force then replaces a wrong binary.
# The subshell stands alone and $? is tested after: set -e is ignored in a
# subshell tested by || or if, so a failed step would not stop the build.
(
  set -e
  [ -d "$SRC/.git" ] || git clone "$SURFER_URL" "$SRC"
  if ! git -C "$SRC" checkout --quiet "$SURFER_REF" 2>/dev/null; then
    git -C "$SRC" fetch --tags origin
    git -C "$SRC" checkout --quiet "$SURFER_REF"
  fi
  git -C "$SRC" submodule update --init --recursive
  cargo install --locked --no-track --force --jobs "$JOBS" \
    --root "$RVA_ROOT/tools" --path "$SRC/surfer"
)
if [ $? -ne 0 ]; then
  echo "FAILED  surfer build"
  exit 1
fi

verify_surfer
