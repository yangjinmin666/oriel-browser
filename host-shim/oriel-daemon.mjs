#!/usr/bin/env node

import {
  closeSync,
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";

import { startDaemonRpcServer } from "./daemon-rpc.mjs";
import { APP_SUPPORT_DIR, loadRuntimeConfig } from "./runtime-config.mjs";
import { createStockChromeHost } from "./stock-chrome-host.mjs";

export const DAEMON_SOCKET_PATH =
  process.env.ORIEL_DAEMON_SOCKET ||
  process.env.ZHIYOU_DAEMON_SOCKET ||
  join(APP_SUPPORT_DIR, "daemon.sock");
export const DAEMON_LOCK_PATH =
  process.env.ORIEL_DAEMON_LOCK ||
  process.env.ZHIYOU_DAEMON_LOCK ||
  join(APP_SUPPORT_DIR, "daemon.lock");

function processIsAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function acquireDaemonLock() {
  mkdirSync(APP_SUPPORT_DIR, { recursive: true, mode: 0o700 });
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const fd = openSync(DAEMON_LOCK_PATH, "wx", 0o600);
      writeFileSync(fd, `${process.pid}\n`);
      closeSync(fd);
      return true;
    } catch (error) {
      if (error?.code !== "EEXIST") throw error;
      let ownerPid = 0;
      try {
        ownerPid = Number(readFileSync(DAEMON_LOCK_PATH, "utf8").trim());
      } catch {}
      if (processIsAlive(ownerPid)) return false;
      unlinkSync(DAEMON_LOCK_PATH);
    }
  }
  return false;
}

function releaseDaemonLock() {
  if (!existsSync(DAEMON_LOCK_PATH)) return;
  try {
    const ownerPid = Number(readFileSync(DAEMON_LOCK_PATH, "utf8").trim());
    if (ownerPid === process.pid) unlinkSync(DAEMON_LOCK_PATH);
  } catch {}
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

if (!acquireDaemonLock()) {
  process.exit(0);
}

const config = loadRuntimeConfig();
let host;
let server;
let shuttingDown = false;

async function shutdown(reason, exitCode = 0) {
  if (shuttingDown) return;
  shuttingDown = true;
  try {
    await server?.close();
  } catch {}
  try {
    await host?.close();
  } catch {}
  releaseDaemonLock();
  if (
    reason &&
    (process.env.ORIEL_DAEMON_VERBOSE === "1" ||
      process.env.ZHIYOU_DAEMON_VERBOSE === "1")
  ) {
    process.stderr.write(`Oriel daemon stopped: ${reason}\n`);
  }
  process.exit(exitCode);
}

try {
  host = await createStockChromeHost(
    (await endpointReady(config.endpoint))
      ? { connectTo: config.endpoint }
      : {
          chromePath: config.browserPath,
          headless: false,
          keepBrowserAlive: true,
          port: config.port,
          userDataDir: config.profilePath,
        },
  );

  server = await startDaemonRpcServer({
    host,
    socketPath: DAEMON_SOCKET_PATH,
    metadata: {
      browserName: config.browserName,
      endpoint: config.endpoint,
      startedAt: new Date().toISOString(),
    },
    onShutdown: () => {
      setImmediate(() => shutdown("requested"));
    },
  });

  host.closed.then(() => shutdown("browser-closed"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("uncaughtException", (error) => {
    process.stderr.write(`${error?.stack || error}\n`);
    shutdown("uncaught-exception", 1);
  });
  process.on("unhandledRejection", (error) => {
    process.stderr.write(`${error?.stack || error}\n`);
    shutdown("unhandled-rejection", 1);
  });
} catch (error) {
  process.stderr.write(`${error?.stack || error}\n`);
  await shutdown("startup-failed", 1);
}
