import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const entry = new URL("./oriel.mjs", import.meta.url);

function runDoctor(config, profileId = "account-1") {
  const directory = mkdtempSync(join(tmpdir(), "oriel-doctor-"));
  const configPath = join(directory, "config.json");
  writeFileSync(configPath, JSON.stringify(config));
  const result = spawnSync(
    process.execPath,
    [fileURLToPath(entry), "--doctor", "--json"],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        ORIEL_PROFILE_ID: profileId,
        ORIEL_CONFIG: configPath,
        ORIEL_DAEMON_SOCKET: join(directory, "daemon.sock"),
      },
    },
  );
  return {
    status: result.status,
    report: JSON.parse(result.stdout),
    stderr: result.stderr,
  };
}

test("doctor emits a safe structured report when the browser is offline", () => {
  const { status, report, stderr } = runDoctor({
    browserId: "test",
    browserName: "Test Chromium",
    browserPath: "/Applications/Test Chromium.app/Contents/MacOS/Test Chromium",
    endpoint: "http://127.0.0.1:48765",
    port: 48765,
    profilePath: "/tmp/oriel-doctor-profile",
  });

  assert.equal(status, 1);
  assert.equal(stderr, "");
  assert.equal(report.schemaVersion, 2);
  assert.equal(report.profileId, "account-1");
  assert.equal(report.status, "needs-attention");
  assert.deepEqual(report.browser, { connected: false });
  assert.deepEqual(report.daemon, { running: false });
  assert.equal(report.configuration.valid, true);
  assert.equal(report.configuration.endpoint, "http://127.0.0.1:48765");
  assert.equal("browserPath" in report.configuration, false);
  assert.equal("profilePath" in report.configuration, false);
});

test("doctor identifies the selected isolated browser profile", () => {
  const { report } = runDoctor(
    {
      browserId: "chrome",
      browserName: "Google Chrome",
      browserPath:
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      endpoint: "http://127.0.0.1:48766",
      port: 48766,
      profilePath: "/tmp/oriel-doctor-profile-account-2",
    },
    "account-2",
  );

  assert.equal(report.profileId, "account-2");
  assert.equal(report.configuration.endpoint, "http://127.0.0.1:48766");
});

test("doctor reports invalid configuration without throwing or leaking paths", () => {
  const { status, report, stderr } = runDoctor({
    endpoint: "http://192.168.1.8:9222",
    profilePath: "/private/should-not-appear",
  });

  assert.equal(status, 1);
  assert.equal(stderr, "");
  assert.equal(report.status, "invalid-config");
  assert.deepEqual(report.browser, { connected: false });
  assert.equal(report.configuration.valid, false);
  assert.match(report.configuration.error, /必须绑定在本机/);
  assert.equal(JSON.stringify(report).includes("should-not-appear"), false);
});
