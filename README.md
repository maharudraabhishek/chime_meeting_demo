# Chime Meeting

Chime Meeting is a Flutter application for secure 1:1 Amazon Chime meetings on
Android and Chrome. Both platforms use the same lobby, BLoC, domain use cases,
Cloudflare gateway, meeting room, controls, diagnostics, and bounded reconnect
watchdog. Platform adapters own only their Amazon Chime media integration.

## Architecture

```text
Flutter UI
  -> MeetingBloc
  -> CreateMeeting / JoinMeeting
  -> Cloudflare Worker /meetings -> D1 placement recovery -> Hipster API
  -> MeetingMediaGateway
       -> Android: Chime Android SDK 0.25.4 + PlatformViews
       -> Chrome: Dart JS interop -> local TypeScript bridge
                  -> amazon-chime-sdk-js 3.32.0 + WebRTC
```

The project uses feature-first Clean Architecture, constructor injection, BLoC
as the meeting lifecycle authority, and GetIt only in the composition root.
Widgets never call REST, platform channels, browser JavaScript, or either Chime
SDK directly. A session is connected only after the selected Chime SDK reports
that media startup completed.

Flutter sends only the existing JSON contract to the public Worker:

```text
Create: POST /meetings {"type":"agent"}
Join:   POST /meetings {"type":"client","meeting_id":"<exact id>"}
```

The Worker owns the upstream credential and D1 placement recovery. The browser
never calls the upstream Hipster endpoint and never sends `x-api-key`.

The currently deployed gateway can route its fixed Hipster request through a
locked-down local relay when the upstream host challenges direct Worker egress.
That relay keeps browser/mobile traffic and credentials behind the Worker, but
its computer, network, and tunnel must remain available and it has no production
uptime guarantee.

A Render Free relay Blueprint is prepared in `render.yaml` as a hosted
compatibility experiment. It still requires an egress probe because managed
cloud egress may receive the same upstream anti-bot challenge.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for shared ownership and
[docs/WEB_CHIME_INTEGRATION.md](docs/WEB_CHIME_INTEGRATION.md) for the complete
Chrome media lifecycle.

## Prerequisites

- Flutter/Dart compatible with Dart `^3.11.1`
- Chrome with WebRTC and `navigator.mediaDevices`
- Node.js compatible with pnpm 10
- pnpm 10.15.1 for the browser bridge
- Android SDK and JDK 17 for Android builds
- ARMv7 or ARM64 Android hardware for Android Chime media
- The public Cloudflare Worker URL

Run Flutter dependency resolution only when the checked-in lockfile must be
materialized locally:

```powershell
flutter pub get
```

## Build the local browser bridge

The browser loads a self-contained IIFE bundle from
`web/chime_bridge/dist/chime_web_bridge.js`. It is built from the pinned local
package and kept with the source because `web/index.html` requires it at
startup. No public CDN or runtime `node_modules` lookup is used.

```powershell
Set-Location web/chime_bridge
pnpm install --frozen-lockfile
pnpm run typecheck
pnpm test
pnpm run build
Set-Location ../..
```

Rebuild the bridge whenever its TypeScript source or lockfile changes. A
missing bundle is an actionable bridge-unavailable error, not a fallback to a
remote script.

## Run Chrome

`MEETING_API_BASE_URL` is public configuration and must be the Cloudflare
gateway base URL, including its trailing slash.

```powershell
flutter run -d chrome `
  --dart-define=MEETING_API_BASE_URL=https://<worker>.workers.dev/
```

The deployed web app must use HTTPS. Loopback development is the browser's
secure-context exception. The browser requests microphone and camera access
through Chime device selection: microphone denial can continue listen-only,
and camera denial can continue audio-only. Audio autoplay policy may require a
user gesture before remote audio can play.

To test two participants, create in normal Chrome, copy the exact MeetingId,
then join it from an Incognito window, Guest profile, or second Chrome profile.
Each window obtains fresh attendee credentials from the Worker.

## Android builds

```powershell
flutter build apk --debug `
  --dart-define=MEETING_API_BASE_URL=https://<worker>.workers.dev/

flutter build appbundle --release `
  --dart-define=MEETING_API_BASE_URL=https://<worker>.workers.dev/
```

The Android adapter, application ID `com.example.chimemeeting`, and Amazon
Chime Android SDK `0.25.4` remain unchanged. A distributable release requires a
local ignored `android/key.properties` and keystore; see
[docs/ANDROID_RELEASE.md](docs/ANDROID_RELEASE.md).

## Web release build

Build the TypeScript bundle first, then build Flutter Web with the public
gateway URL:

```powershell
Set-Location web/chime_bridge
pnpm install --frozen-lockfile
pnpm run typecheck
pnpm test
pnpm run build
Set-Location ../..

flutter build web --release `
  --dart-define=MEETING_API_BASE_URL=https://<worker>.workers.dev/
```

Deploy the contents of `build/web` behind HTTPS. Confirm that
`chime_bridge/dist/chime_web_bridge.js` is present in the deployed assets and
served with a JavaScript content type.

## Reliability and security

- Chime owns transport reconnection. BLoC owns one 25-second timeout per
  reconnect episode and terminates only the matching session if it stalls.
- Native generations and browser session generations prevent callbacks from a
  replaced session from updating the current meeting.
- Leave, failure, replacement, and disposal use idempotent media cleanup.
- Browser audio uses one hidden audio element; meeting video elements are muted
  so they never duplicate audio.
- Browser meeting and attendee credentials remain in memory for the active
  session and are never stored in localStorage or sessionStorage.
- Logs exclude credentials, raw bootstrap responses, attendee identifiers,
  MediaPlacement URLs, and raw exceptions.
- D1 stores only meeting context needed for placement recovery and never stores
  attendee credentials.
- Android x86/x86_64 media startup remains a typed unsupported-runtime failure
  because the pinned native media libraries target ARM devices.

## Validation

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web `
  --dart-define=MEETING_API_BASE_URL=https://<worker>.workers.dev/
```

Static checks do not prove browser permissions, autoplay, real camera or
microphone behavior, remote rendering, two-way media, reconnect behavior, or
Android device behavior. Complete the manual workflow in
[docs/WEB_CHIME_INTEGRATION.md](docs/WEB_CHIME_INTEGRATION.md) before making
runtime claims.

Current Web scope is Chrome 1:1 audio/video. Screen sharing and iOS Chime media
are not part of this integration. Camera switching depends on the browser
exposing at least two usable video devices.

## Documentation

- [Architecture and lifecycle](docs/ARCHITECTURE.md)
- [Chrome Amazon Chime integration](docs/WEB_CHIME_INTEGRATION.md)
- [Android native troubleshooting](docs/ANDROID_TROUBLESHOOTING.md)
- [Android signing and release readiness](docs/ANDROID_RELEASE.md)
- [Cloudflare gateway operations](docs/CLOUDFLARE_GATEWAY.md)
- [Meeting gateway data flow](docs/GATEWAY_DATA_FLOW.md)
- [Submission checklist](docs/SUBMISSION_CHECKLIST.md)
- [Demo script](docs/DEMO_SCRIPT.md)
