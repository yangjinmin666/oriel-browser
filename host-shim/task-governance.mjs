import { randomUUID } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { dirname } from "node:path";

export const EXECUTION_POLICIES = Object.freeze([
  "read-only",
  "draft",
  "requires-approval",
]);

const MAX_AUDIT_EVENTS = 500;
const SAFE_CDP_PREFIXES = Object.freeze([
  "Accessibility.",
  "CSS.get",
  "DOM.get",
  "DOM.describe",
  "DOM.query",
  "DOM.performSearch",
  "DOM.discardSearchResults",
  "DOM.request",
  "Network.get",
  "Page.captureScreenshot",
  "Page.get",
  "Page.printToPDF",
  "Performance.get",
  "Target.attachToTarget",
  "Target.detachFromTarget",
  "Target.get",
  "Browser.get",
]);

const SAFE_CDP_METHODS = new Set([
  "Accessibility.enable",
  "Accessibility.disable",
  "CSS.enable",
  "CSS.disable",
  "DOM.enable",
  "DOM.disable",
  "Network.enable",
  "Network.disable",
  "Page.enable",
  "Page.disable",
  "Page.getNavigationHistory",
  "Runtime.enable",
  "Runtime.disable",
]);

export class ExecutionPolicyError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "ExecutionPolicyError";
    this.code = code;
  }
}

function now() {
  return new Date().toISOString();
}

function runtimeIdFrom(spaceOrId) {
  const value =
    typeof spaceOrId === "object" && spaceOrId !== null
      ? spaceOrId.id
      : spaceOrId;
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function isPolicy(value) {
  return EXECUTION_POLICIES.includes(value);
}

function normaliseFailure(failure) {
  if (!failure || typeof failure !== "object") return null;
  const code = typeof failure.code === "string" ? failure.code : null;
  const recovery =
    typeof failure.safeRecovery === "string" ? failure.safeRecovery : null;
  return code && recovery ? { code, safeRecovery: recovery } : null;
}

function emptyState(profileId) {
  return {
    schemaVersion: 1,
    profileId,
    updatedAt: now(),
    tasks: {},
    events: [],
  };
}

function loadState(path, profileId) {
  if (!existsSync(path)) return emptyState(profileId);
  try {
    const parsed = JSON.parse(readFileSync(path, "utf8"));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return emptyState(profileId);
    }
    return {
      schemaVersion: 1,
      profileId,
      updatedAt: typeof parsed.updatedAt === "string" ? parsed.updatedAt : now(),
      tasks:
        parsed.tasks && typeof parsed.tasks === "object" && !Array.isArray(parsed.tasks)
          ? parsed.tasks
          : {},
      events: Array.isArray(parsed.events) ? parsed.events.slice(-MAX_AUDIT_EVENTS) : [],
    };
  } catch {
    // Governance must fail closed without making a corrupt local log prevent a
    // user from reopening Oriel. Preserve the original file and start a new log.
    return emptyState(profileId);
  }
}

/**
 * Local, metadata-only policy and lifecycle journal for one daemon instance.
 * It intentionally stores no URLs, page text, cookies, input values, or raw
 * browser errors. A runtime task id is only unique within a daemon session, so
 * every persisted task reference includes an opaque daemon session id.
 */
export function createTaskGovernance({ statePath, profileId, sessionId = randomUUID() }) {
  if (typeof statePath !== "string" || !statePath) {
    throw new Error("task governance requires a local state path");
  }
  const state = loadState(statePath, profileId);

  function taskRef(runtimeId) {
    return `${sessionId}:${runtimeId}`;
  }

  function persist() {
    state.updatedAt = now();
    mkdirSync(dirname(statePath), { recursive: true, mode: 0o700 });
    const temporaryPath = `${statePath}.${process.pid}.${randomUUID()}.tmp`;
    try {
      writeFileSync(temporaryPath, `${JSON.stringify(state, null, 2)}\n`, {
        mode: 0o600,
      });
      renameSync(temporaryPath, statePath);
    } finally {
      if (existsSync(temporaryPath)) {
        try {
          unlinkSync(temporaryPath);
        } catch {}
      }
    }
  }

  function event(runtimeId, type, fields = {}) {
    state.events.push({
      id: randomUUID(),
      at: now(),
      taskRef: taskRef(runtimeId),
      runtimeId,
      type,
      ...fields,
    });
    if (state.events.length > MAX_AUDIT_EVENTS) {
      state.events.splice(0, state.events.length - MAX_AUDIT_EVENTS);
    }
  }

  function recordFor(runtimeId, create = true) {
    if (!runtimeId) return null;
    const ref = taskRef(runtimeId);
    let record = state.tasks[ref];
    if (!record && create) {
      record = {
        runtimeId,
        sessionId,
        policy: "requires-approval",
        approvalAvailable: false,
        status: "running",
        stage: "created",
        startedAt: now(),
        endedAt: null,
        lastFailure: null,
      };
      state.tasks[ref] = record;
      event(runtimeId, "task.created", { actor: "agent", stage: "created" });
      persist();
    }
    return record || null;
  }

  function update(runtimeId, mutate, type, fields = {}) {
    const record = recordFor(runtimeId);
    if (!record) return null;
    mutate(record);
    event(runtimeId, type, fields);
    persist();
    return record;
  }

  function blocked(runtimeId, descriptor, code, safeRecovery) {
    const record = recordFor(runtimeId);
    if (!record) {
      throw new ExecutionPolicyError(
        "ORIEL_TASK_SPACE_REQUIRED",
        "A named Oriel task space is required before a browser change",
      );
    }
    record.status = "blocked";
    record.stage =
      code === "ORIEL_DRAFT_ONLY"
        ? "draft-ready"
        : code === "ORIEL_APPROVAL_REQUIRED"
          ? "approval-required"
          : "policy-blocked";
    record.lastFailure = { code, safeRecovery };
    event(runtimeId, "action.blocked", {
      actor: "agent",
      action: descriptor.action,
      code,
      safeRecovery,
    });
    persist();
  }

  function authorizeWrite(runtimeId, descriptor) {
    const record = recordFor(runtimeId, false);
    if (!record) {
      throw new ExecutionPolicyError(
        "ORIEL_TASK_SPACE_REQUIRED",
        "A named Oriel task space is required before a browser change",
      );
    }
    if (record.status === "handed-off") {
      throw new ExecutionPolicyError(
        "SIDECAR_AGENT_CONTROL_REQUIRED",
        "SIDECAR_AGENT_CONTROL_REQUIRED: 用户持有控制权，这是硬停止，不要重试",
      );
    }
    if (record.policy === "read-only") {
      blocked(
        runtimeId,
        descriptor,
        "ORIEL_READ_ONLY_BLOCKED",
        "change-policy",
      );
      throw new ExecutionPolicyError(
        "ORIEL_READ_ONLY_BLOCKED",
        "This task is read-only; browser changes are blocked",
      );
    }
    if (record.policy === "draft") {
      blocked(runtimeId, descriptor, "ORIEL_DRAFT_ONLY", "review-draft");
      throw new ExecutionPolicyError(
        "ORIEL_DRAFT_ONLY",
        "This task is in draft mode; browser changes are blocked",
      );
    }
    if (!record.approvalAvailable) {
      blocked(
        runtimeId,
        descriptor,
        "ORIEL_APPROVAL_REQUIRED",
        "approve-next-action",
      );
      throw new ExecutionPolicyError(
        "ORIEL_APPROVAL_REQUIRED",
        "Approval is required before the next browser change",
      );
    }
    record.approvalAvailable = false;
    record.status = "running";
    record.stage = "action-approved";
    record.lastFailure = null;
    event(runtimeId, "action.allowed", {
      actor: "agent",
      action: descriptor.action,
      approval: "consumed",
    });
    persist();
  }

  function isReadOnlyCDP(method) {
    if (SAFE_CDP_METHODS.has(method)) return true;
    return SAFE_CDP_PREFIXES.some((prefix) => method.startsWith(prefix));
  }

  return {
    profileId,
    sessionId,
    statePath,

    registerTask(space) {
      const runtimeId = runtimeIdFrom(space);
      if (!runtimeId) return null;
      return recordFor(runtimeId);
    },

    taskForRuntimeId(runtimeId) {
      return recordFor(runtimeId, false);
    },

    decorateTaskSpace(space) {
      const runtimeId = runtimeIdFrom(space);
      const record = recordFor(runtimeId);
      if (!record) return space;
      return {
        ...space,
        executionPolicy: record.policy,
        lifecycle: {
          status: record.status,
          stage: record.stage,
          startedAt: record.startedAt,
          ...(record.endedAt ? { endedAt: record.endedAt } : {}),
          approvalAvailable: record.approvalAvailable,
          ...(record.lastFailure ? { lastFailure: record.lastFailure } : {}),
        },
        auditEventCount: state.events.filter(
          (entry) => entry.taskRef === taskRef(runtimeId),
        ).length,
      };
    },

    listAudit(runtimeId = undefined) {
      const parsed = runtimeId === undefined ? null : runtimeIdFrom(runtimeId);
      const events = state.events.filter(
        (entry) =>
          parsed === null || entry.taskRef === taskRef(parsed),
      );
      return { events };
    },

    setPolicy(runtimeId, policy) {
      const parsed = runtimeIdFrom(runtimeId);
      if (!parsed) throw new Error("task policy requires a task space id");
      if (!isPolicy(policy)) {
        throw new Error(`unsupported execution policy: ${String(policy)}`);
      }
      return update(
        parsed,
        (record) => {
          record.policy = policy;
          record.approvalAvailable = false;
          record.status = "running";
          record.stage = "policy-updated";
          record.lastFailure = null;
        },
        "policy.changed",
        { actor: "user", policy },
      );
    },

    approveNextAction(runtimeId) {
      const parsed = runtimeIdFrom(runtimeId);
      const record = recordFor(parsed, false);
      if (!record) throw new Error("task approval requires an active task space");
      if (record.policy !== "requires-approval") {
        throw new ExecutionPolicyError(
          "ORIEL_APPROVAL_NOT_APPLICABLE",
          "Only tasks that require approval can approve a browser change",
        );
      }
      return update(
        parsed,
        (entry) => {
          entry.approvalAvailable = true;
          entry.status = "running";
          entry.stage = "approval-granted";
          entry.lastFailure = null;
        },
        "approval.granted",
        { actor: "user", scope: "next-browser-change" },
      );
    },

    recover(runtimeId) {
      const parsed = runtimeIdFrom(runtimeId);
      const record = recordFor(parsed, false);
      if (!record) throw new Error("task recovery requires an active task space");
      return update(
        parsed,
        (entry) => {
          entry.status = "running";
          entry.stage = "recovery-ready";
          entry.lastFailure = null;
          entry.approvalAvailable = false;
        },
        "recovery.requested",
        { actor: "user", safeRecovery: "retry-safe-step" },
      );
    },

    notePrepared(runtimeId) {
      if (!runtimeId) return;
      update(
        runtimeId,
        (record) => {
          record.status = "running";
          record.stage = "prepared";
          record.lastFailure = null;
        },
        "browser.prepared",
        { actor: "agent", action: "open-about-blank" },
      );
    },

    handOff(runtimeId) {
      if (!runtimeId) return;
      update(
        runtimeId,
        (record) => {
          record.status = "handed-off";
          record.stage = "waiting-for-user";
          record.approvalAvailable = false;
        },
        "control.handed-off",
        { actor: "user" },
      );
    },

    takeOver(runtimeId) {
      if (!runtimeId) return;
      update(
        runtimeId,
        (record) => {
          record.status = "running";
          record.stage = "resumed";
          record.lastFailure = null;
        },
        "control.resumed",
        { actor: "user" },
      );
    },

    complete(runtimeId) {
      if (!runtimeId) return;
      update(
        runtimeId,
        (record) => {
          record.status = "completed";
          record.stage = "complete";
          record.endedAt = now();
          record.approvalAvailable = false;
        },
        "task.completed",
        { actor: "agent" },
      );
    },

    close(runtimeId) {
      if (!runtimeId) return;
      update(
        runtimeId,
        (record) => {
          record.status = "stopped";
          record.stage = "closed";
          record.endedAt = now();
          record.approvalAvailable = false;
        },
        "task.closed",
        { actor: "user" },
      );
    },

    hardStop(runtimeId) {
      if (!runtimeId) return;
      update(
        runtimeId,
        (record) => {
          record.status = "handed-off";
          record.stage = "waiting-for-user";
        },
        "agent.hard-stopped",
        { actor: "system", code: "SIDECAR_AGENT_CONTROL_REQUIRED" },
      );
    },

    recordFailure(runtimeId, action) {
      if (!runtimeId) return;
      update(
        runtimeId,
        (record) => {
          record.status = "failed";
          record.stage = "failed";
          record.lastFailure = {
            code: "ORIEL_BROWSER_ACTION_FAILED",
            safeRecovery: "retry-safe-step",
          };
        },
        "task.failed",
        {
          actor: "system",
          action,
          code: "ORIEL_BROWSER_ACTION_FAILED",
          safeRecovery: "retry-safe-step",
        },
      );
    },

    authorizeRpcWrite(runtimeId, action) {
      authorizeWrite(runtimeId, { action });
    },

    authorizeCDP(runtimeId, method) {
      const record = recordFor(runtimeId, false);
      if (record?.status === "handed-off") {
        throw new ExecutionPolicyError(
          "SIDECAR_AGENT_CONTROL_REQUIRED",
          "SIDECAR_AGENT_CONTROL_REQUIRED: 用户持有控制权，这是硬停止，不要重试",
        );
      }
      if (isReadOnlyCDP(method)) return;
      authorizeWrite(runtimeId, { action: `cdp:${method}` });
    },

    safeFailure(error) {
      return normaliseFailure(error?.lastFailure);
    },
  };
}
