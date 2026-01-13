---
allowed-tools: Task, Read, Write, Bash(mkdir:*), Bash(pwd:*), Bash(basename:*)
argument-hint: <project-dirs...> [--topic "optional topic focus"]
description: Gather blog post context from Claude Code sessions using dual-agent approach
---

# Blog Context Gatherer

Gather comprehensive context for writing blog posts about development work by analyzing Claude Code session transcripts. Uses a dual-agent approach for both breadth and depth.

## Arguments

Parse `$ARGUMENTS` to extract:
- **Project directories**: One or more paths to search for sessions (e.g., `~/project1 ~/project2`)
- **Topic focus** (optional): `--topic "description"` to focus the analysis

If no directories provided, use the current working directory.

## Dual-Agent Strategy

This command uses two Explore agents with different models optimized for complementary tasks:

### Agent 1: Scanner (Haiku)
**Purpose**: Fast, broad coverage - identify all relevant sessions and extract raw data.

**Responsibilities**:
- Use `/extract-transcripts` skill to list and scan sessions
- Extract concrete metrics (throughput, line counts, timings)
- Identify all session file paths for verification
- Catalog milestones, decisions, and technical choices
- Note benchmark results and performance data
- List all projects/repos covered

**Output format**: Structured data dump with file paths, metrics, timeline.

### Agent 2: Synthesizer (Sonnet)
**Purpose**: Deep analysis - create cohesive narrative from Scanner's findings.

**Responsibilities**:
- Take Scanner's output as context
- Synthesize into blog-ready narrative sections
- Explain the "why" behind technical decisions
- Identify challenges overcome and lessons learned
- Create clear feature/milestone breakdowns
- Suggest blog post angles and story arcs
- Highlight interesting technical patterns

**Output format**: Narrative prose organized for blog writing.

## Execution

### Step 1: Launch Scanner Agent (Haiku)

Spawn an Explore agent with `model: haiku` to perform broad analysis:

```
Use the /extract-transcripts skill to gather raw data from Claude Code sessions.

Project directories to scan:
{directories from $ARGUMENTS}

Topic focus: {topic if provided, otherwise "all development work"}

Tasks:
1. List all recent sessions from these projects using transcript_index.py
2. For each significant session (>10 messages), extract:
   - Session file path (full absolute path)
   - Duration and message counts
   - Key technical decisions made
   - Metrics mentioned (performance numbers, counts, sizes)
   - Files touched or discussed
   - Milestones or features completed

Output as structured markdown with clear sections:
- Session Inventory (paths, dates, sizes)
- Metrics & Numbers (any quantitative data)
- Technical Decisions (bullet list)
- Milestones Timeline (chronological)
- Files & Artifacts (paths mentioned)
```

### Step 2: Launch Synthesizer Agent (Sonnet)

After Scanner completes, spawn an Explore agent with `model: sonnet`:

```
You are synthesizing raw session data into blog-ready narrative content.

Topic: {topic if provided}
Projects: {directories}

Scanner findings:
{paste Scanner agent's full output here}

Tasks:
1. Create a cohesive project narrative:
   - What was built and why
   - The journey from start to current state
   - Key architectural decisions and their rationale

2. Identify compelling story elements:
   - Challenges overcome (with specific examples)
   - "Aha" moments or unexpected discoveries
   - Trade-offs considered and choices made
   - Technical patterns worth highlighting

3. Suggest blog post structure:
   - Potential titles/angles
   - Recommended sections
   - Code snippets worth including
   - Diagrams that would help explain concepts

4. Create ready-to-use content blocks:
   - Introduction paragraph
   - Technical deep-dive sections
   - Conclusion/lessons learned

Output as markdown sections that can be directly used or adapted for the blog post.
```

### Step 3: Combine Outputs

Write the combined output to `~/.claude/handoffs/blog-context-<project>.md`:

```markdown
# Blog Context: {project name}

Generated: {timestamp}
Projects analyzed: {list}
Topic focus: {topic or "general"}

---

## Part 1: Raw Data (Scanner)

{Scanner agent output}

---

## Part 2: Narrative Synthesis (Synthesizer)

{Synthesizer agent output}

---

## Verification

Session files analyzed:
{list of absolute paths from Scanner for verification}

To extract full transcript from any session:
python3 ~/.claude/skills/extract-transcripts/extract_transcript.py <path>
```

## Output

1. Display summary to user showing:
   - Number of sessions analyzed
   - Projects covered
   - Suggested blog angles

2. Save full context to `~/.claude/handoffs/blog-context-<project>.md`

3. Confirm: "Blog context saved to `~/.claude/handoffs/blog-context-<project>.md`"

## Usage Examples

```bash
# Single project
/blog-context ~/myproject

# Multiple projects
/blog-context ~/frontend ~/backend --topic "building the auth system"

# Current directory with topic
/blog-context . --topic "performance optimization journey"
```
