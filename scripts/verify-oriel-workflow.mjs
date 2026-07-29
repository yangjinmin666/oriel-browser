#!/usr/bin/env node

// Product-level smoke test. Unlike the inherited ego-lite real-browser suite,
// this runs the runtime bundled inside Oriel.app through Oriel's own daemon.
// It never connects to an existing user browser or profile.

import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const appPath = process.argv[2] || join(root, "build", "Oriel.app");
const runtime = join(appPath, "Contents", "Resources", "Runtime");
const bundledNode = join(runtime, "bin", "node");
const bundledCli = join(runtime, "oriel.mjs");
const chromePath =
  process.env.ORIEL_E2E_CHROME_PATH ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function run(command, args, { env, input, timeoutMs = 30_000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(new Error(`${command} timed out after ${timeoutMs}ms`));
    }, timeoutMs);

    child.stdout.on("data", (chunk) => (stdout += chunk));
    child.stderr.on("data", (chunk) => (stderr += chunk));
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) return resolve({ stdout, stderr });
      reject(
        new Error(
          `${command} exited with ${code}\nstdout:\n${stdout}\nstderr:\n${stderr}`,
        ),
      );
    });
    child.stdin.end(input || "");
  });
}

function startFixture() {
  const server = createServer((request, response) => {
    if (request.url === "/healthz") {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({ ok: true }));
      return;
    }
    const fallback = request.url?.startsWith("/fallback");
    const title = fallback
      ? "Oriel default isolation"
      : "Oriel packaged workflow";
    response.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    response.end(`<!doctype html>
      <html><head><title>${title}</title></head>
      <body><main><h1>${title}</h1><p>Browser snapshot smoke test.</p></main></body></html>`);
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      resolve({ server, url: `http://127.0.0.1:${address.port}/` });
    });
  });
}

function findFreePort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      server.close((error) => (error ? reject(error) : resolve(address.port)));
    });
  });
}

async function closeChrome(endpoint) {
  try {
    const response = await fetch(`${endpoint}/json/version`);
    const version = await response.json();
    if (!version.webSocketDebuggerUrl) return;
    const socket = new WebSocket(version.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => {
      socket.addEventListener("open", resolve, { once: true });
      socket.addEventListener("error", reject, { once: true });
    });
    socket.send(JSON.stringify({ id: 1, method: "Browser.close" }));
    await new Promise((resolve) => {
      socket.addEventListener("message", resolve, { once: true });
      setTimeout(resolve, 1_000);
    });
    socket.close();
  } catch {
    // Cleanup must not mask the actual product assertion failure.
  }
}

async function chromeStillRunning(endpoint) {
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${endpoint}/json/version`, {
        signal: AbortSignal.timeout(250),
      });
      if (!response.ok) return false;
    } catch {
      return false;
    }
    await sleep(250);
  }
  return true;
}

async function terminateTemporaryChrome(profilePath) {
  const { stdout } = await run("/bin/ps", ["-axo", "pid=,command="], {
    timeoutMs: 5_000,
  });
  const pids = stdout
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.includes(`--user-data-dir=${profilePath}`))
    .map((line) => Number(line.split(/\s+/, 1)[0]))
    .filter((pid) => Number.isInteger(pid) && pid > 0);
  for (const pid of pids) {
    try {
      process.kill(pid, "SIGTERM");
    } catch {}
  }
  if (pids.length) await sleep(500);
  return pids.length;
}

async function removeTemporaryRoot(path) {
  let lastError;
  for (let attempt = 0; attempt < 20; attempt++) {
    try {
      await rm(path, { recursive: true, force: true, maxRetries: 0 });
      return;
    } catch (error) {
      lastError = error;
      await sleep(250);
    }
  }
  throw lastError;
}

function resultFrom(output, phase) {
  const line = output
    .split("\n")
    .find((item) => item.startsWith("ORIEL_WORKFLOW_RESULT "));
  assert(line, `${phase} CLI call did not emit its workflow result`);
  return JSON.parse(line.slice("ORIEL_WORKFLOW_RESULT ".length));
}

async function debugTargets(endpoint) {
  const response = await fetch(`${endpoint}/json/list`);
  assert(response.ok, `Could not inspect temporary Chrome targets: ${response.status}`);
  return response.json();
}

async function main() {
  assert(existsSync(bundledNode), `Bundled Node is missing: ${bundledNode}`);
  assert(existsSync(bundledCli), `Bundled Oriel CLI is missing: ${bundledCli}`);
  assert(
    existsSync(chromePath),
    `Google Chrome is required for this smoke test: ${chromePath}`,
  );

  const temporaryRoot = await mkdtemp(join(tmpdir(), "oriel-packaged-workflow-"));
  const port = await findFreePort();
  const endpoint = `http://127.0.0.1:${port}`;
  const configPath = join(temporaryRoot, "config.json");
  const socketPath = join(temporaryRoot, "daemon.sock");
  const lockPath = join(temporaryRoot, "daemon.lock");
  const logPath = join(temporaryRoot, "daemon.log");
  const profilePath = join(temporaryRoot, "profile");
  let fixture;

  const environment = {
    ...process.env,
    ORIEL_CONFIG: configPath,
    ORIEL_DAEMON_SOCKET: socketPath,
    ORIEL_DAEMON_LOCK: lockPath,
    ORIEL_DAEMON_LOG: logPath,
    ORIEL_BROWSER_HEADLESS: "1",
  };
  // Keep the real macOS HOME so Chromium can use the user's normal Keychain
  // service. The browser profile above is still fully temporary and isolated;
  // overriding HOME creates a non-representative machine state where Chromium
  // can fail before Oriel has a chance to exercise the product flow.

  try {
    fixture = await startFixture();
    await writeFile(
      configPath,
      `${JSON.stringify(
        {
          browserId: "oriel-packaged-smoke",
          browserName: "Oriel packaged smoke Chrome",
          browserPath: chromePath,
          endpoint,
          port,
          profilePath,
        },
        null,
        2,
      )}\n`,
    );

    const taskName = "oriel-packaged-workflow";
    const first = await run(bundledNode, [bundledCli, "nodejs"], {
      env: environment,
      input: `
        const task = await taskSpaces.useOrCreate(${JSON.stringify(taskName)});
        const tab = await browser.openOrReuseTab(${JSON.stringify(fixture.url)}, { wait: true, timeout: 10000 });
        const snapshot = await page.snapshot({ scope: "full_page" });
        const currentUrl = await page.url();
        const tabs = await browser.listTabs();
        if (!snapshot.includes("Oriel packaged workflow") || currentUrl !== ${JSON.stringify(fixture.url)}) throw new Error("first CLI call did not reach the fixture page; opened=" + tab.targetId + "; page=" + currentUrl + "; tabs=" + JSON.stringify(tabs) + "; preview=" + JSON.stringify(snapshot.slice(0, 500)));
        console.log("ORIEL_WORKFLOW_RESULT " + JSON.stringify({ phase: "first", taskId: task.id, targetId: tab.targetId, snapshotLength: snapshot.length }));
      `,
    });
    const firstResult = resultFrom(first.stdout, "first");
    assert(firstResult.snapshotLength > 0, "first snapshot was empty");

    const second = await run(bundledNode, [bundledCli, "nodejs"], {
      env: environment,
      input: `
        const task = await taskSpaces.useOrCreate(${JSON.stringify(taskName)});
        const tab = await browser.currentTab();
        const snapshot = await page.snapshot({ scope: "full_page" });
        const currentUrl = await page.url();
        if (!snapshot.includes("Oriel packaged workflow") || currentUrl !== ${JSON.stringify(fixture.url)}) throw new Error("second CLI call did not reuse the fixture page; page=" + currentUrl + "; preview=" + JSON.stringify(snapshot.slice(0, 500)));
        if (!tab?.targetId) throw new Error("reused task has no active page");
        console.log("ORIEL_WORKFLOW_RESULT " + JSON.stringify({ phase: "second", taskId: task.id, targetId: tab.targetId, snapshotLength: snapshot.length }));
        await taskSpaces.complete(task.id, { keep: false });
      `,
    });
    const secondResult = resultFrom(second.stdout, "second");
    assert(
      firstResult.taskId === secondResult.taskId,
      "second CLI call did not reuse the same task space",
    );
    assert(
      firstResult.targetId === secondResult.targetId,
      "second CLI call did not reuse the existing page",
    );
    assert(secondResult.snapshotLength > 0, "reused snapshot was empty");

    const baselineTargets = await debugTargets(endpoint);
    const baselineTargetIds = new Set(
      baselineTargets.map((target) => target.id).filter(Boolean),
    );
    assert(
      baselineTargetIds.size > 0,
      "temporary Chrome had no pre-existing tab to protect",
    );

    const fallbackUrl = new URL("fallback", fixture.url).href;
    const fallbackFirst = await run(bundledNode, [bundledCli, "nodejs"], {
      env: environment,
      input: `
        const before = await browser.listTabs();
        if (before.length !== 0) throw new Error("implicit task space exposed pre-existing browser tabs: " + JSON.stringify(before));
        const tab = await browser.openOrReuseTab(${JSON.stringify(fallbackUrl)}, { wait: true, timeout: 10000 });
        const snapshot = await page.snapshot({ scope: "full_page" });
        if (!snapshot.includes("Oriel default isolation")) throw new Error("implicit task space snapshot missed its own page");
        console.log("ORIEL_WORKFLOW_RESULT " + JSON.stringify({ phase: "fallback-first", targetId: tab.targetId, snapshotLength: snapshot.length }));
      `,
    });
    const fallbackFirstResult = resultFrom(
      fallbackFirst.stdout,
      "fallback-first",
    );

    const fallbackSecond = await run(bundledNode, [bundledCli, "nodejs"], {
      env: environment,
      input: `
        const tabs = await browser.listTabs();
        const tab = await browser.currentTab();
        const snapshot = await page.snapshot({ scope: "full_page" });
        if (tabs.length !== 1 || !tab?.targetId) throw new Error("implicit task space did not retain exactly its own page: " + JSON.stringify(tabs));
        if (!snapshot.includes("Oriel default isolation")) throw new Error("implicit task space did not reuse its page");
        console.log("ORIEL_WORKFLOW_RESULT " + JSON.stringify({ phase: "fallback-second", targetId: tab.targetId, snapshotLength: snapshot.length }));
        await taskSpaces.complete("oriel-default", { keep: false });
      `,
    });
    const fallbackSecondResult = resultFrom(
      fallbackSecond.stdout,
      "fallback-second",
    );
    assert(
      fallbackFirstResult.targetId === fallbackSecondResult.targetId,
      "implicit task space did not reuse the same owned page",
    );

    const finalTargets = await debugTargets(endpoint);
    const finalTargetIds = new Set(
      finalTargets.map((target) => target.id).filter(Boolean),
    );
    for (const targetId of baselineTargetIds) {
      assert(
        finalTargetIds.has(targetId),
        "closing an Oriel task space closed a pre-existing browser tab",
      );
    }
    assert(
      !finalTargetIds.has(fallbackFirstResult.targetId),
      "closing the implicit task space left its owned page open",
    );

    const daemonLog = await readFile(logPath, "utf8").catch(() => "");
    assert(!/Error:|Unhandled|uncaught/i.test(daemonLog), "daemon log contains an error");
    process.stdout.write(
      "Oriel packaged workflow passed: named and implicit spaces reused only their own pages, protected pre-existing tabs, and returned semantic snapshots.\n",
    );
  } finally {
    await run(bundledNode, [bundledCli, "--daemon-stop"], {
      env: environment,
      timeoutMs: 8_000,
    }).catch(() => {});
    await closeChrome(endpoint);
    if (await chromeStillRunning(endpoint)) {
      await terminateTemporaryChrome(profilePath);
      if (await chromeStillRunning(endpoint)) {
        throw new Error("temporary Chrome did not exit after cleanup");
      }
    }
    await new Promise((resolve) => fixture?.server.close(resolve) || resolve());
    await removeTemporaryRoot(temporaryRoot);
  }
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.stack || error.message : String(error)}\n`);
  process.exitCode = 1;
});
