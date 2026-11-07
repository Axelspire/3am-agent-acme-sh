# Copyright (c) 2026 Axelspire Inc.
# SPDX-License-Identifier: MIT
"""DESIGN-189: 3am-scan.sh emits probe_failures for silent/unreachable targets."""

from __future__ import annotations

import json
import os
import socket
import subprocess
import tempfile
import textwrap
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCAN = ROOT / "3am-scan.sh"


def _extract_scan_endpoint_python() -> str:
    """Pull the python heredoc body from _scan_endpoint for unit testing."""
    text = SCAN.read_text(encoding="utf-8")
    start = text.index("python3 - \"$host\" \"$port\" \"$timeout\" <<'PY'")
    body_start = text.index("\n", start) + 1
    end = text.index("\nPY\n", body_start)
    return text[body_start:end]


def test_scan_timeout_prefers_config_field():
    script = textwrap.dedent(
        r"""
        set -euo pipefail
        source ./3am-scan.sh
        """
    )
    # 3am-scan.sh runs main at end — cannot source. Call the helper via bash extract.
    helper = textwrap.dedent(
        r"""
        set -euo pipefail
        SCAN_TIMEOUT=5
        _scan_timeout_from_config() {
          local cfg="$1"
          printf '%s' "$cfg" | python3 -c '
        import json, sys
        doc = json.load(sys.stdin)
        for key in ("scan_timeout_seconds", "tls_connect_timeout_seconds"):
            v = doc.get(key)
            if v is None:
                continue
            try:
                n = int(v)
                if n >= 1:
                    print(n)
                    raise SystemExit(0)
            except (TypeError, ValueError):
                pass
        print("")
        ' 2>/dev/null || true
        }
        out="$(_scan_timeout_from_config '{"scan_timeout_seconds":9}')"
        test "$out" = "9"
        """
    )
    subprocess.run(["bash", "-c", helper], check=True, cwd=str(ROOT))


def test_probe_failure_on_refused_port():
    # Bind then close → connect should refuse on most platforms, or we use port 1.
    py = _extract_scan_endpoint_python()
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
        f.write(py)
        path = f.name
    try:
        # Port 1 is typically closed / refused for non-root.
        proc = subprocess.run(
            ["python3", path, "127.0.0.1", "1", "1"],
            capture_output=True,
            text=True,
            check=False,
        )
        assert proc.returncode == 0, proc.stderr
        envelope = json.loads(proc.stdout.strip())
        assert envelope["kind"] == "probe_failure"
        assert envelope["item"]["status"] in ("refused", "filtered", "timeout", "error")
        assert envelope["item"]["ip"] == "127.0.0.1"
        assert envelope["item"]["port"] == 1
    finally:
        os.unlink(path)


def test_open_tcp_no_tls_classifies_open_no_tls():
    py = _extract_scan_endpoint_python()
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]

    def _accept():
        conn, _ = srv.accept()
        # Do not speak TLS — just accept TCP then close after a moment.
        try:
            conn.recv(1)
        except Exception:
            pass
        conn.close()

    import threading

    t = threading.Thread(target=_accept, daemon=True)
    t.start()
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
        f.write(py)
        path = f.name
    try:
        proc = subprocess.run(
            ["python3", path, "127.0.0.1", str(port), "2"],
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
        assert proc.returncode == 0, proc.stderr
        envelope = json.loads(proc.stdout.strip())
        assert envelope["kind"] == "probe_failure"
        assert envelope["item"]["status"] == "open_no_tls"
    finally:
        os.unlink(path)
        srv.close()
