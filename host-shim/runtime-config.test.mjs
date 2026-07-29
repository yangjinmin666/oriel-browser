import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  DEFAULT_CONFIG,
  loadRuntimeConfig,
  normalizeEndpoint,
  normalizePort,
} from "./runtime-config.mjs";

const runtimeConfigEntry = new URL("./runtime-config.mjs", import.meta.url);

test("uses safe localhost default when no config exists", () => {
  const path = join(mkdtempSync(join(tmpdir(), "oriel-")), "missing.json");
  assert.deepEqual(loadRuntimeConfig(path), DEFAULT_CONFIG);
});

test("normalizes localhost endpoints", () => {
  assert.equal(
    normalizeEndpoint("http://127.0.0.1:9999/"),
    "http://127.0.0.1:9999",
  );
});

test("rejects remote debugging endpoints outside localhost", () => {
  assert.throws(
    () => normalizeEndpoint("http://192.168.1.8:9222"),
    /必须绑定在本机/,
  );
});

test("rejects non-HTTP debugging endpoints", () => {
  assert.throws(() => normalizeEndpoint("ws://127.0.0.1:9222"), /只支持 HTTP/);
});

test("loads a selected browser without losing secure defaults", () => {
  const dir = mkdtempSync(join(tmpdir(), "oriel-"));
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
  const dir = mkdtempSync(join(tmpdir(), "oriel-"));
  const path = join(dir, "config.json");
  writeFileSync(path, JSON.stringify({ browserId: "chrome" }));
  const config = loadRuntimeConfig(path);
  assert.equal(config.endpoint, DEFAULT_CONFIG.endpoint);
  assert.equal(config.port, DEFAULT_CONFIG.port);
});

test("normalizes a portless local endpoint to the configured port", () => {
  const dir = mkdtempSync(join(tmpdir(), "oriel-"));
  const path = join(dir, "config.json");
  writeFileSync(
    path,
    JSON.stringify({ endpoint: "http://localhost", port: 12456 }),
  );
  const config = loadRuntimeConfig(path);
  assert.equal(config.endpoint, "http://localhost:12456");
  assert.equal(config.port, 12456);
});

test("rejects endpoint and port disagreement", () => {
  assert.throws(
    () => normalizeEndpoint("http://127.0.0.1:9222", 9223),
    /端点端口与配置端口不一致/,
  );
});

test("rejects credentials and path fragments in endpoints", () => {
  assert.throws(
    () => normalizeEndpoint("http://user:pass@127.0.0.1:9222"),
    /不能包含账号或密码/,
  );
  assert.throws(
    () => normalizeEndpoint("http://127.0.0.1:9222/json/version"),
    /不能包含路径、查询参数或片段/,
  );
});

test("rejects relative browser and profile paths", () => {
  const dir = mkdtempSync(join(tmpdir(), "oriel-"));
  const path = join(dir, "config.json");
  writeFileSync(path, JSON.stringify({ browserPath: "Chrome" }));
  assert.throws(() => loadRuntimeConfig(path), /browserPath 必须是绝对路径/);

  writeFileSync(path, JSON.stringify({ profilePath: "profiles/chrome" }));
  assert.throws(() => loadRuntimeConfig(path), /profilePath 必须是绝对路径/);
});

test("rejects invalid ports before starting a browser", () => {
  assert.throws(() => normalizePort(80), /1024 到 65535/);
  assert.throws(() => normalizePort("not-a-port"), /1024 到 65535/);
});

test("selects an isolated configuration and defaults for account 2", () => {
  const script = `
    import {
      CONFIG_PATH,
      DEFAULT_CONFIG,
      RUNTIME_PROFILE_ID,
    } from ${JSON.stringify(runtimeConfigEntry.href)}
    console.log(JSON.stringify({
      configPath: CONFIG_PATH,
      defaults: DEFAULT_CONFIG,
      profileId: RUNTIME_PROFILE_ID,
    }))
  `;
  const result = spawnSync(
    process.execPath,
    ["--input-type=module", "--eval", script],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        ORIEL_PROFILE_ID: "account-2",
        ORIEL_CONFIG: "",
        ZHIYOU_CONFIG: "",
        EGO_ANYWHERE_CONFIG: "",
      },
    },
  );

  assert.equal(result.status, 0, result.stderr);
  const payload = JSON.parse(result.stdout);
  assert.equal(payload.profileId, "account-2");
  assert.match(payload.configPath, /config\.account-2\.json$/);
  assert.equal(payload.defaults.profileId, "account-2");
  assert.equal(payload.defaults.port, 9766);
  assert.match(payload.defaults.profilePath, /Profiles\/account-2$/);
});
