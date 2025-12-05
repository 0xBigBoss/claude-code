---
name: canton-docs
description: Fetches Canton Network and Daml documentation via CLI. Retrieves platform architecture, smart contract patterns, Ledger API references, and Daml language specs. Use when working with Canton Network, Daml smart contracts, or Digital Asset platform documentation.
---

# Canton Network Documentation Fetching

## Instructions

- Use pandoc for docs.digitalasset.com pages (HTML renders well)
- Use raw GitHub sources for Daml-LF specs (RST format)
- Use GitHub API for exploring repository contents
- Default version is 3.4; replace with target version as needed

## Quick Reference

### Fetch Overview Documentation

```bash
# Canton architecture overview
pandoc -f html -t plain "https://docs.digitalasset.com/overview/3.4/index.html"

# Canton introduction
pandoc -f html -t plain "https://docs.digitalasset.com/overview/3.4/introduction/canton.html"

# Ledger model explanation
pandoc -f html -t plain "https://docs.digitalasset.com/overview/3.4/explanations/canton/ledger-model.html"
```

### Fetch Daml Language Reference

```bash
# Daml language reference index
pandoc -f html -t plain "https://docs.digitalasset.com/build/3.4/reference/smart-contracts/daml/index.html"

# Templates
pandoc -f html -t plain "https://docs.digitalasset.com/build/3.4/reference/smart-contracts/daml/templates.html"

# Choices
pandoc -f html -t plain "https://docs.digitalasset.com/build/3.4/reference/smart-contracts/daml/choices.html"

# Data types
pandoc -f html -t plain "https://docs.digitalasset.com/build/3.4/reference/smart-contracts/daml/data-types.html"
```

### Fetch Daml Standard Library

```bash
# Standard library index
pandoc -f html -t plain "https://docs.digitalasset.com/build/3.4/reference/daml/stdlib/index.html"

# Specific modules (replace DA-List with target module)
pandoc -f html -t plain "https://docs.digitalasset.com/build/3.4/reference/daml/stdlib/DA-List.html"
pandoc -f html -t plain "https://docs.digitalasset.com/build/3.4/reference/daml/stdlib/DA-Map.html"
pandoc -f html -t plain "https://docs.digitalasset.com/build/3.4/reference/daml/stdlib/DA-Optional.html"
```

### Fetch Ledger API References

```bash
# gRPC Ledger API
pandoc -f html -t plain "https://docs.digitalasset.com/build/3.4/reference/app-dev/ledger-api/lapi-proto-docs.html"

# JSON Ledger API
pandoc -f html -t plain "https://docs.digitalasset.com/build/3.4/reference/app-dev/ledger-api/json-api.html"
```

### Fetch Raw Daml-LF Specifications

```bash
# Daml-LF v2 language spec (authoritative)
curl -sL "https://raw.githubusercontent.com/digital-asset/daml/main/sdk/daml-lf/spec/daml-lf-2.rst"

# Transaction semantics
curl -sL "https://raw.githubusercontent.com/digital-asset/daml/main/sdk/daml-lf/spec/transaction.rst"

# Value types
curl -sL "https://raw.githubusercontent.com/digital-asset/daml/main/sdk/daml-lf/spec/value.rst"

# List available specs
curl -sL "https://api.github.com/repos/digital-asset/daml/contents/sdk/daml-lf/spec" | jq -r '.[].name'
```

## Documentation Sources

| Source | URL Pattern | Notes |
|--------|-------------|-------|
| Main docs | `docs.digitalasset.com/<section>/<version>/` | Use pandoc |
| Daml-LF specs | `raw.githubusercontent.com/digital-asset/daml/main/sdk/daml-lf/spec/` | RST format |
| Canton repo | `github.com/digital-asset/canton` | Source code |

## Common Paths

### Overview (Architecture)

| Topic | Path |
|-------|------|
| Introduction | `overview/3.4/introduction/canton.html` |
| Multi-party apps | `overview/3.4/introduction/multi-party-applications.html` |
| Security | `overview/3.4/explanations/canton/security.html` |
| Ledger model | `overview/3.4/explanations/canton/ledger-model.html` |

### Build (Development)

| Topic | Path |
|-------|------|
| Templates | `build/3.4/reference/smart-contracts/daml/templates.html` |
| Choices | `build/3.4/reference/smart-contracts/daml/choices.html` |
| Data types | `build/3.4/reference/smart-contracts/daml/data-types.html` |
| Standard library | `build/3.4/reference/daml/stdlib/index.html` |
| Ledger API | `build/3.4/reference/app-dev/ledger-api/index.html` |

### Operate (Deployment)

| Topic | Path |
|-------|------|
| Participant setup | `operate/3.4/index.html` |
| Configuration | `operate/3.4/howtos/index.html` |

## Version-Specific Documentation

Replace `3.4` with target version (3.3, 3.5 available):

```bash
pandoc -f html -t plain "https://docs.digitalasset.com/build/3.3/reference/daml/stdlib/index.html"
```

## Troubleshooting

**Empty content:** Check URL path is correct (version number, section name).

**pandoc fails:** Verify URL exists in browser first; some pages may redirect.

**Rate limiting:** Use raw.githubusercontent.com URLs directly instead of API.

## References

- Main Documentation: https://docs.digitalasset.com/
- Canton GitHub: https://github.com/digital-asset/canton
- Daml SDK GitHub: https://github.com/digital-asset/daml
