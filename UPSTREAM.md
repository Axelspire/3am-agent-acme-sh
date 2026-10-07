# Updating upstream acme.sh (OSS pin)

Two independent knobs:

| Knob | Meaning | Where |
|---|---|---|
| **`module`** (`MODULE`, git tag `v0.x.x`) | Our installer / companion / hook | this repo |
| **`pin`** (e.g. `3.0.7`) | Pristine GPL [acme.sh](https://github.com/acmesh-official/acme.sh) archive | `pin` + `archive/<pin>.tar.gz` + `tags/<pin>` |

Operators never track GitHub “latest”. They re-run one-curl and get the
**published** `pin` for that customer. Do **not** wrap `acme.sh --upgrade`.

## Bump checklist

1. Pick an upstream release tag from
   https://github.com/acmesh-official/acme.sh/releases (e.g. `3.1.0`).
2. Vendor it (writes local archive + digest; updates `pin` / `tags/` / `manifest.json`):

   ```bash
   ./scripts/vendor-pin.sh 3.1.0
   # or also copy into the core publish snapshot:
   ./scripts/vendor-pin.sh 3.1.0 --sync-core ../3am-core
   ```

3. Smoke the archive layout (script already checks for an `acme.sh` entrypoint).
   Installer accepts **flat or nested** GitHub layouts.
4. Commit in this repo: `pin`, `tags/<pin>`, `manifest.json` (and any installer
   changes). `archive/*.tar.gz` is **gitignored** — bytes travel via
   `--sync-core` / release bundle until CI attaches them.
5. If installer/companion changed: bump `MODULE` / `VERSION` as needed, tag
   (e.g. `v0.1.2`), set fleet `agents.acme.sh.module`.
6. Always set fleet `agents.acme.sh.pin` to the new pin in the **same** change
   set as the core publish sync (`3am-deployments` `_common/fleet-baseline.yaml`).
7. Merge → `customer-deploy` apply → hosts refresh with:

   ```bash
   curl -fsSL https://axel.<customer>.3am.global/root/agent/acme.sh/install.sh | sh
   ```

## Rules

- Never concatenate proprietary files into `archive/<pin>.tar.gz`.
- `tags/<pin>` must be exactly one lowercase hex sha256 line of the archive
  bytes (hard-fail at install unless `THREEAM_DIGEST_OPTIONAL=1`).
- Do not change `pin` without shipping matching `archive/` + `tags/` objects.
- Prefer official `refs/tags/<pin>.tar.gz`. If you must use a release asset
  with a different layout, drop it at `archive/<pin>.tar.gz` yourself then:

  ```bash
  sha256sum archive/<pin>.tar.gz | awk '{print $1}' > tags/<pin>
  printf '%s\n' '<pin>' > pin
  # refresh manifest.json pin + archive_sha256
  ```

## Until core consumes agent release bundles

Publish path remains `3am-core/deploy/agents/acmesh/`. Use
`./scripts/vendor-pin.sh <pin> --sync-core ../3am-core` then open a core PR
(+ fleet pin bump). See [`OWN_REPO.md`](./OWN_REPO.md).

## Note on pin `3.0.7` (historical)

Live/demo `archive/3.0.7.tar.gz` is a **flat** re-pack
(`sha256 bd98740a…`). GitHub’s `refs/tags/3.0.7.tar.gz` is the nested
`acme.sh-3.0.7/` layout (`sha256 abd446d6…`). Installer accepts both.

`./scripts/vendor-pin.sh` always fetches the **GitHub tag** tarball. For new
pins, publish that file + its `tags/<pin>` digest as-is. Do not re-flat-pack
unless you have a strong reason — and if you do, digest must match the bytes
you actually upload.
