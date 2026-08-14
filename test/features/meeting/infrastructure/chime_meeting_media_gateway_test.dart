import 'package:chime_meeting/features/meeting/domain/entities/meeting_failure.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_media_event.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_result.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_status.dart';
import 'package:chime_meeting/features/meeting/infrastructure/chime/chime_meeting_media_gateway.dart';
import 'package:chime_meeting/features/meeting/infrastructure/chime/chime_platform_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/meeting_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('test.gateway/methods');
  const eventChannel = EventChannel('test.gateway/events');
  const eventControlChannel = MethodChannel('test.gateway/events');
  late List<MethodCall> calls;
  late ChimeMeetingMediaGateway gateway;
  PlatformException? commandFailure;

  setUp(() async {
    calls = <MethodCall>[];
    commandFailure = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          calls.add(call);
          if (commandFailure != null) {
            throw commandFailure!;
          }
          return switch (call.method) {
            ChimePlatformBridge.setMicrophoneEnabledMethod ||
            ChimePlatformBridge.setCameraEnabledMethod =>
              (call.arguments as Map<Object?, Object?>)['enabled'],
            _ => null,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventControlChannel, (_) async => null);
    gateway = ChimeMeetingMediaGateway(
      bridge: ChimePlatformBridge(
        methodChannel: methodChannel,
        eventChannel: eventChannel,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    await gateway.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventControlChannel, null);
  });

  test(
    'accepts a complete bootstrap but stays joining until SDK event',
    () async {
      final result = await gateway.start(meetingBootstrap());

      expect(
        result,
        const MeetingSuccess<MeetingStatus>(MeetingStatus.joining),
      );
      expect(calls.single.method, ChimePlatformBridge.startSessionMethod);
    },
  );

  test(
    'rejects missing placement without crossing the platform bridge',
    () async {
      final result = await gateway.start(
        meetingBootstrapWithoutMediaPlacement(),
      );

      expect(
        result,
        const MeetingError<MeetingStatus>(
          MeetingFailure(MeetingFailureType.missingMediaConfiguration),
        ),
      );
      expect(calls, isEmpty);
    },
  );

  test('maps platform command failures to typed media failures', () async {
    commandFailure = PlatformException(code: 'permission_unavailable');

    final startResult = await gateway.start(meetingBootstrap());

    expect(
      startResult,
      const MeetingError<MeetingStatus>(
        MeetingFailure(MeetingFailureType.permissionUnavailable),
      ),
    );
  });

  test('maps unsupported runtime to the typed domain failure', () async {
    commandFailure = PlatformException(code: 'unsupported_runtime');

    final startResult = await gateway.start(meetingBootstrap());

    expect(
      startResult,
      const MeetingError<MeetingStatus>(
        MeetingFailure(MeetingFailureType.unsupportedRuntime),
      ),
    );
  });

  test('maps confirmed microphone, camera, and leave commands', () async {
    expect(
      await gateway.setMicrophoneEnabled(false),
      const MeetingSuccess<bool>(false),
    );
    expect(
      await gateway.setCameraEnabled(true),
      const MeetingSuccess<bool>(true),
    );
    expect(
      await gateway.leave(),
      const MeetingSuccess<MeetingStatus>(MeetingStatus.disconnected),
    );
  });

  test('forwards mapped events and ignores unknown native events', () async {
    final eventFuture = gateway.events.first;

    await _emitNativeEvent(eventChannel.name, <String, Object?>{
      'type': 'futureSdkEvent',
      'timestampMs': 1,
      'payload': const <String, Object?>{},
    });
    await _emitNativeEvent(eventChannel.name, <String, Object?>{
      'type': 'remoteVideoAvailable',
      'timestampMs': 1700000000000,
      'payload': const <String, Object?>{},
    });

    expect(
      await eventFuture,
      MeetingMediaEvent(
        type: MeetingMediaEventType.remoteVideoAvailable,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      ),
    );
  });

  test(
    'dispose is idempotent, closes events, and rejects later work',
    () async {
      final done = expectLater(gateway.events, emitsDone);

      await gateway.dispose();
      await gateway.dispose();
      await done;

      expect(
        calls
            .where(
              (call) => call.method == ChimePlatformBridge.disposeSessionMethod,
            )
            .length,
        1,
      );
      expect(
        await gateway.start(meetingBootstrap()),
        const MeetingError<MeetingStatus>(
          MeetingFailure(MeetingFailureType.platformBridge),
        ),
      );
    },
  );
}

Future<void> _emitNativeEvent(String channel, Object? event) async {
  final ByteData data = const StandardMethodCodec().encodeSuccessEnvelope(
    event,
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channel, data, (_) {});
}
