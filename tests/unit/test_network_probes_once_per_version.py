# Copyright (c) 2026 Axelspire Inc.
# SPDX-License-Identifier: MIT
"""DESIGN-190: network probes run once per companion VERSION."""

from __future__ import annotations

import json
import os
import subprocess
import textwrap
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCAN_SH = REPO / "3am-scan.sh"


def _extract_probe_funcs() -> str:
    """Pull DESIGN-190 probe helper + _run_network_probes from 3am-scan.sh."""
    text = SCAN_SH.read_text(encoding="utf-8")
    start = text.index("_agent_version()")
    end = text.index("\n_cli_targets_to_hostports()")
    return text[start:end]


def _run_helpers(tmp_path: Path, *, version: str, marker: str | None) -> subprocess.CompletedProcess:
    state = tmp_path / "state"
    state.mkdir()
    if marker is not None:
        (state / "last-network-probes-host1").write_text(marker + "\n", encoding="utf-8")
    funcs = _extract_probe_funcs()
    # Drop _run_network_probes for the helper-only suite (keep through mark helpers).
    cut = funcs.index("_run_network_probes()")
    helpers = funcs[:cut]
    script = textwrap.dedent(
        f"""\
        #!/usr/bin/env bash
        set -euo pipefail
        SCAN_STATE_DIR={state.as_posix()!r}
        HOST_ID="host1"
        SCAN_AGENT_VERSION={version!r}
        {helpers}
        echo "ver=$(_agent_version)"
        if _network_probes_already_done "$(_agent_version)"; then
          echo "skip=1"
        else
          echo "skip=0"
          _mark_network_probes_done "$(_agent_version)"
          echo "marked=$(tr -d '[:space:]' <"$(_network_probes_marker_path)")"
        fi
        """
    )
    wrapper = tmp_path / "probe-helpers.sh"
    wrapper.write_text(script, encoding="utf-8")
    wrapper.chmod(0o755)
    return subprocess.run(
        ["bash", str(wrapper)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_skip_when_marker_matches_version(tmp_path):
    proc = _run_helpers(tmp_path, version="1.2.0", marker="1.2.0")
    assert proc.returncode == 0, proc.stderr
    assert "ver=1.2.0" in proc.stdout
    assert "skip=1" in proc.stdout


def test_run_and_mark_when_version_changes(tmp_path):
    proc = _run_helpers(tmp_path, version="1.2.0", marker="1.1.1")
    assert proc.returncode == 0, proc.stderr
    assert "skip=0" in proc.stdout
    assert "marked=1.2.0" in proc.stdout


def test_run_when_no_marker(tmp_path):
    proc = _run_helpers(tmp_path, version="1.2.0", marker=None)
    assert proc.returncode == 0, proc.stderr
    assert "skip=0" in proc.stdout
    assert "marked=1.2.0" in proc.stdout


def test_run_network_probes_skips_second_invocation(tmp_path):
    """Full _run_network_probes: second call with same version returns []."""
    state = tmp_path / "state"
    state.mkdir()
    cfg = {
        "network_probes": [{
            "id": "azure-instance",
            "parser_id": "azure_imds",
            "url": "http://127.0.0.1:9/nope",
            "method": "GET",
            "timeout_seconds": 1,
        }],
    }
    cfg_path = tmp_path / "cfg.json"
    cfg_path.write_text(json.dumps(cfg), encoding="utf-8")
    funcs = _extract_probe_funcs()
    script = textwrap.dedent(
        f"""\
        #!/usr/bin/env bash
        set -euo pipefail
        export SCAN_STATE_DIR={state.as_posix()!r}
        export SCAN_AGENT_VERSION=9.9.9
        HOST_ID="host-x"
        SCAN_TIMEOUT=1
        _info() {{ echo "3am-scan: $*" >&2; }}
        {funcs}
        cfg="$(cat {cfg_path.as_posix()!r})"
        out1="$(_run_network_probes "$cfg")"
        out2="$(_run_network_probes "$cfg")"
        python3 -c 'import json,sys; print("first_len="+str(len(json.loads(sys.argv[1]))))' "$out1"
        python3 -c 'import json,sys; print("second="+sys.argv[1])' "$out2"
        python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print("first_id="+d[0]["id"])' "$out1"
        """
    )
    wrapper = tmp_path / "full.sh"
    wrapper.write_text(script, encoding="utf-8")
    wrapper.chmod(0o755)
    proc = subprocess.run(
        ["bash", str(wrapper)],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
        env={**os.environ},
    )
    assert proc.returncode == 0, proc.stderr + proc.stdout
    assert "first_len=1" in proc.stdout
    assert "first_id=azure-instance" in proc.stdout
    assert "second=[]" in proc.stdout
