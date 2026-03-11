---
name: spec-best-practices
description: Spec authoring conventions for naming, placement, structure, and lifecycle. Use when creating, reviewing, or updating SPEC.md files, running /specout, or entering the ADF SPEC gate.
---

## When to activate

Engage when:
- Creating a new spec (greenfield or retroactive)
- Reviewing or updating an existing `SPEC.md`
- Entering the ADF `SPEC` gate
- Running `/specout`
- An agent proposes a spec file with the wrong name or location

## Naming

Always `SPEC.md`. No exceptions for the primary spec file.

- Not `feature.spec.md`, not `thing-spec.md`, not `SPEC-feature.md`
- The file name is always exactly `SPEC.md`

Supporting documents linked from a `SPEC.md` TOC may use descriptive names (e.g., `commands.spec.md`, `config-and-state.spec.md`), but only when the root or package `SPEC.md` exists and links to them.

## Placement

Specs are colocated with the code they describe.

### Standard layout

```
repo/
  SPEC.md                    # root spec: project-level scope
  apps/foo/SPEC.md           # app-level spec
  packages/bar/SPEC.md       # package-level spec
  src/lib/module/SPEC.md     # module-level spec (non-monorepo)
```

### Rules

- Root `SPEC.md` covers the project/repo scope: problem, solution, domain model, cross-cutting requirements.
- Package/app/module `SPEC.md` files cover the behavior of that unit.
- Avoid `spec/`, `docs/specs/`, and `docs/plans/` directories by default. Prefer colocated `SPEC.md` files and adjacent supporting docs.
- Plan documents are ephemeral. If a plan captures durable decisions, absorb them into the relevant `SPEC.md` and delete the plan doc.

### When a spec gets long

Add a TOC to the `SPEC.md` linking to adjacent supporting files:

```markdown
## Specifications

- [Commands](./commands.spec.md)
- [Config and State](./config-and-state.spec.md)
- [Error Handling](./errors-and-observability.spec.md)
```

Supporting files live alongside the `SPEC.md` that references them, not in a subdirectory. Exception: large single-binary projects with many cross-cutting spec topics may use a `spec/` directory with a contracts index when the domain is complex enough that colocated `SPEC.md` trees would be awkward. Treat this as an explicit exception, not the default layout.

## Content

Specs are freeform markdown. No rigid template, no YAML frontmatter, no required section ordering. The following elements must be present, arranged in whatever order suits the domain.

### Required elements

**Problem and solution** -- narrative context for why this system/feature exists. Lead with the problem.

**Domain model** -- types, relationships, data flow. Required for new systems. For retroactive specs, derive from inspected code.

**Requirements with `REQ-*` IDs** -- every behavioral requirement gets a stable identifier.
- Format: `REQ-{DOMAIN}-{NNN}` (e.g., `REQ-AUTH-001`, `REQ-SYNC-003`)
- Domain prefix matches the module/package scope
- Append-only; never renumber
- Each requirement is testable and traceable

**Invariants** -- conditions that must always hold. State inline with requirements or in a dedicated section.

**Non-goals** -- explicit scope boundary. What this spec intentionally does not cover. Prevents scope creep and sets expectations for reviewers.

**Acceptance criteria** -- checklistable verification items. Use markdown checklists, not prose.

```markdown
## Acceptance Criteria

- [ ] Auth endpoint returns JWT with tier claim
- [ ] Rate limiter rejects >100 req/min per IP
- [ ] Drift scan completes in <5s for repos with <1000 managed files
```

### Conditional elements

**Risk tags** -- flag high-risk items (schema migrations, auth changes, public API contracts, infra changes). Include them when those risks exist or when the ADF `PLAN` gate requires approval.

**Test traceability** -- maps `REQ-*` IDs to test file:line references. Added during or after the TDD/DEV phase, not at initial authoring.

```markdown
## Test Traceability

| Requirement | Test |
|-------------|------|
| REQ-AUTH-001 | src/auth/auth.test.ts:42 |
| REQ-SYNC-003 | src/sync/sync.test.ts:87 |
```

**`[Normative]` / `[Informative]` section labels** -- use when multiple specs cross-reference each other and precision matters about which sections define binding contracts vs. provide examples.

## Authoring rules

### Evidence-based

Read code before writing spec content. Do not invent behavior, signatures, or file paths. For retroactive specs, derive requirements from the actual implementation.

### Retroactive specs are first-class

Documenting existing behavior in a `SPEC.md` is valid and encouraged. Retroactive specs follow the same structure and naming rules. When writing retroactively:
1. Read the implementation thoroughly
2. Extract requirements from actual behavior
3. Note any discovered inconsistencies as open items, not silent omissions
4. Map test traceability to existing tests

### Mutation policy

- Do not edit a spec without explicit user direction
- When drift is found between spec and code, surface it immediately (use `specalign` patterns)
- Never silently tolerate drift; never silently fix it
- The user decides whether to update spec or code for each discrepancy

### Spec vs. plan

Specs describe **what** the system does and **why**. Plans describe **how** and **when** to build it. Plans are ephemeral work artifacts; specs are durable project documentation.

If a plan doc contains decisions that should outlive the implementation sprint, those decisions belong in the spec. Delete the plan doc after absorption.

## Lifecycle

### Creation (SPEC gate)

The ADF `SPEC` gate requires: IDs, invariants, non-goals, acceptance criteria, and risk tags when high-risk items exist.

When entering the SPEC gate:
1. Determine placement: which `SPEC.md` file should this go in?
2. If the file exists, read it and identify gaps
3. If the file doesn't exist, create it at the correct colocated path
4. Ensure all required elements are present before passing the gate

### Maintenance

- Update spec when behavior changes (spec leads code changes; code leads retroactive spec updates)
- Append new `REQ-*` IDs; never renumber existing ones
- Add test traceability as tests are written
- Run `specalign` when both spec and implementation are in context

### Retirement

When a feature is removed, remove or archive its `SPEC.md`. Do not leave stale specs that describe deleted behavior.
