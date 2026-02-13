Reimplement the current branch with a clean, narrative-quality git commit history suitable for reviewer comprehension. Execute each step fully before proceeding to the next.

<determine_branch_name>
First, determine the current branch name:
!git branch --show-current

Store this value and use it wherever `{branch_name}` appears in subsequent steps.
</determine_branch_name>

<determine_default_branch>
First, determine the repository's default branch:
!gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'

Store this value and use it wherever `{default_branch}` appears in subsequent steps.
</determine_default_branch>

## Hard Rules
- Do not create or switch to a different feature branch. Rewrite history in-place on the current branch name (`{branch_name}`).
- Create a local backup ref before rewriting (prefer an annotated tag). Do not push backup refs unless I explicitly ask.
- Before any history-rewriting command (`git reset`, `git rebase`, `git push --force*`), print the exact command(s) you will run and wait for my confirmation.
- After rewriting, update the remote branch using `git push --force-with-lease origin HEAD:{branch_name}`. Do not push to any other branch.
- If syncing with `origin/{default_branch}` results in conflicts, abort and stop. Do not attempt to resolve conflicts as part of this rewrite-history workflow.

<validate_and_backup>
Before any changes, validate the current state:
- Run `git status` to confirm no uncommitted changes or merge conflicts exist
- Run `git fetch origin` to get the latest remote state
- If issues exist, resolve them before proceeding
- Record the current HEAD sha for verification later
</validate_and_backup>

<analyze_diff>
Study all changes between the current branch and the default branch to form a complete understanding of the final intended state. Use `git diff` and read modified files to understand:
- What functionality was added, changed, or removed
- The logical groupings of related changes
- The dependencies between different parts of the implementation
</analyze_diff>

<sync_with_default_branch>
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
</sync_with_default_branch>

<create_backup_ref>
Create a local backup ref (annotated tag preferred) *after* the sync step above, so the backup represents the final intended tree state:
- `git tag -a {branch_name}-rewrite-backup-$(date +%Y%m%d-%H%M%S) -m "pre-rewrite backup" HEAD`

Record the backup ref name you created. You will use it as `{backup_ref}` below.
</create_backup_ref>

<reset_and_recommit_in_place>
Rewrite in-place on the current branch (`{branch_name}`), without switching branches:
1. Ensure the working tree is clean (`git status`).
2. Fetch latest `origin` (`git fetch origin`).
3. Confirm your backup ref exists and points at the pre-rewrite HEAD.
4. Reset the branch to `origin/{default_branch}` while keeping changes (default to `--mixed` so changes are unstaged):
   - `git reset --mixed origin/{default_branch}`
   - If you explicitly want everything staged, you may use `--soft` instead.

Before running step (4), print the exact `git reset ...` command you intend to run and wait for my confirmation.
</reset_and_recommit_in_place>

<plan_commit_storyline>
Break the implementation into a sequence of self-contained steps. Each step should reflect a logical stage of development, as if writing a tutorial that teaches the reader how to build this feature. Document your planned commit sequence before implementing.
</plan_commit_storyline>

<reimplement_work>
Recommit the changes step by step according to your plan using conventional commits. Each commit must:
- Follow the conventional commit format: `type(scope): description` (e.g., `feat(auth): add login endpoint`, `fix(api): handle null response`)
- Introduce a single coherent idea that builds on previous commits
- Include a commit body explaining the "why" when the change is non-obvious
- Add inline comments when the code's intent requires explanation

Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`

Use `--no-verify` only when bypassing known CI issues. Individual commits need not pass all checks, but this should be rare.
</reimplement_work>

<verify_correctness>
Before opening a PR, confirm the final state matches the backup:
- Run `git diff {backup_ref}` and verify it produces no output
- If differences exist, reconcile them before proceeding
</verify_correctness>

<push_rewritten_branch>
After verification, force-update the remote branch on the same name:
- Print the exact `git push ...` command you intend to run and wait for my confirmation.
- Use: `git push --force-with-lease origin HEAD:{branch_name}`
</push_rewritten_branch>

<pr_handling>
PR handling:
- If a PR already exists for `{branch_name}`, do not create a new PR; update the existing PR description as needed.
- If no PR exists, create one from `{branch_name}` to `{default_branch}`.
- Write the PR following the instructions in `pr.md` (or the repo's PR template if `pr.md` does not exist).
- Include a link to `{backup_ref}` (the tag) in the PR description for reference.
- Omit any AI-generated footers or co-author attributions from commits and PR.
</pr_handling>

<success_criteria>
The task is complete when:
1. The branch's final state is byte-for-byte identical to `{backup_ref}`
2. Each commit uses conventional commit format and introduces one logical change
3. The remote branch `{branch_name}` is updated via `--force-with-lease` (same branch name only)
4. If a PR already existed, it was updated; otherwise a PR was created, with proper documentation and a link to `{backup_ref}`
</success_criteria>
