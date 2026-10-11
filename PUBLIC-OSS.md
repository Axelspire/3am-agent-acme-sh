# Public OSS cutover (CORE-65) — decided

Signed off 2026-10-11.

| Decision | Value |
|---|---|
| License (packaging / companion / wrapper) | **MIT** (`LICENSE`) |
| Upstream `archive/*.tar.gz` | **GPL-3.0**, pristine, unmodified |
| Public repo | Existing **`Axelspire/3am-agent-acme-sh`** (open visibility) |
| Operator entrypoint | PATH **`acme.sh`** (wrapper). `3am-acme` stub is optional/dev only |
| First release tag | **`3.1.1`** (== pin == upstream) |
| Auth for agents | PAT in env OK; Cursor App allow-list not a blocker |

## Operator command (locked)

```bash
curl -fsSL https://axel.<id>.3am.global/root/agent/acme.sh/install.sh | sh
# crontab (single line):
acme.sh --cron --home ~/.acme.sh
```

Do not document `3am-acme` as required. Prefer max compatibility with stock acme.sh muscle memory.
