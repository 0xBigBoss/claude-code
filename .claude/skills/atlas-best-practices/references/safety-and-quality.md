# Atlas Safety and Quality

## Table of Contents

- Migration linting
- Lint suppressions
- Schema testing
- Transaction modes
- Pre-execution checks
- CI integration
- Review checklist

## Migration Linting

Configure analyzers in `atlas.hcl`:

```hcl
lint {
  destructive {
    error = true
  }
  data_depend {
    error = true
  }
  naming {
    match   = "^[a-z_]+$"
    message = "must be lowercase with underscores"
    index {
      match   = "^idx_"
      message = "indexes must start with idx_"
    }
  }
  concurrent_index {
    error = true
  }
}
```

Analyzer intent:

- `DS`: destructive changes (drop schema/table/column).
- `MF`: data-dependent changes (constraints, not-null transitions).
- `BC`: backward-incompatible changes (renames and incompatible contracts).
- `PG` (Pro): PostgreSQL operational safety such as concurrent index rules.

Run:

```bash
atlas migrate lint --env local --latest 1
```

## Lint Suppressions

Use targeted suppressions only when justified:

```sql
-- atlas:nolint destructive
DROP TABLE old_users;
```

Always include a code review note for why suppression is safe.

## Schema Testing

Use `.test.hcl` files for behavior checks:

```hcl
test "schema" "user_constraints" {
  exec {
    sql = "INSERT INTO users (id, email) VALUES (1, 'test@example.com')"
  }

  catch {
    sql   = "INSERT INTO users (id, email) VALUES (2, 'test@example.com')"
    error = "duplicate key"
  }

  assert {
    sql = "SELECT COUNT(*) = 1 FROM users"
    error_message = "expected exactly one user"
  }
}
```

Run:

```bash
atlas schema test --env local schema.test.hcl
```

## Transaction Modes

Per-file directive:

```sql
-- atlas:txmode none
CREATE INDEX CONCURRENTLY idx_users_email ON users (email);
```

Modes:

- `file` (default): one transaction per migration file.
- `all`: one transaction across all files in apply.
- `none`: no transaction wrapping (required for some DDL on specific engines).

## Pre-Execution Checks

For Atlas Pro, block unsafe plans before apply:

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

## CI Integration

Example GitHub Actions step:

```yaml
- uses: ariga/setup-atlas@v0
  with:
    cloud-token: ${{ secrets.ATLAS_CLOUD_TOKEN }}

- name: Lint migrations
  run: atlas migrate lint --env ci --git-base origin/main
```

## Review Checklist

- Is the correct environment selected?
- Is `dev` configured and isolated?
- Did lint pass without broad suppressions?
- Did schema tests cover constraints and failure paths?
- Are destructive operations intentionally approved?
- Is migration directory integrity validated?

```bash
atlas migrate validate --env local
atlas migrate status --env local
```
