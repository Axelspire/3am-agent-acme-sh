# Updating upstream acme.sh

## Who does what

| Role | Action |
|---|---|
| **Engineer** | Run **propose-pin** → test candidate → run **publish-pin** → merge draft PRs |
| **Ops / host owner** | After customer-deploy apply: re-run the same one-curl URL |

```bash
# Ops — after a pin has been published for your customer:
curl -fsSL https://axel.<customer>.3am.global/root/agent/acme.sh/install.sh | sh
```

Do **not** use `acme.sh --upgrade`.

## Versioning (CORE-65 target — locked)

**Our git tag = upstream acme.sh tag = `pin` = `x.y.z`.** No separate `MODULE=v0.x.y` lineage.

```text
our git tag  ==  pin file  ==  archive/<x.y.z>.tar.gz  ==  tags/<x.y.z>  ==  fleet pin
```

When upstream tags `3.1.2`, vendor that archive and tag **this** repo `3.1.2`. Our-only fixes land on `main` and ship with the next upstream tag. Never edit inside the GPL tarball — re-apply wrapper/hook/companion after install.

**Today (transitional):** fleet still has `module: v0.2.1` + `pin: "3.1.1"` until CORE-65 collapses them.

```yaml
# Target fleet shape:
agents:
  acme.sh:
    pin: "3.1.1"   # == our git tag == upstream tag
```

---

## Happy path (GitHub Actions — A2)

### 1) Propose (testable candidate, not customer-facing)

Actions → **propose-pin** → Run workflow:

| Input | Example |
|---|---|
| `upstream_pin` | `3.1.1` |
| `bump_module` | `false` (unless you also changed installer/companion) |

CI will:

1. Run `scripts/vendor-pin.sh`
2. pytest + shellcheck
3. Build a candidate bundle + **local HTTP install smoke**
4. Create a **prerelease** `candidate-<module>+pin-<pin>`
5. Open a **draft** metadata PR (`pin`, `tags/`, `manifest.json`)

Optional local check of the prerelease:

```bash
# Prefer candidate-layout.tar.gz (nested paths). Plain `gh release download`
# flattens archive/tags/companion asset names.
gh release download 'candidate-v0.2.0+pin-3.1.1' -R Axelspire/3am-agent-acme-sh \
  -p candidate-layout.tar.gz -D /tmp
mkdir -p /tmp/cand && tar -xzf /tmp/candidate-layout.tar.gz -C /tmp/cand
cd /tmp/cand && python3 -m http.server 8765 &
THREEAM_AGENT_BASE=http://127.0.0.1:8765 \
  THREEAM_SCAN_SERVER=https://scan.smoke.invalid \
  ACME_EMAIL=smoke@example.invalid \
  ./install.sh
```

### 2) Publish (ready for customer deploy path)

After LGTM on the candidate:

1. Ensure repo secret **`PUBLISH_PAT`** can open PRs on `3am-core` + `3am-deployments`.
2. (Recommended) Environment **`agent-pin-publish`** with required reviewers.
3. Actions → **publish-pin** → `candidate_ref=candidate-v0.2.0+pin-3.1.1`

CI downloads the **frozen** prerelease (does not re-fetch upstream), merges agent metadata, and opens **draft** PRs:

- `3am-core` — includes `archive/<pin>.tar.gz`
- `3am-deployments` — `agents.acme.sh.pin`

### 3) Merge + apply

Merge order: agent (if still open) → core (+ tag / `modules.core` bump if required) → fleet → `customer-deploy` apply → ops one-curl.

---

## Break-glass (local scripts)

Prefer Actions. Scripts remain for offline use:

```bash
./scripts/vendor-pin.sh 3.1.1 --sync-core ../3am-core
./scripts/build-candidate-bundle.sh
./scripts/smoke-candidate.sh
```

See also the worked example: Project store `docs/acme-sh-pin-3.1.1-actions-e2e.md`.

## Rules

- Don’t put our scan scripts inside the upstream tarball (GPL).
- `tags/<pin>` = one-line sha256 of the exact tarball you publish.
- Never bump fleet `pin` without publishing matching `archive/` + `tags/`.
- Candidate prereleases are **not** what customers download until Publish + apply.
