#!/usr/bin/env sh
# Copyright (c) 2026 Axelspire Inc. All rights reserved.
# Proprietary. Unauthorized use prohibited. support3am@axelspire.com
#
# Build a candidate publish bundle directory from the current tree
# (after vendor-pin.sh). Output is suitable for a GitHub prerelease (A2).
#
# Usage:
#   ./scripts/build-candidate-bundle.sh [OUT_DIR]
# Default OUT_DIR: ./dist/candidate-bundle

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "${ROOT}"

OUT="${1:-${ROOT}/dist/candidate-bundle}"
rm -rf "${OUT}"
mkdir -p "${OUT}/companion/deploy" "${OUT}/archive" "${OUT}/tags"

PIN=$(tr -d '[:space:]' < "${ROOT}/pin")
MODULE=$(tr -d '[:space:]' < "${ROOT}/MODULE")
[ -n "${PIN}" ] || { echo "build-candidate-bundle: missing pin" >&2; exit 1; }
[ -f "${ROOT}/archive/${PIN}.tar.gz" ] || {
  echo "build-candidate-bundle: missing archive/${PIN}.tar.gz — run vendor-pin.sh first" >&2
  exit 1
}
[ -f "${ROOT}/tags/${PIN}" ] || {
  echo "build-candidate-bundle: missing tags/${PIN}" >&2
  exit 1
}

# Assembled one-file installer (same as publish path)
./assemble-install.sh > "${OUT}/install.sh"
chmod +x "${OUT}/install.sh"

cp -f "${ROOT}/INSTALL.md" "${OUT}/INSTALL.md"
cp -f "${ROOT}/pin" "${OUT}/pin"
cp -f "${ROOT}/MODULE" "${OUT}/MODULE"
cp -f "${ROOT}/VERSION" "${OUT}/companion/VERSION"
cp -f "${ROOT}/manifest.json" "${OUT}/manifest.json"
cp -f "${ROOT}/tags/${PIN}" "${OUT}/tags/${PIN}"
cp -f "${ROOT}/archive/${PIN}.tar.gz" "${OUT}/archive/${PIN}.tar.gz"
cp -f "${ROOT}/3am-scan.sh" "${OUT}/companion/3am-scan.sh"
cp -f "${ROOT}/deploy/3am_scan.sh" "${OUT}/companion/deploy/3am_scan.sh"
chmod +x "${OUT}/companion/3am-scan.sh" "${OUT}/companion/deploy/3am_scan.sh"

# Convenience: flat digest file for release notes
cp -f "${ROOT}/tags/${PIN}" "${OUT}/ARCHIVE_SHA256.txt"

CANDIDATE_TAG="candidate-${MODULE}+pin-${PIN}"
printf '%s\n' "${CANDIDATE_TAG}" > "${OUT}/CANDIDATE_TAG.txt"
printf '%s\n' "${PIN}" > "${OUT}/UPSTREAM_PIN.txt"

echo "build-candidate-bundle: wrote ${OUT}"
echo "build-candidate-bundle: candidate tag ${CANDIDATE_TAG}"
