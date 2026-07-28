// 自动验证"登录一次就一直记得"的机制——不需要真的去登录任何网站。
// 做法：第一轮往一个域名写一条 cookie，关掉浏览器；第二轮重新开，看它还在不在。

import { createStockChromeHost } from "./stock-chrome-host.mjs";

const MARK = "ego_anywhere_persist_probe";

async function round(label, fn) {
  const host = await createStockChromeHost({ headless: true });
  globalThis.ego = host;
  try {
    await host.createTaskSpace(label);
    await host.createTab("https://example.com");
    await new Promise((r) => setTimeout(r, 2500));
    const [tab] = (await host.listTabs()).tabs;
    const sessionId = await host.attachTo(tab.targetId);
    return await fn(host, sessionId);
  } finally {
    await host.close();
  }
}

// 第一轮：写入
await round("write", async (host, sessionId) => {
  await host.rawCdp("Network.setCookie", {
    name: MARK, value: "1", domain: ".example.com", path: "/",
    expires: Math.floor(Date.now() / 1000) + 86400,
  }, sessionId);
  const { cookies } = await host.rawCdp("Network.getCookies", {}, sessionId);
  console.log("1. 第一轮写入后，cookie 存在:", cookies.some((c) => c.name === MARK));
});

console.log("2. 浏览器已完全关闭");

// 第二轮：全新进程，看还在不在
const survived = await round("read", async (host, sessionId) => {
  const { cookies } = await host.rawCdp("Network.getCookies", {}, sessionId);
  return cookies.some((c) => c.name === MARK);
});

console.log("3. 重开浏览器后，cookie 还在:", survived);

// 对照组：隔离空间不应该持久化
const isolatedSurvived = await (async () => {
  const host = await createStockChromeHost({ headless: true });
  globalThis.ego = host;
  try {
    await host.createTaskSpace("isolated-check", { isolated: true });
    await host.createTab("https://example.com");
    await new Promise((r) => setTimeout(r, 2500));
    const [tab] = (await host.listTabs()).tabs;
    const sessionId = await host.attachTo(tab.targetId);
    const { cookies } = await host.rawCdp("Network.getCookies", {}, sessionId);
    return cookies.some((c) => c.name === MARK);
  } finally { await host.close(); }
})();

console.log("4. 隔离空间里看不到它（应为 false）:", isolatedSurvived);

console.log(
  survived && !isolatedSurvived
    ? "\n结论：默认空间登录态持久化成立，隔离空间确实干净。"
    : "\n结论：不符合预期，需要排查。",
);
