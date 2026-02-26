# Atlas Core Workflows

## Table of Contents

- Workflow choice
- Project configuration (`atlas.hcl`)
- Dev database patterns
- Declarative workflow
- Versioned workflow
- Baselining existing databases
- Schema sources (HCL, SQL, ORM providers)
- Common commands

## Workflow Choice

- Choose declarative for state-driven workflows where Atlas computes and applies drift to target state.
- Choose versioned when migration files must be reviewed, versioned, and promoted across environments.
- Choose baseline flow first for brownfield databases already in production.

## Project Configuration (`atlas.hcl`)

Use explicit environments and variables:

```hcl
variable "db_url" {
  type = string
}

env "local" {
  src = "file://schema.pg.hcl"
  url = var.db_url
  dev = "docker://postgres/15/dev?search_path=public"

  migration {
    dir = "file://migrations"
  }
}

env "prod" {
  src = "file://schema.pg.hcl"
  url = var.db_url
  migration {
    dir = "atlas://myapp"
  }
}
```

Use:

```bash
atlas schema apply --env local --var "db_url=postgres://..."
```

## Dev Database Patterns

Atlas needs `dev` for diffing, linting, and validation.

```bash
# PostgreSQL
docker://postgres/15/dev?search_path=public

# MySQL
docker://mysql/8/dev

# SQLite
sqlite://dev?mode=memory
```

Keep `dev` ephemeral and isolated.

## Declarative Workflow

Use desired-state schema files (`.hcl` or `.sql`) and let Atlas compute changes:

```bash
atlas schema apply --url "postgres://..." --to "file://schema.pg.hcl" --dev-url "docker://postgres/15"
```

Recommended for:

- Teams that prefer Terraform-style drift correction.
- Faster iteration in lower environments.

## Versioned Workflow

Generate migration files and promote through environments:

```bash
atlas migrate diff add_users --dir "file://migrations" --to "file://schema.sql" --dev-url "docker://postgres/15"
atlas migrate apply --dir "file://migrations" --url "postgres://..."
```

Recommended for:

- Regulated workflows requiring immutable migration history.
- Environments where deployment and schema change approvals are separated.

## Baselining Existing Databases

When adopting Atlas for an existing database:

```bash
# Generate a baseline migration from current desired schema.
atlas migrate diff baseline --env local --to "file://schema.hcl"

# Mark baseline as applied in target env without executing it.
atlas migrate apply --env prod --baseline "20240101000000"
```

## Schema Sources (HCL, SQL, ORM Providers)

### HCL

Use database-specific extension hints where practical:

- `.pg.hcl` for PostgreSQL
- `.my.hcl` for MySQL
- `.lt.hcl` for SQLite

### SQL

Use standard DDL files for teams that prefer SQL-authoring:

```sql
CREATE TABLE users (
  id bigint PRIMARY KEY,
  email varchar(255) NOT NULL UNIQUE
);
```

### ORM Providers

Load schema from external providers:

```hcl
data "external_schema" "gorm" {
  program = [
    "go", "run", "-mod=mod",
    "ariga.io/atlas-provider-gorm",
    "load", "--path", "./models",
    "--dialect", "postgres",
  ]
}

env "local" {
  src = data.external_schema.gorm.url
}
```

## Common Commands

```bash
# Versioned flow
atlas migrate diff migration_name --env local
atlas migrate lint --env local --latest 1
atlas migrate apply --env local
atlas migrate validate --env local
atlas migrate status --env local

# Declarative flow
atlas schema apply --env local --auto-approve
atlas schema inspect --url "postgres://..." --format "{{ sql . }}"
atlas schema diff --from "postgres://..." --to "file://schema.hcl"
```
