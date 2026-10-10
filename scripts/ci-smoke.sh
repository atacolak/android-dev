#!/usr/bin/env bash
# Lint/smoke with no attached phone and no toolchain download.
set -euo pipefail

ADEV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ADEV_ROOT"

fail=0
check() {
  local name="$1"; shift
  if "$@"; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name"
    fail=1
  fi
}

echo "=== android-dev ci-smoke ==="

scripts=(
  scripts/env.sh
  scripts/bootstrap.sh
  scripts/doctor.sh
  scripts/ci-smoke.sh
  bin/adev
  lib/adev-common.sh
  lib/fold.sh
  lib/generic.sh
)
for s in "${scripts[@]}"; do
  check "bash -n $s" bash -n "$s"
done

# shellcheck is optional
if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck" shellcheck -x "${scripts[@]}"
else
  echo "SKIP  shellcheck (not installed)"
fi

check "versions.env sourced" bash -c '
  set -euo pipefail
  . ./versions.env
  test -n "$ADEV_NDK"
  test "$ADEV_COMPILE_SDK" = 35
  test "$ADEV_CARGO_NDK" = 4.1.2
'

check "adev help" bash -c './bin/adev help | grep -q bootstrap'
check "adev env prints JAVA or SDK keys" bash -c './bin/adev env | grep -q ANDROID_SDK_ROOT'

# Fold adapter symbols exist
check "fold adapter functions" bash -c '
  set -euo pipefail
  ADEV_ROOT="$PWD"
  . lib/adev-common.sh
  die() { echo "$*" >&2; exit 1; }
  log() { :; }
  . lib/fold.sh
  type fold_adb_ensure >/dev/null
  type fold_deploy >/dev/null
  type fold_smoke >/dev/null
'

# Never commit toolchains, models, keys
check "no tracked binaries/secrets" python3 -c '
import os, subprocess, sys
bad_ext = {".apk", ".aab", ".gguf", ".so", ".keystore", ".jks", ".dex"}
bad_name = {"local.properties"}
raw = subprocess.check_output(["git", "ls-files", "-z"])
fail = 0
for p in raw.split(b"\0"):
    if not p:
        continue
    path = p.decode()
    base = os.path.basename(path)
    ext = os.path.splitext(base)[1].lower()
    if ext in bad_ext or base in bad_name:
        print("tracked forbidden:", path)
        fail = 1
    if path.startswith("sdk/") or path.startswith("ndk/") or path.startswith("jdk/"):
        print("tracked toolchain path:", path)
        fail = 1
sys.exit(fail)
'

# doctor --offline --soft never requires a phone
check "doctor --offline --soft" bash "$ADEV_ROOT/scripts/doctor.sh" --offline --soft

if [ "$fail" -ne 0 ]; then
  echo "ci-smoke: FAIL"
  exit 1
fi
echo "ci-smoke: PASS"
