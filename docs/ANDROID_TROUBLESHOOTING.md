# Android native troubleshooting

Use these checks for source/build diagnosis. They do not replace physical-device
verification, and logs must never include meeting response bodies, join tokens,
attendee identifiers, API keys, or placement URLs.

## Unsupported runtime

Amazon Chime SDK `0.25.4` packages ARMv7 and ARM64 native media libraries. An
x86/x86_64 runtime is intentionally rejected with the typed
`unsupportedRuntime` failure before native media construction. Use supported ARM
hardware for real media validation.

## Camera or microphone permission

The app requests both Android runtime permissions through
`MeetingPermissionBridge` before meeting bootstrap.

- A normal denial shows a retry action.
- A permanent denial exposes **Open settings**.
- After granting permissions in settings, return to the app and retry create or
  join; the app does not retain failed credentials or auto-create a meeting.
- Confirm `CAMERA` and `RECORD_AUDIO` remain declared in the main manifest.

## Blank local or remote video

1. Confirm the meeting reached `Connected`; REST success alone is insufficient.
2. Open the event log and look for local/remote video available, removed,
   paused, or resumed events.
3. Confirm camera state is on before using switch-camera.
4. A late remote participant is valid; no application timeout waits for them.
5. If a participant leaves and rejoins, a new remote tile should replace the old
   tile without terminating the local session.

## Reconnect does not recover

The SDK performs reconnect attempts. The app displays `Reconnecting` and allows
one 25-second episode. Recovery returns to `Connected`; timeout produces the
typed reconnect failure and performs best-effort native cleanup. Do not add REST
meeting recreation or repeated Chime start calls to this path.

## Background and foreground

Backgrounding does not leave the meeting. If camera was enabled, the app asks
Chime to stop it and restores it once after resume only if the same session is
still active. A camera that the user disabled is not restarted.

## Safe build diagnostics

```powershell
flutter analyze
flutter build apk --debug `
  --dart-define=MEETING_API_BASE_URL=https://<worker>.workers.dev/
```

For native compilation without installing or launching an app:

```powershell
cd android
.\gradlew.bat :app:compileDebugKotlin
```

If a command fails, record the task name and exception class only. Sanitize any
tool output before sharing it.

`CXX5304` indicates that Android Studio and Android command-line tools understand
different SDK XML schema versions. It can be non-fatal, but align the installed
SDK tools before a signed release instead of changing application code or the
pinned Chime SDK.
