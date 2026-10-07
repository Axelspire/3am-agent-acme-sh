#!/usr/bin/env sh
# Copyright (c) 2026 Axelspire Inc. All rights reserved.
# Proprietary. Unauthorized use prohibited. support3am@axelspire.com
#
# Testable helpers for acme.sh + companion one-curl install/update.
# Sourced by install.sh. No network I/O here — keep unit-testable.
#
# shellcheck shell=sh

# Published install.sh rewrites the bake marker below (CORE-33).
# Detection uses https://* so the marker string must appear only in printf.
threeam_published_agent_base() {
  # bake-marker: next line is replaced at S3 publish time
  printf '%s' '@THREEAM_AGENT_BASE@'
}

threeam_trim() {
  # trim leading/trailing whitespace from stdin → stdout
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

threeam_sanitize_pin() {
  # Allow semver-ish pins and "master"; reject path traversal.
  _pin="$1"
  case "${_pin}" in
    ''|*/*|*..*|*\\*)
      echo "invalid pin: ${_pin}" >&2
      return 1
      ;;
    master|[0-9]*|[0-9]*.[0-9]*|[0-9]*.[0-9]*.[0-9]*|[0-9]*.[0-9]*.[0-9]*[a-zA-Z]*)
      printf '%s' "${_pin}"
      return 0
      ;;
    *)
      echo "invalid pin: ${_pin}" >&2
      return 1
      ;;
  esac
}

threeam_resolve_agent_base() {
  # Args: optional CLI base ($1). Env: THREEAM_AGENT_BASE, THREEAM_INSTALL_URL,
  # THREEAM_AGENT_BASE_DEFAULT (publish-time).
  _arg="${1:-}"
  _base="${THREEAM_AGENT_BASE:-}"
  if [ -z "${_base}" ] && [ -n "${_arg}" ]; then
    _base="${_arg}"
  fi
  if [ -z "${_base}" ] && [ -n "${THREEAM_INSTALL_URL:-}" ]; then
    _base=$(dirname "${THREEAM_INSTALL_URL}")
  fi
  if [ -z "${_base}" ] && [ -n "${THREEAM_AGENT_BASE_DEFAULT:-}" ]; then
    case "${THREEAM_AGENT_BASE_DEFAULT}" in
      https://*|http://*) _base="${THREEAM_AGENT_BASE_DEFAULT}" ;;
    esac
  fi
  if [ -z "${_base}" ]; then
    _pub=$(threeam_published_agent_base)
    case "${_pub}" in
      https://*|http://*) _base="${_pub}" ;;
    esac
  fi
  if [ -z "${_base}" ]; then
    echo "THREEAM_AGENT_BASE is required (or pass base URL as \$1)" >&2
    return 1
  fi
  # Strip trailing slashes.
  printf '%s' "${_base}" | sed 's|/*$||'
}

threeam_derive_scan_server() {
  # From https://axel.<id>.3am.global/root/agent/acme.sh → https://scan.<id>.3am.global
  _base="$1"
  _host=$(printf '%s' "${_base}" | sed -n 's|^https\{0,1\}://\([^/]*\)/.*|\1|p')
  case "${_host}" in
    axel.*.3am.global)
      _id=$(printf '%s' "${_host}" | sed -n 's/^axel\.\(.*\)\.3am\.global$/\1/p')
      if [ -n "${_id}" ]; then
        printf 'https://scan.%s.3am.global' "${_id}"
        return 0
      fi
      ;;
  esac
  if [ -n "${THREEAM_SCAN_SERVER:-}" ]; then
    printf '%s' "${THREEAM_SCAN_SERVER}"
    return 0
  fi
  echo "could not derive SCAN_SERVER from agent base; set THREEAM_SCAN_SERVER" >&2
  return 1
}

threeam_default_acme_home() {
  printf '%s' "${THREEAM_ACME_HOME:-${HOME}/.acme.sh}"
}

threeam_default_lib_dir() {
  printf '%s' "${THREEAM_LIB_DIR:-${HOME}/.local/lib/3am}"
}

threeam_url_join() {
  # Join base + relative path with exactly one slash.
  _base="$1"
  _rel="$2"
  _base="${_base%/}"
  _rel="${_rel#/}"
  printf '%s/%s' "${_base}" "${_rel}"
}

threeam_hook_dest() {
  _home="$1"
  printf '%s/deploy/3am_scan.sh' "${_home}"
}

threeam_companion_dest() {
  # Colocate with thin hook under acme.sh deploy/ (Phase 4).
  # $1 = ACME_HOME (not lib dir).
  _home="$1"
  printf '%s/deploy/3am-scan.sh' "${_home}"
}

threeam_companion_lib_dest() {
  # Optional lib copy for tooling that expects ~/.local/lib/3am.
  _lib="$1"
  printf '%s/3am-scan.sh' "${_lib}"
}

threeam_should_upgrade_acme() {
  # Exit 0 if acme.sh already installed at home.
  _home="$1"
  if [ -x "${_home}/acme.sh" ]; then
    return 0
  fi
  return 1
}

threeam_resolve_archive_src() {
  # Locate upstream tree after tar extract.
  # Accepts flat layouts (entrypoint at extract root) and nested
  # GitHub-style dirs (acme.sh-<pin>/entrypoint).
  # Args: extract_dir [entrypoint_name]
  _extract="$1"
  _entry="${2:-acme.sh}"
  if [ -x "${_extract}/${_entry}" ]; then
    printf '%s' "${_extract}"
    return 0
  fi
  for _d in "${_extract}"/*; do
    [ -d "${_d}" ] || continue
    if [ -x "${_d}/${_entry}" ]; then
      printf '%s' "${_d}"
      return 0
    fi
  done
  return 1
}

threeam_sha256_file() {
  # Print sha256 hex of file $1.
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
    return 0
  fi
  return 1
}

threeam_verify_archive_digest() {
  # Args: archive_path expected_hex
  # Hard-fail when expected is non-empty and does not match (CORE-44).
  # Set THREEAM_DIGEST_OPTIONAL=1 to warn only (legacy).
  _archive="$1"
  _want="$2"
  [ -n "${_want}" ] || return 0
  _got=$(threeam_sha256_file "${_archive}") || {
    echo "sha256 tool missing; cannot verify archive digest" >&2
    return 1
  }
  if [ "${_got}" = "${_want}" ]; then
    return 0
  fi
  if [ "${THREEAM_DIGEST_OPTIONAL:-0}" = "1" ]; then
    echo "warning: archive sha256 ${_got} != tags ${_want} (continuing; THREEAM_DIGEST_OPTIONAL=1)" >&2
    return 0
  fi
  echo "archive sha256 mismatch: got ${_got} want ${_want}" >&2
  return 1
}

threeam_die() { echo "3am-agent-install: ERROR: $*" >&2; exit 1; }
threeam_info() { echo "3am-agent-install: $*" >&2; }

threeam_need() {
  command -v "$1" >/dev/null 2>&1 || threeam_die "missing dependency: $1"
}

threeam_fetch() {
  # $1=url $2=dest
  curl -fsSL "$1" -o "$2" || threeam_die "download failed: $1"
}

threeam_fetch_to_stdout() {
  curl -fsSL "$1"
}
