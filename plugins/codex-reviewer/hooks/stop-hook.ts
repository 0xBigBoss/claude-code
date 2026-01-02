#!/usr/bin/env bun
/**
 * Stop hook for Codex Reviewer plugin.
 *
 * Intercepts exit attempts when a review gate is active.
 * Calls Codex CLI to review the work before allowing exit.
 *
 * Flow:
 * 1. Check for active review state file (at git repo root)
 * 2. If no state file, allow exit
 * 3. Call Codex CLI with review prompt
 * 4. If APPROVE: clean up state, allow exit
 * 5. If REJECT: inject feedback, block exit, continue
 */

import { readFileSync, writeFileSync, existsSync, appendFileSync, unlinkSync, mkdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

// --- Version ---
const HOOK_VERSION = "2026-01-02T20:30:00Z";
const HOOK_BUILD = "v1.4.0";

// --- Timeout Constants ---
// Must align with plugin.json hook timeout
const HOOK_TIMEOUT_SECONDS = 1800;
const BUFFER_SECONDS = 120;
const MIN_CODEX_TIMEOUT_SECONDS = 60;
const MAX_CODEX_TIMEOUT_SECONDS = HOOK_TIMEOUT_SECONDS - BUFFER_SECONDS; // 1680s

// --- User Config ---
// User preferences stored in ~/.claude/codex/config.json

interface CodexConfig {
  sandbox?: "read-only" | "workspace-write" | "danger-full-access";
  approval_policy?: "untrusted" | "on-failure" | "on-request" | "never";
  bypass_sandbox?: boolean;
  extra_args?: string[];
  timeout_seconds?: number;
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
    timeout_seconds: 1200,
  },
};

let userConfig: UserConfig = DEFAULT_CONFIG;

// --- Logging ---
const codexDir = `${homedir()}/.claude/codex`;
let sessionId = "unknown";
let sessionLogDir = codexDir;
let crashLogPath = `${codexDir}/startup.log`;
let debugLogPath = `${codexDir}/debug.log`;
let debugEnabled = process.env.CODEX_REVIEWER_DEBUG === "1";
let stateFilePath: string | null = null;

// Ensure base directory exists
try {
  mkdirSync(codexDir, { recursive: true });
} catch { /* ignore */ }

// --- Config Loading ---

function loadUserConfig(): UserConfig {
  const configPath = `${codexDir}/config.json`;
  try {
    if (existsSync(configPath)) {
      const content = readFileSync(configPath, "utf-8");
      const parsed = JSON.parse(content) as Partial<UserConfig>;
      return {
        codex: {
          ...DEFAULT_CONFIG.codex,
          ...parsed.codex,
        },
      };
    }
  } catch (e) {
    try {
      appendFileSync(`${codexDir}/startup.log`, `[${new Date().toISOString()}] Failed to load config: ${e}\n`);
    } catch { /* ignore */ }
  }
  return DEFAULT_CONFIG;
}

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
    console.error(line);
  }
}

function setSessionId(id: string) {
  sessionId = id;
  sessionLogDir = `${codexDir}/${id}`;
  try {
    mkdirSync(sessionLogDir, { recursive: true });
  } catch { /* ignore */ }
  crashLogPath = `${sessionLogDir}/crash.log`;
  debugLogPath = `${sessionLogDir}/debug.log`;
}

function debug(msg: string) {
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] [${sessionId}] ${msg}\n`;
  try {
    appendFileSync(crashLogPath, `[DEBUG] ${line}`);
  } catch { /* ignore */ }
  if (!debugEnabled) return;
  appendFileSync(debugLogPath, line);
}

crash(`Hook starting - version: ${HOOK_BUILD} (${HOOK_VERSION}), PID: ${process.pid}`);

// Global error handlers - FAIL CLOSED (strict gate)
// Do NOT clean up state file - let user explicitly cancel
process.on("uncaughtException", (err) => {
  crash("Uncaught exception", err);
  const errorMsg = err instanceof Error ? err.message : String(err);
  console.log(JSON.stringify({
    decision: "block",
    reason: `# Review Gate Error: Uncaught Exception

The review gate encountered an unexpected error and cannot proceed.

**Error:** ${errorMsg}

**To escape this gate:** Run \`/codex-reviewer:cancel\` to remove the review gate, then exit normally.

**To retry:** Simply try to exit again. The hook will re-run.

Check logs at \`~/.claude/codex/${sessionId}/crash.log\` for details.`
  }));
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  crash("Unhandled rejection", reason);
  const errorMsg = reason instanceof Error ? reason.message : String(reason);
  console.log(JSON.stringify({
    decision: "block",
    reason: `# Review Gate Error: Unhandled Rejection

The review gate encountered an unexpected error and cannot proceed.

**Error:** ${errorMsg}

**To escape this gate:** Run \`/codex-reviewer:cancel\` to remove the review gate, then exit normally.

**To retry:** Simply try to exit again. The hook will re-run.

Check logs at \`~/.claude/codex/${sessionId}/crash.log\` for details.`
  }));
  process.exit(1);
});

// --- Git Utilities ---

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

function getStateFilePath(cwd: string): string {
  const gitRoot = getGitRoot(cwd);
  const baseDir = gitRoot || cwd;
  return join(baseDir, ".claude", "codex-review.local.md");
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

interface ReviewState {
  active: boolean;
  task_description: string;
  files_changed: string[];
  review_count: number;
  max_review_cycles: number;
  review_history: ReviewHistoryEntry[];
  timestamp: string;
  debug: boolean;
}

// --- State File Parsing ---

function normalizeHistoryEntry(entry: unknown): ReviewHistoryEntry {
  if (typeof entry !== "object" || entry === null) {
    return { cycle: 0, decision: "REJECT", issues: [], resolved: [], notes: null };
  }

  const obj = entry as Record<string, unknown>;
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

function parseStateFile(content: string): ReviewState | null {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return null;

  const yaml = match[1];
  const state: Partial<ReviewState> = {};

  const lines = yaml.split("\n");
  let inDescription = false;
  let descriptionLines: string[] = [];

  for (const line of lines) {
    if (inDescription) {
      if (line.startsWith("  ")) {
        descriptionLines.push(line.slice(2));
        continue;
      } else {
        inDescription = false;
        state.task_description = descriptionLines.join("\n").trim();
      }
    }

    if (line.startsWith("active:")) {
      state.active = line.includes("true");
    } else if (line.startsWith("task_description:")) {
      const inline = line.split(":").slice(1).join(":").trim();
      if (inline === "|") {
        inDescription = true;
        descriptionLines = [];
      } else {
        state.task_description = inline.replace(/^["']|["']$/g, "");
      }
    } else if (line.startsWith("files_changed:")) {
      const val = line.split(":").slice(1).join(":").trim();
      if (val && val !== "[]") {
        try {
          state.files_changed = JSON.parse(val);
        } catch {
          state.files_changed = [];
        }
      } else {
        state.files_changed = [];
      }
    } else if (line.startsWith("review_count:")) {
      state.review_count = parseInt(line.split(":")[1].trim(), 10);
    } else if (line.startsWith("max_review_cycles:")) {
      state.max_review_cycles = parseInt(line.split(":")[1].trim(), 10);
    } else if (line.startsWith("timestamp:")) {
      state.timestamp = line.split(":").slice(1).join(":").trim().replace(/^["']|["']$/g, "");
    } else if (line.startsWith("debug:")) {
      state.debug = line.includes("true");
    } else if (line.startsWith("review_history:")) {
      const val = line.split(":").slice(1).join(":").trim();
      if (val && val !== "[]") {
        try {
          const parsed = JSON.parse(val);
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

  if (state.active === undefined || !state.task_description) {
    return null;
  }

  return {
    active: state.active,
    task_description: state.task_description,
    files_changed: state.files_changed ?? [],
    review_count: state.review_count ?? 0,
    max_review_cycles: state.max_review_cycles ?? 5,
    review_history: state.review_history ?? [],
    timestamp: state.timestamp || new Date().toISOString(),
    debug: state.debug ?? false,
  };
}

function serializeState(state: ReviewState): string {
  const descriptionIndented = state.task_description
    .split("\n")
    .map((line) => `  ${line}`)
    .join("\n");

  return `---
active: ${state.active}
task_description: |
${descriptionIndented}
files_changed: ${JSON.stringify(state.files_changed)}
review_count: ${state.review_count}
max_review_cycles: ${state.max_review_cycles}
review_history: ${JSON.stringify(state.review_history)}
timestamp: "${state.timestamp}"
debug: ${state.debug}
---

# Codex Review Gate

This file tracks an active Codex review gate.

Do not edit this file manually. Use \`/codex-reviewer:cancel\` to abort.
`;
}

function cleanupStateFile(path: string): void {
  try {
    if (existsSync(path)) {
      unlinkSync(path);
      crash(`State file deleted: ${path}`);
      debug(`[codex-reviewer] Cleaned up state file: ${path}`);
    }
  } catch (e) {
    crash(`Failed to delete state file: ${path}`, e);
  }
}

// --- Codex Review ---

interface ReviewResult {
  status: "approved" | "rejected" | "error";
  issues: ReviewIssue[];
  resolved: ResolvedIssue[];
  notes: string | null;
  errorMessage?: string;  // Present when status === "error"
}

function buildReviewHistorySection(history: ReviewHistoryEntry[]): string {
  if (history.length === 0) return "";

  const sections = history.map((entry) => {
    const parts: string[] = [`### Cycle ${entry.cycle}: ${entry.decision}`];

    if (entry.resolved.length > 0) {
      parts.push(`**Resolved:**\n${entry.resolved.map(r =>
        `  - [ISSUE-${r.id}] ✓ ${r.verification}`
      ).join("\n")}`);
    }

    if (entry.issues.length > 0) {
      parts.push(`**Issues:**\n${entry.issues.map(i =>
        `  - [ISSUE-${i.id}] ${i.severity}: ${i.description}`
      ).join("\n")}`);
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
  taskDescription: string,
  filesChanged: string[],
  reviewHistory: ReviewHistoryEntry[],
  reviewCount: number,
  maxReviews: number,
  cwd: string
): ReviewResult {
  crash(`callCodexReview() started - reviewCount=${reviewCount}, cwd=${cwd}`);

  const whichResult = spawnSync("which", ["codex"], { encoding: "utf-8" });
  if (whichResult.status !== 0) {
    crash("Codex CLI not found - BLOCKING (strict gate)");
    debug("Codex CLI not found - BLOCKING");
    return {
      status: "error",
      issues: [],
      resolved: [],
      notes: null,
      errorMessage: "Codex CLI not found in PATH. Install Codex or run `/codex-reviewer:cancel` to escape.",
    };
  }
  crash(`Codex found at: ${whichResult.stdout?.trim()}`);

  const historySection = buildReviewHistorySection(reviewHistory);
  const filesSection = filesChanged.length > 0
    ? `**Files Changed:** ${filesChanged.join(", ")}\n`
    : "";

  const reviewPrompt = `# Code Review

Review work completed by Claude. Claude claims the task is complete and ready for review.

## Task
${taskDescription}

## Git Context
${filesSection}
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

  const uniqueId = Date.now();
  const outputFile = `/tmp/codex-review-output-${uniqueId}.txt`;

  crash(`Calling Codex with output file: ${outputFile}`);
  crash(`Review prompt length: ${reviewPrompt.length} chars`);

  try {
    const codexConfig = userConfig.codex || DEFAULT_CONFIG.codex!;
    const codexArgs: string[] = ["exec", "-"];

    if (codexConfig.bypass_sandbox) {
      codexArgs.push("--dangerously-bypass-approvals-and-sandbox");
    } else {
      codexArgs.push("--sandbox", codexConfig.sandbox || "read-only");
      codexArgs.push("-c", `approval_policy="${codexConfig.approval_policy || "never"}"`);
    }

    codexArgs.push("-o", outputFile);

    // Filter out -o/--output from extra_args to prevent breaking output parsing
    if (Array.isArray(codexConfig.extra_args)) {
      for (const arg of codexConfig.extra_args) {
        if (typeof arg === "string" && arg !== "-o" && !arg.startsWith("--output")) {
          codexArgs.push(arg);
        }
      }
    }

    // Clamp timeout to safe range: [MIN_CODEX_TIMEOUT_SECONDS, MAX_CODEX_TIMEOUT_SECONDS]
    // This ensures we finish before the hook timeout (with BUFFER_SECONDS margin)
    const requestedTimeout = codexConfig.timeout_seconds ?? 1200;
    let effectiveTimeout = Math.min(requestedTimeout, MAX_CODEX_TIMEOUT_SECONDS);
    effectiveTimeout = Math.max(effectiveTimeout, MIN_CODEX_TIMEOUT_SECONDS);
    if (requestedTimeout < MIN_CODEX_TIMEOUT_SECONDS) {
      crash(`WARNING: Clamping timeout from ${requestedTimeout}s to min ${MIN_CODEX_TIMEOUT_SECONDS}s`);
    }
    if (requestedTimeout > MAX_CODEX_TIMEOUT_SECONDS) {
      crash(`WARNING: Clamping timeout from ${requestedTimeout}s to max ${MAX_CODEX_TIMEOUT_SECONDS}s (hook timeout ${HOOK_TIMEOUT_SECONDS}s - buffer ${BUFFER_SECONDS}s)`);
    }
    const timeoutMs = effectiveTimeout * 1000;

    crash(`Codex config: ${JSON.stringify(codexConfig)}`);
    crash(`Codex args: ${JSON.stringify(codexArgs)}`);
    crash(`Codex timeout: ${timeoutMs}ms (effective=${effectiveTimeout}s, requested=${requestedTimeout}s, max=${MAX_CODEX_TIMEOUT_SECONDS}s)`);

    const result = spawnSync("codex", codexArgs, {
      cwd,
      encoding: "utf-8",
      timeout: timeoutMs,
      maxBuffer: 16 * 1024 * 1024,
      input: reviewPrompt,
    });

    crash(`Codex returned - status: ${result.status}, signal: ${result.signal}, error: ${result.error}`);
    if (result.stderr) {
      crash(`Codex stderr: ${result.stderr.slice(0, 500)}`);
    }
    debug(`[codex-reviewer] Codex exit code: ${result.status}`);

    // STRICT GATE: Any execution error blocks before parsing output
    if (result.error) {
      const errorMsg = result.error instanceof Error ? result.error.message : String(result.error);
      crash(`Codex spawn error - BLOCKING (strict gate): ${errorMsg}`);
      return {
        status: "error",
        issues: [],
        resolved: [],
        notes: null,
        errorMessage: `Codex spawn error: ${errorMsg}. This may be a timeout or process error. Retry or run \`/codex-reviewer:cancel\` to escape.`,
      };
    }

    if (result.signal) {
      crash(`Codex killed by signal ${result.signal} - BLOCKING (strict gate)`);
      return {
        status: "error",
        issues: [],
        resolved: [],
        notes: null,
        errorMessage: `Codex was killed by signal ${result.signal}. This may indicate a timeout or resource issue. Retry or run \`/codex-reviewer:cancel\` to escape.`,
      };
    }

    if (result.status !== 0 && result.status !== null) {
      crash(`Codex exited with non-zero status ${result.status} - BLOCKING (strict gate)`);
      return {
        status: "error",
        issues: [],
        resolved: [],
        notes: null,
        errorMessage: `Codex exited with status ${result.status}. Check Codex logs for details. Retry or run \`/codex-reviewer:cancel\` to escape.`,
      };
    }

    let output = "";
    if (existsSync(outputFile)) {
      output = readFileSync(outputFile, "utf-8");
      crash(`Codex output file contents: ${output.slice(0, 500)}`);
      debug(`[codex-reviewer] Codex output: ${output.slice(0, 500)}`);
    } else {
      crash("No Codex output file created - BLOCKING (strict gate)");
      debug(`[codex-reviewer] No output file created`);
      return {
        status: "error",
        issues: [],
        resolved: [],
        notes: null,
        errorMessage: "Codex completed but no output file was created. This may indicate a Codex configuration issue. Retry or run `/codex-reviewer:cancel` to escape.",
      };
    }

    // Parse from END to avoid matching prompt examples
    const reviewMatches = [...output.matchAll(/<review>\s*(APPROVE|REJECT)\s*<\/review>/gi)];
    const lastReviewMatch = reviewMatches.length > 0 ? reviewMatches[reviewMatches.length - 1] : null;
    const verdict = lastReviewMatch ? lastReviewMatch[1].toUpperCase() : null;

    crash(`Verdict parsing: found ${reviewMatches.length} review tags, verdict=${verdict}`);

    const notesMatches = [...output.matchAll(/<notes>([\s\S]*?)<\/notes>/gi)];
    const lastNotesMatch = notesMatches.length > 0 ? notesMatches[notesMatches.length - 1] : null;
    const notes = lastNotesMatch ? lastNotesMatch[1].trim() : null;

    if (verdict === "APPROVE") {
      crash("Codex approved");
      return { status: "approved", issues: [], resolved: [], notes };
    }

    if (verdict === "REJECT") {
      const issues: ReviewIssue[] = [];
      const issuesMatches = [...output.matchAll(/<issues>([\s\S]*?)<\/issues>/gi)];
      const lastIssuesMatch = issuesMatches.length > 0 ? issuesMatches[issuesMatches.length - 1] : null;
      if (lastIssuesMatch) {
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

      const resolved: ResolvedIssue[] = [];
      const resolvedMatches = [...output.matchAll(/<resolved>([\s\S]*?)<\/resolved>/gi)];
      const lastResolvedMatch = resolvedMatches.length > 0 ? resolvedMatches[resolvedMatches.length - 1] : null;
      if (lastResolvedMatch) {
        const resolvedPattern = /\[ISSUE-(\d+)\]\s*([\s\S]+?)(?=\[ISSUE-|\s*$)/gi;
        let match;
        while ((match = resolvedPattern.exec(lastResolvedMatch[1])) !== null) {
          resolved.push({
            id: parseInt(match[1], 10),
            verification: match[2].trim(),
          });
        }
      }

      // Handle REJECT with no parsed issues - BLOCK with error (strict gate)
      if (issues.length === 0) {
        crash("REJECT verdict but no issues parsed - BLOCKING (strict gate)");
        debug("[codex-reviewer] ERROR: Codex rejected but no issues could be parsed.");
        return {
          status: "error",
          issues: [],
          resolved: [],
          notes,
          errorMessage: "Codex returned REJECT but no issues could be parsed from the output. This may indicate a format drift or truncated response. Retry or run `/codex-reviewer:cancel` to escape.",
        };
      }

      crash(`Codex rejected with ${issues.length} issues, ${resolved.length} resolved`);
      return { status: "rejected", issues, resolved, notes };
    }

    crash("Unclear Codex response (no APPROVE/REJECT verdict found) - BLOCKING (strict gate)");
    debug("Unclear Codex response - BLOCKING");
    return {
      status: "error",
      issues: [],
      resolved: [],
      notes: null,
      errorMessage: "Codex response did not contain a clear APPROVE or REJECT verdict. The output may be malformed or truncated. Retry or run `/codex-reviewer:cancel` to escape.",
    };
  } catch (e) {
    crash("Codex review call threw exception", e);
    debug(`Codex review failed: ${e} - BLOCKING`);
    const errorMsg = e instanceof Error ? e.message : String(e);
    return {
      status: "error",
      issues: [],
      resolved: [],
      notes: null,
      errorMessage: `Codex review threw an exception: ${errorMsg}. Retry or run \`/codex-reviewer:cancel\` to escape.`,
    };
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
      setSessionId(input.session_id);
      crash(`Input parsed: session_id=${input.session_id}, cwd=${input.cwd}, event=${input.hook_event_name}`);
    } catch (parseErr) {
      crash("Failed to parse input JSON", parseErr);
      crash(`Raw input was: ${inputRaw.slice(0, 500)}`);
      throw parseErr;
    }

    const gitRoot = getGitRoot(input.cwd);
    stateFilePath = getStateFilePath(input.cwd);
    crash(`State file: ${stateFilePath}, Git root: ${gitRoot || "none"}, cwd: ${input.cwd}`);

    // Check for active review gate
    if (!existsSync(stateFilePath)) {
      crash("No state file found, approving exit");
      output({ decision: "approve" });
      return;
    }
    crash("State file exists, reading...");

    const stateContent = readFileSync(stateFilePath, "utf-8");
    const state = parseStateFile(stateContent);

    if (!state) {
      crash("Failed to parse state file - BLOCKING (strict gate)");
      // Do NOT clean up - let user inspect/fix or explicitly cancel
      output({
        decision: "block",
        reason: `# Review Gate Error: Malformed State File

The review gate state file exists but could not be parsed. This may indicate file corruption or manual editing.

**State file location:** \`${stateFilePath}\`

**To escape this gate:** Run \`/codex-reviewer:cancel\` to remove the review gate, then exit normally.

**To fix:** Inspect the state file for syntax errors, or delete it manually.`
      });
      return;
    }

    if (!state.active) {
      crash("Review gate inactive, cleaning up stale state file");
      cleanupStateFile(stateFilePath);
      output({ decision: "approve" });
      return;
    }

    if (state.debug) {
      debugEnabled = true;
      debug(`[codex-reviewer] Debug enabled via state file`);
    }

    // Early guard: if max cycles already reached, block without calling Codex
    if (state.review_count >= state.max_review_cycles) {
      debug(`[codex-reviewer] Max review cycles already reached (${state.review_count}/${state.max_review_cycles}) - BLOCKING without calling Codex`);
      // Get last review's issues from history if available
      const lastReview = state.review_history.length > 0
        ? state.review_history[state.review_history.length - 1]
        : null;
      const remainingIssues = lastReview?.issues
        .map((i) => `- [ISSUE-${i.id}] ${i.severity}: ${i.description}`)
        .join("\n") || "- (no issues recorded)";
      output({
        decision: "block",
        reason: `# Review Gate: Max Cycles Already Reached

You have already reached the maximum number of review cycles (${state.max_review_cycles}) without Codex approval.

**Last Review Issues:**
${remainingIssues}

**To escape this gate:** Run \`/codex-reviewer:cancel\` to remove the review gate, then exit normally.

This is a strict gate - exit requires either Codex approval or explicit cancellation.`
      });
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

**To escape this gate:** Run \`/codex-reviewer:cancel\` to remove the review gate, then exit normally.`
      });
      return;
    }

    debug(`[codex-reviewer] Review gate active, calling Codex...`);

    const reviewResult = callCodexReview(
      state.task_description,
      state.files_changed,
      state.review_history,
      state.review_count,
      state.max_review_cycles,
      input.cwd
    );

    debug(`[codex-reviewer] Review result: status=${reviewResult.status}, issues=${reviewResult.issues.length}`);

    // Handle error status - block with explicit error message (strict gate)
    if (reviewResult.status === "error") {
      debug(`[codex-reviewer] Review error: ${reviewResult.errorMessage}`);
      output({
        decision: "block",
        reason: `# Review Gate Error

${reviewResult.errorMessage}

**To escape this gate:** Run \`/codex-reviewer:cancel\` to remove the review gate, then exit normally.

**To retry:** Simply try to exit again. The hook will re-run the Codex review.`
      });
      return;
    }

    // Record this review in history (only for approved/rejected, not errors)
    const historyEntry: ReviewHistoryEntry = {
      cycle: state.review_count + 1,
      decision: reviewResult.status === "approved" ? "APPROVE" : "REJECT",
      issues: reviewResult.issues,
      resolved: reviewResult.resolved,
      notes: reviewResult.notes,
    };
    state.review_history.push(historyEntry);

    if (reviewResult.status === "approved") {
      debug(`[codex-reviewer] Codex approved! Exiting.`);
      cleanupStateFile(stateFilePath);

      // Build approval summary for user visibility
      const notesLine = reviewResult.notes ? `\n**Reviewer notes:** ${reviewResult.notes}` : "";
      const approvalMessage = `# Codex Review: APPROVED

**Review cycle:** ${state.review_count + 1}/${state.max_review_cycles}
**Files reviewed:** ${state.files_changed.length > 0 ? state.files_changed.join(", ") : "(from git diff)"}${notesLine}

The review gate has been cleared. You may now exit or continue with next steps.`;

      output({ decision: "approve", systemMessage: approvalMessage });
      return;
    }

    // Rejected - increment review count
    state.review_count++;

    // Persist state BEFORE checking max cycles (ensures count is saved)
    writeFileSync(stateFilePath, serializeState(state));

    if (state.review_count >= state.max_review_cycles) {
      debug(`[codex-reviewer] Max review cycles (${state.max_review_cycles}) reached - BLOCKING (strict gate)`);
      // STRICT GATE: Do NOT auto-approve after max cycles
      // User must explicitly cancel to escape
      const remainingIssues = reviewResult.issues
        .map((i) => `- [ISSUE-${i.id}] ${i.severity}: ${i.description}`)
        .join("\n");
      output({
        decision: "block",
        reason: `# Review Gate: Max Cycles Reached

You have reached the maximum number of review cycles (${state.max_review_cycles}) without Codex approval.

**Unresolved Issues:**
${remainingIssues || "- (none parsed from last review)"}

**To escape this gate:** Run \`/codex-reviewer:cancel\` to remove the review gate, then exit normally.

This is a strict gate - exit requires either Codex approval or explicit cancellation.`
      });
      return;
    }

    // Format feedback for Claude
    const issuesList = reviewResult.issues
      .map((issue) => `- [ISSUE-${issue.id}] ${issue.severity}: ${issue.description}`)
      .join("\n");

    const resolvedList = reviewResult.resolved.length > 0
      ? `\n\n**Resolved from previous cycle:**\n${reviewResult.resolved.map((r) => `- [ISSUE-${r.id}] ✓ ${r.verification}`).join("\n")}`
      : "";

    const notesSection = reviewResult.notes
      ? `\n\n**Reviewer notes:** ${reviewResult.notes}`
      : "";

    const feedbackPrompt = `# Codex Review Feedback (Cycle ${state.review_count}/${state.max_review_cycles})

Your work was reviewed and requires changes.
${resolvedList}

**Open Issues:**
${issuesList}
${notesSection}

Address ALL open issues above. When done, simply exit - the review gate is still active and will trigger the next review automatically.

**Do NOT call \`/codex-reviewer:review\` again** - that would reset the review cycle. Just exit when ready.

---

Original task: ${state.task_description}`;

    output({ decision: "block", reason: feedbackPrompt });
  } catch (e) {
    crash("main() caught exception", e);
    debug(`Stop hook error: ${e}`);
    // FAIL CLOSED - do NOT clean up state file, do NOT auto-approve
    const errorMsg = e instanceof Error ? e.message : String(e);
    output({
      decision: "block",
      reason: `# Review Gate Error: Hook Exception

The review gate encountered an unexpected error and cannot proceed.

**Error:** ${errorMsg}

**To escape this gate:** Run \`/codex-reviewer:cancel\` to remove the review gate, then exit normally.

**To retry:** Simply try to exit again. The hook will re-run.

Check logs at \`~/.claude/codex/${sessionId}/crash.log\` for details.`
    });
  }
  crash("main() exiting normally");
}

crash("About to call main()");
main().catch((e) => {
  crash("main() promise rejected", e);
  // FAIL CLOSED - do NOT clean up state file, do NOT auto-approve
  const errorMsg = e instanceof Error ? e.message : String(e);
  console.log(JSON.stringify({
    decision: "block",
    reason: `# Review Gate Error: Unhandled Promise Rejection

The review gate encountered an unexpected error and cannot proceed.

**Error:** ${errorMsg}

**To escape this gate:** Run \`/codex-reviewer:cancel\` to remove the review gate, then exit normally.

**To retry:** Simply try to exit again. The hook will re-run.

Check logs at \`~/.claude/codex/${sessionId}/crash.log\` for details.`
  }));
  process.exit(1);
});
