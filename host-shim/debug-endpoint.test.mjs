import assert from "node:assert/strict";
import test from "node:test";

import {
  inspectDebugEndpoint,
  isChromiumDebugVersion,
} from "./debug-endpoint.mjs";

const endpoint = "http://127.0.0.1:39281";
const chromeVersion = {
  Browser: "Chrome/140.0.0.0",
  webSocketDebuggerUrl: "ws://127.0.0.1:39281/devtools/browser/test",
};

test("recognizes a loopback Chromium DevTools version response", () => {
  assert.equal(isChromiumDebugVersion(chromeVersion, endpoint), true);
});

test("rejects ordinary HTTP payloads and remote websocket targets", () => {
  assert.equal(isChromiumDebugVersion({ ok: true }, endpoint), false);
  assert.equal(
    isChromiumDebugVersion(
      {
        ...chromeVersion,
        webSocketDebuggerUrl: "ws://192.168.1.10:39281/devtools/browser/test",
      },
      endpoint,
    ),
    false,
  );
});

test("inspects a valid endpoint without treating any HTTP 200 as ready", async () => {
  const valid = await inspectDebugEndpoint(endpoint, {
    fetchImpl: async (url) => {
      assert.equal(url.href, `${endpoint}/json/version`);
      return { ok: true, json: async () => chromeVersion };
    },
  });
  assert.deepEqual(valid, { ready: true, version: chromeVersion });

  const invalid = await inspectDebugEndpoint(endpoint, {
    fetchImpl: async () => ({ ok: true, json: async () => ({ ok: true }) }),
  });
  assert.deepEqual(invalid, { ready: false, reason: "not-chromium-devtools" });
});

test("treats malformed or unavailable endpoints as not ready", async () => {
  const malformed = await inspectDebugEndpoint("not a URL");
  assert.deepEqual(malformed, { ready: false, reason: "unreachable" });

  const offline = await inspectDebugEndpoint(endpoint, {
    fetchImpl: async () => {
      throw new Error("offline");
    },
  });
  assert.deepEqual(offline, { ready: false, reason: "unreachable" });
});
