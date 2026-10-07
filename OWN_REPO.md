# `3am-agent-acme-sh`

This repository is the **source of truth** for the acme.sh OSS agent
(installer, companion, thin deploy-hook, INSTALL.md, tests).

**Remote:** `Axelspire/3am-agent-acme-sh` (private).

Imported from `3am-datasink/agents/acme-sh-scan` ([CORE-48](https://axelspire.atlassian.net/browse/CORE-48)).

Release: tag module versions (e.g. `v0.1.0`). Fleet pin:
`agents.acme.sh.module` in `3am-deployments` `_common/fleet-baseline.yaml`.

After cutover, remove the datasink in-tree copy
([DATASINK-77](https://axelspire.atlassian.net/browse/DATASINK-77)).
