import 'package:chime_meeting/features/meeting/domain/entities/meeting_failure.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_media_event.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_result.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_status.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_video_role.dart';
import 'package:chime_meeting/features/meeting/infrastructure/web/chime_web_bridge_client.dart';
import 'package:chime_meeting/features/meeting/infrastructure/web/web_meeting_media_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/meeting_fixtures.dart';

void main() {
  test('reports unavailable bridge before exposing bootstrap data', () async {
    final bridge = _FakeWebBridge()..isAvailable = false;
    final gateway = WebMeetingMediaGateway(bridge: bridge);
    addTearDown(gateway.dispose);

    final result = await gateway.start(meetingBootstrap());

    expect(
      (result as MeetingError<MeetingStatus>).failure.type,
      MeetingFailureType.bridgeUnavailable,
    );
    expect(bridge.startRequests, isEmpty);
  });

  test('validates required media placement before calling bridge', () async {
    final bridge = _FakeWebBridge();
    final gateway = WebMeetingMediaGateway(bridge: bridge);
    addTearDown(gateway.dispose);

    final result = await gateway.start(meetingBootstrapWithoutMediaPlacement());

    expect(
      (result as MeetingError<MeetingStatus>).failure.type,
      MeetingFailureType.missingMediaConfiguration,
    );
    expect(bridge.startRequests, isEmpty);
  });

  test('filters stale generations and forwards current generation', () async {
    final bridge = _FakeWebBridge();
    final gateway = WebMeetingMediaGateway(bridge: bridge);
    addTearDown(gateway.dispose);
    final events = <MeetingMediaEvent>[];
    final subscription = gateway.events.listen(events.add);
    addTearDown(subscription.cancel);

    expect(
      await gateway.start(meetingBootstrap()),
      const MeetingSuccess<MeetingStatus>(MeetingStatus.joining),
    );
    bridge.emit('sessionStarted', generation: 1);
    await Future<void>.delayed(Duration.zero);
    expect(events.map((event) => event.type), <MeetingMediaEventType>[
      MeetingMediaEventType.sessionStarted,
    ]);

    await gateway.start(meetingBootstrap());
    bridge.emit('sessionError', generation: 1);
    bridge.emit('sessionReconnecting', generation: 2);
    await Future<void>.delayed(Duration.zero);

    expect(events.map((event) => event.type), <MeetingMediaEventType>[
      MeetingMediaEventType.sessionStarted,
      MeetingMediaEventType.reconnecting,
    ]);
    expect(bridge.stoppedGenerations, contains(1));
  });

  test(
    'coordinates element-first attachment and replacement-safe detach',
    () async {
      final bridge = _FakeWebBridge();
      final gateway = WebMeetingMediaGateway(bridge: bridge);
      addTearDown(gateway.dispose);

      await gateway.attachVideoSurface(MeetingVideoRole.remote, 'remote-old');
      await gateway.start(meetingBootstrap());
      expect(bridge.remoteAttachments, <String>['1:remote-old']);

      await gateway.attachVideoSurface(MeetingVideoRole.remote, 'remote-new');
      await gateway.detachVideoSurface(MeetingVideoRole.remote, 'remote-old');
      expect(bridge.detachedRoles, isEmpty);

      await gateway.detachVideoSurface(MeetingVideoRole.remote, 'remote-new');
      expect(bridge.detachedRoles, <String>['1:remote']);
    },
  );

  test('uses Chime-confirmed mute result and camera commands', () async {
    final bridge = _FakeWebBridge()..unmuteResult = false;
    final gateway = WebMeetingMediaGateway(bridge: bridge);
    addTearDown(gateway.dispose);
    await gateway.start(meetingBootstrap());

    final unmute = await gateway.setMicrophoneEnabled(true);
    expect((unmute as MeetingSuccess<bool>).value, isFalse);

    final mute = await gateway.setMicrophoneEnabled(false);
    expect((mute as MeetingSuccess<bool>).value, isFalse);

    expect(
      await gateway.setCameraEnabled(false),
      const MeetingSuccess<bool>(false),
    );
    expect(bridge.stoppedVideoGenerations, <int>[1]);
  });

  test('dispose is idempotent and prevents later callbacks', () async {
    final bridge = _FakeWebBridge();
    final gateway = WebMeetingMediaGateway(bridge: bridge);
    await gateway.start(meetingBootstrap());
    await gateway.dispose();
    await gateway.dispose();

    expect(bridge.disposeCalls, 1);
    expect(bridge.handler, isNull);
  });
}

final class _FakeWebBridge implements ChimeWebBridgeClient {
  @override
  bool isAvailable = true;

  @override
  bool isSupported = true;

  bool unmuteResult = true;
  bool muteResult = false;
  void Function(WebBridgeEventData event)? handler;
  final List<WebStartSessionRequest> startRequests = <WebStartSessionRequest>[];
  final List<int> stoppedGenerations = <int>[];
  final List<int> stoppedVideoGenerations = <int>[];
  final List<String> remoteAttachments = <String>[];
  final List<String> detachedRoles = <String>[];
  int disposeCalls = 0;

  void emit(String type, {required int generation}) {
    handler?.call(WebBridgeEventData(type: type, generation: generation));
  }

  @override
  void setEventHandler(void Function(WebBridgeEventData event)? handler) {
    this.handler = handler;
  }

  @override
  Future<void> startSession(WebStartSessionRequest request) async {
    startRequests.add(request);
  }

  @override
  Future<void> stopSession(int generation) async {
    stoppedGenerations.add(generation);
  }

  @override
  Future<bool> muteLocalAudio(int generation) async => muteResult;

  @override
  Future<bool> unmuteLocalAudio(int generation) async => unmuteResult;

  @override
  Future<void> startLocalVideo(int generation) async {}

  @override
  Future<void> stopLocalVideo(int generation) async {
    stoppedVideoGenerations.add(generation);
  }

  @override
  Future<bool> switchCamera(int generation) async => true;

  @override
  void attachLocalVideoElement(int generation, String elementId) {}

  @override
  void attachRemoteVideoElement(int generation, String elementId) {
    remoteAttachments.add('$generation:$elementId');
  }

  @override
  void detachVideoElement(int generation, String role) {
    detachedRoles.add('$generation:$role');
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}
