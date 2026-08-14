import { describe, expect, it, vi } from "vitest";

import {
  HIPSTER_UPSTREAM_TIMEOUT_MS,
  HttpHipsterClient,
  UpstreamTimeoutError,
} from "../src/hipster-client";
import { ConsoleGatewayLogger, createGatewayHandler } from "../src/index";
import type {
  GatewayLogEntry,
  GatewayLogger,
  HipsterClient,
  HipsterRelayConfig,
  HipsterUpstreamResponse,
  MeetingContext,
  MeetingContextStore,
  MeetingRequest,
} from "../src/types";

const NOW_MS = 1_800_000_000_000;
const NOW_SECONDS = Math.floor(NOW_MS / 1000);
const API_KEY = "unit-test-server-key";
const MEETING_ID = "meeting-A";

const placement = {
  AudioHostUrl: "https://audio.invalid",
  AudioFallbackUrl: "https://fallback.invalid",
  SignalingUrl: "https://signal.invalid",
  TurnControlUrl: "https://turn.invalid",
  EventIngestionUrl: "https://events.invalid",
};

class FakeHipsterClient implements HipsterClient {
  readonly calls: Array<{
    request: MeetingRequest;
    apiKey: string;
    relay?: HipsterRelayConfig;
  }> = [];

  constructor(private readonly response: HipsterUpstreamResponse) {}

  async postMeeting(
    request: MeetingRequest,
    apiKey: string,
    relay?: HipsterRelayConfig,
  ): Promise<HipsterUpstreamResponse> {
    this.calls.push({
      request,
      apiKey,
      ...(relay === undefined ? {} : { relay }),
    });
    return this.response;
  }
}

class FakeMeetingContextStore implements MeetingContextStore {
  readonly upserts: MeetingContext[] = [];
  readonly reads: string[] = [];
  readonly deletes: string[] = [];
  context: MeetingContext | null = null;
  readError: unknown;
  writeError: unknown;

  async get(meetingId: string): Promise<MeetingContext | null> {
    this.reads.push(meetingId);
    if (this.readError !== undefined) {
      throw this.readError;
    }
    return this.context;
  }

  async upsert(context: MeetingContext): Promise<void> {
    if (this.writeError !== undefined) {
      throw this.writeError;
    }
    this.upserts.push(context);
  }

  async delete(meetingId: string): Promise<void> {
    this.deletes.push(meetingId);
  }
}

class RecordingLogger implements GatewayLogger {
  readonly entries: GatewayLogEntry[] = [];

  log(entry: GatewayLogEntry): void {
    this.entries.push(entry);
  }
}

function successPayload(options: {
  meetingId?: string;
  includePlacement?: boolean;
  attendeeId?: string;
  joinToken?: string;
} = {}): Record<string, unknown> {
  return {
    status: "success",
    data: {
      meeting: {
        MeetingId: options.meetingId ?? MEETING_ID,
        MediaRegion: "region-1",
        ...(options.includePlacement === false
          ? {}
          : { MediaPlacement: placement }),
      },
      attendee: {
        AttendeeId: options.attendeeId ?? "current-attendee",
        JoinToken: options.joinToken ?? "current-join-token",
        ExternalUserId: "current-user",
      },
    },
  };
}

function upstreamSuccess(payload = successPayload()): HipsterUpstreamResponse {
  return { status: 200, payload, isJson: true };
}

function request(
  body: unknown,
  options: { method?: string; path?: string; headers?: HeadersInit } = {},
): Request {
  const headers = new Headers(options.headers);
  if (!headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  const method = options.method ?? "POST";
  const serializedBody =
    method === "GET" || method === "OPTIONS"
      ? undefined
      : typeof body === "string"
        ? body
        : JSON.stringify(body);
  return new Request(`https://gateway.invalid${options.path ?? "/meetings"}`, {
    method,
    headers,
    ...(serializedBody === undefined ? {} : { body: serializedBody }),
  });
}

function buildHandler(
  upstream: HipsterClient,
  store: MeetingContextStore,
  logger: GatewayLogger = new RecordingLogger(),
) {
  return createGatewayHandler({
    hipsterClient: upstream,
    meetingContextStore: store,
    logger,
    now: () => NOW_MS,
    requestId: () => "request-id",
  });
}

async function responseJson(response: Response): Promise<Record<string, unknown>> {
  return (await response.json()) as Record<string, unknown>;
}

function cachedContext(
  overrides: Partial<MeetingContext> = {},
): MeetingContext {
  return {
    meetingId: MEETING_ID,
    mediaPlacement: placement,
    mediaRegion: "cached-region",
    createdAt: NOW_SECONDS - 60,
    expiresAt: NOW_SECONDS + 60,
    ...overrides,
  };
}

describe("meeting gateway", () => {
  it("emits an indexed structured log object instead of a JSON string", () => {
    const consoleSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    try {
      const entry: GatewayLogEntry = {
        event: "meeting_gateway_request",
        requestId: "request-id",
        route: "/meetings",
        method: "POST",
        upstreamStatus: 502,
        resultCategory: "upstream_rejected",
        durationMs: 816,
      };

      new ConsoleGatewayLogger().log(entry);

      expect(consoleSpy).toHaveBeenCalledOnce();
      expect(consoleSpy).toHaveBeenCalledWith(entry);
      expect(typeof consoleSpy.mock.calls[0]?.[0]).toBe("object");
    } finally {
      consoleSpy.mockRestore();
    }
  });

  it("records a sanitized cause category for create failures", async () => {
    const rejectedLogger = new RecordingLogger();
    const rejectedResponse = await buildHandler(
      new FakeHipsterClient({
        status: 502,
        payload: { sensitive: "never logged" },
        isJson: true,
      }),
      new FakeMeetingContextStore(),
      rejectedLogger,
    )(request({ type: "agent" }), { HIPSTER_API_KEY: API_KEY });

    const missingPlacementLogger = new RecordingLogger();
    const missingPlacementResponse = await buildHandler(
      new FakeHipsterClient(
        upstreamSuccess(successPayload({ includePlacement: false })),
      ),
      new FakeMeetingContextStore(),
      missingPlacementLogger,
    )(request({ type: "agent" }), { HIPSTER_API_KEY: API_KEY });

    expect(rejectedResponse.status).toBe(502);
    expect(rejectedLogger.entries[0]).toMatchObject({
      resultCategory: "upstream_rejected",
      upstreamStatus: 502,
    });
    expect(missingPlacementResponse.status).toBe(502);
    expect(missingPlacementLogger.entries[0]).toMatchObject({
      resultCategory: "create_missing_placement",
      upstreamStatus: 200,
    });
    expect(JSON.stringify(rejectedLogger.entries)).not.toContain("never logged");
  });

  it("keeps the upstream timeout inside Flutter's outer deadline", async () => {
    vi.useFakeTimers();
    try {
      let capturedSignal: AbortSignal | undefined;
      const fetchMock = vi.fn(
        async (_input: RequestInfo | URL, init?: RequestInit) =>
          new Promise<Response>((_resolve, reject) => {
            capturedSignal = init?.signal ?? undefined;
            capturedSignal?.addEventListener(
              "abort",
              () => reject(new DOMException("Aborted", "AbortError")),
              { once: true },
            );
          }),
      );
      const client = new HttpHipsterClient(
        fetchMock as unknown as typeof fetch,
      );
      const result = client.postMeeting({ type: "agent" }, API_KEY);

      await vi.advanceTimersByTimeAsync(HIPSTER_UPSTREAM_TIMEOUT_MS - 1);
      expect(capturedSignal?.aborted).toBe(false);

      const rejection = expect(result).rejects.toBeInstanceOf(
        UpstreamTimeoutError,
      );
      await vi.advanceTimersByTimeAsync(1);
      await rejection;

      expect(HIPSTER_UPSTREAM_TIMEOUT_MS).toBe(12_000);
      expect(HIPSTER_UPSTREAM_TIMEOUT_MS).toBeLessThan(15_000);
    } finally {
      vi.useRealTimers();
    }
  });

  it("calls the Workers global fetch with the correct receiver", async () => {
    let observedReceiver: unknown;
    const originalFetch = globalThis.fetch;
    const receiverCheckingFetch = vi.fn(function (
      this: unknown,
      _input: RequestInfo | URL,
      _init?: RequestInit,
    ): Promise<Response> {
      observedReceiver = this;
      return Promise.resolve(
        new Response(JSON.stringify(successPayload()), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    });
    globalThis.fetch = receiverCheckingFetch as unknown as typeof fetch;

    try {
      const client = new HttpHipsterClient();
      const response = await client.postMeeting({ type: "agent" }, API_KEY);

      expect(response.status).toBe(200);
      expect(observedReceiver).toBe(globalThis);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("classifies an invalid upstream header without exposing its message", async () => {
    const client = new HttpHipsterClient(
      vi.fn(async () => {
        throw new TypeError("Invalid header value containing sensitive text");
      }) as unknown as typeof fetch,
    );

    await expect(
      client.postMeeting({ type: "agent" }, API_KEY),
    ).rejects.toMatchObject({
      name: "UpstreamNetworkError",
      message: "The upstream request failed.",
      resultCategory: "upstream_invalid_header",
    });
  });

  it("forwards create as the exact agent body", async () => {
    const upstream = new FakeHipsterClient(upstreamSuccess());
    const store = new FakeMeetingContextStore();
    const response = await buildHandler(upstream, store)(
      request({ type: "agent" }),
      { HIPSTER_API_KEY: API_KEY },
    );

    expect(response.status).toBe(200);
    expect(upstream.calls).toEqual([
      { request: { type: "agent" }, apiKey: API_KEY },
    ]);
  });

  it("injects the server key and never accepts a client-controlled upstream key", async () => {
    let capturedHeaders: Headers | undefined;
    let capturedBody: string | undefined;
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      capturedHeaders = new Headers(init?.headers);
      capturedBody = init?.body as string;
      return new Response(JSON.stringify(successPayload()), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    });
    const upstream = new HttpHipsterClient(fetchMock as unknown as typeof fetch);
    const store = new FakeMeetingContextStore();
    const response = await buildHandler(upstream, store)(
      request(
        { type: "agent" },
        { headers: { "x-api-key": "client-controlled-value" } },
      ),
      { HIPSTER_API_KEY: API_KEY },
    );

    expect(response.status).toBe(200);
    expect(capturedHeaders?.get("x-api-key")).toBe(API_KEY);
    expect(capturedHeaders?.get("x-api-key")).not.toBe(
      "client-controlled-value",
    );
    expect(JSON.parse(capturedBody ?? "null")).toEqual({ type: "agent" });
  });

  it("routes through the authenticated relay without exposing it to Flutter", async () => {
    let capturedUrl = "";
    let capturedHeaders = new Headers();
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      capturedUrl = input.toString();
      capturedHeaders = new Headers(init?.headers);
      return new Response(JSON.stringify(successPayload()), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    });
    const handler = buildHandler(
      new HttpHipsterClient(fetchMock as unknown as typeof fetch),
      new FakeMeetingContextStore(),
    );
    const response = await handler(request({ type: "agent" }), {
      HIPSTER_API_KEY: API_KEY,
      HIPSTER_RELAY_URL: "https://relay.invalid/random-path?ignored=true",
      RELAY_SHARED_SECRET: "relay-shared-secret-that-is-long-enough",
    });

    expect(response.status).toBe(200);
    expect(capturedUrl).toBe("https://relay.invalid/meetings");
    expect(capturedHeaders.get("authorization")).toBe(
      "Bearer relay-shared-secret-that-is-long-enough",
    );
    expect(capturedHeaders.get("x-relay-hipster-key")).toBe(API_KEY);
    expect(capturedHeaders.has("x-api-key")).toBe(false);
  });

  it("fails closed when only part of the relay configuration exists", async () => {
    const upstream = new FakeHipsterClient(upstreamSuccess());
    const response = await buildHandler(
      upstream,
      new FakeMeetingContextStore(),
    )(request({ type: "agent" }), {
      HIPSTER_API_KEY: API_KEY,
      HIPSTER_RELAY_URL: "https://relay.invalid",
    });

    expect(response.status).toBe(503);
    expect(upstream.calls).toHaveLength(0);
  });

  it("forwards the trimmed exact client meeting ID", async () => {
    const upstream = new FakeHipsterClient(upstreamSuccess());
    const store = new FakeMeetingContextStore();
    const response = await buildHandler(upstream, store)(
      request({ type: "client", meeting_id: `  ${MEETING_ID}  ` }),
      { HIPSTER_API_KEY: API_KEY },
    );

    expect(response.status).toBe(200);
    expect(upstream.calls[0]?.request).toEqual({
      type: "client",
      meeting_id: MEETING_ID,
    });
  });

  it("accepts an agent attendee request for an existing meeting", async () => {
    const upstream = new FakeHipsterClient(upstreamSuccess());
    const store = new FakeMeetingContextStore();
    const response = await buildHandler(upstream, store)(
      request({ type: "agent", meeting_id: MEETING_ID }),
      { HIPSTER_API_KEY: API_KEY },
    );

    expect(response.status).toBe(200);
    expect(upstream.calls[0]?.request).toEqual({
      type: "agent",
      meeting_id: MEETING_ID,
    });
  });

  it("stores only create meeting context and waits for persistence", async () => {
    const upstream = new FakeHipsterClient(upstreamSuccess());
    const store = new FakeMeetingContextStore();
    const response = await buildHandler(upstream, store)(
      request({ type: "agent" }),
      { HIPSTER_API_KEY: API_KEY },
    );

    expect(response.status).toBe(200);
    expect(store.upserts).toHaveLength(1);
    expect(store.upserts[0]).toEqual({
      meetingId: MEETING_ID,
      mediaPlacement: placement,
      mediaRegion: "region-1",
      createdAt: NOW_SECONDS,
      expiresAt: NOW_SECONDS + 86_400,
    });
    const stored = JSON.stringify(store.upserts);
    expect(stored).not.toContain("current-join-token");
    expect(stored).not.toContain("current-attendee");
    expect(stored).not.toContain("current-user");
  });

  it("fails create when context persistence fails", async () => {
    const upstream = new FakeHipsterClient(upstreamSuccess());
    const store = new FakeMeetingContextStore();
    store.writeError = new Error("database unavailable");
    const response = await buildHandler(upstream, store)(
      request({ type: "agent" }),
      { HIPSTER_API_KEY: API_KEY },
    );

    expect(response.status).toBe(503);
    expect(await responseJson(response)).toEqual({
      status: "error",
      error: { code: "CONTEXT_PERSISTENCE_FAILED" },
    });
    expect(upstream.calls).toHaveLength(1);
  });

  it("prefers upstream placement and refreshes context", async () => {
    const upstream = new FakeHipsterClient(upstreamSuccess());
    const store = new FakeMeetingContextStore();
    store.context = cachedContext({
      mediaPlacement: { ...placement, AudioHostUrl: "https://old.invalid" },
    });
    const response = await buildHandler(upstream, store)(
      request({ type: "client", meeting_id: MEETING_ID }),
      { HIPSTER_API_KEY: API_KEY },
    );
    const payload = await responseJson(response);

    expect(response.status).toBe(200);
    expect(store.reads).toEqual([]);
    expect(store.upserts[0]?.mediaPlacement).toEqual(placement);
    expect(
      ((payload.data as Record<string, unknown>).meeting as Record<
        string,
        unknown
      >).MediaPlacement,
    ).toEqual(placement);
  });

  it("uses matching non-expired context when join placement is omitted", async () => {
    const upstream = new FakeHipsterClient(
      upstreamSuccess(successPayload({ includePlacement: false })),
    );
    const store = new FakeMeetingContextStore();
    store.context = cachedContext();
    const response = await buildHandler(upstream, store)(
      request({ type: "client", meeting_id: MEETING_ID }),
      { HIPSTER_API_KEY: API_KEY },
    );
    const payload = await responseJson(response);
    const meeting = (payload.data as Record<string, unknown>)
      .meeting as Record<string, unknown>;

    expect(store.reads).toEqual([MEETING_ID]);
    expect(meeting.MediaPlacement).toEqual(placement);
  });

  it("never replaces the current attendee while merging cached placement", async () => {
    const currentAttendee = {
      AttendeeId: "fresh-attendee",
      JoinToken: "fresh-token",
      ExternalUserId: "fresh-user",
      Extra: "preserved",
    };
    const payload = successPayload({ includePlacement: false });
    (payload.data as Record<string, unknown>).attendee = currentAttendee;
    const upstream = new FakeHipsterClient(upstreamSuccess(payload));
    const store = new FakeMeetingContextStore();
    store.context = cachedContext();
    const response = await buildHandler(upstream, store)(
      request({ type: "client", meeting_id: MEETING_ID }),
      { HIPSTER_API_KEY: API_KEY },
    );
    const returned = await responseJson(response);

    expect((returned.data as Record<string, unknown>).attendee).toEqual(
      currentAttendee,
    );
  });

  it("never uses context returned for a different meeting ID", async () => {
    const upstream = new FakeHipsterClient(
      upstreamSuccess(successPayload({ includePlacement: false })),
    );
    const store = new FakeMeetingContextStore();
    store.context = cachedContext({ meetingId: "meeting-B" });
    const response = await buildHandler(upstream, store)(
      request({ type: "client", meeting_id: MEETING_ID }),
      { HIPSTER_API_KEY: API_KEY },
    );
    const payload = await responseJson(response);
    const meeting = (payload.data as Record<string, unknown>)
      .meeting as Record<string, unknown>;

    expect(meeting.MediaPlacement).toBeUndefined();
  });

  it("rejects an upstream response for a different requested meeting", async () => {
    const upstream = new FakeHipsterClient(
      upstreamSuccess(
        successPayload({ meetingId: "meeting-B", includePlacement: false }),
      ),
    );
    const store = new FakeMeetingContextStore();
    store.context = cachedContext();
    const response = await buildHandler(upstream, store)(
      request({ type: "client", meeting_id: MEETING_ID }),
      { HIPSTER_API_KEY: API_KEY },
    );

    expect(response.status).toBe(502);
    expect(store.reads).toEqual([]);
  });

  it("ignores and best-effort deletes expired context", async () => {
    const upstream = new FakeHipsterClient(
      upstreamSuccess(successPayload({ includePlacement: false })),
    );
    const store = new FakeMeetingContextStore();
    store.context = cachedContext({ expiresAt: NOW_SECONDS });
    const response = await buildHandler(upstream, store)(
      request({ type: "client", meeting_id: MEETING_ID }),
      { HIPSTER_API_KEY: API_KEY },
    );
    const payload = await responseJson(response);
    const meeting = (payload.data as Record<string, unknown>)
      .meeting as Record<string, unknown>;

    expect(meeting.MediaPlacement).toBeUndefined();
    expect(store.deletes).toEqual([MEETING_ID]);
  });

  it("ignores and best-effort deletes malformed cached placement", async () => {
    const upstream = new FakeHipsterClient(
      upstreamSuccess(successPayload({ includePlacement: false })),
    );
    const store = new FakeMeetingContextStore();
    store.context = cachedContext({ mediaPlacement: { AudioHostUrl: "only-one" } });
    const response = await buildHandler(upstream, store)(
      request({ type: "client", meeting_id: MEETING_ID }),
      { HIPSTER_API_KEY: API_KEY },
    );
    const payload = await responseJson(response);
    const meeting = (payload.data as Record<string, unknown>)
      .meeting as Record<string, unknown>;

    expect(meeting.MediaPlacement).toBeUndefined();
    expect(store.deletes).toEqual([MEETING_ID]);
  });

  it("leaves join unchanged when context is missing", async () => {
    const original = successPayload({ includePlacement: false });
    const upstream = new FakeHipsterClient(upstreamSuccess(original));
    const store = new FakeMeetingContextStore();
    const response = await buildHandler(upstream, store)(
      request({ type: "client", meeting_id: MEETING_ID }),
      { HIPSTER_API_KEY: API_KEY },
    );

    expect(await responseJson(response)).toEqual(original);
  });

  it("leaves join unchanged when D1 is temporarily unavailable", async () => {
    const original = successPayload({ includePlacement: false });
    const upstream = new FakeHipsterClient(upstreamSuccess(original));
    const store = new FakeMeetingContextStore();
    store.readError = new Error("database unavailable");
    const response = await buildHandler(upstream, store)(
      request({ type: "client", meeting_id: MEETING_ID }),
      { HIPSTER_API_KEY: API_KEY },
    );

    expect(response.status).toBe(200);
    expect(await responseJson(response)).toEqual(original);
  });

  it("returns 400 for malformed JSON", async () => {
    const upstream = new FakeHipsterClient(upstreamSuccess());
    const response = await buildHandler(
      upstream,
      new FakeMeetingContextStore(),
    )(request("{"), { HIPSTER_API_KEY: API_KEY });

    expect(response.status).toBe(400);
    expect(upstream.calls).toHaveLength(0);
  });

  it("returns 400 for unsupported types and extra fields", async () => {
    const upstream = new FakeHipsterClient(upstreamSuccess());
    const handler = buildHandler(upstream, new FakeMeetingContextStore());

    const unsupported = await handler(request({ type: "observer" }), {
      HIPSTER_API_KEY: API_KEY,
    });
    const extra = await handler(
      request({ type: "agent", arbitrary: true }),
      { HIPSTER_API_KEY: API_KEY },
    );

    expect(unsupported.status).toBe(400);
    expect(extra.status).toBe(400);
    expect(upstream.calls).toHaveLength(0);
  });

  it("returns 413 when the streaming body exceeds 8 KB", async () => {
    const upstream = new FakeHipsterClient(upstreamSuccess());
    const response = await buildHandler(
      upstream,
      new FakeMeetingContextStore(),
    )(
      request(JSON.stringify({ type: "agent", padding: "x".repeat(8192) })),
      { HIPSTER_API_KEY: API_KEY },
    );

    expect(response.status).toBe(413);
    expect(upstream.calls).toHaveLength(0);
  });

  it("returns 405 for unsupported methods on known routes", async () => {
    const response = await buildHandler(
      new FakeHipsterClient(upstreamSuccess()),
      new FakeMeetingContextStore(),
    )(request(null, { method: "GET" }), { HIPSTER_API_KEY: API_KEY });

    expect(response.status).toBe(405);
    expect(response.headers.get("Allow")).toBe("POST, OPTIONS");
  });

  it("returns 404 for unknown routes", async () => {
    const response = await buildHandler(
      new FakeHipsterClient(upstreamSuccess()),
      new FakeMeetingContextStore(),
    )(request(null, { method: "GET", path: "/unknown" }), {
      HIPSTER_API_KEY: API_KEY,
    });

    expect(response.status).toBe(404);
  });

  it("supports health and CORS preflight with hardened response headers", async () => {
    const handler = buildHandler(
      new FakeHipsterClient(upstreamSuccess()),
      new FakeMeetingContextStore(),
    );
    const health = await handler(
      request(null, { method: "GET", path: "/health" }),
      {},
    );
    const preflight = await handler(
      request(null, { method: "OPTIONS" }),
      {},
    );

    expect(health.status).toBe(200);
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(preflight.headers.get("Cache-Control")).toBe("no-store");
    expect(preflight.headers.get("X-Content-Type-Options")).toBe("nosniff");
  });

  it("returns safe 503 and never calls upstream when the secret is absent", async () => {
    const upstream = new FakeHipsterClient(upstreamSuccess());
    const response = await buildHandler(
      upstream,
      new FakeMeetingContextStore(),
    )(request({ type: "agent" }), {});

    expect(response.status).toBe(503);
    expect(upstream.calls).toHaveLength(0);

    const blankResponse = await buildHandler(
      upstream,
      new FakeMeetingContextStore(),
    )(request({ type: "agent" }), { HIPSTER_API_KEY: "   " });
    expect(blankResponse.status).toBe(503);
    expect(upstream.calls).toHaveLength(0);
  });

  it("returns sanitized diagnostic headers on failures", async () => {
    const response = await buildHandler(
      new FakeHipsterClient({
        status: 502,
        payload: { sensitive: "not-returned" },
        isJson: true,
      }),
      new FakeMeetingContextStore(),
    )(request({ type: "agent" }), { HIPSTER_API_KEY: API_KEY });

    expect(response.headers.get("X-Request-Id")).toBe("request-id");
    expect(response.headers.get("X-Gateway-Result-Category")).toBe(
      "upstream_rejected",
    );
    expect(response.headers.get("X-Upstream-Status")).toBe("502");
    expect(response.headers.get("Access-Control-Expose-Headers")).toContain(
      "X-Gateway-Result-Category",
    );
  });

  it("normalizes surrounding secret whitespace before constructing the header", async () => {
    const upstream = new FakeHipsterClient(upstreamSuccess());
    const response = await buildHandler(
      upstream,
      new FakeMeetingContextStore(),
    )(request({ type: "agent" }), {
      HIPSTER_API_KEY: `  ${API_KEY}\r\n`,
    });

    expect(response.status).toBe(200);
    expect(upstream.calls[0]?.apiKey).toBe(API_KEY);
  });

  it("rejects embedded secret control characters before upstream fetch", async () => {
    const upstream = new FakeHipsterClient(upstreamSuccess());
    const logger = new RecordingLogger();
    const response = await buildHandler(
      upstream,
      new FakeMeetingContextStore(),
      logger,
    )(request({ type: "agent" }), {
      HIPSTER_API_KEY: `prefix\n${API_KEY}`,
    });

    expect(response.status).toBe(503);
    expect(upstream.calls).toHaveLength(0);
    expect(logger.entries[0]?.resultCategory).toBe(
      "invalid_worker_secret_format",
    );
  });

  it("preserves a safe upstream success status and rejects missing attendees", async () => {
    const created = await buildHandler(
      new FakeHipsterClient({
        status: 201,
        payload: successPayload(),
        isJson: true,
      }),
      new FakeMeetingContextStore(),
    )(request({ type: "agent" }), { HIPSTER_API_KEY: API_KEY });

    const missingAttendeePayload = successPayload();
    delete (missingAttendeePayload.data as Record<string, unknown>).attendee;
    const malformed = await buildHandler(
      new FakeHipsterClient(upstreamSuccess(missingAttendeePayload)),
      new FakeMeetingContextStore(),
    )(request({ type: "agent" }), { HIPSTER_API_KEY: API_KEY });

    expect(created.status).toBe(201);
    expect(malformed.status).toBe(502);
  });

  it("sanitizes non-JSON and non-success upstream responses", async () => {
    const nonJson = await buildHandler(
      new FakeHipsterClient({ status: 200, payload: null, isJson: false }),
      new FakeMeetingContextStore(),
    )(request({ type: "agent" }), { HIPSTER_API_KEY: API_KEY });
    const rejected = await buildHandler(
      new FakeHipsterClient({
        status: 401,
        payload: { sensitive: "not-returned" },
        isJson: true,
      }),
      new FakeMeetingContextStore(),
    )(request({ type: "agent" }), { HIPSTER_API_KEY: API_KEY });

    expect(nonJson.status).toBe(502);
    expect(JSON.stringify(await responseJson(nonJson))).not.toContain("sensitive");
    expect(rejected.status).toBe(401);
    expect(JSON.stringify(await responseJson(rejected))).not.toContain(
      "not-returned",
    );
  });

  it("reports only categorical metadata for a non-JSON upstream challenge", async () => {
    const fetchMock = vi.fn(async () =>
      new Response("challenge content must not be returned", {
        status: 202,
        headers: {
          "Content-Type": "text/html; charset=UTF-8",
          "sg-captcha": "challenge-value-must-not-be-logged",
          Location: "https://challenge.invalid/sensitive-path",
        },
      }),
    );
    const upstream = new HttpHipsterClient(
      fetchMock as unknown as typeof fetch,
    );
    const logger = new RecordingLogger();
    const response = await buildHandler(
      upstream,
      new FakeMeetingContextStore(),
      logger,
    )(request({ type: "agent" }), { HIPSTER_API_KEY: API_KEY });

    expect(response.status).toBe(502);
    expect(response.headers.get("X-Gateway-Result-Category")).toBe(
      "upstream_anti_bot_challenge",
    );
    expect(response.headers.get("X-Upstream-Status")).toBe("202");
    expect(response.headers.get("X-Upstream-Content-Type-Category")).toBe(
      "html",
    );
    expect(response.headers.get("X-Upstream-Sg-Captcha-Present")).toBe(
      "true",
    );
    expect(response.headers.get("X-Upstream-Location-Present")).toBe("true");
    expect(logger.entries[0]).toMatchObject({
      resultCategory: "upstream_anti_bot_challenge",
      upstreamStatus: 202,
      upstreamContentTypeCategory: "html",
      upstreamSgCaptchaPresent: true,
      upstreamLocationPresent: true,
    });
    const serialized = JSON.stringify(logger.entries);
    expect(serialized).not.toContain("challenge-value-must-not-be-logged");
    expect(serialized).not.toContain("sensitive-path");
    expect(serialized).not.toContain("challenge content");
  });

  it("never writes a raw JoinToken or response payload to logs", async () => {
    const tokenFixture = "raw-token-that-must-not-be-logged";
    const logger = new RecordingLogger();
    const upstream = new FakeHipsterClient(
      upstreamSuccess(
        successPayload({
          includePlacement: false,
          joinToken: tokenFixture,
          attendeeId: "sensitive-attendee-id",
        }),
      ),
    );
    const store = new FakeMeetingContextStore();
    store.context = cachedContext();
    await buildHandler(upstream, store, logger)(
      request({ type: "client", meeting_id: MEETING_ID }),
      { HIPSTER_API_KEY: API_KEY },
    );

    const logs = JSON.stringify(logger.entries);
    expect(logs).not.toContain(tokenFixture);
    expect(logs).not.toContain("sensitive-attendee-id");
    expect(logs).not.toContain(MEETING_ID);
    expect(logs).not.toContain(placement.AudioHostUrl);
  });
});
