---
name: tilt
description: Manages Tilt development environments via CLI and Tiltfile authoring. Activates when working with Tiltfile, running tilt commands, querying resource status/logs, or when user mentions Tilt, local_resource, k8s_yaml, docker_build, or live_update. For detailed CLI reference see CLI_REFERENCE.md. For Tiltfile patterns see TILTFILE_API.md.
---

# Tilt Development Environment

## Instructions

- Use `tilt get uiresources -o json` to query resource status programmatically.
- Use `tilt get uiresource/<name> -o json` for detailed single resource state.
- Use `tilt logs -f <resource>` for streaming log retrieval.
- Use `tilt trigger <resource>` to force updates; `tilt wait` to block until ready.
- For Tiltfile authoring, see @TILTFILE_API.md
- For complete CLI reference with JSON parsing patterns, see @CLI_REFERENCE.md

## Quick Reference

### Check Resource Status

```bash
tilt get uiresources -o json | jq '.items[] | {name: .metadata.name, runtime: .status.runtimeStatus, update: .status.updateStatus}'
```

### Wait for Resource Ready

```bash
tilt wait --for=condition=Ready uiresource/<name> --timeout=120s
```

### Get Resource Logs

```bash
tilt logs <resource>
```

### Trigger Update

```bash
tilt trigger <resource>
```

### Lifecycle Commands

```bash
tilt up        # Start Tilt
tilt down      # Stop and clean up
tilt ci        # CI/batch mode
```

## Resource Status Values

- **RuntimeStatus**: `unknown`, `none`, `pending`, `ok`, `error`, `not_applicable`
- **UpdateStatus**: `none`, `pending`, `in_progress`, `ok`, `error`, `not_applicable`

## References

- Tilt Documentation: https://docs.tilt.dev/
- CLI Reference: https://docs.tilt.dev/cli/tilt.html
- Tiltfile API: https://docs.tilt.dev/api.html
- Extensions: https://github.com/tilt-dev/tilt-extensions
