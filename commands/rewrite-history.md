Reimplement the current branch with a clean, narrative-quality git commit history suitable for reviewer comprehension. Execute each step fully before proceeding to the next.

## Determine Branch Name

First, determine the current branch name:
!git branch --show-current

Store this value and use it wherever `{branch_name}` appears in subsequent steps.

## Determine Default Branch

First, determine the repository's default branch:
!gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'

Store this value and use it wherever `{default_branch}` appears in subsequent steps.

## Hard Rules
- Rewrite history in-place on the current branch name (`{branch_name}`).
- You may create additional branches for independent changes (see Triage Changes and Create Independent Branches below).
- Create a local backup ref before rewriting (prefer an annotated tag). Do not push backup refs unless I explicitly ask.
- Before any history-rewriting command (`git reset`, `git rebase`, `git push --force*`), print the exact command(s) you will run and wait for my confirmation.
- After rewriting, update the remote branch using `git push --force-with-lease origin HEAD:{branch_name}`. Do not push independent branches without my confirmation.
- If syncing with `origin/{default_branch}` results in conflicts, abort and stop. Do not attempt to resolve conflicts as part of this rewrite-history workflow.

## Validate and Backup

Before any changes, validate the current state:
- Run `git status` to confirm no uncommitted changes or merge conflicts exist
- Run `git fetch origin` to get the latest remote state
- If issues exist, resolve them before proceeding
- Record the current HEAD sha for verification later

## Analyze Diff

Study all changes between the current branch and the default branch to form a complete understanding of the final intended state. Use `git diff` and read modified files to understand:
- What functionality was added, changed, or removed
- The logical groupings of related changes
- The dependencies between different parts of the implementation

## Sync with Default Branch

Sync with the latest `origin/{default_branch}` as a separate step (do this *before* rewriting history):
1. Ensure working tree clean (`git status`) and fetch latest (`git fetch origin`).
2. Integrate `origin/{default_branch}` into your branch so the final, intended state already includes the latest default branch changes:
   - Prefer a non-rewriting merge for this pre-step:
     - `git merge --no-ff origin/{default_branch}`
   - If you explicitly prefer a linear history for this pre-step, you may rebase instead:
     - `git rebase origin/{default_branch}`
3. If conflicts occur:
   - Do not resolve conflicts as part of this rewrite-history workflow.
   - Abort the operation (`git merge --abort` or `git rebase --abort`) and stop.
   - Ask me to run the separate `git-rebase-sync` skill/workflow before continuing.

Note: The goal is to avoid mixing "conflict resolution vs latest default branch" into the later history rewrite step.

## Create Backup Ref

Create a local backup ref (annotated tag preferred) *after* the sync step above, so the backup represents the final intended tree state:
- `git tag -a {branch_name}-rewrite-backup-$(date +%Y%m%d-%H%M%S) -m "pre-rewrite backup" HEAD`

Record the backup ref name you created. You will use it as `{backup_ref}` below.

## Triage Changes

After syncing, categorize every change (against the now-current `origin/{default_branch}`) into one of two buckets:

1. **Core feature** — directly implements the branch's purpose (the feature, fix, or enhancement).
2. **Independent** — unrelated improvements that could merge separately (dev tooling, localnet config, linter fixes, dependency bumps, chore cleanup, unrelated refactors).

Present the triage as a table:

| Files | Category | Branch (if independent) |
|-------|----------|-------------------------|

For independent changes, propose a namespaced branch: `{branch_name}/split/<short-description>` (e.g. `feat/auth/split/chore-localnet-config`). This avoids collisions in multi-contributor repos.

If no independent changes are identified, note that and skip ahead to Reset and Recommit In-Place.

## Reset and Recommit In-Place

Rewrite in-place on the current branch (`{branch_name}`), without switching branches:
1. Ensure the working tree is clean (`git status`).
2. Fetch latest `origin` (`git fetch origin`).
3. Confirm your backup ref exists and points at the pre-rewrite HEAD.
4. Reset the branch to `origin/{default_branch}` while keeping changes (default to `--mixed` so changes are unstaged):
   - `git reset --mixed origin/{default_branch}`
   - If you explicitly want everything staged, you may use `--soft` instead.

Before running step (4), print the exact `git reset ...` command you intend to run and wait for my confirmation.

## Plan Commit Storyline

Present the full commit plan for my approval. This is the single confirmation gate — include the triage classification inline so I can review both the split and the narrative in one pass.

**Ordering rule**: Independent (non-feature) commits go first (bottom of history), core feature commits follow on top. This ensures independent commits can be cherry-picked onto separate branches cleanly.

For each planned commit, show:
- Commit message (conventional commit format)
- Category: `independent` or `core`
- Files touched

Within each bucket, order commits as a logical narrative — each step should reflect a stage of development, as if writing a tutorial. Wait for my approval before committing. I may reclassify items or reorder.

## Reimplement Work

Recommit the changes step by step according to your plan using conventional commits. Each commit must:
- Follow the conventional commit format: `type(scope): description` (e.g., `feat(auth): add login endpoint`, `fix(api): handle null response`)
- Introduce a single coherent idea that builds on previous commits
- Include a commit body explaining the "why" when the change is non-obvious
- Add inline comments when the code's intent requires explanation

Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`

Use `--no-verify` only when bypassing known CI issues. Individual commits need not pass all checks, but this should be rare.

## Verify Correctness

Before opening a PR, confirm the final state matches the backup:
- Run `git diff {backup_ref}` and verify it produces no output
- If differences exist, reconcile them before proceeding

## Create Independent Branches

If the triage identified independent changes, create a branch for each independent group without leaving `{branch_name}`:

1. For each independent group, create a branch off `origin/{default_branch}`:
   - `git branch {independent_branch_name} origin/{default_branch}`
2. Cherry-pick the corresponding commits onto each independent branch without switching:
   - `git cherry-pick --no-commit <commit-sha> && git -C . stash && git checkout {independent_branch_name} && git stash pop && git commit -C <commit-sha> && git checkout {branch_name}`
   - Or, more reliably: `git worktree add /tmp/{independent_branch_name} {independent_branch_name} && git -C /tmp/{independent_branch_name} cherry-pick <commit-sha>... && git worktree remove /tmp/{independent_branch_name}`
3. List the created branches and their commits for my review. Do not push them until I confirm.

Note: The feature branch (`{branch_name}`) still contains all commits (independent + core). The independent branches are convenience copies for early merging. After independent PRs land in `{default_branch}`, the feature branch should be rebased to drop the now-redundant commits (use the `git-rebase-sync` skill for that).

## Push Rewritten Branch

After verification, force-update the remote branch on the same name:
- Print the exact `git push ...` command you intend to run and wait for my confirmation.
- Use: `git push --force-with-lease origin HEAD:{branch_name}`

## Push Independent Branches

If independent branches were created, list them with their commits and ask for confirmation before pushing. For each confirmed branch:
- `git push -u origin {independent_branch_name}`
- Create a PR from `{independent_branch_name}` to `{default_branch}` following the instructions in `pr.md`.
- Mark these PRs as ready to merge independently of the feature branch.

## PR Handling

- If a PR already exists for `{branch_name}`, do not create a new PR; update the existing PR description as needed.
- If no PR exists, create one from `{branch_name}` to `{default_branch}`.
- Write the PR following the instructions in `pr.md` (or the repo's PR template if `pr.md` does not exist).
- Include a link to `{backup_ref}` (the tag) in the PR description for reference.
- If independent branches were split out, list them in the PR description with links to their PRs and a note that they can be merged first to reduce the feature diff.
- Omit any AI-generated footers or co-author attributions from commits and PR.

## Success Criteria

The task is complete when:
1. The branch's final state is byte-for-byte identical to `{backup_ref}`
2. Each commit uses conventional commit format and introduces one logical change
3. Independent commits are ordered first (bottom of history), core feature commits on top
4. Independent branches exist with cherry-picked copies of the independent commits (if any were triaged)
5. The remote branch `{branch_name}` is updated via `--force-with-lease` (same branch name only)
6. Independent branches are pushed and have PRs (with my confirmation)
7. If a PR already existed for the feature, it was updated; otherwise a PR was created, with proper documentation, a link to `{backup_ref}`, and references to independent PRs
