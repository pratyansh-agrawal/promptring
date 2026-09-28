#!/usr/bin/env node

import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const packageRoot = dirname(fileURLToPath(import.meta.url));
const installRoot = join(homedir(), ".copilot", "promptring");
const runtime = join(installRoot, "bin", "promptring.py");
const command = process.argv[2];

function run(executable, args) {
  const result = spawnSync(executable, args, { stdio: "inherit" });
  if (result.error) {
    console.error(`promptring: ${result.error.message}`);
    process.exit(1);
  }
  process.exit(result.status ?? 1);
}

function printHelp() {
  console.log(`promptring - desktop notifications for GitHub Copilot CLI

Usage:
  promptring install              Install or refresh Copilot hooks
  promptring --check              Send a test notification
  promptring --status             Show sound configuration
  promptring --mute               Mute the notification sound
  promptring --unmute             Restore the notification sound
  promptring --tring <file>       Use a custom notification sound
  promptring --untring            Restore the bundled sound
  promptring <category> [message] Send a notification directly

The npm postinstall runs the OS-specific installer automatically.`);
}

if (command === "install") {
  if (process.platform === "win32") {
    run("powershell.exe", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      join(packageRoot, "install.ps1"),
    ]);
  }
  run("bash", [join(packageRoot, "install.sh")]);
}

if (command === "--help" || command === "-h" || command === "help") {
  printHelp();
  process.exit(0);
}

if (!existsSync(runtime)) {
  printHelp();
  console.error("\npromptring is not configured yet. Run: promptring install");
  process.exit(1);
}

run(process.platform === "win32" ? "python" : "python3", [
  runtime,
  ...process.argv.slice(2),
]);
