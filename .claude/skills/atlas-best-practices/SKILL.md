---
name: atlas-best-practices
description: Patterns for Atlas database schema management covering HCL/SQL schema definitions, versioned and declarative migrations, linting analyzers, testing, project configuration, declarative roles/permissions (v1.1+), data management, and schema exporters. Use when working with atlas.hcl, .hcl schema files, Atlas CLI commands, or database migrations.
---

# Atlas Best Practices

Atlas is a language-independent tool for managing database schemas using declarative or versioned workflows.

## Two Workflows

**Declarative (Terraform-like):** Atlas compares current vs desired state and generates migrations automatically.
```bash
atlas schema apply --url "postgres://..." --to "file://schema.hcl" --dev-url "docker://postgres/15"
```

**Versioned:** Atlas generates migration files from schema changes, stored in version control.
```bash
atlas migrate diff add_users --dir "file://migrations" --to "file://schema.sql" --dev-url "docker://postgres/15"
atlas migrate apply --dir "file://migrations" --url "postgres://..."
```

## Dev Database

Atlas requires a dev database for schema validation, diffing, and linting. Use the docker driver for ephemeral containers:

```bash
# PostgreSQL
--dev-url "docker://postgres/15/dev?search_path=public"

# MySQL
--dev-url "docker://mysql/8/dev"

# SQLite
--dev-url "sqlite://dev?mode=memory"
```

## Schema-as-Code

### HCL Schema (Recommended)

Use database-specific file extensions for editor support: `.pg.hcl` (PostgreSQL), `.my.hcl` (MySQL), `.lt.hcl` (SQLite).

```hcl
schema "public" {
  comment = "Application schema"
}

table "users" {
  schema = schema.public
  column "id" {
    type = bigint
  }
  column "email" {
    type = varchar(255)
    null = false
  }
  column "created_at" {
    type    = timestamptz
    default = sql("now()")
  }
  primary_key {
    columns = [column.id]
  }
  index "idx_users_email" {
    columns = [column.email]
    unique  = true
  }
}

table "orders" {
  schema = schema.public
  column "id" {
    type = bigint
  }
  column "user_id" {
    type = bigint
    null = false
  }
  column "total" {
    type = numeric
    null = false
  }
  foreign_key "fk_user" {
    columns     = [column.user_id]
    ref_columns = [table.users.column.id]
    on_delete   = CASCADE
  }
  check "positive_total" {
    expr = "total > 0"
  }
}
```

### SQL Schema

Use standard SQL DDL files:

```sql
CREATE TABLE "users" (
  "id" bigint PRIMARY KEY,
  "email" varchar(255) NOT NULL UNIQUE,
  "created_at" timestamptz DEFAULT now()
);
```

## Roles, Users, and Permissions (v1.1+ Pro)

Atlas v1.1 manages roles, users, and permissions declaratively. Define them in HCL alongside tables and indexes.

```hcl
role "app_readonly" {
  comment = "Read-only access for application"
}

role "app_admin" {
  superuser   = false
  create_db   = false
  create_role = false
  login       = true
  member_of   = [role.app_readonly]
}

user "app_user" {
  password  = var.app_password
  member_of = [role.app_admin]
}

permission {
  for_each   = [table.users, table.orders, table.products]
  for        = each.value
  to         = role.app_readonly
  privileges = [SELECT]
}

permission {
  for        = schema.public
  to         = role.app_admin
  privileges = [ALL]
  grantable  = true
}
```

Enable in `atlas.hcl`:
```hcl
env "prod" {
  schema {
    src = "file://schema.hcl"
    mode {
      roles       = true
      permissions = true
    }
  }
}
```

Passwords are masked as `<sensitive>` in logs and inspection output.

Supported databases: PostgreSQL, MySQL, MariaDB, SQL Server, ClickHouse, Spanner, Databricks.

### Pre-v1.1 / non-Pro fallback

Without Pro, `migrate diff` does not track GRANT, REVOKE, or role changes. Use hand-written migrations:

```sql
-- migrations/20240101120000_app_role_grants.sql
GRANT SELECT ON "users" TO app_readonly;
```

After adding, update checksums:
```bash
atlas migrate hash --env local
atlas migrate validate --env local
```

## Declarative Data Management (v1.1+)

Define lookup tables and seed data as code. Atlas syncs rows based on the configured mode.

```hcl
data {
  table = table.countries
  rows = [
    { id = 1, code = "US", name = "United States" },
    { id = 2, code = "IL", name = "Israel" },
    { id = 3, code = "DE", name = "Germany" },
  ]
}
```

Configure sync mode in `atlas.hcl`:
```hcl
env "prod" {
  data {
    mode    = UPSERT
    include = ["countries"]
  }
}
```

Sync modes:
- **INSERT** - add new rows only, never touch existing data.
- **UPSERT** - insert new rows, update existing by primary key.
- **SYNC** - full sync: insert, update, and delete to match desired state.

## Schema Exporters (v1.1+)

Export schemas to files or external services on `atlas schema inspect` or `atlas schema diff`:

```hcl
exporter "sql" "schema" {
  path     = "schema/sql"
  split_by = object
  naming   = same
}

exporter "hcl" "schema" {
  path     = "schema/hcl"
  split_by = object
  ext      = ".pg.hcl"
}

exporter "http" "webhook" {
  url           = "https://api.example.com/schemas"
  method        = "POST"
  body_template = "{{ sql . }}"
}

exporter "multi" "all" {
  exporters = [exporter.sql.schema, exporter.hcl.schema, exporter.http.webhook]
  on_error  = CONTINUE
}

env "prod" {
  url = getenv("DB_URL")
  export {
    schema {
      inspect = exporter.multi.all
    }
  }
}
```

Run with:
```bash
atlas schema inspect --env prod --export
```

## PostgreSQL: CAST Definitions and Replica Identity (v1.1+)

### Custom CASTs

```hcl
cast {
  source = varchar
  target = composite.my_type
  with   = INOUT
}

cast {
  source = int4
  target = composite.my_type
  with   = function.int4_to_my_type
  as     = ASSIGNMENT
}
```

`with`: `INOUT` (type I/O functions) or a function reference. `as`: `IMPLICIT`, `ASSIGNMENT`, or explicit-only (default).

### Replica Identity

Configure logical replication row identification:

```hcl
table "users" {
  schema = schema.public
  replica_identity = FULL
}

table "accounts" {
  schema = schema.public
  index "idx_account_id" {
    unique  = true
    columns = [column.account_id]
  }
  replica_identity = index.idx_account_id
}
```

Options: primary key (default), unique index reference, or `FULL`.

## Project Configuration

Create `atlas.hcl` for environment configuration:

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

  format {
    migrate {
      diff = "{{ sql . \"  \" }}"
    }
  }
}

env "prod" {
  src = "file://schema.pg.hcl"
  url = var.db_url

  migration {
    dir = "atlas://myapp"  # Atlas Registry
  }
}
```

Run with environment:
```bash
atlas schema apply --env local --var "db_url=postgres://..."
```

## Migration Linting

Atlas analyzes migrations for safety. Configure in `atlas.hcl`:

```hcl
lint {
  destructive {
    error = true  # Fail on DROP TABLE/COLUMN
  }
  data_depend {
    error = true  # Fail on data-dependent changes
  }
  naming {
    match   = "^[a-z_]+$"
    message = "must be lowercase with underscores"
    index {
      match   = "^idx_"
      message = "indexes must start with idx_"
    }
  }
  # PostgreSQL: require CONCURRENTLY for indexes (Pro)
  concurrent_index {
    error = true
  }
}
```

Key analyzers:
- **DS**: Destructive changes (DROP SCHEMA/TABLE/COLUMN)
- **MF**: Data-dependent changes (ADD UNIQUE, NOT NULL)
- **BC**: Backward incompatible (rename table/column)
- **PG** (Pro): Concurrent index, blocking DDL

Lint migrations:
```bash
atlas migrate lint --env local --latest 1
```

Suppress specific checks in migration files:
```sql
-- atlas:nolint destructive
DROP TABLE old_users;
```

## Schema Testing

Write tests in `.test.hcl` files:

```hcl
test "schema" "user_constraints" {
  parallel = true

  exec {
    sql = "INSERT INTO users (id, email) VALUES (1, 'test@example.com')"
  }

  # Test unique constraint
  catch {
    sql   = "INSERT INTO users (id, email) VALUES (2, 'test@example.com')"
    error = "duplicate key"
  }

  assert {
    sql = "SELECT COUNT(*) = 1 FROM users"
    error_message = "expected exactly one user"
  }

  cleanup {
    sql = "DELETE FROM users"
  }
}

# Table-driven tests
test "schema" "email_validation" {
  for_each = [
    {input: "valid@test.com", valid: true},
    {input: "invalid",        valid: false},
  ]

  exec {
    sql    = "SELECT validate_email('${each.value.input}')"
    output = each.value.valid ? "t" : "f"
  }
}
```

Run tests:
```bash
atlas schema test --env local schema.test.hcl
```

## Transaction Modes

Control transaction behavior per-file with directives:

```sql
-- atlas:txmode none
CREATE INDEX CONCURRENTLY idx_users_email ON users (email);
```

Modes: `file` (default, one tx per file), `all` (one tx for all), `none` (no tx).

## Pre-Execution Checks (Pro)

Block dangerous operations in `atlas.hcl` (requires Atlas Pro):

```hcl
env "prod" {
  check "migrate_apply" {
    deny "too_many_files" {
      condition = length(self.planned_migration.files) > 3
      message   = "Cannot apply more than 3 migrations at once"
    }
  }
}
```

## Common Commands

```bash
# Generate migration from schema diff
atlas migrate diff migration_name --env local

# Apply pending migrations
atlas migrate apply --env local

# Validate migration directory integrity
atlas migrate validate --env local

# View migration status
atlas migrate status --env local

# Push to Atlas Registry
atlas migrate push myapp --env local

# Declarative apply (no migration files)
atlas schema apply --env local --auto-approve

# Inspect current database schema
atlas schema inspect --url "postgres://..." --format "{{ sql . }}"

# Compare schemas
atlas schema diff --from "postgres://..." --to "file://schema.hcl"
```

## CI/CD Integration

GitHub Actions setup:
```yaml
- uses: ariga/setup-atlas@v0
  with:
    cloud-token: ${{ secrets.ATLAS_CLOUD_TOKEN }}

- name: Lint migrations
  run: atlas migrate lint --env ci --git-base origin/main
```

## Baseline for Existing Databases

When adopting Atlas on existing databases:

```bash
# Create baseline migration reflecting current schema
atlas migrate diff baseline --env local --to "file://schema.hcl"

# Mark baseline as applied (skip execution)
atlas migrate apply --env prod --baseline "20240101000000"
```

## ORM Integration

Atlas supports loading schemas from ORMs via external providers:

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

Supported: GORM, Sequelize, TypeORM, Django, SQLAlchemy, Prisma, and more.

## Instructions

- Always use a dev database for `migrate diff` and `schema apply`; it validates schemas safely.
- Enable strict linting in CI to catch destructive and data-dependent changes early.
- Use versioned migrations for production; declarative workflow suits development/testing.
- Test schemas with `.test.hcl` files; validate constraints, triggers, and functions.
- Push migrations to Atlas Registry for deployment; avoid copying files manually.
- Use `-- atlas:txmode none` for PostgreSQL concurrent index operations.
- Configure naming conventions in lint rules; consistency prevents errors.
- Use declarative `role`, `user`, and `permission` blocks for security management (v1.1+ Pro); enable with `mode { roles = true; permissions = true }`.
- Without Pro, GRANT/REVOKE and role changes require hand-written migrations followed by `atlas migrate hash` and `atlas migrate validate`.
- Use `data` blocks with INSERT/UPSERT/SYNC modes for lookup tables and seed data; avoid hand-managing reference data in migrations.
- Use schema exporters to keep SQL/HCL file exports and external webhooks in sync with actual schema state.
- Manage PostgreSQL custom CASTs and replica identity declaratively in HCL; avoid manual DDL for these.
