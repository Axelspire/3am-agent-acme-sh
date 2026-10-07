#!/usr/bin/env sh
# Copyright (c) 2026 Axelspire Inc. All rights reserved.
# Proprietary. Unauthorized use prohibited. support3am@axelspire.com
#
# Vendor a pristine upstream acme.sh release into this repo's pin/tags
# (and local archive/*.tar.gz — gitignored) for publish sync.
#
# Usage:
#   ./scripts/vendor-pin.sh <pin> [--sync-core PATH_TO_3AM_CORE]
#
# Examples:
#   ./scripts/vendor-pin.sh 3.1.0
#   ./scripts/vendor-pin.sh 3.1.0 --sync-core ../3am-core
#
# Then: bump fleet agents.acme.sh.pin (and core module tag after sync),
# apply customer-deploy. Hosts pick up via one-curl (not acme.sh --upgrade).

set -eu

PIN="${1:-}"
if [ -z "${PIN}" ] || [ "${PIN}" = "-h" ] || [ "${PIN}" = "--help" ]; then
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi
shift

SYNC_CORE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sync-core)
      SYNC_CORE="${2:-}"
      [ -n "${SYNC_CORE}" ] || { echo "vendor-pin: --sync-core needs a path" >&2; exit 1; }
      shift 2
      ;;
    *)
      echo "vendor-pin: unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

# Reject path traversal / junk
case "${PIN}" in
  *[!A-Za-z0-9._-]* | "" | .* | */* | *..*)
    echo "vendor-pin: invalid pin: ${PIN}" >&2
    exit 1
    ;;
esac

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "${ROOT}"

ARCHIVE_DIR="${ROOT}/archive"
TAGS_DIR="${ROOT}/tags"
mkdir -p "${ARCHIVE_DIR}" "${TAGS_DIR}"

OUT="${ARCHIVE_DIR}/${PIN}.tar.gz"
URL="https://github.com/acmesh-official/acme.sh/archive/refs/tags/${PIN}.tar.gz"

echo "vendor-pin: fetching ${URL}"
curl -fsSL -o "${OUT}.tmp" "${URL}"
mv "${OUT}.tmp" "${OUT}"

if command -v sha256sum >/dev/null 2>&1; then
  DIGEST=$(sha256sum "${OUT}" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  DIGEST=$(shasum -a 256 "${OUT}" | awk '{print $1}')
else
  echo "vendor-pin: need sha256sum or shasum" >&2
  exit 1
fi

printf '%s\n' "${DIGEST}" > "${TAGS_DIR}/${PIN}"
printf '%s\n' "${PIN}" > "${ROOT}/pin"

# Quick layout check: archive must contain an acme.sh entrypoint somewhere.
PROBE=$(mktemp -d)
trap 'rm -rf "${PROBE}"' EXIT
tar -tzf "${OUT}" | head -n 40 > "${PROBE}/list"
if ! grep -E '(^|/)acme\.sh$' "${PROBE}/list" >/dev/null 2>&1; then
  echo "vendor-pin: ERROR: no acme.sh entrypoint in archive (bad pin or asset)" >&2
  echo "vendor-pin: first entries:" >&2
  head -n 20 "${PROBE}/list" >&2
  exit 1
fi

MODULE=$(tr -d '[:space:]' < "${ROOT}/MODULE")
COMPANION=$(tr -d '[:space:]' < "${ROOT}/VERSION")
# Rewrite manifest pin + digest; keep other fields.
python3 - "${ROOT}/manifest.json" "${PIN}" "${DIGEST}" "${MODULE}" "${COMPANION}" <<'PY'
import json, sys
path, pin, digest, module, companion = sys.argv[1:6]
with open(path, encoding="utf-8") as f:
    m = json.load(f)
m["pin"] = pin
m["archive_sha256"] = digest
m["module"] = module
m["companion"] = companion
with open(path, "w", encoding="utf-8") as f:
    json.dump(m, f, indent=2)
    f.write("\n")
PY

echo "vendor-pin: wrote archive/${PIN}.tar.gz"
echo "vendor-pin: tags/${PIN} = ${DIGEST}"
echo "vendor-pin: pin -> ${PIN}"
echo "vendor-pin: updated manifest.json"

if [ -n "${SYNC_CORE}" ]; then
  DEST="${SYNC_CORE}/deploy/agents/acmesh"
  if [ ! -d "${DEST}" ]; then
    echo "vendor-pin: core publish tree missing: ${DEST}" >&2
    exit 1
  fi
  mkdir -p "${DEST}/archive" "${DEST}/tags"
  cp -f "${OUT}" "${DEST}/archive/${PIN}.tar.gz"
  cp -f "${TAGS_DIR}/${PIN}" "${DEST}/tags/${PIN}"
  cp -f "${ROOT}/pin" "${DEST}/pin"
  cp -f "${ROOT}/manifest.json" "${DEST}/manifest.json"
  echo "vendor-pin: synced pin/archive/tags/manifest -> ${DEST}"
  echo "vendor-pin: next: PR 3am-core, bump fleet agents.acme.sh.pin + core:, apply"
fi

echo "vendor-pin: done"
echo "vendor-pin: commit in this repo: pin, tags/${PIN}, manifest.json"
echo "vendor-pin: the .tar.gz stays local (gitignored); --sync-core copied it into 3am-core for deploy/S3"
