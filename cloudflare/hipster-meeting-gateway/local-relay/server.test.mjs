import assert from "node:assert/strict";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { createRelayHandler, isMainModulePath } from "./server.mjs";

const SHARED_SECRET = "test-only-shared-secret-that-is-long-enough";

test("recognizes the relay entrypoint on file URLs without extra Linux slashes", () => {
  const currentPath = fileURLToPath(import.meta.url).replace(
    /server\.test\.mjs$/u,
    "server.mjs",
  );
  assert.equal(isMainModulePath(`file://${currentPath}`, currentPath), false);
  assert.equal(
    isMainModulePath(new URL("./server.mjs", import.meta.url).href, currentPath),
    true,
  );
});

function relayRequest(body, headers = {}) {
  return new Request("http://relay.invalid/meetings", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

test("rejects unauthenticated requests without calling Hipster", async () => {
  let called = false;
  const handler = createRelayHandler({
    sharedSecret: SHARED_SECRET,
    fetchImplementation: async () => {
      called = true;
      throw new Error("must not run");
    },
  });
  const response = await handler(relayRequest({ type: "agent" }));
  assert.equal(response.status, 401);
  assert.equal(called, false);
});

test("forwards only the validated JSON body and current server key", async () => {
  let capturedBody;
  let capturedKey;
  const currentPayload = {
    status: "success",
    data: {
      meeting: { MeetingId: "meeting-id" },
      attendee: { JoinToken: "current-token" },
    },
  };
  const handler = createRelayHandler({
    sharedSecret: SHARED_SECRET,
    fetchImplementation: async (_url, init) => {
      capturedBody = init.body;
      capturedKey = new Headers(init.headers).get("x-api-key");
      return new Response(JSON.stringify(currentPayload), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    },
  });
  const response = await handler(
    relayRequest(
      { type: "agent" },
      {
        Authorization: `Bearer ${SHARED_SECRET}`,
        "x-relay-hipster-key": "current-server-key",
      },
    ),
  );
  assert.equal(response.status, 200);
  assert.equal(capturedBody, '{"type":"agent"}');
  assert.equal(capturedKey, "current-server-key");
  assert.deepEqual(await response.json(), currentPayload);
});

test("rejects extra payload fields before calling Hipster", async () => {
  let called = false;
  const handler = createRelayHandler({
    sharedSecret: SHARED_SECRET,
    fetchImplementation: async () => {
      called = true;
      throw new Error("must not run");
    },
  });
  const response = await handler(
    relayRequest(
      { type: "agent", arbitrary: true },
      {
        Authorization: `Bearer ${SHARED_SECRET}`,
        "x-relay-hipster-key": "current-server-key",
      },
    ),
  );
  assert.equal(response.status, 400);
  assert.equal(called, false);
});
