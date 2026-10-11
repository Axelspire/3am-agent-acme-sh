# Public OSS cutover checklist (CORE-65)

Blocked on product/legal sign-off. Engineering prep is in place (pin-mirrored
tags, candidate-pin naming, proposed `3am-acme` entrypoint, docs).

## Decisions required (Dan)

1. **License** for packaging + companion + wrapper: **Apache-2.0** (matches
   public `Axelspire/at3am`) or **MIT**. Upstream `archive/*.tar.gz` stays GPL-3.0
   and pristine either way.
2. **Public repo name:** open/rename current `3am-agent-acme-sh`, or new
   `3am-acme` (design sketch).
3. **Entrypoint name:** ship `3am-acme` as the public CLI, or keep PATH
   `acme.sh` wrapper as the only operator command (crontab stays
   `acme.sh --cron` either way for phase 1).
4. **First tag strategy** when going public:
   - **A)** Tag current main as `3.1.1` (matches today’s pin; wrapper already
     includes CORE-64/65 cron fold).
   - **B)** Wait for next upstream (e.g. `3.1.2`) for the first mirrored public tag.
   - **C)** Publish under a new public remote and tag there only (private
     `v0.2.1` history stays private).

## After sign-off (engineering)

1. Create/rename public repo; set LICENSE; replace proprietary COPYRIGHT headers
   on packaging/companion (not on GPL archive).
2. Grant Cursor GitHub App (and CI) access to the public SoT.
3. Point core `OWN_REPO.md` / assemble path at the public remote.
4. Run propose-pin → publish-pin for the chosen first `x.y.z`.
5. Fleet: `module == pin`; retire `v0.x.y` language from INSTALL / Confluence /
   UPSTREAM (phase 3).
6. Confluence [OSS agent one-curl](https://axelspire.atlassian.net/wiki/spaces/3am/pages/71598082) rewrite for one version line.

## Already done without sign-off

- Single crontab (CORE-64/65 phase 1) on main / v0.2.1
- propose-pin / publish-pin emit `candidate-pin-<x.y.z>` and tag repo `x.y.z`
- `MODULE` forced to pin on propose/publish
- Proposed `3am-acme` entrypoint stub (install/cron/stamp/wake)
