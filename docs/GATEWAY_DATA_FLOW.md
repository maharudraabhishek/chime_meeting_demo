# Meeting Gateway Data Flow

This page explains the currently working assessment/demo route in plain
language. For deployment commands and troubleshooting, see
[CLOUDFLARE_GATEWAY.md](CLOUDFLARE_GATEWAY.md).

## Working architecture

```mermaid
flowchart LR
    User["User"]
    App["Flutter app<br/>public Worker URL only"]
    Worker["Cloudflare Worker<br/>validation + safe errors"]
    Secrets["Worker secrets<br/>Hipster key + relay configuration"]
    D1[("Cloudflare D1<br/>meeting context only")]
    Tunnel["Public Cloudflare Quick Tunnel<br/>HTTPS transport"]
    Relay["Local Node relay<br/>authenticates each proxy request"]
    Hipster["Hipster API<br/>POST /api/meetings"]

    User --> App
    App -->|"HTTPS POST /meetings<br/>JSON; no API key"| Worker
    Secrets -.->|"server-side bindings"| Worker
    Worker <-->|"meeting ID + placement + optional region<br/>timestamps; no attendee credentials"| D1
    Worker -->|"HTTPS + relay bearer credential<br/>validated JSON"| Tunnel
    Tunnel --> Relay
    Relay -->|"HTTPS JSON<br/>server-side x-api-key"| Hipster
    Hipster --> Relay --> Worker --> App
```

Only `MEETING_API_BASE_URL` is compiled into Flutter. It is a public endpoint,
not a secret. The Hipster key is stored as a Cloudflare Worker secret, is sent
transiently across the authenticated relay request, and is never stored by the
relay or D1.

The local relay is not a general-purpose proxy. Its only proxy route is
`POST /meetings`; `GET /health` is a local health check. It accepts only the
supported agent/client JSON bodies, applies size and timeout limits, and
forwards to one fixed Hipster HTTPS URL.

## Create data flow

```mermaid
flowchart TD
    A["Flutter<br/>POST /meetings<br/>{type: agent}"]
    B["Worker<br/>validate request"]
    C["Authenticated relay<br/>preserve exact JSON"]
    D["Hipster<br/>create meeting + creator attendee"]
    E{"Valid success envelope,<br/>MeetingId, and MediaPlacement?"}
    F["D1 upsert<br/>placement + optional region<br/>24-hour expiry"]
    G["Flutter receives<br/>original success envelope"]
    H["Sanitized gateway error<br/>no raw response or token"]

    A --> B --> C --> D --> E
    E -->|"Yes"| F --> G
    E -->|"No"| H
```

The Worker waits for the D1 write before returning Create success. D1 never
stores the creator attendee, `AttendeeId`, `ExternalUserId`, or `JoinToken`.

## Join and MediaPlacement recovery

```mermaid
flowchart TD
    A["Flutter<br/>POST /meetings<br/>{type: client, meeting_id: exact ID}"]
    B["Relay calls Hipster<br/>with the same JSON"]
    C["Hipster returns<br/>fresh User B attendee"]
    D{"Response MeetingId<br/>matches request?"}
    E{"Current response has valid<br/>MediaPlacement?"}
    F["Use upstream placement<br/>and refresh D1 context"]
    G["Load exact matching,<br/>non-expired D1 context"]
    H{"Valid matching<br/>context exists?"}
    I["Merge placement only<br/>preserve current attendee"]
    J["Return unchanged response<br/>Flutter typed missing-media boundary"]
    K["Sanitized invalid-response error"]
    L["Return current or enriched<br/>response to Flutter"]

    A --> B --> C --> D
    D -->|"No"| K
    D -->|"Yes"| E
    E -->|"Yes"| F --> L
    E -->|"No"| G --> H
    H -->|"Yes"| I --> L
    H -->|"No"| J
```

User B always receives credentials from the current Hipster Join response. The
Worker can merge only the matching cached placement and optional region; it
never reuses User A's attendee, chooses another meeting's context, or invents
Chime URLs.

## Why the Worker-only route failed

```mermaid
flowchart LR
    subgraph Before["Before the gateway"]
        A1["Device or local curl"] -->|"residential/mobile egress"| A2["Hipster"]
        A2 -->|"HTTP 200 JSON"| A1
    end

    subgraph Failed["Worker-only route"]
        B1["Cloudflare Worker"] -->|"shared cloud egress"| B2["SiteGround protection"]
        B2 -->|"HTTP 202 HTML<br/>sg-captcha"| B1
    end

    subgraph Current["Current compatibility route"]
        C1["Cloudflare Worker"] --> C2["Authenticated local relay"]
        C2 -->|"residential egress"| C3["Hipster"]
        C3 -->|"HTTP 200 JSON"| C2
    end
```

The earlier Worker sent the correct HTTPS URL, HTTP method, JSON body, and
server-owned key. The failure was the upstream hosting layer classifying shared
Cloudflare egress as automated traffic and returning an HTML challenge instead
of the Hipster JSON contract. The response contained no usable meeting or
attendee data, so accepting HTTP `202` as success could never work.

Changing D1, Flutter parsing, the timeout, or the API key could not convert the
challenge page into meeting data. The working relay preserves the request
contract and changes only the network egress seen by Hipster.

## How the working route was tested

```mermaid
flowchart LR
    Smoke["Sanitized smoke runner"]
    Worker["Public Worker /meetings"]
    Relay["Tunnel + local relay"]
    Hipster["Hipster"]
    D1[("D1 context")]
    Checks["Boolean checks only<br/>no IDs, keys, tokens, or bodies printed"]

    Smoke -->|"Create exact Flutter JSON"| Worker
    Worker --> Relay --> Hipster
    Hipster --> Relay --> Worker
    Worker --> D1
    Worker --> Checks
    Smoke -->|"Join with exact in-memory MeetingId"| Worker
    Worker --> Checks
```

The live smoke exercised the same public Worker endpoint and JSON bodies used
by Flutter. It verified HTTP and envelope success, required placement fields,
the exact Join meeting match, attendee credential structure, and that User B's
attendee was fresh. Identifiers and credentials remained in memory and were not
printed. An aggregate-only D1 query confirmed context persistence without
reading placement JSON.

This test proves the HTTP gateway, relay, D1 recovery, and attendee isolation.
It did not tap the Flutter UI or verify Android permissions, Chime session
startup, audio/video, reconnect behavior, or native video views.

## Operational boundary

The current Quick Tunnel is a free assessment/demo compatibility path. The
relay computer, Node process, tunnel process, residential internet connection,
and current Worker relay configuration must all remain available. Quick Tunnel
does not provide a production uptime SLA. A production service should use a
stable backend egress accepted by Hipster or a Hipster-provided backend-safe
endpoint while keeping the same Worker, D1, and mobile security boundaries.
