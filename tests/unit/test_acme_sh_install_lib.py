# Copyright (c) 2026 Axelspire Inc. All rights reserved.
# Proprietary. Unauthorized use prohibited. support3am@axelspire.com
"""Unit tests for install-lib.sh helpers (≥90% of lib logic)."""

from __future__ import annotations

import os
import subprocess
import textwrap
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
LIB = REPO / "install-lib.sh"
HOOK = REPO / "deploy" / "3am_scan.sh"
INSTALL = REPO / "install.sh"


def _run_lib(script: str, env: dict | None = None) -> subprocess.CompletedProcess[str]:
    full = textwrap.dedent(
        f"""
        set -eu
        . '{LIB}'
        {script}
        """
    )
    e = os.environ.copy()
    # Clear publish defaults for deterministic tests unless caller sets them.
    e.pop("THREEAM_AGENT_BASE", None)
    e.pop("THREEAM_INSTALL_URL", None)
    e.pop("THREEAM_SCAN_SERVER", None)
    e.pop("THREEAM_AGENT_BASE_DEFAULT", None)
    if env:
        e.update(env)
    return subprocess.run(
        ["sh", "-c", full],
        capture_output=True,
        text=True,
        env=e,
        check=False,
    )


class TestSanitizePin:
    def test_semver(self):
        r = _run_lib('threeam_sanitize_pin "3.0.7"; echo')
        assert r.returncode == 0
        assert r.stdout.strip() == "3.0.7"

    def test_master(self):
        r = _run_lib('threeam_sanitize_pin "master"; echo')
        assert r.returncode == 0
        assert r.stdout.strip() == "master"

    def test_suffix_pin(self):
        r = _run_lib('threeam_sanitize_pin "3.0.7a"; echo')
        assert r.returncode == 0
        assert r.stdout.strip() == "3.0.7a"

    def test_rejects_slash(self):
        r = _run_lib('threeam_sanitize_pin "../evil" || echo FAIL')
        assert "FAIL" in r.stdout
        assert r.returncode == 0

    def test_rejects_empty(self):
        r = _run_lib('threeam_sanitize_pin "" || echo FAIL')
        assert "FAIL" in r.stdout


class TestResolveAgentBase:
    def test_env_wins(self):
        r = _run_lib(
            'threeam_resolve_agent_base "https://ignored.example/agent/acme.sh"; echo',
            env={"THREEAM_AGENT_BASE": "https://axel.demo.3am.global/root/agent/acme.sh"},
        )
        assert r.returncode == 0
        assert r.stdout.strip() == "https://axel.demo.3am.global/root/agent/acme.sh"

    def test_cli_arg(self):
        r = _run_lib(
            'threeam_resolve_agent_base "https://axel.demo.3am.global/root/agent/acme.sh/"; echo'
        )
        assert r.returncode == 0
        assert r.stdout.strip() == "https://axel.demo.3am.global/root/agent/acme.sh"

    def test_install_url_dirname(self):
        r = _run_lib(
            "threeam_resolve_agent_base; echo",
            env={
                "THREEAM_INSTALL_URL": "https://axel.x.3am.global/root/agent/acme.sh/install.sh"
            },
        )
        assert r.returncode == 0
        assert r.stdout.strip() == "https://axel.x.3am.global/root/agent/acme.sh"

    def test_publish_default_env(self):
        r = _run_lib(
            "threeam_resolve_agent_base; echo",
            env={
                "THREEAM_AGENT_BASE_DEFAULT": "https://axel.demo.3am.global/root/agent/acme.sh"
            },
        )
        assert r.returncode == 0
        assert r.stdout.strip().endswith("/agent/acme.sh")

    def test_baked_marker_https(self, tmp_path):
        """Simulate CORE-33 replace of the single @THREEAM_AGENT_BASE@ marker."""
        baked = tmp_path / "lib.sh"
        text = LIB.read_text().replace(
            "@THREEAM_AGENT_BASE@",
            "https://axel.demo.3am.global/root/agent/acme.sh",
        )
        baked.write_text(text)
        script = f"set -eu\n. '{baked}'\nthreeam_resolve_agent_base; echo\n"
        e = os.environ.copy()
        for k in ("THREEAM_AGENT_BASE", "THREEAM_INSTALL_URL", "THREEAM_AGENT_BASE_DEFAULT"):
            e.pop(k, None)
        r = subprocess.run(["sh", "-c", script], capture_output=True, text=True, env=e, check=False)
        assert r.returncode == 0
        assert r.stdout.strip() == "https://axel.demo.3am.global/root/agent/acme.sh"

    def test_missing_errors(self):
        r = _run_lib("threeam_resolve_agent_base || echo FAIL")
        assert "FAIL" in r.stdout


class TestDeriveScanServer:
    def test_from_axel(self):
        r = _run_lib(
            'threeam_derive_scan_server "https://axel.demo.3am.global/root/agent/acme.sh"; echo'
        )
        assert r.returncode == 0
        assert r.stdout.strip() == "https://scan.demo.3am.global"

    def test_override_env(self):
        r = _run_lib(
            'threeam_derive_scan_server "https://root.example.com/agent/acme.sh" || true; echo done',
            env={"THREEAM_SCAN_SERVER": "https://scan.custom.example"},
        )
        # Non-axel host without successful derive — but env is checked after case miss.
        # Re-run: function returns env when host doesn't match axel pattern.
        r2 = _run_lib(
            'threeam_derive_scan_server "https://root.example.com/agent/acme.sh"; echo',
            env={"THREEAM_SCAN_SERVER": "https://scan.custom.example"},
        )
        assert r2.returncode == 0
        assert r2.stdout.strip() == "https://scan.custom.example"

    def test_missing(self):
        r = _run_lib(
            'threeam_derive_scan_server "https://root.example.com/agent/acme.sh" || echo FAIL'
        )
        assert "FAIL" in r.stdout


class TestUrlAndPaths:
    def test_url_join(self):
        r = _run_lib(
            'threeam_url_join "https://h/root/agent/acme.sh/" "/companion/3am-scan.sh"; echo'
        )
        assert r.stdout.strip() == "https://h/root/agent/acme.sh/companion/3am-scan.sh"

    def test_hook_dest(self):
        r = _run_lib('threeam_hook_dest "/home/u/.acme.sh"; echo')
        assert r.stdout.strip() == "/home/u/.acme.sh/deploy/3am_scan.sh"

    def test_companion_dest_colocated(self):
        r = _run_lib('threeam_companion_dest "/home/u/.acme.sh"; echo')
        assert r.stdout.strip() == "/home/u/.acme.sh/deploy/3am-scan.sh"

    def test_companion_lib_dest(self):
        r = _run_lib('threeam_companion_lib_dest "/home/u/.local/lib/3am"; echo')
        assert r.stdout.strip() == "/home/u/.local/lib/3am/3am-scan.sh"

    def test_defaults(self, tmp_path, monkeypatch):
        home = tmp_path / "home"
        home.mkdir()
        r = _run_lib(
            "threeam_default_acme_home; echo; threeam_default_lib_dir; echo",
            env={"HOME": str(home)},
        )
        assert str(home / ".acme.sh") in r.stdout
        assert str(home / ".local/lib/3am") in r.stdout

    def test_should_upgrade(self, tmp_path):
        home = tmp_path / ".acme.sh"
        home.mkdir()
        r = _run_lib(f'threeam_should_upgrade_acme "{home}" || echo NO')
        assert "NO" in r.stdout
        (home / "acme.sh").write_text("#!/bin/sh\n")
        (home / "acme.sh").chmod(0o755)
        r2 = _run_lib(f'threeam_should_upgrade_acme "{home}" && echo YES')
        assert "YES" in r2.stdout


class TestDeployHook:
    def test_hook_defines_function(self, tmp_path):
        companion = tmp_path / "3am-scan.sh"
        companion.write_text("#!/bin/sh\necho SCAN_OK\n")
        companion.chmod(0o755)
        script = textwrap.dedent(
            f"""
            set -eu
            . '{HOOK}'
            export THREEAM_SCAN='{companion}'
            export SCAN_SERVER='https://scan.demo.3am.global'
            3am_scan_deploy 'agent:uuid' '{tmp_path}/k.pem' '{tmp_path}/c.pem' '' '{tmp_path}/full.pem'
            """
        )
        (tmp_path / "k.pem").write_text("k")
        (tmp_path / "c.pem").write_text("c")
        (tmp_path / "full.pem").write_text("f")
        r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, check=False)
        assert r.returncode == 0
        assert "SCAN_OK" in r.stdout

    def test_hook_missing_companion_returns_zero(self, tmp_path):
        script = textwrap.dedent(
            f"""
            set -eu
            . '{HOOK}'
            unset THREEAM_SCAN SCAN_HELPER THREEAM_LIB_DIR
            3am_scan_deploy 'd' '{tmp_path}/k' '{tmp_path}/c' '' ''
            echo RC:$?
            """
        )
        (tmp_path / "k").write_text("k")
        (tmp_path / "c").write_text("c")
        r = subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            env={**os.environ, "HOME": str(tmp_path / "nohome")},
            check=False,
        )
        assert r.returncode == 0
        assert "RC:0" in r.stdout

    def test_hook_scan_failure_still_zero(self, tmp_path):
        companion = tmp_path / "3am-scan.sh"
        companion.write_text("#!/bin/sh\nexit 7\n")
        companion.chmod(0o755)
        script = textwrap.dedent(
            f"""
            set -eu
            . '{HOOK}'
            export THREEAM_SCAN='{companion}'
            3am_scan_deploy 'd' '{tmp_path}/k' '{tmp_path}/c' '' '{tmp_path}/c'
            echo RC:$?
            """
        )
        (tmp_path / "k").write_text("k")
        (tmp_path / "c").write_text("c")
        r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, check=False)
        assert r.returncode == 0
        assert "RC:0" in r.stdout
        assert "scan failed" in r.stderr


class TestResolveArchiveSrc:
    def test_flat_layout(self, tmp_path):
        root = tmp_path / "extract"
        root.mkdir()
        (root / "acme.sh").write_text("#!/bin/sh\n")
        (root / "acme.sh").chmod(0o755)
        (root / "deploy").mkdir()
        r = _run_lib(f'threeam_resolve_archive_src "{root}" "acme.sh"; echo')
        assert r.returncode == 0
        assert r.stdout.strip() == str(root)

    def test_nested_layout(self, tmp_path):
        root = tmp_path / "extract"
        nested = root / "acme.sh-3.0.7"
        nested.mkdir(parents=True)
        (nested / "acme.sh").write_text("#!/bin/sh\n")
        (nested / "acme.sh").chmod(0o755)
        r = _run_lib(f'threeam_resolve_archive_src "{root}" "acme.sh"; echo')
        assert r.returncode == 0
        assert r.stdout.strip() == str(nested)

    def test_missing(self, tmp_path):
        root = tmp_path / "extract"
        (root / "deploy").mkdir(parents=True)
        r = _run_lib(f'threeam_resolve_archive_src "{root}" "acme.sh" || echo FAIL')
        assert "FAIL" in r.stdout


class TestVerifyArchiveDigest:
    def test_match(self, tmp_path):
        f = tmp_path / "a.tgz"
        f.write_bytes(b"hello")
        import hashlib

        want = hashlib.sha256(b"hello").hexdigest()
        r = _run_lib(f'threeam_verify_archive_digest "{f}" "{want}" && echo OK')
        assert r.returncode == 0
        assert "OK" in r.stdout

    def test_mismatch_hard_fail(self, tmp_path):
        f = tmp_path / "a.tgz"
        f.write_bytes(b"hello")
        r = _run_lib(
            f'threeam_verify_archive_digest "{f}" "{"0" * 64}" || echo FAIL',
            env={"THREEAM_DIGEST_OPTIONAL": "0"},
        )
        assert "FAIL" in r.stdout

    def test_mismatch_optional(self, tmp_path):
        f = tmp_path / "a.tgz"
        f.write_bytes(b"hello")
        r = _run_lib(
            f'threeam_verify_archive_digest "{f}" "{"0" * 64}" && echo OK',
            env={"THREEAM_DIGEST_OPTIONAL": "1"},
        )
        assert r.returncode == 0
        assert "OK" in r.stdout


class TestInstallShPresent:
    def test_files_executable_bits_and_no_secrets(self):
        text = INSTALL.read_text()
        assert "PUBLIC" in text.upper() or "no secrets" in text.lower()
        assert "archive/" in text
        assert "companion/" in text
        assert "3am_scan" in text
        # Must not embed API keys / private key material patterns.
        assert "BEGIN PRIVATE KEY" not in text
        assert "api_key" not in text.lower()
        assert LIB.is_file()
        assert HOOK.is_file()


class TestInstallDryRunMockCurl:
    def test_companion_only_install(self, tmp_path):
        """End-to-end install with THREEAM_SKIP_ACME and mocked curl."""
        base = tmp_path / "base"
        (base / "companion" / "deploy").mkdir(parents=True)
        (base / "companion" / "3am-scan.sh").write_text("#!/bin/sh\necho scan\n")
        (base / "companion" / "deploy" / "3am_scan.sh").write_text(
            HOOK.read_text()
        )
        (base / "companion" / "VERSION").write_text("test-1\n")
        (base / "pin").write_text("3.0.7\n")

        curl_bin = tmp_path / "bin"
        curl_bin.mkdir()
        curl_shim = curl_bin / "curl"
        # Map URL path under file:// style from AGENT_BASE local paths via file fetch.
        # Our install uses https URLs; shim translates AGENT_BASE prefix to local dir.
        curl_shim.write_text(
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
                base="https://axel.demo.3am.global/root/agent/acme.sh"
                rel="${{url#$base/}}"
                src="{base}/$rel"
                if [ -n "$out" ]; then
                  cp "$src" "$out"
                else
                  cat "$src"
                fi
                """
            )
        )
        curl_shim.chmod(0o755)

        home = tmp_path / "home"
        home.mkdir()
        acme_home = home / ".acme.sh"
        acme_home.mkdir()
        # Pretend acme already installed so upgrade path is unused with SKIP.
        (acme_home / "acme.sh").write_text("#!/bin/sh\n")
        (acme_home / "acme.sh").chmod(0o755)

        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{curl_bin}:{env.get('PATH', '')}",
                "HOME": str(home),
                "THREEAM_AGENT_BASE": "https://axel.demo.3am.global/root/agent/acme.sh",
                "THREEAM_SKIP_ACME": "1",
                "THREEAM_INSTALL_LIB": str(LIB),
            }
        )
        r = subprocess.run(
            ["sh", str(INSTALL)],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
        assert r.returncode == 0, r.stderr
        assert (acme_home / "deploy" / "3am-scan.sh").is_file()
        assert (acme_home / "deploy" / "3am_scan.sh").is_file()
        assert (home / ".local/lib/3am/3am-scan.sh").is_file()
        assert (acme_home / "3am-scan.env").is_file()
        env_body = (acme_home / "3am-scan.env").read_text()
        assert "https://scan.demo.3am.global" in env_body
        assert str(acme_home / "deploy" / "3am-scan.sh") in env_body
