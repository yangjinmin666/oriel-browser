#!/usr/bin/env node

import { spawn } from "node:child_process";
import { closeSync, existsSync, mkdirSync, openSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { connectDaemonRpc } from "./daemon-rpc.mjs";
import {
  APP_SUPPORT_DIR,
  CONFIG_PATH,
  loadRuntimeConfig,
} from "./runtime-config.mjs";

const RUNTIME_DIR = dirname(fileURLToPath(import.meta.url));
const BUNDLED_BROWSER_RUNTIME = join(RUNTIME_DIR, "browser-runtime");
const BROWSER_RUNTIME = existsSync(join(BUNDLED_BROWSER_RUNTIME, "run.js"))
  ? BUNDLED_BROWSER_RUNTIME
  : join(RUNTIME_DIR, "../package/ego-browser/dist/src");
const BUNDLED_SKILL_DIR = join(RUNTIME_DIR, "skill");
const SKILL_DIR = existsSync(BUNDLED_SKILL_DIR)
  ? BUNDLED_SKILL_DIR
  : join(RUNTIME_DIR, "../skills/ego-browser");
const DAEMON_ENTRY = join(RUNTIME_DIR, "oriel-daemon.mjs");
const DAEMON_SOCKET_PATH =
  process.env.ORIEL_DAEMON_SOCKET ||
  process.env.ZHIYOU_DAEMON_SOCKET ||
  join(APP_SUPPORT_DIR, "daemon.sock");
const DAEMON_LOG_PATH =
  process.env.ORIEL_DAEMON_LOG ||
  process.env.ZHIYOU_DAEMON_LOG ||
  join(APP_SUPPORT_DIR, "daemon.log");
const args = process.argv.slice(2);
if (args[0] === "nodejs") args.shift();
process.env.EGO_BROWSER_AGENT_WORKSPACE ||= SKILL_DIR;

function wantsJson() {
  return args.includes("--json");
}

function loadConfigForCommand() {
  try {
    return { config: loadRuntimeConfig(), error: null };
  } catch (error) {
    return {
      config: null,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

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

async function connectExistingDaemon(connectTimeoutMs = 400) {
  const client = await connectDaemonRpc({
    socketPath: DAEMON_SOCKET_PATH,
    connectTimeoutMs,
  });
  try {
    const status = await client.daemonRequest("daemon.ping");
    return { client, status };
  } catch (error) {
    await client.close();
    throw error;
  }
}

function launchDaemon() {
  mkdirSync(APP_SUPPORT_DIR, { recursive: true, mode: 0o700 });
  const logFd = openSync(DAEMON_LOG_PATH, "a", 0o600);
  try {
    const child = spawn(process.execPath, [DAEMON_ENTRY], {
      detached: true,
      stdio: ["ignore", logFd, logFd],
      env: {
        ...process.env,
        ORIEL_CONFIG: CONFIG_PATH,
        ORIEL_DAEMON_SOCKET: DAEMON_SOCKET_PATH,
      },
    });
    child.unref();
  } finally {
    closeSync(logFd);
  }
}

async function ensureDaemon() {
  try {
    return await connectExistingDaemon();
  } catch {}
  launchDaemon();
  let lastError;
  for (let attempt = 0; attempt < 60; attempt++) {
    try {
      return await connectExistingDaemon(250);
    } catch (error) {
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
  }
  throw new Error(
    `Oriel 后台没有在 12 秒内启动${lastError ? `: ${lastError.message}` : ""}`,
  );
}

async function doctorReport({ config, configError }) {
  const ready = config ? await endpointReady(config.endpoint) : false;
  let daemonStatus = null;
  try {
    const connection = await connectExistingDaemon();
    daemonStatus = connection.status;
    await connection.client.close();
  } catch {}

  return {
    schemaVersion: 1,
    status:
      config && ready && daemonStatus
        ? "ready"
        : config && ready
          ? "browser-ready"
          : config
            ? "needs-attention"
            : "invalid-config",
    configuration: config
      ? {
          valid: true,
          browserId: config.browserId,
          browserName: config.browserName,
          endpoint: config.endpoint,
        }
      : { valid: false, error: configError },
    browser: { connected: ready },
    daemon: daemonStatus
      ? {
          running: true,
          pid: daemonStatus.pid,
          clients: daemonStatus.clients,
        }
      : { running: false },
  };
}

function writeDoctorReport(report) {
  if (wantsJson()) {
    process.stdout.write(`${JSON.stringify(report)}\n`);
    return;
  }
  process.stdout.write(
    [
      `Oriel: ${report.status}`,
      report.configuration.valid
        ? `Browser: ${report.configuration.browserName}`
        : `Configuration: ${report.configuration.error}`,
      report.configuration.valid
        ? `Endpoint: ${report.configuration.endpoint}`
        : "Endpoint: unavailable",
      `Daemon: ${report.daemon.running ? `ready (pid ${report.daemon.pid})` : "not running"}`,
      report.status === "ready"
        ? "Codex can reuse persistent browser sessions now."
        : report.browser.connected
          ? "The browser is ready; the daemon starts automatically on the first task."
          : "Open the Oriel control center and start the browser.",
      "",
    ].join("\n"),
  );
}

const configState = loadConfigForCommand();

if (args[0] === "--doctor" || args[0] === "--daemon-status") {
  const report = await doctorReport({
    config: configState.config,
    configError: configState.error,
  });
  writeDoctorReport(report);
  process.exit(report.status === "ready" ? 0 : 1);
}

if (!configState.config) {
  throw new Error(configState.error);
}

const config = configState.config;

if (args[0] === "--daemon-stop") {
  try {
    const { client } = await connectExistingDaemon();
    await client.daemonRequest("daemon.shutdown");
    await client.close();
    process.stdout.write("Oriel daemon stopped.\n");
  } catch {
    process.stdout.write("Oriel daemon is not running.\n");
  }
  process.exit(0);
}

const { client: host } = await ensureDaemon();
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
