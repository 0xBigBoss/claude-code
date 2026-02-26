# Atlas v1.1 Feature Coverage

Atlas v1.1.0 was announced on February 3, 2026. This file tracks the new capabilities from that release and how to apply them.

Primary source:
- https://atlasgo.io/blog/2026/02/03/atlas-v1-1

## Table of Contents

- Database Security as Code
- Declarative Data Management
- Aurora DSQL support
- ClickHouse improvements
- Azure Fabric support
- PostgreSQL enhancements
- Spanner enhancements
- CockroachDB support
- Slack integration
- Schema exporters
- MySQL TLS support

## Database Security as Code

Define roles, users, and permissions in schema state, then manage through normal Atlas workflows.

```hcl
role "app_readonly" {}

user "app_user" {
  password = var.app_password
}

permission {
  for        = schema.public
  to         = role.app_readonly
  privileges = [SELECT]
}
```

Enable security mode in environment config:

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

Notes:

- Feature is Atlas Pro.
- Password values are masked in logs/inspect output.
- Prefer data sources + input variables so secrets are not hardcoded.

## Declarative Data Management

Manage lookup/seed rows as desired state:

```hcl
data {
  table = table.countries
  rows = [
    { id = 1, code = "US", name = "United States" },
    { id = 2, code = "DE", name = "Germany" },
  ]
}
```

Configure data sync policy:

```hcl
env "prod" {
  data {
    mode    = UPSERT
    include = ["countries"]
  }
}
```

Modes:

- `INSERT`: add only.
- `UPSERT`: add/update by key.
- `SYNC`: add/update/delete to exact desired state.

## Aurora DSQL Support

Use `dsql://` URLs:

```hcl
env "dsql" {
  url = "dsql://admin:${local.dsql_pass}@cluster.dsql.us-east-1.on.aws/?sslmode=require"
  dev = "docker://dsql/16"
}
```

Atlas adapts generated DDL for DSQL behavior (for example async index creation and non-transactional DDL constraints).

## ClickHouse Improvements

### Cluster mode

Use `?mode=cluster` on URL so Atlas emits cluster-aware DDL.

### Data retention on table recreation

Atlas handles table recreation flows that require `ORDER BY`/`PARTITION BY` changes by copying/swapping data to avoid loss.

## Azure Fabric Support

Atlas supports Microsoft Fabric Data Warehouse (SQL Server/T-SQL based), enabling declarative and CI/CD workflows for Fabric environments.

## PostgreSQL Enhancements

### `CAST` support

```hcl
cast {
  source = int4
  target = composite.my_type
  with   = function.int4_to_my_type
  as     = ASSIGNMENT
}
```

### Replica identity support

```hcl
table "accounts" {
  schema = schema.public
  replica_identity = FULL
}
```

You can use primary key (default), unique index, or `FULL`.

## Spanner Enhancements

### PostgreSQL dialect support

```hcl
env "spanner" {
  url = "spanner://projects/my-project/instances/my-instance/databases/my-db"
  dev = "docker://spannerpg/latest"
}
```

### Vector indexes

```hcl
index "DocEmbeddingIdx" {
  columns       = [column.DocEmbedding]
  type          = VECTOR
  distance_type = COSINE
}
```

## CockroachDB Support

Dedicated `crdb://` driver:

```hcl
env "cockroach" {
  url = "crdb://user:pass@cluster.cockroachlabs.cloud:26257/defaultdb?sslmode=verify-full"
  dev = "docker://crdb/v25.1.1/dev"
}
```

Notes:

- Supports declarative and versioned workflows.
- `sslmode=verify-full` for CockroachDB Cloud.
- Feature is Atlas Pro.

## Slack Integration

Atlas Cloud includes native Slack integration for CI completion, migration deployment, drift detection, and review notifications. Configure in Atlas Cloud settings per project/channel.

## Schema Exporters

Use declarative exporters and run inspect/diff with `--export`:

```hcl
exporter "sql" "schema" {
  path     = "schema/sql"
  split_by = object
  naming   = same
}

env "prod" {
  export {
    schema {
      inspect = exporter.sql.schema
    }
  }
}
```

Run:

```bash
atlas schema inspect --env prod --export
```

## MySQL TLS Support

Use TLS options in MySQL URL:

```text
mysql://user:pass@host:3306/db?tls=true&ssl-ca=/path/to/ca.pem
```

For client cert auth, include `ssl-cert` and `ssl-key` parameters.
