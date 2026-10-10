#!/usr/bin/env bash
# Shared helpers for adev. Expects ADEV_ROOT.

set -euo pipefail

die() { echo "adev: $*" >&2; exit 1; }
log() { printf '[adev] %s\n' "$*"; }

need_root() {
  [ -n "${ADEV_ROOT:-}" ] || die "ADEV_ROOT unset (source scripts/env.sh)"
}

load_env() {
  need_root
  # shellcheck disable=SC1091
  . "$ADEV_ROOT/scripts/env.sh"
}

load_profile() {
  local p="${ADEV_PROFILE:-fold}"
  local f="$ADEV_ROOT/profiles/${p}.env"
  [ -f "$f" ] || die "unknown profile '$p' (expected $f)"
  # shellcheck disable=SC1090
  . "$f"
}

quote_cmd() {
  local a out=""
  for a in "$@"; do
    out+=" $(printf '%q' "$a")"
  done
  printf '%s' "${out# }"
}
