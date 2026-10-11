#!/usr/bin/env sh
# Copyright (c) 2026 Axelspire Inc.
# SPDX-License-Identifier: MIT
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

# Marker for our daily companion wake line (idempotent crontab edits).
threeam_acme_wrapper_marker() {
  printf '%s' '3am-acme-wrapper CORE-64'
}

threeam_upstream_acme_path() {
  # $1 = ACME_HOME
  printf '%s/acme.sh.upstream' "$1"
}

threeam_ensure_domain_deploy_hook() {
  # Args: domain.conf path. Ensure Le_DeployHook includes 3am_scan (idempotent).
  _conf="$1"
  [ -f "${_conf}" ] || return 0
  if grep -q "^Le_DeployHook=" "${_conf}" 2>/dev/null; then
    _cur=$(sed -n 's/^Le_DeployHook=//p' "${_conf}" | head -n1 | tr -d "'\"")
    case ",${_cur}," in
      *,3am_scan,*) return 0 ;;
    esac
    if [ -n "${_cur}" ]; then
      _new="${_cur},3am_scan"
    else
      _new="3am_scan"
    fi
    # portable in-place replace of the Le_DeployHook line
    _tmp="${_conf}.3am$$"
    sed "s/^Le_DeployHook=.*/Le_DeployHook='${_new}'/" "${_conf}" > "${_tmp}" && mv "${_tmp}" "${_conf}"
  else
    printf "Le_DeployHook='%s'\n" "3am_scan" >> "${_conf}"
  fi
}

threeam_ensure_all_deploy_hooks() {
  # Stamp Le_DeployHook=3am_scan on every domain conf under ACME_HOME.
  _home="$1"
  [ -d "${_home}" ] || return 0
  for _conf in "${_home}"/*/*.conf; do
    [ -f "${_conf}" ] || continue
    case "${_conf}" in
      */account.conf|*/ca.conf) continue ;;
    esac
    threeam_ensure_domain_deploy_hook "${_conf}"
  done
}

threeam_list_cert_domains() {
  # Print domain names (basename of *_ecc dirs without _ecc / plain dirs with .cer).
  _home="$1"
  for _di in "${_home}"/*/; do
    [ -d "${_di}" ] || continue
    _base=$(basename "${_di}")
    case "${_base}" in
      ca|dnsapi|deploy|notify|http.header) continue ;;
    esac
    _d="${_base%_ecc}"
    if ls "${_di}${_d}.cer" >/dev/null 2>&1 || ls "${_di}"/*.cer >/dev/null 2>&1; then
      printf '%s\n' "${_d}"
    fi
  done
}

threeam_write_acme_wrapper() {
  # Args: ACME_HOME. Moves real acme.sh → acme.sh.upstream and writes wrapper
  # that sources 3am-scan.env, stamps Le_DeployHook, and auto-deploys after
  # issue/sign-csr so the hook is ALWAYS in place after one-curl (CORE-64).
  _home="$1"
  _real="${_home}/acme.sh"
  _up=$(threeam_upstream_acme_path "${_home}")
  _marker=$(threeam_acme_wrapper_marker)
  [ -f "${_real}" ] || return 1
  if grep -q "${_marker}" "${_real}" 2>/dev/null; then
    # Already wrapped; keep existing upstream binary.
    [ -x "${_up}" ] || return 1
  else
    mv "${_real}" "${_up}"
    chmod +x "${_up}"
  fi
  cat > "${_real}" <<EOF
#!/usr/bin/env sh
# ${_marker} — rewritten by agent/acme.sh one-curl install; do not edit.
set -eu
ACME_HOME="${_home}"
UPSTREAM="${_up}"
ENV_FILE="\${ACME_HOME}/3am-scan.env"
if [ -f "\${ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  . "\${ENV_FILE}"
fi
export THREEAM_ACME_HOME="\${ACME_HOME}"

_is_issue=0
_is_signcsr=0
_is_cron=0
_is_deploy=0
_has_deploy_hook=0
_domain=""
_prev=""
for _a in "\$@"; do
  case "\${_prev}" in
    -d|--domain) _domain="\${_a}" ;;
  esac
  case "\${_a}" in
    --issue) _is_issue=1 ;;
    --sign-csr|--signcsr) _is_signcsr=1 ;;
    --cron) _is_cron=1 ;;
    --deploy) _is_deploy=1 ;;
    --deploy-hook) _has_deploy_hook=1 ;;
  esac
  _prev="\${_a}"
done

# Ensure every domain conf will invoke 3am_scan after renew (and before cron).
threeam_stamp_hooks() {
  for _conf in "\${ACME_HOME}"/*/*.conf; do
    [ -f "\${_conf}" ] || continue
    case "\${_conf}" in
      */account.conf|*/ca.conf) continue ;;
    esac
    if grep -q "^Le_DeployHook=" "\${_conf}" 2>/dev/null; then
      _cur=\$(sed -n 's/^Le_DeployHook=//p' "\${_conf}" | head -n1 | tr -d "'\\"")
      case ",\${_cur}," in
        *,3am_scan,*) ;;
        *)
          if [ -n "\${_cur}" ]; then _new="\${_cur},3am_scan"; else _new="3am_scan"; fi
          _tmp="\${_conf}.3am\$\$"
          sed "s/^Le_DeployHook=.*/Le_DeployHook='\${_new}'/" "\${_conf}" > "\${_tmp}" && mv "\${_tmp}" "\${_conf}"
          ;;
      esac
    else
      printf "Le_DeployHook='%s'\\n" "3am_scan" >> "\${_conf}"
    fi
  done
}

if [ "\${_is_cron}" = "1" ] || [ "\${_is_issue}" = "1" ] || [ "\${_is_signcsr}" = "1" ] || [ "\${_is_deploy}" = "1" ]; then
  threeam_stamp_hooks
fi

_run_deploy() {
  _d="\$1"
  [ -n "\${_d}" ] || return 0
  "\${UPSTREAM}" --home "\${ACME_HOME}" --deploy -d "\${_d}" --deploy-hook 3am_scan || true
}

# Inject --deploy-hook when operator uses --deploy without it.
if [ "\${_is_deploy}" = "1" ] && [ "\${_has_deploy_hook}" = "0" ]; then
  set -- "\$@" --deploy-hook 3am_scan
fi

_wake_companion() {
  # After --cron: run scan even when renew was not due (short-lived agent certs).
  # No second crontab line — CORE-65 / single-entrypoint direction.
  _scan="\${THREEAM_SCAN:-}"
  if [ -z "\${_scan}" ] || [ ! -x "\${_scan}" ]; then
    if [ -x "\${ACME_HOME}/deploy/3am-scan.sh" ]; then
      _scan="\${ACME_HOME}/deploy/3am-scan.sh"
    else
      return 0
    fi
  fi
  # Skip until a leaf cert exists (pre-enroll hosts).
  ls "\${ACME_HOME}"/*_ecc/*.cer >/dev/null 2>&1 || ls "\${ACME_HOME}"/*/*.cer >/dev/null 2>&1 || return 0
  "\${_scan}" >/dev/null 2>&1 || true
}

"\${UPSTREAM}" --home "\${ACME_HOME}" "\$@"
_rc=\$?

# issue/sign-csr do not apply --deploy-hook in upstream 3.1.x — force deploy.
if [ "\${_rc}" -eq 0 ] && { [ "\${_is_issue}" = "1" ] || [ "\${_is_signcsr}" = "1" ]; }; then
  threeam_stamp_hooks
  if [ -n "\${_domain}" ]; then
    _run_deploy "\${_domain}"
  else
    for _di in "\${ACME_HOME}"/*/; do
      [ -d "\${_di}" ] || continue
      _base=\$(basename "\${_di}")
      case "\${_base}" in ca|dnsapi|deploy|notify) continue ;; esac
      _d="\${_base%_ecc}"
      if ls "\${_di}\${_d}.cer" >/dev/null 2>&1 || ls "\${_di}"/*.cer >/dev/null 2>&1; then
        _run_deploy "\${_d}"
      fi
    done
  fi
fi

# Single crontab line: upstream --cron → our wrapper also wakes companion.
if [ "\${_is_cron}" = "1" ]; then
  _wake_companion
fi

exit "\${_rc}"
EOF
  chmod +x "${_real}"
}

threeam_scan_cron_marker() {
  # Legacy marker from CORE-64 dual-cron; used only to strip old lines.
  printf '%s' '# 3am-scan daily wake (CORE-64)'
}

threeam_strip_legacy_scan_cron() {
  # Remove the CORE-64 dual-cron wake line if present; keep upstream --cron only.
  # stdin crontab → stdout without our legacy marker lines.
  _marker=$(threeam_scan_cron_marker)
  while IFS= read -r _row || [ -n "${_row}" ]; do
    case "${_row}" in
      *"${_marker}"*) continue ;;
    esac
    printf '%s\n' "${_row}"
  done
}

threeam_remove_legacy_scan_cron() {
  # Idempotent cleanup of the complex daily wake cron (operator feedback / CORE-65).
  if [ "${THREEAM_SKIP_SCAN_CRON:-0}" = "1" ]; then
    return 0
  fi
  if ! command -v crontab >/dev/null 2>&1; then
    return 0
  fi
  _existing=$(crontab -l 2>/dev/null || true)
  [ -n "${_existing}" ] || return 0
  case "${_existing}" in
    *"$(threeam_scan_cron_marker)"*) ;;
    *) return 0 ;;
  esac
  _tmp=$(mktemp "${TMPDIR:-/tmp}/3am-scan-cron.XXXXXX")
  printf '%s\n' "${_existing}" | threeam_strip_legacy_scan_cron > "${_tmp}"
  if [ -s "${_tmp}" ]; then
    crontab "${_tmp}" || true
  else
    crontab -r 2>/dev/null || crontab /dev/null 2>/dev/null || true
  fi
  rm -f "${_tmp}"
  threeam_info "removed legacy daily 3am-scan wake cron (scan runs from acme.sh --cron wrapper)"
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
