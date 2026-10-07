# `3am-agent-acme-sh`

Source of truth for the acme.sh OSS agent (installer, companion, thin
deploy-hook, INSTALL.md, tests, upstream pin tooling).

**Remote:** `Axelspire/3am-agent-acme-sh` (private).

| Artifact | Role |
|---|---|
| `MODULE` / git tag `v0.x.x` | Wrapper/installer/companion release → fleet `agents.acme.sh.module` |
| `pin` + `tags/<pin>` (+ local `archive/`) | Upstream GPL acme.sh → fleet `agents.acme.sh.pin` |
| `VERSION` | Companion version → fleet `agents.acme.sh.companion` |

Upstream bumps: [`UPSTREAM.md`](./UPSTREAM.md) and `./scripts/vendor-pin.sh`.

Until core fetches release bundles, sync publish bits into
`3am-core/deploy/agents/acmesh/` (`assemble-install.sh` + `vendor-pin.sh --sync-core`).
