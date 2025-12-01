# Fix Linear Issue

Fix the Linear issue specified by the identifier (e.g., ENG-123).

## Instructions

1. **Fetch issue details** using the linear-cli skill:
   ```bash
   linear issue view $ARGUMENTS --json
   ```

2. **Understand the issue**: Read the title, description, and any comments to fully understand what needs to be fixed.

3. **Explore the codebase**: Search for relevant code based on the issue description. Understand the context before making changes.

4. **Implement the fix**: Make minimal, focused changes that address the issue. Follow project conventions.

5. **Verify the fix**: Run tests, linters, and builds as appropriate to ensure the fix works and doesn't break anything.

6. **Summarize**: Provide a brief summary of what was changed and why.

## Usage

```
/fix-linear ENG-123
```

Where `ENG-123` is the Linear issue identifier.
