# Copyright (c) 2026 Axelspire Inc.
# SPDX-License-Identifier: MIT
"""Two-pin upgrade path through the real install.sh (mocked curl, fake upstream).

Re-running the one-curl installer is the agent upgrade path: it must swap the
pinned upstream acme.sh and companion, keep the wrapper, and refuse a tampered
archive without touching the installed pin.
"""

from __future__ import annotations

import hashlib
import io
import os
import subprocess
import tarfile
import textwrap
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LIB = REPO / "install-lib.sh"
HOOK = REPO / "deploy" / "3am_scan.sh"
INSTALL = REPO / "install.sh"

AGENT_BASE = "https://axel.demo.3am.global/root/agent/acme.sh"
WRAPPER_MARKER = "3am-acme-wrapper CORE-64"

FAKE_UPSTREAM = textwrap.dedent(
    """\
    #!/bin/sh
    # FAKE_UPSTREAM_PIN={pin}
    home=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --home) home="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [ -n "$home" ] || exit 2
    mkdir -p "$home"
    cp "$0" "$home/acme.sh"
    chmod +x "$home/acme.sh"
    """
)


def _archive_bytes(pin: str) -> bytes:
    body = FAKE_UPSTREAM.format(pin=pin).encode()
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        info = tarfile.TarInfo(f"acme.sh-{pin}/acme.sh")
        info.size = len(body)
        info.mode = 0o755
        tar.addfile(info, io.BytesIO(body))
    return buf.getvalue()


def _publish(base: Path, pin: str, companion: str, *, bad_digest: bool = False) -> None:
    """Write the served agent/acme.sh/ layout for one pin."""
    (base / "archive").mkdir(parents=True, exist_ok=True)
    (base / "tags").mkdir(exist_ok=True)
    (base / "companion" / "deploy").mkdir(parents=True, exist_ok=True)
    data = _archive_bytes(pin)
    (base / "archive" / f"{pin}.tar.gz").write_bytes(data)
    digest = "0" * 64 if bad_digest else hashlib.sha256(data).hexdigest()
    (base / "tags" / pin).write_text(digest + "\n")
    (base / "pin").write_text(pin + "\n")
    (base / "companion" / "3am-scan.sh").write_text(
        f"#!/bin/sh\n# companion {companion}\necho scan\n"
    )
    (base / "companion" / "deploy" / "3am_scan.sh").write_text(HOOK.read_text())
    (base / "companion" / "VERSION").write_text(companion + "\n")


def _curl_shim(bin_dir: Path, base: Path) -> None:
    bin_dir.mkdir(exist_ok=True)
    shim = bin_dir / "curl"
    shim.write_text(
        textwrap.dedent(
            f"""\
            #!/bin/sh
            set -eu
            out=""
            url=""
            while [ $# -gt 0 ]; do
              case "$1" in
                -o) out="$2"; shift 2 ;;
                -fsSL|-sS|-f|-s|-L) shift ;;
                *) url="$1"; shift ;;
              esac
            done
            rel="${{url#{AGENT_BASE}/}}"
            src="{base}/$rel"
            [ -f "$src" ] || exit 22
            if [ -n "$out" ]; then
              cp "$src" "$out"
            else
              cat "$src"
            fi
            """
        )
    )
    shim.chmod(0o755)


def _install(tmp_path: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    for k in (
        "THREEAM_ACME_HOME",
        "THREEAM_LIB_DIR",
        "THREEAM_SCAN",
        "SCAN_HELPER",
        "THREEAM_INSTALL_URL",
        "THREEAM_SCAN_SERVER",
        "THREEAM_SKIP_ACME",
        "THREEAM_DIGEST_OPTIONAL",
        "ACME_EMAIL",
    ):
        env.pop(k, None)
    env.update(
        {
            "PATH": f"{tmp_path / 'bin'}:{env.get('PATH', '')}",
            "HOME": str(tmp_path / "home"),
            "THREEAM_AGENT_BASE": AGENT_BASE,
            "THREEAM_SKIP_SCAN_CRON": "1",
            "THREEAM_INSTALL_LIB": str(LIB),
        }
    )
    return subprocess.run(
        ["sh", str(INSTALL)], capture_output=True, text=True, env=env, check=False
    )


def _setup(tmp_path: Path) -> Path:
    base = tmp_path / "base"
    (tmp_path / "home").mkdir()
    _curl_shim(tmp_path / "bin", base)
    return base


class TestUpgradePath:
    def test_rerun_upgrades_pin_and_companion(self, tmp_path):
        base = _setup(tmp_path)
        acme_home = tmp_path / "home" / ".acme.sh"

        _publish(base, "3.1.0", "1.0.0")
        r1 = _install(tmp_path)
        assert r1.returncode == 0, r1.stderr
        assert "FAKE_UPSTREAM_PIN=3.1.0" in (acme_home / "acme.sh.upstream").read_text()
        assert WRAPPER_MARKER in (acme_home / "acme.sh").read_text()
        assert (acme_home / "deploy" / "VERSION").read_text().strip() == "1.0.0"

        _publish(base, "3.1.1", "1.1.0")
        r2 = _install(tmp_path)
        assert r2.returncode == 0, r2.stderr
        assert "existing acme.sh detected" in r2.stderr
        upstream = (acme_home / "acme.sh.upstream").read_text()
        assert "FAKE_UPSTREAM_PIN=3.1.1" in upstream
        assert WRAPPER_MARKER not in upstream
        assert WRAPPER_MARKER in (acme_home / "acme.sh").read_text()
        assert (acme_home / "deploy" / "VERSION").read_text().strip() == "1.1.0"
        assert "companion 1.1.0" in (acme_home / "deploy" / "3am-scan.sh").read_text()

    def test_tampered_upgrade_keeps_installed_pin(self, tmp_path):
        base = _setup(tmp_path)
        acme_home = tmp_path / "home" / ".acme.sh"

        _publish(base, "3.1.0", "1.0.0")
        assert _install(tmp_path).returncode == 0

        _publish(base, "3.1.1", "1.1.0", bad_digest=True)
        r = _install(tmp_path)
        assert r.returncode != 0
        assert "digest does not match" in r.stderr
        assert "FAKE_UPSTREAM_PIN=3.1.0" in (acme_home / "acme.sh.upstream").read_text()
        assert WRAPPER_MARKER in (acme_home / "acme.sh").read_text()
        assert (acme_home / "deploy" / "VERSION").read_text().strip() == "1.0.0"
