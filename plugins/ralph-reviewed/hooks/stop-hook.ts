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
const HOOK_VERSION = "2026-01-05T20:30:00Z";
const HOOK_BUILD = "v1.8.0";

// --- User Config ---
// User preferences stored in ~/.claude/ralphs/config.json

interface CodexConfig {
  sandbox?: "read-only" | "workspace-write" | "danger-full-access";
  approval_policy?: "untrusted" | "on-failure" | "on-request" | "never";
  bypass_sandbox?: boolean;
  extra_args?: string[];
  timeout_seconds?: number; // Timeout for Codex CLI call (default: 1200 = 20 min)
}

interface UserConfig {
  codex?: CodexConfig;
}

const DEFAULT_CONFIG: UserConfig = {
  codex: {
    sandbox: "read-only",
    approval_policy: "never",
    bypass_sandbox: false,
    extra_args: [],
    timeout_seconds: 1200, // 20 minutes
  },
};

let userConfig: UserConfig = DEFAULT_CONFIG;

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

// --- Config Loading ---

function loadUserConfig(): UserConfig {
  const configPath = `${ralphsDir}/config.json`;
  try {
    if (existsSync(configPath)) {
      const content = readFileSync(configPath, "utf-8");
      const parsed = JSON.parse(content) as Partial<UserConfig>;
      // Merge with defaults
      return {
        codex: {
          ...DEFAULT_CONFIG.codex,
          ...parsed.codex,
        },
      };
    }
  } catch (e) {
    // Log but don't fail - use defaults
    try {
      appendFileSync(`${ralphsDir}/startup.log`, `[${new Date().toISOString()}] Failed to load config: ${e}\n`);
    } catch { /* ignore */ }
  }
  return DEFAULT_CONFIG;
}

// Load config at startup
userConfig = loadUserConfig();

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
 * Get the true root git repository, walking up through submodules.
 * If cwd is inside a submodule, returns the top-level parent repo.
 * Returns null if not in a git repo or git command fails.
 */
function getGitRoot(cwd: string): string | null {
  try {
    let dir = cwd;

    // Walk up through submodule hierarchy to find true root
    while (true) {
      // Check if we're in a submodule (has a parent superproject)
      const superResult = spawnSync("git", ["rev-parse", "--show-superproject-working-tree"], {
        cwd: dir,
        encoding: "utf-8",
        timeout: 5000,
      });

      const superproject = superResult.status === 0 ? superResult.stdout.trim() : "";

      if (!superproject) {
        // No parent superproject - this is the true root (or we're not in a submodule)
        const rootResult = spawnSync("git", ["rev-parse", "--show-toplevel"], {
          cwd: dir,
          encoding: "utf-8",
          timeout: 5000,
        });
        if (rootResult.status === 0 && rootResult.stdout) {
          return rootResult.stdout.trim();
        }
        return null;
      }

      // Move up to the parent repo and check again (handles nested submodules)
      dir = superproject;
    }
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

/**
 * Hook output schema for Claude Code stop hooks.
 * See: https://code.claude.com/docs/en/hooks.md
 *
 * - decision: "approve" allows exit, "block" prevents it
 * - reason: Message shown to Claude when blocking (ignored on approve)
 * - systemMessage: Optional message shown to user regardless of decision
 */
interface HookOutput {
  decision: "approve" | "block";
  reason?: string;
  systemMessage?: string;
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

/**
 * Normalize a review history entry to handle old schema versions.
 * Ensures all required fields exist with sensible defaults.
 */
function normalizeHistoryEntry(entry: unknown): ReviewHistoryEntry {
  if (typeof entry !== "object" || entry === null) {
    return {
      cycle: 0,
      decision: "REJECT",
      issues: [],
      resolved: [],
      notes: null,
    };
  }

  const obj = entry as Record<string, unknown>;

  // Normalize issues array
  const issues: ReviewIssue[] = [];
  if (Array.isArray(obj.issues)) {
    for (const issue of obj.issues) {
      if (typeof issue === "object" && issue !== null) {
        const i = issue as Record<string, unknown>;
        issues.push({
          id: typeof i.id === "number" ? i.id : 0,
          severity: (["critical", "major", "minor"].includes(String(i.severity))
            ? String(i.severity)
            : "minor") as "critical" | "major" | "minor",
          description: typeof i.description === "string" ? i.description : "",
        });
      }
    }
  }

  // Normalize resolved array
  const resolved: ResolvedIssue[] = [];
  if (Array.isArray(obj.resolved)) {
    for (const r of obj.resolved) {
      if (typeof r === "object" && r !== null) {
        const res = r as Record<string, unknown>;
        resolved.push({
          id: typeof res.id === "number" ? res.id : 0,
          verification: typeof res.verification === "string" ? res.verification : "",
        });
      }
    }
  }

  return {
    cycle: typeof obj.cycle === "number" ? obj.cycle : 0,
    decision: obj.decision === "APPROVE" ? "APPROVE" : "REJECT",
    issues,
    resolved,
    notes: typeof obj.notes === "string" ? obj.notes : null,
  };
}

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
          const parsed = JSON.parse(val);
          // Normalize each entry to handle old schema versions
          state.review_history = Array.isArray(parsed)
            ? parsed.map((entry: unknown) => normalizeHistoryEntry(entry))
            : [];
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
    max_review_cycles: state.max_review_cycles ?? state.max_iterations,
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
- Issue IDs must be unique across all cycles - continue numbering from previous reviews (don't restart at ISSUE-1)
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
    // Build args dynamically from user config
    const codexConfig = userConfig.codex || DEFAULT_CONFIG.codex!;
    const codexArgs: string[] = [
      "exec",
      "-",  // read prompt from stdin
    ];

    // Sandbox/approval settings (bypass_sandbox overrides both)
    if (codexConfig.bypass_sandbox) {
      codexArgs.push("--dangerously-bypass-approvals-and-sandbox");
    } else {
      codexArgs.push("--sandbox", codexConfig.sandbox || "read-only");
      // Use -c config override style (exec doesn't have -a flag)
      codexArgs.push("-c", `approval_policy="${codexConfig.approval_policy || "never"}"`);
    }

    // Output file (extra_args could override, but parsing would break)
    codexArgs.push("-o", outputFile);

    // Extra user-provided args (validated as string array, appended last)
    // Note: These can override earlier flags if user intends to customize behavior
    if (Array.isArray(codexConfig.extra_args)) {
      for (const arg of codexConfig.extra_args) {
        if (typeof arg === "string") {
          codexArgs.push(arg);
        }
      }
    }

    // Convert timeout from seconds to milliseconds
    const timeoutMs = (codexConfig.timeout_seconds || 1200) * 1000;

    crash(`Codex config: ${JSON.stringify(codexConfig)}`);
    crash(`Codex args: ${JSON.stringify(codexArgs)}`);
    crash(`Codex timeout: ${timeoutMs}ms (${codexConfig.timeout_seconds || 1200}s)`);

    // NOTE: This timeout must be less than plugin.json hook timeout (1800s)
    const result = spawnSync("codex", codexArgs, {
      cwd,
      encoding: "utf-8",
      timeout: timeoutMs,
      maxBuffer: 16 * 1024 * 1024,
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

    // Parse verdict from the END of output to avoid matching echoed examples
    // Find the last <review>...</review> tag in the output
    const reviewMatches = [...output.matchAll(/<review>\s*(APPROVE|REJECT)\s*<\/review>/gi)];
    const lastReviewMatch = reviewMatches.length > 0 ? reviewMatches[reviewMatches.length - 1] : null;
    const verdict = lastReviewMatch ? lastReviewMatch[1].toUpperCase() : null;

    crash(`Verdict parsing: found ${reviewMatches.length} review tags, verdict=${verdict}`);

    // Parse notes (present in both APPROVE and REJECT) - also use last match
    const notesMatches = [...output.matchAll(/<notes>([\s\S]*?)<\/notes>/gi)];
    const lastNotesMatch = notesMatches.length > 0 ? notesMatches[notesMatches.length - 1] : null;
    const notes = lastNotesMatch ? lastNotesMatch[1].trim() : null;

    // Parse response based on extracted verdict
    if (verdict === "APPROVE") {
      crash("Codex approved");
      return { approved: true, issues: [], resolved: [], notes };
    }

    if (verdict === "REJECT") {
      // Parse issues - use last <issues> block
      const issues: ReviewIssue[] = [];
      const issuesMatches = [...output.matchAll(/<issues>([\s\S]*?)<\/issues>/gi)];
      const lastIssuesMatch = issuesMatches.length > 0 ? issuesMatches[issuesMatches.length - 1] : null;
      if (lastIssuesMatch) {
        // Use [\s\S]+? for multi-line descriptions, terminated by next issue or end
        const issuePattern = /\[ISSUE-(\d+)\]\s*(critical|major|minor):\s*([\s\S]+?)(?=\[ISSUE-|\s*$)/gi;
        let match;
        while ((match = issuePattern.exec(lastIssuesMatch[1])) !== null) {
          issues.push({
            id: parseInt(match[1], 10),
            severity: match[2].toLowerCase() as "critical" | "major" | "minor",
            description: match[3].trim(),
          });
        }
      }

      // Parse resolved - use last <resolved> block
      const resolved: ResolvedIssue[] = [];
      const resolvedMatches = [...output.matchAll(/<resolved>([\s\S]*?)<\/resolved>/gi)];
      const lastResolvedMatch = resolvedMatches.length > 0 ? resolvedMatches[resolvedMatches.length - 1] : null;
      if (lastResolvedMatch) {
        // Use [\s\S]+? for multi-line verifications
        const resolvedPattern = /\[ISSUE-(\d+)\]\s*([\s\S]+?)(?=\[ISSUE-|\s*$)/gi;
        let match;
        while ((match = resolvedPattern.exec(lastResolvedMatch[1])) !== null) {
          resolved.push({
            id: parseInt(match[1], 10),
            verification: match[2].trim(),
          });
        }
      }

      // Handle REJECT with no parsed issues - auto-approve with warning to avoid deadlock
      if (issues.length === 0) {
        crash("REJECT verdict but no issues parsed - auto-approving with warning to avoid deadlock");
        debug("[ralph-reviewed] WARNING: Codex rejected but no issues could be parsed. Auto-approving to avoid deadlock.");
        return { approved: true, issues: [], resolved: [], notes: notes ? `[AUTO-APPROVED: REJECT with unparseable issues] ${notes}` : "[AUTO-APPROVED: REJECT with unparseable issues]" };
      }

      crash(`Codex rejected with ${issues.length} issues, ${resolved.length} resolved`);
      return { approved: false, issues, resolved, notes };
    }

    // Unclear response - default to approve
    crash("Unclear Codex response (no APPROVE/REJECT verdict found), approving by default");
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

    // Check for BLOCKED signal (special termination without review)
    const blockedPattern = /<promise>\s*BLOCKED\s*<\/promise>/i;
    const blockedClaimed = lastMessage && blockedPattern.test(lastMessage);
    debug(`[ralph-reviewed] Blocked pattern check: ${blockedClaimed}`);

    if (blockedClaimed) {
      // BLOCKED is a special termination signal - exit without Codex review
      crash("BLOCKED claimed - terminating loop without review");
      debug(`[ralph-reviewed] BLOCKED signal received. Terminating loop without review.`);
      cleanupStateFile(stateFilePath);
      output({
        decision: "approve",
        systemMessage: `# Ralph Loop: BLOCKED

**Iteration:** ${state.iteration}/${state.max_iterations}

Task reported as blocked. Loop terminated without review.`
      });
      return;
    }

    if (!completionClaimed) {
      // Normal iteration - no completion claimed
      state.iteration++;

      // Check max iterations
      if (state.iteration >= state.max_iterations) {
        // Max iterations reached - allow exit
        debug(`[ralph-reviewed] Max iterations (${state.max_iterations}) reached, exiting loop`);
        cleanupStateFile(stateFilePath);
        output({
          decision: "approve",
          systemMessage: `# Ralph Loop: Max Iterations Reached

**Iteration:** ${state.iteration}/${state.max_iterations}

Loop ended without completion claim. Review the work and consider restarting if needed.`
        });
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

    // Require git repository - Codex needs a trusted directory
    if (!gitRoot) {
      crash("Not in a git repository - BLOCKING (Codex requires git repo)");
      output({
        decision: "block",
        reason: `# Review Gate Error: Not a Git Repository

Codex requires a git repository to run. The current directory is not inside a git repo.

**Current directory:** \`${input.cwd}\`

**To fix:** Initialize a git repository with \`git init\`, or move the project into an existing git repo.

**To escape this loop:** Run \`/ralph-reviewed:cancel-ralph\` to remove the loop, then exit normally.`
      });
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

      // Build approval summary for user visibility
      const notesLine = reviewResult.notes ? `\n**Reviewer notes:** ${reviewResult.notes}` : "";
      const approvalMessage = `# Ralph Loop: Codex APPROVED

**Iteration:** ${state.iteration}/${state.max_iterations}
**Review cycle:** ${state.review_count + 1}/${state.max_review_cycles}${notesLine}

The review gate has been cleared. Task completed successfully.`;

      output({ decision: "approve", systemMessage: approvalMessage });
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

      // Build summary with remaining issues
      const remainingIssues = reviewResult.issues.length > 0
        ? reviewResult.issues.map(i => `- [ISSUE-${i.id}] ${i.severity}: ${i.description}`).join("\n")
        : "(no issues parsed)";

      output({
        decision: "approve",
        systemMessage: `# Ralph Loop: Max Review Cycles Reached

**Iteration:** ${state.iteration}/${state.max_iterations}
**Review cycle:** ${state.review_count}/${state.max_review_cycles}

**Unresolved issues:**
${remainingIssues}

Loop ended without Codex approval. Review remaining issues manually.`
      });
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
