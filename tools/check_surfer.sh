#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/check_surfer.sh [--build] -- report Surfer and its packages; with
# --build, build Surfer when it is missing or the wrong version.
#
# Surfer is built from https://gitlab.com/surfer-project/surfer at commit
# SURFER_REF, cloned into $RVA_ROOT/tools/surfer, and installed to
# $RVA_ROOT/tools/bin (cargo install --root). It is correct when every
# shared library resolves (ldd) and --version names exactly
# SURFER_VERSION ("git: v0.7.0-35-g010b840)"); the version is checked
# again after a build.
#
# The pin is a commit, not the v0.7.0 tag: examples/fe_demo's command
# files were written and checked (DOC-004) with this build. The v0.7.0
# tag has no zoom_to command, and its wellen (0.20.5) names an unpacked
# array element a[i] as a.a.[i] or a.a, not a.[i] (wellen 0.21.0 here),
# so fe_demo's files fail in it. Move the pin to a release tag once one
# includes this commit.
#
# Rust is needed to build only. --build installs it per clone, at
# RUST_VERSION, into $RVA_ROOT/tools/rust (RUSTUP_HOME and CARGO_HOME
# there) with rustup's --no-modify-path, so no shell profile is edited
# and a Rust the user has in ~/.cargo is neither used nor changed. Rust
# is never a prerequisite the user installs.
#
# Packages: the [surfer] group of tools/apt-requirements.txt. Options,
# exit status, RVA_ROOT and JOBS: see tools/check_lib.sh.
set -uo pipefail
source "$(dirname "$0")/check_lib.sh" "$@"

SRC="$RVA_ROOT/tools/surfer"
SURFER_URL="https://gitlab.com/surfer-project/surfer.git"
SURFER_REF="010b84085e7eb27546fce84ca8f02ca6b4797b6a"   # 2026-05-25
SURFER_VERSION="v0.7.0-35-g010b840"   # what --version prints after git:

# Rust 1.95.0 built Surfer v0.7.0 on 2026-10-27; this commit needs 1.92
# or later (rust-version in its Cargo.toml).
RUST_VERSION="1.95.0"
RUST_DIR="$RVA_ROOT/tools/rust"
export RUSTUP_HOME="$RUST_DIR/rustup" CARGO_HOME="$RUST_DIR/cargo"
export RUSTUP_TOOLCHAIN="$RUST_VERSION"

verify_rust() {
  local version
  version=$("$CARGO_HOME/bin/rustc" --version 2>/dev/null || true)
  if [[ "$version" == "rustc $RUST_VERSION "* ]]; then
    echo "OK      rust:   $version at $RUST_DIR"
    return 0
  fi
  echo "MISSING rust $RUST_VERSION at $RUST_DIR (--build installs it)"
  return 1
}

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
  if [[ "$version" != *"git: $SURFER_VERSION)"* ]]; then
    echo "BROKEN  surfer: expected $SURFER_VERSION, got: $version"
    return 1
  fi
  echo "OK      surfer: $version at $BIN/surfer"
}

check_pkgs surfer
verify_surfer; tool_ok=$?
[ -z "$MISSING_PKGS" ] && [ "$tool_ok" = 0 ] && exit 0
[ -n "$MISSING_PKGS" ] && apt_hint
[ "$tool_ok" = 0 ] && exit 1
verify_rust; rust_ok=$?
if [ "$BUILD" = 0 ]; then
  build_hint "Build Surfer"
  exit 1
fi
if [ -n "$MISSING_PKGS" ]; then
  echo "NOT BUILT surfer: install the packages first"
  exit 1
fi

# --- Build --------------------------------------------------------------
# The link step is slow. --no-track keeps cargo's .crates.toml and
# .crates2.json out of tools/; --force then replaces a wrong binary.
# The subshell stands alone and $? is tested after: set -e is ignored in a
# subshell tested by || or if, so a failed step would not stop the build.
(
  set -e
  if [ "$rust_ok" != 0 ]; then
    # rustup-init: minimal profile (rustc, cargo, rust-std); -y answers
    # its questions. Run again it installs or selects RUST_VERSION.
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs |
      sh -s -- -y --no-modify-path --profile minimal \
        --default-toolchain "$RUST_VERSION"
  fi
  export PATH="$CARGO_HOME/bin:$PATH"
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
