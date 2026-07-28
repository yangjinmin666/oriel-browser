import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  DEFAULT_CONFIG,
  loadRuntimeConfig,
  normalizeEndpoint,
} from "./runtime-config.mjs";

test("uses safe localhost default when no config exists", () => {
  const path = join(mkdtempSync(join(tmpdir(), "zhiyou-")), "missing.json");
  assert.deepEqual(loadRuntimeConfig(path), DEFAULT_CONFIG);
});

test("normalizes localhost endpoints", () => {
  assert.equal(normalizeEndpoint("http://127.0.0.1:9999/"), "http://127.0.0.1:9999");
});

test("rejects remote debugging endpoints outside localhost", () => {
  assert.throws(
    () => normalizeEndpoint("http://192.168.1.8:9222"),
    /必须绑定在本机/,
  );
});

test("rejects non-HTTP debugging endpoints", () => {
  assert.throws(
    () => normalizeEndpoint("ws://127.0.0.1:9222"),
    /只支持 HTTP/,
  );
});

test("loads a selected browser without losing secure defaults", () => {
  const dir = mkdtempSync(join(tmpdir(), "zhiyou-"));
  const path = join(dir, "config.json");
  writeFileSync(
    path,
    JSON.stringify({
      browserId: "tabbit",
      browserName: "Tabbit",
      browserPath: "/Applications/Tabbit.app/Contents/MacOS/Tabbit",
      endpoint: "http://localhost:10455",
      port: 10455,
      profilePath: join(dir, "profile"),
    }),
  );
  const config = loadRuntimeConfig(path);
  assert.equal(config.browserId, "tabbit");
  assert.equal(config.endpoint, "http://localhost:10455");
  assert.equal(config.port, 10455);
});

test("fills endpoint and port defaults for partial configuration", () => {
  const dir = mkdtempSync(join(tmpdir(), "zhiyou-"));
  const path = join(dir, "config.json");
  writeFileSync(path, JSON.stringify({ browserId: "chrome" }));
  const config = loadRuntimeConfig(path);
  assert.equal(config.endpoint, DEFAULT_CONFIG.endpoint);
  assert.equal(config.port, DEFAULT_CONFIG.port);
});
