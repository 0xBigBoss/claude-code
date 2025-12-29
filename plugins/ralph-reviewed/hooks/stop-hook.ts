#!/usr/bin/env bun
/**
 * Stop hook for Ralph Reviewed plugin.
 *
 * Intercepts exit attempts during an active Ralph loop.
 * When completion is claimed, triggers Codex review gate.
 *
 * NOTE: Ralph loops only work within git repositories. The state file is stored
 * at the git repo root (.claude/ralph-loop.local.md) to ensure it survives
 * directory changes within the repo. Outside of git repos, falls back to cwd
 * but directory changes will break the loop.
 *
 * Flow:
 * 1. Check for active loop state file (at git repo root)
 * 2. If no loop, allow exit
 * 3. Extract last assistant message from transcript
 * 4. Check for completion promise
 *    - Not found: increment iteration, block exit, re-feed prompt
 *    - Found: trigger review gate
 * 5. Review gate:
 *    - Call Codex CLI with review prompt
 *    - APPROVE: allow exit
 *    - REJECT: inject feedback, block exit, continue
 */

import { readFileSync, writeFileSync, existsSync, appendFileSync, unlinkSync, mkdirSync } from "node:fs";
import { execSync, spawnSync } from "node:child_process";
import { homedir } from "node:os";

// --- Version ---
// Update this when making changes to help diagnose cached code issues
const HOOK_VERSION = "2025-12-28T16:50:00Z";
const HOOK_BUILD = "v1.1.0-cleanup-fix";

// --- Crash Reporting ---
// Session-specific logs stored in ~/.claude/ralphs/{session_id}/
// Pre-session logs go to ~/.claude/ralphs/startup.log
const ralphsDir = `${homedir()}/.claude/ralphs`;
let sessionId = "unknown";
let sessionLogDir = ralphsDir; // Updated when session ID is known
let crashLogPath = `${ralphsDir}/startup.log`; // Before we know session ID

// Ensure base ralphs directory exists
try {
  mkdirSync(ralphsDir, { recursive: true });
} catch { /* ignore */ }

function crash(msg: string, error?: unknown) {
  const timestamp = new Date().toISOString();
  let line = `[${timestamp}] [${sessionId}] ${msg}`;
  if (error) {
    if (error instanceof Error) {
      line += `\n  Error: ${error.message}\n  Stack: ${error.stack}`;
    } else {
      line += `\n  Error: ${String(error)}`;
    }
  }
  line += "\n";
  try {
    appendFileSync(crashLogPath, line);
  } catch {
    // Last resort: stderr
    console.error(line);
  }
}

function setSessionId(id: string) {
  sessionId = id;
  sessionLogDir = `${ralphsDir}/${id}`;

  // Create session-specific directory
  try {
    mkdirSync(sessionLogDir, { recursive: true });
  } catch { /* ignore */ }

  crashLogPath = `${sessionLogDir}/crash.log`;
}

// Log startup immediately to help diagnose "operation aborted" errors
crash(`Hook starting - version: ${HOOK_BUILD} (${HOOK_VERSION}), PID: ${process.pid}`);

// Global error handlers
process.on("uncaughtException", (err) => {
  crash("Uncaught exception", err);
  // Clean up state file to avoid re-triggering loop
  if (stateFilePath) {
    try {
      unlinkSync(stateFilePath);
      crash(`Cleaned up state file on uncaught exception: ${stateFilePath}`);
    } catch { /* ignore cleanup errors */ }
  }
  // Output approve to avoid trapping user
  console.log(JSON.stringify({ decision: "approve" }));
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  crash("Unhandled rejection", reason);
  // Clean up state file to avoid re-triggering loop
  if (stateFilePath) {
    try {
      unlinkSync(stateFilePath);
      crash(`Cleaned up state file on unhandled rejection: ${stateFilePath}`);
    } catch { /* ignore cleanup errors */ }
  }
  // Output approve to avoid trapping user
  console.log(JSON.stringify({ decision: "approve" }));
  process.exit(1);
});

let debugLogPath = `${ralphsDir}/debug.log`; // Updated with session ID later
let debugEnabled = process.env.RALPH_DEBUG === "1";
let stateFilePath: string | null = null; // Set in main() for error handler access

function debug(msg: string) {
  // Always log to crash log for traceability
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] [${sessionId}] ${msg}\n`;

  // Always append to session crash log (for debugging crashes)
  try {
    appendFileSync(crashLogPath, `[DEBUG] ${line}`);
  } catch { /* ignore */ }

  // Only write to debug log if debug mode is enabled
  if (!debugEnabled) return;
  appendFileSync(debugLogPath, line);
}
import { join } from "node:path";

// --- Git Utilities ---

/**
 * Get the git repository root directory.
 * Returns null if not in a git repo or git command fails.
 */
function getGitRoot(cwd: string): string | null {
  try {
    const result = spawnSync("git", ["rev-parse", "--show-toplevel"], {
      cwd,
      encoding: "utf-8",
      timeout: 5000,
    });
    if (result.status === 0 && result.stdout) {
      return result.stdout.trim();
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Determine the state file path.
 * Uses git repo root if available, otherwise falls back to cwd.
 */
function getStateFilePath(cwd: string): string {
  const gitRoot = getGitRoot(cwd);
  const baseDir = gitRoot || cwd;
  return join(baseDir, ".claude", "ralph-loop.local.md");
}

// --- Types ---

interface HookInput {
  session_id: string;
  transcript_path: string;
  cwd: string;
  hook_event_name: "Stop";
}

interface HookOutput {
  decision: "approve" | "block";
  reason?: string;
}

interface ReviewIssue {
  id: number;
  severity: "critical" | "major" | "minor";
  description: string;
}

interface ResolvedIssue {
  id: number;
  verification: string;
}

interface ReviewHistoryEntry {
  cycle: number;
  decision: "APPROVE" | "REJECT";
  issues: ReviewIssue[];
  resolved: ResolvedIssue[];
  notes: string | null;
}

interface LoopState {
  active: boolean;
  iteration: number;
  max_iterations: number;
  completion_promise: string;
  original_prompt: string;
  timestamp: string;
  review_enabled: boolean;
  review_count: number;
  max_review_cycles: number;
  pending_feedback: string | null;
  review_history: ReviewHistoryEntry[];
  debug: boolean;
}

interface TranscriptEntry {
  type?: string;
  message?: {
    role: string;
    content: Array<{ type: string; text?: string }>;
  };
  // Legacy format fallback
  role?: string;
  content?: Array<{ type: string; text?: string }>;
}

// --- State File Parsing ---

function parseStateFile(content: string): LoopState | null {
  // Extract YAML frontmatter
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return null;

  const yaml = match[1];
  const state: Partial<LoopState> = {};

  // Parse each field
  const lines = yaml.split("\n");
  let inPrompt = false;
  let promptLines: string[] = [];

  for (const line of lines) {
    if (inPrompt) {
      if (line.startsWith("  ")) {
        promptLines.push(line.slice(2));
        continue;
      } else {
        inPrompt = false;
        state.original_prompt = promptLines.join("\n").trim();
      }
    }

    if (line.startsWith("active:")) {
      state.active = line.includes("true");
    } else if (line.startsWith("iteration:")) {
      state.iteration = parseInt(line.split(":")[1].trim(), 10);
    } else if (line.startsWith("max_iterations:")) {
      state.max_iterations = parseInt(line.split(":")[1].trim(), 10);
    } else if (line.startsWith("completion_promise:")) {
      state.completion_promise = line.split(":").slice(1).join(":").trim().replace(/^["']|["']$/g, "");
    } else if (line.startsWith("original_prompt:")) {
      const inline = line.split(":").slice(1).join(":").trim();
      if (inline === "|") {
        inPrompt = true;
        promptLines = [];
      } else {
        state.original_prompt = inline.replace(/^["']|["']$/g, "");
      }
    } else if (line.startsWith("timestamp:")) {
      state.timestamp = line.split(":").slice(1).join(":").trim().replace(/^["']|["']$/g, "");
    } else if (line.startsWith("review_enabled:")) {
      state.review_enabled = line.includes("true");
    } else if (line.startsWith("review_count:")) {
      state.review_count = parseInt(line.split(":")[1].trim(), 10);
    } else if (line.startsWith("max_review_cycles:")) {
      state.max_review_cycles = parseInt(line.split(":")[1].trim(), 10);
    } else if (line.startsWith("pending_feedback:")) {
      const val = line.split(":").slice(1).join(":").trim();
      state.pending_feedback = val === "null" ? null : val.replace(/^["']|["']$/g, "");
    } else if (line.startsWith("debug:")) {
      state.debug = line.includes("true");
    } else if (line.startsWith("review_history:")) {
      const val = line.split(":").slice(1).join(":").trim();
      if (val && val !== "[]") {
        try {
          state.review_history = JSON.parse(val);
        } catch {
          state.review_history = [];
        }
      } else {
        state.review_history = [];
      }
    }
  }

  // Validate required fields
  if (
    state.active === undefined ||
    state.iteration === undefined ||
    state.max_iterations === undefined ||
    !state.completion_promise ||
    !state.original_prompt
  ) {
    return null;
  }

  return {
    active: state.active,
    iteration: state.iteration,
    max_iterations: state.max_iterations,
    completion_promise: state.completion_promise,
    original_prompt: state.original_prompt,
    timestamp: state.timestamp || new Date().toISOString(),
    review_enabled: state.review_enabled ?? true,
    review_count: state.review_count ?? 0,
    max_review_cycles: state.max_review_cycles ?? 3,
    pending_feedback: state.pending_feedback ?? null,
    review_history: state.review_history ?? [],
    debug: state.debug ?? false,
  };
}

function serializeState(state: LoopState): string {
  const promptIndented = state.original_prompt
    .split("\n")
    .map((line) => `  ${line}`)
    .join("\n");

  return `---
active: ${state.active}
iteration: ${state.iteration}
max_iterations: ${state.max_iterations}
completion_promise: "${state.completion_promise}"
original_prompt: |
${promptIndented}
timestamp: "${state.timestamp}"
review_enabled: ${state.review_enabled}
review_count: ${state.review_count}
max_review_cycles: ${state.max_review_cycles}
pending_feedback: ${state.pending_feedback ? `"${state.pending_feedback.replace(/"/g, '\\"')}"` : "null"}
review_history: ${JSON.stringify(state.review_history)}
debug: ${state.debug}
---

# Ralph Reviewed Loop State

This file tracks the state of an active Ralph loop with review gates.

Do not edit this file manually. Use \`/ralph-reviewed:cancel-ralph\` to stop.
`;
}

// --- State File Cleanup ---

function cleanupStateFile(stateFilePath: string): void {
  try {
    if (existsSync(stateFilePath)) {
      unlinkSync(stateFilePath);
      crash(`State file deleted: ${stateFilePath}`);
      debug(`[ralph-reviewed] Cleaned up state file: ${stateFilePath}`);
    }
  } catch (e) {
    crash(`Failed to delete state file: ${stateFilePath}`, e);
    debug(`[ralph-reviewed] Failed to cleanup state file: ${e}`);
  }
}

// --- Transcript Parsing ---

function getLastAssistantMessage(transcriptPath: string): string | null {
  if (!existsSync(transcriptPath)) return null;

  try {
    const content = readFileSync(transcriptPath, "utf-8");
    const lines = content.trim().split("\n").filter(Boolean);

    // Find last assistant message (iterate backwards)
    for (let i = lines.length - 1; i >= 0; i--) {
      try {
        const entry: TranscriptEntry = JSON.parse(lines[i]);

        // Handle new format: { type: "assistant", message: { role, content } }
        const role = entry.message?.role || entry.role;
        const msgContent = entry.message?.content || entry.content;

        if (role === "assistant" && Array.isArray(msgContent)) {
          const textParts = msgContent
            .filter((c) => c.type === "text" && c.text)
            .map((c) => c.text)
            .join("\n");
          if (textParts) return textParts;
        }
      } catch {
        continue;
      }
    }
  } catch {
    return null;
  }

  return null;
}

// --- Codex Review ---

interface ReviewResult {
  approved: boolean;
  issues: ReviewIssue[];
  resolved: ResolvedIssue[];
  notes: string | null;
}

function formatIssuesForDisplay(issues: ReviewIssue[]): string {
  return issues
    .map((issue) => `  - [ISSUE-${issue.id}] ${issue.severity}: ${issue.description}`)
    .join("\n");
}

function formatResolvedForDisplay(resolved: ResolvedIssue[]): string {
  return resolved
    .map((r) => `  - [ISSUE-${r.id}] ✓ ${r.verification}`)
    .join("\n");
}

function buildReviewHistorySection(history: ReviewHistoryEntry[]): string {
  if (history.length === 0) return "";

  const sections = history.map((entry) => {
    const parts: string[] = [`### Cycle ${entry.cycle}: ${entry.decision}`];

    if (entry.resolved.length > 0) {
      parts.push(`**Resolved:**\n${formatResolvedForDisplay(entry.resolved)}`);
    }

    if (entry.issues.length > 0) {
      parts.push(`**Issues:**\n${formatIssuesForDisplay(entry.issues)}`);
    }

    if (entry.notes) {
      parts.push(`**Notes:** ${entry.notes}`);
    }

    return parts.join("\n");
  });

  return `## Previous Reviews

${sections.join("\n\n")}

`;
}

function callCodexReview(
  originalPrompt: string,
  reviewHistory: ReviewHistoryEntry[],
  reviewCount: number,
  maxReviews: number,
  cwd: string
): ReviewResult {
  crash(`callCodexReview() started - reviewCount=${reviewCount}, cwd=${cwd}`);

  // Check if codex is available
  const whichResult = spawnSync("which", ["codex"], { encoding: "utf-8" });
  if (whichResult.status !== 0) {
    crash("Codex CLI not found, approving by default");
    debug("Codex CLI not found, approving by default");
    return { approved: true, issues: [], resolved: [], notes: null };
  }
  crash(`Codex found at: ${whichResult.stdout?.trim()}`);

  // Build review history section
  const historySection = buildReviewHistorySection(reviewHistory);

  // Build review prompt with formal issue format
  const reviewPrompt = `# Code Review

Review work completed by Claude in an iterative loop. Claude claims the task is complete.

## Assignment
${originalPrompt}

## Git Context
**Working Directory**: \`pwd\`
**Repository**: \`basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"\`
**Branch**: \`git branch --show-current 2>/dev/null || echo "detached/unknown"\`
**Uncommitted changes**: \`git diff --stat 2>/dev/null || echo "None"\`
**Staged changes**: \`git diff --cached --stat 2>/dev/null || echo "None"\`
**Recent commits (last 4 hours)**: \`git log --oneline -5 --since="4 hours ago" 2>/dev/null || echo "None"\`

${historySection}## Review Process
1. Understand the task (read referenced files as needed)
2. Review git changes (\`git diff\`, \`git diff --cached\`, \`git log\`, etc.)
3. Run verification commands from success criteria if applicable
4. Check ALL requirements - be thorough, not superficial

## Output Format

If approved:
\`\`\`
<review>APPROVE</review>
<notes>Optional notes for the record</notes>
\`\`\`

If issues found:
\`\`\`
<review>REJECT</review>
<resolved>
[ISSUE-1] How you verified this previous issue is now fixed
</resolved>
<issues>
[ISSUE-1] severity: Description of the issue
[ISSUE-2] severity: Description of another issue
</issues>
<notes>Optional notes visible to future review cycles</notes>
\`\`\`

- Severity levels: \`critical\` (blocking), \`major\` (significant), \`minor\` (nice to fix)
- \`<resolved>\` section: List any previous issues you verified as fixed (omit if none or first review)
- \`<notes>\` section: Optional, visible to future review cycles
- Be thorough - report ALL issues found

Review ${reviewCount + 1}/${maxReviews}.`;

  // Use unique file paths based on timestamp to avoid collisions
  const uniqueId = Date.now();
  const outputFile = `/tmp/codex-review-output-${uniqueId}.txt`;

  crash(`Calling Codex with output file: ${outputFile}`);
  crash(`Review prompt length: ${reviewPrompt.length} chars`);

  try {
    const codexArgs = [
      "exec",
      "-",  // read prompt from stdin
      "--sandbox", "read-only",  // No writes except output file
      "-c", 'approval_policy="never"',  // Non-interactive
      "-o", outputFile,
    ];
    crash(`Codex args: ${JSON.stringify(codexArgs)}`);

    // NOTE: This timeout (20 min) must be less than plugin.json hook timeout
    // Plugin hook timeout was 120s which caused "operation aborted" errors
    const result = spawnSync("codex", codexArgs, {
      cwd,
      encoding: "utf-8",
      timeout: 1200000, // 20 minute timeout
      maxBuffer: 1024 * 1024,
      input: reviewPrompt,  // pass prompt via stdin
    });

    crash(`Codex returned - status: ${result.status}, signal: ${result.signal}, error: ${result.error}`);
    if (result.stderr) {
      crash(`Codex stderr: ${result.stderr.slice(0, 500)}`);
    }
    debug(`[ralph-reviewed] Codex exit code: ${result.status}, stderr: ${result.stderr?.slice(0, 200)}`);

    // Read output from file
    let output = "";
    if (existsSync(outputFile)) {
      output = readFileSync(outputFile, "utf-8");
      crash(`Codex output file contents: ${output.slice(0, 500)}`);
      debug(`[ralph-reviewed] Codex output: ${output.slice(0, 500)}`);
    } else {
      crash("No Codex output file created");
      debug(`[ralph-reviewed] No output file created`);
    }

    // Parse notes (present in both APPROVE and REJECT)
    const notesMatch = output.match(/<notes>([\s\S]*?)<\/notes>/);
    const notes = notesMatch ? notesMatch[1].trim() : null;

    // Parse response
    if (output.includes("<review>APPROVE</review>")) {
      crash("Codex approved");
      return { approved: true, issues: [], resolved: [], notes };
    }

    if (output.includes("<review>REJECT</review>")) {
      // Parse issues
      const issues: ReviewIssue[] = [];
      const issuesMatch = output.match(/<issues>([\s\S]*?)<\/issues>/);
      if (issuesMatch) {
        const issuePattern = /\[ISSUE-(\d+)\]\s*(critical|major|minor):\s*(.+)/gi;
        let match;
        while ((match = issuePattern.exec(issuesMatch[1])) !== null) {
          issues.push({
            id: parseInt(match[1], 10),
            severity: match[2].toLowerCase() as "critical" | "major" | "minor",
            description: match[3].trim(),
          });
        }
      }

      // Parse resolved
      const resolved: ResolvedIssue[] = [];
      const resolvedMatch = output.match(/<resolved>([\s\S]*?)<\/resolved>/);
      if (resolvedMatch) {
        const resolvedPattern = /\[ISSUE-(\d+)\]\s*(.+)/gi;
        let match;
        while ((match = resolvedPattern.exec(resolvedMatch[1])) !== null) {
          resolved.push({
            id: parseInt(match[1], 10),
            verification: match[2].trim(),
          });
        }
      }

      crash(`Codex rejected with ${issues.length} issues, ${resolved.length} resolved`);
      return { approved: false, issues, resolved, notes };
    }

    // Unclear response - default to approve
    crash("Unclear Codex response, approving by default");
    debug("Unclear Codex response, approving by default");
    return { approved: true, issues: [], resolved: [], notes: null };
  } catch (e) {
    crash("Codex review call threw exception", e);
    debug(`Codex review failed: ${e}, approving by default`);
    return { approved: true, issues: [], resolved: [], notes: null };
  }
}

// --- Main Hook Logic ---

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf-8");
}

function output(result: HookOutput): void {
  console.log(JSON.stringify(result));
}

async function main() {
  crash("main() entered");

  try {
    crash("Reading stdin...");
    const inputRaw = await readStdin();
    crash(`Stdin received: ${inputRaw.length} bytes`);

    let input: HookInput;
    try {
      input = JSON.parse(inputRaw);
      // Switch to session-specific crash log immediately
      setSessionId(input.session_id);
      crash(`Input parsed: session_id=${input.session_id}, cwd=${input.cwd}, event=${input.hook_event_name}`);
    } catch (parseErr) {
      crash("Failed to parse input JSON", parseErr);
      crash(`Raw input was: ${inputRaw.slice(0, 500)}`);
      throw parseErr;
    }

    // Use git repo root for state file to handle directory changes within repo
    const gitRoot = getGitRoot(input.cwd);
    stateFilePath = getStateFilePath(input.cwd);

    // Set session-specific file paths
    debugLogPath = `${sessionLogDir}/debug.log`;
    crash(`State file: ${stateFilePath}, Git root: ${gitRoot || "none"}, cwd: ${input.cwd}, logs: ${sessionLogDir}`);

    // Check for active loop
    if (!existsSync(stateFilePath)) {
      crash("No state file found, approving exit");
      output({ decision: "approve" });
      return;
    }
    crash("State file exists, reading...");

    // Parse state
    const stateContent = readFileSync(stateFilePath, "utf-8");
    const state = parseStateFile(stateContent);

    if (!state) {
      // Corrupt state file - clean up and exit
      crash("Failed to parse state file, cleaning up");
      cleanupStateFile(stateFilePath);
      output({ decision: "approve" });
      return;
    }

    if (!state.active) {
      // Loop was deactivated - clean up stale file and exit
      crash("Loop inactive, cleaning up stale state file");
      cleanupStateFile(stateFilePath);
      output({ decision: "approve" });
      return;
    }

    // Enable debug if set in state
    if (state.debug) {
      debugEnabled = true;
      debug(`[ralph-reviewed] Debug enabled via state file`);
    }

    // Get last assistant message
    const lastMessage = getLastAssistantMessage(input.transcript_path);

    // Debug logging
    debug(`[ralph-reviewed] Iteration: ${state.iteration}, Transcript: ${input.transcript_path}`);
    debug(`[ralph-reviewed] Last message (truncated): ${lastMessage?.slice(-200) || "null"}`);

    // Check for completion promise
    const promisePattern = new RegExp(
      `<promise>\\s*${state.completion_promise}\\s*</promise>`,
      "i"
    );
    const completionClaimed = lastMessage && promisePattern.test(lastMessage);
    debug(`[ralph-reviewed] Promise pattern: ${promisePattern}, Claimed: ${completionClaimed}`);

    if (!completionClaimed) {
      // Normal iteration - no completion claimed
      state.iteration++;

      // Check max iterations
      if (state.iteration >= state.max_iterations) {
        // Max iterations reached - allow exit
        debug(`[ralph-reviewed] Max iterations (${state.max_iterations}) reached, exiting loop`);
        cleanupStateFile(stateFilePath);
        output({ decision: "approve" });
        return;
      }

      // Update state file
      writeFileSync(stateFilePath, serializeState(state));

      // Build continuation prompt
      let prompt = `# Ralph Loop - Iteration ${state.iteration}/${state.max_iterations}\n\n`;

      if (state.pending_feedback) {
        prompt += `## Review Feedback from Previous Attempt\n\n${state.pending_feedback}\n\nAddress the above feedback.\n\n---\n\n`;
        // Clear pending feedback after injecting
        state.pending_feedback = null;
        writeFileSync(stateFilePath, serializeState(state));
      }

      prompt += state.original_prompt;
      prompt += `\n\nWhen complete, output: <promise>${state.completion_promise}</promise>`;

      output({ decision: "block", reason: prompt });
      return;
    }

    // Completion claimed - enter review gate
    debug(`[ralph-reviewed] Completion claimed! Entering review gate...`);

    if (!state.review_enabled) {
      // Reviews disabled - allow exit
      debug(`[ralph-reviewed] Reviews disabled, approving exit`);
      cleanupStateFile(stateFilePath);
      output({ decision: "approve" });
      return;
    }

    // Perform Codex review
    debug(`[ralph-reviewed] Calling Codex for review...`);

    const reviewResult = callCodexReview(
      state.original_prompt,
      state.review_history,
      state.review_count,
      state.max_review_cycles,
      input.cwd
    );

    debug(`[ralph-reviewed] Review result: approved=${reviewResult.approved}, issues=${reviewResult.issues.length}`);

    // Record this review in history
    const historyEntry: ReviewHistoryEntry = {
      cycle: state.review_count + 1,
      decision: reviewResult.approved ? "APPROVE" : "REJECT",
      issues: reviewResult.issues,
      resolved: reviewResult.resolved,
      notes: reviewResult.notes,
    };
    state.review_history.push(historyEntry);

    if (reviewResult.approved) {
      // Approved - allow exit
      debug(`[ralph-reviewed] Codex approved! Exiting loop.`);
      cleanupStateFile(stateFilePath);
      output({ decision: "approve" });
      return;
    }

    // Rejected - check review count
    state.review_count++;

    if (state.review_count >= state.max_review_cycles) {
      // Max reviews reached - allow exit with warning
      debug(
        `[ralph-reviewed] Max review cycles (${state.max_review_cycles}) reached. Issues: ${reviewResult.issues.length}`
      );
      cleanupStateFile(stateFilePath);
      output({ decision: "approve" });
      return;
    }

    // Format issues for Claude's feedback
    const issuesList = reviewResult.issues
      .map((issue) => `- [ISSUE-${issue.id}] ${issue.severity}: ${issue.description}`)
      .join("\n");

    const resolvedList = reviewResult.resolved.length > 0
      ? `\n\n**Resolved from previous cycle:**\n${reviewResult.resolved.map((r) => `- [ISSUE-${r.id}] ✓ ${r.verification}`).join("\n")}`
      : "";

    const notesSection = reviewResult.notes
      ? `\n\n**Reviewer notes:** ${reviewResult.notes}`
      : "";

    // Store formatted feedback for state
    state.pending_feedback = issuesList;
    state.iteration++; // Increment iteration for the feedback round
    writeFileSync(stateFilePath, serializeState(state));

    // Build prompt with structured feedback
    const feedbackPrompt = `# Ralph Loop - Iteration ${state.iteration}/${state.max_iterations}

## Review Feedback (Cycle ${state.review_count}/${state.max_review_cycles})

Your previous completion was reviewed and requires changes.
${resolvedList}

**Open Issues:**
${issuesList}
${notesSection}

Address ALL open issues above, then output <promise>${state.completion_promise}</promise> when truly complete.

---

${state.original_prompt}`;

    output({ decision: "block", reason: feedbackPrompt });
  } catch (e) {
    crash("main() caught exception", e);
    debug(`Stop hook error: ${e}`);
    // Clean up state file to avoid re-triggering loop
    if (stateFilePath) {
      try {
        unlinkSync(stateFilePath);
        crash(`Cleaned up state file on main() exception: ${stateFilePath}`);
      } catch { /* ignore cleanup errors */ }
    }
    // On error, allow exit to avoid trapping user
    output({ decision: "approve" });
  }
  crash("main() exiting normally");
}

crash("About to call main()");
main().catch((e) => {
  crash("main() promise rejected", e);
  // Clean up state file to avoid re-triggering loop
  if (stateFilePath) {
    try {
      unlinkSync(stateFilePath);
      crash(`Cleaned up state file on main() rejection: ${stateFilePath}`);
    } catch { /* ignore cleanup errors */ }
  }
  console.log(JSON.stringify({ decision: "approve" }));
  process.exit(1);
});
