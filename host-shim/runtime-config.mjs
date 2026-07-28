import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join } from "node:path";

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
  browserPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  endpoint: "http://127.0.0.1:9765",
  port: 9765,
  profilePath: join(APP_SUPPORT_DIR, "Profiles", "chrome"),
});

function configError(message) {
  return new Error(`Oriel 配置无效：${message}`);
}

function nonEmptyString(value, field, fallback) {
  if (value === undefined || value === null || value === "") return fallback;
  if (typeof value !== "string" || !value.trim()) {
    throw configError(`${field} 必须是非空字符串`);
  }
  return value.trim();
}

function absolutePath(value, field, fallback) {
  const path = nonEmptyString(value, field, fallback);
  if (!isAbsolute(path)) {
    throw configError(`${field} 必须是绝对路径`);
  }
  return path;
}

export function normalizePort(value, fallback = DEFAULT_CONFIG.port) {
  if (value === undefined || value === null || value === "") return fallback;
  const port = Number(value);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    throw configError("浏览器调试端口必须在 1024 到 65535 之间");
  }
  return port;
}

export function normalizeEndpoint(value, expectedPort) {
  const raw = String(value || "")
    .trim()
    .replace(/\/+$/, "");
  if (!raw) {
    const port = normalizePort(expectedPort, DEFAULT_CONFIG.port);
    return `http://127.0.0.1:${port}`;
  }
  let parsed;
  try {
    parsed = new URL(raw);
  } catch {
    throw configError("浏览器调试端点不是有效 URL");
  }
  if (!["127.0.0.1", "localhost", "[::1]"].includes(parsed.hostname)) {
    throw configError("浏览器调试端点必须绑定在本机");
  }
  if (parsed.protocol !== "http:") {
    throw configError("浏览器调试端点只支持 HTTP");
  }
  if (parsed.username || parsed.password) {
    throw configError("浏览器调试端点不能包含账号或密码");
  }
  if (parsed.pathname !== "/" || parsed.search || parsed.hash) {
    throw configError("浏览器调试端点不能包含路径、查询参数或片段");
  }

  const portFromEndpoint = parsed.port ? Number(parsed.port) : undefined;
  const port = normalizePort(
    expectedPort ?? portFromEndpoint,
    DEFAULT_CONFIG.port,
  );
  if (portFromEndpoint && portFromEndpoint !== port) {
    throw configError("端点端口与配置端口不一致");
  }
  parsed.port = String(port);
  return parsed.toString().replace(/\/+$/, "");
}

export function loadRuntimeConfig(path = CONFIG_PATH) {
  if (!existsSync(path)) return { ...DEFAULT_CONFIG };
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    throw configError(
      `无法读取 ${path}（${error instanceof Error ? error.message : String(error)}）`,
    );
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw configError("根对象必须是 JSON 对象");
  }

  const endpointCandidate = nonEmptyString(
    parsed.endpoint,
    "endpoint",
    DEFAULT_CONFIG.endpoint,
  );
  let endpointPort;
  try {
    endpointPort = new URL(endpointCandidate).port || undefined;
  } catch {}
  const port = normalizePort(parsed.port ?? endpointPort, DEFAULT_CONFIG.port);
  const endpoint = normalizeEndpoint(endpointCandidate, port);

  return {
    browserId: nonEmptyString(
      parsed.browserId,
      "browserId",
      DEFAULT_CONFIG.browserId,
    ),
    browserName: nonEmptyString(
      parsed.browserName,
      "browserName",
      DEFAULT_CONFIG.browserName,
    ),
    browserPath: absolutePath(
      parsed.browserPath,
      "browserPath",
      DEFAULT_CONFIG.browserPath,
    ),
    endpoint,
    port,
    profilePath: absolutePath(
      parsed.profilePath,
      "profilePath",
      DEFAULT_CONFIG.profilePath,
    ),
    ...(typeof parsed.updatedAt === "string"
      ? { updatedAt: parsed.updatedAt }
      : {}),
  };
}
