// 读知乎问题页：标题 + 回答。
//
// 前提：必须有头模式。知乎给无头浏览器返回空白页（正文 ~118 字符、title 为空）。
// 本工具会显式检测这种情况并返回 blocked: true，而不是安静地返回空结果——
// "抓到 0 条回答"和"被反爬挡了"是两回事，调用方需要能区分。

function boundedInteger(value, fallback, max) {
  const number = value === undefined ? fallback : Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(1, Math.min(max, Math.trunc(number)));
}

export async function extractQuestion(ctx, args = {}) {
  const questionUrl = args.questionUrl || "";
  const maxAnswers = boundedInteger(args.maxAnswers, 5, 50);
  if (!questionUrl) throw new Error("questionUrl is required");

  await ctx.browser.openOrReuseTab(questionUrl, { wait: true });
  await ctx.page.waitForLoadState("load");

  const probe = await ctx.page.evaluate(() => ({
    title: document.title,
    bodyLength: document.body.innerText.length,
  }));

  // 反爬白页的特征：标题空 + 正文极短。这里放宽到 400 字符，留出余量。
  if (!probe.title || probe.bodyLength < 400) {
    return {
      title: null,
      answers: [],
      blocked: true,
      hint: "知乎返回了反爬白页。用有头模式（headless: false）重试；已登录会话更稳。",
    };
  }

  // 回答是懒加载的，首屏通常只有 2 条，往下滚才继续出。
  let previous = 0;
  for (let i = 0; i < 12; i++) {
    const count = await ctx.page.locator(".List-item").count();
    if (count >= maxAnswers || count === previous) break;
    previous = count;
    await ctx.page.evaluate(() => window.scrollBy(0, 2000));
    await ctx.page.waitForTimeout(1200);
  }

  const title = await ctx.page
    .locator(".QuestionHeader-title")
    .first()
    .innerText()
    .catch(() => null);

  const answers = await ctx.page
    .locator(".List-item")
    .evaluateAll((items, limit) =>
      items
        .slice(0, limit)
        .map((el) => el.innerText.trim())
        .filter(Boolean),
    maxAnswers);

  return { title: title?.trim() ?? null, answers, blocked: false };
}
