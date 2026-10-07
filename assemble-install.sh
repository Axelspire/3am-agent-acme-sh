#!/usr/bin/env sh
# Copyright (c) 2026 Axelspire Inc. All rights reserved.
# Proprietary. Unauthorized use prohibited. support3am@axelspire.com
#
# Assemble a self-contained install.sh for 3am-core S3 publish
# (curl|sh cannot source sibling install-lib.sh).
#
# Usage:
#   ./assemble-install.sh [agent_base_url] > install.published.sh
#   # agent_base_url replaces @THREEAM_AGENT_BASE@ (optional; empty keeps marker)

set -eu
DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
BASE_URL="${1:-}"

{
  echo "#!/usr/bin/env sh"
  echo "# AUTO-ASSEMBLED from install-lib.sh + install.sh — do not edit in core by hand."
  echo "# Source of truth: Axelspire/3am-agent-acme-sh"
  echo "#"
  sed '1,2d' "${DIR}/install-lib.sh"
  echo ""
  echo "# --- install.sh body ---"
  # Drop shebang and the lib-source bootstrap; call main directly.
  awk '
    BEGIN { skip=1 }
    /^threeam_install_main\(\)/ { skip=0 }
    skip==0 { print }
  ' "${DIR}/install.sh"
} > "${TMPDIR:-/tmp}/3am-install.assembled.$$"
# Prepend set -eu after headers for the published file
{
  head -n 5 "${TMPDIR:-/tmp}/3am-install.assembled.$$"
  echo "set -eu"
  tail -n +6 "${TMPDIR:-/tmp}/3am-install.assembled.$$"
} > "${TMPDIR:-/tmp}/3am-install.assembled2.$$"

if [ -n "${BASE_URL}" ]; then
  sed "s|@THREEAM_AGENT_BASE@|${BASE_URL}|g" "${TMPDIR:-/tmp}/3am-install.assembled2.$$"
else
  cat "${TMPDIR:-/tmp}/3am-install.assembled2.$$"
fi
rm -f "${TMPDIR:-/tmp}/3am-install.assembled.$$" "${TMPDIR:-/tmp}/3am-install.assembled2.$$"
