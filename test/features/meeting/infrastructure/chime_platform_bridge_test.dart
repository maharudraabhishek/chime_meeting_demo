import 'package:chime_meeting/features/meeting/infrastructure/chime/chime_platform_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/meeting_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('test.chime/methods');
  late ChimePlatformBridge bridge;
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    bridge = ChimePlatformBridge(methodChannel: methodChannel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          calls.add(call);
          return switch (call.method) {
            ChimePlatformBridge.setMicrophoneEnabledMethod ||
            ChimePlatformBridge.setCameraEnabledMethod =>
              (call.arguments as Map<Object?, Object?>)['enabled'],
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test(
    'serializes only the Chime session fields required by Android',
    () async {
      await bridge.startSession(meetingBootstrap());

      expect(calls, hasLength(1));
      expect(calls.single.method, ChimePlatformBridge.startSessionMethod);
      expect(calls.single.arguments, <String, Object>{
        'meetingId': fixtureMeetingId,
        'attendeeId': 'attendee-123',
        'externalUserId': 'client',
        'joinToken': 'test-token-not-a-real-credential',
        'audioHostUrl': 'audio.example.test',
        'audioFallbackUrl': 'wss://fallback.example.test',
        'signalingUrl': 'wss://signal.example.test',
        'turnControlUrl': 'https://turn.example.test',
        'eventIngestionUrl': 'https://events.example.test',
      });

      final arguments = calls.single.arguments! as Map<Object?, Object?>;
      expect(arguments, isNot(contains('screenDataUrl')));
      expect(arguments, isNot(contains('screenViewingUrl')));
      expect(arguments, isNot(contains('screenSharingUrl')));
    },
  );

  test('rejects missing media placement before invoking Android', () {
    expect(
      () => bridge.startSession(meetingBootstrapWithoutMediaPlacement()),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'missing_media_configuration',
        ),
      ),
    );
    expect(calls, isEmpty);
  });

  test(
    'uses centralized command names and confirmed boolean results',
    () async {
      expect(await bridge.setMicrophoneEnabled(false), isFalse);
      expect(await bridge.setCameraEnabled(true), isTrue);
      await bridge.leaveSession();
      await bridge.disposeSession();

      expect(calls.map((call) => call.method), <String>[
        ChimePlatformBridge.setMicrophoneEnabledMethod,
        ChimePlatformBridge.setCameraEnabledMethod,
        ChimePlatformBridge.leaveSessionMethod,
        ChimePlatformBridge.disposeSessionMethod,
      ]);
      expect(calls[0].arguments, <String, Object>{'enabled': false});
      expect(calls[1].arguments, <String, Object>{'enabled': true});
    },
  );

  test('rejects null microphone and camera confirmations', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (_) async => null);

    await expectLater(
      bridge.setMicrophoneEnabled(true),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'platform_bridge_failure',
        ),
      ),
    );
    await expectLater(
      bridge.setCameraEnabled(false),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'platform_bridge_failure',
        ),
      ),
    );
  });
}
