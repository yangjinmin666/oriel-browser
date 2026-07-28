#!/usr/bin/env node

import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { createStockChromeHost } from "./stock-chrome-host.mjs";
import { loadRuntimeConfig } from "./runtime-config.mjs";

const RUNTIME_DIR = dirname(fileURLToPath(import.meta.url));
const BROWSER_RUNTIME = join(RUNTIME_DIR, "browser-runtime");
const SKILL_DIR = join(RUNTIME_DIR, "skill");
const args = process.argv.slice(2);
if (args[0] === "nodejs") args.shift();

const config = loadRuntimeConfig();
process.env.EGO_BROWSER_AGENT_WORKSPACE ||= SKILL_DIR;

async function endpointReady(endpoint) {
  try {
    const response = await fetch(`${endpoint}/json/version`, {
      signal: AbortSignal.timeout(1_500),
    });
    return response.ok;
  } catch {
    return false;
  }
}

if (args[0] === "--doctor") {
  const ready = await endpointReady(config.endpoint);
  process.stdout.write(
    [
      `ZhiYou: ${ready ? "ready" : "browser not running"}`,
      `Browser: ${config.browserName}`,
      `Endpoint: ${config.endpoint}`,
      ready
        ? "Codex can use the browser now."
        : "Open the ZhiYou control center and start the browser.",
      "",
    ].join("\n"),
  );
  process.exit(ready ? 0 : 1);
}

let host;
if (await endpointReady(config.endpoint)) {
  host = await createStockChromeHost({ connectTo: config.endpoint });
} else {
  host = await createStockChromeHost({
    chromePath: config.browserPath,
    headless: false,
    keepBrowserAlive: true,
    port: config.port,
    userDataDir: config.profilePath,
  });
}

globalThis.ego = host;

try {
  const { runMain } = await import(
    pathToFileURL(join(BROWSER_RUNTIME, "run.js")).href
  );
  process.exitCode = await runMain({ argv: args });
} catch (error) {
  process.stderr.write(
    `${error instanceof Error ? error.stack || error.message : String(error)}\n`,
  );
  process.exitCode = 1;
} finally {
  await host.close();
}
