# acme.sh + one-file scan (DATASINK-31 / DATASINK-55)

Test/dev scan agent for **3am-datasink**. Long-term we build our own agent;
for Phase 0/1 smoke we use **pristine upstream [acme.sh](https://github.com/acmesh-official/acme.sh)**
plus our proprietary companion — never patched into the GPL tree.

> **`at3am`** is our separate ACME client product (OSS-capable). It is **not**
> this test agent. Sink paths may still be named `/v1/at3am/*` historically.

## Own-repo SoT

This repository is the packaging source of truth — see [`OWN_REPO.md`](./OWN_REPO.md).
Assemble published `install.sh` into `3am-core/deploy/agents/acmesh/` until core consumes release bundles.

## One-curl install / update (preferred)

Per-customer FQDN (same URL upgrades pin + companion + hook):

```bash
curl -fsSL https://axel.<customer_id>.3am.global/root/agent/acme.sh/install.sh | sh
# demo:
curl -fsSL https://axel.3am-demo.3am.global/root/agent/acme.sh/install.sh | sh
```

Console: `https://axel.<id>.3am.global/console/agents` (catalog + INSTALL.md).

What it does:

1. Downloads pinned GPL `archive/<pin>.tar.gz` from the same prefix (pristine).
2. Verifies `tags/<pin>` sha256 (hard-fail unless `THREEAM_DIGEST_OPTIONAL=1`).
3. Extracts **flat or nested** archive layouts; runs `acme.sh --install --force` / refresh.
4. Installs companion + thin deploy-hook under `~/.acme.sh/deploy/` (lib mirror too).
5. Writes `~/.acme.sh/3am-scan.env` with `SCAN_SERVER` + `THREEAM_SCAN` (no secrets).
6. Wraps `acme.sh` so `Le_DeployHook=3am_scan` is **always** stamped and auto-deploy
   runs after issue/sign-csr (CORE-64 — no manual `--deploy-hook` required).
7. Installs a daily companion wake cron (sources `3am-scan.env`; skips until a cert exists).

```bash
# After client cert exists (CN = agent.<uuid>):
. "$HOME/.acme.sh/3am-scan.env"
acme.sh --deploy -d 'agent.<uuid>'
# issue/sign-csr also stamp + auto-deploy via the wrapper
```

Served layout (`3am-core` root S3 / API GET — public, no auth):

```text
agent/acme.sh/
  install.sh                 # one-curl (CORE-33)
  pin                        # e.g. 3.0.7
  archive/<pin>.tar.gz       # GPL upstream ONLY
  tags/<pin>                 # optional digest
  companion/3am-scan.sh      # proprietary (OUTSIDE tarball)
  companion/deploy/3am_scan.sh
  companion/VERSION
```

Later OSS agents follow the same pattern under `agent/<name>/`.

## Manual layout (rebase-friendly)

```text
workdir/
  acme.sh/          ← pristine upstream (GPL). Update anytime.
  3am-scan.sh       ← OUR scan file. Never edit acme.sh.
  deploy/3am_scan.sh ← thin deploy-hook launcher (optional)
```

We intentionally **do not** patch `acme.sh`. Cert issuance / renewal stays in
upstream (or `at3am`). Companion only: **mTLS to the sink → config → TLS scan → results**.

## Bootstrap (cert first, then scan)

Dan lock: agents that renew certs also scan — **get a client cert first**.

1. Issue a client cert whose **CN = host_id** (via acme.sh against your ACME
   CA, or `at3am`, or a test CA). Prefer `agent:<uuid>` from public UUID mint.
2. Point env at the datasink scan vanity and run `3am-scan.sh` (or use the hook).

```bash
export SCAN_SERVER="https://scan.<customer_id>.3am.global"
export SCAN_CERT="$HOME/.acme.sh/agent:uuid_ecc/fullchain.cer"
export SCAN_KEY="$HOME/.acme.sh/agent:uuid_ecc/agent:uuid.key"
export SCAN_CA="/path/to/server-or-public-ca.pem"   # recommended
export THREEAM_SCAN="$HOME/.local/lib/3am/3am-scan.sh"

"$THREEAM_SCAN"
```

## Sink API (historical `/v1/at3am/*`)

| Step | Call |
|---|---|
| Config | `GET /v1/at3am/config/{host_id}` (mTLS; falls back to legacy `/scope`) |
| Results | `POST /v1/at3am/results` JSON `{ agent_host, results: [...] }` |

Set `SCAN_USE_SCOPE=1` to force the legacy scope path.

## GPL / license boundary

- **acme.sh** is GPL-3.0 — keep the distributed tarball pristine; do not concatenate proprietary scan into it.
- **`3am-scan.sh`** is Axelspire proprietary (repo `COPYRIGHT`).
- **`deploy/3am_scan.sh`** is a thin launcher only (env map + exec); still shipped outside the GPL archive for v1 clarity.

## Updating upstream acme.sh

See **[`UPSTREAM.md`](./UPSTREAM.md)**. Prefer GitHub Actions **propose-pin** → **publish-pin** (A2).

```bash
# Break-glass only:
./scripts/vendor-pin.sh 3.1.0 --sync-core ../3am-core
```

## Maintainer sync into core publish

```bash
./assemble-install.sh > ../3am-core/deploy/agents/acmesh/install.sh
cp 3am-scan.sh ../3am-core/deploy/agents/acmesh/companion/
cp deploy/3am_scan.sh ../3am-core/deploy/agents/acmesh/companion/deploy/
# pin / archive / tags via scripts/vendor-pin.sh --sync-core
```

## Tests

```bash
python3 -m pytest tests/unit/test_acme_sh_install_lib.py --confcutdir=tests/unit -v
shellcheck -x install-lib.sh install.sh
```
