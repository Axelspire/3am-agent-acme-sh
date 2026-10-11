# acme.sh agent — install

One-curl install (or upgrade) for this customer. Same URL refreshes the pinned
upstream acme.sh archive **and** the proprietary scan companion / thin deploy-hook.

## Host prerequisites

| Tool | Required? | Notes |
|---|---|---|
| `curl`, `tar` | **yes** | Used by our one-curl wrapper |
| `crontab` (package `cron` / `cronie` / `vixie-cron`) | **recommended** | **Upstream acme.sh** dependency — not ours. On `--install`, acme.sh pre-checks for `crontab`/`fcrontab` so it can schedule renewals. Without it, stock `acme.sh --install` exits: *“Please add '--force'… Pre-check failed”*. |
| `openssl` | recommended | CSR / issue / companion |
| `socat` | optional | Only for acme.sh standalone HTTP-01 |

Our wrapper passes `--force` to `acme.sh --install` (fresh and upgrade) so one-curl still succeeds on headless hosts that lack crontab (CORE-64). Install **cron** on real agents anyway — otherwise the single renew/scan job is never registered.

```bash
# Debian/Ubuntu example (before or after one-curl)
sudo apt-get install -y cron
```

## One-curl

```bash
curl -fsSL @THREEAM_AGENT_BASE@/install.sh | sh
```

Pinned upstream: **@PIN@** · Companion module: **@MODULE@**

Derived scan vanity: `@THREEAM_SCAN_SERVER@` (override with `THREEAM_SCAN_SERVER`).

## What gets installed

| Piece | Location |
|---|---|
| Upstream acme.sh (GPL) | `~/.acme.sh/acme.sh.upstream` (moved by one-curl) |
| PATH wrapper `acme.sh` | `~/.acme.sh/acme.sh` — sources `3am-scan.env`, stamps `Le_DeployHook=3am_scan`, auto-deploys after issue/sign-csr |
| Thin deploy-hook `3am_scan` | `~/.acme.sh/deploy/3am_scan.sh` |
| Scan companion | `~/.acme.sh/deploy/3am-scan.sh` (also mirrored under `~/.local/lib/3am/`) |
| Env defaults (no secrets) | `~/.acme.sh/3am-scan.env` |

The GPL `archive/@PIN@.tar.gz` is never modified — companion and hook stay outside it.

**Always-on deploy-hook (CORE-64):** one-curl wraps `acme.sh` so operators do **not**
need to remember `--deploy-hook 3am_scan`. On `--issue` / `--sign-csr` / `--cron` /
`--deploy`, the wrapper stamps every domain conf with `Le_DeployHook=3am_scan` and,
after a successful issue/sign-csr, runs `--deploy --deploy-hook 3am_scan` itself.
`--deploy` without a hook also gets `3am_scan` injected. Re-running one-curl
re-wraps and re-stamps existing confs.

## Scheduling (one cron line)

**One crontab line** (from `acme.sh --install` — CORE-65; no second companion wake):

```text
acme.sh --cron --home ~/.acme.sh
```

That path is our wrapper: source `3am-scan.env` → stamp `Le_DeployHook=3am_scan` →
upstream renew → thin hook on renew → **also** wake the companion when a leaf cert
exists (even if renew was not due). Re-running one-curl strips any legacy
`# 3am-scan daily wake (CORE-64)` dual-cron line.

**Verify after one-curl / enroll:**

```bash
grep -q '3am-acme-wrapper CORE-64' ~/.acme.sh/acme.sh && echo wrapped_ok
crontab -l | grep 'acme.sh --cron'
# After any issue/sign-csr (or re-run one-curl):
grep Le_DeployHook ~/.acme.sh/agent.*/agent.*.conf
# Force deploy path (does not wait for renew):
. ~/.acme.sh/3am-scan.env
acme.sh --deploy -d 'agent.<uuid>'
```

## After install

1. Mint UUID: `curl -fsS https://axel.<id>.3am.global/api/uuid`
2. Issue a **clientAuth-only** CSR for CN `agent.<uuid>` (stock acme.sh CSR
   includes serverAuth → CORE-30 finalize 406). Prefer dotted CN (CORE-63).
3. Sign — the wrapper registers `3am_scan` and deploys automatically:

```bash
. "$HOME/.acme.sh/3am-scan.env"
# Short-lived agent7 (~7d): renew before expiry — pass --days 3 (default 60 is wrong).
acme.sh --sign-csr --csr ./agent.csr -d 'agent.<uuid>' \
  --server 'https://axel.<id>.3am.global/server-prod/directory/agent7' \
  --dns --yes-I-know-dns-manual-mode-enough-go-ahead-please \
  --days 3
# Manual deploy (hook injected if omitted):
acme.sh --deploy -d 'agent.<uuid>'
```

Scan failures are logged but do **not** fail renew (`hook` returns 0).

## Optional env

| Variable | Purpose |
|---|---|
| `ACME_EMAIL` | Passed to `acme.sh --install -m` |
| `THREEAM_ACME_HOME` | Override acme home (default `~/.acme.sh`) |
| `THREEAM_SKIP_ACME=1` | Companion/hook only |
| `THREEAM_DIGEST_OPTIONAL=1` | Warn instead of hard-fail on tags mismatch |
| `THREEAM_SKIP_SCAN_CRON=1` | Skip stripping legacy dual-cron wake lines |

## Downloads

- Installer: `@THREEAM_AGENT_BASE@/install.sh`
- Upstream archive: `@THREEAM_AGENT_BASE@/archive/@PIN@.tar.gz`
- Companion: `@THREEAM_AGENT_BASE@/companion/3am-scan.sh`
- Catalog: `…/root/agent/catalog.json`

## Updates

Re-run the one-curl command. There is no proprietary `--upgrade` wrap.
