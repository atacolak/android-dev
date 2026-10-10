#!/usr/bin/env bash
# Portable environment entrypoint. Source from a login shell or a script:
#   source /path/to/android-dev/scripts/env.sh
# Idempotent. Does not install anything.
#
# Layout defaults (override with env):
#   ADEV_JAVA_HOME / JAVA_HOME  -> ~/.local/opt/jdk-17
#   ANDROID_SDK_ROOT            -> ~/.local/opt/android-sdk
#   ANDROID_NDK_HOME            -> $ANDROID_SDK_ROOT/ndk/$ADEV_NDK

if [ -n "${BASH_VERSION:-}" ]; then
  _adev_src="${BASH_SOURCE[0]}"
else
  _adev_src="$0"
fi
ADEV_ROOT="$(cd "$(dirname "$_adev_src")/.." && pwd)"
unset _adev_src
export ADEV_ROOT

# shellcheck disable=SC1091
. "$ADEV_ROOT/versions.env"

_adev_first_dir() {
  local d
  for d in "$@"; do
    [ -n "$d" ] && [ -d "$d" ] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

if [ -z "${ADEV_JAVA_HOME:-}" ]; then
  ADEV_JAVA_HOME="$(_adev_first_dir \
    "${JAVA_HOME:-}" \
    "$HOME/.local/opt/jdk-17" \
    /usr/lib/jvm/java-17-openjdk \
    /usr/lib/jvm/java-17-openjdk-amd64 \
    /opt/android-studio/jbr \
    || true)"
fi
if [ -n "${ADEV_JAVA_HOME:-}" ]; then
  export JAVA_HOME="$ADEV_JAVA_HOME"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/.local/opt/android-sdk}}"
export ANDROID_HOME="$ANDROID_SDK_ROOT"

_ndk_dir="$ANDROID_SDK_ROOT/ndk/${ADEV_NDK}"
if [ -d "$_ndk_dir" ]; then
  export ANDROID_NDK_HOME="$_ndk_dir"
  export ANDROID_NDK_ROOT="$_ndk_dir"
  export ANDROID_NDK="$_ndk_dir"
fi
unset _ndk_dir

_sdk_path_bits=""
[ -d "$ANDROID_SDK_ROOT/platform-tools" ] && _sdk_path_bits="$ANDROID_SDK_ROOT/platform-tools"
[ -d "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" ] && _sdk_path_bits="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin${_sdk_path_bits:+:$_sdk_path_bits}"
[ -n "$_sdk_path_bits" ] && export PATH="$_sdk_path_bits:$PATH"
unset _sdk_path_bits

if [ -d "$HOME/.cargo/bin" ]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

export ADEV_PROFILE="${ADEV_PROFILE:-fold}"
export ADEV_SSH_HOST="${ADEV_SSH_HOST:-fold}"
export ADEV_APP="${ADEV_APP:-$HOME/workspace/android-transcribe}"
export ADEV_STATE_DIR="${ADEV_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/adev}"

# cargo-ndk / gradle helpers used by the companion app
if [ -n "${ANDROID_NDK_HOME:-}" ]; then
  export TRANSCRIBE_CMAKE_ARGS="${TRANSCRIBE_CMAKE_ARGS:--DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16}"
fi
