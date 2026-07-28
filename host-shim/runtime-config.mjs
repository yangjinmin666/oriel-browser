import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export const APP_SUPPORT_DIR = join(
  homedir(),
  "Library",
  "Application Support",
  "Oriel",
);

export const LEGACY_APP_SUPPORT_DIRS = [
  join(homedir(), "Library", "Application Support", "ZhiYou"),
  join(homedir(), "Library", "Application Support", "Ego Anywhere"),
];

const legacyConfigPath = LEGACY_APP_SUPPORT_DIRS.map((directory) =>
  join(directory, "config.json"),
).find(existsSync);

export const CONFIG_PATH =
  process.env.ORIEL_CONFIG ||
  process.env.ZHIYOU_CONFIG ||
  process.env.EGO_ANYWHERE_CONFIG ||
  (existsSync(join(APP_SUPPORT_DIR, "config.json"))
    ? join(APP_SUPPORT_DIR, "config.json")
    : legacyConfigPath
      ? legacyConfigPath
      : join(APP_SUPPORT_DIR, "config.json"));

export const DEFAULT_CONFIG = Object.freeze({
  browserId: "chrome",
  browserName: "Google Chrome",
  browserPath:
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  endpoint: "http://127.0.0.1:9765",
  port: 9765,
  profilePath: join(APP_SUPPORT_DIR, "Profiles", "chrome"),
});

export function normalizeEndpoint(value) {
  const raw = String(value || "").trim().replace(/\/+$/, "");
  if (!raw) return DEFAULT_CONFIG.endpoint;
  const parsed = new URL(raw);
  if (!["127.0.0.1", "localhost", "[::1]"].includes(parsed.hostname)) {
    throw new Error("浏览器调试端点必须绑定在本机");
  }
  if (parsed.protocol !== "http:") {
    throw new Error("浏览器调试端点只支持 HTTP");
  }
  return parsed.toString().replace(/\/+$/, "");
}

export function loadRuntimeConfig(path = CONFIG_PATH) {
  if (!existsSync(path)) return { ...DEFAULT_CONFIG };
  const parsed = JSON.parse(readFileSync(path, "utf8"));
  const endpoint = normalizeEndpoint(parsed.endpoint);
  const port = Number(parsed.port || new URL(endpoint).port || 9765);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    throw new Error("浏览器调试端口无效");
  }
  return {
    ...DEFAULT_CONFIG,
    ...parsed,
    endpoint,
    port,
  };
}
