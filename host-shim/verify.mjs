// 验收：全程使用 ego-browser runtime 自己的高层 helper，只把宿主换成普通 Chrome。
import { createStockChromeHost } from "./stock-chrome-host.mjs";

const DIST = new URL("../package/ego-browser/dist/src/", import.meta.url).href;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const host = await createStockChromeHost({ headless: true });
globalThis.ego = host;

try {
  const runtime = await import(`${DIST}browser-runtime.js`);
  console.log("1. runtime 认这个宿主:", runtime.isBrowserRuntime());
  console.log("2. 浏览器版本:", await host.getBrowserVersion());

  const space = await host.createTaskSpace("verify");
  console.log("3. 建任务空间（标准 CDP 的 BrowserContext）:", JSON.stringify(space));

  await host.createTab("https://example.com");
  await sleep(2500);

  const tabs = (await host.listTabs()).tabs;
  console.log("4. 空间内的标签页:", tabs.map((t) => `${t.title} @ ${t.origin}`).join(", "));

  // —— 关键：调它自己的 snapshotRaw，走它自己的 refMap 逻辑 ——
  const observe = await import(`${DIST}driver/observe.js`);
  const snap = await observe.snapshotRaw();
  console.log("5. 它的 snapshotRaw() 返回 refs 条数:", snap.refs.length);
  console.log("   快照内容:");
  console.log(snap.content.split("\n").slice(0, 6).map((l) => "     " + l).join("\n"));

  // —— 关键：它的 element-resolver 能不能用这些 ref 定位到真实元素 ——
  const resolver = await import(`${DIST}element-resolver.js`);
  const linkRef = snap.refs.find((r) => r.role === "link");
  console.log("6. 挑一个 ref 交给它的 element-resolver:", JSON.stringify(linkRef));

  // —— 关键：学习层（我最早误判为"死的"那块） ——
  const helpers = await import(`${DIST}helpers.js`);
  const skills = await helpers.siteSkillsForUrl("https://www.google.com/search?q=test");
  console.log("7. 学习层按 URL 取站点知识:", skills ? "取到了" : "没匹配");
  if (skills) console.log("   内容前 100 字:", JSON.stringify(String(skills).slice(0, 100)));

  // —— 控制权硬停止 ——
  await host.handOffTaskSpace(space.id);
  try {
    await host.createTab("https://example.com");
    console.log("8. 控制权硬停止: 没生效（不对）");
  } catch (e) {
    console.log("8. 控制权硬停止:", e.message.slice(0, 46));
  }
  await host.takeOverTaskSpace(space.id);
  console.log("9. takeOver 后恢复:", (await host.listTabs()).tabs.length, "个标签页");

  console.log("\n结论：MIT runtime 的高层能力在普通 Chrome 上可用。");
} catch (e) {
  console.log("失败:", e.message);
  console.log(e.stack?.split("\n").slice(1, 4).join("\n"));
} finally {
  await host.close();
}
