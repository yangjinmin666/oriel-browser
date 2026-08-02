import assert from "node:assert/strict";
import { mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { connectDaemonRpc, startDaemonRpcServer } from "./daemon-rpc.mjs";
import { createTaskGovernance } from "./task-governance.mjs";

function createFakeHost() {
  const spaces = new Map();
  const selectedByScope = new Map();
  const trackedTargets = [];
  const openedTabs = [];
  let sequence = 0;

  const host = {
    onCDPMessage: null,
    onSendCDPMessageError: null,
    sendCDPMessage(raw) {
      const request = JSON.parse(raw);
      queueMicrotask(() => {
        const result =
          request.method === "Target.attachToTarget"
            ? { sessionId: `session-${request.params?.owner}` }
            : { owner: request.params?.owner };
        host.onCDPMessage?.(
          JSON.stringify({
            id: request.id,
            result,
          }),
        );
      });
    },
    forScope(scopeId) {
      return {
        async trackActiveTarget(targetId) {
          trackedTargets.push({ scopeId, targetId });
        },
        async createTaskSpace(name) {
          const space = {
            id: ++sequence,
            taskId: name,
            name,
            ownership: "agent",
          };
          spaces.set(space.id, space);
          selectedByScope.set(scopeId, space.id);
          return space;
        },
        async useTaskSpace(nameOrId) {
          const space = [...spaces.values()].find(
            (entry) => entry.id === Number(nameOrId) || entry.name === nameOrId,
          );
          if (!space) throw new Error(`missing space: ${nameOrId}`);
          selectedByScope.set(scopeId, space.id);
          return space;
        },
        async listTaskSpaces() {
          return { taskSpaces: [...spaces.values()] };
        },
        async createTab(url) {
          openedTabs.push({ scopeId, url });
          return { targetId: `target-${openedTabs.length}`, url };
        },
        async listTabs() {
          const space = spaces.get(selectedByScope.get(scopeId));
          return {
            tabs: [
              {
                targetId: `target-${space?.id ?? "none"}`,
                title: space?.name ?? "none",
                active: true,
              },
            ],
          };
        },
      };
    },
    async close() {},
  };
  return { host, trackedTargets, openedTabs };
}

async function withDaemon(run) {
  const directory = mkdtempSync(join(tmpdir(), "oriel-daemon-test-"));
  const socketPath = join(directory, "daemon.sock");
  const { host, trackedTargets } = createFakeHost();
  const server = await startDaemonRpcServer({ host, socketPath });
  try {
    await run({ host, trackedTargets, server, socketPath });
  } finally {
    await server.close();
    rmSync(directory, { recursive: true, force: true });
  }
}

test("daemon socket is private to the current user", async () => {
  await withDaemon(async ({ socketPath }) => {
    assert.equal(statSync(socketPath).mode & 0o777, 0o600);
  });
});

test("task spaces survive independent client connections", async () => {
  await withDaemon(async ({ socketPath }) => {
    const first = await connectDaemonRpc({ socketPath });
    const created = await first.createTaskSpace("persistent-space");
    await first.close();

    const second = await connectDaemonRpc({ socketPath });
    const listed = await second.listTaskSpaces();
    assert.equal(listed.taskSpaces.length, 1);
    assert.equal(listed.taskSpaces[0].id, created.id);
    assert.equal(listed.taskSpaces[0].name, "persistent-space");
    await second.close();
  });
});

test("parallel clients keep independent active task spaces", async () => {
  await withDaemon(async ({ socketPath }) => {
    const first = await connectDaemonRpc({ socketPath });
    const second = await connectDaemonRpc({ socketPath });
    await first.createTaskSpace("first-space");
    await second.createTaskSpace("second-space");

    assert.equal((await first.listTabs()).tabs[0].title, "first-space");
    assert.equal((await second.listTabs()).tabs[0].title, "second-space");
    await first.close();
    await second.close();
  });
});

test("CDP ids are rewritten and responses return only to their client", async () => {
  await withDaemon(async ({ socketPath }) => {
    const first = await connectDaemonRpc({ socketPath });
    const second = await connectDaemonRpc({ socketPath });

    const firstResponse = new Promise((resolve) => {
      first.onCDPMessage = (raw) => resolve(JSON.parse(raw));
    });
    const secondResponse = new Promise((resolve) => {
      second.onCDPMessage = (raw) => resolve(JSON.parse(raw));
    });
    first.sendCDPMessage(
      JSON.stringify({
        id: 1,
        method: "Runtime.evaluate",
        params: { owner: "first" },
      }),
    );
    second.sendCDPMessage(
      JSON.stringify({
        id: 1,
        method: "Runtime.evaluate",
        params: { owner: "second" },
      }),
    );

    assert.deepEqual(await firstResponse, {
      id: 1,
      result: { owner: "first" },
    });
    assert.deepEqual(await secondResponse, {
      id: 1,
      result: { owner: "second" },
    });
    await first.close();
    await second.close();
  });
});

test("switching a tab records the selected target before forwarding CDP", async () => {
  await withDaemon(async ({ socketPath, trackedTargets }) => {
    const client = await connectDaemonRpc({ socketPath });
    const response = new Promise((resolve) => {
      client.onCDPMessage = (raw) => resolve(JSON.parse(raw));
    });

    client.sendCDPMessage(
      JSON.stringify({
        id: 7,
        method: "Target.activateTarget",
        params: { targetId: "target-selected" },
      }),
    );

    assert.deepEqual(await response, {
      id: 7,
      result: {},
    });
    assert.equal(trackedTargets.length, 1);
    assert.equal(trackedTargets[0].targetId, "target-selected");
    await client.close();
  });
});

test("session events are routed only to the client that attached", async () => {
  await withDaemon(async ({ host, socketPath }) => {
    const first = await connectDaemonRpc({ socketPath });
    const second = await connectDaemonRpc({ socketPath });
    const firstMessages = [];
    const secondMessages = [];
    first.onCDPMessage = (raw) => firstMessages.push(JSON.parse(raw));
    second.onCDPMessage = (raw) => secondMessages.push(JSON.parse(raw));

    first.sendCDPMessage(
      JSON.stringify({
        id: 1,
        method: "Target.attachToTarget",
        params: { owner: "first" },
      }),
    );
    await new Promise((resolve) => setTimeout(resolve, 10));
    host.onCDPMessage(
      JSON.stringify({
        method: "Network.requestWillBeSent",
        sessionId: "session-first",
        params: { requestId: "private-to-first" },
      }),
    );
    await new Promise((resolve) => setTimeout(resolve, 10));

    assert.equal(
      firstMessages.some(
        (message) => message.params?.requestId === "private-to-first",
      ),
      true,
    );
    assert.equal(
      secondMessages.some(
        (message) => message.params?.requestId === "private-to-first",
      ),
      false,
    );
    await first.close();
    await second.close();
  });
});

test("one client cannot send commands through another client's CDP session", async () => {
  await withDaemon(async ({ socketPath }) => {
    const first = await connectDaemonRpc({ socketPath });
    const second = await connectDaemonRpc({ socketPath });

    first.sendCDPMessage(
      JSON.stringify({
        id: 1,
        method: "Target.attachToTarget",
        params: { owner: "first" },
      }),
    );
    await new Promise((resolve) => setTimeout(resolve, 10));

    const blocked = new Promise((resolve) => {
      second.onCDPMessage = (raw) => resolve(JSON.parse(raw));
    });
    second.sendCDPMessage(
      JSON.stringify({
        id: 2,
        method: "Runtime.evaluate",
        sessionId: "session-first",
        params: { expression: "document.cookie" },
      }),
    );
    assert.match((await blocked).error.message, /belongs to another/);
    await first.close();
    await second.close();
  });
});

test("daemon rejects methods outside the explicit allowlist", async () => {
  await withDaemon(async ({ socketPath }) => {
    const client = await connectDaemonRpc({ socketPath });
    await assert.rejects(
      client.daemonRequest("readArbitraryFile", "/etc/passwd"),
      /method is not allowed/,
    );
    await client.close();
  });
});

test("task approval is available only through the control-plane RPC", async () => {
  const directory = mkdtempSync(join(tmpdir(), "oriel-governed-daemon-test-"));
  const socketPath = join(directory, "daemon.sock");
  const { host } = createFakeHost();
  const governance = createTaskGovernance({
    statePath: join(directory, "task-governance.json"),
    profileId: "test-profile",
    sessionId: "test-session",
  });
  const server = await startDaemonRpcServer({
    host,
    socketPath,
    governance,
  });
  try {
    const client = await connectDaemonRpc({ socketPath });
    const task = await client.createTaskSpace("approval-boundary");

    assert.equal(client.approveTaskAction, undefined);
    await assert.rejects(
      client.daemonRequest("approveTaskAction", task.id),
      /method is not allowed/,
    );

    await client.daemonRequest("control.task.approve-next", task.id);
    const listed = await client.listTaskSpaces();
    assert.equal(listed.taskSpaces[0].lifecycle.approvalAvailable, true);
    await client.close();
  } finally {
    await server.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test("opening a web page is a read, but other schemes still need approval", async () => {
  const directory = mkdtempSync(join(tmpdir(), "oriel-open-tab-test-"));
  const socketPath = join(directory, "daemon.sock");
  const { host, openedTabs } = createFakeHost();
  const governance = createTaskGovernance({
    statePath: join(directory, "task-governance.json"),
    profileId: "test-profile",
    sessionId: "test-session",
  });
  const server = await startDaemonRpcServer({ host, socketPath, governance });
  try {
    const client = await connectDaemonRpc({ socketPath });
    await client.createTaskSpace("unattended-read");

    // A fresh task defaults to requires-approval and holds no approval, yet an
    // agent must still be able to reach a page and observe it.
    await client.daemonRequest("createTab", "https://example.com/");
    await client.daemonRequest("createTab", "about:blank");
    assert.deepEqual(
      openedTabs.map((tab) => tab.url),
      ["https://example.com/", "about:blank"],
    );

    for (const url of [
      "file:///etc/passwd",
      "javascript:fetch('https://evil.test')",
      "chrome://settings",
      "devtools://devtools/bundled/inspector.html",
    ]) {
      await assert.rejects(
        client.daemonRequest("createTab", url),
        (error) => error.code === "ORIEL_APPROVAL_REQUIRED",
        `${url} must still require approval`,
      );
    }
    assert.equal(openedTabs.length, 2);

    await client.close();
  } finally {
    await server.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test("daemon allows background target tracking without activating a tab", async () => {
  await withDaemon(async ({ socketPath, trackedTargets }) => {
    const client = await connectDaemonRpc({ socketPath });
    await client.trackActiveTarget("boss-background-target");

    assert.deepEqual(trackedTargets, [
      {
        scopeId: trackedTargets[0].scopeId,
        targetId: "boss-background-target",
      },
    ]);
    await client.close();
  });
});
