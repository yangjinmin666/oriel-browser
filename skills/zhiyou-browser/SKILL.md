---
name: zhiyou-browser
description: Control websites in a managed Chrome, Tabbit, Edge, or Chromium browser through 智游 ZhiYou. Use for opening pages, interacting with logged-in sites, extracting page data, testing web apps, screenshots, and other browser automation.
---

# 智游 ZhiYou

智游 ZhiYou lets Codex control a real Chromium browser without requiring the
ego lite browser. The macOS control center manages the browser connection and
keeps login state in a dedicated local browser profile.

## Before browser work

Run the built-in health check:

```bash
~/.local/bin/zhiyou --doctor
```

If it says the browser is not running, open **智游 ZhiYou** and press
**Start browser**. Never ask the user to paste cookies or tokens.

## Run browser tasks

Use heredoc scripts:

```bash
~/.local/bin/zhiyou nodejs <<'EOF'
const task = await taskSpaces.useOrCreate('inspect page')
await browser.openOrReuseTab('https://example.com', { wait: true, timeout: 20 })
console.log(await page.snapshot())
await taskSpaces.complete(task.id, { keep: false })
EOF
```

Use semantic snapshots first, then act with refs or durable selectors. Keep
reusing the same task-space name within one user goal.

## Safety

- Browser debugging is bound to `127.0.0.1`, but any local process can control
  the managed browser while it is running.
- Do not print, export, or persist cookies, passwords, tokens, or Keychain data.
- Keep the domain scope limited to the sites needed for the current task.
- When the user takes control, stop immediately. Do not retry or take control
  back until the user explicitly asks to continue.
- For messages, purchases, applications, publishing, deletion, and other
  consequential actions, obtain explicit confirmation immediately before the
  final action.

## Site-specific behavior

Load and follow the matching notes under the installed `learnings/` directory.
Anti-bot sites may still require manual verification. Never attempt to bypass a
CAPTCHA or platform security challenge.
