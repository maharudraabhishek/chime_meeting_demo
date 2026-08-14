import { createServer } from "node:http";
import { timingSafeEqual } from "node:crypto";
import { pathToFileURL } from "node:url";

const HIPSTER_MEETINGS_URL = "https://assess.hipster-dev.com/api/meetings";
const MAX_REQUEST_BYTES = 8 * 1024;
const MAX_RESPONSE_BYTES = 256 * 1024;
const UPSTREAM_TIMEOUT_MS = 12_000;

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

function jsonResponse(status, code) {
  return new Response(
    JSON.stringify({ status: "error", error: { code } }),
    { status, headers: JSON_HEADERS },
  );
}

function secretsMatch(actual, expected) {
  const actualBytes = Buffer.from(actual);
  const expectedBytes = Buffer.from(expected);
  return (
    actualBytes.length === expectedBytes.length &&
    timingSafeEqual(actualBytes, expectedBytes)
  );
}

async function readBoundedBody(stream, maximumBytes) {
  if (stream === null) return null;
  const reader = stream.getReader();
  const chunks = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > maximumBytes) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const result = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

function validateMeetingRequest(value) {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  const keys = Object.keys(value);
  if (keys.some((key) => key !== "type" && key !== "meeting_id")) {
    return null;
  }
  if (value.type !== "agent" && value.type !== "client") return null;
  if (value.meeting_id === undefined) {
    return value.type === "agent" ? { type: "agent" } : null;
  }
  if (typeof value.meeting_id !== "string") return null;
  const meetingId = value.meeting_id.trim();
  if (meetingId.length === 0 || meetingId.length > 128) return null;
  return { type: value.type, meeting_id: meetingId };
}

export function createRelayHandler({ sharedSecret, fetchImplementation = fetch }) {
  if (typeof sharedSecret !== "string" || sharedSecret.length < 32) {
    throw new Error("Local relay authentication is not configured.");
  }

  return async function handle(request) {
    const url = new URL(request.url);
    if (url.pathname === "/health" && request.method === "GET") {
      return new Response(JSON.stringify({ status: "ok" }), {
        status: 200,
        headers: JSON_HEADERS,
      });
    }
    if (url.pathname !== "/meetings") {
      return jsonResponse(404, "NOT_FOUND");
    }
    if (request.method !== "POST") {
      return jsonResponse(405, "METHOD_NOT_ALLOWED");
    }

    const authorization = request.headers.get("authorization") ?? "";
    const expectedAuthorization = `Bearer ${sharedSecret}`;
    if (!secretsMatch(authorization, expectedAuthorization)) {
      return jsonResponse(401, "UNAUTHORIZED");
    }

    const hipsterApiKey = request.headers.get("x-relay-hipster-key")?.trim();
    if (
      hipsterApiKey === undefined ||
      hipsterApiKey.length === 0 ||
      /[\u0000-\u001f\u007f]/u.test(hipsterApiKey)
    ) {
      return jsonResponse(400, "INVALID_UPSTREAM_CREDENTIAL");
    }

    const bodyBytes = await readBoundedBody(request.body, MAX_REQUEST_BYTES);
    if (bodyBytes === null) return jsonResponse(400, "INVALID_REQUEST");

    let body;
    try {
      body = validateMeetingRequest(
        JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bodyBytes)),
      );
    } catch {
      body = null;
    }
    if (body === null) return jsonResponse(400, "INVALID_REQUEST");

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);
    try {
      const upstream = await fetchImplementation(HIPSTER_MEETINGS_URL, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          "x-api-key": hipsterApiKey,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      const responseBytes = await readBoundedBody(
        upstream.body,
        MAX_RESPONSE_BYTES,
      );
      if (responseBytes === null) {
        return jsonResponse(502, "INVALID_UPSTREAM_RESPONSE");
      }
      return new Response(responseBytes, {
        status: upstream.status,
        headers: {
          ...JSON_HEADERS,
          "Content-Type":
            upstream.headers.get("content-type") ?? "application/octet-stream",
        },
      });
    } catch {
      return jsonResponse(
        controller.signal.aborted ? 504 : 502,
        controller.signal.aborted
          ? "UPSTREAM_TIMEOUT"
          : "UPSTREAM_UNAVAILABLE",
      );
    } finally {
      clearTimeout(timeout);
    }
  };
}

function toWebRequest(request) {
  const host = request.headers.host ?? "127.0.0.1";
  const headers = new Headers();
  for (const [name, value] of Object.entries(request.headers)) {
    if (value === undefined) continue;
    headers.set(name, Array.isArray(value) ? value.join(", ") : value);
  }
  return new Request(`http://${host}${request.url ?? "/"}`, {
    method: request.method,
    headers,
    body:
      request.method === "GET" || request.method === "HEAD"
        ? undefined
        : request,
    duplex: "half",
  });
}

function sendNodeResponse(nodeResponse, response) {
  nodeResponse.statusCode = response.status;
  for (const [name, value] of response.headers.entries()) {
    nodeResponse.setHeader(name, value);
  }
  if (response.body === null) {
    nodeResponse.end();
    return;
  }
  const reader = response.body.getReader();
  const pump = async () => {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      nodeResponse.write(Buffer.from(value));
    }
    nodeResponse.end();
  };
  void pump().catch(() => nodeResponse.destroy());
}

export function isMainModulePath(moduleUrl, argvPath) {
  return argvPath !== undefined && moduleUrl === pathToFileURL(argvPath).href;
}

const isMainModule =
  process.argv[1] !== undefined &&
  isMainModulePath(import.meta.url, process.argv[1]);

if (isMainModule) {
  const sharedSecret = process.env.RELAY_SHARED_SECRET;
  const port = Number(process.env.PORT ?? process.env.RELAY_PORT ?? "8788");
  const bindHost = process.env.RELAY_BIND_HOST ?? "127.0.0.1";
  if (typeof sharedSecret !== "string" || sharedSecret.length < 32) {
    console.error("Local relay configuration is missing.");
    process.exit(1);
  }
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    console.error("Local relay port is invalid.");
    process.exit(1);
  }
  if (typeof bindHost !== "string" || bindHost.length === 0) {
    console.error("Local relay bind host is invalid.");
    process.exit(1);
  }
  const handler = createRelayHandler({ sharedSecret });
  const server = createServer((request, response) => {
    void handler(toWebRequest(request))
      .then((result) => sendNodeResponse(response, result))
      .catch(() => sendNodeResponse(response, jsonResponse(500, "INTERNAL_ERROR")));
  });
  server.listen(port, bindHost, () => {
    console.log(`Local relay ready on ${bindHost}:${port}`);
  });
}
