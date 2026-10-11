# `3am-agent-acme-sh`

Source of truth for the acme.sh agent (installer, companion, thin deploy-hook,
INSTALL.md, tests, upstream pin tooling + GH Actions).

**Remote:** [`Axelspire/3am-agent-acme-sh`](https://github.com/Axelspire/3am-agent-acme-sh)
— public OSS (**MIT**). Upstream archives under `archive/` remain **GPL-3.0**.

| Artifact | Role (CORE-65) |
|---|---|
| git tag `x.y.z` / `pin` / `tags/<pin>` | **Only** release identity — mirrors upstream acme.sh |
| `MODULE` file | Alias **== pin** (SPA/TF `@MODULE@` bake) |
| `VERSION` / fleet `companion` | Companion content version (not a release tag) |
| Actions `propose-pin` / `publish-pin` | Candidate `candidate-pin-x.y.z` → tag `x.y.z` + core/fleet PRs |
| PATH `acme.sh` | Operator entrypoint (wrapper). Optional stub `3am-acme` is not required |

Upstream bumps: [`UPSTREAM.md`](./UPSTREAM.md). Decisions: [`PUBLIC-OSS.md`](./PUBLIC-OSS.md).
