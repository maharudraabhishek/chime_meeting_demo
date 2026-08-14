import type {
  HipsterClient,
  HipsterRelayConfig,
  HipsterUpstreamResponse,
  MeetingRequest,
} from "./types";

const HIPSTER_MEETINGS_URL =
  "https://assess.hipster-dev.com/api/meetings";

/// Leaves budget inside Flutter's 15-second outer request deadline for the
/// Worker to serialize and return a typed 504 response.
export const HIPSTER_UPSTREAM_TIMEOUT_MS = 12_000;

export class UpstreamTimeoutError extends Error {
  constructor() {
    super("The upstream request timed out.");
    this.name = "UpstreamTimeoutError";
  }
}

export class UpstreamNetworkError extends Error {
  constructor(readonly resultCategory: UpstreamNetworkResultCategory) {
    super("The upstream request failed.");
    this.name = "UpstreamNetworkError";
  }
}

export type UpstreamNetworkResultCategory =
  | "upstream_invalid_header"
  | "upstream_incorrect_receiver"
  | "upstream_request_context_error"
  | "upstream_dns_error"
  | "upstream_tls_error"
  | "upstream_connection_refused"
  | "upstream_connection_lost"
  | "upstream_network_error";

function classifyNetworkError(error: unknown): UpstreamNetworkResultCategory {
  if (!(error instanceof Error)) return "upstream_network_error";
  const message = error.message.toLowerCase();
  if (
    message.includes("header") ||
    message.includes("bytestring") ||
    message.includes("invalid character")
  ) {
    return "upstream_invalid_header";
  }
  if (message.includes("illegal invocation")) {
    return "upstream_incorrect_receiver";
  }
  if (message.includes("request context")) {
    return "upstream_request_context_error";
  }
  if (message.includes("dns") || message.includes("resolve")) {
    return "upstream_dns_error";
  }
  if (
    message.includes("tls") ||
    message.includes("ssl") ||
    message.includes("certificate")
  ) {
    return "upstream_tls_error";
  }
  if (message.includes("connection refused")) {
    return "upstream_connection_refused";
  }
  if (message.includes("network connection lost")) {
    return "upstream_connection_lost";
  }
  return "upstream_network_error";
}

export class HttpHipsterClient implements HipsterClient {
  constructor(
    // Do not store the Workers global `fetch` function directly and later call
    // it as an HttpHipsterClient method. Web-platform functions require the
    // correct receiver in workerd and otherwise fail immediately before I/O.
    private readonly fetchImplementation: typeof fetch = (input, init) =>
      globalThis.fetch(input, init),
    private readonly timeoutMs: number = HIPSTER_UPSTREAM_TIMEOUT_MS,
  ) {}

  async postMeeting(
    request: MeetingRequest,
    apiKey: string,
    relay?: HipsterRelayConfig,
  ): Promise<HipsterUpstreamResponse> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const headers = new Headers({
        Accept: "application/json",
        "Content-Type": "application/json",
      });
      if (relay === undefined) {
        headers.set("x-api-key", apiKey);
      } else {
        headers.set("Authorization", `Bearer ${relay.sharedSecret}`);
        headers.set("x-relay-hipster-key", apiKey);
      }
      const response = await this.fetchImplementation(
        relay?.url ?? HIPSTER_MEETINGS_URL,
        {
        method: "POST",
        headers,
        body: JSON.stringify(request),
        signal: controller.signal,
        },
      );

      // Record only categorical response metadata. Header values and response
      // bodies may contain sensitive upstream details and are never logged.
      const contentType = response.headers.get("content-type")?.toLowerCase();
      const diagnostics = {
        contentTypeCategory:
          contentType === undefined
            ? ("absent" as const)
            : contentType.includes("json")
              ? ("json" as const)
              : contentType.includes("html")
                ? ("html" as const)
                : ("other" as const),
        sgCaptchaPresent: response.headers.has("sg-captcha"),
        locationPresent: response.headers.has("location"),
      };

      const text = await response.text();
      if (text.length === 0) {
        return {
          status: response.status,
          payload: null,
          isJson: false,
          ...diagnostics,
        };
      }

      try {
        return {
          status: response.status,
          payload: JSON.parse(text) as unknown,
          isJson: true,
          ...diagnostics,
        };
      } catch (error: unknown) {
        if (error instanceof SyntaxError) {
          return {
            status: response.status,
            payload: null,
            isJson: false,
            ...diagnostics,
          };
        }
        throw error;
      }
    } catch (error: unknown) {
      if (controller.signal.aborted) {
        throw new UpstreamTimeoutError();
      }
      if (error instanceof UpstreamTimeoutError) {
        throw error;
      }
      throw new UpstreamNetworkError(classifyNetworkError(error));
    } finally {
      clearTimeout(timeout);
    }
  }
}
