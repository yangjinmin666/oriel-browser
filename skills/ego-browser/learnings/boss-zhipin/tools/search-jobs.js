// BOSS 直聘岗位搜索：只读。
//
// 这个工具**不会**打招呼、不会投递。理由见 notes/overview.md：
// 批量打招呼是账号风险最高的动作，不应该藏在一个"搜索"工具里顺手做掉。
// 投递要么人工确认，要么单独写一个显式的、限速的工具。
//
// 前提：有头模式 + 已登录会话。匿名 profile 会被重定向到 /web/passport/zp/security.html。

const DEFAULT_CITY = "101020100"; // 上海

function boundedInteger(value, fallback, max) {
  const number = value === undefined ? fallback : Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(1, Math.min(max, Math.trunc(number)));
}

export async function searchJobs(ctx, args = {}) {
  const query = args.query || "";
  if (!query) throw new Error("query is required");
  const city = args.city || DEFAULT_CITY;
  const maxJobs = boundedInteger(args.maxJobs, 15, 120);

  const url =
    `https://www.zhipin.com/web/geek/jobs?query=${encodeURIComponent(query)}&city=${encodeURIComponent(city)}`;
  await ctx.browser.openOrReuseTab(url, { wait: true });
  await ctx.page.waitForLoadState("load");

  // 单页应用，渲染慢。实测 12 秒左右才稳定，别急着读。
  await ctx.page.waitForTimeout(12000);

  const state = await ctx.page.evaluate(() => ({
    href: location.href,
    cards: document.querySelectorAll(".job-card-box").length,
    bodyLength: document.body.innerText.length,
  }));

  // 反爬的两种表现：被踢到安全验证页，或者页面渲染为空。
  if (state.href.includes("/web/passport/zp/security.html") || (state.cards === 0 && state.bodyLength < 400)) {
    return {
      jobs: [],
      blocked: true,
      hint:
        "被 BOSS 直聘反爬拦下。需要：有头模式 + 已登录会话。匿名 profile 即使有头也拿不到岗位列表；" +
        "可用 login.mjs 先登录一次，或用连接模式接到用户日常已登录的浏览器。",
    };
  }

  // 需要更多结果就往下滚，直到卡片数不再增长。
  let previous = 0;
  for (let i = 0; i < 12; i++) {
    const count = await ctx.page.locator(".job-card-box").count();
    if (count >= maxJobs || count === previous) break;
    previous = count;
    await ctx.page.evaluate(() => window.scrollBy(0, 2200));
    await ctx.page.waitForTimeout(1500);
  }

  const jobs = await ctx.page.locator(".job-card-box").evaluateAll((cards, limit) => {
    const text = (el, sel) => el.querySelector(sel)?.innerText?.trim().replace(/\s+/g, " ") || null;
    return cards.slice(0, limit).map((card) => {
      const rawSalary = text(card, ".job-salary");
      return {
        name: text(card, ".job-name"),
        // 实测薪资常渲染成 "-K"，数字缺失。这种情况返回 null，不要当成真实薪资。
        salary: rawSalary && /\d/.test(rawSalary) ? rawSalary : null,
        salaryRaw: rawSalary,
        tags: text(card, ".tag-list"),
        // 注意：类名叫 boss-name，内容其实是公司名。
        company: text(card, ".boss-name"),
        location: text(card, ".company-location"),
        url: card.querySelector("a")?.href || null,
      };
    });
  }, maxJobs);

  return { jobs, blocked: false };
}
