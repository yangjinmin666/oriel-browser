import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { createTaskGovernance } from "./task-governance.mjs";

function temporaryGovernance(sessionId = "test-session") {
  const directory = mkdtempSync(join(tmpdir(), "oriel-governance-test-"));
  const statePath = join(directory, "task-governance.json");
  return {
    directory,
    statePath,
    governance: createTaskGovernance({
      statePath,
      profileId: "temporary-profile",
      sessionId,
    }),
  };
}

test("default policy blocks browser writes until one explicit approval", () => {
  const { directory, governance } = temporaryGovernance();
  try {
    governance.registerTask({ id: 7 });
    assert.throws(
      () => governance.authorizeRpcWrite(7, "open-tab"),
      (error) => error?.code === "ORIEL_APPROVAL_REQUIRED",
    );

    governance.approveNextAction(7);
    governance.authorizeCDP(7, "Page.navigate");
    assert.equal(
      governance.decorateTaskSpace({ id: 7 }).lifecycle.approvalAvailable,
      false,
    );
    assert.throws(
      () => governance.authorizeCDP(7, "Runtime.evaluate"),
      (error) => error?.code === "ORIEL_APPROVAL_REQUIRED",
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("read-only and draft policies both preserve a safe recovery path", () => {
  const { directory, governance } = temporaryGovernance();
  try {
    governance.registerTask({ id: 8 });
    governance.setPolicy(8, "read-only");
    assert.throws(
      () => governance.authorizeRpcWrite(8, "open-tab"),
      (error) => error?.code === "ORIEL_READ_ONLY_BLOCKED",
    );
    assert.deepEqual(governance.decorateTaskSpace({ id: 8 }).lifecycle.lastFailure, {
      code: "ORIEL_READ_ONLY_BLOCKED",
      safeRecovery: "change-policy",
    });

    governance.setPolicy(8, "draft");
    assert.throws(
      () => governance.authorizeCDP(8, "Page.navigate"),
      (error) => error?.code === "ORIEL_DRAFT_ONLY",
    );
    governance.recover(8);
    assert.equal(governance.decorateTaskSpace({ id: 8 }).lifecycle.status, "running");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("audit remains local, metadata-only, and survives a daemon session restart", () => {
  const { directory, statePath, governance } = temporaryGovernance("first-session");
  try {
    governance.registerTask({ id: 9 });
    governance.handOff(9);
    governance.hardStop(9);
    governance.takeOver(9);
    governance.recordFailure(9, "task-command");

    const saved = readFileSync(statePath, "utf8");
    assert.equal(statSync(statePath).mode & 0o777, 0o600);
    assert.equal(saved.includes("https://"), false);
    assert.equal(saved.includes("cookie"), false);
    assert.equal(saved.includes("Runtime.evaluate"), false);

    const restarted = createTaskGovernance({
      statePath,
      profileId: "temporary-profile",
      sessionId: "second-session",
    });
    const events = restarted.listAudit().events;
    assert.equal(events.some((event) => event.type === "control.handed-off"), true);
    assert.equal(events.some((event) => event.type === "agent.hard-stopped"), true);
    assert.equal(events.some((event) => event.type === "task.failed"), true);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("handoff clears an unused approval and hard-stops even read-only CDP commands", () => {
  const { directory, governance } = temporaryGovernance();
  try {
    governance.registerTask({ id: 10 });
    governance.approveNextAction(10);
    governance.handOff(10);
    assert.equal(
      governance.decorateTaskSpace({ id: 10 }).lifecycle.approvalAvailable,
      false,
    );
    assert.throws(
      () => governance.authorizeCDP(10, "Target.attachToTarget"),
      (error) => error?.code === "SIDECAR_AGENT_CONTROL_REQUIRED",
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
