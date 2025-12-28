#!/usr/bin/env bun
/**
 * Stop hook for Ralph Reviewed plugin.
 *
 * Intercepts exit attempts during an active Ralph loop.
 * When completion is claimed, triggers Codex review gate.
 *
 * Flow:
 * 1. Check for active loop state file
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

import { readFileSync, writeFileSync, existsSync, appendFileSync, unlinkSync } from "node:fs";
import { execSync, spawnSync } from "node:child_process";

// --- Crash Reporting ---
// Session-specific crash logs to avoid clobbering between concurrent sessions
let sessionId = "unknown";
let crashLogPath = "/tmp/ralph-reviewed-crash-startup.log"; // Before we know session ID

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
  crashLogPath = `/tmp/ralph-reviewed-crash-${id}.log`;
}

// Log startup immediately to help diagnose "operation aborted" errors
crash(`Hook starting - PID: ${process.pid}, argv: ${JSON.stringify(process.argv)}`);

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

let debugLogPath = "/tmp/ralph-reviewed-debug.log"; // Updated with session ID later
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

function getWorkSummary(transcriptPath: string): string {
  // Extract a summary of assistant messages for review context
  if (!existsSync(transcriptPath)) return "No transcript available.";

  try {
    const content = readFileSync(transcriptPath, "utf-8");
    const lines = content.trim().split("\n").filter(Boolean);

    const summaryParts: string[] = [];
    let charCount = 0;
    const maxChars = 4000; // Limit summary size

    for (let i = lines.length - 1; i >= 0 && charCount < maxChars; i--) {
      try {
        const msg: TranscriptMessage = JSON.parse(lines[i]);
        if (msg.role === "assistant" && Array.isArray(msg.content)) {
          const textParts = msg.content
            .filter((c) => c.type === "text" && c.text)
            .map((c) => c.text)
            .join("\n");
          if (textParts) {
            summaryParts.unshift(textParts.slice(0, maxChars - charCount));
            charCount += textParts.length;
          }
        }
      } catch {
        continue;
      }
    }

    return summaryParts.join("\n\n---\n\n") || "No assistant messages found.";
  } catch {
    return "Failed to read transcript.";
  }
}

// --- Git Operations ---

function getGitDiff(cwd: string): string {
  try {
    // Get diff of all changes (staged and unstaged)
    const result = spawnSync("git", ["diff", "HEAD"], {
      cwd,
      encoding: "utf-8",
      timeout: 10000,
    });

    if (result.status === 0 && result.stdout) {
      const diff = result.stdout.trim();
      // Limit diff size
      if (diff.length > 8000) {
        return diff.slice(0, 8000) + "\n\n... (diff truncated)";
      }
      return diff || "(no changes)";
    }
    return "(no git diff available)";
  } catch {
    return "(git diff failed)";
  }
}

// --- Codex Review ---

interface ReviewResult {
  approved: boolean;
  feedback: string | null;
}

function callCodexReview(
  originalPrompt: string,
  workSummary: string,
  gitDiff: string,
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
    return { approved: true, feedback: null };
  }
  crash(`Codex found at: ${whichResult.stdout?.trim()}`);

  // Build review prompt
  const reviewPrompt = `# Code Review Request

You are reviewing work completed by Claude in an iterative development loop.

## Original Task
${originalPrompt}

## Work Summary (recent assistant output)
${workSummary.slice(0, 3000)}

## Code Changes
\`\`\`diff
${gitDiff}
\`\`\`

## Review Guidelines
- Focus on: functional correctness, obvious bugs, missing requirements
- Ignore: style preferences, minor improvements, documentation nits
- Be practical: if it works and meets requirements, approve it
- This is review ${reviewCount + 1} of ${maxReviews} maximum

## Your Decision
Output exactly one of:
- \`<review>APPROVE</review>\` - Work meets requirements, ship it
- \`<review>REJECT: your specific feedback here</review>\` - Needs changes

If rejecting, be specific and actionable. Focus on 1-2 critical issues only.`;

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

    // Parse response
    if (output.includes("<review>APPROVE</review>")) {
      crash("Codex approved");
      return { approved: true, feedback: null };
    }

    // Look for REJECT pattern
    const rejectMatch = output.match(/<review>REJECT:\s*([\s\S]*?)<\/review>/);
    if (rejectMatch) {
      crash(`Codex rejected with feedback: ${rejectMatch[1].slice(0, 200)}`);
      return { approved: false, feedback: rejectMatch[1].trim() };
    }

    // Unclear response - default to approve
    crash("Unclear Codex response, approving by default");
    debug("Unclear Codex response, approving by default");
    return { approved: true, feedback: null };
  } catch (e) {
    crash("Codex review call threw exception", e);
    debug(`Codex review failed: ${e}, approving by default`);
    return { approved: true, feedback: null };
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

    stateFilePath = join(input.cwd, ".claude", "ralph-loop.local.md");

    // Set session-specific file paths
    debugLogPath = `/tmp/ralph-reviewed-${input.session_id}.log`;
    crash(`State file: ${stateFilePath}, Debug log: ${debugLogPath}`);

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
    const workSummary = getWorkSummary(input.transcript_path);
    const gitDiff = getGitDiff(input.cwd);

    const reviewResult = callCodexReview(
      state.original_prompt,
      workSummary,
      gitDiff,
      state.review_count,
      state.max_review_cycles,
      input.cwd
    );

    debug(`[ralph-reviewed] Review result: approved=${reviewResult.approved}, feedback=${reviewResult.feedback}`);

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
        `[ralph-reviewed] Max review cycles (${state.max_review_cycles}) reached. Final feedback: ${reviewResult.feedback}`
      );
      cleanupStateFile(stateFilePath);
      output({ decision: "approve" });
      return;
    }

    // Store feedback and continue
    state.pending_feedback = reviewResult.feedback;
    state.iteration++; // Increment iteration for the feedback round
    writeFileSync(stateFilePath, serializeState(state));

    // Build prompt with feedback
    const feedbackPrompt = `# Ralph Loop - Iteration ${state.iteration}/${state.max_iterations}

## Review Feedback (Cycle ${state.review_count}/${state.max_review_cycles})

Your previous completion was reviewed and requires changes:

${reviewResult.feedback}

Address the feedback above, then output <promise>${state.completion_promise}</promise> when truly complete.

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
