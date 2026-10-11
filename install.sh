#!/usr/bin/env sh
# Copyright (c) 2026 Axelspire Inc.
# SPDX-License-Identifier: MIT
#
# One-curl install/update for per-customer acme.sh + datasink companion.
#
#   curl -fsSL https://axel.<id>.3am.global/root/agent/acme.sh/install.sh | sh
#
# Same URL upgrades: refreshes pinned upstream acme.sh archive AND companion/hook.
# Public agent GET only — no secrets in this script.
#
# Layout (served under agent/acme.sh/ — GPL archive stays pristine):
#   install.sh
#   pin                          # e.g. 3.0.7
#   INSTALL.md                   # operator instructions (baked placeholders)
#   manifest.json
#   archive/<pin>.tar.gz         # upstream GPL acme.sh (untouched)
#   tags/<pin>                   # sha256 of archive bytes (required when present)
#   companion/3am-scan.sh        # MIT companion (OUTSIDE GPL tarball)
#   companion/deploy/3am_scan.sh # thin deploy-hook launcher
#   companion/VERSION
#
# Optional env:
#   THREEAM_AGENT_BASE   download base (baked per-customer at publish when piped)
#   THREEAM_ACME_HOME    default ~/.acme.sh
#   THREEAM_LIB_DIR      default ~/.local/lib/3am
#   THREEAM_SCAN_SERVER  override derived https://scan.<id>.3am.global
#   ACME_EMAIL           email for acme.sh --install -m
#   THREEAM_SKIP_ACME=1  install companion/hook only
#   THREEAM_DIGEST_OPTIONAL=1  warn on tags mismatch instead of hard-fail
#
# shellcheck shell=sh

set -eu

_INSTALL_DIR=$(CDPATH='' cd -- "$(dirname "$0")" 2>/dev/null && pwd || true)
if [ -n "${_INSTALL_DIR}" ] && [ -f "${_INSTALL_DIR}/install-lib.sh" ]; then
  # shellcheck source=install-lib.sh
  . "${_INSTALL_DIR}/install-lib.sh"
else
  # Piped via curl|sh — lib functions are inlined below if not found.
  # When published from 3am-core, install.sh is self-contained (lib appended).
  if [ -n "${THREEAM_INSTALL_LIB:-}" ] && [ -f "${THREEAM_INSTALL_LIB}" ]; then
    # shellcheck source=/dev/null
    . "${THREEAM_INSTALL_LIB}"
  fi
fi

# Ensure helpers exist when this file is the self-contained published artifact.
if ! command -v threeam_resolve_agent_base >/dev/null 2>&1; then
  echo "install.sh: missing install-lib.sh (set THREEAM_INSTALL_LIB)" >&2
  exit 1
fi

threeam_install_main() {
  _cli_base="${1:-}"
  threeam_need curl
  threeam_need tar
  threeam_need mktemp

  AGENT_BASE=$(threeam_resolve_agent_base "${_cli_base}") || exit 1
  ACME_HOME=$(threeam_default_acme_home)
  LIB_DIR=$(threeam_default_lib_dir)
  SCAN_SERVER=$(threeam_derive_scan_server "${AGENT_BASE}") || exit 1

  threeam_info "agent base: ${AGENT_BASE}"
  threeam_info "acme home:  ${ACME_HOME}"
  threeam_info "lib dir:    ${LIB_DIR}"
  threeam_info "scan:       ${SCAN_SERVER}"

  PIN_RAW=$(threeam_fetch_to_stdout "$(threeam_url_join "${AGENT_BASE}" "pin")" | threeam_trim)
  PIN=$(threeam_sanitize_pin "${PIN_RAW}") || exit 1
  threeam_info "acme.sh pin: ${PIN}"

  WORK=$(mktemp -d "${TMPDIR:-/tmp}/3am-acme-install.XXXXXX")
  # shellcheck disable=SC2064
  trap 'rm -rf "${WORK}"' EXIT INT HUP

  if [ "${THREEAM_SKIP_ACME:-0}" != "1" ]; then
    ARCHIVE_URL=$(threeam_url_join "${AGENT_BASE}" "archive/${PIN}.tar.gz")
    threeam_info "fetching ${ARCHIVE_URL}"
    threeam_fetch "${ARCHIVE_URL}" "${WORK}/acme.tgz"

    # Integrity: tags/<pin> is a one-line sha256 of the archive bytes.
    TAG_URL=$(threeam_url_join "${AGENT_BASE}" "tags/${PIN}")
    if TAG_HEX=$(threeam_fetch_to_stdout "${TAG_URL}" 2>/dev/null | threeam_trim); then
      # Strip accidental banners — first hex token only.
      TAG_HEX=$(printf '%s' "${TAG_HEX}" | tr -c '0-9a-fA-F' '\n' | grep -E '^[0-9a-fA-F]{64}$' | head -n1 || true)
      if [ -n "${TAG_HEX}" ]; then
        if threeam_verify_archive_digest "${WORK}/acme.tgz" "${TAG_HEX}"; then
          threeam_info "archive sha256 matches tags/${PIN}"
        else
          threeam_die "tags/${PIN} digest does not match archive sha256"
        fi
      fi
    fi

    mkdir -p "${WORK}/extract"
    tar -xzf "${WORK}/acme.tgz" -C "${WORK}/extract"
    # Flat (acme.sh at root) or nested (acme.sh-<pin>/acme.sh) — CORE-43.
    if ! SRC=$(threeam_resolve_archive_src "${WORK}/extract" "acme.sh"); then
      threeam_die "acme.sh not found in archive (expected flat or nested layout)"
    fi
    threeam_info "archive source: ${SRC}"

    if threeam_should_upgrade_acme "${ACME_HOME}"; then
      threeam_info "existing acme.sh detected — refreshing script home from pin (working dir preserved)"
      if [ -x "${ACME_HOME}/acme.sh" ]; then
        (
          cd "${SRC}"
          if [ -n "${ACME_EMAIL:-}" ]; then
            ./acme.sh --install -m "${ACME_EMAIL}" --home "${ACME_HOME}" --force || \
              ./acme.sh --upgrade --home "${ACME_HOME}" || true
          else
            ./acme.sh --install --home "${ACME_HOME}" --force || \
              ./acme.sh --upgrade --home "${ACME_HOME}" || true
          fi
        )
      fi
    else
      # Upstream acme.sh refuses --install without crontab unless --force
      # (renew pre-check). Pass --force on fresh install too (CORE-64).
      threeam_info "installing acme.sh into ${ACME_HOME}"
      if ! command -v crontab >/dev/null 2>&1 && ! command -v fcrontab >/dev/null 2>&1; then
        threeam_info "no crontab/fcrontab — using acme.sh --force (upstream); install cron for renew jobs"
      fi
      (
        cd "${SRC}"
        if [ -n "${ACME_EMAIL:-}" ]; then
          ./acme.sh --install -m "${ACME_EMAIL}" --home "${ACME_HOME}" --force
        else
          ./acme.sh --install --home "${ACME_HOME}" --force
        fi
      ) || threeam_die "acme.sh --install failed"
    fi
  fi

  mkdir -p "${LIB_DIR}" "${ACME_HOME}/deploy"

  COMP_URL=$(threeam_url_join "${AGENT_BASE}" "companion/3am-scan.sh")
  HOOK_URL=$(threeam_url_join "${AGENT_BASE}" "companion/deploy/3am_scan.sh")
  VER_URL=$(threeam_url_join "${AGENT_BASE}" "companion/VERSION")

  COMP_DEST=$(threeam_companion_dest "${ACME_HOME}")
  threeam_info "fetching companion → ${COMP_DEST}"
  threeam_fetch "${COMP_URL}" "${COMP_DEST}"
  chmod +x "${COMP_DEST}"
  # Mirror into lib dir for tools that still look there.
  threeam_fetch "${COMP_URL}" "$(threeam_companion_lib_dest "${LIB_DIR}")"
  chmod +x "$(threeam_companion_lib_dest "${LIB_DIR}")"

  threeam_info "fetching thin deploy-hook"
  threeam_fetch "${HOOK_URL}" "$(threeam_hook_dest "${ACME_HOME}")"
  chmod +x "$(threeam_hook_dest "${ACME_HOME}")"

  if VER=$(threeam_fetch_to_stdout "${VER_URL}" 2>/dev/null | threeam_trim); then
    printf '%s\n' "${VER}" > "${LIB_DIR}/VERSION"
    printf '%s\n' "${VER}" > "${ACME_HOME}/deploy/VERSION"
    threeam_info "companion version: ${VER}"
  fi

  # Persist defaults for the hook (no secrets).
  ENV_FILE="${ACME_HOME}/3am-scan.env"
  cat > "${ENV_FILE}" <<EOF
# Generated by agent/acme.sh/install.sh — public defaults only, no secrets.
export SCAN_SERVER="${SCAN_SERVER}"
export THREEAM_SCAN="${COMP_DEST}"
export THREEAM_LIB_DIR="${LIB_DIR}"
export THREEAM_ACME_HOME="${ACME_HOME}"
EOF
  threeam_info "wrote ${ENV_FILE}"

  if [ "${THREEAM_SKIP_ACME:-0}" != "1" ] || [ -x "${ACME_HOME}/acme.sh" ] || [ -x "$(threeam_upstream_acme_path "${ACME_HOME}")" ]; then
    if [ -x "${ACME_HOME}/acme.sh" ] || [ -x "$(threeam_upstream_acme_path "${ACME_HOME}")" ]; then
      threeam_info "wrapping acme.sh so 3am_scan deploy-hook is always registered"
      threeam_write_acme_wrapper "${ACME_HOME}" || threeam_info "warning: could not wrap acme.sh"
      threeam_ensure_all_deploy_hooks "${ACME_HOME}"
    fi
  fi

  threeam_info "deploy-hook: 3am_scan (auto via wrapper; Le_DeployHook stamped on domain confs)"
  threeam_info "scheduling: one crontab line — acme.sh --cron (renew→hook + companion wake)"
  threeam_remove_legacy_scan_cron
  threeam_info "done"
}

# When sourced for tests, skip main.
if [ "${THREEAM_INSTALL_SOURCED:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

threeam_install_main "${1:-}"
