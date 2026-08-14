# Architecture and lifecycle

## Ownership boundaries

| Area | Authority | Responsibility |
| --- | --- | --- |
| UI | Flutter widgets | Render immutable state and emit user intents |
| Orchestration | `MeetingBloc` | Bootstrap, lifecycle, watchdogs, terminal state, diagnostics |
| Domain | Entities, use cases, gateway contracts | Typed results and SDK-independent rules |
| Data | Repository and HTTP data source | Worker requests, DTO validation, and failure mapping |
| Android media | Android `MeetingMediaGateway` adapter and native controller | One Android Chime session, observers, controls, cleanup, and PlatformViews |
| Web media | `WebMeetingMediaGateway` and local TypeScript bridge | One browser Chime session, WebRTC devices, observers, DOM media binding, and cleanup |
| Backend | Cloudflare Worker and D1 | Server credential, Hipster forwarding, response validation, and placement recovery |

GetIt is confined to the application composition root. All other layers receive
dependencies through constructors. Conditional platform factories select the
media and permission adapters without making BLoC or the domain platform-aware.
Widgets never call REST, platform channels, browser JavaScript, or Chime
directly.

## Control plane and media plane

```text
Control plane
Flutter use case -> POST Worker /meetings -> Hipster meeting API
                                    \-> D1 MediaPlacement recovery

Media plane
MeetingBloc -> MeetingMediaGateway
                 |-> Android Chime SDK -> native audio/video + PlatformViews
                 \-> Web bridge -> Chime JS SDK -> WebRTC + DOM media elements
```

The web bridge never creates or joins meetings over HTTP. Flutter Web uses the
same repository and request bodies as Android. The upstream key remains on the
server, and the Worker returns a new attendee identity for each Join request.

## Meeting bootstrap

```text
create/join intent
  -> connectivity preflight
  -> platform permission boundary
  -> Worker POST /meetings
  -> validated MeetingBootstrap
  -> selected MeetingMediaGateway.start
  -> Chime session-start callback
  -> connected
```

REST success or start-command acceptance does not establish `connected`. The
SDK callback does. Required meeting placement and attendee fields are validated
before session construction; missing values become typed failures and are never
invented.

On Android, the permission gateway asks the operating system before media
startup. On Web, the permission adapter allows startup to reach browser-owned
device selection, where microphone and camera outcomes are classified
independently. This permits listen-only or audio-only participation where the
browser and SDK allow it.

## Reconnect watchdog

Amazon Chime remains responsible for transport recovery. The application does
not create a meeting, issue another REST Join, or construct another session
while reconnecting.

```text
connected
  -> Chime reconnect callback
  -> reconnecting + one 25-second BLoC watchdog
       -> Chime recovery: connected, watchdog cancelled
       -> timeout: failed(reconnectTimeout), media cleanup, watchdog cancelled
```

Duplicate reconnect callbacks remain in one episode. Android native generation
values and Web bridge generation values are matched to the active Dart session
identity, so stale callbacks and timers cannot recover or fail a replacement
session.

## Lifecycle and media behavior

- Android backgrounding preserves the meeting and applies the existing
  lifecycle-aware camera policy.
- Hiding a browser tab does not leave, rebuild, or aggressively reconnect the
  meeting; Chime and browser media policy remain authoritative.
- Camera and microphone control state follows confirmed adapter events.
- Remote attendee departure changes presence, diagnostics, and video
  availability only; it never tears down the local session.
- Local and remote video surfaces remain platform-neutral in presentation.
  Android binds native PlatformViews; Web binds muted HTML video elements.
- The Web adapter resolves both tile-before-element and element-before-tile
  ordering and rejects removal callbacks for a superseded tile.
- Browser meeting audio is bound once to a hidden audio element, separate from
  the muted video elements.
- Permission failure is typed and retryable when the runtime permits it.
  Android may offer settings for permanent denial; Web does not fabricate a
  settings deep link.

## Events and diagnostics

Both platform adapters map into the shared `MeetingMediaEvent` stream:

- meeting and audio-session start/stop;
- reconnecting, recovered, and poor connection;
- participant join/leave;
- local and remote mute/unmute;
- local and remote video available/removed/paused/resumed;
- microphone and camera state;
- active speaker, bounded volume indications, and audio-device changes;
- typed terminal session errors.

The Web callback boundary validates event type and generation and ignores
malformed or stale events without throwing into Chime observers. The BLoC
retains at most 50 safe event-log entries. Diagnostics expose coarse connection,
network, reconnect, microphone, and camera state without credentials, SDK
objects, DOM nodes, streams, placement URLs, or exception payloads.

## Resource ownership

Each media adapter has one idempotent teardown path. The Web bridge retains the
exact observer and realtime callback references required for removal, then
unbinds video and audio elements, stops local tiles and device inputs, stops the
session, releases owned device/session objects where supported, removes its
hidden audio element, and clears credential-bearing references. One cleanup
failure does not skip later cleanup steps.

Flutter video widgets own only their render surfaces and notify the gateway
when a surface is attached or detached. The gateway owns Chime tile binding;
the TypeScript bridge owns Chime SDK objects and browser media resources.

## Backend and security

Flutter sends only Create/Join JSON to the public HTTPS Worker. The Worker owns
the Hipster credential, validates upstream responses, and may restore only
matching, non-expired `MediaPlacement` from D1. It never stores or reuses
attendee credentials.

Browser and Android builds contain no Hipster key. Browser requests never send
`x-api-key` and never call Hipster directly. Join tokens, attendee identifiers,
raw bootstrap responses, placement URLs, media streams, and raw exception
details are excluded from logs, diagnostics, browser storage, and durable UI
state.

Web support targets current Chrome in a secure context. Android support retains
the pinned Chime Android SDK and its ARM runtime boundary. The iOS media
implementation remains outside the current platform selection.
