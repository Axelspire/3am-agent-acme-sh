# acme.sh agent — install

One-curl install (or upgrade) for this customer. Same URL refreshes the pinned
upstream acme.sh archive **and** the proprietary scan companion / thin deploy-hook.

## One-curl

```bash
curl -fsSL @THREEAM_AGENT_BASE@/install.sh | sh
```

Pinned upstream: **@PIN@** · Companion module: **@MODULE@**

Derived scan vanity: `@THREEAM_SCAN_SERVER@` (override with `THREEAM_SCAN_SERVER`).

## What gets installed

| Piece | Location |
|---|---|
| Upstream acme.sh (GPL) | `~/.acme.sh/` via `acme.sh --install` |
| Thin deploy-hook `3am_scan` | `~/.acme.sh/deploy/3am_scan.sh` |
| Scan companion | `~/.acme.sh/deploy/3am-scan.sh` (also mirrored under `~/.local/lib/3am/`) |
| Env defaults (no secrets) | `~/.acme.sh/3am-scan.env` |

The GPL `archive/@PIN@.tar.gz` is never modified — companion and hook stay outside it.

## After install

1. Issue a client cert whose CN is `agent:<uuid>` (or your host_id).
2. Source env and deploy:

```bash
. "$HOME/.acme.sh/3am-scan.env"
acme.sh --deploy -d 'agent:<uuid>' --deploy-hook 3am_scan
```

Scan failures are logged but do **not** fail renew (`hook` returns 0).

## Optional env

| Variable | Purpose |
|---|---|
| `ACME_EMAIL` | Passed to `acme.sh --install -m` |
| `THREEAM_ACME_HOME` | Override acme home (default `~/.acme.sh`) |
| `THREEAM_SKIP_ACME=1` | Companion/hook only |
| `THREEAM_DIGEST_OPTIONAL=1` | Warn instead of hard-fail on tags mismatch |

## Downloads

- Installer: `@THREEAM_AGENT_BASE@/install.sh`
- Upstream archive: `@THREEAM_AGENT_BASE@/archive/@PIN@.tar.gz`
- Companion: `@THREEAM_AGENT_BASE@/companion/3am-scan.sh`
- Catalog: `…/root/agent/catalog.json`

## Updates

Re-run the one-curl command. There is no proprietary `--upgrade` wrap.
