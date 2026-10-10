#!/usr/bin/env bash
# Fold-specific device adapter, extracted from xr/scripts/xrctl.
# Transport: this host -> SSH $ADEV_SSH_HOST (Termux) -> Fold-local adb
#            -> 127.0.0.1:<current Wireless Debugging port> -> Android
#
# The rotating ADB port is discovered beside the device. Never nmap it
# over NetBird/LAN. Preserve Termux ADB identity; never pm clear / uninstall
# merely to iterate.

ADEV_SSH_HOST="${ADEV_SSH_HOST:-fold}"
ADEV_ADB_WIFI_TIMEOUT_S="${ADEV_ADB_WIFI_TIMEOUT_S:-180}"
ADEV_SETTLE_S="${ADEV_SETTLE_S:-12}"
ADEV_STATE_DIR="${ADEV_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/adev}"
ADEV_KEEP_RUNS="${ADEV_KEEP_RUNS:-15}"

_FOLD_SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
_FOLD_REMOTE_ENV='export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export PATH="$HOME/bin:$PREFIX/bin:/system/bin:/system/xbin:$PATH"
export ADB_MDNS_OPENSCREEN="${ADB_MDNS_OPENSCREEN:-1}"
mkdir -p "$HOME/tmp"
'

fold_ssh() {
  ssh "${_FOLD_SSH_OPTS[@]}" "$ADEV_SSH_HOST" "$_FOLD_REMOTE_ENV$*"
}

fold_pick_serial() {
  local list serial
  list="$(fold_ssh 'adb devices')"
  serial="$(printf '%s\n' "$list" | awk '/[[:space:]]device$/{print $1; exit}')"
  [ -n "$serial" ] || return 1
  printf '%s\n' "$serial"
}

fold_adb() {
  local serial
  serial="$(fold_pick_serial)" || die "no adb device (run: adev adb ensure)"
  fold_ssh "adb -s $(printf '%q' "$serial") $*"
}

fold_new_run() {
  local n
  mkdir -p "$ADEV_STATE_DIR/runs"
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
  RUN="$ADEV_STATE_DIR/runs/$RUN_ID"
  mkdir -p "$RUN"
  echo "$RUN" >"$ADEV_STATE_DIR/last-run"
  n="$(find "$ADEV_STATE_DIR/runs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
  if [ "$n" -gt "$ADEV_KEEP_RUNS" ]; then
    find "$ADEV_STATE_DIR/runs" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
      | sort -n | head -n "$((n - ADEV_KEEP_RUNS))" | awk '{print $2}' \
      | while read -r d; do rm -rf "$d"; done
  fi
}

fold_extract_crashes() {
  local logf="$1" out="$2"
  awk '
    BEGIN { grab=0; n=0 }
    /FATAL EXCEPTION/ { grab=1; n=0 }
    /FORTIFY:/ { grab=1; n=0 }
    grab { print; n++; if (n>120) { grab=0; n=0 } }
    grab && /^[-]+ beginning of/ { grab=0; n=0 }
    /Fatal signal/ { print; grab=1; n=1 }
    /DEBUG +: +signal / { print }
    /DEBUG +: +Abort message/ { print }
    /DEBUG +: +backtrace:/ { grab=1; n=1 }
  ' "$logf" >"$out" || true
}

fold_adb_ensure() {
  log "ensuring Fold-local wireless ADB via $ADEV_SSH_HOST"
  if fold_pick_serial >/dev/null 2>&1; then
    log "adb already device"
    fold_ssh 'adb devices -l'
    return 0
  fi
  fold_ssh 'adb devices | awk "/offline$/{print \$1}" | while read -r s; do adb disconnect "$s" >/dev/null 2>&1 || true; done' || true
  set +e
  timeout "$ADEV_ADB_WIFI_TIMEOUT_S" ssh "${_FOLD_SSH_OPTS[@]}" "$ADEV_SSH_HOST" "$_FOLD_REMOTE_ENV"'adb-wifi'
  local rc=$?
  set -e
  if [ "$rc" -eq 124 ]; then
    die "adb-wifi timed out after ${ADEV_ADB_WIFI_TIMEOUT_S}s"
  fi
  if ! fold_pick_serial >/dev/null 2>&1; then
    cat >&2 <<'EOFE'
adev: Termux adb is not `device`.

This is the one-time OS pairing boundary (or Wireless Debugging is off).

On the Fold: Developer options -> Wireless debugging -> Pair device with pairing code.
Then, from this host while that dialog is up:

  adev adb pair <6-digit-code> <pairing-port>

After a successful pair, later cycles only need `adev adb ensure`.
Do not delete Termux ADB keys to "fix" this.
EOFE
    return 2
  fi
  log "adb device"
  fold_ssh 'adb devices -l'
}

fold_adb_shell() {
  [ "$#" -ge 1 ] || die "usage: adev adb shell <args...>"
  local serial q="" a
  serial="$(fold_pick_serial)" || { fold_adb_ensure; serial="$(fold_pick_serial)" || die "no adb device"; }
  for a in "$@"; do
    q+=" $(printf '%q' "$a")"
  done
  fold_ssh "adb -s $(printf '%q' "$serial") shell$q"
}

fold_adb_pair() {
  local code="${1:-}" port="${2:-}"
  [ -n "$code" ] && [ -n "$port" ] || die "usage: adev adb pair <6-digit-code> <pairing-port>"
  log "adb pair 127.0.0.1:$port (on device)"
  fold_ssh "printf '%s\\n' $(printf '%q' "$code") | adb pair 127.0.0.1:$(printf '%q' "$port")"
  fold_adb_ensure
}

fold_device_status() {
  echo "=== transport ==="
  echo "profile=${ADEV_PROFILE:-fold}"
  echo "ssh_host=$ADEV_SSH_HOST"
  echo "=== ssh ==="
  fold_ssh 'whoami; hostname; echo sshd_ok'
  echo "=== adb ==="
  fold_ssh 'adb devices -l' || true
  if fold_pick_serial >/dev/null 2>&1; then
    echo "=== get-state ==="
    fold_adb 'get-state' || true
    echo "=== model ==="
    fold_adb 'shell getprop ro.product.model'
    fold_adb 'shell getprop ro.build.version.release'
  else
    echo "(adb not device — run adev adb ensure)"
  fi
}

fold_deploy() {
  local apk="" pkg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --package|-p) pkg="${2:-}"; shift 2 || die "missing --package value" ;;
      --package=*) pkg="${1#--package=}"; shift ;;
      --) shift; break ;;
      -*) die "unknown deploy option: $1" ;;
      *) if [ -z "$apk" ]; then apk="$1"; shift; else die "unexpected arg: $1"; fi ;;
    esac
  done
  [ -n "$apk" ] || die "usage: adev deploy <apk> --package <pkg>"
  [ -n "$pkg" ] || die "deploy requires --package <pkg>"
  [ -f "$apk" ] || die "apk not found: $apk"
  fold_adb_ensure
  log "scp $apk -> $ADEV_SSH_HOST:tmp/adev-deploy.apk"
  scp "${_FOLD_SSH_OPTS[@]}" "$apk" "$ADEV_SSH_HOST:tmp/adev-deploy.apk"
  log "adb install -r -d -t ($pkg)"
  local serial rc
  serial="$(fold_pick_serial)" || die "no adb device after ensure"
  set +e
  fold_ssh "adb -s $(printf '%q' "$serial") install -r -d -t \"\$HOME/tmp/adev-deploy.apk\""
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || die "adb install failed (exit $rc)"
  fold_adb "shell pm path $pkg" || true
  fold_adb "shell dumpsys package $pkg" 2>/dev/null \
    | awk '/versionName=|versionCode=|lastUpdateTime=/{print}' | head -10 || true
}

fold_resolve_activity() {
  local pkg="$1" act=""
  act="$(fold_adb "shell cmd package resolve-activity --brief $pkg" 2>/dev/null \
    | awk 'NF && $0 !~ /priority|No activity/{print; exit}')"
  if [ -z "$act" ] || [ "$act" = "No activity found" ]; then
    act="$(fold_adb "shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER $pkg" 2>/dev/null \
      | awk 'NF && $0 ~ /\//{print; exit}')"
  fi
  [ -n "$act" ] || act="$pkg/.MainActivity"
  printf '%s\n' "$act"
}

fold_stop() {
  local pkg="${1:-}"
  [ -n "$pkg" ] || die "usage: adev stop <package>"
  fold_adb_ensure
  fold_adb "shell am force-stop $pkg"
}

fold_launch() {
  local pkg="${1:-}" activity
  [ -n "$pkg" ] || die "usage: adev launch <package>"
  fold_adb_ensure
  activity="$(fold_resolve_activity "$pkg")"
  log "am start -W -n $activity"
  fold_adb "shell am start -W -n $activity"
}

fold_screenshot() {
  local dest="${1:-}" tmp
  fold_adb_ensure
  if [ -z "$dest" ]; then
    mkdir -p "$ADEV_STATE_DIR"
    dest="$ADEV_STATE_DIR/screen.png"
  fi
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp)"
  fold_adb 'exec-out screencap -p' >"$tmp" || true
  python3 - "$tmp" "$dest" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
i = data.find(b"\x89PNG\r\n\x1a\n")
open(dst, "wb").write(data if i < 0 else data[i:])
PY
  rm -f "$tmp"
  if [ -s "$dest" ]; then
    log "screenshot $dest ($(stat -c%s "$dest") bytes)"
  else
    log "screenshot empty"
  fi
}

fold_logs() {
  local pkg="${1:-}" tmp
  [ -n "$pkg" ] || die "usage: adev logs <package>"
  fold_adb_ensure
  tmp="$(mktemp)"
  fold_adb 'logcat -d -v threadtime' >"$tmp" || true
  echo "----- pid -----"
  fold_adb "shell pidof $pkg" || echo "(none)"
  echo "----- package lines (tail) -----"
  grep -E "$pkg|FATAL EXCEPTION|Fatal signal|FORTIFY:" "$tmp" | tail -80 || true
  echo "----- crash excerpt -----"
  fold_extract_crashes "$tmp" /dev/stdout
  rm -f "$tmp"
}

fold_smoke() {
  local pkg="${1:-}" activity start_rc pid="" resumed=0 fatal=0 native=0 status detail
  [ -n "$pkg" ] || die "usage: adev smoke <package>"
  fold_adb_ensure
  fold_new_run
  activity="$(fold_resolve_activity "$pkg")"
  log "smoke $pkg activity=$activity settle=${ADEV_SETTLE_S}s"
  printf '%s\n' "$activity" >"$RUN/activity.txt"
  fold_adb "logcat -c" >/dev/null 2>&1 || true
  fold_adb "shell am force-stop $pkg" >/dev/null 2>&1 || true
  sleep 1
  set +e
  fold_adb "shell am start -W -n $activity" | tee "$RUN/launch.txt"
  start_rc=${PIPESTATUS[0]}
  set -e
  sleep "$ADEV_SETTLE_S"
  fold_adb "shell pidof $pkg" >"$RUN/pid.txt" 2>&1 || true
  fold_adb "shell dumpsys activity activities" >"$RUN/dumpsys-activities.txt" 2>&1 || true
  fold_adb "logcat -d -v threadtime" >"$RUN/logcat.txt" 2>&1 || true
  fold_screenshot "$RUN/screen.png" >/dev/null || true
  fold_extract_crashes "$RUN/logcat.txt" "$RUN/crash-excerpt.txt"
  pid="$(tr -d ' \n' <"$RUN/pid.txt" || true)"
  if grep -E "mResumedActivity.*$pkg|topResumedActivity.*$pkg|$pkg/" \
       "$RUN/dumpsys-activities.txt" >/dev/null 2>&1; then
    resumed=1
  fi
  if grep -E "FATAL EXCEPTION|Fatal signal|FORTIFY:" "$RUN/crash-excerpt.txt" >/dev/null 2>&1; then
    fatal=1
  fi
  if grep -E "Fatal signal|tombstone" "$RUN/crash-excerpt.txt" >/dev/null 2>&1; then
    native=1
  fi
  {
    echo "package=$pkg"
    echo "activity=$activity"
    echo "am_start_rc=$start_rc"
    echo "pid=${pid:-none}"
    echo "resumed=$resumed"
    echo "fatal=$fatal"
    echo "native=$native"
    echo "settle_s=$ADEV_SETTLE_S"
    echo "run=$RUN"
  } | tee "$RUN/smoke.txt"
  if [ "$fatal" -eq 1 ] || [ "$native" -eq 1 ]; then
    status=FAIL_CRASH
    detail="process crashed; see $RUN/crash-excerpt.txt"
  elif [ -z "$pid" ]; then
    status=FAIL_DIED
    detail="no pid after ${ADEV_SETTLE_S}s"
  elif [ "$start_rc" -ne 0 ]; then
    status=FAIL_LAUNCH
    detail="am start rc=$start_rc pid=$pid"
  elif [ "$resumed" -ne 1 ]; then
    status=FAIL_NOT_RESUMED
    detail="pid=$pid but activity not resumed"
  else
    status=PASS_STAGE_A
    detail="pid=$pid activity=$activity resumed"
  fi
  {
    echo "status=$status"
    echo "detail=$detail"
  } | tee "$RUN/classify.txt"
  [ "$status" = "PASS_STAGE_A" ]
}

fold_pull() {
  local remote="${1:-}" dest="${2:-}" serial reader
  [ -n "$remote" ] && [ -n "$dest" ] || die "usage: adev pull <remote-path> <local-path>"
  fold_adb_ensure
  mkdir -p "$(dirname "$dest")"
  serial="$(fold_pick_serial)" || die "no adb device"
  reader="cat $(printf '%q' "$remote")"
  if [[ "$remote" =~ /Android/data/([^/]+)/ ]]; then
    reader="run-as $(printf '%q' "${BASH_REMATCH[1]}") cat $(printf '%q' "$remote")"
  fi
  ssh "${_FOLD_SSH_OPTS[@]}" "$ADEV_SSH_HOST" \
    "$_FOLD_REMOTE_ENV adb -s $(printf '%q' "$serial") exec-out $reader" \
    >"$dest"
  if [ ! -s "$dest" ]; then
    die "pull empty: $remote"
  fi
  log "pulled $remote -> $dest ($(stat -c%s "$dest") bytes)"
}
