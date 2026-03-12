---
name: canton-nodes
description: Canton validator node reference data. Use for participant IDs, database names, port availability, and architecture context.
---

# Canton Validator Nodes

Reference data for Send's Canton validators. For connection commands, use the `sinfra` CLI.

## Quick Access

```bash
sinfra hosts --filter testnet    # List testnet hosts
sinfra psql canton-testnet-docker --exec  # Connect to postgres (with with-secrets)
sinfra grpc canton-testnet-docker health  # Health check
```

See the `sinfra` skill for full CLI documentation.

## Participant Info

| Environment | UID | User |
|-------------|-----|------|
| Devnet | `send-dev-1::122033c9...` | - |
| Testnet | `send-test-cantonwallet-1::1220f760...` | `tn-validator-waxuq421oyl8wdbbj3gwizlkycqpfsyl@clients` |
| Mainnet | `send-cantonwallet-1::1220f1b0...` | `cantonwallet_validator@clients` |

## Port Availability

| Port | Service | Devnet | Testnet | Mainnet |
|------|---------|--------|---------|---------|
| 5001 | Ledger API | closed | open | open |
| 5002 | Admin API | open | open | open |
| 5003 | Validator HTTP | closed | open | open |
| 7575 | JSON API | open | open | open |
| 8080 | Scan API | closed | open | open |
| 8090 | External Admin | closed | open | open |
| 8091 | External Ledger | closed | open | open |
| 45432 | PQS Postgres | - | - | open |

## Postgres Databases

| Environment | Host | Databases |
|-------------|------|-----------|
| Devnet | canton-devnet-docker | `participant-1`, `validator` |
| Testnet | canton-testnet-docker | `participant-0`, `participant-1`, `validator` |
| Mainnet | canton-mainnet-docker | `participant-3`, `participant-4`, `validator` |
| Mainnet PQS | canton-mainnet-docker:45432 | `pqs-app-provider-4` (via pqs-postgres) |

## API URLs

**Testnet:**
```
http://canton-testnet-docker.tail6be6de.ts.net:{5001,5002,5003,7575,8080}
```

**Mainnet:**
```
http://canton-mainnet-docker.tail6be6de.ts.net:{5001,5002,5003,7575,8080}
```

**Kubernetes (in-cluster):**
```
http://canton-testnet-proxy.tailscale.svc.cluster.local:{5001,5002,5003,8080}
http://canton-mainnet-proxy.tailscale.svc.cluster.local:{5001,5002,5003,8080,45432}
```

### Scan API (port 8080)

Nginx caching reverse proxy round-robining across 13 SV scan endpoints. GET cached 30s, POST cached 5s. Returns `X-Cache-Status` header (MISS/HIT).

```bash
# Health check
curl http://canton-mainnet-docker.tail6be6de.ts.net:8080/healthz

# DSO info
curl http://canton-mainnet-docker.tail6be6de.ts.net:8080/api/scan/v0/dso

# From K8s pod
curl http://canton-mainnet-proxy.tailscale.svc.cluster.local:8080/api/scan/v0/dso
```

Config on server: `/data/canton/{testnet,mainnet}/compose-scan-proxy.yaml`

## Public Endpoints (Cloudflare Tunnels)

| Endpoint | Env | API | Backend |
|----------|-----|-----|---------|
| `grpc-ta.cantonwallet.com` | testnet | Admin | `envoy-proxy:8090` |
| `grpc-tl.cantonwallet.com` | testnet | Ledger | `envoy-proxy:8091` |
| `json-api-testnet.cantonwallet.com` | testnet | JSON API | `participant:7575` |
| `grpc-ma.cantonwallet.com` | mainnet | Admin | `envoy-proxy:8090` |
| `grpc-ml.cantonwallet.com` | mainnet | Ledger | `envoy-proxy:8091` |
| `json-api-mainnet.cantonwallet.com` | mainnet | JSON API | `participant:7575` |
| `grpc-da.cantonwallet.com` | devnet | Admin | `envoy-proxy:8090` |
| `grpc-dl.cantonwallet.com` | devnet | Ledger | `envoy-proxy:8091` |

gRPC convention: `grpc-{t|m|d}{a|l}.cantonwallet.com`. No validator gRPC routes via CF.

All routes authenticated via CF Access service tokens. gRPC routes use Envoy for gRPC-Web conversion. JSON API credentials are in 1Password `api-gateway-secrets` items (`CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`). gRPC credentials are in `grpc-tunnel` items.

DNS and tunnel config: `terraform/infra/dns-cantonwallet.tf`

## Architecture

- Canton environments run as Docker containers with Tailscale sidecars
- Each environment exposes services on a unique Tailscale FQDN (`canton-testnet-docker`, etc.)
- Host machines (`send-canton01`, `send-canton02`) run multiple environment containers

## Related

- CLI: `sinfra` skill
- Tailscale egress: `kubernetes/infrastructure/swiss/tailscale/egress-canton.yaml`
