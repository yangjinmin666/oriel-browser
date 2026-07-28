# 知乎（zhihu.com）

## ⚠️ 最重要的一条：必须用有头模式

知乎会检测无头浏览器（headless）。无头访问问题页得到的是一张**空白页**：

| 模式 | document.title | 正文长度 | 抓到的回答数 |
|---|---|---|---|
| `headless: true` | 空 | 118 字符 | 0 |
| `headless: false` | `如何正确使用知乎？ - 知乎` | 4031 字符 | 2 |

（2026-07-28 在 `https://www.zhihu.com/question/19550225` 上实测）

**所以：访问知乎一定要有头模式。** 如果抓到的正文长度只有一两百字符、`document.title` 是空的，那不是"页面没加载完"，是被反爬挡了——再等也不会出来，换有头模式重试。

配合持久化的登录态会更稳：真实 Chrome + 有头 + 已登录会话，看起来就是个正常用户。

## 页面结构（已实测）

问题页 `https://www.zhihu.com/question/<id>`：

- 问题标题：`.QuestionHeader-title` ✅ 已验证
- 回答列表项：`.List-item` ✅ 已验证（首屏只有 2 条，见下面的懒加载）

## 懒加载：回答要滚动才出来

首屏只渲染 2 条回答，往下滚才继续加载。要抓多条回答必须滚动，用 `scrollToBottomUntil` 之类的循环直到 `.List-item` 数量不再增长，或者达到你要的条数。

## 未验证的部分

下面这些是常见写法，但**本次没有实测**，用之前先自己确认一次，不要当成已知事实：

- 回答正文：`.RichContent-inner`
- 作者名：`.AuthorInfo-name`
- 赞同按钮：`.VoteButton`
- 登录墙弹窗：`.Modal-wrapper` / `[class*="SignFlow"]`

## 登录

未登录也能读到部分内容，但会碰到登录墙弹窗，且可见的回答数量更少。需要完整内容时先登录一次：

```bash
node host-shim/login.mjs https://www.zhihu.com/signin
```

登录态会由 Chrome 自己加密保存，之后一直有效。
