---
name: linear-cli
description: Provides Linear CLI patterns for issue management, branch workflows, and pull request creation. Activates when working with Linear issues, creating PRs with Linear integration, or when the user mentions Linear, issue tracking, or ticket workflows.
---

# Linear CLI Usage

## Required Configuration

The CLI requires certain parameters that must be provided via flags, config file, or environment variables:

- **Sort order**: Set `LINEAR_ISSUE_SORT=priority` or use `--sort priority` (required for `list`)
- **Team**: Set via `--team <KEY>` flag or run from a directory with `.linear.toml` config

Run `linear config` to interactively generate a `.linear.toml` configuration file.

## Listing Issues

```bash
# List your assigned issues (sort is required)
LINEAR_ISSUE_SORT=priority linear issue list --team SEN

# Filter by state (default: unstarted)
LINEAR_ISSUE_SORT=priority linear issue list --team SEN --state started
LINEAR_ISSUE_SORT=priority linear issue list --team SEN --state backlog
LINEAR_ISSUE_SORT=priority linear issue list --team SEN --all-states

# Filter by assignee
LINEAR_ISSUE_SORT=priority linear issue list --team SEN --all-assignees
LINEAR_ISSUE_SORT=priority linear issue list --team SEN --assignee username
LINEAR_ISSUE_SORT=priority linear issue list --team SEN --unassigned

# Open in browser/app
linear issue list --team SEN --web
linear issue list --team SEN --app
```

**Available states**: `triage`, `backlog`, `unstarted`, `started`, `completed`, `canceled`

**Priority indicators in output**:
- `⚠⚠⚠` = Urgent priority
- `▄▆█` = High priority
- `▄▆` = Medium priority
- `---` = Low/No priority

## Starting Work on an Issue

```bash
# Start working on an issue (creates branch, updates status)
linear issue start ABC-123

# Get issue ID from current branch
linear issue id
```

## Viewing Issue Details

```bash
# View current branch's issue
linear issue view

# View specific issue
linear issue view ABC-123

# Open in browser
linear issue view ABC-123 --browser

# Get just the URL
linear issue url ABC-123
```

## Creating Pull Requests

```bash
# Create PR with Linear issue details (title, description, trailer)
linear issue pr

# The PR will include:
# - Issue title as PR title
# - Issue description in PR body
# - Linear-issue trailer for automatic linking
```

## Issue Management

```bash
# Get issue title (useful for commit messages)
linear issue title ABC-123

# Get issue description with trailer (for PR body)
linear issue describe ABC-123

# Create a new issue
linear issue create

# Update an existing issue
linear issue update ABC-123

# Delete an issue
linear issue delete ABC-123
```

## Team Management

```bash
# List available teams
linear team list
```

## Branch Naming Convention

Linear CLI creates branches in the format: `<username>/<issue-id>-<slug>`

Example: `allen/abc-123-fix-login-bug`

The `linear issue id` command extracts the issue ID from this branch name.

## Integration Tips

- Commit messages can reference issues with `Fixes ABC-123` or `Closes ABC-123`
- PR descriptions automatically link when created with `linear issue pr`
- Use `linear issue describe` output for detailed commit messages with proper trailers
