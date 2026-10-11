#!/usr/bin/env bash
# Copyright (c) 2026 Axelspire Inc.
# SPDX-License-Identifier: MIT
#
# Thin acme.sh deploy-hook launcher for datasink scan.
#
# GPL boundary: this file only maps acme.sh deploy args → SCAN_* env and
# execs the proprietary companion OUTSIDE the acme.sh tree. Do not embed
# scan/report protocol here. Do not ship this inside the GPL archive tarball
# as a required part of upstream — install via one-curl companion path.
#
# Hook name: 3am_scan  →  function 3am_scan_deploy
# (Name must match acme.sh convention; bash required — digit-leading
# function names are invalid in POSIX dash.)
# Upstream contract: https://github.com/acmesh-official/acme.sh/wiki/deployhooks
#
# Preferred location (survives acme.sh --upgrade):
#   $LE_WORKING_DIR/deploy/3am_scan.sh   (usually ~/.acme.sh/deploy/)
#
# Companion resolution (first match wins):
#   1) $THREEAM_SCAN / $SCAN_HELPER (absolute path; wins over 3am-scan.env)
#   2) $THREEAM_LIB_DIR/3am-scan.sh
#   3) $ACME_HOME/deploy/3am-scan.sh (colocated; after sourcing 3am-scan.env)
#   4) $HOME/.local/lib/3am/3am-scan.sh
#
# Failure policy: scan failure is logged; deploy returns 0 so renew is not
# bricked (product may tighten later).

# shellcheck shell=bash
# shellcheck disable=SC3033

3am_scan_deploy() {
  _domain="$1"
  _keyfile="$2"
  _certfile="$3"
  _cafile="$4"
  _fullchain="$5"

  # Cron → acme.sh --cron does not source our env. Load defaults from the
  # ACME home next to this hook (written by one-curl install) — CORE-64.
  # Explicit THREEAM_SCAN / SCAN_SERVER / SCAN_HELPER win over the env file.
  _preset_scan="${THREEAM_SCAN:-}"
  _preset_helper="${SCAN_HELPER:-}"
  _preset_server="${SCAN_SERVER:-}"
  _hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  _acme_home="${THREEAM_ACME_HOME:-${LE_WORKING_DIR:-${_hook_dir%/deploy}}}"
  if [ -f "${_acme_home}/3am-scan.env" ]; then
    # shellcheck disable=SC1091
    . "${_acme_home}/3am-scan.env"
  fi
  [ -n "${_preset_scan}" ] && THREEAM_SCAN="${_preset_scan}"
  [ -n "${_preset_helper}" ] && SCAN_HELPER="${_preset_helper}"
  [ -n "${_preset_server}" ] && SCAN_SERVER="${_preset_server}"

  _scan=""
  if [ -n "${THREEAM_SCAN:-}" ] && [ -x "${THREEAM_SCAN}" ]; then
    _scan="${THREEAM_SCAN}"
  elif [ -n "${SCAN_HELPER:-}" ] && [ -x "${SCAN_HELPER}" ]; then
    _scan="${SCAN_HELPER}"
  elif [ -n "${THREEAM_LIB_DIR:-}" ] && [ -x "${THREEAM_LIB_DIR}/3am-scan.sh" ]; then
    _scan="${THREEAM_LIB_DIR}/3am-scan.sh"
  elif [ -x "${_acme_home}/deploy/3am-scan.sh" ]; then
    _scan="${_acme_home}/deploy/3am-scan.sh"
  elif [ -x "${HOME}/.local/lib/3am/3am-scan.sh" ]; then
    _scan="${HOME}/.local/lib/3am/3am-scan.sh"
  fi

  if [ -z "${_scan}" ]; then
    echo "3am_scan_deploy: companion 3am-scan.sh not found (set THREEAM_SCAN)" >&2
    return 0
  fi

  # Prefer fullchain for mTLS client presentation when present.
  if [ -n "${_fullchain}" ] && [ -f "${_fullchain}" ]; then
    SCAN_CERT="${_fullchain}"
  else
    SCAN_CERT="${_certfile}"
  fi
  SCAN_KEY="${_keyfile}"
  if [ -n "${_cafile}" ] && [ -f "${_cafile}" ]; then
    # Optional CA for verifying the scan server; leave unset if empty.
    : "${SCAN_CA:=}"
  fi

  export SCAN_CERT SCAN_KEY
  if [ -n "${SCAN_CA:-}" ]; then
    export SCAN_CA
  fi
  if [ -n "${SCAN_SERVER:-}" ]; then
    export SCAN_SERVER
  fi

  echo "3am_scan_deploy: domain=${_domain} running ${_scan}" >&2
  if ! "${_scan}"; then
    echo "3am_scan_deploy: scan failed (renew/deploy continues)" >&2
    return 0
  fi
  return 0
}
