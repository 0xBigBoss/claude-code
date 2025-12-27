#!/usr/bin/env bun
/**
 * SessionStart hook that uses Haiku to intelligently determine
 * which best-practice skills should be loaded based on project context.
 *
 * Runs on:
 * - Session startup (new session)
 * - After compaction (context reset)
 *
 * Haiku explores the project using Glob/Read tools, then outputs
 * skill names as hints for Claude to activate via Skill tool.
 */

import { join } from "node:path";
import { spawn } from "node:child_process";

const AVAILABLE_SKILLS = [
  "python-best-practices",
  "typescript-best-practices",
  "react-best-practices",
  "go-best-practices",
  "playwright-best-practices",
  "zig-best-practices",
  "tilt",
  "tamagui-best-practices",
] as const;

type SkillName = (typeof AVAILABLE_SKILLS)[number];

interface HookInput {
  session_id: string;
  transcript_path: string;
  cwd: string;
  hook_event_name: "SessionStart";
  source: "startup" | "resume" | "clear" | "compact";
}

interface HookOutput {
  hookSpecificOutput: {
    hookEventName: "SessionStart";
    additionalContext: string;
  };
}

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf-8");
}

async function invokeHaiku(cwd: string): Promise<string[]> {
  const analyzePrompt = `You are analyzing a project to determine which development best-practice skills should be loaded for this coding session.

Available skills (only output these exact names):
${AVAILABLE_SKILLS.map((s) => `- ${s}`).join("\n")}

Your task:
1. Use Glob to find project files (package.json, tsconfig.json, pyproject.toml, go.mod, Tiltfile, build.zig, *.tsx, *.py, etc.)
2. Use Read on key config files to understand the project type
3. Output ONLY a JSON array of skill names that apply to this project

After exploring, output ONLY a valid JSON array like: ["typescript-best-practices", "react-best-practices"]
Do not include any other text, explanation, or markdown formatting.`;

  return new Promise((resolve) => {
    const proc = spawn("claude", ["--model", "haiku", "-p", analyzePrompt], {
      cwd,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    proc.stdout.on("data", (data) => {
      stdout += data.toString();
    });

    proc.stderr.on("data", (data) => {
      stderr += data.toString();
    });

    proc.on("close", (code) => {
      if (code !== 0) {
        console.error(`Haiku exited with code ${code}: ${stderr}`);
        resolve([]);
        return;
      }

      // Extract JSON array from output (Haiku might include extra text)
      const jsonMatch = stdout.match(/\[[\s\S]*?\]/);
      if (!jsonMatch) {
        console.error(`No JSON array found in Haiku output: ${stdout}`);
        resolve([]);
        return;
      }

      try {
        const skills = JSON.parse(jsonMatch[0]) as string[];
        const validSkills = skills.filter((s): s is SkillName =>
          AVAILABLE_SKILLS.includes(s as SkillName)
        );
        resolve(validSkills);
      } catch (e) {
        console.error(`Failed to parse Haiku output: ${e}`);
        resolve([]);
      }
    });

    proc.on("error", (err) => {
      console.error(`Failed to spawn Haiku: ${err}`);
      resolve([]);
    });
  });
}

function formatSkillHint(skillNames: string[]): string {
  const skillList = skillNames.map((s) => `- ${s}`).join("\n");
  return `Relevant best-practice skills detected for this project:\n${skillList}\n\nConsider using the Skill tool to activate them if applicable to the current task.`;
}

async function main() {
  try {
    const inputRaw = await readStdin();
    const input: HookInput = JSON.parse(inputRaw);

    // Invoke Haiku to analyze project
    const skills = await invokeHaiku(input.cwd);

    if (skills.length === 0) {
      process.exit(0);
    }

    // Output hook response with skill hints
    const output: HookOutput = {
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: formatSkillHint(skills),
      },
    };

    console.log(JSON.stringify(output));
    process.exit(0);
  } catch (e) {
    console.error(`Hook error: ${e}`);
    process.exit(1);
  }
}

main();
