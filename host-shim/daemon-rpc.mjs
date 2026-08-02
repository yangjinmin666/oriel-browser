import { randomUUID } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, unlinkSync } from "node:fs";
import { createConnection, createServer } from "node:net";
import { dirname } from "node:path";

const MAX_MESSAGE_BYTES = 16 * 1024 * 1024;
const RPC_TIMEOUT_MS = 30_000;

export const HOST_RPC_METHODS = Object.freeze([
  "getBrowserVersion",
  "listTabs",
  "createTab",
  "snapshot",
  "createTaskSpace",
  "useTaskSpace",
  "listTaskSpaces",
  "closeTaskSpace",
  "completeTaskSpace",
  "claimTaskSpace",
  "handOffTaskSpace",
  "takeOverTaskSpace",
  "trackActiveTarget",
  "upgradeBrowser",
]);

const CONTROL_RPC_METHODS = new Set([
  "control.task.set-policy",
  "control.task.approve-next",
  "control.task.recover",
  "control.task.audit",
]);

const TASK_SCOPED_RPC_METHODS = new Set([
  "listTabs",
  "createTab",
  "snapshot",
  "trackActiveTarget",
]);

// Opening a page is a read: it fetches a document, it does not act on the
// user's behalf. Gating it made every task block on its first step, so an
// unattended agent stopped before it could observe anything. The actions that
// carry consequence — clicks, typing, form submission, downloads — are gated
// separately through authorizeCDP, which keeps its own read-only allowlist.
//
// Only http(s) and about:blank are treated as reads here. Schemes such as
// file:, chrome:, devtools: and javascript: reach beyond page content or run
// script, so they still require approval.
function isSafeLocalTab(url) {
  if (typeof url !== "string") return false;
  const value = url.trim();
  if (value === "") return true;
  if (value.toLowerCase() === "about:blank") return true;
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    return false;
  }
  return parsed.protocol === "http:" || parsed.protocol === "https:";
}

function isHardStop(error) {
  return /SIDECAR_AGENT_CONTROL_REQUIRED/.test(
    error instanceof Error ? error.message : String(error),
  );
}

function writeMessage(socket, message) {
  if (socket.destroyed || !socket.writable) return false;
  return socket.write(`${JSON.stringify(message)}\n`);
}

function attachMessageReader(socket, onMessage, onProtocolError) {
  let buffer = "";
  socket.setEncoding("utf8");
  socket.on("data", (chunk) => {
    buffer += chunk;
    if (Buffer.byteLength(buffer) > MAX_MESSAGE_BYTES) {
      onProtocolError(new Error("daemon message exceeded size limit"));
      socket.destroy();
      return;
    }
    while (true) {
      const newline = buffer.indexOf("\n");
      if (newline < 0) break;
      const line = buffer.slice(0, newline);
      buffer = buffer.slice(newline + 1);
      if (!line) continue;
      try {
        onMessage(JSON.parse(line));
      } catch {
        onProtocolError(new Error("daemon received invalid JSON"));
      }
    }
  });
}

function errorPayload(error) {
  return {
    message: error instanceof Error ? error.message : String(error),
    ...(error?.code ? { code: error.code } : {}),
  };
}

export async function startDaemonRpcServer({
  host,
  socketPath,
  metadata = {},
  governance = null,
  onShutdown = () => {},
}) {
  mkdirSync(dirname(socketPath), { recursive: true, mode: 0o700 });
  if (existsSync(socketPath)) unlinkSync(socketPath);

  const clients = new Set();
  const cdpRoutes = new Map();
  const sessionOwners = new Map();
  let wireMessageId = 1_000_000_000;

  function sendToClient(client, message) {
    return writeMessage(client.socket, message);
  }

  function broadcast(message) {
    for (const client of clients) sendToClient(client, message);
  }

  async function ensureGovernedTask(client) {
    if (!governance || client.activeTaskRuntimeId) return;

    // The stock browser host creates `oriel-default` lazily on the first
    // browser-scoped call. Synchronize that host-owned fallback into the
    // governance layer before evaluating any write policy. This preserves the
    // default isolation guarantee without treating the implicit space as an
    // ungoverned browser session.
    await client.host.listTabs();
    const listed = await client.host.listTaskSpaces();
    const fallback = listed?.taskSpaces?.find(
      (space) => space?.name === "oriel-default",
    );
    const runtimeId = Number(fallback?.id);
    if (!Number.isInteger(runtimeId) || runtimeId <= 0) {
      throw new Error("A named Oriel task space is required before a browser change");
    }
    await client.host.useTaskSpace(runtimeId);
    client.activeTaskRuntimeId = runtimeId;
    governance.registerTask(fallback);
  }

  host.onCDPMessage = (raw) => {
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      parsed = null;
    }
    const route = parsed?.id !== undefined ? cdpRoutes.get(parsed.id) : null;
    if (route) {
      cdpRoutes.delete(parsed.id);
      if (
        route.method === "Target.attachToTarget" &&
        typeof parsed?.result?.sessionId === "string"
      ) {
        sessionOwners.set(parsed.result.sessionId, route.client);
      }
      if (
        route.method === "Target.detachFromTarget" &&
        typeof route.params?.sessionId === "string"
      ) {
        sessionOwners.delete(route.params.sessionId);
      }
      parsed.id = route.originalId;
      sendToClient(route.client, {
        type: "cdp",
        payload: JSON.stringify(parsed),
      });
      return;
    }
    if (typeof parsed?.sessionId === "string") {
      const owner = sessionOwners.get(parsed.sessionId);
      if (owner) {
        sendToClient(owner, { type: "cdp", payload: raw });
      }
      return;
    }
    if (
      parsed?.method === "Target.detachedFromTarget" &&
      typeof parsed?.params?.sessionId === "string"
    ) {
      sessionOwners.delete(parsed.params.sessionId);
    }
    broadcast({ type: "cdp", payload: raw });
  };

  host.onSendCDPMessageError = (message, code) => {
    broadcast({ type: "cdp-error", message: String(message), code });
  };

  const server = createServer((socket) => {
    const client = {
      id: randomUUID(),
      socket,
      activeTaskRuntimeId: null,
      host:
        typeof host.forScope === "function"
          ? host.forScope(randomUUID())
          : host,
    };
    clients.add(client);

    const removeClient = () => {
      clients.delete(client);
      for (const [wireId, route] of cdpRoutes) {
        if (route.client === client) cdpRoutes.delete(wireId);
      }
      for (const [sessionId, owner] of sessionOwners) {
        if (owner === client) sessionOwners.delete(sessionId);
      }
    };
    socket.on("close", removeClient);
    socket.on("error", () => {});

    attachMessageReader(
      socket,
      async (message) => {
        if (message?.type === "cdp-send") {
          try {
            const payload = JSON.parse(message.payload);
            if (payload?.id === undefined) {
              throw new Error("CDP request is missing an id");
            }
            if (
              payload.method === "Target.activateTarget" &&
              typeof payload.params?.targetId === "string" &&
              typeof client.host.trackActiveTarget === "function"
            ) {
              await client.host.trackActiveTarget(payload.params.targetId);
            }
            const sessionOwner = payload.sessionId
              ? sessionOwners.get(payload.sessionId)
              : null;
            if (sessionOwner && sessionOwner !== client) {
              sendToClient(client, {
                type: "cdp",
                payload: JSON.stringify({
                  id: payload.id,
                  error: {
                    message: "CDP session belongs to another Oriel client",
                  },
                }),
              });
              return;
            }
            await ensureGovernedTask(client);
            governance?.authorizeCDP(
              client.activeTaskRuntimeId,
              payload.method,
            );
            const wireId = wireMessageId++;
            cdpRoutes.set(wireId, {
              client,
              originalId: payload.id,
              method: payload.method,
              params: payload.params,
            });
            payload.id = wireId;
            host.sendCDPMessage(JSON.stringify(payload));
          } catch (error) {
            if (isHardStop(error)) {
              governance?.hardStop(client.activeTaskRuntimeId);
            } else if (!error?.code?.startsWith("ORIEL_")) {
              governance?.recordFailure(client.activeTaskRuntimeId, "cdp-command");
            }
            sendToClient(client, {
              type: "cdp-error",
              ...errorPayload(error),
            });
          }
          return;
        }

        if (message?.type !== "rpc" || message.id === undefined) return;
        try {
          let result;
          if (message.method === "daemon.ping") {
            result = {
              ok: true,
              pid: process.pid,
              clients: clients.size,
              ...metadata,
            };
          } else if (message.method === "daemon.shutdown") {
            result = { done: true };
            queueMicrotask(onShutdown);
          } else if (CONTROL_RPC_METHODS.has(message.method)) {
            if (!governance) {
              throw new Error("daemon governance is unavailable");
            }
            const args = Array.isArray(message.args) ? message.args : [];
            if (message.method === "control.task.audit" && args.length === 0) {
              result = governance.listAudit();
            } else {
              const runtimeId = Number(args[0]);
              if (!Number.isInteger(runtimeId) || runtimeId <= 0) {
                throw new Error("task governance requires a numeric task space id");
              }
              if (message.method === "control.task.set-policy") {
                result = governance.setPolicy(runtimeId, args[1]);
              } else if (message.method === "control.task.approve-next") {
                result = governance.approveNextAction(runtimeId);
              } else if (message.method === "control.task.recover") {
                result = governance.recover(runtimeId);
              } else {
                result = governance.listAudit(runtimeId);
              }
            }
          } else {
            if (!HOST_RPC_METHODS.includes(message.method)) {
              throw new Error(
                `daemon method is not allowed: ${message.method}`,
              );
            }
            const args = Array.isArray(message.args) ? message.args : [];
            if (TASK_SCOPED_RPC_METHODS.has(message.method)) {
              await ensureGovernedTask(client);
            }
            const method = client.host[message.method];
            if (typeof method !== "function") {
              throw new Error(
                `daemon host does not implement ${message.method}`,
              );
            }
            if (
              message.method === "createTab" &&
              !isSafeLocalTab(args[0] ?? "about:blank")
            ) {
              governance?.authorizeRpcWrite(
                client.activeTaskRuntimeId,
                "open-tab",
              );
            }
            result = await method(...args);

            if (message.method === "createTaskSpace") {
              const runtimeId = Number(result?.id);
              if (Number.isInteger(runtimeId) && runtimeId > 0) {
                client.activeTaskRuntimeId = runtimeId;
                governance?.registerTask(result);
              }
            } else if (
              message.method === "useTaskSpace" ||
              message.method === "claimTaskSpace"
            ) {
              const runtimeId = Number(result?.id);
              if (Number.isInteger(runtimeId) && runtimeId > 0) {
                client.activeTaskRuntimeId = runtimeId;
                governance?.registerTask(result);
              }
            } else if (message.method === "listTaskSpaces") {
              result = {
                ...result,
                taskSpaces: Array.isArray(result?.taskSpaces)
                  ? result.taskSpaces.map((space) =>
                      governance
                        ? governance.decorateTaskSpace(space)
                        : space,
                    )
                  : [],
              };
            } else if (message.method === "createTab") {
              governance?.notePrepared(client.activeTaskRuntimeId);
            } else if (message.method === "handOffTaskSpace") {
              if (result?.done !== false) {
                governance?.handOff(client.activeTaskRuntimeId);
              }
            } else if (message.method === "takeOverTaskSpace") {
              governance?.takeOver(client.activeTaskRuntimeId);
            } else if (message.method === "completeTaskSpace") {
              if (result?.done !== false) {
                governance?.complete(client.activeTaskRuntimeId);
              }
            } else if (message.method === "closeTaskSpace") {
              if (result?.done !== false) {
                governance?.close(client.activeTaskRuntimeId);
                client.activeTaskRuntimeId = null;
              }
            }
          }
          sendToClient(client, {
            type: "rpc-result",
            id: message.id,
            result,
          });
        } catch (error) {
          if (isHardStop(error)) {
            governance?.hardStop(client.activeTaskRuntimeId);
          } else if (!error?.code?.startsWith("ORIEL_")) {
            governance?.recordFailure(client.activeTaskRuntimeId, "task-command");
          }
          sendToClient(client, {
            type: "rpc-error",
            id: message.id,
            error: errorPayload(error),
          });
        }
      },
      (error) => {
        sendToClient(client, {
          type: "protocol-error",
          error: errorPayload(error),
        });
      },
    );
  });

  await new Promise((resolve, reject) => {
    const onError = (error) => {
      server.off("listening", onListening);
      reject(error);
    };
    const onListening = () => {
      server.off("error", onError);
      resolve();
    };
    server.once("error", onError);
    server.once("listening", onListening);
    server.listen(socketPath);
  });
  chmodSync(socketPath, 0o600);

  return {
    socketPath,
    get clientCount() {
      return clients.size;
    },
    async close() {
      for (const client of clients) client.socket.destroy();
      await new Promise((resolve) => server.close(resolve));
      if (existsSync(socketPath)) unlinkSync(socketPath);
    },
  };
}

export async function connectDaemonRpc({
  socketPath,
  connectTimeoutMs = 1_500,
  rpcTimeoutMs = RPC_TIMEOUT_MS,
}) {
  const socket = createConnection(socketPath);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.destroy();
      reject(new Error("连接 Oriel 后台超时"));
    }, connectTimeoutMs);
    const done = (fn) => (value) => {
      clearTimeout(timer);
      socket.off("connect", onConnect);
      socket.off("error", onError);
      fn(value);
    };
    const onConnect = done(resolve);
    const onError = done(reject);
    socket.once("connect", onConnect);
    socket.once("error", onError);
  });

  let requestId = 0;
  const pending = new Map();
  let closed = false;

  const rejectPending = (error) => {
    for (const entry of pending.values()) {
      clearTimeout(entry.timer);
      entry.reject(error);
    }
    pending.clear();
  };

  const client = {
    onCDPMessage: null,
    onSendCDPMessageError: null,

    sendCDPMessage(payload) {
      if (closed) throw new Error("Oriel 后台连接已关闭");
      writeMessage(socket, { type: "cdp-send", payload });
    },

    daemonRequest(method, ...args) {
      if (closed) return Promise.reject(new Error("Oriel 后台连接已关闭"));
      const id = ++requestId;
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          pending.delete(id);
          reject(new Error(`Oriel 后台请求超时: ${method}`));
        }, rpcTimeoutMs);
        pending.set(id, { resolve, reject, timer });
        writeMessage(socket, { type: "rpc", id, method, args });
      });
    },

    async close() {
      if (closed) return;
      closed = true;
      socket.end();
      rejectPending(new Error("Oriel 后台连接已关闭"));
    },
  };

  for (const method of HOST_RPC_METHODS) {
    client[method] = (...args) => client.daemonRequest(method, ...args);
  }

  attachMessageReader(
    socket,
    (message) => {
      if (message?.type === "cdp") {
        client.onCDPMessage?.(message.payload);
        return;
      }
      if (message?.type === "cdp-error") {
        client.onSendCDPMessageError?.(message.message, message.code);
        return;
      }
      if (message?.type !== "rpc-result" && message?.type !== "rpc-error")
        return;
      const entry = pending.get(message.id);
      if (!entry) return;
      pending.delete(message.id);
      clearTimeout(entry.timer);
      if (message.type === "rpc-error") {
        const error = new Error(message.error?.message || "Oriel 后台请求失败");
        if (message.error?.code) error.code = message.error.code;
        entry.reject(error);
      } else {
        entry.resolve(message.result);
      }
    },
    (error) => {
      client.onSendCDPMessageError?.(error.message);
    },
  );

  socket.on("close", () => {
    if (closed) return;
    closed = true;
    rejectPending(new Error("Oriel 后台连接意外关闭"));
  });
  socket.on("error", (error) => {
    if (!closed) rejectPending(error);
  });

  return client;
}
