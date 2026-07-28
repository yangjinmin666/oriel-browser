// 登录一次，以后一直记得。
//
//   node host-shim/login.mjs https://github.com/login
//
// 会开一个可见的 Chrome（我们自己的，跟你日常浏览器无关），你手动登录，
// 回终端按回车。登录态由 Chrome 自己加密保存在我们的配置目录里，
// 之后所有自动化任务都直接是已登录状态。
//
// 我们不读取、不解密、不复制你的任何凭据，也不碰你日常用的浏览器。

import { createInterface } from "node:readline/promises";
import { createStockChromeHost, DEFAULT_PROFILE_DIR } from "./stock-chrome-host.mjs";

const url = process.argv[2];
if (!url) {
  console.error("用法: node host-shim/login.mjs <要登录的网址>");
  process.exit(1);
}

const host = await createStockChromeHost({ headless: false });
console.log("配置目录:", DEFAULT_PROFILE_DIR);

try {
  const space = await host.createTaskSpace("login");
  await host.createTab(url);

  // 交出控制权：用户持有期间，agent 侧任何操作都会硬失败。
  await host.handOffTaskSpace(space.id);
  console.log(`\n已打开 ${url}`);
  console.log("请在弹出的 Chrome 窗口里完成登录（含验证码、二次验证都可以）。");

  const rl = createInterface({ input: process.stdin, output: process.stdout });
  await rl.question("\n登录完成后按回车继续... ");
  rl.close();

  await host.takeOverTaskSpace(space.id);

  const [tab] = (await host.listTabs()).tabs;
  const sessionId = await host.attachTo(tab.targetId);
  const { cookies } = await host.rawCdp("Network.getCookies", {}, sessionId);
  const host_ = new URL(url).hostname;
  const mine = cookies.filter((c) => {
    const d = c.domain.replace(/^\./, "");
    return host_ === d || host_.endsWith(`.${d}`);
  });

  // 只报数量和名字，绝不打印任何 cookie 值。
  console.log(`\n该站点已保存 ${mine.length} 条 cookie:`, mine.map((c) => c.name).join(", ") || "（无）");
  console.log(mine.length ? "登录态已持久化，后续任务直接可用。" : "没检测到该站点的 cookie，可能登录未完成。");
} finally {
  await host.close();
}
