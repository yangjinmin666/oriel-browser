---
name: oriel-browser
description: Control websites in a managed Chrome, Tabbit, Edge, or Chromium browser through Oriel. Use for opening pages, interacting with logged-in sites, extracting page data, testing web apps, screenshots, and other browser automation.
---

# Oriel

Oriel lets Codex control a real Chromium browser without requiring the
ego lite browser. The macOS control center manages the browser connection and
keeps login state in a dedicated local browser profile. A local daemon preserves
task spaces and page ownership across independent Codex calls.

## Before browser work

Run the built-in health check:

```bash
~/.local/bin/oriel --doctor
```

If it says the browser is not running, open **Oriel** and press
**Start browser**. Never ask the user to paste cookies or tokens.

The daemon starts automatically on the first browser task. Diagnose it with:

```bash
~/.local/bin/oriel --daemon-status
```

## Run browser tasks

Use heredoc scripts:

```bash
~/.local/bin/oriel nodejs <<'EOF'
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
