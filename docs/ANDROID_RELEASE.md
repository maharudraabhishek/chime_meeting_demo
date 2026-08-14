# Android release readiness

## Signing

Release signing is optional for local static validation and mandatory for a
distributable APK/AAB. Keep the keystore and `android/key.properties` outside
source control. The Gradle script reads these property names only when the file
exists:

```properties
storeFile=<path-to-keystore>
storePassword=<local-secret>
keyAlias=<local-alias>
keyPassword=<local-secret>
```

Never paste property values into logs, documentation, chat, CI output, Gradle
source, or Dart defines. Prefer a secure CI secret store for automated releases.

Build the Play artifact with:

```powershell
flutter build appbundle --release `
  --dart-define=MEETING_API_BASE_URL=https://<worker>.workers.dev/
```

An unsigned build is not a releasable artifact. Confirm the final AAB signature
and enroll the app in Play App Signing before upload.

## Repository readiness

- Application ID remains `com.example.chimemeeting`; confirm ownership and Play
  Console uniqueness before first publication. This task intentionally does not
  rename it.
- Increment `version` in `pubspec.yaml` for every release; both version name and
  version code flow into Android Gradle configuration.
- Compile/target SDK values follow the installed Flutter toolchain. This cleanup
  resolved target API 36; confirm it still meets policy on the upload date.
- The manifest explicitly requires camera and microphone hardware, declares the
  matching permissions, disables cleartext traffic, and disables Android backup.
- Chime native media supports ARMv7 and ARM64. Inspect the final bundle in Play
  Console/App Bundle Explorer and confirm required 64-bit libraries are present.
- Upload an AAB rather than a universal APK for Play distribution.

## Operator/Play Console checks

These cannot be proven by static repository validation:

- final signing key custody and recovery plan;
- Play App Signing enrollment and signed AAB acceptance;
- current target API policy compliance;
- privacy policy, Data safety form, camera/microphone disclosure, content rating,
  launcher/store icon, store listing, screenshots, support contact, and regional
  declarations;
- pre-launch report results and supported-device filtering;
- two-device ARM meeting, reconnect, background/foreground, and permission QA.

Google Play requirements change independently of this repository. Re-check the
official Android/Play documentation immediately before submission.

## Official references

- [Target API level requirements](https://developer.android.com/google/play/requirements/target-sdk)
- [64-bit architecture requirements](https://developer.android.com/google/play/requirements/64-bit)
- [Android App Bundle format](https://developer.android.com/guide/app-bundle/app-bundle-format)
- [Upload a signed app bundle](https://developer.android.com/studio/publish/upload-bundle)
