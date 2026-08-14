# Submission checklist

## Required behavior

- [ ] User A creates a meeting.
- [ ] User B joins the exact same meeting ID.
- [ ] Local video renders.
- [ ] Remote video renders.
- [ ] Microphone can be disabled and enabled.
- [ ] Camera can be disabled and enabled.
- [ ] Leave works without a crash or orphaned session.
- [ ] `Idle`, `Joining`, `Connected`, and `Disconnected` are visible at the appropriate times.
- [ ] Event log shows meeting start/end, participant join/leave, microphone changes, and camera changes.

## Quality gates

- [ ] `flutter pub get` passes.
- [ ] `dart format --output=none --set-exit-if-changed lib test` passes.
- [ ] `flutter analyze` reports no issues.
- [ ] `flutter test` passes.
- [ ] Android debug APK builds with only the public Worker URL supplied through `--dart-define` when an override is needed.
- [ ] Signed Android release AAB builds from ignored/local signing configuration.
- [ ] Two ARM Android devices complete the real 1:1 flow.
- [ ] Fresh-install permission flow is tested.
- [ ] Invalid/blank meeting ID is rejected without calling the backend.

## Security and repository hygiene

- [ ] No API key is present in committed source.
- [ ] No JoinToken or attendee credentials are logged or persisted.
- [ ] `docs/reference/` is excluded from Git because the supplied Postman collection contains a credential.
- [ ] `artifacts/`, IDE files, build output, and local AI/tool memory are not committed.
- [ ] `git diff --check` reports no whitespace errors before submission.
- [ ] Application ID ownership, version code, target API, ARM64 libraries, Data safety, privacy policy, and Play listing are reviewed in Play Console.

## Deliverables

- [ ] Git repository contains the Flutter source and README.
- [ ] README remains concise and includes setup, state-management choice, architecture, assumptions, and known limitations.
- [ ] Android APK is attached separately.
- [ ] Play submissions use the signed AAB and Play App Signing; APKs are for direct QA only.
- [ ] Demo video is under 5 minutes and demonstrates the running app.
