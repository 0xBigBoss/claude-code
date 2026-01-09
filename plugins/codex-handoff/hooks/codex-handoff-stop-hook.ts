#!/usr/bin/env bun
/**
 * Stop hook for Codex Handoff plugin.
 *
 * Intercepts exit attempts when a handoff gate is active.
 * Calls Codex CLI to process the handoff, then feeds output back to Claude.
 *
 * Flow:
 * 1. Check for active handoff state file (at git repo root)
 * 2. If no state file, allow exit
 * 3. Call Codex CLI with handoff context
 * 4. Clean up state file (one-shot gate)
 * 5. Block exit with Codex output as reason (session resumes)
 */

import { readFileSync, writeFileSync, existsSync, appendFileSync, unlinkSync, mkdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

// --- Version ---
const HOOK_VERSION = "2026-01-09T00:00:00Z";
const HOOK_BUILD = "v1.0.0";

// --- Timeout Constants ---
const HOOK_TIMEOUT_SECONDS = 1800;
const BUFFER_SECONDS = 120;
const MIN_CODEX_TIMEOUT_SECONDS = 60;
const MAX_CODEX_TIMEOUT_SECONDS = HOOK_TIMEOUT_SECONDS - BUFFER_SECONDS;
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
    sandbox: "workspace-write",
    approval_policy: "never",
    bypass_sandbox: false,
    extra_args: [],
    timeout_seconds: 1200,
  },
};

let userConfig: UserConfig = DEFAULT_CONFIG;

// --- Logging ---
const handoffDir = `${homedir()}/.claude/codex-handoff`;
let sessionId = "unknown";
let sessionLogDir = handoffDir;
let crashLogPath = `${handoffDir}/startup.log`;
let debugLogPath = `${handoffDir}/debug.log`;
let debugEnabled = process.env.CODEX_HANDOFF_DEBUG === "1";
let stateFilePath: string | null = null;

// Ensure base directory exists
try {
  mkdirSync(handoffDir, { recursive: true });
} catch { /* ignore */ }

// --- Config Loading ---

function loadUserConfig(): UserConfig {
  const configPath = `${handoffDir}/config.json`;
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
      appendFileSync(`${handoffDir}/startup.log`, `[${new Date().toISOString()}] Failed to load config: ${e}\n`);
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
  sessionLogDir = `${handoffDir}/${id}`;
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

// Global error handlers - block exit on error
process.on("uncaughtException", (err) => {
  crash("Uncaught exception", err);
  const errorMsg = err instanceof Error ? err.message : String(err);
  console.log(JSON.stringify({
    decision: "block",
    reason: `# Handoff Gate Error: Uncaught Exception

The handoff gate encountered an unexpected error and cannot proceed.

**Error:** ${errorMsg}

**To escape this gate:** Run \`/codex-handoff:cancel\` to remove the gate, then exit normally.

**To retry:** Simply try to exit again. The hook will re-run.

Check logs at \`~/.claude/codex-handoff/${sessionId}/crash.log\` for details.`
  }));
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  crash("Unhandled rejection", reason);
  const errorMsg = reason instanceof Error ? reason.message : String(reason);
  console.log(JSON.stringify({
    decision: "block",
    reason: `# Handoff Gate Error: Unhandled Rejection

The handoff gate encountered an unexpected error and cannot proceed.

**Error:** ${errorMsg}

**To escape this gate:** Run \`/codex-handoff:cancel\` to remove the gate, then exit normally.

**To retry:** Simply try to exit again. The hook will re-run.

Check logs at \`~/.claude/codex-handoff/${sessionId}/crash.log\` for details.`
  }));
  process.exit(1);
});

// --- Git Utilities ---

function getImmediateGitRoot(cwd: string): string | null {
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

function getParentSuperproject(cwd: string): string | null {
  try {
    const result = spawnSync("git", ["rev-parse", "--show-superproject-working-tree"], {
      cwd,
      encoding: "utf-8",
      timeout: 5000,
    });
    if (result.status === 0 && result.stdout.trim()) {
      return result.stdout.trim();
    }
    return null;
  } catch {
    return null;
  }
}

function isStateFileActive(path: string): boolean {
  try {
    if (!existsSync(path)) return false;
    const content = readFileSync(path, "utf-8");
    return content.includes("active: true");
  } catch {
    return false;
  }
}

function getStateFilePath(cwd: string): string {
  let dir = cwd;
  const checked: string[] = [];
  let fallbackPath: string | null = null;

  while (true) {
    const gitRoot = getImmediateGitRoot(dir);
    if (!gitRoot) {
      break;
    }

    const stateFile = join(gitRoot, ".claude", "codex-handoff.local.md");
    checked.push(stateFile);

    if (!fallbackPath) {
      fallbackPath = stateFile;
    }

    if (isStateFileActive(stateFile)) {
      crash(`Found ACTIVE state file at: ${stateFile} (checked: ${checked.join(", ")})`);
      return stateFile;
    }

    if (existsSync(stateFile)) {
      crash(`Found INACTIVE state file at: ${stateFile}, continuing to check parents`);
    }

    const parent = getParentSuperproject(gitRoot);
    if (!parent) {
      crash(`No active state file found, using fallback: ${fallbackPath} (checked: ${checked.join(", ")})`);
      return fallbackPath;
    }

    dir = parent;
  }

  return fallbackPath || join(cwd, ".claude", "codex-handoff.local.md");
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

interface HandoffState {
  active: boolean;
  handoff_path: string | null;
  timestamp: string;
  debug: boolean;
}

// --- Handoff File Reading ---

function readHandoffFile(handoffPath: string): string | null {
  try {
    const expandedPath = handoffPath.replace(/^~/, homedir());
    if (existsSync(expandedPath)) {
      const content = readFileSync(expandedPath, "utf-8");
      crash(`Read handoff file: ${expandedPath} (${content.length} chars)`);
      return content;
    }
    crash(`Handoff file not found: ${expandedPath}`);
    return null;
  } catch (e) {
    crash(`Failed to read handoff file: ${handoffPath}`, e);
    return null;
  }
}

// --- State File Parsing ---

function parseStateFile(content: string): HandoffState | null {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return null;

  const yaml = match[1];
  const state: Partial<HandoffState> = {};

  const lines = yaml.split("\n");
  for (const line of lines) {
    if (line.startsWith("active:")) {
      state.active = line.includes("true");
    } else if (line.startsWith("handoff_path:")) {
      const val = line.split(":").slice(1).join(":").trim().replace(/^["']|["']$/g, "");
      state.handoff_path = val === "null" ? null : val;
    } else if (line.startsWith("timestamp:")) {
      state.timestamp = line.split(":").slice(1).join(":").trim().replace(/^["']|["']$/g, "");
    } else if (line.startsWith("debug:")) {
      state.debug = line.includes("true");
    }
  }

  if (state.active === undefined || !state.handoff_path) {
    return null;
  }

  return {
    active: state.active,
    handoff_path: state.handoff_path,
    timestamp: state.timestamp || new Date().toISOString(),
    debug: state.debug ?? false,
  };
}

function cleanupStateFile(path: string): void {
  try {
    if (existsSync(path)) {
      unlinkSync(path);
      crash(`State file deleted: ${path}`);
      debug(`[codex-handoff] Cleaned up state file: ${path}`);
    }
  } catch (e) {
    crash(`Failed to delete state file: ${path}`, e);
  }
}

// --- Codex Invocation ---

interface CodexResult {
  status: "success" | "error";
  output: string;
  errorMessage?: string;
}

function callCodex(handoffContent: string, cwd: string): CodexResult {
  crash(`callCodex() started - cwd=${cwd}`);

  const whichResult = spawnSync("which", ["codex"], { encoding: "utf-8" });
  if (whichResult.status !== 0) {
    crash("Codex CLI not found - blocking");
    return {
      status: "error",
      output: "",
      errorMessage: "Codex CLI not found in PATH. Install Codex or run `/codex-handoff:cancel` to escape.",
    };
  }
  crash(`Codex found at: ${whichResult.stdout?.trim()}`);

  const handoffPrompt = `# Handoff Continuation

A teammate has handed off the following work for you to continue:

<handoff>
${handoffContent}
</handoff>

## Instructions

1. Read the context and key files mentioned in the handoff
2. Continue the work according to the next_steps section
3. Provide a summary of what you did or discovered

Your response will be passed back to Claude Code to continue the session.`;

  const uniqueId = Date.now();
  const outputFile = `/tmp/codex-handoff-output-${uniqueId}.txt`;

  crash(`Calling Codex with output file: ${outputFile}`);
  crash(`Handoff prompt length: ${handoffPrompt.length} chars`);

  try {
    const codexConfig = userConfig.codex || DEFAULT_CONFIG.codex!;
    const codexArgs: string[] = ["exec", "-"];

    if (codexConfig.bypass_sandbox) {
      codexArgs.push("--dangerously-bypass-approvals-and-sandbox");
    } else {
      codexArgs.push("--sandbox", codexConfig.sandbox || "workspace-write");
      codexArgs.push("-c", `approval_policy="${codexConfig.approval_policy || "never"}"`);
    }

    codexArgs.push("-o", outputFile);

    if (Array.isArray(codexConfig.extra_args)) {
      for (const arg of codexConfig.extra_args) {
        if (typeof arg === "string" && arg !== "-o" && !arg.startsWith("--output")) {
          codexArgs.push(arg);
        }
      }
    }

    const requestedTimeout = codexConfig.timeout_seconds ?? 1200;
    let effectiveTimeout = Math.min(requestedTimeout, MAX_CODEX_TIMEOUT_SECONDS);
    effectiveTimeout = Math.max(effectiveTimeout, MIN_CODEX_TIMEOUT_SECONDS);
    if (requestedTimeout < MIN_CODEX_TIMEOUT_SECONDS) {
      crash(`WARNING: Clamping timeout from ${requestedTimeout}s to min ${MIN_CODEX_TIMEOUT_SECONDS}s`);
    }
    if (requestedTimeout > MAX_CODEX_TIMEOUT_SECONDS) {
      crash(`WARNING: Clamping timeout from ${requestedTimeout}s to max ${MAX_CODEX_TIMEOUT_SECONDS}s`);
    }
    const timeoutMs = effectiveTimeout * 1000;

    crash(`Codex config: ${JSON.stringify(codexConfig)}`);
    crash(`Codex args: ${JSON.stringify(codexArgs)}`);
    crash(`Codex timeout: ${timeoutMs}ms`);

    const result = spawnSync("codex", codexArgs, {
      cwd,
      encoding: "utf-8",
      timeout: timeoutMs,
      maxBuffer: 16 * 1024 * 1024,
      input: handoffPrompt,
    });

    crash(`Codex returned - status: ${result.status}, signal: ${result.signal}, error: ${result.error}`);
    if (result.stderr) {
      crash(`Codex stderr: ${result.stderr.slice(0, 500)}`);
    }

    if (result.error) {
      const errorMsg = result.error instanceof Error ? result.error.message : String(result.error);
      crash(`Codex spawn error: ${errorMsg}`);
      return {
        status: "error",
        output: "",
        errorMessage: `Codex spawn error: ${errorMsg}. Retry or run \`/codex-handoff:cancel\` to escape.`,
      };
    }

    if (result.signal) {
      crash(`Codex killed by signal ${result.signal}`);
      return {
        status: "error",
        output: "",
        errorMessage: `Codex was killed by signal ${result.signal}. This may indicate a timeout. Retry or run \`/codex-handoff:cancel\` to escape.`,
      };
    }

    if (result.status !== 0 && result.status !== null) {
      crash(`Codex exited with non-zero status ${result.status}`);
      return {
        status: "error",
        output: "",
        errorMessage: `Codex exited with status ${result.status}. Check Codex logs. Retry or run \`/codex-handoff:cancel\` to escape.`,
      };
    }

    let output = "";
    if (existsSync(outputFile)) {
      output = readFileSync(outputFile, "utf-8");
      crash(`Codex output file contents: ${output.slice(0, 500)}`);
    } else {
      crash("No Codex output file created");
      return {
        status: "error",
        output: "",
        errorMessage: "Codex completed but no output file was created. Retry or run `/codex-handoff:cancel` to escape.",
      };
    }

    crash(`Codex completed successfully with ${output.length} chars output`);
    return { status: "success", output };
  } catch (e) {
    crash("Codex call threw exception", e);
    const errorMsg = e instanceof Error ? e.message : String(e);
    return {
      status: "error",
      output: "",
      errorMessage: `Codex threw an exception: ${errorMsg}. Retry or run \`/codex-handoff:cancel\` to escape.`,
    };
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

    setSessionId(input.session_id || "unknown");
    const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
    crash(`Input parsed: session_id=${input.session_id}, cwd=${cwd}, event=${input.hook_event_name}`);

    const gitRoot = getImmediateGitRoot(cwd);
    stateFilePath = getStateFilePath(cwd);
    crash(`State file: ${stateFilePath}, Git root: ${gitRoot || "none"}, cwd: ${cwd}`);

    // Check for active handoff gate
    if (!existsSync(stateFilePath)) {
      crash("No state file found, allowing exit (no output)");
      return;
    }
    crash("State file exists, reading...");

    const stateContent = readFileSync(stateFilePath, "utf-8");
    const state = parseStateFile(stateContent);

    if (!state) {
      crash("Failed to parse state file - blocking");
      output({
        decision: "block",
        reason: `# Handoff Gate Error: Malformed State File

The handoff gate state file exists but could not be parsed.

**State file location:** \`${stateFilePath}\`

**To escape this gate:** Run \`/codex-handoff:cancel\` to remove the gate, then exit normally.

**To fix:** Inspect the state file for syntax errors, or delete it manually.`
      });
      return;
    }

    if (!state.active) {
      crash("Handoff gate inactive, cleaning up stale state file");
      cleanupStateFile(stateFilePath);
      return;
    }

    if (state.debug) {
      debugEnabled = true;
      debug(`[codex-handoff] Debug enabled via state file`);
    }

    // Require git repository for Codex
    if (!gitRoot) {
      crash("Not in a git repository - blocking");
      output({
        decision: "block",
        reason: `# Handoff Gate Error: Not a Git Repository

Codex requires a git repository to run. The current directory is not inside a git repo.

**Current directory:** \`${cwd}\`

**To fix:** Initialize a git repository with \`git init\`, or move the project into an existing git repo.

**To escape this gate:** Run \`/codex-handoff:cancel\` to remove the gate, then exit normally.`
      });
      return;
    }

    debug(`[codex-handoff] Handoff gate active, calling Codex...`);

    // Read handoff content
    const handoffContent = state.handoff_path ? readHandoffFile(state.handoff_path) : null;
    if (!handoffContent) {
      crash("No handoff content available - handoff file missing");
      output({
        decision: "block",
        reason: `# Handoff Gate Error: No Handoff Content

The handoff file could not be read.

**Handoff path:** \`${state.handoff_path || "(not set)"}\`

**To fix:** Regenerate the handoff with \`/handoff\` or run \`/codex-handoff:cancel\` to escape.`
      });
      return;
    }

    const codexResult = callCodex(handoffContent, cwd);

    debug(`[codex-handoff] Codex result: status=${codexResult.status}`);

    // Handle error
    if (codexResult.status === "error") {
      debug(`[codex-handoff] Codex error: ${codexResult.errorMessage}`);
      output({
        decision: "block",
        reason: `# Handoff Gate Error

${codexResult.errorMessage}

**To escape this gate:** Run \`/codex-handoff:cancel\` to remove the gate, then exit normally.

**To retry:** Simply try to exit again. The hook will re-run.`
      });
      return;
    }

    // Success - clean up state file (one-shot gate)
    cleanupStateFile(stateFilePath);
    debug(`[codex-handoff] Codex completed successfully, state cleared`);

    // Block exit with Codex output as feedback - session resumes
    const feedbackPrompt = `# Codex Handoff Complete

Codex has processed the handoff and returned the following:

---

${codexResult.output}

---

The handoff gate has been cleared. Continue working with this context.`;

    output({ decision: "block", reason: feedbackPrompt });
  } catch (e) {
    crash("main() caught exception", e);
    debug(`Stop hook error: ${e}`);
    const errorMsg = e instanceof Error ? e.message : String(e);
    output({
      decision: "block",
      reason: `# Handoff Gate Error: Hook Exception

The handoff gate encountered an unexpected error and cannot proceed.

**Error:** ${errorMsg}

**To escape this gate:** Run \`/codex-handoff:cancel\` to remove the gate, then exit normally.

**To retry:** Simply try to exit again. The hook will re-run.

Check logs at \`~/.claude/codex-handoff/${sessionId}/crash.log\` for details.`
    });
  }
  crash("main() exiting normally");
}

crash("About to call main()");
main().catch((e) => {
  crash("main() promise rejected", e);
  const errorMsg = e instanceof Error ? e.message : String(e);
  console.log(JSON.stringify({
    decision: "block",
    reason: `# Handoff Gate Error: Unhandled Promise Rejection

The handoff gate encountered an unexpected error and cannot proceed.

**Error:** ${errorMsg}

**To escape this gate:** Run \`/codex-handoff:cancel\` to remove the gate, then exit normally.

**To retry:** Simply try to exit again. The hook will re-run.

Check logs at \`~/.claude/codex-handoff/${sessionId}/crash.log\` for details.`
  }));
  process.exit(1);
});
