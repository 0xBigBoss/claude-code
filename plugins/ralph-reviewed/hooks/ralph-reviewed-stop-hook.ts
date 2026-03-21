#!/usr/bin/env bun
/**
 * Stop hook for Ralph Reviewed plugin.
 *
 * Intercepts exit attempts during an active Ralph loop.
 * When completion is claimed, triggers Codex review gate.
 *
 * State, prompt, and log operations are delegated to the `rl` CLI
 * (@0xbigboss/rl). The hook only handles stdin parsing, Codex review,
 * and the block/allow decision.
 *
 * Flow:
 * 1. Check for active loop state file (at git repo root)
 * 2. If no loop, allow exit
 * 3. Read state via `rl status --json`
 * 4. Check for completion/blocked flags
 *    - Not found: increment iteration, block exit, re-feed prompt
 *    - Found: trigger review gate
 * 5. Review gate:
 *    - Call Codex CLI with review prompt
 *    - APPROVE: allow exit
 *    - REJECT: inject feedback, block exit, continue
 */

import { readFileSync, existsSync, appendFileSync, unlinkSync, mkdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

// --- Version ---
const HOOK_VERSION = "2026-03-21T14:00:00Z";
const HOOK_BUILD = "v3.0.0";
const STDIN_TIMEOUT_MS = 2000;

// --- User Config ---

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

// --- Crash Reporting ---
const ralphsDir = `${homedir()}/.claude/ralphs`;
let sessionId = "unknown";
let sessionLogDir = ralphsDir;
let crashLogPath = `${ralphsDir}/startup.log`;

try {
  mkdirSync(ralphsDir, { recursive: true });
} catch { /* ignore */ }

// --- Config Loading ---

function loadUserConfig(): UserConfig {
  const standardPath = `${homedir()}/.claude/codex.json`;
  const legacyPath = `${ralphsDir}/config.json`;

  for (const configPath of [standardPath, legacyPath]) {
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
        appendFileSync(`${ralphsDir}/startup.log`, `[${new Date().toISOString()}] Failed to load config from ${configPath}: ${e}\n`);
      } catch { /* ignore */ }
    }
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
  sessionLogDir = `${ralphsDir}/${id}`;
  try {
    mkdirSync(sessionLogDir, { recursive: true });
  } catch { /* ignore */ }
  crashLogPath = `${sessionLogDir}/crash.log`;
}

crash(`Hook starting - version: ${HOOK_BUILD} (${HOOK_VERSION}), PID: ${process.pid}`);

// Global error handlers
let stateFilePath: string | null = null;

process.on("uncaughtException", (err) => {
  crash("Uncaught exception", err);
  if (stateFilePath) {
    try { unlinkSync(stateFilePath); crash(`Cleaned up state file on uncaught exception: ${stateFilePath}`); } catch { /* ignore */ }
  }
  console.log(JSON.stringify({}));
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  crash("Unhandled rejection", reason);
  if (stateFilePath) {
    try { unlinkSync(stateFilePath); crash(`Cleaned up state file on unhandled rejection: ${stateFilePath}`); } catch { /* ignore */ }
  }
  console.log(JSON.stringify({}));
  process.exit(1);
});

let debugLogPath = `${ralphsDir}/debug.log`;
let debugEnabled = process.env.RALPH_DEBUG === "1";

function debug(msg: string) {
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] [${sessionId}] ${msg}\n`;
  try {
    appendFileSync(crashLogPath, `[DEBUG] ${line}`);
  } catch { /* ignore */ }
  if (!debugEnabled) return;
  appendFileSync(debugLogPath, line);
}

// --- Git Utilities ---

function getGitRoot(cwd: string): string | null {
  try {
    let dir = cwd;
    while (true) {
      const superResult = spawnSync("git", ["rev-parse", "--show-superproject-working-tree"], {
        cwd: dir, encoding: "utf-8", timeout: 5000,
      });
      const superproject = superResult.status === 0 ? superResult.stdout.trim() : "";
      if (!superproject) {
        const rootResult = spawnSync("git", ["rev-parse", "--show-toplevel"], {
          cwd: dir, encoding: "utf-8", timeout: 5000,
        });
        if (rootResult.status === 0 && rootResult.stdout) return rootResult.stdout.trim();
        return null;
      }
      dir = superproject;
    }
  } catch {
    return null;
  }
}

function getStateFilePath(cwd: string): string {
  const gitRoot = getGitRoot(cwd);
  return join(gitRoot || cwd, ".rl", "state.json");
}

// --- rl CLI integration ---

function callRl(args: string[], cwd: string): { ok: boolean; stdout: string } {
  const result = spawnSync("rl", args, { cwd, encoding: "utf-8", timeout: 10000 });
  if (result.status !== 0) {
    crash(`rl ${args.join(" ")} failed: ${result.stderr || result.stdout}`);
    return { ok: false, stdout: result.stdout || "" };
  }
  return { ok: true, stdout: result.stdout || "" };
}

function rlStatusJson(cwd: string): Record<string, unknown> | null {
  const result = callRl(["status", "--json"], cwd);
  if (!result.ok) return null;
  try {
    return JSON.parse(result.stdout) as Record<string, unknown>;
  } catch {
    crash(`Failed to parse rl status output: ${result.stdout.slice(0, 200)}`);
    return null;
  }
}

function rlPrompt(cwd: string): string | null {
  const result = callRl(["prompt", "--json"], cwd);
  if (!result.ok) return null;
  try {
    const parsed = JSON.parse(result.stdout);
    return typeof parsed === "string" ? parsed : null;
  } catch {
    return result.stdout.trim() || null;
  }
}

// --- State File Cleanup ---

function cleanupStateFile(path: string): void {
  try {
    if (existsSync(path)) {
      unlinkSync(path);
      crash(`State file deleted: ${path}`);
      debug(`[ralph-reviewed] Cleaned up state file: ${path}`);
    }
  } catch (e) {
    crash(`Failed to delete state file: ${path}`, e);
  }
}

// --- Last Reject Feedback ---

function getLastRejectFeedback(rlDir: string): string | null {
  try {
    const logFilePath = join(rlDir, "log.jsonl");
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
      } catch { continue; }
    }
  } catch { /* ignore */ }
  return null;
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

interface HookOutput {
  decision?: "block";
  reason?: string;
  systemMessage?: string;
  continue?: boolean;
  stopReason?: string;
}

interface ReviewResult {
  approved: boolean;
  feedback: string;
}

// --- Codex Review ---

function callCodexReview(reviewCount: number, cwd: string): ReviewResult {
  crash(`callCodexReview() started - reviewCount=${reviewCount}, cwd=${cwd}`);

  const whichResult = spawnSync("which", ["codex"], { encoding: "utf-8" });
  if (whichResult.status !== 0) {
    crash("Codex CLI not found, approving by default");
    return { approved: true, feedback: "" };
  }

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

  const uniqueId = Date.now();
  const rlDirPath = stateFilePath ? join(stateFilePath, "..") : "/tmp";
  const outputFile = join(rlDirPath, `codex-review-${uniqueId}.txt`);

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

    if (Array.isArray(codexConfig.extra_args)) {
      for (const arg of codexConfig.extra_args) {
        if (typeof arg === "string") codexArgs.push(arg);
      }
    }

    const timeoutMs = (codexConfig.timeout_seconds || 1200) * 1000;
    crash(`Codex args: ${JSON.stringify(codexArgs)}, timeout: ${timeoutMs}ms`);

    const result = spawnSync("codex", codexArgs, {
      cwd, encoding: "utf-8", timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024, input: reviewPrompt,
    });

    crash(`Codex returned - status: ${result.status}, signal: ${result.signal}`);
    if (result.stderr) crash(`Codex stderr: ${result.stderr.slice(0, 500)}`);

    let codexOutput = "";
    if (existsSync(outputFile)) {
      codexOutput = readFileSync(outputFile, "utf-8");
      crash(`Codex output: ${codexOutput.slice(0, 500)}`);
    } else {
      crash("No Codex output file created");
    }

    const reviewMatches = [...codexOutput.matchAll(/<review>\s*(APPROVE|REJECT)\s*<\/review>/gi)];
    const verdict = reviewMatches.length > 0
      ? reviewMatches[reviewMatches.length - 1][1].toUpperCase()
      : null;

    crash(`Verdict: ${verdict}`);

    if (verdict === "APPROVE") return { approved: true, feedback: codexOutput };
    if (verdict === "REJECT") {
      const lastTag = codexOutput.lastIndexOf("<review>");
      const feedback = lastTag >= 0 ? codexOutput.slice(0, lastTag).trim() : codexOutput.trim();
      return { approved: false, feedback };
    }

    crash("No APPROVE/REJECT found, approving by default");
    return { approved: true, feedback: codexOutput };
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
      } catch { /* keep reading */ }
    };

    const onData = (chunk: string | Buffer) => { data += chunk.toString(); tryResolve(); };
    const onEnd = () => { if (resolved) return; resolved = true; cleanup(); resolve(data); };
    const onError = (err: Error) => { if (resolved) return; resolved = true; cleanup(); reject(err); };

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
        throw parseErr;
      }
    }

    setSessionId(input.session_id || "unknown");
    const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
    crash(`Input parsed: session_id=${input.session_id}, cwd=${cwd}`);

    const gitRoot = getGitRoot(cwd);
    stateFilePath = getStateFilePath(cwd);
    debugLogPath = `${sessionLogDir}/debug.log`;
    crash(`State file: ${stateFilePath}, Git root: ${gitRoot || "none"}, cwd: ${cwd}`);

    // Fast gate: no state file means no active loop
    if (!existsSync(stateFilePath)) {
      crash("No state file found, approving exit");
      output({});
      return;
    }

    // Read full state via rl CLI (single call, cached for the hook invocation)
    const rlCwd = gitRoot || cwd;
    const state = rlStatusJson(rlCwd);

    if (!state) {
      crash("Failed to read state via rl, cleaning up");
      cleanupStateFile(stateFilePath);
      output({});
      return;
    }

    if (!state.active) {
      crash("Loop inactive, cleaning up stale state file");
      cleanupStateFile(stateFilePath);
      output({});
      return;
    }

    if (state.debug) {
      debugEnabled = true;
      debug(`[ralph-reviewed] Debug enabled via state file`);
    }

    const iteration = state.iteration as number;
    const maxIterations = state.max_iterations as number;
    const reviewEnabled = state.review_enabled as boolean;
    const reviewCount = state.review_count as number;
    const maxReviewCycles = state.max_review_cycles as number;
    const completionClaimed = state.completion_claimed === true;
    const blockedClaimed = state.blocked_claimed === true;

    debug(`[ralph-reviewed] Iteration: ${iteration}, done: ${completionClaimed}, blocked: ${blockedClaimed}`);

    if (blockedClaimed) {
      crash("BLOCKED claimed - terminating loop without review");
      cleanupStateFile(stateFilePath);
      output({
        systemMessage: `# Ralph Loop: BLOCKED\n\n**Iteration:** ${iteration}\n\nTask reported as blocked. Loop terminated without review.`
      });
      return;
    }

    if (!completionClaimed) {
      // Normal iteration - no completion claimed
      const nextIteration = iteration + 1;

      if (nextIteration >= maxIterations) {
        debug(`[ralph-reviewed] Max iterations (${maxIterations}) reached, exiting loop`);
        cleanupStateFile(stateFilePath);
        output({
          systemMessage: `# Ralph Loop: Max Iterations Reached\n\n**Iteration:** ${nextIteration}\n\nLoop ended without completion claim. Review the work and consider restarting if needed.`
        });
        return;
      }

      // Update iteration via rl
      callRl(["state", "set", "iteration", String(nextIteration)], rlCwd);

      // Clear any stale completion/blocked flags
      callRl(["state", "set", "completion_claimed", "false"], rlCwd);
      callRl(["state", "set", "blocked_claimed", "false"], rlCwd);

      // Build continuation prompt
      const originalPrompt = rlPrompt(rlCwd) || "(no prompt found)";
      let prompt = `# Ralph Loop \u2014 Iteration ${nextIteration}\n\n`;

      const rlDir = join(rlCwd, ".rl");
      const pendingFeedback = getLastRejectFeedback(rlDir);
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

    if (!reviewEnabled) {
      debug(`[ralph-reviewed] Reviews disabled, approving exit`);
      cleanupStateFile(stateFilePath);
      output({});
      return;
    }

    if (!gitRoot) {
      crash("Not in a git repository - BLOCKING (Codex requires git repo)");
      output({
        decision: "block",
        reason: `# Review Gate Error: Not a Git Repository\n\nCodex requires a git repository to run.\n\n**Current directory:** \`${cwd}\`\n\n**To fix:** Initialize a git repository with \`git init\`.\n\n**To escape this loop:** Run \`/ralph-reviewed:cancel-ralph\` to remove the loop, then exit normally.`
      });
      return;
    }

    debug(`[ralph-reviewed] Calling Codex for review...`);

    const reviewResult = callCodexReview(reviewCount, gitRoot);

    debug(`[ralph-reviewed] Review result: approved=${reviewResult.approved}`);

    // Log review via rl
    callRl(["log", "review", "--decision", reviewResult.approved ? "approve" : "reject", "--feedback", reviewResult.feedback], rlCwd);

    if (reviewResult.approved) {
      debug(`[ralph-reviewed] Codex approved! Exiting loop.`);
      cleanupStateFile(stateFilePath);
      output({
        systemMessage: `# Ralph Loop: Codex APPROVED\n\n**Iteration:** ${iteration} | **Review cycle:** ${reviewCount + 1}\n\nReview gate cleared.`
      });
      return;
    }

    // Rejected
    const newReviewCount = reviewCount + 1;

    if (newReviewCount >= maxReviewCycles) {
      debug(`[ralph-reviewed] Max review cycles (${maxReviewCycles}) reached.`);
      cleanupStateFile(stateFilePath);
      output({
        systemMessage: `# Ralph Loop: Max Review Cycles Reached\n\n**Iteration:** ${iteration} | **Review cycle:** ${newReviewCount}\n\nLoop ended without approval. Review feedback manually.`
      });
      return;
    }

    const nextIteration = iteration + 1;
    callRl(["state", "set", "iteration", String(nextIteration)], rlCwd);
    callRl(["state", "set", "review_count", String(newReviewCount)], rlCwd);
    callRl(["state", "set", "completion_claimed", "false"], rlCwd);

    const reviewPromptText = rlPrompt(rlCwd) || "(no prompt found)";
    const feedbackPrompt = `# Ralph Loop \u2014 Iteration ${nextIteration}

## Review Feedback (Cycle ${newReviewCount})

Your previous completion was reviewed and requires changes.

${reviewResult.feedback}

Address ALL open issues above, then output <promise>COMPLETE</promise> when truly complete.

---

${reviewPromptText}`;

    output({ decision: "block", reason: feedbackPrompt });
  } catch (e) {
    crash("main() caught exception", e);
    if (stateFilePath) {
      try { unlinkSync(stateFilePath); crash(`Cleaned up state file on main() exception: ${stateFilePath}`); } catch { /* ignore */ }
    }
    output({});
  }
  crash("main() exiting normally");
}

crash("About to call main()");
main().catch((e) => {
  crash("main() promise rejected", e);
  if (stateFilePath) {
    try { unlinkSync(stateFilePath); crash(`Cleaned up state file on main() rejection: ${stateFilePath}`); } catch { /* ignore */ }
  }
  console.log(JSON.stringify({}));
  process.exit(1);
});
