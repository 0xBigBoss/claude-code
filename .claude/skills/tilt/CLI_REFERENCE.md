# Tilt CLI Reference

## Table of Contents

- [Resource Queries](#resource-queries)
- [Logs](#logs)
- [Control Commands](#control-commands)
- [Wait Conditions](#wait-conditions)
- [JSON Parsing Patterns](#json-parsing-patterns)

## Resource Queries

### List All Resources

```bash
tilt get uiresources -o json
```

JSON structure:

```json
{
  "apiVersion": "tilt.dev/v1alpha1",
  "kind": "UIResource",
  "items": [{
    "metadata": {"name": "resource-name"},
    "status": {
      "runtimeStatus": "unknown|none|pending|ok|error|not_applicable",
      "updateStatus": "none|pending|in_progress|ok|error|not_applicable",
      "triggerMode": "TriggerModeAuto|TriggerModeManual",
      "queued": false,
      "lastDeployTime": "2024-01-01T00:00:00Z",
      "conditions": [...]
    }
  }]
}
```

### Get Single Resource

```bash
tilt get uiresource/<name> -o json
```

### Describe Resource (Human-Readable)

```bash
tilt describe uiresource/<name>
```

Note: `describe` outputs human-readable format only; use `get -o json` for structured output.

### List Available Resource Types

```bash
tilt api-resources
```

## Logs

**Note**: Always use snapshot-based log retrieval, not streaming (`-f`). Streaming doesn't work well with agent tooling.

### Snapshot Logs

```bash
tilt logs <resource>              # Get current logs snapshot
tilt logs <resource1> <resource2> # Multiple resources
```

### Filter and Search Logs

```bash
# Filter by level/source at capture time
tilt logs --level=warn <resource>             # Only warn/error
tilt logs --source=build <resource>           # Build logs only
tilt logs --source=runtime <resource>         # Runtime logs only

# Pipe to search tools for specific patterns
tilt logs <resource> | tail -50               # Recent logs
tilt logs <resource> | head -100              # First logs
tilt logs <resource> | rg -i "error|fail"     # Search for errors
tilt logs <resource> | rg "listening on"      # Find startup confirmation
```

## Control Commands

### Trigger Manual Update

```bash
tilt trigger <resource>
```

Forces an update even if no files changed.

### Enable Resources

```bash
tilt enable <resource>
tilt enable <resource1> <resource2>
tilt enable --all                 # Enable all resources
tilt enable --labels=backend      # Enable by label
```

### Disable Resources

```bash
tilt disable <resource>
tilt disable <resource1> <resource2>
tilt disable --all                # Disable all resources
tilt disable --labels=frontend    # Disable by label
```

### Change Tiltfile Args

```bash
tilt args -- --env=staging
```

Updates args for running Tilt instance.

## Wait Conditions

### Wait for Ready

```bash
tilt wait --for=condition=Ready uiresource/<name>
```

### With Timeout

```bash
tilt wait --for=condition=Ready uiresource/<name> --timeout=120s
```

### Wait for Multiple Resources

```bash
tilt wait --for=condition=Ready uiresource/api uiresource/web
```

### Wait for All Resources

```bash
tilt wait --for=condition=Ready uiresource --all
```

## JSON Parsing Patterns

### Extract All Resource Names

```bash
tilt get uiresources -o json | jq -r '.items[].metadata.name'
```

### Extract Failed Resources

```bash
tilt get uiresources -o json | jq -r '.items[] | select(.status.runtimeStatus == "error") | .metadata.name'
```

### Extract Pending Resources

```bash
tilt get uiresources -o json | jq -r '.items[] | select(.status.updateStatus == "pending" or .status.updateStatus == "in_progress") | .metadata.name'
```

### Check Specific Resource Status

```bash
tilt get uiresource/<name> -o json | jq '.status.runtimeStatus'
```

### Get Status Summary

```bash
tilt get uiresources -o json | jq '.items[] | {name: .metadata.name, runtime: .status.runtimeStatus, update: .status.updateStatus}'
```

### Get Last Deploy Times

```bash
tilt get uiresources -o json | jq '.items[] | {name: .metadata.name, deployed: .status.lastDeployTime}'
```

### Count Resources by Status

```bash
tilt get uiresources -o json | jq -r '.items | group_by(.status.runtimeStatus) | map({status: .[0].status.runtimeStatus, count: length})'
```

### Check if All Resources Ready

```bash
tilt get uiresources -o json | jq -e '[.items[].status.runtimeStatus] | all(. == "ok" or . == "not_applicable")'
```

Returns exit code 0 if all ready, 1 otherwise.

## Lifecycle Commands

### Start Tilt

```bash
tilt up
tilt up --stream          # Stream logs to terminal
tilt up --port=10351      # Custom API port
tilt up -- --env=dev      # Pass args to Tiltfile
```

### Stop Tilt

```bash
tilt down
```

Removes resources created by `tilt up`.

### CI Mode

```bash
tilt ci                   # Default timeout: 30m
tilt ci --timeout=10m     # Custom timeout
```

Runs until all resources reach steady state or error, then exits.

### Verify Installation

```bash
tilt verify-install
```

### Version

```bash
tilt version
```

## Global Flags

```
-d, --debug      Enable debug logging
-v, --verbose    Enable verbose logging
--klog int       Kubernetes API logging (0-4: debug, 5-9: tracing)
--host string    Host for Tilt API server (default "localhost")
--port int       Port for Tilt API server (default 10350)
```
