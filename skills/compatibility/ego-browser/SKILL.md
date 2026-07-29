---
name: ego-browser
description: Compatibility entry for browser tasks after Oriel replaces the old ego-browser agent integration. Use the Oriel CLI and current taskSpaces, browser, and page facade APIs.
---

# Oriel Compatibility

This name is retained only so old prompts route safely to Oriel. Use
`oriel-browser` for new work.

Run browser work through Oriel with the current facade:

```bash
~/.local/bin/oriel nodejs <<'EOF'
const task = await taskSpaces.useOrCreate('browser task')
await browser.openOrReuseTab('https://example.com', {
  wait: true,
  timeout: 20
})
console.log(await page.snapshot())
await taskSpaces.complete(task.id, { keep: false })
EOF
```

Do not use legacy global task-space or text-snapshot helpers. Follow all safety,
confirmation, task-space isolation, and site-specific guidance in the canonical
`oriel-browser` skill.
