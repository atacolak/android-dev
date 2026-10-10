#!/usr/bin/env bash
# Idempotent Linux install of the pinned JDK/SDK/NDK/Rust Android toolchain.
# No sudo. No daemons. Does not commit binaries.
set -euo pipefail

ADEV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ADEV_ROOT/scripts/env.sh"

OPT_BASE="${ADEV_OPT_BASE:-$HOME/.local/opt}"
JDK_DIR="${ADEV_JAVA_HOME:-$OPT_BASE/jdk-17}"
SDK_DIR="${ANDROID_SDK_ROOT:-$OPT_BASE/android-sdk}"

log() { printf '[bootstrap] %s\n' "$*"; }
die() { echo "bootstrap: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "need $1 on PATH"; }

need curl
need tar
need unzip
need python3

java_major() {
  local v
  v="$("$1" -version 2>&1 | awk -F[\".] '/version/{print $2; exit}')"
  printf '%s\n' "${v:-0}"
}

install_jdk() {
  if [ -x "$JDK_DIR/bin/java" ] && [ "$(java_major "$JDK_DIR/bin/java")" = "$ADEV_JDK_MAJOR" ]; then
    log "jdk $ADEV_JDK_MAJOR already at $JDK_DIR"
    return 0
  fi
  if command -v java >/dev/null 2>&1 && [ "$(java_major java)" = "$ADEV_JDK_MAJOR" ]; then
    log "system java $(java -version 2>&1 | head -1) — not copying"
    return 0
  fi
  log "installing Temurin JDK $ADEV_JDK_MAJOR -> $JDK_DIR"
  mkdir -p "$OPT_BASE"
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/jdk.tar.gz" "$ADEV_JDK_API"
  mkdir -p "$tmp/extract"
  tar -xzf "$tmp/jdk.tar.gz" -C "$tmp/extract"
  local extracted
  extracted="$(find "$tmp/extract" -maxdepth 1 -mindepth 1 -type d | head -1)"
  [ -n "$extracted" ] || die "jdk tarball had no directory"
  rm -rf "$JDK_DIR"
  mv "$extracted" "$JDK_DIR"
  rm -rf "$tmp"
  log "jdk installed: $("$JDK_DIR/bin/java" -version 2>&1 | head -1)"
}

install_cmdline_tools() {
  if [ -x "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]; then
    log "sdkmanager already at $SDK_DIR/cmdline-tools/latest"
    return 0
  fi
  log "installing Android cmdline-tools $ADEV_CMDLINE_TOOLS"
  mkdir -p "$SDK_DIR/cmdline-tools"
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/cmd.zip" "$ADEV_CMDLINE_TOOLS_ZIP"
  unzip -q "$tmp/cmd.zip" -d "$tmp"
  rm -rf "$SDK_DIR/cmdline-tools/latest"
  mv "$tmp/cmdline-tools" "$SDK_DIR/cmdline-tools/latest"
  rm -rf "$tmp"
}

sdkmanager_bin() {
  printf '%s\n' "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
}

accept_licenses() {
  yes | "$(sdkmanager_bin)" --sdk_root="$SDK_DIR" --licenses >/dev/null || true
}

install_sdk_packages() {
  export JAVA_HOME="${JAVA_HOME:-$JDK_DIR}"
  export PATH="$JAVA_HOME/bin:$PATH"
  log "sdk packages: platforms;android-$ADEV_COMPILE_SDK build-tools;$ADEV_BUILD_TOOLS ndk;$ADEV_NDK"
  accept_licenses
  "$(sdkmanager_bin)" --sdk_root="$SDK_DIR" --install \
    "platforms;android-$ADEV_COMPILE_SDK" \
    "build-tools;$ADEV_BUILD_TOOLS" \
    "ndk;$ADEV_NDK" \
    "platform-tools"
}

install_rust() {
  if ! command -v rustup >/dev/null 2>&1; then
    log "installing rustup (default toolchain)"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  fi
  log "rustup target add $ADEV_RUST_TARGET"
  rustup target add "$ADEV_RUST_TARGET"
  if cargo ndk --version >/dev/null 2>&1; then
    local have
    have="$(cargo ndk --version 2>/dev/null | awk '{print $NF; exit}')"
    log "cargo-ndk present ($have); want $ADEV_CARGO_NDK"
    if [ "$have" != "$ADEV_CARGO_NDK" ]; then
      cargo install cargo-ndk --version "$ADEV_CARGO_NDK" --locked --force
    fi
  else
    cargo install cargo-ndk --version "$ADEV_CARGO_NDK" --locked
  fi
}

check_host_cmake() {
  if command -v cmake >/dev/null 2>&1 && command -v ninja >/dev/null 2>&1; then
    log "cmake $(cmake --version | head -1); ninja $(ninja --version)"
    return 0
  fi
  cat >&2 <<EOF
bootstrap: cmake and ninja are required (transcribe-cpp-sys builds via CMake).
Install with the host package manager, e.g.:
  sudo apt-get install -y cmake ninja-build
This script will not apt-get as root.
EOF
  return 1
}

log "ADEV_ROOT=$ADEV_ROOT"
install_jdk
# re-source so JAVA_HOME/SDK pick up newly installed paths
# shellcheck disable=SC1091
. "$ADEV_ROOT/scripts/env.sh"
export JAVA_HOME="${JAVA_HOME:-$JDK_DIR}"
export ANDROID_SDK_ROOT="$SDK_DIR"
export ANDROID_HOME="$SDK_DIR"
install_cmdline_tools
install_sdk_packages
install_rust
check_host_cmake
log "bootstrap ok"
"$ADEV_ROOT/scripts/doctor.sh"
