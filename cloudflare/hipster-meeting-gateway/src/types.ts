export const MAX_REQUEST_BODY_BYTES = 8 * 1024;
export const MAX_MEETING_ID_LENGTH = 128;
export const CONTEXT_RETENTION_SECONDS = 24 * 60 * 60;

export type JsonObject = Record<string, unknown>;

export interface AgentMeetingRequest {
  readonly type: "agent";
  readonly meeting_id?: string;
}

export interface ClientMeetingRequest {
  readonly type: "client";
  readonly meeting_id: string;
}

export type MeetingRequest = AgentMeetingRequest | ClientMeetingRequest;

export interface MediaPlacement extends JsonObject {
  readonly AudioHostUrl: string;
  readonly AudioFallbackUrl: string;
  readonly SignalingUrl: string;
  readonly TurnControlUrl: string;
}

export interface MeetingContext {
  readonly meetingId: string;
  readonly mediaPlacement: unknown;
  readonly mediaRegion?: string;
  readonly createdAt: number;
  readonly expiresAt: number;
}

export interface MeetingContextStore {
  get(meetingId: string): Promise<MeetingContext | null>;
  upsert(context: MeetingContext): Promise<void>;
  delete(meetingId: string): Promise<void>;
}

export interface HipsterUpstreamResponse {
  readonly status: number;
  readonly payload: unknown;
  readonly isJson: boolean;
  readonly contentTypeCategory?: "json" | "html" | "other" | "absent";
  readonly sgCaptchaPresent?: boolean;
  readonly locationPresent?: boolean;
}

export interface HipsterRelayConfig {
  readonly url: string;
  readonly sharedSecret: string;
}

export interface HipsterClient {
  postMeeting(
    request: MeetingRequest,
    apiKey: string,
    relay?: HipsterRelayConfig,
  ): Promise<HipsterUpstreamResponse>;
}

export interface GatewayLogEntry {
  readonly event: "meeting_gateway_request";
  readonly requestId: string;
  readonly route: string;
  readonly method: string;
  readonly upstreamStatus?: number;
  readonly upstreamContentTypeCategory?: "json" | "html" | "other" | "absent";
  readonly upstreamSgCaptchaPresent?: boolean;
  readonly upstreamLocationPresent?: boolean;
  readonly resultCategory: string;
  readonly durationMs: number;
  readonly contextCacheHit?: boolean;
}

export interface GatewayLogger {
  log(entry: GatewayLogEntry): void;
}

export type GatewayEnv = Partial<Pick<Env, "DB" | "HIPSTER_API_KEY">> & {
  readonly HIPSTER_RELAY_URL?: string;
  readonly RELAY_SHARED_SECRET?: string;
};

export function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function readNonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

export function asMediaPlacement(value: unknown): MediaPlacement | null {
  if (!isJsonObject(value)) {
    return null;
  }

  const requiredFields = [
    "AudioHostUrl",
    "AudioFallbackUrl",
    "SignalingUrl",
    "TurnControlUrl",
  ] as const;

  for (const field of requiredFields) {
    if (readNonEmptyString(value[field]) === null) {
      return null;
    }
  }

  return value as MediaPlacement;
}

export function toCacheableMediaPlacement(
  value: MediaPlacement,
): MediaPlacement {
  const eventIngestionUrl = readNonEmptyString(value.EventIngestionUrl);
  return {
    AudioHostUrl: value.AudioHostUrl,
    AudioFallbackUrl: value.AudioFallbackUrl,
    SignalingUrl: value.SignalingUrl,
    TurnControlUrl: value.TurnControlUrl,
    ...(eventIngestionUrl === null
      ? {}
      : { EventIngestionUrl: eventIngestionUrl }),
  };
}
