#!/usr/bin/env bash
# Host-local adb (USB / emulator). ANDROID_SERIAL optional.

_g_adb() {
  if [ -n "${ANDROID_SERIAL:-}" ]; then
    adb -s "$ANDROID_SERIAL" "$@"
  else
    adb "$@"
  fi
}

generic_adb_ensure() {
  log "host adb devices"
  adb start-server >/dev/null 2>&1 || true
  adb devices -l
  _g_adb get-state >/dev/null
}

generic_adb_shell() {
  [ "$#" -ge 1 ] || die "usage: adev adb shell <args...>"
  generic_adb_ensure
  _g_adb shell "$@"
}

generic_adb_pair() {
  die "generic profile: pair with host adb (adb pair <ip:port> <code>)"
}

generic_device_status() {
  echo "=== transport ==="
  echo "profile=generic"
  echo "=== adb ==="
  adb devices -l || true
  if _g_adb get-state >/dev/null 2>&1; then
    echo "=== model ==="
    _g_adb shell getprop ro.product.model
    _g_adb shell getprop ro.build.version.release
  else
    echo "(no host adb device)"
  fi
}

generic_deploy() {
  local apk="" pkg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --package|-p) pkg="${2:-}"; shift 2 || die "missing --package value" ;;
      --package=*) pkg="${1#--package=}"; shift ;;
      -*) die "unknown deploy option: $1" ;;
      *) if [ -z "$apk" ]; then apk="$1"; shift; else die "unexpected arg: $1"; fi ;;
    esac
  done
  [ -n "$apk" ] && [ -n "$pkg" ] || die "usage: adev deploy <apk> --package <pkg>"
  [ -f "$apk" ] || die "apk not found: $apk"
  generic_adb_ensure
  log "adb install -r -d -t ($pkg)"
  _g_adb install -r -d -t "$apk"
  _g_adb shell pm path "$pkg" || true
}

generic_stop() {
  local pkg="${1:-}"
  [ -n "$pkg" ] || die "usage: adev stop <package>"
  generic_adb_ensure
  _g_adb shell am force-stop "$pkg"
}

generic_launch() {
  local pkg="${1:-}" act
  [ -n "$pkg" ] || die "usage: adev launch <package>"
  generic_adb_ensure
  act="$(_g_adb shell cmd package resolve-activity --brief "$pkg" | awk 'NF && $0 !~ /priority|No activity/{print; exit}')"
  [ -n "$act" ] || act="$pkg/.MainActivity"
  log "am start -W -n $act"
  _g_adb shell am start -W -n "$act"
}

generic_screenshot() {
  local dest="${1:-$ADEV_STATE_DIR/screen.png}"
  generic_adb_ensure
  mkdir -p "$(dirname "$dest")"
  _g_adb exec-out screencap -p >"$dest"
  log "screenshot $dest"
}

generic_logs() {
  local pkg="${1:-}"
  [ -n "$pkg" ] || die "usage: adev logs <package>"
  generic_adb_ensure
  echo "----- pid -----"
  _g_adb shell pidof "$pkg" || echo "(none)"
  echo "----- logcat -----"
  _g_adb logcat -d -v threadtime | grep -E "$pkg|FATAL EXCEPTION|Fatal signal" | tail -80 || true
}

generic_smoke() {
  local pkg="${1:-}"
  [ -n "$pkg" ] || die "usage: adev smoke <package>"
  generic_stop "$pkg"
  generic_launch "$pkg"
  sleep "${ADEV_SETTLE_S:-8}"
  _g_adb shell pidof "$pkg" >/dev/null
}

generic_pull() {
  local remote="${1:-}" dest="${2:-}"
  [ -n "$remote" ] && [ -n "$dest" ] || die "usage: adev pull <remote> <local>"
  generic_adb_ensure
  mkdir -p "$(dirname "$dest")"
  _g_adb pull "$remote" "$dest"
}
