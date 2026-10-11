# `3am-agent-acme-sh`

Source of truth for the acme.sh agent (installer, companion, thin deploy-hook,
INSTALL.md, tests, upstream pin tooling + GH Actions).

**Remote today:** `Axelspire/3am-agent-acme-sh` (**private**).

**CORE-65 target:** public OSS (Apache-2.0 or MIT — product/legal sign-off),
possibly renamed (`3am-acme` vs keep this name). Packaging + companion open;
pristine GPL `archive/*.tar.gz` still vendored at install. See `PUBLIC-OSS.md`.

| Artifact | Role (CORE-65) |
|---|---|
| git tag `x.y.z` / `pin` / `tags/<pin>` | **Only** release identity — mirrors upstream acme.sh |
| `MODULE` file | Transitional alias **== pin** (SPA/TF `@MODULE@` bake) |
| `VERSION` / fleet `companion` | Companion content version (not a release tag) |
| Actions `propose-pin` / `publish-pin` | Candidate `candidate-pin-x.y.z` → tag `x.y.z` + core/fleet PRs |
| `3am-acme` | Proposed single entrypoint (name TBD) |

Upstream bumps: [`UPSTREAM.md`](./UPSTREAM.md).
