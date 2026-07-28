# 交接给 Codex

2026-07-28。接手前把「已验证事实」整节读完 —— 里面每条都是实测踩出来的，重新推一遍会浪费时间，而且有几条反直觉。

## 一、这个项目是什么

`citrolabs/ego-lite`（MIT，`Copyright (c) 2026 CitroLabs`）的 fork。上游远端保留为 `upstream`，工作分支 `host-shim`。

上游仓库提供的是 **Node helper runtime + agent skill**，不含浏览器本体（浏览器是单独的免费下载，不在 MIT 覆盖范围内）。

我们加的东西全在 `host-shim/`，**没有改上游任何一行代码**。目的：给那套 runtime 换一个宿主，让它跑在普通 Chrome 上，从而不依赖 ego lite 浏览器（这是将来换壳商用的前提）。

## 二、当前状态

| 能力 | 状态 |
|---|---|
| 宿主适配层（14 个方法）跑在普通 Chrome 上 | ✅ 已验证 |
| 语义快照（Accessibility 树 → `{content, refs}`） | ✅ GitHub 页实测 300 个元素 |
| 任务空间隔离（标准 CDP BrowserContext） | ✅ |
| 控制权交接硬停止 | ✅ |
| 登录态持久化（Chrome 自己加密，我们不读凭据） | ✅ 重启后仍在 |
| 连接已运行浏览器（`connectTo`，对付强反爬） | ✅ 已用它读到 BOSS 直聘登录态页面 |
| **点击 / 输入** | ❌ **不报错但无效（见下）** |
| 打包成可日常使用的 skill | ❌ 未做 |

验证脚本：`host-shim/verify.mjs`、`persist-test.mjs`、`verify-actions.mjs`（后者目前 0/5）。

## 三、已验证事实（别重新推导）

**运行环境**
1. `EGO_BROWSER_AGENT_WORKSPACE` 等环境变量**传不进 `ego-browser nodejs` 的 Node 进程**。那个进程由浏览器启动，不继承 shell 环境。实测自定义变量全为 undefined。
2. 装好的 **ego lite 0.4.5.6 的站点知识加载器是空转的** —— 连它自己打包的 google / x-com 都读不到（`learnContext()` 返回 `exists=false`，`siteSkills()` 返回 `[]`）。源码里加载器存在，发布版不工作。**这是可提给上游的干净 bug。**
3. `npm run <script> -- node <<'EOF'` 这种写法会被 **npm 吞掉 stdin**，heredoc 到不了进程里。直接 `node dist/cli.js node <<'EOF'`。
4. 本仓库的构建要用 `node scripts/build.mjs`（tsconfig 是 noEmit，`tsc` 不产出）。产物在 `package/ego-browser/dist/src/`。

**宿主契约（写适配层时容易错）**
5. `listTabs()` 必须返回 **`{ tabs: [...] }`**，不是裸数组。见 `browser-runtime.ts:117`。返回裸数组会报 `no active tab to attach session`。
6. `snapshot()` 必须返回 `{ content, refs }`，`refs` 形状是 `[{ backendNodeId, role, name }]`。见 `browser-runtime.ts` 的 `browserSnapshotRefsToRefMap`。
7. runtime 只用**标准 CDP**（38 个域，Accessibility/Browser/DOM/Input/Network/Page/Runtime/Target），零自定义域。宿主对象的核心就一个方法：`sendCDPMessage(字符串)` 进、`onCDPMessage(字符串)` 出。
8. `browserSnapshotRefsToRefMap` 第一句是 `refMap.clear()` —— 这就是 ref 每次快照失效的根因，改它是一行的事（可作为上游改进）。

**国内站点反爬（重要）**
9. **知乎**：无头 → 白页（正文 118 字符、title 空）；有头 → 正常（4031 字符）。
10. **BOSS 直聘**：无头 → **被重定向到 `/web/passport/zp/security.html`**；有头但全新 profile → 0 个岗位卡片；有头 + 已登录 → 15 个卡片。**必须有头 + 已登录 + 至少等 12 秒。**
11. 因此适配层 `headless` 默认为 `false`。无头是提速手段，不是安全默认值。
12. 对付强反爬最有效的是 `connectTo` 模式，接到用户日常已登录的浏览器（真实指纹 + 真实会话）。Tabbit 的调试端点是 `http://127.0.0.1:53563`，但**这个端口在 Tabbit 正常重启后就没了**，需要带 `--remote-debugging-port` 重新启动才有。

**Chromium 的 WebMCP（记录，暂不做）**
13. stock Chrome 150 和 Tabbit 都有 `WebMCP` CDP 域（`enable/disable/invokeTool/cancelInvocation`），标记 experimental。但**页面侧没有 JS 接口**（`navigator.modelContext` 之类都不存在），`enable` 后收不到任何 `toolsAdded` 事件。**管子铺好了、水龙头没装，现在不能建在它上面。**

## 四、你的任务（按顺序）

### 任务 1：摸清 BOSS 直聘的投递流程，写进说明书

这是用户当下最痛的点 —— 他现在用 Tabbit + Codex 手工投递，很麻烦。

已知：列表页只探到 **1 个 `.op-btn-chat`**，而卡片有 15 个。说明打招呼的入口不在列表页卡片上，需要进详情页。

要摸清并记录：
- 详情页（`/job_detail/*.html`）的结构：岗位描述、薪资、公司信息、打招呼按钮的选择器
- 打招呼按钮点下去之后会发生什么：弹窗？跳聊天页？出验证码？
- 是否有「已沟通」状态，怎么识别（避免重复打招呼）
- 分页 / 无限滚动怎么加载更多岗位

**硬约束：**
- **只看结构，绝对不要真的发出打招呼。** 这是用户自己的求职账号。
- 用 `connectTo` 模式接到 Tabbit（因为需要已登录会话）。**只开你自己的标签页，读完关掉，绝不动用户原有的标签页，绝不结束浏览器进程**（适配层已有 `ownTargets` 护栏，别绕过它）。
- 探测过程要慢，不要连续快速请求。

写完更新两处（内容保持一致）：
- `skills/ego-browser/learnings/boss-zhipin/notes/overview.md`（完整版）
- `~/.claude/skills/boss-zhipin/SKILL.md`（agent 直接读的那份，Codex 侧是它的 symlink）

改完跑 `npx tsx package/ego-browser/scripts/validate-site-skills.ts` 校验格式。

### 任务 2：修点击 / 输入（`verify-actions.mjs` 目前 0/5）

现象：`keyboard.fill` / `pointer.click` / `keyboard.press` **不抛错也不生效**。这是最糟的失败形态。

线索：这些模块导出的是 Playwright 风格的名字（`waitForLoadState`、`pressSequentially`、`selectOption`、`setChecked`），怀疑中间还有一层 Playwright 兼容的 page/locator 对象要提供，而适配层只喂了裸 CDP。

**第一步先只做诊断，不要急着写实现**：读 `package/ego-browser/src/driver/pointer.ts` 和 `keyboard.ts`，搞清楚 `click()` 到底通过什么路径拿到元素、依赖哪些状态。判断是「少初始化几行」还是「要实现一整套兼容层」，把结论汇报给用户 —— 他需要这个来收窄工期预估（目前是 0.5～3 天的跨度）。

顺带：`verify-actions.mjs` 第 5 项（用快照 ref 点击）挂在 `snap.refs.find(r => r.role === "button")` 返回 undefined，那是测试自身的问题（data: 页面的 AX 角色名可能不是 `button`），修测试即可。

### 任务 3（可选）：给上游提 issue

事实 2 那个 bug：发布版 ego lite 读不到自带的站点知识。可复现步骤都在上面。这是干净的第一个上游贡献。

## 五、通用规矩

- **不许改动 `/Applications/ego lite.app` 或 `~/.local/share/ego/`**（已签名，改了会启动失败）。
- **不许让实测数字变成估算值。** 说明书里每条选择器都要在真实页面上验证过；没验证的放到「未验证的部分」小节，明确标注。
- **不许打印或落盘 cookie 值、账号名、密码、Keychain 内容。** 只报数量和字段名。
- **不许在用户的浏览器里批量关标签页或结束进程。**
- 说明书里关于账号风险的那节（不要批量打招呼、投递要人工确认或严格限速）**保留**。用户可以自己决定放宽，但不要你替他删掉。
- 每完成一个任务：跑一遍相关验证脚本 → `git commit`（只本地提交，不要 push、不要配远端）。
- 卡住了、或者需要用户做决定（比如需要他登录、需要重启 Tabbit）就**停下来问**，不要猜着往前推。
