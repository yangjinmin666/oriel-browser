// 验证"能干活"：用 runtime 自己的 click / fill / press 等 helper 真正操作页面。
// 用 data: 页面，不依赖网络，结果可确定验证。
import { createStockChromeHost } from "./stock-chrome-host.mjs";

const DIST = new URL("../package/ego-browser/dist/src/", import.meta.url).href;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const PAGE = `<!doctype html><meta charset="utf-8"><title>action-test</title>
<input id="name" placeholder="name">
<input type="checkbox" id="agree">
<button id="go" onclick="document.getElementById('out').textContent=
  document.getElementById('name').value + '|' + document.getElementById('agree').checked">send</button>
<div id="out">empty</div>
<div id="keys">-</div>
<script>document.getElementById('name').addEventListener('keydown',
  e => document.getElementById('keys').textContent = e.key);</script>`;

const host = await createStockChromeHost({ headless: true });
globalThis.ego = host;
const pass = [];
const fail = [];
const check = (label, ok, detail = "") => (ok ? pass : fail).push(`${label}${detail ? " → " + detail : ""}`);

try {
  await host.createTaskSpace("actions");
  await host.createTab("data:text/html," + encodeURIComponent(PAGE));
  await sleep(1500);

  const [tab] = (await host.listTabs()).tabs;
  const sid = await host.attachTo(tab.targetId);
  const read = async (sel, prop = "textContent") => {
    const r = await host.rawCdp("Runtime.evaluate", {
      returnByValue: true,
      expression: `document.querySelector(${JSON.stringify(sel)}).${prop}`,
    }, sid);
    return r.result.value;
  };

  const keyboard = await import(`${DIST}driver/keyboard.js`);
  const pointer = await import(`${DIST}driver/pointer.js`);
  const waits = await import(`${DIST}driver/waits.js`);
  console.log("keyboard 导出:", Object.keys(keyboard).join(","));
  console.log("pointer  导出:", Object.keys(pointer).join(","));
  console.log("waits    导出:", Object.keys(waits).join(","));
  console.log("");

  try {
    await keyboard.fill("#name", "zhangsan");
    check("fill 填写输入框", (await read("#name", "value")) === "zhangsan", await read("#name", "value"));
  } catch (e) { check("fill 填写输入框", false, "抛错: " + e.message.slice(0, 60)); }

  try {
    await pointer.click("#agree");
    check("click 勾选复选框", (await read("#agree", "checked")) === true);
  } catch (e) { check("click 勾选复选框", false, "抛错: " + e.message.slice(0, 60)); }

  try {
    await pointer.click("#go");
    await sleep(400);
    const out = await read("#out");
    check("click 触发按钮副作用", out === "zhangsan|true", out);
  } catch (e) { check("click 触发按钮副作用", false, "抛错: " + e.message.slice(0, 60)); }

  try {
    await keyboard.focus("#name");
    await keyboard.press("Enter");
    await sleep(300);
    check("press 发送按键", (await read("#keys")) === "Enter", await read("#keys"));
  } catch (e) { check("press 发送按键", false, "抛错: " + e.message.slice(0, 60)); }

  try {
    const observe = await import(`${DIST}driver/observe.js`);
    const snap = await observe.snapshotRaw();
    const btn = snap.refs.find((r) => r.role === "button");
    await host.rawCdp("Runtime.evaluate", { expression: `document.getElementById('out').textContent='reset'` }, sid);
    await pointer.click(`@e${btn.backendNodeId}`);
    await sleep(400);
    const out = await read("#out");
    check("用快照 ref 点击（语义闭环）", out !== "reset", `ref=${btn.backendNodeId}, out=${out}`);
  } catch (e) { check("用快照 ref 点击（语义闭环）", false, "抛错: " + e.message.slice(0, 70)); }

  console.log("通过:");
  for (const p of pass) console.log("  OK  " + p);
  if (fail.length) { console.log("失败:"); for (const f of fail) console.log("  XX  " + f); }
  console.log(`\n合计 ${pass.length} 通过 / ${fail.length} 失败`);
} catch (e) {
  console.log("整体失败:", e.message);
  console.log(e.stack?.split("\n").slice(1, 4).join("\n"));
} finally {
  await host.close();
}
