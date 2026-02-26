# Atlas CLI Gaps Agents Often Miss

This reference captures Atlas CLI capabilities and constraints that AI agents commonly omit when proposing workflows.

## Table of Contents

- Planning and approval workflows
- Migration directory maintenance
- Schema quality commands beyond apply/diff
- `atlas.hcl` controls that change behavior
- URL and connection pitfalls
- Dev-database nuances
- Feature availability and version policy
- Suggested default workflow for agents
- Sources

## Planning and Approval Workflows

Agents often jump directly to `atlas schema apply`. Prefer explicit planning when review gates are required:

```bash
atlas schema plan --env dev
atlas schema plan --env dev --pending
atlas schema plan lint --env dev --file file://plan.hcl
atlas schema plan validate --env dev --file file://plan.hcl
atlas schema plan approve --url atlas://<schema-slug>/plans/<name>
```

Key idea:

- `schema plan` is for pre-planning/review/approval before execution.
- Use `--push`, `--pending`, and `approve` to separate authoring from deployment.

## Migration Directory Maintenance

Agents frequently miss non-obvious maintenance commands:

```bash
# Create checkpoint snapshot for faster bootstrap of new envs.
atlas migrate checkpoint --env dev

# Recompute atlas.sum after manual file edits.
atlas migrate hash --env dev

# Validate checksums and (optionally) SQL semantics with dev DB execution.
atlas migrate validate --env dev --dev-url "docker://postgres/15/dev?search_path=public"

# Reorder/rebase migration history when needed.
atlas migrate rebase 20240101010101 --env dev
```

Other high-signal commands:

- `atlas migrate test` for migration tests.
- `atlas migrate set` only for explicit revision-table reconciliation.
- `atlas migrate import` for importing non-Atlas migration formats.

## Schema Quality Commands Beyond Apply/Diff

Useful commands agents commonly skip:

```bash
atlas schema validate --env dev
atlas schema lint --env dev
atlas schema fmt schema/
atlas schema stats inspect --env prod
atlas tool lsp --stdio
```

Notes:

- `schema stats inspect` emits OpenMetrics.
- `tool lsp` provides language-server support for editor integration.

## `atlas.hcl` Controls That Change Behavior

### Schema mode

Roles/permissions are excluded by default and must be explicitly enabled:

```hcl
schema {
  src = "file://schema.hcl"
  mode {
    roles       = true
    permissions = true
    sensitive   = ALLOW // DENY is default
  }
}
```

### Data config

`max_rows` is required when syncing data against a live database URL:

```hcl
data {
  mode     = UPSERT
  include  = ["countries", "currencies"]
  exclude  = ["temp_*"]
  max_rows = 1000
}
```

### Diff policy

Prevent accidental destructive plans at diff time:

```hcl
diff {
  skip {
    drop_schema = true
    drop_table  = true
  }
  concurrent_index {
    create = true
    drop   = true
  }
}
```

### Lint policy

Non-linear change handling is important for team workflows:

```hcl
lint {
  non_linear {
    error   = true
    on_edit = WARN // IGNORE | ERROR
  }
  destructive {
    error = true
    force = true // Pro
  }
}
```

## URL and Connection Pitfalls

### TLS defaults and params

- PostgreSQL defaults to SSL mode `required`; set `?sslmode=disable` only for local/non-TLS setups.
- MySQL TLS requires explicit URL parameters like `?tls=true&ssl-ca=...` (and optionally `ssl-cert`, `ssl-key`).
- Aurora DSQL requires `sslmode=require`.

### URL escaping

Special characters in credentials must be URL-escaped. In `atlas.hcl`, prefer:

```hcl
locals {
  db_pass = urlescape(getenv("DB_PASSWORD"))
}
```

### Scope/mode semantics

- PostgreSQL/CockroachDB scope commonly uses `search_path`.
- SQL Server and Oracle use Atlas `mode` (`schema` vs `database`) to control scope.
- Unix-socket forms exist for MySQL/MariaDB (`mysql+unix://...`, `maria+unix://...`).

## Dev-Database Nuances

- Use `--dev-url` for validation and canonicalization to avoid false-positive diffs.
- Atlas uses dev-db execution to catch SQL semantic errors that static parsing may miss.
- For Pro users, baseline dev schemas can be configured with `docker`/`dev` blocks and `baseline` SQL.
- `docker+<driver>://...` supports custom local/registry images.
- Some emulated dev images do not enforce every managed-service limitation (example: DSQL); keep schema features within target engine support.

## Feature Availability and Version Policy

Agents should always account for product/version boundaries:

- Atlas is open-core; many advanced CLI/database capabilities are Pro.
- Drivers like SQL Server, ClickHouse, Redshift, Oracle, Spanner, Snowflake, Databricks, CockroachDB, Aurora DSQL, and Azure Fabric are Pro.
- Supported CLI policy is the latest two minor versions.
- Binaries older than 6 months are removed from CDN/Docker Hub.
- Atlas Community (Apache 2.0) exists separately from Atlas (EULA binary).

## Suggested Default Workflow for Agents

1. Validate CLI/version and feature availability (`atlas version`, Pro vs open checks).
2. Load `atlas.hcl` env and confirm `dev` URL is configured.
3. Run `schema validate/lint` before generating plans.
4. Prefer `schema plan` for reviewed environments; use `apply` only after approval.
5. For versioned flow, run `migrate diff -> lint -> validate -> status -> apply`.
6. After manual migration edits, run `migrate hash` and then `migrate validate`.
7. Treat connection URLs and TLS settings as first-class config, not ad hoc flags.

## Sources

- https://atlasgo.io/cli-reference
- https://atlasgo.io/atlas-schema/projects
- https://atlasgo.io/concepts/url
- https://atlasgo.io/concepts/dev-database
- https://atlasgo.io/lint/analyzers
- https://atlasgo.io/features#pro
