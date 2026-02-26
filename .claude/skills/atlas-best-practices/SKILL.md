---
name: atlas-best-practices
description: Use when working with atlas.hcl, Atlas CLI commands, schema HCL/SQL files, or migration planning and reviews, including Atlas v1.1 security, data, and exporter capabilities.
---

# Atlas Best Practices

Atlas supports declarative and versioned schema workflows. Keep this file minimal and load only the reference file needed for the current task.

## Workflow Selection

- Use declarative workflow when desired schema state is the source of truth.
- Use versioned workflow when migration files are required for auditing and staged deployments.
- Use baseline workflow when onboarding an existing database.

## Default Execution Flow

1. Confirm the target `env` in `atlas.hcl`.
2. Confirm `dev` is configured and isolated from production.
3. Plan first, then lint/test/validate, then apply.
4. Run production changes through CI/CD or approved deployment workflow.

## Quick Commands

```bash
# Declarative
atlas schema apply --env local

# Versioned
atlas migrate diff add_change --env local
atlas migrate lint --env local --latest 1
atlas migrate apply --env local

# Integrity
atlas migrate validate --env local
atlas migrate status --env local
```

## Reference Map

- [core-workflows.md](references/core-workflows.md)
  Use for environment config, schema-as-code patterns, declarative vs versioned workflows, baselining, and ORM provider loading.
- [safety-and-quality.md](references/safety-and-quality.md)
  Use for lint analyzers, transaction modes, schema tests, pre-execution checks, and CI patterns.
- [atlas-v1-1-features.md](references/atlas-v1-1-features.md)
  Use for Atlas v1.1 coverage (released on 2026-02-03), including security as code, declarative data, new drivers/platform support, Slack integration, schema exporters, and MySQL TLS.
- [cli-agent-gaps.md](references/cli-agent-gaps.md)
  Use for Atlas CLI capabilities and edge cases agents often miss: planning workflows, migration directory maintenance commands, URL/TLS pitfalls, feature availability, and version policy constraints.

## Guardrails

- Keep credentials out of source files; prefer Atlas data sources and input variables.
- Require explicit review for destructive or data-dependent migrations.
- Fail loudly on unsupported drivers, missing `dev` URLs, or unknown environment names.
