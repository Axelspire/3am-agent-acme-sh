# Architecture

**Category:** architecture  
**Last updated:** 2026-10-20  
**Audience:** platform architects, ops on rota

## TL;DR

Public **MIT** packaging for pristine upstream [acme.sh](https://github.com/acmesh-official/acme.sh) (GPL archive) plus AxelSpire MIT scan companion / deploy-hook. Own-repo SoT for Linux agent install (`install.sh`); not the separate `at3am` ACME client product.

## Overview

- One-curl install from customer root (`axel.<customer>.3am.global/root/agent/acme.sh/install.sh`).
- Pin == upstream acme.sh tag; digest-verified archive; wrapper stamps `Le_DeployHook=3am_scan`.
- Companion talks to datasink scan APIs; no secrets in `3am-scan.env` beyond scan endpoints.
- See `OWN_REPO.md`, `PUBLIC-OSS.md`, and console Agents catalog.

## Update log

Human-facing product history for operators. **Criterion links** live in the AxelSpire `3am-design-model` delivery log (`evidence/delivery-log.yaml`), not in this file.

| Date (UTC) | Summary | PR |
| --- | --- | --- |
| 2026-10-23 | Two-pin upgrade path test + `upgrade-path-check` CI job (readiness AGT.03) | branch `cursor/design-36-upgrade-path-check-c99a` |
| 2026-10-18 | Dependabot path fix for readiness SEC.04 | [#10](https://github.com/Axelspire/3am-agent-acme-sh/pull/10) |
