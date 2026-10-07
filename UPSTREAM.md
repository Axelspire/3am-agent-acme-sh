# Updating upstream acme.sh

## Who does what

| Role | Action |
|---|---|
| **Packaging engineer** | Pick a new acme.sh version, run `vendor-pin.sh`, open PRs |
| **Ops / host owner** | After deploy: re-run the same one-curl install URL (no special upgrade tool) |

```bash
# Ops — after a pin has been published for your customer:
curl -fsSL https://axel.<customer>.3am.global/root/agent/acme.sh/install.sh | sh
```

Do **not** use `acme.sh --upgrade`. The install URL already refreshes the pinned upstream + our companion.

## Two version numbers (don’t mix them up)

| Name | Example | What it is |
|---|---|---|
| **module** | `v0.1.1` | *Our* wrapper (installer, scan companion, hook) — this git repo’s tag |
| **pin** | `3.0.7` | *Upstream* acme.sh release from GitHub |

Fleet (`3am-deployments` `_common/fleet-baseline.yaml`):

```yaml
agents:
  acme.sh:
    module: v0.1.1    # our wrapper
    pin: "3.0.7"      # upstream acme.sh
    companion: "1.1.0"
```

## How to publish a new upstream version (engineer)

Goal: put `archive/3.1.0.tar.gz` (example) on the customer download URL, and set `pin` to `3.1.0`.

1. Choose a release: https://github.com/acmesh-official/acme.sh/releases

2. Download it and update metadata **and** copy into core’s publish folder:

   ```bash
   ./scripts/vendor-pin.sh 3.1.0 --sync-core ../3am-core
   ```

   That does three practical things:
   - Saves the tarball under `archive/3.1.0.tar.gz` on your laptop (not committed here — see below)
   - Writes the checksum to `tags/3.1.0` and sets `pin` + `manifest.json`
   - Copies tarball + checksum + pin into `3am-core/deploy/agents/acmesh/` so the next **core deploy** uploads them to S3

3. Commit in **this** repo: `pin`, `tags/3.1.0`, `manifest.json` (and installer changes if any).

4. Open a **3am-core** PR with the synced `deploy/agents/acmesh/` files (includes the `.tar.gz`).

5. In **3am-deployments**, set `agents.acme.sh.pin: "3.1.0"` (same PR cycle as the core bump).

6. Merge + `customer-deploy` apply.

7. Tell ops to re-run the one-curl above.

### Why the `.tar.gz` isn’t in this git repo

The tarball is ~0.5 MB+ and we gitignore `archive/*.tar.gz` so this repo stays small.

What matters for git history here is the **pin name + checksum** (`pin`, `tags/<pin>`).  
What matters for customers is the **file on S3** — that copy is made by `--sync-core` into `3am-core`, which deploy already knows how to publish.

So: metadata in this repo, tarball shipped via the core PR → deploy → S3. Ops never handle the tarball by hand.

## Rules

- Don’t put our scan scripts inside the upstream tarball (GPL boundary).
- `tags/<pin>` = one-line sha256 of the exact tarball you publish (install fails if they don’t match).
- Never bump `pin` in fleet without also publishing matching `archive/` + `tags/` files.

## Note on current pin `3.0.7`

Demo’s published `3.0.7.tar.gz` is an older flat pack (`bd98740a…`).  
`vendor-pin.sh` downloads GitHub’s normal nested tag tarball (`abd446d6…` for 3.0.7).  
For **new** pins, publish whatever `vendor-pin.sh` downloaded — no need to re-flatten.
