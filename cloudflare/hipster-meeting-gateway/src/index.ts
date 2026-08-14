import {
  HttpHipsterClient,
  UpstreamNetworkError,
  UpstreamTimeoutError,
} from "./hipster-client";
import { D1MeetingContextStore } from "./meeting-context-store";
import type {
  GatewayEnv,
  GatewayLogEntry,
  GatewayLogger,
  HipsterClient,
  HipsterRelayConfig,
  JsonObject,
  MediaPlacement,
  MeetingContext,
  MeetingContextStore,
  MeetingRequest,
} from "./types";
import {
  asMediaPlacement,
  CONTEXT_RETENTION_SECONDS,
  isJsonObject,
  MAX_MEETING_ID_LENGTH,
  MAX_REQUEST_BODY_BYTES,
  readNonEmptyString,
  toCacheableMediaPlacement,
} from "./types";

const BASE_RESPONSE_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Expose-Headers":
    "X-Request-Id, X-Gateway-Result-Category, X-Upstream-Status, " +
    "X-Upstream-Content-Type-Category, X-Upstream-Sg-Captcha-Present, " +
    "X-Upstream-Location-Present",
} as const;

export class ConsoleGatewayLogger implements GatewayLogger {
  log(entry: GatewayLogEntry): void {
    // Pass the object itself so Workers Logs indexes each allow-listed field.
    // Stringifying here collapses the event into one unqueryable message.
    console.log(entry);
  }
}

interface GatewayDependencies {
  readonly hipsterClient?: HipsterClient;
  readonly meetingContextStore?: MeetingContextStore;
  readonly logger?: GatewayLogger;
  readonly now?: () => number;
  readonly requestId?: () => string;
}

interface RequestResult {
  readonly response: Response;
  readonly resultCategory: string;
  readonly upstreamStatus?: number;
  readonly upstreamContentTypeCategory?: "json" | "html" | "other" | "absent";
  readonly upstreamSgCaptchaPresent?: boolean;
  readonly upstreamLocationPresent?: boolean;
  readonly contextCacheHit?: boolean;
}

class RequestValidationError extends Error {}
class RequestBodyTooLargeError extends Error {}

export function createGatewayHandler(
  dependencies: GatewayDependencies = {},
): (request: Request, env: GatewayEnv) => Promise<Response> {
  const hipsterClient = dependencies.hipsterClient ?? new HttpHipsterClient();
  const logger = dependencies.logger ?? new ConsoleGatewayLogger();
  const now = dependencies.now ?? (() => Date.now());
  const makeRequestId = dependencies.requestId ?? (() => crypto.randomUUID());

  return async (request: Request, env: GatewayEnv): Promise<Response> => {
    const startedAt = now();
    const requestId = makeRequestId();
    const url = new URL(request.url);
    let result: RequestResult;

    try {
      result = await routeRequest({
        request,
        path: url.pathname,
        env,
        requestId,
        hipsterClient,
        injectedStore: dependencies.meetingContextStore,
        now,
      });
    } catch (error: unknown) {
      if (error instanceof RequestBodyTooLargeError) {
        result = errorResult(413, "REQUEST_TOO_LARGE", "request_too_large");
      } else if (error instanceof RequestValidationError) {
        result = errorResult(400, "INVALID_REQUEST", "invalid_request");
      } else if (error instanceof UpstreamTimeoutError) {
        result = errorResult(504, "UPSTREAM_TIMEOUT", "upstream_timeout");
      } else if (error instanceof UpstreamNetworkError) {
        result = errorResult(
          502,
          "UPSTREAM_UNAVAILABLE",
          error.resultCategory,
        );
      } else {
        result = errorResult(500, "INTERNAL_ERROR", "unexpected_error");
      }
    }

    const durationMs = Math.max(0, now() - startedAt);
    logger.log({
      event: "meeting_gateway_request",
      requestId,
      route: url.pathname,
      method: request.method,
      ...(result.upstreamStatus === undefined
        ? {}
        : { upstreamStatus: result.upstreamStatus }),
      ...(result.upstreamContentTypeCategory === undefined
        ? {}
        : {
            upstreamContentTypeCategory:
              result.upstreamContentTypeCategory,
          }),
      ...(result.upstreamSgCaptchaPresent === undefined
        ? {}
        : { upstreamSgCaptchaPresent: result.upstreamSgCaptchaPresent }),
      ...(result.upstreamLocationPresent === undefined
        ? {}
        : { upstreamLocationPresent: result.upstreamLocationPresent }),
      resultCategory: result.resultCategory,
      durationMs,
      ...(result.contextCacheHit === undefined
        ? {}
        : { contextCacheHit: result.contextCacheHit }),
    });

    const headers = new Headers(result.response.headers);
    headers.set("X-Request-Id", requestId);
    headers.set("X-Gateway-Result-Category", result.resultCategory);
    if (result.upstreamStatus !== undefined) {
      headers.set("X-Upstream-Status", result.upstreamStatus.toString());
    }
    if (result.upstreamContentTypeCategory !== undefined) {
      headers.set(
        "X-Upstream-Content-Type-Category",
        result.upstreamContentTypeCategory,
      );
    }
    if (result.upstreamSgCaptchaPresent !== undefined) {
      headers.set(
        "X-Upstream-Sg-Captcha-Present",
        result.upstreamSgCaptchaPresent.toString(),
      );
    }
    if (result.upstreamLocationPresent !== undefined) {
      headers.set(
        "X-Upstream-Location-Present",
        result.upstreamLocationPresent.toString(),
      );
    }
    return new Response(result.response.body, {
      status: result.response.status,
      statusText: result.response.statusText,
      headers,
    });
  };
}

interface RouteRequestArguments {
  readonly request: Request;
  readonly path: string;
  readonly env: GatewayEnv;
  readonly requestId: string;
  readonly hipsterClient: HipsterClient;
  readonly injectedStore: MeetingContextStore | undefined;
  readonly now: () => number;
}

async function routeRequest({
  request,
  path,
  env,
  hipsterClient,
  injectedStore,
  now,
}: RouteRequestArguments): Promise<RequestResult> {
  if (path !== "/meetings" && path !== "/health") {
    return errorResult(404, "NOT_FOUND", "route_not_found");
  }

  if (request.method === "OPTIONS") {
    return {
      response: new Response(null, {
        status: 204,
        headers: {
          ...BASE_RESPONSE_HEADERS,
          "Access-Control-Allow-Methods":
            path === "/meetings" ? "POST, OPTIONS" : "GET, OPTIONS",
          "Access-Control-Allow-Headers": "Accept, Content-Type",
          "Access-Control-Max-Age": "86400",
        },
      }),
      resultCategory: "cors_preflight",
    };
  }

  if (path === "/health") {
    if (request.method !== "GET") {
      return methodNotAllowed("GET, OPTIONS");
    }
    return {
      response: jsonResponse(200, { status: "ok" }),
      resultCategory: "healthy",
    };
  }

  if (request.method !== "POST") {
    return methodNotAllowed("POST, OPTIONS");
  }

  const secret = env.HIPSTER_API_KEY;
  if (typeof secret !== "string") {
    return errorResult(503, "SERVICE_NOT_CONFIGURED", "missing_worker_secret");
  }
  const normalizedSecret = secret.trim();
  if (normalizedSecret.length === 0) {
    return errorResult(503, "SERVICE_NOT_CONFIGURED", "missing_worker_secret");
  }
  if (/[\u0000-\u001f\u007f]/u.test(normalizedSecret)) {
    return errorResult(
      503,
      "SERVICE_NOT_CONFIGURED",
      "invalid_worker_secret_format",
    );
  }

  const store =
    injectedStore ??
    (env.DB === undefined ? undefined : new D1MeetingContextStore(env.DB));
  if (store === undefined) {
    return errorResult(503, "SERVICE_NOT_CONFIGURED", "missing_d1_binding");
  }

  const meetingRequest = await parseMeetingRequest(request);
  const relay = readRelayConfig(env);
  if (relay === null) {
    return errorResult(
      503,
      "SERVICE_NOT_CONFIGURED",
      "invalid_relay_configuration",
    );
  }
  const upstream = await hipsterClient.postMeeting(
    meetingRequest,
    normalizedSecret,
    relay,
  );

  if (upstream.status < 200 || upstream.status >= 300) {
    return {
      ...errorResult(
        safeUpstreamStatus(upstream.status),
        "UPSTREAM_REJECTED",
        "upstream_rejected",
      ),
      upstreamStatus: upstream.status,
    };
  }

  if (!upstream.isJson) {
    const isSiteGroundChallenge =
      upstream.status === 202 && upstream.sgCaptchaPresent === true;
    return {
      ...errorResult(
        502,
        isSiteGroundChallenge
          ? "UPSTREAM_ANTI_BOT_CHALLENGE"
          : "INVALID_UPSTREAM_RESPONSE",
        isSiteGroundChallenge
          ? "upstream_anti_bot_challenge"
          : "upstream_non_json",
      ),
      upstreamStatus: upstream.status,
      ...(upstream.contentTypeCategory === undefined
        ? {}
        : { upstreamContentTypeCategory: upstream.contentTypeCategory }),
      ...(upstream.sgCaptchaPresent === undefined
        ? {}
        : { upstreamSgCaptchaPresent: upstream.sgCaptchaPresent }),
      ...(upstream.locationPresent === undefined
        ? {}
        : { upstreamLocationPresent: upstream.locationPresent }),
    };
  }

  const envelope = readSuccessEnvelope(upstream.payload);
  if (envelope === null) {
    return {
      ...errorResult(502, "INVALID_UPSTREAM_RESPONSE", "upstream_invalid_success"),
      upstreamStatus: upstream.status,
    };
  }

  const requestedMeetingId = meetingRequest.meeting_id;
  if (
    requestedMeetingId !== undefined &&
    envelope.meetingId !== requestedMeetingId
  ) {
    return {
      ...errorResult(502, "INVALID_UPSTREAM_RESPONSE", "meeting_id_mismatch"),
      upstreamStatus: upstream.status,
    };
  }

  const upstreamPlacement = asMediaPlacement(
    envelope.meeting.MediaPlacement,
  );
  const mediaRegion = readOptionalNonEmptyString(envelope.meeting.MediaRegion);
  const currentEpochSeconds = Math.floor(now() / 1000);

  if (requestedMeetingId === undefined) {
    if (upstreamPlacement === null) {
      return {
        ...errorResult(502, "INVALID_UPSTREAM_RESPONSE", "create_missing_placement"),
        upstreamStatus: upstream.status,
      };
    }

    const context = makeContext(
      envelope.meetingId,
      upstreamPlacement,
      mediaRegion,
      currentEpochSeconds,
    );
    try {
      await store.upsert(context);
    } catch (error: unknown) {
      return {
        ...errorResult(503, "CONTEXT_PERSISTENCE_FAILED", "create_context_write_failed"),
        upstreamStatus: upstream.status,
      };
    }

    return {
      response: jsonResponse(upstream.status, upstream.payload),
      resultCategory: "create_success",
      upstreamStatus: upstream.status,
    };
  }

  if (upstreamPlacement !== null) {
    const context = makeContext(
      envelope.meetingId,
      upstreamPlacement,
      mediaRegion,
      currentEpochSeconds,
    );
    let refreshFailed = false;
    try {
      await store.upsert(context);
    } catch (error: unknown) {
      // The current upstream response is already complete. Cache refresh failure
      // must not discard fresh attendee credentials or valid placement.
      refreshFailed = true;
    }
    return {
      response: jsonResponse(upstream.status, upstream.payload),
      resultCategory: refreshFailed
        ? "existing_meeting_context_refresh_failed"
        : "existing_meeting_upstream_placement",
      upstreamStatus: upstream.status,
      contextCacheHit: false,
    };
  }

  let cachedContext: MeetingContext | null;
  try {
    cachedContext = await store.get(envelope.meetingId);
  } catch (error: unknown) {
    return {
      response: jsonResponse(upstream.status, upstream.payload),
      resultCategory: "context_read_unavailable",
      upstreamStatus: upstream.status,
      contextCacheHit: false,
    };
  }

  if (
    cachedContext === null ||
    cachedContext.meetingId !== envelope.meetingId
  ) {
    return {
      response: jsonResponse(upstream.status, upstream.payload),
      resultCategory: "context_miss",
      upstreamStatus: upstream.status,
      contextCacheHit: false,
    };
  }

  const cachedPlacement = asMediaPlacement(cachedContext.mediaPlacement);
  if (
    cachedContext.expiresAt <= currentEpochSeconds ||
    cachedPlacement === null
  ) {
    try {
      await store.delete(cachedContext.meetingId);
    } catch (error: unknown) {
      // Expired or malformed state is already ignored; deletion is best-effort.
    }
    return {
      response: jsonResponse(upstream.status, upstream.payload),
      resultCategory:
        cachedContext.expiresAt <= currentEpochSeconds
          ? "context_expired"
          : "context_malformed",
      upstreamStatus: upstream.status,
      contextCacheHit: false,
    };
  }

  const mergedMeeting: JsonObject = {
    ...envelope.meeting,
    MediaPlacement: toCacheableMediaPlacement(cachedPlacement),
    ...(mediaRegion === undefined && cachedContext.mediaRegion !== undefined
      ? { MediaRegion: cachedContext.mediaRegion }
      : {}),
  };
  const mergedPayload: JsonObject = {
    ...envelope.payload,
    data: {
      ...envelope.data,
      meeting: mergedMeeting,
    },
  };

  return {
    response: jsonResponse(upstream.status, mergedPayload),
    resultCategory: "context_hit",
    upstreamStatus: upstream.status,
    contextCacheHit: true,
  };
}

function readRelayConfig(env: GatewayEnv): HipsterRelayConfig | null | undefined {
  const rawUrl = env.HIPSTER_RELAY_URL;
  const rawSharedSecret = env.RELAY_SHARED_SECRET;
  if (rawUrl === undefined && rawSharedSecret === undefined) return undefined;
  if (typeof rawUrl !== "string" || typeof rawSharedSecret !== "string") {
    return null;
  }
  const sharedSecret = rawSharedSecret.trim();
  if (
    sharedSecret.length < 32 ||
    /[\u0000-\u001f\u007f]/u.test(sharedSecret)
  ) {
    return null;
  }
  let url: URL;
  try {
    url = new URL(rawUrl.trim());
  } catch {
    return null;
  }
  if (
    url.protocol !== "https:" ||
    url.host.length === 0 ||
    url.username.length > 0 ||
    url.password.length > 0
  ) {
    return null;
  }
  if (url.hostname !== "script.google.com") {
    url.pathname = "/meetings";
  }
  url.search = "";
  url.hash = "";
  const protocol = url.hostname === "script.google.com" ? "apps_script" : "headers";
  return { url: url.toString(), sharedSecret, protocol };
}

interface SuccessEnvelope {
  readonly payload: JsonObject;
  readonly data: JsonObject;
  readonly meeting: JsonObject;
  readonly meetingId: string;
}

function readSuccessEnvelope(value: unknown): SuccessEnvelope | null {
  if (!isJsonObject(value) || value.status !== "success") {
    return null;
  }
  const data = value.data;
  if (
    !isJsonObject(data) ||
    !isJsonObject(data.meeting) ||
    !isJsonObject(data.attendee)
  ) {
    return null;
  }
  const meetingId = readNonEmptyString(data.meeting.MeetingId);
  if (
    meetingId === null ||
    readNonEmptyString(data.attendee.AttendeeId) === null ||
    readNonEmptyString(data.attendee.JoinToken) === null ||
    readNonEmptyString(data.attendee.ExternalUserId) === null
  ) {
    return null;
  }
  return { payload: value, data, meeting: data.meeting, meetingId };
}

async function parseMeetingRequest(request: Request): Promise<MeetingRequest> {
  const contentLength = request.headers.get("Content-Length");
  if (contentLength !== null) {
    const parsedLength = Number(contentLength);
    if (Number.isFinite(parsedLength) && parsedLength > MAX_REQUEST_BODY_BYTES) {
      throw new RequestBodyTooLargeError();
    }
  }

  if (request.body === null) {
    throw new RequestValidationError();
  }

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let byteLength = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    byteLength += value.byteLength;
    if (byteLength > MAX_REQUEST_BODY_BYTES) {
      void reader.cancel().catch(() => undefined);
      throw new RequestBodyTooLargeError();
    }
    chunks.push(value);
  }

  const bytes = new Uint8Array(byteLength);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  let decoded: string;
  try {
    decoded = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch (error: unknown) {
    throw new RequestValidationError();
  }

  let value: unknown;
  try {
    value = JSON.parse(decoded) as unknown;
  } catch (error: unknown) {
    throw new RequestValidationError();
  }

  if (!isJsonObject(value)) {
    throw new RequestValidationError();
  }
  const allowedKeys = new Set(["type", "meeting_id"]);
  if (Object.keys(value).some((key) => !allowedKeys.has(key))) {
    throw new RequestValidationError();
  }
  if (value.type !== "agent" && value.type !== "client") {
    throw new RequestValidationError();
  }

  if (value.meeting_id === undefined) {
    if (value.type === "client") {
      throw new RequestValidationError();
    }
    return { type: "agent" };
  }
  if (typeof value.meeting_id !== "string") {
    throw new RequestValidationError();
  }
  const meetingId = value.meeting_id.trim();
  if (meetingId.length === 0 || meetingId.length > MAX_MEETING_ID_LENGTH) {
    throw new RequestValidationError();
  }

  return value.type === "client"
    ? { type: "client", meeting_id: meetingId }
    : { type: "agent", meeting_id: meetingId };
}

function makeContext(
  meetingId: string,
  mediaPlacement: MediaPlacement,
  mediaRegion: string | undefined,
  createdAt: number,
): MeetingContext {
  return {
    meetingId,
    mediaPlacement: toCacheableMediaPlacement(mediaPlacement),
    ...(mediaRegion === undefined ? {} : { mediaRegion }),
    createdAt,
    expiresAt: createdAt + CONTEXT_RETENTION_SECONDS,
  };
}

function readOptionalNonEmptyString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value
    : undefined;
}

function safeUpstreamStatus(status: number): number {
  return Number.isInteger(status) && status >= 400 && status <= 599
    ? status
    : 502;
}

function methodNotAllowed(allow: string): RequestResult {
  const response = jsonResponse(405, errorBody("METHOD_NOT_ALLOWED"));
  response.headers.set("Allow", allow);
  return { response, resultCategory: "method_not_allowed" };
}

function errorResult(
  status: number,
  code: string,
  resultCategory: string,
): RequestResult {
  return {
    response: jsonResponse(status, errorBody(code)),
    resultCategory,
  };
}

function errorBody(code: string): JsonObject {
  return { status: "error", error: { code } };
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: BASE_RESPONSE_HEADERS,
  });
}

const handler = createGatewayHandler();

export default {
  fetch(request: Request, env: GatewayEnv): Promise<Response> {
    return handler(request, env);
  },
};
