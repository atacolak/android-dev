#!/usr/bin/env bash
# Diagnose the android-dev toolchain. Exit 0 only if required host tools exist.
# --offline  skip network and device checks (CI / no phone)
# --soft     report failures but exit 0 (CI syntax gate uses ci-smoke instead)
set -u

ADEV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ADEV_ROOT/scripts/env.sh"

OFFLINE=0
SOFT=0
for a in "$@"; do
  case "$a" in
    --offline) OFFLINE=1 ;;
    --soft) SOFT=1 ;;
    -h|--help) echo "usage: doctor.sh [--offline] [--soft]"; exit 0 ;;
  esac
done

fail=0
ok() { printf 'OK    %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }
warn() { printf 'WARN  %s\n' "$*"; }

echo "=== android-dev doctor ==="
echo "ADEV_ROOT=$ADEV_ROOT"
echo "profile=${ADEV_PROFILE:-fold}"
echo "JAVA_HOME=${JAVA_HOME:-}"
echo "ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-}"
echo "ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-}"
echo

if command -v java >/dev/null 2>&1; then
  ver="$(java -version 2>&1 | head -1)"
  major="$(java -version 2>&1 | awk -F[\".] '/version/{print $2; exit}')"
  if [ "$major" = "$ADEV_JDK_MAJOR" ]; then
    ok "java $ver"
  else
    bad "java major $major (need $ADEV_JDK_MAJOR): $ver"
  fi
else
  bad "java not on PATH"
fi

if [ -d "${ANDROID_SDK_ROOT:-}/platforms/android-${ADEV_COMPILE_SDK}" ]; then
  ok "platforms;android-$ADEV_COMPILE_SDK"
else
  bad "missing $ANDROID_SDK_ROOT/platforms/android-$ADEV_COMPILE_SDK"
fi

if [ -d "${ANDROID_SDK_ROOT:-}/build-tools/${ADEV_BUILD_TOOLS}" ]; then
  ok "build-tools;$ADEV_BUILD_TOOLS"
else
  bad "missing $ANDROID_SDK_ROOT/build-tools/$ADEV_BUILD_TOOLS"
fi

if [ -d "${ANDROID_NDK_HOME:-}" ] && [ -f "${ANDROID_NDK_HOME:-}/source.properties" ]; then
  ok "ndk $ADEV_NDK at $ANDROID_NDK_HOME"
else
  bad "missing ndk $ADEV_NDK (ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-unset})"
fi

if [ -x "${ANDROID_SDK_ROOT:-}/platform-tools/adb" ] || command -v adb >/dev/null 2>&1; then
  ok "adb $(command -v adb 2>/dev/null || echo "$ANDROID_SDK_ROOT/platform-tools/adb")"
else
  warn "host adb not required for fold profile (Termux has it)"
fi

if command -v rustc >/dev/null 2>&1; then
  ok "rustc $(rustc --version)"
else
  bad "rustc not on PATH"
fi

if command -v rustup >/dev/null 2>&1 && rustup target list --installed | grep -qx "$ADEV_RUST_TARGET"; then
  ok "rust target $ADEV_RUST_TARGET"
else
  bad "rustup target $ADEV_RUST_TARGET not installed"
fi

if command -v cargo >/dev/null 2>&1 && cargo ndk --version >/dev/null 2>&1; then
  have="$(cargo ndk --version 2>/dev/null | awk '{print $NF; exit}')"
  if [ "$have" = "$ADEV_CARGO_NDK" ]; then
    ok "cargo-ndk $have"
  else
    warn "cargo-ndk $have (pinned $ADEV_CARGO_NDK)"
  fi
else
  bad "cargo-ndk missing"
fi

if command -v cmake >/dev/null 2>&1; then
  ok "cmake $(cmake --version | head -1)"
else
  bad "cmake missing"
fi
if command -v ninja >/dev/null 2>&1; then
  ok "ninja $(ninja --version)"
else
  bad "ninja missing"
fi

if command -v curl >/dev/null 2>&1; then
  ok "curl $(curl --version | head -1 | awk '{print $1,$2}')"
else
  bad "curl missing (gradle model download uses curl)"
fi

app="${ADEV_APP:-}"
if [ -n "$app" ] && [ -d "$app" ]; then
  if [ -x "$app/gradlew" ]; then
    ok "companion app $app (gradle wrapper present)"
  else
    warn "companion app $app has no gradlew"
  fi
else
  warn "companion app not cloned ($app) — adev clone-app"
fi

if [ "$OFFLINE" -eq 0 ]; then
  if [ "${ADEV_PROFILE:-fold}" = "fold" ]; then
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${ADEV_SSH_HOST:-fold}" 'echo ssh_ok' >/dev/null 2>&1; then
      ok "ssh ${ADEV_SSH_HOST:-fold}"
    else
      warn "ssh ${ADEV_SSH_HOST:-fold} unreachable (device checks skipped)"
    fi
  fi
else
  echo "(offline: skipped device/ssh)"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "doctor: PASS"
  exit 0
fi
echo "doctor: FAIL ($fail)"
if [ "$SOFT" -eq 1 ]; then
  exit 0
fi
exit 1
