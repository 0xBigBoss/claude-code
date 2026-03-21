#!/usr/bin/env bun
/**
 * Stop hook for Ralph Reviewed plugin.
 *
 * Intercepts exit attempts during an active Ralph loop.
 * When completion is claimed, triggers Codex review gate.
 *
 * NOTE: Ralph loops only work within git repositories. The state file is stored
 * at the git repo root (.rl/state.json) to ensure it survives directory changes
 * within the repo. Outside of git repos, falls back to cwd but directory changes
 * will break the loop.
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
const HOOK_VERSION = "2026-03-21T00:00:00Z";
const HOOK_BUILD = "v2.0.0";
const STDIN_TIMEOUT_MS = 2000;

// --- User Config ---
// User preferences stored in ~/.claude/codex.json
// Legacy fallback: ~/.claude/ralphs/config.json

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
  // Standard location: ~/.claude/codex.json
  const standardPath = `${homedir()}/.claude/codex.json`;
  // Legacy fallback: ~/.claude/ralphs/config.json
  const legacyPath = `${ralphsDir}/config.json`;

  for (const configPath of [standardPath, legacyPath]) {
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
        appendFileSync(`${ralphsDir}/startup.log`, `[${new Date().toISOString()}] Failed to load config from ${configPath}: ${e}\n`);
      } catch { /* ignore */ }
    }
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
  // Output empty JSON to avoid trapping user
  console.log(JSON.stringify({}));
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
  // Output empty JSON to avoid trapping user
  console.log(JSON.stringify({}));
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
  return join(baseDir, ".rl", "state.json");
}

// --- Types ---

interface HookInput {
  session_id: string;
  transcript_path?: string;
  cwd?: string;
  permission_mode?: string;
  hook_event_name: "Stop";
  stop_hook_active?: boolean;
}

/**
 * Hook output schema for Claude Code stop hooks.
 * See: https://code.claude.com/docs/en/hooks.md
 *
 * - decision: "block" prevents stopping (omit to allow)
 * - reason: Message shown to Claude when blocking
 * - systemMessage: Optional message shown to user regardless of decision
 */
interface HookOutput {
  decision?: "block";
  reason?: string;
  systemMessage?: string;
  continue?: boolean;
  stopReason?: string;
}


interface LoopState {
  active: boolean;
  iteration: number;
  max_iterations: number;
  timestamp: string;
  review_enabled: boolean;
  review_count: number;
  max_review_cycles: number;
  debug: boolean;
}


// --- State File Parsing ---

function parseStateFile(content: string): LoopState | null {
  try {
    const parsed = JSON.parse(content) as Partial<LoopState>;

    // Validate required fields
    if (
      parsed.active === undefined ||
      parsed.iteration === undefined ||
      parsed.max_iterations === undefined
    ) {
      return null;
    }

    return {
      active: parsed.active,
      iteration: parsed.iteration,
      max_iterations: parsed.max_iterations,
      timestamp: parsed.timestamp || new Date().toISOString(),
      review_enabled: parsed.review_enabled ?? true,
      review_count: parsed.review_count ?? 0,
      max_review_cycles: parsed.max_review_cycles ?? parsed.max_iterations,
      debug: parsed.debug ?? false,
    };
  } catch {
    return null;
  }
}

function serializeState(state: LoopState): string {
  return JSON.stringify(state, null, 2) + "\n";
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

// --- JSONL Log ---

type LogEntry = Record<string, unknown> & {
  ts: string;
  type: "review" | "phase" | "commit" | "decision" | "summary";
};

/**
 * Get the log file path from the state file path.
 * State is at .rl/state.json, log is at .rl/log.jsonl.
 */
function getLogFilePath(stateFile: string): string {
  return join(stateFile, "..", "log.jsonl");
}

function appendLog(stateFile: string, entry: LogEntry): void {
  try {
    // Ensure .rl/ directory exists
    const dir = join(stateFile, "..");
    mkdirSync(dir, { recursive: true });
    const logPath = getLogFilePath(stateFile);
    appendFileSync(logPath, JSON.stringify(entry) + "\n");
  } catch (e) {
    crash(`Failed to append to log.jsonl`, e);
  }
}

// --- Prompt and Review History from .rl/ ---

/**
 * Read the original prompt from .rl/prompt.md.
 */
function readPrompt(stateFile: string): string | null {
  try {
    const promptPath = join(stateFile, "..", "prompt.md");
    if (!existsSync(promptPath)) return null;
    return readFileSync(promptPath, "utf-8").trim();
  } catch {
    return null;
  }
}

/**
 * Get feedback from the last review if it was a rejection.
 * Scans backwards — only needs the last review entry.
 */
function getLastRejectFeedback(stateFile: string): string | null {
  try {
    const logFilePath = getLogFilePath(stateFile);
    if (!existsSync(logFilePath)) return null;
    const content = readFileSync(logFilePath, "utf-8").trim();
    if (!content) return null;

    const lines = content.split("\n");
    for (let i = lines.length - 1; i >= 0; i--) {
      try {
        const parsed = JSON.parse(lines[i]);
        if (parsed.type !== "review") continue;
        if (parsed.decision !== "reject") return null;
        return typeof parsed.feedback === "string" ? parsed.feedback : null;
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
  feedback: string;
}

function callCodexReview(
  reviewCount: number,
  cwd: string
): ReviewResult {
  crash(`callCodexReview() started - reviewCount=${reviewCount}, cwd=${cwd}`);

  // Check if codex is available
  const whichResult = spawnSync("which", ["codex"], { encoding: "utf-8" });
  if (whichResult.status !== 0) {
    crash("Codex CLI not found, approving by default");
    debug("Codex CLI not found, approving by default");
    return { approved: true, feedback: "" };
  }
  crash(`Codex found at: ${whichResult.stdout?.trim()}`);

  // Build review prompt
  const reviewPrompt = `# Code Review

An agent worked on a task in an iterative loop and claims it's done. Review the work.

## Context

The \`.rl/\` directory contains loop state and tools. Start here:
- \`.rl/rl prompt\` — read the original task assignment
- \`.rl/rl status\` — check loop state
- \`cat .rl/log.jsonl\` — read the event log (phases, commits, decisions the agent made)
- \`.rl/rl log decision "your review notes"\` — log your own findings

## How to Review

1. Read the task with \`.rl/rl prompt\`
2. Read the event log to understand what the agent did and why
3. Review the actual code — read changed files, check both committed and uncommitted work
4. If the task includes verification commands or tests, run them
5. Judge: does this implementation satisfy the original request?

Review the code, not the process. The agent may not have committed everything — that's fine. What matters is whether the work is correct and complete relative to the task.

\`.rl/\` is loop infrastructure. Do not flag it.

## Verdict

End your response with exactly one of:
- \`<review>APPROVE</review>\` — the work satisfies the task
- \`<review>REJECT</review>\` — something is broken or a requirement is unmet

If rejecting, explain what's wrong and what needs to change. Be specific and actionable.

Review ${reviewCount + 1}.`;

  // Write review output to .rl/ directory
  const uniqueId = Date.now();
  const rlDirPath = stateFilePath ? join(stateFilePath, "..") : "/tmp";
  const outputFile = join(rlDirPath, `codex-review-${uniqueId}.txt`);

  crash(`Calling Codex with output file: ${outputFile}`);

  try {
    // Build args dynamically from user config
    const codexConfig = userConfig.codex || DEFAULT_CONFIG.codex!;
    const codexArgs: string[] = [
      "exec",
      "-",  // read prompt from stdin
    ];

    if (codexConfig.bypass_sandbox) {
      codexArgs.push("--dangerously-bypass-approvals-and-sandbox");
    } else {
      codexArgs.push("--sandbox", codexConfig.sandbox || "read-only");
      codexArgs.push("-c", `approval_policy="${codexConfig.approval_policy || "never"}"`);
    }

    codexArgs.push("-o", outputFile);

    if (Array.isArray(codexConfig.extra_args)) {
      for (const arg of codexConfig.extra_args) {
        if (typeof arg === "string") {
          codexArgs.push(arg);
        }
      }
    }

    const timeoutMs = (codexConfig.timeout_seconds || 1200) * 1000;

    crash(`Codex args: ${JSON.stringify(codexArgs)}, timeout: ${timeoutMs}ms`);

    const result = spawnSync("codex", codexArgs, {
      cwd,
      encoding: "utf-8",
      timeout: timeoutMs,
      maxBuffer: 16 * 1024 * 1024,
      input: reviewPrompt,
    });

    crash(`Codex returned - status: ${result.status}, signal: ${result.signal}`);
    if (result.stderr) crash(`Codex stderr: ${result.stderr.slice(0, 500)}`);

    // Read output
    let output = "";
    if (existsSync(outputFile)) {
      output = readFileSync(outputFile, "utf-8");
      crash(`Codex output: ${output.slice(0, 500)}`);
    } else {
      crash("No Codex output file created");
    }

    // Parse verdict — last <review> tag wins
    const reviewMatches = [...output.matchAll(/<review>\s*(APPROVE|REJECT)\s*<\/review>/gi)];
    const verdict = reviewMatches.length > 0
      ? reviewMatches[reviewMatches.length - 1][1].toUpperCase()
      : null;

    crash(`Verdict: ${verdict}`);

    if (verdict === "APPROVE") {
      return { approved: true, feedback: output };
    }

    if (verdict === "REJECT") {
      // Extract feedback — everything after the last <review>REJECT</review> tag
      const lastTag = output.lastIndexOf("<review>");
      const feedback = lastTag >= 0
        ? output.slice(0, lastTag).trim()
        : output.trim();
      return { approved: false, feedback };
    }

    // No clear verdict — approve by default
    crash("No APPROVE/REJECT found, approving by default");
    return { approved: true, feedback: output };
  } catch (e) {
    crash("Codex review failed", e);
    return { approved: true, feedback: "" };
  }
}

// --- Main Hook Logic ---

async function readStdin(): Promise<string> {
  if (process.stdin.isTTY) return "";

  return await new Promise((resolve, reject) => {
    let data = "";
    let resolved = false;

    const cleanup = () => {
      clearTimeout(timer);
      process.stdin.off("data", onData);
      process.stdin.off("end", onEnd);
      process.stdin.off("error", onError);
      process.stdin.pause();
    };

    const tryResolve = () => {
      if (resolved) return;
      try {
        JSON.parse(data);
        resolved = true;
        cleanup();
        resolve(data);
      } catch {
        // keep reading
      }
    };

    const onData = (chunk: string | Buffer) => {
      data += chunk.toString();
      tryResolve();
    };

    const onEnd = () => {
      if (resolved) return;
      resolved = true;
      cleanup();
      resolve(data);
    };

    const onError = (err: Error) => {
      if (resolved) return;
      resolved = true;
      cleanup();
      reject(err);
    };

    const timer = setTimeout(() => {
      if (resolved) return;
      resolved = true;
      cleanup();
      resolve(data);
    }, STDIN_TIMEOUT_MS);

    process.stdin.setEncoding("utf-8");
    process.stdin.on("data", onData);
    process.stdin.on("end", onEnd);
    process.stdin.on("error", onError);
    process.stdin.resume();
  });
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
    const trimmed = inputRaw.trim();
    if (!trimmed) {
      crash("No stdin payload received; using fallback context");
      input = {
        session_id: "unknown",
        transcript_path: "",
        cwd: process.env.CLAUDE_PROJECT_DIR || process.cwd(),
        hook_event_name: "Stop",
      };
    } else {
      try {
        input = JSON.parse(trimmed);
      } catch (parseErr) {
        crash("Failed to parse input JSON", parseErr);
        crash(`Raw input was: ${trimmed.slice(0, 500)}`);
        throw parseErr;
      }
    }

    // Switch to session-specific crash log immediately
    setSessionId(input.session_id || "unknown");
    const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
    crash(`Input parsed: session_id=${input.session_id}, cwd=${cwd}, event=${input.hook_event_name}`);

    // Use git repo root for state file to handle directory changes within repo
    const gitRoot = getGitRoot(cwd);
    stateFilePath = getStateFilePath(cwd);

    // Set session-specific file paths
    debugLogPath = `${sessionLogDir}/debug.log`;
    crash(`State file: ${stateFilePath}, Git root: ${gitRoot || "none"}, cwd: ${cwd}, logs: ${sessionLogDir}`);

    // Check for active loop
    if (!existsSync(stateFilePath)) {
      crash("No state file found, approving exit");
      output({});
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
      output({});
      return;
    }

    if (!state.active) {
      // Loop was deactivated - clean up stale file and exit
      crash("Loop inactive, cleaning up stale state file");
      cleanupStateFile(stateFilePath);
      output({});
      return;
    }

    // Enable debug if set in state
    if (state.debug) {
      debugEnabled = true;
      debug(`[ralph-reviewed] Debug enabled via state file`);
    }

    // Check for completion/blocked via state flags (set by `rl done`)
    // Re-read state to pick up flags set during this iteration
    const freshContent = readFileSync(stateFilePath, "utf-8");
    const freshState = JSON.parse(freshContent) as Record<string, unknown>;
    const completionClaimed = freshState.completion_claimed === true;
    const blockedClaimed = freshState.blocked_claimed === true;

    debug(`[ralph-reviewed] Iteration: ${state.iteration}, done: ${completionClaimed}, blocked: ${blockedClaimed}`);

    if (blockedClaimed) {
      // BLOCKED is a special termination signal - exit without Codex review
      crash("BLOCKED claimed - terminating loop without review");
      debug(`[ralph-reviewed] BLOCKED signal received. Terminating loop without review.`);
      cleanupStateFile(stateFilePath);
      output({
        systemMessage: `# Ralph Loop: BLOCKED

**Iteration:** ${state.iteration}

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
          systemMessage: `# Ralph Loop: Max Iterations Reached

**Iteration:** ${state.iteration}

Loop ended without completion claim. Review the work and consider restarting if needed.`
        });
        return;
      }

      // Update state file
      writeFileSync(stateFilePath, serializeState(state));

      // Build continuation prompt
      const originalPrompt = readPrompt(stateFilePath) || "(no prompt found)";
      let prompt = `# Ralph Loop \u2014 Iteration ${state.iteration}\n\n`;

      const pendingFeedback = getLastRejectFeedback(stateFilePath);
      if (pendingFeedback) {
        prompt += `## Review Feedback from Previous Attempt\n\n${pendingFeedback}\n\nAddress the above feedback.\n\n---\n\n`;
      }

      prompt += originalPrompt;
      prompt += `\n\nWhen complete, run: .rl/rl done`;

      output({ decision: "block", reason: prompt });
      return;
    }

    // Completion claimed - enter review gate
    debug(`[ralph-reviewed] Completion claimed! Entering review gate...`);

    if (!state.review_enabled) {
      // Reviews disabled - allow exit
      debug(`[ralph-reviewed] Reviews disabled, approving exit`);
      cleanupStateFile(stateFilePath);
      output({});
      return;
    }

    // Require git repository - Codex needs a trusted directory
    if (!gitRoot) {
      crash("Not in a git repository - BLOCKING (Codex requires git repo)");
      output({
        decision: "block",
        reason: `# Review Gate Error: Not a Git Repository

Codex requires a git repository to run. The current directory is not inside a git repo.

**Current directory:** \`${cwd}\`

**To fix:** Initialize a git repository with \`git init\`, or move the project into an existing git repo.

**To escape this loop:** Run \`/ralph-reviewed:cancel-ralph\` to remove the loop, then exit normally.`
      });
      return;
    }

    // Perform Codex review
    debug(`[ralph-reviewed] Calling Codex for review...`);

    const reviewPromptText = readPrompt(stateFilePath) || "(no prompt found)";

    const reviewResult = callCodexReview(
      state.review_count,
      gitRoot || cwd
    );

    debug(`[ralph-reviewed] Review result: approved=${reviewResult.approved}`);

    // Log review to .rl/log.jsonl
    appendLog(stateFilePath, {
      ts: new Date().toISOString(),
      type: "review",
      cycle: state.review_count + 1,
      decision: reviewResult.approved ? "approve" : "reject",
      feedback: reviewResult.feedback,
    });

    if (reviewResult.approved) {
      debug(`[ralph-reviewed] Codex approved! Exiting loop.`);
      cleanupStateFile(stateFilePath);
      output({
        systemMessage: `# Ralph Loop: Codex APPROVED\n\n**Iteration:** ${state.iteration} | **Review cycle:** ${state.review_count + 1}\n\nReview gate cleared.`
      });
      return;
    }

    // Rejected
    state.review_count++;

    if (state.review_count >= state.max_review_cycles) {
      debug(`[ralph-reviewed] Max review cycles (${state.max_review_cycles}) reached.`);
      cleanupStateFile(stateFilePath);
      output({
        systemMessage: `# Ralph Loop: Max Review Cycles Reached\n\n**Iteration:** ${state.iteration} | **Review cycle:** ${state.review_count}\n\nLoop ended without approval. Review feedback manually.`
      });
      return;
    }

    state.iteration++;
    writeFileSync(stateFilePath, serializeState(state));

    // Feed back the reviewer's feedback + original prompt
    const feedbackPrompt = `# Ralph Loop \u2014 Iteration ${state.iteration}

## Review Feedback (Cycle ${state.review_count})

${reviewResult.feedback}

---

Fix the issues above, then run \`.rl/rl done\` when complete.

---

${reviewPromptText}`;

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
    output({});
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
  console.log(JSON.stringify({}));
  process.exit(1);
});
