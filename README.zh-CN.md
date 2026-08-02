# Oriel

**让 AI 帮你操作国内网站——那些会把普通自动化浏览器直接拦在门外的网站。**

[English](./README.md) · MIT License · macOS

---

## 问题

你让 Codex 或 Claude Code 去知乎抓点内容，它打开页面，抓回来一片空白。

不是代码写错了，是**知乎认出了无头浏览器**，返回给它一张白纸。BOSS 直聘更狠，直接把你踢到安全验证页。

海外的浏览器自动化工具默认用无头模式——省资源、跑得快。但那套默认值在国内**根本跑不起来**。

## 实测数据

我们在真实页面上量过（2026-07-28）：

| 网站 | 无头模式 | 有头 + 已登录 |
|---|---|---|
| 知乎问题页 | 正文 **118 字节**，标题为空 | 正文 **4031 字节**，正常 |
| BOSS 直聘岗位列表 | 被重定向到 `/web/passport/zp/security.html` | **15 张**岗位卡片 |

还有一个不太有人测过的指标——**页面有多少可交互元素带语义标注**（决定 AI 能不能"看懂"页面）：

| 网站 | 可交互元素 | 有语义名字 | 覆盖率 |
|---|---:|---:|---:|
| 知乎 | 116 | 113 | **97%** |
| GitHub | 275 | 158 | 57% |
| B 站 | 158 | 73 | 46% |
| 淘宝 | 1912 | 152 | **8%** |

结论很反直觉：**国内网站的语义质量方差极大**，从 97% 到 8%。所以「什么时候该放弃读 DOM、改用截图+坐标」这个判断，在国内比在海外重要得多。

（单页样本，非普查。淘宝为未登录状态。）

## Oriel 做了什么

- **默认有头 + 复用你的登录态**，而不是无头 + 匿名
- **登录一次就一直记得** —— 由 Chrome 自己加密保存，Oriel 不读取、不解密、不导出任何 cookie
- **自动检测** Chrome / Tabbit / Edge，一键启动，CDP 端点只监听本机
- **常驻后台进程**，跨多次 AI 调用复用同一个标签页，不用每轮重新导航
- **站点说明书** —— 把踩过的坑写成 AI 能读的知识（已有知乎、BOSS 直聘、Google、X）
- **控制权交接** —— 需要你登录或过验证码时，AI 会把浏览器交还给你，期间它的任何操作都会硬失败

## 安装

目前**没有公开发布的下载包**，安装方式是从源码构建。

要求：macOS 13 或更新、Xcode Command Line Tools、npm。

```bash
git clone https://github.com/yangjinmin666/oriel-browser.git
cd oriel-browser
./scripts/build-macos-app.sh       # 产物：build/Oriel.app
./scripts/package-macos-dmg.sh     # 可选，打成 DMG
```

构建时会下载官方 Node.js 运行时、校验 SHA-256、打进 App 里——用这个 App 的人不需要自己装 Node。

首次运行：

1. 打开 **Oriel**
2. 选择 Chrome、Tabbit 或 Edge
3. 点**启动浏览器**
4. 在弹出来的这个浏览器里，把你要用的网站登录一遍（只需要做这一次）
5. 在「Agent 集成」里点**一键安装**
6. 重启 Codex 和 Claude Code

验证装好了：

```bash
oriel --doctor
```

然后在 Codex 或 Claude Code 里直接说人话：

> 打开知乎搜索「AI 产品经理」，把前 10 条整理给我

常用命令：

```bash
oriel --doctor          # 浏览器、配置、daemon、CLI、skill 的分项状态
oriel --daemon-status   # 同上（别名）
oriel --daemon-stop     # 停掉常驻后台进程
```

## AI 不能自己给自己放行

每个任务空间都有执行策略：

- **只读 / 草稿** —— 直接禁掉所有会改变浏览器状态的操作
- **需要批准** —— 每一个这类操作，都得你在 Oriel 里点一次批准才放行

**打开网页算「读」，不算「动手」。** 所以无论哪档策略，AI 都能打开页面、看内容——搜索、筛选、整理这类活儿不需要你点任何东西。需要批准的是真正动手的那些操作。`file:`、`chrome:`、`devtools:`、`javascript:` 这几种地址超出了「读网页」的范围，仍然要批准。

策略切换、批准、恢复、审计记录都只存在于 Oriel 应用里，**没有对应的 agent API**——AI 没有办法批准自己被拦下的操作。

标签页也是隔离的：一个任务空间只看得见、也只关得掉它自己开的标签页，不会去动你原本开着的页面。

但要说清楚边界：这是**标签页隔离，不是账号隔离**。同一个 Oriel 浏览器 profile 下的任务空间共享登录态。要隔离账号，得用不同的 Oriel 浏览器 profile。

## 安全边界

- 调试端点只绑 `127.0.0.1`；连接或停止之前，Oriel 会验证它确实是本机回环上的 Chromium DevTools
- daemon 的 Unix socket 权限是 `0600`，只有当前用户能连
- **受管浏览器运行期间，本机上的其他进程也可能控制它**——不用的时候在控制中心把它停掉
- 验证码和平台安全校验必须你自己过。Oriel 不做，也不承诺绕过

## 现状（请如实看待）

`v0.2.0-alpha`，能跑，但还不是成品：

- **macOS 应用未签名未公证**。首次双击会被 Gatekeeper 拦下，需要「系统设置 → 隐私与安全性 → 仍要打开」。这是免费项目的常态，不是安装错误。完整的首次打开流程见 [英文 README](./README.md#opening-a-distributed-dmg-on-macos)。
- **干净环境验收尚未完成** —— 见 [`docs/CLEAN_ENVIRONMENT_ACCEPTANCE.md`](./docs/CLEAN_ENVIRONMENT_ACCEPTANCE.md)。我们没有把它假装成通过。
- 站点说明书里凡是**未经实测**的部分都单独标注了，不要当成已验证的事实。
- 目前只支持 macOS。

## ⚠️ 关于自动化投递

Oriel 可以自动完成**搜索、筛选、整理岗位清单**。

但**不建议、也不提供批量自动打招呼/投递**。招聘平台对异常行为检测严格，短时间大量操作可能导致限流甚至封号——那是你自己的求职账号。投递环节请保留人工确认。

## 许可与致谢

**Oriel 采用 MIT 许可证。**

本项目基于 [CitroLabs/ego-lite](https://github.com/citrolabs/ego-lite) 的 MIT 开源 `ego-browser` 运行时构建并做了修改。原始版权与许可声明完整保留在 [`LICENSE`](./LICENSE) 中：

```
Copyright (c) 2026 CitroLabs
Copyright (c) 2026 Oriel contributors
```

设计上参考了 ego-lite 的若干思路（隔离任务空间、控制权交接协议、站点知识分层），在此致谢。

**需要说明的边界：**

- **ego lite 浏览器本身不是 MIT，也不包含在本项目中。** 上游仓库提供的是 Node 运行时和 skill，浏览器是单独的免费下载。**Oriel 不需要、也不分发 ego lite 浏览器**——它使用你自己已安装的 Chrome / Tabbit / Edge。
- macOS 应用内打包了官方 **Node.js** 二进制（MIT），其许可文本随包分发。
- Chrome、Microsoft Edge、Tabbit 均为各自权利人的商标。Oriel 仅检测和调用你本机已安装的浏览器，不分发它们，与其开发方无隶属关系。

完整的第三方声明见 [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md)。
