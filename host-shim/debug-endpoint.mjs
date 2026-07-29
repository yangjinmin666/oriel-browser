const LOOPBACK_HOSTS = new Set(["127.0.0.1", "localhost", "::1", "[::1]"]);

function isLoopbackHost(hostname) {
  return LOOPBACK_HOSTS.has(String(hostname || "").toLowerCase());
}

function endpointUrl(endpoint) {
  const base = new URL(endpoint);
  return new URL("/json/version", base);
}

export function isChromiumDebugVersion(version, endpoint) {
  if (!version || typeof version !== "object") return false;
  if (typeof version.Browser !== "string" || !version.Browser.trim()) {
    return false;
  }
  if (
    typeof version.webSocketDebuggerUrl !== "string" ||
    !version.webSocketDebuggerUrl.trim()
  ) {
    return false;
  }

  try {
    const expected = new URL(endpoint);
    const debuggerUrl = new URL(version.webSocketDebuggerUrl);
    return (
      debuggerUrl.protocol === "ws:" &&
      isLoopbackHost(expected.hostname) &&
      isLoopbackHost(debuggerUrl.hostname) &&
      debuggerUrl.port === expected.port
    );
  } catch {
    return false;
  }
}

export async function inspectDebugEndpoint(
  endpoint,
  { fetchImpl = fetch, timeoutMs = 1_500 } = {},
) {
  try {
    const response = await fetchImpl(endpointUrl(endpoint), {
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!response.ok) {
      return { ready: false, reason: "http-status" };
    }
    const version = await response.json();
    if (!isChromiumDebugVersion(version, endpoint)) {
      return { ready: false, reason: "not-chromium-devtools" };
    }
    return { ready: true, version };
  } catch {
    return { ready: false, reason: "unreachable" };
  }
}
