#!/usr/bin/env sh
# Copyright (c) 2026 Axelspire Inc. All rights reserved.
# Proprietary. Unauthorized use prohibited. support3am@axelspire.com
#
# A2 smoke: serve a candidate bundle over localhost HTTP and run install.sh
# against it (digest check + extract + acme.sh --install into a temp HOME).
#
# Usage:
#   ./scripts/smoke-candidate.sh [BUNDLE_DIR]
# Default BUNDLE_DIR: ./dist/candidate-bundle

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BUNDLE="${1:-${ROOT}/dist/candidate-bundle}"
[ -d "${BUNDLE}" ] || { echo "smoke-candidate: missing bundle ${BUNDLE}" >&2; exit 1; }
[ -f "${BUNDLE}/install.sh" ] || { echo "smoke-candidate: no install.sh in bundle" >&2; exit 1; }
[ -f "${BUNDLE}/pin" ] || { echo "smoke-candidate: no pin in bundle" >&2; exit 1; }

PIN=$(tr -d '[:space:]' < "${BUNDLE}/pin")
WANT=$(tr -d '[:space:]' < "${BUNDLE}/tags/${PIN}")
GOT=$(
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${BUNDLE}/archive/${PIN}.tar.gz" | awk '{print $1}'
  else
    shasum -a 256 "${BUNDLE}/archive/${PIN}.tar.gz" | awk '{print $1}'
  fi
)
[ "${GOT}" = "${WANT}" ] || {
  echo "smoke-candidate: digest mismatch got=${GOT} want=${WANT}" >&2
  exit 1
}
echo "smoke-candidate: archive sha256 OK (${GOT})"

# Confirm entrypoint present in archive
tar -tzf "${BUNDLE}/archive/${PIN}.tar.gz" | grep -E '(^|/)acme\.sh$' >/dev/null \
  || { echo "smoke-candidate: acme.sh entrypoint missing in archive" >&2; exit 1; }
echo "smoke-candidate: archive layout OK"

PORT=${SMOKE_PORT:-8765}
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"; kill "${SERVER_PID:-}" 2>/dev/null || true' EXIT

HOME_DIR="${WORK}/home"
mkdir -p "${HOME_DIR}"
export HOME="${HOME_DIR}"

# acme.sh --install refuses without crontab unless --force; fresh install
# path does not pass --force. Provide cron when possible (CI/ubuntu).
if ! command -v crontab >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq >/dev/null 2>&1 || true
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cron >/dev/null 2>&1 || true
  fi
fi
# Fallback: seed a fake existing install so installer uses --force refresh path
if ! command -v crontab >/dev/null 2>&1; then
  mkdir -p "${HOME}/.acme.sh"
  printf '#!/bin/sh\necho stub\n' > "${HOME}/.acme.sh/acme.sh"
  chmod +x "${HOME}/.acme.sh/acme.sh"
fi

# Local static server for THREEAM_AGENT_BASE
python3 -m http.server "${PORT}" --directory "${BUNDLE}" >/tmp/smoke-http.log 2>&1 &
SERVER_PID=$!
sleep 1

BASE="http://127.0.0.1:${PORT}"
echo "smoke-candidate: THREEAM_AGENT_BASE=${BASE}"

# Localhost base cannot derive scan.<id>.3am.global — set explicitly.
# Companion/hook still install; we do not call the scan API in smoke.
set +e
THREEAM_AGENT_BASE="${BASE}" \
  THREEAM_SCAN_SERVER="${THREEAM_SCAN_SERVER:-https://scan.smoke.invalid}" \
  ACME_EMAIL="${ACME_EMAIL:-smoke@example.invalid}" \
  THREEAM_DIGEST_OPTIONAL=0 \
  sh "${BUNDLE}/install.sh" "${BASE}" >"${WORK}/install.log" 2>&1
RC=$?
set -e

if [ "${RC}" -ne 0 ]; then
  echo "smoke-candidate: install.sh failed (rc=${RC}); log:" >&2
  tail -n 80 "${WORK}/install.log" >&2 || true
  exit "${RC}"
fi

# acme.sh should exist under HOME after --install
if [ ! -x "${HOME}/.acme.sh/acme.sh" ] && [ ! -f "${HOME}/.acme.sh/acme.sh" ]; then
  echo "smoke-candidate: ~/.acme.sh/acme.sh missing after install" >&2
  tail -n 80 "${WORK}/install.log" >&2 || true
  exit 1
fi

# Companion + thin hook under ~/.acme.sh/deploy/
if [ ! -f "${HOME}/.acme.sh/deploy/3am_scan.sh" ]; then
  echo "smoke-candidate: deploy hook missing" >&2
  tail -n 80 "${WORK}/install.log" >&2 || true
  exit 1
fi
if [ ! -f "${HOME}/.acme.sh/deploy/3am-scan.sh" ] && [ ! -f "${HOME}/.local/lib/3am/3am-scan.sh" ]; then
  echo "smoke-candidate: companion missing" >&2
  tail -n 80 "${WORK}/install.log" >&2 || true
  exit 1
fi

echo "smoke-candidate: OK (pin=${PIN})"
