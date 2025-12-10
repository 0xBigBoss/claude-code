Reimplement the current branch with a clean, narrative-quality git commit history suitable for reviewer comprehension. Execute each step fully before proceeding to the next.

<determine_default_branch>
First, determine the repository's default branch:
!gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'

Store this value and use it wherever `{default_branch}` appears in subsequent steps.
</determine_default_branch>

<validate_and_backup>
Before any changes, validate and backup the current state:
- Run `git status` to confirm no uncommitted changes or merge conflicts exist
- Run `git fetch origin` to get the latest remote state
- If issues exist, resolve them before proceeding
- Create a backup branch: `git branch {branch_name}-backup` to preserve the original commits
- Record the current HEAD sha for verification later
</validate_and_backup>

<analyze_diff>
Study all changes between the current branch and the default branch to form a complete understanding of the final intended state. Use `git diff` and read modified files to understand:
- What functionality was added, changed, or removed
- The logical groupings of related changes
- The dependencies between different parts of the implementation
</analyze_diff>

<reset_and_rebase>
Reset the current branch to the latest default branch while preserving all changes:
- Run `git reset origin/{default_branch}` to move HEAD to the latest default branch
- All changes from the original commits now appear as unstaged modifications in the working directory
- This effectively rebases your work onto the latest default branch with a clean slate for recommitting
</reset_and_rebase>

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
- Run `git diff {branch_name}-backup` and verify it produces no output
- If differences exist, reconcile them before proceeding
</verify_correctness>

<open_pull_request>
Create a PR from the current branch to the default branch:
- Write the PR following the instructions in `pr.md`
- Include a link to the backup branch in the PR description for reference
- Omit any AI-generated footers or co-author attributions from commits and PR
</open_pull_request>

<success_criteria>
The task is complete when:
1. The branch's final state is byte-for-byte identical to the backup branch
2. Each commit uses conventional commit format and introduces one logical change
3. The PR is opened with proper documentation and a link to the backup branch
</success_criteria>
