// 宿主适配层：让 ego-browser 的 MIT runtime 跑在普通 Chrome 上，而不是 ego lite。
//
// runtime 期望一个全局 `ego` 宿主对象（见 src/browser-runtime.ts 的 browserEgo()）。
// 本文件提供该对象的一个实现，全部基于标准 CDP，不依赖 ego lite 浏览器。
//
// 已覆盖 runtime 用到的 14 个宿主方法：
//   通道   sendCDPMessage / onCDPMessage / onSendCDPMessageError
//   信息   getBrowserVersion
//   标签   listTabs / createTab
//   观察   snapshot
//   工作区 createTaskSpace / useTaskSpace / listTaskSpaces / closeTaskSpace /
//         completeTaskSpace / claimTaskSpace / handOffTaskSpace / takeOverTaskSpace
//   杂项   upgradeBrowser（本实现不负责升级，空转）

import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { inspectDebugEndpoint } from "./debug-endpoint.mjs";

const DEFAULT_CHROME =
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 登录态持久化：用一个固定的 Chrome 配置目录，让 Chrome 自己加密保存 cookie
// （macOS 上密钥在钥匙串里）。我们不读、不解密、不落盘任何凭据。
export const DEFAULT_PROFILE_DIR = join(
  process.env.XDG_DATA_HOME || join(homedir(), ".local", "share"),
  "oriel-browser",
  "chrome-profile",
);

// connectTo: 连接一个**已经在运行**的 Chromium 的调试端点，而不是自己启动。
//   例：createStockChromeHost({ connectTo: "http://127.0.0.1:53563" })
// 用途：对付强反爬站点。用户日常浏览器有真实指纹、真实登录态、有的还自带验证码处理，
//   通过得去；全新的匿名 profile 常常连页面都拿不到（BOSS 直聘会直接踢到安全验证页）。
// 代价：需要那个浏览器开着调试端口（无认证），且与用户共享浏览器——隔离性打折。
//   所以这是可选模式，不是默认。
export async function createStockChromeHost(options = {}) {
  const {
    connectTo = null,
    chromePath = DEFAULT_CHROME,
    // 默认有头。国内多个站点会检测无头浏览器：知乎在无头下只返回一张空白页
    // （正文 118 字符 vs 有头 4031 字符，2026-07-28 实测）。无头是提速手段，
    // 不是安全默认值，需要时显式传 headless: true。
    headless = false,
    keepBrowserAlive = false,
    port = 0,
    userDataDir = DEFAULT_PROFILE_DIR,
  } = options;
  let child = null;
  let version;

  if (connectTo) {
    const base = connectTo.replace(/\/$/, "");
    const inspected = await inspectDebugEndpoint(base);
    if (!inspected.ready) throw new Error(`连不上已运行的浏览器: ${base}`);
    version = inspected.version;
  } else {
    mkdirSync(userDataDir, { recursive: true });
    const chosenPort = port || 9500 + Math.floor(Number(process.pid) % 400);
    child = spawn(
      chromePath,
      [
        `--remote-debugging-port=${chosenPort}`,
        "--remote-debugging-address=127.0.0.1",
        `--user-data-dir=${userDataDir}`,
        ...(headless ? ["--headless=new"] : []),
        "--no-first-run",
        "--no-default-browser-check",
        "about:blank",
      ],
      { stdio: "ignore", detached: keepBrowserAlive },
    );
    if (keepBrowserAlive) child.unref();
    version = await waitForEndpoint(chosenPort);
  }
  const ws = new WebSocket(version.webSocketDebuggerUrl);
  await new Promise((res, rej) => {
    ws.onopen = res;
    ws.onerror = rej;
  });
  let resolveClosed;
  let hostClosed = false;
  const closed = new Promise((resolve) => {
    resolveClosed = resolve;
  });

  // runtime 自己的 pending 表走 onCDPMessage；本 shim 内部调用另开一套 id 段，互不干扰。
  let internalId = 900000;
  const internalPending = new Map();

  ws.onmessage = (event) => {
    const raw =
      typeof event.data === "string" ? event.data : String(event.data);
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      parsed = null;
    }
    if (parsed && internalPending.has(parsed.id)) {
      const entry = internalPending.get(parsed.id);
      internalPending.delete(parsed.id);
      parsed.error
        ? entry.reject(new Error(parsed.error.message))
        : entry.resolve(parsed.result);
      return;
    }
    host.onCDPMessage?.(raw);
  };
  ws.onclose = () => {
    if (hostClosed) return;
    hostClosed = true;
    for (const entry of internalPending.values()) {
      entry.reject(new Error("浏览器连接已关闭"));
    }
    internalPending.clear();
    resolveClosed();
  };

  function cdp(method, params = {}, sessionId) {
    const id = internalId++;
    return new Promise((resolve, reject) => {
      internalPending.set(id, { resolve, reject });
      const timer = setTimeout(() => {
        internalPending.delete(id);
        reject(new Error(`shim CDP timeout: ${method}`));
      }, 30000);
      const wrap = (fn) => (v) => {
        clearTimeout(timer);
        fn(v);
      };
      internalPending.set(id, { resolve: wrap(resolve), reject: wrap(reject) });
      ws.send(
        JSON.stringify({
          id,
          method,
          params,
          ...(sessionId ? { sessionId } : {}),
        }),
      );
    });
  }

  const sessions = new Map(); // targetId -> sessionId
  async function attach(targetId) {
    if (sessions.has(targetId)) return sessions.get(targetId);
    const { sessionId } = await cdp("Target.attachToTarget", {
      targetId,
      flatten: true,
    });
    sessions.set(targetId, sessionId);
    return sessionId;
  }

  // ——— 任务空间：用标准 CDP 的 BrowserContext 做隔离 ———
  const spaces = new Map(); // id -> task-space state, including owned target ids
  const defaultScope = Symbol("default-scope");
  const defaultSpaceName = "oriel-default";
  const activeSpaceByScope = new Map();
  let spaceSeq = 0;

  function scopeKey(context) {
    return context?.__orielScopeId ?? defaultScope;
  }

  function activeSpaceId(context) {
    return activeSpaceByScope.get(scopeKey(context)) ?? null;
  }

  function selectSpace(spaceId, context) {
    activeSpaceByScope.set(scopeKey(context), spaceId);
  }

  function clearSpaceSelections(spaceId) {
    for (const [key, selectedId] of activeSpaceByScope) {
      if (selectedId === spaceId) activeSpaceByScope.delete(key);
    }
  }

  function assertAgentControl(space) {
    if (space.ownership !== "agent") {
      throw new Error(
        "SIDECAR_AGENT_CONTROL_REQUIRED: 用户持有控制权，这是硬停止，不要重试",
      );
    }
    return space;
  }

  // A missing task-space selection must never expose the user's current tabs.
  // The fallback is persistent across CLI calls but owns only targets it creates.
  function ensureActiveSpace(context) {
    let space = spaces.get(activeSpaceId(context));
    if (!space) {
      space = [...spaces.values()].find(
        (candidate) => candidate.name === defaultSpaceName,
      );
      if (!space) {
        const id = ++spaceSeq;
        space = {
          id,
          name: defaultSpaceName,
          browserContextId: undefined,
          isolated: false,
          ownership: "agent",
          activeTargetId: null,
          targetIds: new Set(),
          targetInfo: new Map(),
        };
        spaces.set(id, space);
      }
      selectSpace(space.id, context);
    }
    return assertAgentControl(space);
  }

  // Target.getTargets does not expose Chrome's visible-tab selection and its
  // ordering is not a selection contract. Keep the selected target on the
  // task space instead, so listTabs, snapshots, and later CLI calls agree.
  function activeTargetForSpace(space, targets) {
    const remembered = space?.activeTargetId
      ? targets.find((target) => target.targetId === space.activeTargetId)
      : null;
    const chosen = remembered || pickActive(targets);
    if (space && chosen) space.activeTargetId = chosen.targetId;
    return chosen;
  }

  async function pageTargets(browserContextId) {
    const { targetInfos } = await cdp("Target.getTargets", {});
    return targetInfos.filter(
      (t) =>
        t.type === "page" &&
        (!browserContextId || t.browserContextId === browserContextId),
    );
  }

  async function pageTargetsForSpace(space) {
    const targets = await pageTargets(space.browserContextId);
    const owned = space.browserContextId
      ? targets
      : targets.filter((target) => space.targetIds.has(target.targetId));

    // Chrome deliberately omits `hidden: true` targets from Target.getTargets.
    // They are still valid CDP targets, though, and Oriel created and owns their
    // ids. Keep a lightweight local entry so the runtime can attach and operate
    // them without ever making them visible in the user's tab strip.
    const listed = new Set(owned.map((target) => target.targetId));
    for (const targetId of space.targetIds) {
      if (listed.has(targetId)) continue;
      const remembered = space.targetInfo.get(targetId) || {};
      owned.push({
        targetId,
        type: "page",
        title: remembered.title || "",
        url: remembered.url || "about:blank",
      });
    }
    return owned;
  }

  // "当前页"的唯一判定入口。listTabs 的 active 标记和 snapshot 都必须走这里，
  // 否则两边会指向不同的标签页——之前 snapshot 固定取 [0]，取到的是启动时那个
  // about:blank，于是快照拍的是空白页，而 runtime 的点击其实作用在真实页面上。
  function pickActive(targets) {
    const real = targets.filter((t) => t.url && t.url !== "about:blank");
    return real[real.length - 1] ?? targets[targets.length - 1] ?? null;
  }

  const host = {
    onCDPMessage: null,
    onSendCDPMessageError: null,

    // 整个适配层的核心：字符串进，字符串出。
    sendCDPMessage(payload) {
      try {
        ws.send(payload);
      } catch (error) {
        host.onSendCDPMessageError?.(String(error?.message ?? error));
      }
    },

    async getBrowserVersion() {
      return version.Browser;
    },

    // 注意：宿主必须返回 { tabs: [...] } 这种包了一层的形状，不是裸数组。
    // 见 src/browser-runtime.ts:117 —— `result?.tabs || result?.targetInfos || []`。
    // 返回裸数组会让它取不到，报 "no active tab to attach session"。
    async listTabs(context) {
      const space = ensureActiveSpace(context);
      const targets = await pageTargetsForSpace(space);
      const tabs = targets.map((t, index) => {
        let origin = "",
          pathname = "",
          href = t.url;
        try {
          const u = new URL(t.url);
          origin = u.origin;
          pathname = u.pathname;
          href = u.href;
        } catch {}
        return {
          targetId: t.targetId,
          url: t.url,
          title: t.title,
          active: false,
          origin,
          pathname,
          href,
          index,
        };
      });
      const chosen = activeTargetForSpace(space, tabs);
      if (chosen) chosen.active = true;
      return { tabs };
    },

    async createTab(url = "about:blank", optionsOrContext = {}, maybeContext) {
      const context = maybeContext || (
        optionsOrContext?.__orielScopeId ? optionsOrContext : undefined
      );
      const options = maybeContext ? (optionsOrContext || {}) : {};
      const space = ensureActiveSpace(context);
      const { targetId } = await cdp("Target.createTarget", {
        url,
        browserContextId: space.browserContextId,
        // Agent task spaces must never pull a user's browser window forward.
        // The target remains controllable over CDP and is selected only in
        // Oriel's internal task-space state.
        background: options.background !== false,
        focus: false,
        // Hidden pages are only used when an automation caller asks for them.
        // Manual login/hand-off flows keep their normal visible tab.
        hidden: options.hidden === true,
      });
      space.targetIds.add(targetId);
      space.targetInfo.set(targetId, { url, title: "" });
      space.activeTargetId = targetId;
      return { targetId, url };
    },

    // 快照：ego lite 是浏览器原生实现，这里用标准 CDP 的可访问性树自己拼。
    // 返回 { content, refs }，refs 形状必须是 [{ backendNodeId, role, name }]
    // ——见 src/browser-runtime.ts 的 browserSnapshotRefsToRefMap。
    async snapshot(_options = {}, context) {
      const space = ensureActiveSpace(context);
      const target = activeTargetForSpace(
        space,
        await pageTargetsForSpace(space),
      );
      if (!target) throw new Error("当前任务空间里没有页面");
      const sessionId = await attach(target.targetId);
      await cdp("Accessibility.enable", {}, sessionId);
      const { nodes } = await cdp("Accessibility.getFullAXTree", {}, sessionId);

      const refs = [];
      const lines = [];
      for (const node of nodes) {
        const role = node.role?.value ?? "";
        const name = (node.name?.value ?? "").trim();
        if (
          !role ||
          role === "none" ||
          role === "InlineTextBox" ||
          role === "StaticText"
        )
          continue;
        if (!name && !INTERESTING_ROLES.has(role)) continue;
        const backendNodeId = node.backendDOMNodeId;
        if (backendNodeId === undefined) continue;
        refs.push({ backendNodeId, role, name });
        lines.push(
          `- ${role}${name ? ` "${name}"` : ""} [ref=${backendNodeId}]`,
        );
      }
      return { content: lines.join("\n"), refs };
    },

    // isolated: false（默认）——用 Chrome 的默认区域，登录态由 Chrome 加密持久化，
    //   重启后仍然记得。任务空间之间共享 cookie。
    // isolated: true ——用临时 BrowserContext，空间之间完全隔离，但**不持久化**，
    //   关掉就没了。适合一次性的干净环境。
    async createTaskSpace(name, opts = {}, context) {
      const isolated = opts.isolated === true;
      const browserContextId = isolated
        ? (await cdp("Target.createBrowserContext", {})).browserContextId
        : undefined;
      const id = ++spaceSeq;
      const space = {
        id,
        name: name ?? `space-${id}`,
        browserContextId,
        isolated,
        ownership: "agent",
        activeTargetId: null,
        targetIds: new Set(),
        targetInfo: new Map(),
      };
      spaces.set(id, space);
      selectSpace(id, context);
      return publicSpace(space);
    },

    async useTaskSpace(nameOrId, context) {
      const space = findSpace(nameOrId);
      selectSpace(space.id, context);
      return publicSpace(space);
    },

    async trackActiveTarget(targetId, context) {
      const space = ensureActiveSpace(context);
      if (!space.targetIds.has(targetId)) {
        const targets = await pageTargetsForSpace(space);
        if (!targets.some((target) => target.targetId === targetId)) {
          throw new Error("target does not belong to the active task space");
        }
        space.targetIds.add(targetId);
      }
      space.activeTargetId = targetId;
    },

    async listTaskSpaces() {
      const taskSpaces = await Promise.all(
        [...spaces.values()].map(async (space) => {
          const targets = await pageTargetsForSpace(space);
          const active = activeTargetForSpace(space, targets);
          const title = active?.title?.trim() || active?.url?.trim() || "";
          return publicSpace(space, title ? [title] : []);
        }),
      );
      return { taskSpaces };
    },

    async closeTaskSpace(nameOrId, context) {
      const space = findSpace(nameOrId ?? activeSpaceId(context));
      if (space.browserContextId) {
        // 只有隔离空间有自己的 context；默认空间用的是 Chrome 默认区域，不能销毁，
        // 否则会连带清掉持久化的登录态。
        await cdp("Target.disposeBrowserContext", {
          browserContextId: space.browserContextId,
        });
      } else {
        // Shared-profile spaces isolate tab ownership, not cookies. Closing one
        // space therefore closes only targets that this space created.
        for (const targetId of space.targetIds) {
          await cdp("Target.closeTarget", { targetId }).catch(() => {});
        }
      }
      space.targetIds.clear();
      space.targetInfo.clear();
      space.activeTargetId = null;
      spaces.delete(space.id);
      clearSpaceSelections(space.id);
      return { done: true };
    },

    async completeTaskSpace(nameOrId, opts = {}, context) {
      const space = findSpace(nameOrId ?? activeSpaceId(context));
      if (space.ownership === "user" && opts.keep)
        return { done: false, skipped: "user-owned" };
      if (opts.keep) return { done: true };
      return host.closeTaskSpace(nameOrId, context);
    },

    // 控制权：用户持有期间任何操作硬失败，不重试、不自动夺回。
    async handOffTaskSpace(nameOrId, context) {
      const space = findSpace(nameOrId ?? activeSpaceId(context));
      if (space.ownership === "user")
        return { done: false, skipped: "user-owned" };
      space.ownership = "delegated-to-user";
      return { done: true };
    },
    async takeOverTaskSpace(nameOrId, context) {
      const space = findSpace(nameOrId ?? activeSpaceId(context));
      space.ownership = "agent";
      return { done: true };
    },
    async claimTaskSpace(nameOrId, context) {
      const space = findSpace(nameOrId);
      space.ownership = "agent";
      selectSpace(space.id, context);
      return publicSpace(space);
    },

    async upgradeBrowser() {
      return { done: false, skipped: "stock-chrome-host 不负责浏览器升级" };
    },

    // 给配套工具（登录、诊断）用的原始 CDP 出口；runtime 自己不走这里。
    rawCdp: cdp,
    attachTo: attach,
    closed,

    // daemon 为每个 CLI 连接创建独立 scope。任务空间是全局共享的，但“当前选中”
    // 按连接隔离，避免并行 Codex 任务互相切换对方的活动页面。
    forScope(scopeId) {
      const context = { __orielScopeId: scopeId };
      return {
        getBrowserVersion: (...args) => host.getBrowserVersion(...args),
        listTabs: () => host.listTabs(context),
        createTab: (url, options) => host.createTab(url, options, context),
        snapshot: (options) => host.snapshot(options, context),
        createTaskSpace: (name, opts) =>
          host.createTaskSpace(name, opts, context),
        useTaskSpace: (nameOrId) => host.useTaskSpace(nameOrId, context),
        listTaskSpaces: (...args) => host.listTaskSpaces(...args),
        closeTaskSpace: (nameOrId) => host.closeTaskSpace(nameOrId, context),
        completeTaskSpace: (nameOrId, opts) =>
          host.completeTaskSpace(nameOrId, opts, context),
        handOffTaskSpace: (nameOrId) =>
          host.handOffTaskSpace(nameOrId, context),
        takeOverTaskSpace: (nameOrId) =>
          host.takeOverTaskSpace(nameOrId, context),
        claimTaskSpace: (nameOrId) => host.claimTaskSpace(nameOrId, context),
        upgradeBrowser: (...args) => host.upgradeBrowser(...args),
        trackActiveTarget: (targetId) =>
          host.trackActiveTarget(targetId, context),
      };
    },

    // 连接模式下只断开自己，绝不结束浏览器进程——那是用户正在用的浏览器。
    async close() {
      try {
        ws.close();
      } catch {}
      if (child && !keepBrowserAlive) {
        child.kill();
        await sleep(400);
      }
    },
  };

  function findSpace(nameOrId) {
    for (const space of spaces.values()) {
      if (
        space.id === Number(nameOrId) ||
        space.name === nameOrId ||
        space.id === nameOrId
      )
        return space;
    }
    throw new Error(`找不到任务空间: ${nameOrId}`);
  }
  const publicSpace = (s, recentTabTitles = []) => ({
    taskId: s.name,
    id: s.id,
    name: s.name,
    createdBy: "agent",
    ownership: s.ownership,
    recentTabTitles,
  });

  return host;
}

const INTERESTING_ROLES = new Set([
  "button",
  "link",
  "textbox",
  "checkbox",
  "radio",
  "combobox",
  "listbox",
  "option",
  "tab",
  "menuitem",
  "searchbox",
  "switch",
  "slider",
]);

async function waitForEndpoint(port) {
  const endpoint = `http://127.0.0.1:${port}`;
  for (let i = 0; i < 60; i++) {
    const inspected = await inspectDebugEndpoint(endpoint);
    if (inspected.ready) return inspected.version;
    await sleep(250);
  }
  throw new Error("Chrome 调试端口未就绪");
}
