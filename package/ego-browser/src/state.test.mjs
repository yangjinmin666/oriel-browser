import assert from "node:assert/strict";
import test from "node:test";

import { send } from "../dist/src/state.js";

test("default state transport loads the browser runtime without a static cycle", async () => {
  const previousEgo = globalThis.ego;
  const sent = [];
  const ego = {
    sendCDPMessage(payload) {
      const request = JSON.parse(payload);
      sent.push(request);
      queueMicrotask(() => {
        ego.onCDPMessage?.(
          JSON.stringify({ id: request.id, result: { product: "Oriel" } }),
        );
      });
    },
  };
  globalThis.ego = ego;
  try {
    const response = await send({ method: "Browser.getVersion" });
    assert.deepEqual(response, { result: { product: "Oriel" } });
    assert.equal(sent[0].method, "Browser.getVersion");
  } finally {
    if (previousEgo === undefined) {
      delete globalThis.ego;
    } else {
      globalThis.ego = previousEgo;
    }
  }
});
