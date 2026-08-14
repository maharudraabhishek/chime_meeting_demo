# Amazon Chime integration for Flutter Web

This document describes the Chrome media adapter that extends the existing
Flutter application. It does not introduce a separate lobby, state machine, API
client, or meeting lifecycle.

## 1. Architecture

```text
Flutter meeting UI
  -> MeetingBloc
  -> CreateMeeting / JoinMeeting
  -> MeetingRepository -> Cloudflare Worker /meetings
  -> MeetingMediaGateway
       -> conditional WebMeetingMediaGateway
       -> typed Dart JS interop
       -> globalThis.chimeWebBridge
       -> amazon-chime-sdk-js 3.32.0
       -> browser WebRTC
```

The control plane and media plane remain separate. Flutter obtains the meeting
bootstrap through the Worker. The TypeScript bridge receives only that bootstrap
and media commands; it never performs Create or Join HTTP requests.

The deployed Worker can retain D1 recovery while forwarding its fixed upstream
request through the existing locked-down relay. That is a server-side routing
detail: the browser still calls only the Worker. The relay host and tunnel must
remain available and do not provide a production uptime guarantee.

Android continues to select its native Chime gateway, Method/Event Channels,
and PlatformViews. Presentation, BLoC, domain entities, and use cases are shared.
iOS media is not selected by this integration.

## 2. Dart and JavaScript boundary

Browser-only Dart files are isolated with conditional imports/exports based on
`dart.library.js_interop`. They use `dart:js_interop` for the bridge and
`package:web` for DOM elements. Common and native Dart files do not import
browser libraries.

The locally bundled script registers one application global:

```text
globalThis.chimeWebBridge
```

Its public operations cover support detection, event-handler registration,
session start/stop, mute/unmute, camera on/off, camera switching, video-element
attachment, and disposal. Internal Chime SDK classes are not exposed globally.

Each start request carries a monotonically increasing generation plus minimal
meeting and attendee DTOs. Every event returning to Dart contains only a type,
generation, and minimal safe fields. Events never contain tokens, placement
URLs, bootstrap objects, DOM objects, `MediaStream`, or exception objects. Dart
validates and filters the event before it reaches the domain stream.

## 3. Build the TypeScript bundle

The bridge is an isolated pnpm package under `web/chime_bridge`. It pins
`amazon-chime-sdk-js` 3.32.0 and uses TypeScript plus esbuild. `web/index.html`
loads its IIFE before Flutter bootstrap. The output is self-contained and does
not load Chime from a CDN or resolve `node_modules` in the browser.

```powershell
Set-Location web/chime_bridge
pnpm install --frozen-lockfile
pnpm run typecheck
pnpm test
pnpm run build
Set-Location ../..
```

The expected asset is:

```text
web/chime_bridge/dist/chime_web_bridge.js
```

The deterministic bundle is kept with the source so a clone can load the
script required by `web/index.html` before pnpm setup. `node_modules` and test
build output remain ignored. Re-run typecheck, tests, and build whenever
TypeScript source or dependency metadata changes. If the asset is absent or
fails to load, startup reports a typed bridge/runtime failure; it never falls
back to a CDN.

## 4. Session startup order

1. The existing Create or Join use case posts to the configured Worker.
2. Flutter validates and maps the response into `MeetingBootstrap`.
3. The Web gateway confirms that the bridge, media devices, WebRTC, and secure
   context requirements are available.
4. Required meeting fields are validated: MeetingId plus AudioHostUrl,
   AudioFallbackUrl, SignalingUrl, and TurnControlUrl. Required attendee fields
   are AttendeeId, ExternalUserId, and JoinToken. EventIngestionUrl is optional.
5. Any prior browser session is cleaned up, then the new generation becomes
   active.
6. The bridge constructs `MeetingSessionConfiguration`, logger, device
   controller, and `DefaultMeetingSession` without logging the bootstrap.
7. Audio/video, attendee presence, local mute, fatal realtime, active-speaker,
   volume, and device-change observers are registered before `audioVideo.start`.
8. The bridge creates and binds one hidden audio element.
9. Microphone and camera inputs are selected independently.
10. The bridge calls `audioVideo.start()`.
11. Only `audioVideoDidStart` emits the shared `sessionStarted` event. BLoC then
    moves the meeting to connected.
12. If camera input is ready, the local video tile starts after that callback.

Command acceptance is not proof of connectivity. The existing startup timeout
continues to bound a session that never emits its start callback.

## 5. Video tile binding

The meeting room retains its remote main surface and local thumbnail. The web
implementation supplies one stable, unique HTML video element for each role.
Each element fills its Flutter bounds, uses the role's object-fit policy,
autoplays, plays inline, has no controls, and is muted at the HTML layer because
meeting audio has a separate owner.

Widgets create and dispose render surfaces but never call JavaScript. They tell
the media gateway when an element is attached or detached. The bridge owns tile
selection and `bindVideoElement`/`unbindVideoElement` calls.

The bridge caches both tile state and element identity so these races are safe:

```text
tile first -> remember tile -> element arrives -> bind
element first -> remember element -> tile arrives -> bind
```

The local tile is identified by `localTile`. The 1:1 remote tile must be
non-local, non-content, and have a bound attendee. Content-share modality is
ignored. Removal clears only the matching tile id, so a delayed callback cannot
remove a newer replacement tile after remote video restarts or a participant
rejoins.

## 6. Audio binding and autoplay

The TypeScript session owns one hidden `HTMLAudioElement`. It appends the
element to the document, enables autoplay, disables controls, and binds it with
Chime's audio-element API. Meeting audio is not routed through either video
element.

The bridge attempts playback safely. If Chrome blocks autoplay, the meeting can
remain connected and the condition is classified as user-action-required where
the shared failure/event model can represent it. A click or tap in the meeting
UI may satisfy browser policy. Teardown unbinds, pauses, and removes the audio
element.

## 7. Browser permissions and devices

Browser permission is requested by Chime device operations, not by Android
permission APIs and not by one all-or-nothing audio/video request.

- Microphone: list inputs, select a suitable device, and start it. Permission
  denial is typed and the session remains eligible for listen-only connection
  using the SDK-supported null input path where available.
- Camera: list inputs, select a suitable device, and start it. Denial or absence
  is typed and the meeting continues audio-only.
- Camera off: stop the local tile, then stop video input.
- Camera on: resolve/start the selected input and start the local tile only when
  the session has started.
- Switch camera: re-enumerate devices, choose the next device circularly, and
  call `startVideoInput` with that device id. Fewer than two devices returns
  `false` without failing the meeting.

Common browser device errors are reduced to safe categories: permission denied,
not found, busy/not readable, constraint failure, or media operation failure.
No fake browser-settings link is offered. Retry remains possible when browser
policy permits it.

## 8. Reconnect mapping

Chime JS owns WebRTC transport recovery. JavaScript does not add an application
reconnect timer.

- The first `audioVideoDidStartConnecting(true)` in an episode emits
  `reconnecting`.
- Duplicate callbacks in the same episode do not emit another reconnect start.
- `audioVideoDidStart` during that episode emits `connectionRecovered`, then
  clears the episode marker.
- Initial `audioVideoDidStart` emits `sessionStarted`, never recovered.
- Unexpected stop or fatal realtime error maps to a safe typed failure.

BLoC remains the timeout authority through its existing 25-second bounded
watchdog. Generation checks prevent an old session from recovering or failing a
replacement session.

## 9. Events and attendee state

Presence callbacks ignore `#content` attendees. A present attendee emits join
once and receives one retained volume-indicator subscription. Departure emits
leave, removes that subscription, and clears cached remote mute/volume state;
it does not end the local meeting.

Volume callbacks treat null fields as unchanged. Remote mute/unmute emits only
on a real state transition. Volume is coalesced to a bounded cadence instead of
flooding Dart. Local mute truth comes from Chime realtime mute callbacks. The
active-speaker subscription uses `DefaultActiveSpeakerPolicy` and maps the first
attendee, when present, into the shared active-speaker event.

Network-poor and network-good callbacks update shared network state without
duplicating reconnect recovery. Device-change events, video availability, and
fatal failures use the same domain event model as Android.

## 10. Cleanup ownership

Session replacement, leave, and disposal use one idempotent cleanup path. The
active generation is invalidated before asynchronous teardown begins. Cleanup
removes active-speaker, presence, per-attendee volume, local-mute, fatal,
audio/video, and device-change observers with the exact callback references
used during subscription. It then:

1. unbinds local and remote video;
2. stops and removes the local video tile;
3. stops video and audio inputs;
4. unbinds the hidden audio element;
5. stops audio-video;
6. releases owned device/session resources when supported;
7. pauses and removes the hidden audio element;
8. clears element, tile, attendee, volume, active-speaker, reconnect, bootstrap,
   and credential-bearing references.

Each operation is best effort so one failure does not prevent later cleanup.
Running cleanup twice is safe. No event is emitted after disposal.

## 11. Run and debug Chrome

First verify that the public gateway is reachable:

```powershell
Invoke-WebRequest `
  -Uri https://<worker>.workers.dev/health `
  -Method Get
```

Then run Flutter with the public gateway URL:

```powershell
flutter run -d chrome `
  --dart-define=MEETING_API_BASE_URL=https://<worker>.workers.dev/
```

Use Chrome DevTools to check:

- the local bridge asset loaded before Flutter bootstrap;
- there are no uncaught exceptions or unhandled promise rejections;
- the page is a secure context and media devices/WebRTC are available;
- permission and autoplay outcomes are understood;
- Flutter HTTP traffic targets only the Cloudflare gateway;
- browser requests never target Hipster and never contain `x-api-key`;
- Chime signaling/media traffic is present after successful bootstrap;
- consoles contain no JoinToken, attendee credentials, bootstrap payload,
  placement URL, or raw media error.

If `/health` succeeds but `/meetings` cannot obtain valid upstream JSON, keep
the browser pointed at Cloudflare. Do not add the upstream key to Flutter or the
bridge and do not bypass the Worker. Unit/static validation can continue, but a
live Create/Join result remains blocked by the control plane.

## 12. Two-Chrome workflow

Use normal Chrome for User A and Incognito, Guest, or a second profile for User
B. Two tabs in one profile can share browser permission/device policy, so
separate contexts provide a clearer 1:1 check.

1. User A creates a meeting through the existing lobby.
2. Copy the exact MeetingId shown by the application.
3. User B pastes that exact id and joins.
4. Confirm both reach connected only after their Chime start callbacks.
5. Confirm each context received a fresh attendee from the Worker; never compare
   or print the token values.
6. Grant microphone/camera as desired and verify local thumbnail, remote main
   video, and two-way audio.
7. Exercise mute/unmute, camera off/on, and camera switch when at least two
   devices are available.
8. Leave and rejoin User B, then confirm a replacement remote tile binds.
9. Exercise a brief network interruption and confirm one reconnect episode and
   recovery, or the bounded BLoC timeout.
10. Review the safe event log and DevTools checks above.

Record unsupported hardware or browser policy as a limitation. Do not report
two-way audio/video, permissions, reconnect, or camera switching as successful
unless they were exercised in the browser.

## 13. Security verification

| Check | Required result |
| --- | --- |
| Hipster API key in Dart, TypeScript, HTML, source maps, or browser storage | No |
| Browser request with `x-api-key` | No |
| Direct browser request to Hipster | No |
| JoinToken or raw bootstrap in console/event log | No |
| Attendee credentials in localStorage or sessionStorage | No |
| Worker owns the upstream credential | Yes |
| Each Join obtains a fresh attendee bootstrap | Yes |

The bridge keeps the active bootstrap only in session memory and clears its
references during replacement, leave, or disposal. Safe errors expose a
category rather than raw browser, Chime, or upstream payloads.

## 14. Release build notes

Build and test the pinned bridge before Flutter Web:

```powershell
Set-Location web/chime_bridge
pnpm install --frozen-lockfile
pnpm run typecheck
pnpm test
pnpm run build
Set-Location ../..

dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release `
  --dart-define=MEETING_API_BASE_URL=https://<worker>.workers.dev/
```

Deploy `build/web` behind HTTPS and verify the bridge asset is included. Treat
`MEETING_API_BASE_URL` as public configuration only. Never pass the Hipster key,
`x-api-key`, JoinToken, attendee bootstrap, or any other client secret through a
Dart define, HTML, TypeScript source, source map, browser storage, or deployment
configuration visible to the browser.

Before release, search the browser bundle and console behavior for accidental
credential logging, confirm direct Hipster requests are absent, and repeat the
two-context workflow against the release deployment.

The supported Web scope is current Chrome in a secure context for 1:1
audio/video. Screen sharing is intentionally absent. Audio autoplay remains
subject to browser gesture policy, and camera switching is available only when
Chrome exposes at least two usable video devices.
