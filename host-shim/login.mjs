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

  // Do not inspect cookies merely to prove a login. Chromium persists the
  // session inside its own profile and Keychain; avoiding a credential read
  // keeps this helper out of the user's full authentication state entirely.
  console.log("\n已按你的确认结束登录流程。登录态由 Chromium 自己持久化，后续任务可直接尝试使用。");
} finally {
  await host.close();
}
