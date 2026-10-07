# `3am-agent-acme-sh`

Source of truth for the acme.sh OSS agent (installer, companion, thin
deploy-hook, INSTALL.md, tests, upstream pin tooling + GH Actions).

**Remote:** `Axelspire/3am-agent-acme-sh` (private).

| Artifact | Role |
|---|---|
| `MODULE` / git tag `v0.x.x` | Wrapper release → fleet `agents.acme.sh.module` |
| `pin` + `tags/<pin>` | Upstream GPL acme.sh → fleet `agents.acme.sh.pin` |
| Actions `propose-pin` / `publish-pin` | Candidate (A2 prerelease) → promote to core/fleet PRs |

Upstream bumps: [`UPSTREAM.md`](./UPSTREAM.md).
