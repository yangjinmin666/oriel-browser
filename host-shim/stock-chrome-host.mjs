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

const DEFAULT_CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 登录态持久化：用一个固定的 Chrome 配置目录，让 Chrome 自己加密保存 cookie
// （macOS 上密钥在钥匙串里）。我们不读、不解密、不落盘任何凭据。
export const DEFAULT_PROFILE_DIR = join(
  process.env.XDG_DATA_HOME || join(homedir(), ".local", "share"),
  "ego-anywhere",
  "chrome-profile",
);

export async function createStockChromeHost(options = {}) {
  const {
    chromePath = DEFAULT_CHROME,
    // 默认有头。国内多个站点会检测无头浏览器：知乎在无头下只返回一张空白页
    // （正文 118 字符 vs 有头 4031 字符，2026-07-28 实测）。无头是提速手段，
    // 不是安全默认值，需要时显式传 headless: true。
    headless = false,
    port = 0,
    userDataDir = DEFAULT_PROFILE_DIR,
  } = options;
  mkdirSync(userDataDir, { recursive: true });

  const chosenPort = port || 9500 + Math.floor(Number(process.pid) % 400);
  const child = spawn(chromePath, [
    `--remote-debugging-port=${chosenPort}`,
    "--remote-debugging-address=127.0.0.1",
    `--user-data-dir=${userDataDir}`,
    ...(headless ? ["--headless=new"] : []),
    "--no-first-run",
    "--no-default-browser-check",
    "about:blank",
  ], { stdio: "ignore" });

  const version = await waitForEndpoint(chosenPort);
  const ws = new WebSocket(version.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });

  // runtime 自己的 pending 表走 onCDPMessage；本 shim 内部调用另开一套 id 段，互不干扰。
  let internalId = 900000;
  const internalPending = new Map();

  ws.onmessage = (event) => {
    const raw = typeof event.data === "string" ? event.data : String(event.data);
    let parsed;
    try { parsed = JSON.parse(raw); } catch { parsed = null; }
    if (parsed && internalPending.has(parsed.id)) {
      const entry = internalPending.get(parsed.id);
      internalPending.delete(parsed.id);
      parsed.error ? entry.reject(new Error(parsed.error.message)) : entry.resolve(parsed.result);
      return;
    }
    host.onCDPMessage?.(raw);
  };

  function cdp(method, params = {}, sessionId) {
    const id = internalId++;
    return new Promise((resolve, reject) => {
      internalPending.set(id, { resolve, reject });
      const timer = setTimeout(() => {
        internalPending.delete(id);
        reject(new Error(`shim CDP timeout: ${method}`));
      }, 30000);
      const wrap = (fn) => (v) => { clearTimeout(timer); fn(v); };
      internalPending.set(id, { resolve: wrap(resolve), reject: wrap(reject) });
      ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
    });
  }

  const sessions = new Map();   // targetId -> sessionId
  async function attach(targetId) {
    if (sessions.has(targetId)) return sessions.get(targetId);
    const { sessionId } = await cdp("Target.attachToTarget", { targetId, flatten: true });
    sessions.set(targetId, sessionId);
    return sessionId;
  }

  // ——— 任务空间：用标准 CDP 的 BrowserContext 做隔离 ———
  const spaces = new Map();     // id -> { id, name, browserContextId, ownership }
  let activeSpaceId = null;
  let spaceSeq = 0;

  function requireActiveSpace() {
    const space = spaces.get(activeSpaceId);
    if (!space) throw new Error("没有选中的任务空间，先调用 createTaskSpace/useTaskSpace");
    if (space.ownership !== "agent") {
      throw new Error("SIDECAR_AGENT_CONTROL_REQUIRED: 用户持有控制权，这是硬停止，不要重试");
    }
    return space;
  }

  async function pageTargets(browserContextId) {
    const { targetInfos } = await cdp("Target.getTargets", {});
    return targetInfos.filter(
      (t) => t.type === "page" && (!browserContextId || t.browserContextId === browserContextId),
    );
  }

  const host = {
    onCDPMessage: null,
    onSendCDPMessageError: null,

    // 整个适配层的核心：字符串进，字符串出。
    sendCDPMessage(payload) {
      try { ws.send(payload); }
      catch (error) { host.onSendCDPMessageError?.(String(error?.message ?? error)); }
    },

    async getBrowserVersion() { return version.Browser; },

    // 注意：宿主必须返回 { tabs: [...] } 这种包了一层的形状，不是裸数组。
    // 见 src/browser-runtime.ts:117 —— `result?.tabs || result?.targetInfos || []`。
    // 返回裸数组会让它取不到，报 "no active tab to attach session"。
    async listTabs() {
      const space = spaces.get(activeSpaceId);
      const targets = await pageTargets(space?.browserContextId);
      const tabs = targets.map((t, index) => {
        let origin = "", pathname = "", href = t.url;
        try { const u = new URL(t.url); origin = u.origin; pathname = u.pathname; href = u.href; } catch {}
        return { targetId: t.targetId, url: t.url, title: t.title, active: false, origin, pathname, href, index };
      });
      // 真实页面优先于启动时那个 about:blank，否则"当前标签"会指到空白页上。
      const real = tabs.filter((t) => t.url && t.url !== "about:blank");
      const chosen = real[real.length - 1] ?? tabs[tabs.length - 1];
      if (chosen) chosen.active = true;
      return { tabs };
    },

    async createTab(url = "about:blank") {
      const space = requireActiveSpace();
      const { targetId } = await cdp("Target.createTarget", {
        url, browserContextId: space.browserContextId,
      });
      return { targetId, url };
    },

    // 快照：ego lite 是浏览器原生实现，这里用标准 CDP 的可访问性树自己拼。
    // 返回 { content, refs }，refs 形状必须是 [{ backendNodeId, role, name }]
    // ——见 src/browser-runtime.ts 的 browserSnapshotRefsToRefMap。
    async snapshot() {
      const space = spaces.get(activeSpaceId);
      const [target] = await pageTargets(space?.browserContextId);
      if (!target) throw new Error("当前任务空间里没有页面");
      const sessionId = await attach(target.targetId);
      await cdp("Accessibility.enable", {}, sessionId);
      const { nodes } = await cdp("Accessibility.getFullAXTree", {}, sessionId);

      const refs = [];
      const lines = [];
      for (const node of nodes) {
        const role = node.role?.value ?? "";
        const name = (node.name?.value ?? "").trim();
        if (!role || role === "none" || role === "InlineTextBox" || role === "StaticText") continue;
        if (!name && !INTERESTING_ROLES.has(role)) continue;
        const backendNodeId = node.backendDOMNodeId;
        if (backendNodeId === undefined) continue;
        refs.push({ backendNodeId, role, name });
        lines.push(`- ${role}${name ? ` "${name}"` : ""} [ref=${backendNodeId}]`);
      }
      return { content: lines.join("\n"), refs };
    },

    // isolated: false（默认）——用 Chrome 的默认区域，登录态由 Chrome 加密持久化，
    //   重启后仍然记得。任务空间之间共享 cookie。
    // isolated: true ——用临时 BrowserContext，空间之间完全隔离，但**不持久化**，
    //   关掉就没了。适合一次性的干净环境。
    async createTaskSpace(name, opts = {}) {
      const isolated = opts.isolated === true;
      const browserContextId = isolated
        ? (await cdp("Target.createBrowserContext", {})).browserContextId
        : undefined;
      const id = ++spaceSeq;
      const space = {
        id, name: name ?? `space-${id}`, browserContextId, isolated, ownership: "agent",
      };
      spaces.set(id, space);
      activeSpaceId = id;
      return publicSpace(space);
    },

    async useTaskSpace(nameOrId) {
      const space = findSpace(nameOrId);
      activeSpaceId = space.id;
      return publicSpace(space);
    },

    async listTaskSpaces() { return [...spaces.values()].map(publicSpace); },

    async closeTaskSpace(nameOrId) {
      const space = findSpace(nameOrId);
      if (space.browserContextId) {
        // 只有隔离空间有自己的 context；默认空间用的是 Chrome 默认区域，不能销毁，
        // 否则会连带清掉持久化的登录态。
        await cdp("Target.disposeBrowserContext", { browserContextId: space.browserContextId });
      } else {
        for (const tab of (await host.listTabs()).tabs) {
          await cdp("Target.closeTarget", { targetId: tab.targetId });
        }
      }
      spaces.delete(space.id);
      if (activeSpaceId === space.id) activeSpaceId = null;
      return { done: true };
    },

    async completeTaskSpace(nameOrId, opts = {}) {
      const space = findSpace(nameOrId);
      if (space.ownership === "user" && opts.keep) return { done: false, skipped: "user-owned" };
      if (opts.keep) return { done: true };
      return host.closeTaskSpace(nameOrId);
    },

    // 控制权：用户持有期间任何操作硬失败，不重试、不自动夺回（见 requireActiveSpace）
    async handOffTaskSpace(nameOrId) {
      const space = findSpace(nameOrId ?? activeSpaceId);
      if (space.ownership === "user") return { done: false, skipped: "user-owned" };
      space.ownership = "delegated-to-user";
      return { done: true };
    },
    async takeOverTaskSpace(nameOrId) {
      const space = findSpace(nameOrId ?? activeSpaceId);
      space.ownership = "agent";
      return { done: true };
    },
    async claimTaskSpace(nameOrId) {
      const space = findSpace(nameOrId);
      space.ownership = "agent";
      activeSpaceId = space.id;
      return publicSpace(space);
    },

    async upgradeBrowser() { return { done: false, skipped: "stock-chrome-host 不负责浏览器升级" }; },

    // 给配套工具（登录、诊断）用的原始 CDP 出口；runtime 自己不走这里。
    rawCdp: cdp,
    attachTo: attach,

    async close() { try { ws.close(); } catch {} child.kill(); await sleep(400); },
  };

  function findSpace(nameOrId) {
    for (const space of spaces.values()) {
      if (space.id === Number(nameOrId) || space.name === nameOrId || space.id === nameOrId) return space;
    }
    throw new Error(`找不到任务空间: ${nameOrId}`);
  }
  const publicSpace = (s) => ({ id: s.id, name: s.name, ownership: s.ownership });

  return host;
}

const INTERESTING_ROLES = new Set([
  "button", "link", "textbox", "checkbox", "radio", "combobox", "listbox",
  "option", "tab", "menuitem", "searchbox", "switch", "slider",
]);

async function waitForEndpoint(port) {
  for (let i = 0; i < 60; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (res.ok) return await res.json();
    } catch {}
    await sleep(250);
  }
  throw new Error("Chrome 调试端口未就绪");
}
